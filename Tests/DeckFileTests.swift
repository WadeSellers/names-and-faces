import XCTest
import SwiftData
@testable import NamesAndFaces

/// A shared deck arrives over the network, so these cover both halves: what
/// goes up is complete, and what comes down can't be trusted.
/// No Vision here, so unlike the extractor tests these run in the simulator.
final class DeckFileTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Deck.self, Person.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func jpeg(_ color: UIColor = .systemTeal) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 50))
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 50))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    @discardableResult
    private func makeDeck(in context: ModelContext, name: String = "Fall 2026 First Years") -> Deck {
        let deck = Deck(name: name)
        context.insert(deck)
        for personName in ["Coraline Adams", "Bo Chen", "Ines Okafor"] {
            let person = Person(name: personName, imageData: jpeg())
            context.insert(person)
            person.deck = deck
        }
        return deck
    }

    // MARK: - Round trip

    func testRoundTripKeepsEveryFaceAndName() throws {
        let context = try makeContext()
        let deck = makeDeck(in: context)

        let data = try DeckFile(deck: deck).encoded()
        let decoded = try PropertyListDecoder().decode(DeckFile.self, from: data)

        XCTAssertEqual(decoded.deckName, "Fall 2026 First Years")
        XCTAssertEqual(decoded.people.count, 3)
        XCTAssertEqual(Set(decoded.people.map(\.name)),
                       ["Coraline Adams", "Bo Chen", "Ines Okafor"])
        XCTAssertTrue(decoded.people.allSatisfy { !$0.imageData.isEmpty })
    }

    func testUncroppedPeopleDoNotCarryADuplicateOriginal() throws {
        let context = try makeContext()
        let deck = makeDeck(in: context)
        // Every person here is uncropped, so the original is the display image.
        deck.people.forEach { $0.originalImageData = self.jpeg(.systemPink) }

        let file = DeckFile(deck: deck)
        XCTAssertTrue(file.people.allSatisfy { $0.originalImageData == nil },
                      "shipping the original twice would double the file for nothing")

        deck.people.first?.crop = CropRegion(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let cropped = DeckFile(deck: deck)
        XCTAssertEqual(cropped.people.filter { $0.originalImageData != nil }.count, 1,
                       "a cropped person keeps their original so the recipient can re-crop")
    }

    func testProgressDoesNotTravelWithTheDeck() throws {
        let context = try makeContext()
        let deck = makeDeck(in: context)
        for person in deck.people {
            person.box = 4
            person.timesCorrect = 12
            person.introducedAt = .now
        }

        let file = try PropertyListDecoder().decode(
            DeckFile.self, from: try DeckFile(deck: deck).encoded()
        )

        let fresh = try makeContext()
        let imported = file.insert(into: fresh, existingNames: [])
        XCTAssertEqual(imported.people.count, 3)
        XCTAssertTrue(imported.people.allSatisfy { $0.box == 0 && $0.introducedAt == nil },
                      "the recipient starts at zero, like any new deck")
    }

    // MARK: - Naming

    func testImportingTwiceDoesNotCollideOrMerge() throws {
        XCTAssertEqual(DeckFile.uniqueName(from: "Cohort", taken: []), "Cohort")
        XCTAssertEqual(DeckFile.uniqueName(from: "Cohort", taken: ["Cohort"]), "Cohort (2)")
        XCTAssertEqual(DeckFile.uniqueName(from: "Cohort", taken: ["Cohort", "Cohort (2)"]), "Cohort (3)")
    }

    // MARK: - Untrusted input

    func testGarbageFailsWithAMessageInsteadOfCrashing() throws {
        XCTAssertThrowsError(try DeckFile.read(from: Data("this is not a deck".utf8))) { error in
            XCTAssertNotNil((error as? DeckFile.ReadError)?.errorDescription)
        }
    }

    func testDeckFromANewerAppIsRefusedClearly() throws {
        let context = try makeContext()
        var file = DeckFile(deck: makeDeck(in: context))
        file.formatVersion = DeckFile.currentVersion + 1
        XCTAssertThrowsError(try DeckFile.read(from: try file.encoded())) { error in
            guard case .fromANewerApp = error as? DeckFile.ReadError else {
                return XCTFail("expected a version error, got \(error)")
            }
        }
    }

    func testOneUnreadablePortraitDoesNotCostTheWholeDeck() throws {
        let context = try makeContext()
        var file = DeckFile(deck: makeDeck(in: context))
        file.people[1].imageData = Data(repeating: 0x00, count: 128)   // not an image
        let read = try DeckFile.read(from: try file.encoded())
        XCTAssertEqual(read.people.count, 2)
        XCTAssertEqual(Set(read.people.map(\.name)), ["Coraline Adams", "Ines Okafor"])
    }

    func testAbsurdNamesAreTruncatedNotStored() throws {
        let context = try makeContext()
        var file = DeckFile(deck: makeDeck(in: context))
        file.deckName = String(repeating: "z", count: 5_000)
        file.people[0].name = String(repeating: "y", count: 5_000)
        let read = try DeckFile.read(from: try file.encoded())
        XCTAssertLessThanOrEqual(read.deckName.count, DeckFile.Limits.maxNameLength)
        XCTAssertLessThanOrEqual(read.people[0].name.count, DeckFile.Limits.maxNameLength)
    }

    func testDeckWithNoUsableFacesIsRefused() throws {
        let context = try makeContext()
        var file = DeckFile(deck: makeDeck(in: context))
        for index in file.people.indices {
            file.people[index].imageData = Data(repeating: 0x00, count: 64)
        }
        XCTAssertThrowsError(try DeckFile.read(from: try file.encoded())) { error in
            guard case .empty = error as? DeckFile.ReadError else {
                return XCTFail("expected an empty-deck error, got \(error)")
            }
        }
    }

    // MARK: - The real path, end to end

    func testEncodeThenReadThenImport() throws {
        let context = try makeContext()
        let deck = makeDeck(in: context, name: "Neighborhood Playhouse")

        // Exactly what travels: bytes up to the server, the same bytes down.
        let bytes = try DeckFile(deck: deck).encoded()
        XCTAssertEqual(bytes.prefix(8), Data("bplist00".utf8), "the server only accepts binary plists")

        let file = try DeckFile.read(from: bytes)
        let receiving = try makeContext()
        let imported = file.insert(into: receiving, existingNames: ["Neighborhood Playhouse"])

        XCTAssertEqual(imported.name, "Neighborhood Playhouse (2)")
        XCTAssertEqual(imported.people.count, 3)
    }
}
