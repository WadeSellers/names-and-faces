import SwiftUI
import SwiftData
import PhotosUI

/// Add or edit a single person: photo (camera or library), crop, and name.
/// Pass `person: nil` to create a new card in the deck.
struct PersonEditView: View {
    let deck: Deck
    let person: Person?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var displayData: Data?
    @State private var originalData: Data?
    @State private var crop: CropRegion?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingCrop = false
    @State private var confirmingDelete = false

    init(deck: Deck, person: Person?) {
        self.deck = deck
        self.person = person
        _name = State(initialValue: person?.name ?? "")
        _displayData = State(initialValue: person?.imageData)
        _originalData = State(initialValue: person?.originalImageData ?? person?.imageData)
        _crop = State(initialValue: person?.crop)
    }

    private var canSave: Bool {
        displayData != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 14) {
                            Group {
                                if let displayData {
                                    FaceImage(data: displayData)
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
                            .frame(width: 190, height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                            HStack(spacing: 10) {
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
                                    Label(displayData == nil ? "Add Photo" : "Replace",
                                          systemImage: "photo")
                                        .font(.subheadline.bold())
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)

                                if originalData != nil {
                                    Button {
                                        showingCrop = true
                                    } label: {
                                        Label("Crop", systemImage: "crop")
                                            .font(.subheadline.bold())
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                }
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
                        if person.introducedAt != nil {
                            LabeledContent("In rotation", value: "Yes")
                        }
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
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        setNewPhoto(image)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    setNewPhoto(image)
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingCrop) {
                if let originalData, let original = UIImage(data: originalData) {
                    CropEditorView(image: original, initialCrop: crop) { region, croppedImage in
                        withAnimation(.snappy) {
                            crop = region
                            displayData = region == nil
                                ? originalData
                                : croppedImage.jpegData(compressionQuality: 0.85)
                        }
                    }
                }
            }
            .confirmationDialog("Delete this person?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deletePerson() }
            }
        }
    }

    private func setNewPhoto(_ image: UIImage) {
        let data = image.resized(maxDimension: 900).jpegData(compressionQuality: 0.8)
        originalData = data
        displayData = data
        crop = nil
    }

    private func save() {
        guard let displayData else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let person {
            person.name = trimmed
            person.imageData = displayData
            person.originalImageData = originalData
            person.crop = crop
        } else {
            let newPerson = Person(name: trimmed, imageData: displayData)
            newPerson.originalImageData = originalData
            newPerson.crop = crop
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
