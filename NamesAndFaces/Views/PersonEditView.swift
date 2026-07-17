import SwiftUI
import SwiftData
import PhotosUI

/// Add or edit a single person: photo (camera or library) plus name.
/// Pass `person: nil` to create a new card in the deck.
struct PersonEditView: View {
    let deck: Deck
    let person: Person?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var imageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var confirmingDelete = false

    init(deck: Deck, person: Person?) {
        self.deck = deck
        self.person = person
        _name = State(initialValue: person?.name ?? "")
        _imageData = State(initialValue: person?.imageData)
    }

    private var canSave: Bool {
        imageData != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Group {
                                if let imageData {
                                    FaceImage(data: imageData)
                                } else {
                                    Rectangle()
                                        .fill(.quaternary)
                                        .overlay {
                                            Image(systemName: "person.crop.rectangle.badge.plus")
                                                .font(.largeTitle)
                                                .foregroundStyle(.secondary)
                                        }
                                }
                            }
                            .frame(width: 180, height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Menu {
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button {
                                        showingCamera = true
                                    } label: {
                                        Label("Take Photo", systemImage: "camera")
                                    }
                                }
                                Button {
                                    photoItem = nil
                                    showingPhotoPicker = true
                                } label: {
                                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                                }
                            } label: {
                                Text(imageData == nil ? "Add Photo" : "Change Photo")
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                }

                if let person, person.timesCorrect + person.timesMissed > 0 {
                    Section("Progress") {
                        LabeledContent("Correct", value: "\(person.timesCorrect)")
                        LabeledContent("Missed", value: "\(person.timesMissed)")
                        LabeledContent("Level", value: "\(person.box) of \(Person.maxBox)")
                    }
                }

                if person != nil {
                    Section {
                        Button("Delete Person", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(person == nil ? "Add Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        imageData = image.resized(maxDimension: 900).jpegData(compressionQuality: 0.8)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    imageData = image.resized(maxDimension: 900).jpegData(compressionQuality: 0.8)
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Delete this person?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deletePerson() }
            }
        }
    }

    @State private var showingPhotoPicker = false

    private func save() {
        guard let imageData else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let person {
            person.name = trimmed
            person.imageData = imageData
        } else {
            let newPerson = Person(name: trimmed, imageData: imageData)
            context.insert(newPerson)
            newPerson.deck = deck
        }
        dismiss()
    }

    private func deletePerson() {
        if let person {
            context.delete(person)
        }
        dismiss()
    }
}
