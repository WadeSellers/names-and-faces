import XCTest
@testable import NamesAndFaces

/// The face-to-name geometry on made-up rects. No Vision involved, so unlike
/// `PDFExtractorTests` these run in the Simulator.
final class NamePlacementTests: XCTestCase {

    private static let people = [
        "George Washington", "John Adams", "Thomas Jefferson",
        "James Madison", "James Monroe", "John Quincy Adams",
        "Andrew Jackson", "Martin Van Buren", "William Henry Harrison",
    ]

    /// A 3x3 grid of 100 px faces, 300 px apart, top-left origin.
    private static let faces: [CGRect] = (0..<9).map { index in
        CGRect(x: 100 + CGFloat(index % 3) * 300,
               y: 200 + CGFloat(index / 3) * 300,
               width: 100, height: 100)
    }

    /// A 20 px tall line centred on the face, its top `offset` from the face top.
    private static func line(_ string: String, over face: CGRect, offset: CGFloat) -> TextLine {
        TextLine(string: string, rect: CGRect(x: face.midX - 70, y: face.minY + offset, width: 140, height: 20))
    }

    private static func names(below gap: CGFloat) -> [TextLine] {
        zip(people, faces).map { line($0, over: $1, offset: 100 + gap) }
    }

    private static func lines(above gap: CGFloat, _ strings: [String]) -> [TextLine] {
        zip(strings, faces).map { line($0, over: $1, offset: -20 - gap) }
    }

    func testNamesBelow() {
        XCTAssertEqual(NamePlacement.best(faces: Self.faces, lines: Self.names(below: 40)), .below)
    }

    func testNamesOnlyAbove() {
        // The row underneath's names also sit "below" the first two rows, but
        // only "above" explains all nine faces.
        let lines = Self.lines(above: 20, Self.people)
        XCTAssertEqual(NamePlacement.best(faces: Self.faces, lines: lines), .above)

        let (name, _) = NamePlacement.above.name(near: Self.faces[4], lines: lines)
        XCTAssertEqual(name, "James Monroe")
    }

    func testRankAboveNameBelow() {
        // The sumo sheet: a rank line tight above every photo, the name further
        // below. Both sides match all nine faces and the rank is closer.
        let ranks = ["Yokozuna", "Ozeki", "Sekiwake", "Komusubi",
                     "Maegashira #1", "Maegashira #3", "Maegashira #5", "Maegashira #8", "Juryo"]
        let lines = Self.lines(above: 4, ranks) + Self.names(below: 60)

        let placement = NamePlacement.best(faces: Self.faces, lines: lines)
        XCTAssertEqual(placement, .below)
        XCTAssertEqual(placement.name(near: Self.faces[5], lines: lines).name, "John Quincy Adams")
    }

    func testTwoWordLabelAboveStillLosesToNameBelow() {
        // A role line that happens to look like a name ("Stage Manager") ties
        // with the real names on every count but gap. Ties go to below.
        let roles = Array(repeating: "Stage Manager", count: 9)
        let lines = Self.lines(above: 4, roles) + Self.names(below: 60)
        XCTAssertEqual(NamePlacement.best(faces: Self.faces, lines: lines), .below)
    }

    func testNamesToTheRight() {
        let lines = zip(Self.people, Self.faces).map { name, face in
            TextLine(string: name, rect: CGRect(x: face.maxX + 20, y: face.midY - 10, width: 140, height: 20))
        }
        XCTAssertEqual(NamePlacement.best(faces: Self.faces, lines: lines), .right)
    }

    func testNoFacesOrNoLinesDefaultsToBelow() {
        XCTAssertEqual(NamePlacement.best(faces: [], lines: Self.names(below: 40)), .below)
        XCTAssertEqual(NamePlacement.best(faces: Self.faces, lines: []), .below)
    }

    func testTwoLineNameRejoins() {
        let face = Self.faces[0]
        let lines = [Self.line("Jane", over: face, offset: 130), Self.line("Doe", over: face, offset: 152)]
        XCTAssertEqual(NamePlacement.below.name(near: face, lines: lines).name, "Jane Doe")
    }

    func testLooksLikeName() {
        XCTAssertTrue(NamePlacement.looksLikeName("John Quincy Adams"))
        XCTAssertFalse(NamePlacement.looksLikeName("Yokozuna"))
        XCTAssertFalse(NamePlacement.looksLikeName("Maegashira #3"))
        XCTAssertFalse(NamePlacement.looksLikeName("class of 2027"))
    }
}
