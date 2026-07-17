import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One cohort: the grid of faces, plus import, add, and study entry points.
struct DeckDetailView: View {
    @Bindable var deck: Deck

    @Environment(\.modelContext) private var context

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

    var body: some View {
        Group {
            if deck.people.isEmpty {
                ContentUnavailableView {
                    Label("No People Yet", systemImage: "doc.viewfinder")
                } description: {
                    Text("Import the cohort PDF and every face and name will be pulled out automatically.")
                } actions: {
                    Button("Import PDF") { showingFileImporter = true }
                        .buttonStyle(.borderedProminent)
                    Button("Add Person Manually") { showingAddPerson = true }
                }
            } else {
                ScrollView {
                    HStack(spacing: 12) {
                        Text("\(deck.people.count) \(deck.people.count == 1 ? "person" : "people")")
                        Text("\(Int(deck.mastery * 100))% mastered")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

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
                    .padding()
                    .padding(.bottom, 80)
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
                        Label("Import PDF", systemImage: "doc.viewfinder")
                    }
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    if !deck.people.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            for person in deck.people {
                                person.resetProgress()
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
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
        }
    }
}

private struct PersonCell: View {
    let person: Person

    var body: some View {
        VStack(spacing: 6) {
            FaceImage(data: person.imageData)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    ProgressView(value: person.mastery)
                        .tint(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }

            Text(person.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
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
