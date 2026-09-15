import Foundation
import SwiftData

@Model
final class Deck {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Person.deck)
    var people: [Person] = []

    /// The 6-digit code this deck is currently shared under, if any.
    var shareCode: String?
    /// Proves this phone shared it, so only this phone can stop sharing.
    var shareOwnerToken: String?
    var shareExpiresAt: Date?

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

extension Deck {
    /// A code that hasn't expired on the server yet.
    var activeShareCode: String? {
        guard let shareCode, let shareExpiresAt, shareExpiresAt > .now else { return nil }
        return shareCode
    }

    /// 0...1 — average Leitner box across the deck.
    var mastery: Double {
        guard !people.isEmpty else { return 0 }
        let total = people.reduce(0) { $0 + $1.box }
        return Double(total) / Double(people.count * Person.maxBox)
    }
}

@Model
final class Person {
    static let maxBox = 4

    var name: String
    /// What every screen displays — already cropped if a crop is set.
    @Attribute(.externalStorage) var imageData: Data
    /// The uncropped source, kept so crops are non-destructive and re-editable.
    @Attribute(.externalStorage) var originalImageData: Data?
    var crop: CropRegion?
    var deck: Deck?

    /// Leitner box 0 (unknown) ... 4 (mastered). Drives study ordering.
    var box: Int
    var timesCorrect: Int
    var timesMissed: Int
    var lastReviewedAt: Date?
    /// When this face joined the study rotation; nil = still waiting to be added.
    var introducedAt: Date?
    var createdAt: Date

    init(name: String, imageData: Data, createdAt: Date = .now) {
        self.name = name
        self.imageData = imageData
        self.box = 0
        self.timesCorrect = 0
        self.timesMissed = 0
        self.createdAt = createdAt
    }
}

extension Person {
    var mastery: Double { Double(box) / Double(Person.maxBox) }

    func resetProgress() {
        box = 0
        timesCorrect = 0
        timesMissed = 0
        lastReviewedAt = nil
        introducedAt = nil
    }
}
