import SwiftUI
import SwiftData

/// Tapping Share goes straight to the code: a small card with six digits and a
/// Copy button. If the deck doesn't have a code yet, one is made on the spot —
/// the tap on Share is the request.
struct ShareDeckView: View {
    @Bindable var deck: Deck

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .working
    @State private var copied = false
    @State private var confirmingStop = false
    @State private var messageItem: CodeMessage?

    private enum Phase: Equatable {
        case working
        case ready(String)
        case failed(String)
        case stopping
    }

    private struct CodeMessage: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 22)

            Group {
                switch phase {
                case .working, .stopping:
                    ProgressView()
                        .controlSize(.large)
                        .frame(height: 150)
                case .failed(let message):
                    failure(message)
                case .ready(let code):
                    codeCard(code)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .task { await prepare() }
        .confirmationDialog("Stop sharing this deck?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) { Task { await stopSharing() } }
        } message: {
            Text("The code stops working and the copy online is deleted. Anyone who already added the deck keeps it.")
        }
        .sheet(item: $messageItem) { message in
            TextShareSheet(text: message.text)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text("Share \u{201C}\(deck.name)\u{201D}")
                .font(.headline)
                .lineLimit(1)
            Text("Anyone with Name That Face can tap New Deck \u{2192} Enter a Code.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func codeCard(_ code: String) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(spaced(code))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                if let expires = deck.shareExpiresAt {
                    Text("Works until \(expires.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                Button {
                    copy(code)
                } label: {
                    Label(copied ? "Copied" : "Copy Code",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    messageItem = CodeMessage(text: message(for: code))
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Send the code with instructions")
            }

            Button("Stop Sharing", role: .destructive) {
                confirmingStop = true
            }
            .font(.footnote)
            .padding(.top, 2)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await prepare() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 30)
    }

    // MARK: - Actions

    /// Reuse the code the deck already has; otherwise make one.
    private func prepare() async {
        if let code = deck.activeShareCode {
            phase = .ready(code)
            return
        }
        guard !deck.people.isEmpty else {
            phase = .failed("Add some faces before sharing this deck.")
            return
        }
        phase = .working
        do {
            let shared = try await CodeShareClient.share(DeckFile(deck: deck))
            deck.shareCode = shared.code
            deck.shareOwnerToken = shared.ownerToken
            deck.shareExpiresAt = shared.expiresAt
            phase = .ready(shared.code)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }

    private func stopSharing() async {
        guard let code = deck.shareCode, let token = deck.shareOwnerToken else { return }
        phase = .stopping
        do {
            try await CodeShareClient.stopSharing(code: code, ownerToken: token)
            deck.shareCode = nil
            deck.shareOwnerToken = nil
            deck.shareExpiresAt = nil
            dismiss()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Text

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private func message(for code: String) -> String {
        """
        Here's a Name That Face deck: \u{201C}\(deck.name),\u{201D} \(deck.people.count) faces, \
        already cropped and named.

        1. Get the free app (skip if you have it): https://apps.apple.com/app/id6811378880
        2. Tap New Deck, choose Enter a Code, and type \(spaced(code)).

        The code works until \(deck.shareExpiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "it expires").
        """
    }
}

/// Sends a plain message: the code, not a file.
private struct TextShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
