import CoreGraphics
import Foundation

/// A line of recognized text, in top-left pixel coordinates.
struct TextLine {
    let string: String
    let rect: CGRect
}

/// Where the printed name sits relative to its portrait on a page, and the
/// pure geometry for pairing faces with names. No Vision in here, so the unit
/// tests can drive it with made-up rects in the Simulator.
enum NamePlacement: CaseIterable {
    case below, above, right, left

    /// Try each placement against every face and keep the one that explains the
    /// page best: most faces matched, then most matches that read as a person's
    /// name, then `below`, then the tightest gap.
    ///
    /// The name-like count is what separates a name from a label printed on the
    /// other side of the photo. A sumo sheet has "Yokozuna" or "Maegashira #3"
    /// just above each photo and the wrestler's name further below; both sides
    /// match every face, and on gap alone the closer rank line won. Ties go to
    /// `below`, which is what cohort sheets and yearbooks use.
    static func best(faces: [CGRect], lines: [TextLine]) -> NamePlacement {
        guard !faces.isEmpty, !lines.isEmpty else { return .below }

        var best: (placement: NamePlacement, matches: Int, nameLike: Int, gap: CGFloat)?

        for placement in allCases {
            var gaps: [CGFloat] = []
            var nameLike = 0
            for face in faces {
                let (name, lineIndex) = placement.name(near: face, lines: lines)
                guard !name.isEmpty, let lineIndex else { continue }
                gaps.append(placement.gap(from: face, to: lines[lineIndex].rect))
                if looksLikeName(name) { nameLike += 1 }
            }
            guard !gaps.isEmpty else { continue }
            let candidate = (placement: placement, matches: gaps.count, nameLike: nameLike, gap: median(gaps))

            guard let current = best else {
                best = candidate
                continue
            }
            let better: Bool
            if candidate.matches != current.matches {
                better = candidate.matches > current.matches
            } else if candidate.nameLike != current.nameLike {
                better = candidate.nameLike > current.nameLike
            } else if current.placement == .below {
                better = false
            } else {
                better = candidate.gap < current.gap - 0.5
            }
            if better {
                best = candidate
            }
        }
        return best?.placement ?? .below
    }

    /// Distance from the face edge the name sits against to the line.
    func gap(from face: CGRect, to line: CGRect) -> CGFloat {
        switch self {
        case .below: return line.minY - face.maxY
        case .above: return face.minY - line.maxY
        case .right: return line.minX - face.maxX
        case .left:  return face.minX - line.maxX
        }
    }

    /// The text line(s) sitting in this placement relative to the face, aligned with it.
    func name(near face: CGRect, lines: [TextLine]) -> (name: String, lineIndex: Int?) {
        let verticalReach = face.height * 3.5
        let horizontalReach = face.width * 4
        let slack = face.height * 0.1

        let candidates = lines.enumerated().filter { _, line in
            switch self {
            case .below:
                let span = face.insetBy(dx: -face.width * 0.75, dy: 0)
                return line.rect.minY > face.maxY - slack
                    && line.rect.minY < face.maxY + verticalReach
                    && line.rect.midX > span.minX && line.rect.midX < span.maxX
            case .above:
                let span = face.insetBy(dx: -face.width * 0.75, dy: 0)
                return line.rect.maxY < face.minY + slack
                    && line.rect.maxY > face.minY - verticalReach
                    && line.rect.midX > span.minX && line.rect.midX < span.maxX
            case .right:
                return line.rect.minX > face.maxX - face.width * 0.1
                    && line.rect.minX < face.maxX + horizontalReach
                    && line.rect.midY > face.minY - face.height
                    && line.rect.midY < face.maxY + face.height
            case .left:
                return line.rect.maxX < face.minX + face.width * 0.1
                    && line.rect.maxX > face.minX - horizontalReach
                    && line.rect.midY > face.minY - face.height
                    && line.rect.midY < face.maxY + face.height
            }
        }

        // Nearest first, measured from the face edge the name sits against.
        let ordered = candidates.sorted {
            gap(from: face, to: $0.element.rect) < gap(from: face, to: $1.element.rect)
        }

        guard let (firstIndex, first) = ordered.first else { return ("", nil) }
        var name = first.string

        // A name split across two stacked lines ("Jane" / "Doe"). Only a
        // single-word first line can be half a name — anything longer already
        // reads as a whole name, and the line under it is a job title.
        if self == .below || self == .above,
           first.string.split(separator: " ").count == 1,
           let (_, second) = ordered.dropFirst().first,
           abs(second.rect.minY - first.rect.maxY) < first.rect.height * 0.9 {
            name = self == .below ? name + " " + second.string : second.string + " " + name
        }

        return (name, firstIndex)
    }

    /// Two to five words, capitalized, no digits: a person, not a rank or a label.
    static func looksLikeName(_ string: String) -> Bool {
        guard string.count <= 40,
              string.rangeOfCharacter(from: .decimalDigits) == nil,
              let first = string.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) else { return false }
        let words = string.split(separator: " ")
        return words.count >= 2 && words.count <= 5
    }

    static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
