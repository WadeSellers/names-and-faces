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

    @State private var importRequest: DeckImportRequest?

    var body: some Scene {
        WindowGroup {
            DeckListView()
                .fontDesign(.rounded)
                // Someone tapped a .ntfdeck in Messages, Mail, or Files.
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == DeckFile.fileExtension else { return }
                    importRequest = DeckImportRequest(url: url)
                }
                .sheet(item: $importRequest) { request in
                    DeckImportView(url: request.url)
                        .fontDesign(.rounded)
                }
        }
        .modelContainer(container)
    }
}
