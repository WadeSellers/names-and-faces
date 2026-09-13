import Foundation
import SwiftData

/// The half of deck files that touches the SwiftData models. Kept apart from
/// `DeckFile` itself so the Quick Look extension can read a deck without
/// linking the app's data layer.
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
