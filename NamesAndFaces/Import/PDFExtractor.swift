import Foundation
import PDFKit
import UIKit
import Vision

/// A face + name pair pulled out of the PDF, awaiting user review.
struct ExtractedCandidate: Identifiable {
    let id = UUID()
    /// Displayed (and saved) portrait — reflects any user crop.
    var image: UIImage
    /// The untouched extraction, kept so crops stay re-editable.
    let original: UIImage
    var name: String
    var crop: CropRegion?
    var include: Bool = true
}

enum PDFExtractorError: LocalizedError {
    case cannotOpen

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "That PDF couldn't be opened."
        }
    }
}

/// Renders each PDF page, detects faces and printed text on-device with Vision,
/// and pairs every face with the name printed beneath it. Tuned against real
/// Playhouse cohort sheets (grids of headshots, name on one line below each photo).
struct PDFExtractor {
    private struct TextLine {
        let string: String
        let rect: CGRect
    }

    private struct Entry {
        let crop: CGRect
        let name: String
    }

    static func extract(from url: URL, progress: @escaping (Int, Int) -> Void) throws -> [ExtractedCandidate] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            throw PDFExtractorError.cannotOpen
        }

        var results: [ExtractedCandidate] = []
        for pageIndex in 0..<document.pageCount {
            progress(pageIndex + 1, document.pageCount)
            guard let page = document.page(at: pageIndex) else { continue }
            guard let cgImage = render(page).cgImage else { continue }
            results.append(contentsOf: try extractPeople(from: cgImage))
        }
        return results
    }

    private static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(4, max(2, 3000 / max(bounds.width, 1)))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    private static func extractPeople(from cgImage: CGImage) throws -> [ExtractedCandidate] {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        // Names aren't dictionary words; correction turns them into ones.
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([faceRequest, textRequest])

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Vision rects are normalized with a bottom-left origin; convert to
        // top-left pixel coordinates so "below the face" means larger y.
        func pixelRect(_ normalized: CGRect) -> CGRect {
            CGRect(x: normalized.minX * width,
                   y: (1 - normalized.maxY) * height,
                   width: normalized.width * width,
                   height: normalized.height * height)
        }

        let faces = (faceRequest.results ?? [])
            .map { pixelRect($0.boundingBox) }
            .filter { $0.width > 40 }

        let lines: [TextLine] = (textRequest.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !string.isEmpty,
                  !string.contains("@"),
                  string.rangeOfCharacter(from: .letters) != nil else { return nil }
            return TextLine(string: string, rect: pixelRect(observation.boundingBox))
        }

        // Pass 1: pair every detected face with the name below it.
        var entries: [Entry] = []
        var usedLineIndices = Set<Int>()
        var matchedGeometry: [(crop: CGRect, line: CGRect)] = []

        for face in faces {
            let (name, lineIndex) = nameBelow(face: face, lines: lines)
            let crop = portraitCrop(for: face, width: width, height: height)
            entries.append(Entry(crop: crop, name: name))
            if let lineIndex {
                usedLineIndices.insert(lineIndex)
                matchedGeometry.append((crop, lines[lineIndex].rect))
            }
        }

        // Pass 2: a name-like line nobody claimed means the face detector missed
        // a portrait (glasses, hair, low contrast). The photo sits directly above
        // its name on these sheets, so synthesize a crop there using the median
        // geometry of the matched pairs.
        if !matchedGeometry.isEmpty {
            let cropW = median(matchedGeometry.map(\.crop.width))
            let cropH = median(matchedGeometry.map(\.crop.height))
            let dx = median(matchedGeometry.map { $0.line.minX - $0.crop.minX })
            let dy = median(matchedGeometry.map { $0.line.minY - $0.crop.maxY })

            for (lineIndex, line) in lines.enumerated() {
                guard !usedLineIndices.contains(lineIndex), looksLikeName(line.string) else { continue }

                let faceAbove = faces.contains { face in
                    face.maxY < line.rect.minY &&
                    line.rect.minY - face.maxY < face.height * 4 &&
                    abs(face.midX - line.rect.midX) < cropW
                }
                guard !faceAbove else { continue }

                let raw = CGRect(x: line.rect.minX - dx,
                                 y: line.rect.minY - dy - cropH,
                                 width: cropW,
                                 height: cropH)
                let crop = raw.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
                // A crop that fell mostly off-page is a header, not a portrait.
                guard crop.width * crop.height > cropW * cropH * 0.6 else { continue }
                entries.append(Entry(crop: crop, name: line.string))
            }
        }

        // Reading order: row buckets, then left to right.
        let rowHeight = (entries.map(\.crop.height).max() ?? 100) * 1.3
        entries.sort { a, b in
            let rowA = Int(a.crop.midY / rowHeight)
            let rowB = Int(b.crop.midY / rowHeight)
            return rowA == rowB ? a.crop.minX < b.crop.minX : rowA < rowB
        }

        return entries.map { entry in
            let image = cgImage.cropping(to: entry.crop).map { UIImage(cgImage: $0) }
                ?? UIImage(cgImage: cgImage)
            return ExtractedCandidate(image: image, original: image, name: entry.name)
        }
    }

    /// The name is the text line(s) directly under the face, horizontally aligned with it.
    private static func nameBelow(face: CGRect, lines: [TextLine]) -> (name: String, lineIndex: Int?) {
        let horizontalSpan = face.insetBy(dx: -face.width * 0.75, dy: 0)
        let below = lines.enumerated()
            .filter { _, line in
                line.rect.minY > face.maxY - face.height * 0.1 &&
                line.rect.minY < face.maxY + face.height * 3.5 &&
                line.rect.midX > horizontalSpan.minX &&
                line.rect.midX < horizontalSpan.maxX
            }
            .sorted { $0.element.rect.minY < $1.element.rect.minY }

        guard let (firstIndex, first) = below.first else { return ("", nil) }
        var name = first.string
        // A name split across two tightly stacked lines ("Jane" / "Doe").
        if let (_, second) = below.dropFirst().first,
           second.rect.minY - first.rect.maxY < first.rect.height * 0.9 {
            name += " " + second.string
        }
        return (name, firstIndex)
    }

    /// Expand the detected face rect to a portrait-style crop (hair, chin, shoulders).
    private static func portraitCrop(for face: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        let padX = face.width * 0.55
        let padTop = face.height * 0.75
        let padBottom = face.height * 0.6
        let rect = CGRect(x: face.minX - padX,
                          y: face.minY - padTop,
                          width: face.width + padX * 2,
                          height: face.height + padTop + padBottom)
        return rect.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
    }

    private static func looksLikeName(_ string: String) -> Bool {
        guard string.count <= 40,
              string.rangeOfCharacter(from: .decimalDigits) == nil,
              let first = string.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) else { return false }
        let words = string.split(separator: " ")
        return words.count >= 2 && words.count <= 5
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
