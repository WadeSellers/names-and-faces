import Foundation
import SwiftData
import UIKit

/// A deck written out as a single file, so it can be handed to someone over
/// AirDrop, Messages, Mail, Files — anything that moves a file. There is no
/// server on either end, so a shared deck never expires.
///
/// Binary property list rather than JSON: plists store `Data` natively, where
/// JSON would base64 every portrait and inflate the file by a third.
struct DeckFile: Codable {
    /// Bumped when the shape changes. A reader refuses versions it predates.
    static let currentVersion = 1

    /// Extension and type identifier, declared in Info.plist.
    static let fileExtension = "ntfdeck"

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
                return "That deck file is too large to open."
            case .unreadable:
                return "That file isn't a deck, or it was damaged on the way here."
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
    init(deck: Deck, note: String? = nil) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        self.formatVersion = DeckFile.currentVersion
        self.deckName = deck.name
        self.exportedAt = .now
        self.appVersion = "\(version) (\(build))"
        self.note = note
        self.people = deck.people
            .sorted { $0.createdAt < $1.createdAt }
            .map { person in
                PersonFile(
                    name: person.name,
                    imageData: person.imageData,
                    // Redundant unless the portrait was actually cropped.
                    originalImageData: person.crop == nil ? nil : person.originalImageData,
                    crop: person.crop
                )
            }
        // Progress is deliberately absent. What you have in rotation and how
        // well you know it is yours, not a property of the deck.
    }

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// Writes the deck to a temporary file named after the deck, ready to hand
    /// to a share sheet. The caller deletes it when the sheet goes away.
    func writeToTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-decks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory
            .appendingPathComponent(DeckFile.safeFileName(for: deckName))
            .appendingPathExtension(DeckFile.fileExtension)

        try encoded().write(to: url, options: .atomic)
        return url
    }

    /// Keeps the deck's own name on the file where it can, without letting a
    /// deck name become a path.
    static func safeFileName(for name: String) -> String {
        var cleaned = name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 60 { cleaned = String(cleaned.prefix(60)) }
        return cleaned.isEmpty ? "Deck" : cleaned
    }
}

// MARK: - Reading

extension DeckFile {
    /// Reads a deck file from disk. Every failure is an error to show, never a
    /// crash and never a partial import.
    static func read(from url: URL) throws -> DeckFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Limits.maxFileBytes else { throw ReadError.tooLarge }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ReadError.unreadable
        }

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
            .filter { $0.imageData.count <= Limits.maxImageBytes && UIImage(data: $0.imageData) != nil }
            .map { person in
                var person = person
                person.name = sanitized(name: person.name, fallback: "Unknown")
                if let original = person.originalImageData,
                   original.count > Limits.maxImageBytes || UIImage(data: original) == nil {
                    person.originalImageData = nil
                    person.crop = nil
                }
                return person
            }

        guard !file.people.isEmpty else { throw ReadError.empty }
        return file
    }

    private static func sanitized(name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return String(trimmed.prefix(Limits.maxNameLength))
    }
}

// MARK: - Importing

extension DeckFile {
    /// Inserts the deck. Progress starts at zero for the new owner, and a name
    /// already in use gets a number rather than merging into someone else's deck.
    @discardableResult
    func insert(into context: ModelContext, existingNames: [String]) -> Deck {
        let deck = Deck(name: DeckFile.uniqueName(from: deckName, taken: existingNames))
        context.insert(deck)

        for person in people {
            let model = Person(name: person.name, imageData: person.imageData)
            model.originalImageData = person.originalImageData
            model.crop = person.crop
            context.insert(model)
            model.deck = deck
        }
        return deck
    }

    static func uniqueName(from name: String, taken: [String]) -> String {
        guard taken.contains(name) else { return name }
        var counter = 2
        while taken.contains("\(name) (\(counter))") { counter += 1 }
        return "\(name) (\(counter))"
    }
}
