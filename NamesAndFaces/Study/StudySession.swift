import Foundation
import Observation

/// One sitting with a deck. Weakest faces come first; a missed face comes
/// back a few cards later and repeats until answered correctly, while the
/// Leitner box on each person carries progress between sessions.
@Observable
final class StudySession {
    private(set) var queue: [Person]
    private(set) var firstTryCorrect = 0
    private(set) var missedPeople: [Person] = []

    let totalPeople: Int
    private var missedIDs: Set<ObjectIdentifier> = []

    init(people: [Person]) {
        // Shuffle, then bring the least-known boxes to the front.
        let ordered = people.shuffled().sorted { $0.box < $1.box }
        queue = ordered
        totalPeople = ordered.count
    }

    var current: Person? { queue.first }
    var isFinished: Bool { queue.isEmpty }

    var peopleRemaining: Int {
        Set(queue.map { ObjectIdentifier($0) }).count
    }

    var progress: Double {
        guard totalPeople > 0 else { return 1 }
        return Double(totalPeople - peopleRemaining) / Double(totalPeople)
    }

    func answer(correct: Bool) {
        guard let person = queue.first else { return }
        queue.removeFirst()
        person.lastReviewedAt = .now

        let firstAttempt = !missedIDs.contains(ObjectIdentifier(person))
        if correct {
            person.timesCorrect += 1
            if firstAttempt {
                firstTryCorrect += 1
                person.box = min(Person.maxBox, person.box + 1)
            }
        } else {
            person.timesMissed += 1
            person.box = max(0, person.box - 1)
            if firstAttempt {
                missedIDs.insert(ObjectIdentifier(person))
                missedPeople.append(person)
            }
            // Come back to this face after a few others.
            queue.insert(person, at: min(3, queue.count))
        }
    }
}
