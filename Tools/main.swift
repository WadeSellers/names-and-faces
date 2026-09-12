import Foundation

let expected = [
    "George Washington", "John Adams", "Thomas Jefferson",
    "James Madison", "James Monroe", "John Quincy Adams",
    "Andrew Jackson", "Martin Van Buren", "William Henry Harrison",
    "John Tyler", "James K. Polk", "Zachary Taylor",
]

let cases: [(String, Int)] = [
    ("A-grid-name-below", 9),
    ("B-name-beside", 8),
    ("C-name-above", 9),
    ("D-dense-yearbook", 12),
    ("E-name-plus-role", 6),
    ("F-two-line-name", 6),
]

let dir = CommandLine.arguments[1]
for (fixture, count) in cases {
    let url = URL(fileURLWithPath: "\(dir)/\(fixture).pdf")
    do {
        let found = try PDFExtractor.extract(from: url) { _, _ in }
        let names = found.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let wanted = Set(expected.prefix(count))
        let correct = names.filter { wanted.contains($0) }.count
        print("\n── \(fixture)")
        print("   portraits found: \(found.count) of \(count)   names exactly right: \(correct) of \(count)")
        for n in names { print("     • \(n.isEmpty ? "(blank)" : n)") }
    } catch {
        print("\n── \(fixture)  ERROR: \(error)")
    }
}
