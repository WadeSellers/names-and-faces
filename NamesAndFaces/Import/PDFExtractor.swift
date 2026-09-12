import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
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

        // Sheets are uniform: the name sits in the same place relative to every
        // face on the page. Work out where that is instead of assuming "below".
        let placement = bestPlacement(faces: faces, lines: lines)

        // Pass 1: pair every detected face with its name.
        var entries: [Entry] = []
        var usedLineIndices = Set<Int>()
        var matchedGeometry: [(crop: CGRect, line: CGRect)] = []

        for face in faces {
            let (name, lineIndex) = nameNear(face: face, lines: lines, placement: placement)
            let crop = portraitCrop(for: face, width: width, height: height)
            entries.append(Entry(crop: crop, name: name))
            if let lineIndex {
                usedLineIndices.insert(lineIndex)
                matchedGeometry.append((crop, lines[lineIndex].rect))
            }
        }

        // Pass 2: a name-like line nobody claimed means the face detector missed
        // a portrait (glasses, hair, low contrast). Its photo sits at the same
        // offset from the name as every matched pair on this page, so synthesize
        // a crop there using the median geometry.
        if !matchedGeometry.isEmpty {
            let cropW = median(matchedGeometry.map(\.crop.width))
            let cropH = median(matchedGeometry.map(\.crop.height))
            let offsetX = median(matchedGeometry.map { $0.crop.minX - $0.line.minX })
            let offsetY = median(matchedGeometry.map { $0.crop.minY - $0.line.minY })

            for (lineIndex, line) in lines.enumerated() {
                guard !usedLineIndices.contains(lineIndex), looksLikeName(line.string) else { continue }

                let raw = CGRect(x: line.rect.minX + offsetX,
                                 y: line.rect.minY + offsetY,
                                 width: cropW,
                                 height: cropH)
                let crop = raw.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral

                // A crop that fell mostly off-page is a header, not a portrait.
                guard crop.width * crop.height > cropW * cropH * 0.6 else { continue }
                // Somebody already claimed that spot.
                let taken = entries.contains { entry in
                    let overlap = entry.crop.intersection(crop)
                    guard !overlap.isNull else { return false }
                    return overlap.width * overlap.height > cropW * cropH * 0.3
                }
                guard !taken else { continue }

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

    /// Where the printed name sits relative to its portrait on this page.
    private enum NamePlacement: CaseIterable {
        case below, above, right, left
    }

    /// Try each placement against every face and keep the one that explains the
    /// page best: most faces matched, then the tightest gap. Ties go to `below`,
    /// which is what cohort sheets and yearbooks use.
    private static func bestPlacement(faces: [CGRect], lines: [TextLine]) -> NamePlacement {
        guard !faces.isEmpty, !lines.isEmpty else { return .below }

        var best: (placement: NamePlacement, matches: Int, gap: CGFloat) = (.below, -1, .greatestFiniteMagnitude)

        for placement in NamePlacement.allCases {
            var gaps: [CGFloat] = []
            for face in faces {
                let (name, lineIndex) = nameNear(face: face, lines: lines, placement: placement)
                guard !name.isEmpty, let lineIndex else { continue }
                gaps.append(gap(from: face, to: lines[lineIndex].rect, placement: placement))
            }
            guard !gaps.isEmpty else { continue }
            let medianGap = median(gaps)
            let better = gaps.count > best.matches
                || (gaps.count == best.matches && medianGap < best.gap - 0.5)
            if better {
                best = (placement, gaps.count, medianGap)
            }
        }
        return best.matches > 0 ? best.placement : .below
    }

    private static func gap(from face: CGRect, to line: CGRect, placement: NamePlacement) -> CGFloat {
        switch placement {
        case .below: return line.minY - face.maxY
        case .above: return face.minY - line.maxY
        case .right: return line.minX - face.maxX
        case .left:  return face.minX - line.maxX
        }
    }

    /// The text line(s) sitting in `placement` relative to the face, aligned with it.
    private static func nameNear(face: CGRect, lines: [TextLine], placement: NamePlacement) -> (name: String, lineIndex: Int?) {
        let verticalReach = face.height * 3.5
        let horizontalReach = face.width * 4
        let slack = face.height * 0.1

        let candidates = lines.enumerated().filter { _, line in
            switch placement {
            case .below:
                let span = face.insetBy(dx: -face.width * 0.75, dy: 0)
                return line.rect.minY > face.maxY - slack
                    && line.rect.minY < face.maxY + verticalReach
                    && line.rect.midX > span.minX && line.rect.midX < span.maxX
            case .above:
                let span = face.insetBy(dx: -face.width * 0.75, dy: 0)
                return line.rect.maxY < face.minY + slack
                    && line.rect.maxY > face.minY - verticalReach
                    && line.rect.midX > span.minX && line.rect.midX < span.maxX
            case .right:
                return line.rect.minX > face.maxX - face.width * 0.1
                    && line.rect.minX < face.maxX + horizontalReach
                    && line.rect.midY > face.minY - face.height
                    && line.rect.midY < face.maxY + face.height
            case .left:
                return line.rect.maxX < face.minX + face.width * 0.1
                    && line.rect.maxX > face.minX - horizontalReach
                    && line.rect.midY > face.minY - face.height
                    && line.rect.midY < face.maxY + face.height
            }
        }

        // Nearest first, measured from the face edge the name sits against.
        let ordered = candidates.sorted {
            gap(from: face, to: $0.element.rect, placement: placement)
                < gap(from: face, to: $1.element.rect, placement: placement)
        }

        guard let (firstIndex, first) = ordered.first else { return ("", nil) }
        var name = first.string

        // A name split across two stacked lines ("Jane" / "Doe"). Only a
        // single-word first line can be half a name — anything longer already
        // reads as a whole name, and the line under it is a job title.
        if placement == .below || placement == .above,
           first.string.split(separator: " ").count == 1,
           let (_, second) = ordered.dropFirst().first,
           abs(second.rect.minY - first.rect.maxY) < first.rect.height * 0.9 {
            name = placement == .below ? name + " " + second.string : second.string + " " + name
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
