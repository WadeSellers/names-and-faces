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
    @FocusState private var editingName: UUID?

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
                    // While a name is being edited this button sits directly above
                    // the keyboard, where "Add 23 People" reads like it would file
                    // everyone mid-edit. It finishes the edit instead.
                    Button {
                        if editingName != nil {
                            editingName = nil
                        } else {
                            save()
                        }
                    } label: {
                        Text(editingName != nil
                             ? "Done"
                             : "Add \(includedCount) \(includedCount == 1 ? "Person" : "People")")
                            .font(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(editingName == nil && includedCount == 0)
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
                    CandidateCell(candidate: $candidate, editingName: $editingName) {
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
    var editingName: FocusState<UUID?>.Binding
    let onCrop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: candidate.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // The crop button is small and easy to miss; the photo itself is
                // the obvious thing to tap when a name has crept into it.
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture(perform: onCrop)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Crop this photo")
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

            // Extraction can pull in a neighbour's name or a job title, so the
            // whole string has to be readable — truncated to one line is exactly
            // where a wrong name hides. Wraps at rest and while editing.
            TextField("Name", text: $candidate.name, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                .focused(editingName, equals: candidate.id)
                .submitLabel(.done)
                .onChange(of: candidate.name) { _, newValue in
                    // A vertical-axis field turns Return into a newline; keep
                    // Return meaning "I'm finished with this name".
                    guard newValue.contains("\n") else { return }
                    candidate.name = newValue
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    editingName.wrappedValue = nil
                }
        }
        .opacity(candidate.include ? 1 : 0.35)
    }
}
