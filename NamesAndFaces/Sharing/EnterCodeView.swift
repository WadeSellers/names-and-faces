import SwiftUI

/// Type the six digits someone gave you; get their deck, already cropped and
/// named. No account on either side.
struct EnterCodeView: View {
    /// Hands the fetched deck back so the caller can show the usual preview.
    let onRedeemed: (DeckFile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isFetching = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private var digits: String { String(code.filter(\.isNumber).prefix(6)) }
    private var isComplete: Bool { digits.count == 6 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image(systemName: "number.square")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    Text("Enter the 6-digit code someone shared with you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // One wide field with big, spaced digits: easy to read back
                // against a code written on a whiteboard.
                TextField("000000", text: $code)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(8)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($fieldFocused)
                    .padding(.vertical, 14)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: code) { _, newValue in
                        let cleaned = String(newValue.filter(\.isNumber).prefix(6))
                        if cleaned != newValue { code = cleaned }
                        // Only a digit the person types clears the message —
                        // emptying the field after a wrong code must not
                        // erase the explanation of what went wrong.
                        if !cleaned.isEmpty { errorMessage = nil }
                    }
                    .disabled(isFetching)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .navigationTitle("Enter a Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await fetch() }
                } label: {
                    Group {
                        if isFetching {
                            ProgressView()
                        } else {
                            Text("Get Deck")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isComplete || isFetching)
                .padding()
                .background(.bar)
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func fetch() async {
        isFetching = true
        defer { isFetching = false }
        do {
            let file = try await CodeShareClient.redeem(code: digits)
            dismiss()
            onRedeemed(file)
        } catch {
            errorMessage = error.localizedDescription
            code = ""
            fieldFocused = true
        }
    }
}
