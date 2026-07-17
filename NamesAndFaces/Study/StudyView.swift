import SwiftUI

/// The flashcard screen: face up front, tap to toggle the name,
/// swipe right for "got it," left for "missed it." The rotation grows
/// only when the user taps Add Face; new faces introduce themselves
/// with their name showing.
struct StudyView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session: StudySession
    @State private var revealed: Bool
    @State private var dragOffset: CGSize = .zero

    init(people: [Person]) {
        let session = StudySession(people: people)
        _session = State(initialValue: session)
        _revealed = State(initialValue: session.isIntroCard)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let person = session.current {
                    card(for: person)
                } else {
                    ContentUnavailableView("Nothing to study", systemImage: "person.crop.rectangle.stack")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    ProgressView(value: Double(session.inRotationCount), total: Double(max(session.totalPeople, 1)))
                        .frame(width: 140)
                }
            }
        }
    }

    // MARK: - Card

    private func card(for person: Person) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ZStack {
                FaceImage(data: person.imageData)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .top) {
                        if session.isIntroCard {
                            Text("New Face")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(.top, 12)
                        }
                    }
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

            Text(hint(for: person))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            rotationStatus

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

    private func hint(for person: Person) -> String {
        if session.isIntroCard {
            return "New face — remember \(person.name). Swipe right when you've got them."
        }
        return revealed
            ? "Swipe right if you knew it, left if you didn't."
            : "Say their name, then tap the card to check."
    }

    // MARK: - Rotation status

    private var rotationStatus: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.inRotationCount) of \(session.totalPeople) in rotation")
                    .font(.subheadline.bold())
                Text(session.canAddMore
                     ? "\(session.waitingCount) waiting to be added"
                     : "Everyone's in — keep going!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.snappy) {
                    session.introduceNext()
                    revealed = true
                    dragOffset = .zero
                }
            } label: {
                Label("Add Face", systemImage: "person.badge.plus")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canAddMore)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var swipeBadge: some View {
        if session.isIntroCard {
            EmptyView()
        } else if dragOffset.width > 40 {
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
            revealed = session.isIntroCard
            dragOffset = .zero
        }
    }
}
