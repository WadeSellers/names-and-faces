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
    @State private var sharingDeck: Deck?
    @State private var choosingNewDeck = false
    @State private var enteringCode = false
    @State private var redeemedDeck: RedeemedDeck?

    /// A deck fetched by code, waiting for its preview.
    private struct RedeemedDeck: Identifiable {
        let id = UUID()
        let file: DeckFile
    }

    private static let pitch = "Import a PDF of headshots. Every face is found, the name printed with it is read, and you get a deck of flashcards — no typing, no cropping."

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No Decks Yet", systemImage: "doc.viewfinder")
                    } description: {
                        Text(Self.pitch)
                    } actions: {
                        Button("Import a PDF") { showingFileImporter = true }
                            .buttonStyle(.borderedProminent)
                        Button("Enter a Code") { enteringCode = true }
                        Button("Take Photos") { promptForNewDeck() }
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
                                .swipeActions(edge: .leading) {
                                    if !deck.people.isEmpty {
                                        Button {
                                            sharingDeck = deck
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.accentColor)
                                    }
                                }
                            }
                            .onDelete(perform: deleteDecks)

                            Button {
                                choosingNewDeck = true
                            } label: {
                                Label("New Deck", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.vertical, 8)
                            }
                        } footer: {
                            Text(Self.pitch)
                                .padding(.top, 6)
                        }
                    }
                }
            }
            .navigationTitle("Name That Face")
            .confirmationDialog("New Deck", isPresented: $choosingNewDeck, titleVisibility: .hidden) {
                Button("Import a PDF") { showingFileImporter = true }
                Button("Enter a Code") { enteringCode = true }
                Button("Take Photos") { promptForNewDeck() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Deck", isPresented: $showingNewDeckAlert) {
                TextField("Deck name", text: $newDeckName)
                Button("Create") { createDeck() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name it, then add people with your camera or photo library.")
            }
            .sheet(isPresented: $enteringCode) {
                EnterCodeView { file in
                    // Let the code sheet finish closing before the preview opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        redeemedDeck = RedeemedDeck(file: file)
                    }
                }
            }
            .sheet(item: $redeemedDeck) { redeemed in
                DeckImportView(file: redeemed.file)
            }
            .sheet(item: $sharingDeck) { deck in
                ShareDeckView(deck: deck)
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
        return raw.isEmpty ? "New Deck" : raw
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

    @Environment(\.dynamicTypeSize) private var typeSize

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
        // A deck name set in accessibility type has no room beside the faces and
        // the ring, so the row becomes a column.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))

        return layout {
            facesFan

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(deck.name)
                        .font(.headline)
                        .lineLimit(2)
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
                    .lineLimit(2)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

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

    @ScaledMetric(relativeTo: .caption) private var diameter: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.quaternarySystemFill), lineWidth: 4)
            Circle()
                .trim(from: 0, to: mastery)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(mastery * 100))")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(width: min(diameter, 68), height: min(diameter, 68))
    }
}
