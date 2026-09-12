import AppKit
import CoreGraphics

// Minimal UIKit shim so the SHIPPING PDFExtractor.swift compiles unmodified on macOS.
typealias UIImage = NSImage

extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}

struct CropRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
