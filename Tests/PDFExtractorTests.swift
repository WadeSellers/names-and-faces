import XCTest
@testable import NamesAndFaces

/// Runs the real extractor against PDFs in layouts the Playhouse sheets don't
/// use, to see how the heuristics hold up on other people's documents.
///
/// NOTE: Vision cannot create an inference context in the iOS Simulator, so
/// these only run on a real device. `Tools/extract-harness` runs the same
/// extractor natively on macOS when no device is handy.
final class PDFExtractorTests: XCTestCase {

    private static let expected = [
        "George Washington", "John Adams", "Thomas Jefferson",
        "James Madison", "James Monroe", "John Quincy Adams",
        "Andrew Jackson", "Martin Van Buren", "William Henry Harrison",
        "John Tyler", "James K. Polk", "Zachary Taylor",
    ]

    private func report(_ fixture: String, expectedCount: Int) throws -> (found: Int, correct: Int) {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: fixture, withExtension: "pdf"),
            "fixture \(fixture).pdf missing from the test bundle"
        )
        let candidates = try PDFExtractor.extract(from: url) { _, _ in }
        let names = candidates.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let wanted = Set(Self.expected.prefix(expectedCount))
        let correct = names.filter { wanted.contains($0) }.count

        print("── \(fixture): \(candidates.count) found / \(expectedCount) expected, \(correct) names correct")
        for name in names { print("     \(name.isEmpty ? "(no name)" : name)") }
        return (candidates.count, correct)
    }

    func testGridNameBelow() throws {
        let r = try report("A-grid-name-below", expectedCount: 9)
        XCTAssertEqual(r.found, 9, "baseline layout should find every portrait")
        XCTAssertEqual(r.correct, 9, "baseline layout should read every name")
    }

    func testNameBesidePhoto() throws {
        let r = try report("B-name-beside", expectedCount: 8)
        XCTAssertEqual(r.correct, 8, "a roster with names beside the photos should still pair up")
    }

    func testNameAbovePhoto() throws {
        let r = try report("C-name-above", expectedCount: 9)
        XCTAssertEqual(r.correct, 9, "names above photos must not pair with the row beneath")
    }

    func testDenseYearbook() throws {
        let r = try report("D-dense-yearbook", expectedCount: 12)
        XCTAssertEqual(r.correct, 12, "small yearbook type should still read")
    }

    func testNamePlusRoleLine() throws {
        let r = try report("E-name-plus-role", expectedCount: 6)
        XCTAssertEqual(r.correct, 6, "a job title under the name is not part of the name")
    }

    func testTwoLineName() throws {
        let r = try report("F-two-line-name", expectedCount: 6)
        XCTAssertEqual(r.correct, 6, "a name split across two lines should rejoin")
    }
}
