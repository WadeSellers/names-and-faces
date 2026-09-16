import SwiftUI

/// What someone sees when a deck arrives in Messages, Mail, or Files and they
/// tap it — the deck itself, rather than a file size and a generic icon.
struct DeckPreviewView: View {
    let deckName: String
    let totalCount: Int
    let note: String?
    let faces: [Face]

    struct Face: Identifiable {
        let id: Int
        let name: String
        let image: UIImage?
    }

    private var hiddenCount: Int { max(0, totalCount - faces.count) }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Text(deckName)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("\(totalCount) \(totalCount == 1 ? "face" : "faces") · Name That Face deck")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 12) {
                ForEach(faces) { face in
                    VStack(spacing: 4) {
                        Group {
                            if let image = face.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text(face.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if hiddenCount > 0 {
                Text("+ \(hiddenCount) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            Text("To add it, tap the share button and choose Name That Face.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 16)
        }
        .fontDesign(.rounded)
    }
}

/// Shown when the file is damaged or isn't a deck at all.
struct DeckPreviewUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fontDesign(.rounded)
    }
}
