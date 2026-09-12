import SwiftUI
import SwiftData

/// The flashcard screen: a card stack with the next face peeking from
/// behind. Tap to reveal the name, swipe right for "got it," left for
/// "missed it." The rotation grows only when the user taps Add Face.
struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var session: StudySession
    @State private var revealed: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var correctPulse = 0
    @State private var missPulse = 0
    @State private var croppingPerson: Person?

    init(people: [Person]) {
        let session = StudySession(people: people)
        _session = State(initialValue: session)
        _revealed = State(initialValue: session.isIntroCard)
    }

    private struct StackCard: Identifiable {
        let person: Person
        let depth: Int
        var id: PersistentIdentifier { person.persistentModelID }
    }

    private var stack: [StackCard] {
        session.queue.prefix(2).enumerated().map { StackCard(person: $0.element, depth: $0.offset) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                if session.current != nil {
                    // At accessibility text sizes the card plus its chrome is
                    // taller than the screen, so the column scrolls rather than
                    // overlapping itself or squeezing the face down to a stamp.
                    if typeSize.isAccessibilitySize {
                        ScrollView {
                            studyColumn
                                .padding(.vertical, 12)
                        }
                    } else {
                        VStack(spacing: 18) {
                            Spacer(minLength: 0)
                            studyColumn
                            Spacer(minLength: 8)
                        }
                    }
                } else {
                    ContentUnavailableView("Nothing to study", systemImage: "person.crop.rectangle.stack")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { dismiss() }
                        .fontWeight(.medium)
                }
                ToolbarItem(placement: .principal) {
                    ProgressView(value: Double(session.inRotationCount),
                                 total: Double(max(session.totalPeople, 1)))
                        .tint(.accentColor)
                        .frame(width: 132)
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: revealed)
        .sensoryFeedback(.success, trigger: correctPulse)
        .sensoryFeedback(.error, trigger: missPulse)
        .sensoryFeedback(.impact(weight: .medium), trigger: session.inRotationCount)
        .fullScreenCover(item: $croppingPerson) { person in
            let originalData = person.originalImageData ?? person.imageData
            if let original = UIImage(data: originalData) {
                CropEditorView(image: original, initialCrop: person.crop) { crop, croppedImage in
                    person.originalImageData = originalData
                    person.crop = crop
                    person.imageData = crop == nil
                        ? originalData
                        : (croppedImage.jpegData(compressionQuality: 0.85) ?? person.imageData)
                }
            }
        }
    }

    private var studyColumn: some View {
        VStack(spacing: 18) {
            cardStack
            hintText
            rotationStatus
            answerButtons
        }
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.14), .clear],
                       startPoint: .top,
                       endPoint: .center)
            .ignoresSafeArea()
    }

    // MARK: - Card stack

    private var cardStack: some View {
        ZStack {
            ForEach(stack) { card in
                studyCard(for: card)
                    .zIndex(card.depth == 0 ? 2 : 1)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private func studyCard(for card: StackCard) -> some View {
        let isTop = card.depth == 0
        return FaceCard(person: card.person,
                        revealed: isTop && revealed,
                        isIntro: isTop && session.isIntroCard,
                        dragWidth: isTop ? dragOffset.width : 0,
                        onCrop: isTop ? { croppingPerson = card.person } : nil)
            .scaleEffect(isTop ? 1 : 0.93, anchor: .top)
            .offset(isTop ? dragOffset : CGSize(width: 0, height: 18))
            .opacity(isTop ? 1 : 0.65)
            .rotationEffect(.degrees(isTop ? Double(dragOffset.width) / 22 : 0))
            .onTapGesture {
                guard isTop else { return }
                withAnimation(.snappy) { revealed.toggle() }
            }
            .gesture(isTop ? dragGesture : nil)
            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .identity))
    }

    private var dragGesture: some Gesture {
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
                    withAnimation(.spring(duration: 0.35)) { dragOffset = .zero }
                }
            }
    }

    // MARK: - Under-card chrome

    private var hintText: some View {
        Group {
            if let person = session.current {
                if session.isIntroCard {
                    Text("New face — remember **\(person.name)**. Swipe right when you've got them.")
                } else if revealed {
                    Text("Swipe right if you knew it, left if you didn't.")
                } else {
                    Text("Say their name, then tap the card to check.")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 34)
        .padding(.horizontal, 32)
    }

    private var rotationStatus: some View {
        // At accessibility text sizes a row of label + button squeezes both into
        // ellipses, so they stack instead.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.inRotationCount) of \(session.totalPeople) in rotation")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(session.canAddMore
                     ? "\(session.waitingCount) waiting to be added"
                     : "Everyone's in — keep going!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(duration: 0.4)) {
                    session.introduceNext()
                    revealed = true
                    dragOffset = .zero
                }
            } label: {
                Label("Add Face", systemImage: "person.badge.plus")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!session.canAddMore)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 28)
    }

    private var answerButtons: some View {
        HStack(spacing: 56) {
            answerButton(symbol: "xmark", tint: .red) { complete(correct: false) }
            answerButton(symbol: "checkmark", tint: .green) { complete(correct: true) }
        }
    }

    private func answerButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.bold())
                .foregroundStyle(tint)
                .frame(width: 62, height: 62)
                .background(.background, in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Answering

    private func complete(correct: Bool) {
        if !session.isIntroCard {
            if correct { correctPulse += 1 } else { missPulse += 1 }
        }
        let exitX: CGFloat = correct ? 700 : -700
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGSize(width: exitX, height: dragOffset.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(duration: 0.4)) {
                session.answer(correct: correct)
                dragOffset = .zero
            }
            revealed = session.isIntroCard
        }
    }
}

// MARK: - Card

/// One face card: portrait, optional "New Face" ribbon, name scrim when
/// revealed, and green/red edge glow proportional to the drag.
private struct FaceCard: View {
    let person: Person
    let revealed: Bool
    let isIntro: Bool
    let dragWidth: CGFloat
    var onCrop: (() -> Void)?

    private var dragTint: Color? {
        guard !isIntro, abs(dragWidth) > 24 else { return nil }
        return dragWidth > 0 ? .green : .red
    }

    var body: some View {
        FaceImage(data: person.imageData)
            .overlay(alignment: .bottom) {
                if revealed {
                    nameScrim
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if isIntro {
                    Text("New Face")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                // The moment the name is showing is when you notice a sliver
                // of printed text in the photo — offer the fix right there.
                if revealed, let onCrop {
                    Button(action: onCrop) {
                        Image(systemName: "crop")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .padding(9)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .overlay {
                if let dragTint {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(dragTint.opacity(min(abs(dragWidth) / 600, 0.30)))
                }
            }
            .overlay(alignment: dragWidth >= 0 ? .topLeading : .topTrailing) {
                if let dragTint {
                    Text(dragTint == .green ? "Got It" : "Missed")
                        .font(.title3.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(dragTint.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(dragWidth >= 0 ? -8 : 8))
                        .padding(18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var nameScrim: some View {
        VStack(spacing: 0) {
            Text(person.name)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.top, 44)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .top,
                           endPoint: .bottom)
        )
    }
}
