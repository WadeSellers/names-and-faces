import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One group: the grid of faces, plus import, add, and study entry points.
struct DeckDetailView: View {
    @Bindable var deck: Deck

    @Environment(\.modelContext) private var context
    @Namespace private var studyZoom

    @State private var showingFileImporter = false
    @State private var importRequest: ImportRequest?
    @State private var showingStudy = false
    @State private var editingPerson: Person?
    @State private var showingAddPerson = false
    @State private var importError: String?

    private var sortedPeople: [Person] {
        deck.people.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var inRotationCount: Int {
        deck.people.filter { $0.introducedAt != nil }.count
    }

    var body: some View {
        Group {
            if deck.people.isEmpty {
                ContentUnavailableView {
                    Label("No People Yet", systemImage: "doc.viewfinder")
                } description: {
                    Text("Import a PDF of headshots and every face and name is pulled out automatically. Or add people one at a time.")
                } actions: {
                    Button("Import a PDF") { showingFileImporter = true }
                        .buttonStyle(.borderedProminent)
                    Button("Add Someone Manually") { showingAddPerson = true }
                }
            } else {
                ScrollView {
                    statsHeader

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                        ForEach(sortedPeople) { person in
                            Button {
                                editingPerson = person
                            } label: {
                                PersonCell(person: person)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 90)
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Import a PDF", systemImage: "doc.viewfinder")
                    }
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    if !deck.people.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            withAnimation {
                                for person in deck.people {
                                    person.resetProgress()
                                }
                            }
                        } label: {
                            Label("Reset Progress", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !deck.people.isEmpty {
                Button {
                    showingStudy = true
                } label: {
                    Label("Study", systemImage: "rectangle.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 6)
                .matchedTransitionSource(id: "study", in: studyZoom)
                .padding()
                .background(.bar)
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                importRequest = ImportRequest(url: url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import Failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $importRequest) { request in
            ImportReviewView(deck: deck, url: request.url)
        }
        .sheet(item: $editingPerson) { person in
            PersonEditView(deck: deck, person: person)
        }
        .sheet(isPresented: $showingAddPerson) {
            PersonEditView(deck: deck, person: nil)
        }
        .fullScreenCover(isPresented: $showingStudy) {
            StudyView(people: deck.people)
                .navigationTransition(.zoom(sourceID: "study", in: studyZoom))
        }
    }

    private var statsHeader: some View {
        HStack(spacing: 0) {
            stat(value: "\(deck.people.count)", label: "People")
            divider
            stat(value: "\(inRotationCount)", label: "In Rotation")
            divider
            stat(value: "\(Int(deck.mastery * 100))%", label: "Mastered")
        }
        .padding(.vertical, 12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 30)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Cell

private struct PersonCell: View {
    let person: Person

    var body: some View {
        VStack(spacing: 7) {
            FaceImage(data: person.imageData)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if person.introducedAt != nil {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                            .padding(7)
                    }
                }
                .shadow(color: .black.opacity(0.10), radius: 6, y: 3)

            Text(person.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            LevelIndicator(box: person.box)
        }
    }
}

/// Five tiny segments showing the Leitner level at a glance.
private struct LevelIndicator: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Person.maxBox, id: \.self) { index in
                Capsule()
                    .fill(index < box ? Color.accentColor : Color(.quaternarySystemFill))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 10)
    }
}

/// Renders stored JPEG data, filling its container.
struct FaceImage: View {
    let data: Data

    var body: some View {
        GeometryReader { proxy in
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}
