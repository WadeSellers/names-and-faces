import SwiftUI
import SwiftData

/// Wraps a picked PDF URL so it can drive a `.sheet(item:)`.
struct ImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

/// Runs extraction on a picked PDF, then lets the user fix names and
/// exclude bad detections before the cards are saved to the deck.
struct ImportReviewView: View {
    let deck: Deck
    let url: URL

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case extracting(String)
        case review
        case failed(String)
    }

    @State private var phase: Phase = .extracting("Reading PDF…")
    @State private var candidates: [ExtractedCandidate] = []

    private var includedCount: Int {
        candidates.filter(\.include).count
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .extracting(let message):
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Nothing Found", systemImage: "person.crop.rectangle.badge.plus")
                    } description: {
                        Text(message)
                    }
                case .review:
                    reviewGrid
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if case .review = phase {
                    Button {
                        save()
                    } label: {
                        Text("Add \(includedCount) \(includedCount == 1 ? "Person" : "People")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(includedCount == 0)
                    .padding()
                    .background(.bar)
                }
            }
        }
        .interactiveDismissDisabled()
        .task { await extract() }
    }

    private var reviewGrid: some View {
        ScrollView {
            Text("Check each name against its face. Tap the circle to leave someone out.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                ForEach($candidates) { $candidate in
                    CandidateCell(candidate: $candidate)
                }
            }
            .padding()
        }
    }

    private func extract() async {
        do {
            let found = try await Task.detached(priority: .userInitiated) { [url] in
                try PDFExtractor.extract(from: url) { page, total in
                    Task { @MainActor in
                        phase = .extracting("Scanning page \(page) of \(total)…")
                    }
                }
            }.value

            if found.isEmpty {
                phase = .failed("No faces were detected in that PDF. You can still add people one at a time with a photo.")
            } else {
                candidates = found
                phase = .review
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() {
        for candidate in candidates where candidate.include {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = candidate.image.resized(maxDimension: 900).jpegData(compressionQuality: 0.8) else { continue }
            let person = Person(name: name.isEmpty ? "Unknown" : name, imageData: data)
            context.insert(person)
            person.deck = deck
        }
        dismiss()
    }
}

private struct CandidateCell: View {
    @Binding var candidate: ExtractedCandidate

    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: candidate.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button {
                        candidate.include.toggle()
                    } label: {
                        Image(systemName: candidate.include ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(candidate.include ? Color.accentColor : .secondary)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(6)
                }

            TextField("Name", text: $candidate.name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
        .opacity(candidate.include ? 1 : 0.35)
    }
}
