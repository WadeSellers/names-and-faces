import SwiftUI
import SwiftData

/// Home screen: one deck per cohort, with fanned face previews and a
/// mastery ring per deck.
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
        withAnimation {
            context.insert(Deck(name: name))
        }
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            context.delete(decks[index])
        }
    }
}

// MARK: - Row

private struct DeckRow: View {
    let deck: Deck

    private var previewPeople: [Person] {
        Array(deck.people.sorted { $0.createdAt < $1.createdAt }.prefix(3))
    }

    private var inRotationCount: Int {
        deck.people.filter { $0.introducedAt != nil }.count
    }

    var body: some View {
        HStack(spacing: 14) {
            facesFan

            VStack(alignment: .leading, spacing: 3) {
                Text(deck.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !deck.people.isEmpty {
                MasteryRing(mastery: deck.mastery)
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        guard !deck.people.isEmpty else { return "Empty — import a PDF" }
        var parts = ["\(deck.people.count) \(deck.people.count == 1 ? "person" : "people")"]
        if inRotationCount > 0 {
            parts.append("\(inRotationCount) in rotation")
        }
        return parts.joined(separator: " · ")
    }

    private var facesFan: some View {
        ZStack {
            if previewPeople.isEmpty {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "person.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            } else {
                ForEach(Array(previewPeople.enumerated()), id: \.element.persistentModelID) { index, person in
                    FaceImage(data: person.imageData)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        .offset(x: CGFloat(index) * 18)
                        .zIndex(Double(-index))
                }
            }
        }
        .frame(width: previewPeople.count > 1 ? 44 + CGFloat(previewPeople.count - 1) * 18 : 44,
               height: 44,
               alignment: .leading)
    }
}

/// Circular progress ring with the mastery percentage in the middle.
private struct MasteryRing: View {
    let mastery: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.quaternarySystemFill), lineWidth: 4)
            Circle()
                .trim(from: 0, to: mastery)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(mastery * 100))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 42, height: 42)
    }
}
