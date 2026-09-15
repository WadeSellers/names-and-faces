import SwiftUI
import SwiftData

/// Two ways out for a deck: a 6-digit code anyone can type in, or the file
/// itself. The code leads, because it works for a whole room at once — write
/// it on a whiteboard, say it in a meeting.
struct ShareDeckView: View {
    @Bindable var deck: Deck

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var fileItem: ShareItem?
    @State private var codeMessageItem: CodeMessage?
    @State private var confirmingStop = false

    private struct CodeMessage: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let code = deck.activeShareCode {
                        activeCode(code)
                    } else {
                        getCodeRow
                    }
                } header: {
                    Text("Share with a code")
                } footer: {
                    Text("Anyone with Name That Face can tap New Deck \u{2192} Enter a Code and get this deck, cropped and named. Codes stop working after 30 days.")
                }

                Section {
                    Button {
                        sendFile()
                    } label: {
                        Label("Send as a File", systemImage: "doc")
                    }
                } footer: {
                    Text("AirDrop, Messages, or Mail. Nothing is stored online.")
                }
            }
            .navigationTitle("Share \u{201C}\(deck.name)\u{201D}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't Share", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Stop sharing this deck?", isPresented: $confirmingStop, titleVisibility: .visible) {
                Button("Stop Sharing", role: .destructive) { Task { await stopSharing() } }
            } message: {
                Text("The code stops working and the copy online is deleted. Anyone who already added the deck keeps it.")
            }
            .sheet(item: $fileItem) { item in
                ShareSheet(item: item) { try? FileManager.default.removeItem(at: item.url) }
            }
            .sheet(item: $codeMessageItem) { message in
                TextShareSheet(text: message.text)
            }
        }
    }

    // MARK: - Rows

    private var getCodeRow: some View {
        Button {
            Task { await getCode() }
        } label: {
            HStack {
                Label("Get a Code", systemImage: "number.square")
                Spacer()
                if isWorking { ProgressView() }
            }
        }
        .disabled(isWorking || deck.people.isEmpty)
    }

    @ViewBuilder
    private func activeCode(_ code: String) -> some View {
        VStack(spacing: 6) {
            Text(spaced(code))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .textSelection(.enabled)
            if let expires = deck.shareExpiresAt {
                Text("Works until \(expires.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)

        Button {
            codeMessageItem = CodeMessage(text: message(for: code))
        } label: {
            Label("Send the Code", systemImage: "square.and.arrow.up")
        }

        Button {
            UIPasteboard.general.string = code
        } label: {
            Label("Copy Code", systemImage: "doc.on.doc")
        }

        Button(role: .destructive) {
            confirmingStop = true
        } label: {
            HStack {
                Label("Stop Sharing", systemImage: "xmark.circle")
                Spacer()
                if isWorking { ProgressView() }
            }
        }
        .disabled(isWorking)
    }

    // MARK: - Actions

    private func getCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let shared = try await CodeShareClient.share(DeckFile(deck: deck))
            deck.shareCode = shared.code
            deck.shareOwnerToken = shared.ownerToken
            deck.shareExpiresAt = shared.expiresAt
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopSharing() async {
        guard let code = deck.shareCode, let token = deck.shareOwnerToken else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await CodeShareClient.stopSharing(code: code, ownerToken: token)
            deck.shareCode = nil
            deck.shareOwnerToken = nil
            deck.shareExpiresAt = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendFile() {
        let file = DeckFile(deck: deck)
        do {
            fileItem = ShareItem(url: try file.writeToTemporaryFile(),
                                 deckName: deck.name,
                                 faceCount: file.people.count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Text

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private func message(for code: String) -> String {
        """
        Here's a Name That Face deck: \u{201C}\(deck.name)\u{201D}, \(deck.people.count) faces. \
        Open the app, tap New Deck, choose Enter a Code, and type \(code). \
        Don't have it yet? https://apps.apple.com/app/id6811378880
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
