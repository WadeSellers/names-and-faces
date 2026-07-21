import Foundation
import SwiftData
import UIKit

/// Seeds the bundled "US Presidents" demo deck on first launch, so the app
/// has faces to study before the first cohort PDF ever arrives. Runs once:
/// deleting the deck is respected and it never comes back on its own.
enum PresidentsDemoDeck {
    private static let seededDefaultsKey = "didSeedPresidentsDemoDeck"
    static let deckName = "US Presidents"

    /// Asset name in `Assets.xcassets/Presidents` and display name,
    /// in order of first term.
    private static let presidents: [(asset: String, name: String)] = [
        ("01-george-washington", "George Washington"),
        ("02-john-adams", "John Adams"),
        ("03-thomas-jefferson", "Thomas Jefferson"),
        ("04-james-madison", "James Madison"),
        ("05-james-monroe", "James Monroe"),
        ("06-john-quincy-adams", "John Quincy Adams"),
        ("07-andrew-jackson", "Andrew Jackson"),
        ("08-martin-van-buren", "Martin Van Buren"),
        ("09-william-henry-harrison", "William Henry Harrison"),
        ("10-john-tyler", "John Tyler"),
        ("11-james-k-polk", "James K. Polk"),
        ("12-zachary-taylor", "Zachary Taylor"),
        ("13-millard-fillmore", "Millard Fillmore"),
        ("14-franklin-pierce", "Franklin Pierce"),
        ("15-james-buchanan", "James Buchanan"),
        ("16-abraham-lincoln", "Abraham Lincoln"),
        ("17-andrew-johnson", "Andrew Johnson"),
        ("18-ulysses-s-grant", "Ulysses S. Grant"),
        ("19-rutherford-b-hayes", "Rutherford B. Hayes"),
        ("20-james-a-garfield", "James A. Garfield"),
        ("21-chester-a-arthur", "Chester A. Arthur"),
        ("22-grover-cleveland", "Grover Cleveland"),
        ("23-benjamin-harrison", "Benjamin Harrison"),
        ("24-william-mckinley", "William McKinley"),
        ("25-theodore-roosevelt", "Theodore Roosevelt"),
        ("26-william-howard-taft", "William Howard Taft"),
        ("27-woodrow-wilson", "Woodrow Wilson"),
        ("28-warren-g-harding", "Warren G. Harding"),
        ("29-calvin-coolidge", "Calvin Coolidge"),
        ("30-herbert-hoover", "Herbert Hoover"),
        ("31-franklin-d-roosevelt", "Franklin D. Roosevelt"),
        ("32-harry-s-truman", "Harry S. Truman"),
        ("33-dwight-d-eisenhower", "Dwight D. Eisenhower"),
        ("34-john-f-kennedy", "John F. Kennedy"),
        ("35-lyndon-b-johnson", "Lyndon B. Johnson"),
        ("36-richard-nixon", "Richard Nixon"),
        ("37-gerald-ford", "Gerald Ford"),
        ("38-jimmy-carter", "Jimmy Carter"),
        ("39-ronald-reagan", "Ronald Reagan"),
        ("40-george-h-w-bush", "George H. W. Bush"),
        ("41-bill-clinton", "Bill Clinton"),
        ("42-george-w-bush", "George W. Bush"),
        ("43-barack-obama", "Barack Obama"),
        ("44-donald-trump", "Donald Trump"),
        ("45-joe-biden", "Joe Biden"),
    ]

    @MainActor
    static func seedIfNeeded(into context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededDefaultsKey) else { return }

        // A deck by this name already exists (e.g. restored from a backup) —
        // claim the flag and leave it alone.
        let name = deckName
        var existing = FetchDescriptor<Deck>(predicate: #Predicate { $0.name == name })
        existing.fetchLimit = 1
        if let found = try? context.fetch(existing), !found.isEmpty {
            defaults.set(true, forKey: seededDefaultsKey)
            return
        }

        let deck = Deck(name: name)
        context.insert(deck)

        // Stagger createdAt so previews and the study rotation introduce
        // the presidents in historical order.
        let base = Date.now
        for (index, president) in presidents.enumerated() {
            guard let asset = NSDataAsset(name: "Presidents/\(president.asset)") else {
                assertionFailure("Missing bundled portrait for \(president.name)")
                continue
            }
            let person = Person(name: president.name,
                                imageData: asset.data,
                                createdAt: base.addingTimeInterval(TimeInterval(index)))
            person.deck = deck
            context.insert(person)
        }

        try? context.save()
        defaults.set(true, forKey: seededDefaultsKey)
    }
}
