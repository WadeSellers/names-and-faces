import Foundation
import ImageIO
import UIKit

/// A deck packed into one blob — what a share code stores on the server and
/// what the receiving phone unpacks.
///
/// Binary property list rather than JSON: plists store `Data` natively, where
/// JSON would base64 every portrait and inflate the file by a third.
struct DeckFile: Codable {
    /// Bumped when the shape changes. A reader refuses versions it predates.
    static let currentVersion = 1

    var formatVersion: Int
    var deckName: String
    var exportedAt: Date
    /// Recorded for support questions, never branched on.
    var appVersion: String
    var note: String?
    var people: [PersonFile]

    struct PersonFile: Codable {
        var name: String
        /// The cropped portrait — what every screen shows.
        var imageData: Data
        /// Only carried when this person has a crop, so the recipient can
        /// re-crop them. With no crop the original *is* the display image,
        /// and shipping it twice would double the file for nothing.
        var originalImageData: Data?
        var crop: CropRegion?
    }
}

// MARK: - Limits

extension DeckFile {
    /// A deck file arrives from outside the app, so it is read defensively.
    enum Limits {
        static let maxPeople = 2_000
        static let maxImageBytes = 10 * 1024 * 1024
        static let maxNameLength = 200
        static let maxFileBytes = 200 * 1024 * 1024
    }

    enum ReadError: LocalizedError {
        case tooLarge
        case unreadable
        case fromANewerApp(version: Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "That deck is too large to open."
            case .unreadable:
                return "That deck was damaged on the way here. Ask for a new code."
            case .fromANewerApp:
                return "That deck was made with a newer version of Name That Face. Update the app to open it."
            case .empty:
                return "That deck arrived with no faces in it."
            }
        }
    }
}

// MARK: - Writing

extension DeckFile {
    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }
}

// MARK: - Reading

extension DeckFile {
    /// Unpacks a deck fetched by code. Every failure is an error to show, never
    /// a crash and never a partial import — the bytes came from the network.
    static func read(from data: Data) throws -> DeckFile {
        guard data.count <= Limits.maxFileBytes else { throw ReadError.tooLarge }

        var file: DeckFile
        do {
            file = try PropertyListDecoder().decode(DeckFile.self, from: data)
        } catch {
            throw ReadError.unreadable
        }

        guard file.formatVersion <= currentVersion else {
            throw ReadError.fromANewerApp(version: file.formatVersion)
        }

        file.deckName = sanitized(name: file.deckName, fallback: "Imported Deck")
        file.note = file.note.map { String($0.prefix(Limits.maxNameLength)) }

        // Drop what can't be trusted rather than refusing the whole deck: one
        // bad portrait in a cohort of 23 shouldn't cost the other 22.
        file.people = file.people
            .prefix(Limits.maxPeople)
            .filter { $0.imageData.count <= Limits.maxImageBytes && isReadableImage($0.imageData) }
            .map { person in
                var person = person
                person.name = sanitized(name: person.name, fallback: "Unknown")
                if let original = person.originalImageData,
                   original.count > Limits.maxImageBytes || !isReadableImage(original) {
                    person.originalImageData = nil
                    person.crop = nil
                }
                return person
            }

        guard !file.people.isEmpty else { throw ReadError.empty }
        return file
    }

    /// True when the bytes really are an image, established from the header
    /// alone. Decoding every portrait just to check it would cost megabytes
    /// each — survivable in the app, fatal inside an extension.
    private static func isReadableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return false }
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && height > 0
    }

    private static func sanitized(name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return String(trimmed.prefix(Limits.maxNameLength))
    }
}

