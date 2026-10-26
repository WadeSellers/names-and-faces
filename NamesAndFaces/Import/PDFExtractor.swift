import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Vision

/// A face + name pair pulled out of a PDF or photo, awaiting user review.
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

/// Detects faces and printed text on-device with Vision and pairs every face
/// with its printed name. A PDF is rendered page by page; a photo or screenshot
/// goes in as it is. Both end up in `extractPeople(from:)`. Tuned against real
/// Playhouse cohort sheets (grids of headshots, name on one line below each photo).
struct PDFExtractor {
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

    /// Screenshots of a staff page, a Zoom gallery, a photo of a printed sheet:
    /// each image is one "page".
    static func extract(from images: [UIImage], progress: @escaping (Int, Int) -> Void) throws -> [ExtractedCandidate] {
        var results: [ExtractedCandidate] = []
        for (index, image) in images.enumerated() {
            progress(index + 1, images.count)
            guard let cgImage = image.cgImage else { continue }
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

    /// One rendered page or one photo, in its upright orientation.
    static func extractPeople(from cgImage: CGImage) throws -> [ExtractedCandidate] {
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

        // Drops specks the detector calls faces: 40 px on a letter page rendered
        // at 4x (2448 px wide). A 1206 px phone screenshot shows the same sheet
        // at half that, so the floor scales down with it, but never above 40.
        let minFaceWidth = min(40, width * 40 / 2448)
        let faces = (faceRequest.results ?? [])
            .map { pixelRect($0.boundingBox) }
            .filter { $0.width > minFaceWidth }

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
        let placement = NamePlacement.best(faces: faces, lines: lines)

        // Pass 1: pair every detected face with its name.
        var entries: [Entry] = []
        var usedLineIndices = Set<Int>()
        var matchedGeometry: [(crop: CGRect, line: CGRect)] = []

        for face in faces {
            let (name, lineIndex) = placement.name(near: face, lines: lines)
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
            let cropW = NamePlacement.median(matchedGeometry.map(\.crop.width))
            let cropH = NamePlacement.median(matchedGeometry.map(\.crop.height))
            let offsetX = NamePlacement.median(matchedGeometry.map { $0.crop.minX - $0.line.minX })
            let offsetY = NamePlacement.median(matchedGeometry.map { $0.crop.minY - $0.line.minY })

            for (lineIndex, line) in lines.enumerated() {
                guard !usedLineIndices.contains(lineIndex), NamePlacement.looksLikeName(line.string) else { continue }

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
}
