import SwiftUI
import SwiftData

@main
struct NamesAndFacesApp: App {
    var body: some Scene {
        WindowGroup {
            DeckListView()
        }
        .modelContainer(for: [Deck.self, Person.self])
    }
}
