import Foundation

/// A user-adjusted crop, normalized 0...1 with a top-left origin, relative to
/// the original image.
///
/// Deliberately free of SwiftData: this type travels inside shared deck files,
/// which the Quick Look extension also has to read.
struct CropRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
