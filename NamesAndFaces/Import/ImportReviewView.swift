import SwiftUI
import SwiftData

/// Wraps a picked PDF URL so it can drive a `.sheet(item:)`.
struct ImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

/// Runs extraction on a picked PDF, then lets the user fix names, crop
/// portraits, and exclude bad detections before the cards are saved.
struct ImportReviewView: View {
    let deck: Deck
    let url: URL

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case extracting(page: Int, total: Int)
        case review
        case failed(String)
    }

    private struct CropTarget: Identifiable {
        let id = UUID()
        let index: Int
    }

    @State private var phase: Phase = .extracting(page: 0, total: 0)
    @State private var candidates: [ExtractedCandidate] = []
    @State private var cropTarget: CropTarget?

    private var includedCount: Int {
        candidates.filter(\.include).count
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .extracting(let page, let total):
                    extractingView(page: page, total: total)
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
                            .monospacedDigit()
                            .contentTransition(.numericText())
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
        .fullScreenCover(item: $cropTarget) { target in
            let candidate = candidates[target.index]
            CropEditorView(image: candidate.original, initialCrop: candidate.crop) { region, croppedImage in
                withAnimation(.snappy) {
                    candidates[target.index].crop = region
                    candidates[target.index].image = croppedImage
                }
            }
        }
    }

    // MARK: - Phases

    private func extractingView(page: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "text.below.photo")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text(total > 0 ? "Scanning page \(page) of \(total)…" : "Reading PDF…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())

            ProgressView(value: total > 0 ? Double(page) : 0, total: Double(max(total, 1)))
                .frame(width: 200)
        }
    }

    private var reviewGrid: some View {
        ScrollView {
            Text("Check each name against its face. Crop a photo if any of the printed name sneaked in, and tap the circle to leave someone out.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                ForEach($candidates) { $candidate in
                    CandidateCell(candidate: $candidate) {
                        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
                            cropTarget = CropTarget(index: index)
                        }
                    }
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
                        withAnimation { phase = .extracting(page: page, total: total) }
                    }
                }
            }.value

            if found.isEmpty {
                phase = .failed("No faces were detected in that PDF. You can still add people one at a time with a photo.")
            } else {
                candidates = found
                withAnimation(.snappy) { phase = .review }
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
            person.originalImageData = candidate.original.resized(maxDimension: 900).jpegData(compressionQuality: 0.8)
            person.crop = candidate.crop
            context.insert(person)
            person.deck = deck
        }
        dismiss()
    }
}

// MARK: - Cell

private struct CandidateCell: View {
    @Binding var candidate: ExtractedCandidate
    let onCrop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: candidate.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.snappy) { candidate.include.toggle() }
                    } label: {
                        Image(systemName: candidate.include ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolEffect(.bounce, value: candidate.include)
                            .foregroundStyle(candidate.include ? Color.accentColor : .secondary)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(6)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: onCrop) {
                        Image(systemName: "crop")
                            .font(.subheadline.bold())
                            .padding(7)
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
