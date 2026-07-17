import SwiftUI
import SwiftData

/// Home screen: one deck per cohort.
struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var showingNewDeckAlert = false
    @State private var newDeckName = ""

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No Cohorts Yet", systemImage: "person.crop.rectangle.stack")
                    } description: {
                        Text("Create a deck for your first cohort, then import their PDF to build flashcards.")
                    } actions: {
                        Button("New Deck") { promptForNewDeck() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(decks) { deck in
                            NavigationLink {
                                DeckDetailView(deck: deck)
                            } label: {
                                DeckRow(deck: deck)
                            }
                        }
                        .onDelete(perform: deleteDecks)
                    }
                }
            }
            .navigationTitle("Names & Faces")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        promptForNewDeck()
                    } label: {
                        Label("New Deck", systemImage: "plus")
                    }
                }
            }
            .alert("New Deck", isPresented: $showingNewDeckAlert) {
                TextField("Cohort name", text: $newDeckName)
                Button("Create") { createDeck() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name this cohort — for example \u{201C}Fall 2026 First Years\u{201D}.")
            }
        }
    }

    private func promptForNewDeck() {
        newDeckName = ""
        showingNewDeckAlert = true
    }

    private func createDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        context.insert(Deck(name: name))
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            context.delete(decks[index])
        }
    }
}

private struct DeckRow: View {
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.name)
                .font(.headline)
            HStack(spacing: 12) {
                Text("\(deck.people.count) \(deck.people.count == 1 ? "person" : "people")")
                if !deck.people.isEmpty {
                    Text("\(Int(deck.mastery * 100))% mastered")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !deck.people.isEmpty {
                ProgressView(value: deck.mastery)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}
