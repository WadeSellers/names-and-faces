import SwiftUI
import SwiftData

/// Wraps an incoming file URL so it can drive a `.sheet(item:)`.
struct DeckImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

/// Shown when someone opens a `.ntfdeck` sent to them. A deck from another
/// person gets looked at before it lands in your library — never a silent
/// import.
struct DeckImportView: View {
    /// A file someone tapped, or a deck already fetched by code.
    enum Source {
        case url(URL)
        case file(DeckFile)
    }

    let source: Source

    init(url: URL) { self.source = .url(url) }
    init(file: DeckFile) { self.source = .file(file) }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    private enum Phase {
        case reading
        case ready(DeckFile)
        case failed(String)
    }

    @State private var phase: Phase = .reading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .reading:
                    ProgressView("Opening deck…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Can't Open That Deck", systemImage: "doc.questionmark")
                    } description: {
                        Text(message)
                    }
                case .ready(let file):
                    preview(of: file)
                }
            }
            .navigationTitle("Shared Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if case .ready(let file) = phase {
                    Button {
                        add(file)
                    } label: {
                        Text("Add \(file.people.count) \(file.people.count == 1 ? "Face" : "Faces")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
        }
        .task { load() }
    }

    private func preview(of file: DeckFile) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(file.deckName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("\(file.people.count) \(file.people.count == 1 ? "face" : "faces")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = file.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 14) {
                ForEach(Array(file.people.enumerated()), id: \.offset) { _, person in
                    VStack(spacing: 6) {
                        FaceImage(data: person.imageData)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(person.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
    }

    private func load() {
        do {
            switch source {
            case .url(let url): phase = .ready(try DeckFile.read(from: url))
            case .file(let file): phase = .ready(file)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func add(_ file: DeckFile) {
        file.insert(into: context, existingNames: decks.map(\.name))
        dismiss()
    }
}
