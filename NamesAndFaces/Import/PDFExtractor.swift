import Foundation
import PDFKit
import UIKit
import Vision

/// A face + name pair pulled out of the PDF, awaiting user review.
struct ExtractedCandidate: Identifiable {
    let id = UUID()
    var image: UIImage
    var name: String
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
/// and pairs every face with the name printed beneath it.
struct PDFExtractor {
    private struct TextLine {
        let string: String
        let rect: CGRect
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
        let scale = min(4, max(2, 2200 / max(bounds.width, 1)))
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

        var faces = (faceRequest.results ?? [])
            .map { pixelRect($0.boundingBox) }
            .filter { $0.width > 40 }

        // Reading order: bucket into rows, then left to right.
        let rowHeight = (faces.map(\.height).max() ?? 100) * 1.3
        faces.sort { a, b in
            let rowA = Int(a.midY / rowHeight)
            let rowB = Int(b.midY / rowHeight)
            return rowA == rowB ? a.minX < b.minX : rowA < rowB
        }

        let lines: [TextLine] = (textRequest.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !string.isEmpty,
                  !string.contains("@"),
                  string.rangeOfCharacter(from: .letters) != nil else { return nil }
            return TextLine(string: string, rect: pixelRect(observation.boundingBox))
        }

        return faces.map { face in
            let crop = portraitCrop(for: face, width: width, height: height)
            let image = cgImage.cropping(to: crop).map { UIImage(cgImage: $0) }
                ?? UIImage(cgImage: cgImage)
            return ExtractedCandidate(image: image, name: nameBelow(face: face, lines: lines))
        }
    }

    /// The name is the text line(s) directly under the face, horizontally aligned with it.
    private static func nameBelow(face: CGRect, lines: [TextLine]) -> String {
        let horizontalSpan = face.insetBy(dx: -face.width * 0.75, dy: 0)
        let below = lines
            .filter { line in
                line.rect.minY > face.maxY - face.height * 0.1 &&
                line.rect.minY < face.maxY + face.height * 2.2 &&
                line.rect.midX > horizontalSpan.minX &&
                line.rect.midX < horizontalSpan.maxX
            }
            .sorted { $0.rect.minY < $1.rect.minY }

        guard let first = below.first else { return "" }
        var name = first.string
        // A name split across two tightly stacked lines ("Jane" / "Doe").
        if let second = below.dropFirst().first,
           second.rect.minY - first.rect.maxY < first.rect.height * 0.9 {
            name += " " + second.string
        }
        return name
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
