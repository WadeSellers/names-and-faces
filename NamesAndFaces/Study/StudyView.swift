import SwiftUI

/// The flashcard screen: face up front, tap to toggle the name,
/// swipe right for "got it," left for "missed it."
struct StudyView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session: StudySession
    @State private var revealed = false
    @State private var dragOffset: CGSize = .zero

    init(people: [Person]) {
        _session = State(initialValue: StudySession(people: people))
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.isFinished {
                    summary
                } else if let person = session.current {
                    card(for: person)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !session.isFinished {
                        ProgressView(value: session.progress)
                            .frame(width: 140)
                    }
                }
            }
        }
    }

    // MARK: - Card

    private func card(for person: Person) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            ZStack {
                FaceImage(data: person.imageData)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .bottom) {
                        if revealed {
                            Text(person.name)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(.thinMaterial)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
                    .overlay {
                        swipeBadge
                    }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width) / 20))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) { revealed.toggle() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if value.translation.width > 110 {
                            complete(correct: true)
                        } else if value.translation.width < -110 {
                            complete(correct: false)
                        } else {
                            withAnimation(.spring) { dragOffset = .zero }
                        }
                    }
            )
            .id(ObjectIdentifier(person))

            Text(revealed ? "Swipe right if you knew it, left if you didn't." : "Say their name, then tap the card to check.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 60) {
                Button {
                    complete(correct: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2.bold())
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .tint(.red)

                Button {
                    complete(correct: true)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.title2.bold())
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .tint(.green)
            }

            Spacer(minLength: 12)
        }
    }

    @ViewBuilder
    private var swipeBadge: some View {
        if dragOffset.width > 40 {
            badge("Got It", color: .green)
        } else if dragOffset.width < -40 {
            badge("Missed", color: .red)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title2.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }

    private func complete(correct: Bool) {
        let exitX: CGFloat = correct ? 700 : -700
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = CGSize(width: exitX, height: dragOffset.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            session.answer(correct: correct)
            revealed = false
            dragOffset = .zero
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: session.missedPeople.isEmpty ? "trophy.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Session Complete")
                .font(.title.bold())

            Text("\(session.firstTryCorrect) of \(session.totalPeople) on the first try")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !session.missedPeople.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Worth another look")
                        .font(.subheadline.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(session.missedPeople) { person in
                                VStack(spacing: 4) {
                                    FaceImage(data: person.imageData)
                                        .frame(width: 64, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(person.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}
