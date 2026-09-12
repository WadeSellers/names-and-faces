import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home screen: one deck per group of people, with fanned face previews and a
/// mastery ring per deck. The PDF import lives here too — it's the whole point
/// of the app, so it shouldn't be buried inside a deck you have to make first.
struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var showingNewDeckAlert = false
    @State private var newDeckName = ""
    @State private var showingFileImporter = false
    @State private var importRequest: ImportRequest?
    @State private var importingInto: Deck?
    @State private var importError: String?

    private static let pitch = "Import a PDF of headshots. Every face is found, the name printed with it is read, and you get a deck of flashcards — no typing, no cropping."

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups Yet", systemImage: "doc.viewfinder")
                    } description: {
                        Text(Self.pitch)
                    } actions: {
                        Button("Import a PDF") { showingFileImporter = true }
                            .buttonStyle(.borderedProminent)
                        Button("Start an Empty Group") { promptForNewDeck() }
                    }
                } else {
                    List {
                        Section {
                            ForEach(decks) { deck in
                                NavigationLink {
                                    DeckDetailView(deck: deck)
                                } label: {
                                    DeckRow(deck: deck)
                                }
                            }
                            .onDelete(perform: deleteDecks)
                        } footer: {
                            Text(Self.pitch)
                                .padding(.top, 6)
                        }
                    }
                }
            }
            .navigationTitle("Name That Face")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Import a PDF", systemImage: "doc.viewfinder")
                        }
                        Button {
                            promptForNewDeck()
                        } label: {
                            Label("Start an Empty Group", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .alert("New Group", isPresented: $showingNewDeckAlert) {
                TextField("Group name", text: $newDeckName)
                Button("Create") { createDeck() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name this group — your new class, cast, team, or cohort.")
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    startImport(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import Failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(item: $importRequest, onDismiss: discardEmptyImportDeck) { request in
                if let deck = importingInto {
                    ImportReviewView(deck: deck, url: request.url)
                }
            }
        }
    }

    // MARK: - Actions

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

    /// Importing from the home screen makes the group for you, named after the
    /// file, so the first thing a newcomer does is the thing the app is for.
    private func startImport(from url: URL) {
        let deck = Deck(name: Self.groupName(from: url))
        context.insert(deck)
        importingInto = deck
        importRequest = ImportRequest(url: url)
    }

    /// Backing out of the review sheet shouldn't leave an empty group behind.
    private func discardEmptyImportDeck() {
        if let deck = importingInto, deck.people.isEmpty {
            context.delete(deck)
        }
        importingInto = nil
    }

    static func groupName(from url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "New Group" : raw
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

    /// The bundled deck, still untouched — label it so nobody mistakes it for
    /// something they added.
    private var isUntouchedSample: Bool {
        deck.name == PresidentsDemoDeck.deckName && inRotationCount == 0
    }

    var body: some View {
        HStack(spacing: 14) {
            facesFan

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(deck.name)
                        .font(.headline)
                    if isUntouchedSample {
                        Text("TRY IT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
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
        if isUntouchedSample {
            return "\(deck.people.count) faces to practice on"
        }
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
