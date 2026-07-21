import SwiftUI
import SwiftData

@main
struct NamesAndFacesApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Deck.self, Person.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        PresidentsDemoDeck.seedIfNeeded(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            DeckListView()
                .fontDesign(.rounded)
        }
        .modelContainer(container)
    }
}
