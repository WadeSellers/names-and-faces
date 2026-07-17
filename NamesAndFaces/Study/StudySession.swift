import Foundation
import Observation

/// Continuous study over a user-controlled rotation. The rotation starts at
/// three faces and grows only when the user asks for one more; membership is
/// persisted on each Person (`introducedAt`) so it survives between sittings.
/// A face entering the rotation is shown once with its name (an intro card)
/// before it gets quizzed. The rotation cycles until the user ends the session,
/// with missed faces coming back a few cards later.
@Observable
final class StudySession {
    static let startingRotationSize = 3

    private(set) var queue: [Person] = []
    private(set) var rotation: [Person] = []
    private(set) var waiting: [Person] = []

    let totalPeople: Int

    private var pendingIntro: Set<ObjectIdentifier> = []
    private var missedIDs: Set<ObjectIdentifier> = []
    private var lastShown: Person?

    init(people: [Person]) {
        totalPeople = people.count
        // Introduction order = the order they came off the sheet.
        let ordered = people.sorted {
            $0.createdAt == $1.createdAt ? $0.name < $1.name : $0.createdAt < $1.createdAt
        }
        rotation = ordered.filter { $0.introducedAt != nil }
        waiting = ordered.filter { $0.introducedAt == nil }

        while rotation.count < Self.startingRotationSize, !waiting.isEmpty {
            let next = waiting.removeFirst()
            next.introducedAt = .now
            rotation.append(next)
            pendingIntro.insert(ObjectIdentifier(next))
        }
        rebuildQueue()
    }

    var current: Person? { queue.first }

    /// True while the current card is a face's first appearance (name shown).
    var isIntroCard: Bool {
        guard let current else { return false }
        return pendingIntro.contains(ObjectIdentifier(current))
    }

    var inRotationCount: Int { rotation.count }
    var waitingCount: Int { waiting.count }
    var canAddMore: Bool { !waiting.isEmpty }

    /// The "one more face" button: pull the next person into the rotation
    /// and show them immediately as an intro card.
    func introduceNext() {
        guard !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        next.introducedAt = .now
        rotation.append(next)
        pendingIntro.insert(ObjectIdentifier(next))
        queue.insert(next, at: 0)
    }

    func answer(correct: Bool) {
        guard let person = queue.first else { return }
        let id = ObjectIdentifier(person)
        queue.removeFirst()
        lastShown = person

        if pendingIntro.contains(id) {
            // Introduction acknowledged; quizzing starts on the next pass.
            pendingIntro.remove(id)
        } else {
            person.lastReviewedAt = .now
            if correct {
                person.timesCorrect += 1
                if missedIDs.contains(id) {
                    // Recovery rep after a miss this session — no promotion yet.
                    missedIDs.remove(id)
                } else {
                    person.box = min(Person.maxBox, person.box + 1)
                }
            } else {
                person.timesMissed += 1
                person.box = max(0, person.box - 1)
                missedIDs.insert(id)
                // Come back to this face after a few others.
                queue.insert(person, at: min(3, queue.count))
            }
        }

        if queue.isEmpty {
            rebuildQueue()
        }
    }

    /// A fresh pass through the rotation: shuffled, weakest boxes first,
    /// intro cards up front, and never the same face twice in a row.
    private func rebuildQueue() {
        var cycle = rotation.shuffled().sorted { $0.box < $1.box }
        if cycle.count > 1, let lastShown, cycle.first === lastShown {
            cycle.swapAt(0, 1)
        }
        let intros = cycle.filter { pendingIntro.contains(ObjectIdentifier($0)) }
        let rest = cycle.filter { !pendingIntro.contains(ObjectIdentifier($0)) }
        queue = intros + rest
    }
}
