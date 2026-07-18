import Foundation
import Observation

/// Continuous study over a user-controlled rotation. The rotation starts at
/// three faces and grows only when the user asks for one more; membership is
/// persisted on each Person (`introducedAt`) so it survives between sittings.
///
/// Frequency follows mastery (expanding retrieval practice): each pass
/// through the deck, a level-0 face appears three times with widening gaps,
/// a level-1 face twice, and everyone else once. A face levels up at most
/// once per pass, so a new face earns its way down from 3× to 1× across
/// three passes — and a miss drops its level, which automatically raises
/// its frequency again. A face entering the rotation is shown once with its
/// name (an intro card), with its first real quiz a few cards later while
/// the name is still warm.
@Observable
final class StudySession {
    static let startingRotationSize = 3

    private(set) var queue: [Person] = []
    private(set) var rotation: [Person] = []
    private(set) var waiting: [Person] = []

    let totalPeople: Int

    private var pendingIntro: Set<ObjectIdentifier> = []
    private var missedIDs: Set<ObjectIdentifier> = []
    private var promotedThisPass: Set<ObjectIdentifier> = []
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

    /// The "one more face" button: pull the next person into the rotation,
    /// show them immediately as an intro card, and line up their first
    /// quizzes with expanding gaps while the name is still warm.
    func introduceNext() {
        guard !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        next.introducedAt = .now
        rotation.append(next)
        pendingIntro.insert(ObjectIdentifier(next))
        queue.insert(next, at: 0)
        insertAvoidingRepeat(next, around: 3)
        insertAvoidingRepeat(next, around: 9)
    }

    func answer(correct: Bool) {
        guard let person = queue.first else { return }
        let id = ObjectIdentifier(person)
        queue.removeFirst()
        lastShown = person

        if pendingIntro.contains(id) {
            // Introduction acknowledged; quizzing starts a few cards later.
            pendingIntro.remove(id)
        } else {
            person.lastReviewedAt = .now
            if correct {
                person.timesCorrect += 1
                if missedIDs.contains(id) {
                    // Recovery rep after a miss this session — no promotion.
                    missedIDs.remove(id)
                } else if !promotedThisPass.contains(id) {
                    // One level per pass: locking a face in takes separate
                    // passes, not one lucky streak of its repeats.
                    person.box = min(Person.maxBox, person.box + 1)
                    promotedThisPass.insert(id)
                }
            } else {
                person.timesMissed += 1
                person.box = max(0, person.box - 1)
                missedIDs.insert(id)
                // Come back to this face after a few others.
                insertAvoidingRepeat(person, around: min(3, queue.count))
            }
        }

        if queue.isEmpty {
            rebuildQueue()
        }
    }

    // MARK: - Pass construction

    /// How many times a face appears in one pass: 3× at level 0,
    /// 2× at level 1, 1× from level 2 up.
    private func appearances(of person: Person) -> Int {
        max(1, 3 - person.box)
    }

    /// A fresh pass: shuffled, weakest levels first, intro cards up front,
    /// never the same face twice in a row — then the extra appearances for
    /// low-level faces are laid in with expanding gaps.
    private func rebuildQueue() {
        promotedThisPass.removeAll()

        var base = rotation.shuffled().sorted { $0.box < $1.box }
        if base.count > 1, let lastShown, base.first === lastShown {
            base.swapAt(0, 1)
        }
        let intros = base.filter { pendingIntro.contains(ObjectIdentifier($0)) }
        let rest = base.filter { !pendingIntro.contains(ObjectIdentifier($0)) }
        queue = intros + rest

        // A rotation of one can't space out repeats.
        guard rotation.count > 1 else { return }

        for person in base {
            let extras = appearances(of: person) - 1
            guard extras > 0,
                  let first = queue.firstIndex(where: { $0 === person }) else { continue }
            var anchor = first
            for extra in 0..<extras {
                // Short gap to the second look, a longer one to the third.
                let gap = extra == 0 ? 3 : max(6, (queue.count - anchor) * 2 / 3)
                let target = anchor + gap
                let countBefore = queue.count
                insertAvoidingRepeat(person, around: target)
                guard queue.count > countBefore else { break }
                anchor = min(target, queue.count - 1)
            }
        }
    }

    /// Insert near `index`, nudging forward so the same face never sits in
    /// two consecutive slots (which would also break the card stack's
    /// identity). If every slot from `index` on would clash, the copy is
    /// dropped — that only happens when the person already holds the tail.
    private func insertAvoidingRepeat(_ person: Person, around index: Int) {
        var idx = min(max(index, 0), queue.count)
        while idx <= queue.count {
            let before = idx > 0 ? queue[idx - 1] : nil
            let after = idx < queue.count ? queue[idx] : nil
            if before !== person, after !== person {
                queue.insert(person, at: idx)
                return
            }
            idx += 1
        }
    }
}
