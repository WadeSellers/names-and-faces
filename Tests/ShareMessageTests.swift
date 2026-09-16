import XCTest
@testable import NamesAndFaces

/// What someone reads when a deck lands in their Messages thread.
final class ShareMessageTests: XCTestCase {

    private let item = ShareItem(
        url: URL(fileURLWithPath: "/tmp/Fall 2026 First Years.ntfdeck"),
        deckName: "Fall 2026 First Years",
        faceCount: 23
    )

    func testNoteNamesTheDeckAndTheCount() {
        XCTAssertTrue(item.message.contains("“Fall 2026 First Years,”"))
        XCTAssertTrue(item.message.contains("23 faces"))
    }

    func testNoteSaysWhatEachPieceIsInOrder() {
        let message = item.message
        guard let app = message.range(of: "1. Get the free app"),
              let file = message.range(of: "2. Tap the deck file") else {
            return XCTFail("both steps should be spelled out:\n\(message)")
        }
        XCTAssertLessThan(app.lowerBound, file.lowerBound, "the app has to come before the file")
        XCTAssertTrue(message.contains("https://apps.apple.com/app/id6811378880"))
        XCTAssertTrue(message.contains("choose Name That Face"))
    }

    func testSingularFace() {
        let one = ShareItem(url: item.url, deckName: "Solo", faceCount: 1)
        XCTAssertTrue(one.message.contains("1 face,"))
    }

    func testPrintMessageForReview() {
        print("\n----- MESSAGE -----\n\(item.message)\n-------------------\n")
    }
}
