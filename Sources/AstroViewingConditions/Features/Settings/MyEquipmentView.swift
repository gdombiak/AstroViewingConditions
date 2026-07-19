import SharedCode
import SwiftData
import SwiftUI

struct MyEquipmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EquipmentItem.name) private var equipment: [EquipmentItem]

    @State private var showingAddEquipment = false
    @State private var deletionErrorMessage: String?

    var body: some View {
        List {
            Section("Always Available") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Naked Eye", systemImage: "eye")
                        .font(.subheadline)
                    Text("Available for every observing session. No setup required.")
                        .font(.caption)
                        .appSecondaryForeground()
                }
            }
            .appListRowSurface()

            Section("Your Equipment") {
                if equipment.isEmpty {
                    ContentUnavailableView {
                        Label("No Equipment Yet", systemImage: "binoculars")
                    } description: {
                        Text("Add the binoculars or telescopes you use for observing.")
                    } actions: {
                        Button("Add Equipment") {
                            showingAddEquipment = true
                        }
                    }
                } else {
                    ForEach(equipment) { item in
                        NavigationLink {
                            EquipmentEditorView(item: item)
                        } label: {
                            EquipmentRow(item: item)
                        }
                    }
                    .onDelete(perform: deleteEquipment)
                }
            }
            .appListRowSurface()
        }
        .appListBackground()
        .appNavigationTitle("My Equipment")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddEquipment = true
                } label: {
                    Image(systemName: "plus")
                }
                .appToolbarButtonStyle()
                .accessibilityLabel("Add equipment")
            }
        }
        .sheet(isPresented: $showingAddEquipment) {
            NavigationStack {
                EquipmentEditorView()
            }
        }
        .alert("Cannot Delete Equipment", isPresented: deletionErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionErrorMessage ?? "The equipment could not be deleted. Please try again.")
        }
    }

    private func deleteEquipment(at offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(equipment[offset])
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete equipment: \(error)")
            modelContext.rollback()
            deletionErrorMessage = "The equipment could not be deleted. Please try again."
        }
    }

    private var deletionErrorAlert: Binding<Bool> {
        Binding(
            get: { deletionErrorMessage != nil },
            set: { if !$0 { deletionErrorMessage = nil } }
        )
    }
}

private struct EquipmentRow: View {
    let item: EquipmentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.subheadline)
            Text("\(item.type.displayName) · \(item.detailText)")
                .font(.caption)
                .appSecondaryForeground()
        }
    }
}

private struct EquipmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let item: EquipmentItem?
    @State private var name: String
    @State private var type: EquipmentType
    @State private var magnification: String
    @State private var aperture: String
    @State private var apertureUnit: EquipmentApertureUnit = .millimeters
    @State private var validationMessage: String?

    init(item: EquipmentItem? = nil) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _type = State(initialValue: item?.type ?? .binoculars)
        let apertureUnit = item?.apertureUnit ?? .millimeters
        _apertureUnit = State(initialValue: apertureUnit)
        _magnification = State(initialValue: item?.magnification.map { EquipmentFormatting.decimalText($0, locale: .current) } ?? "")
        _aperture = State(initialValue: item?.apertureMillimeters.map {
            EquipmentFormatting.apertureInputText(
                fromMillimeters: $0,
                unit: apertureUnit,
                locale: .current
            )
        } ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Type", selection: $type) {
                    ForEach(EquipmentType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            if type == .binoculars {
                Section("Optics") {
                    TextField("Magnification", text: $magnification)
                        .keyboardType(.decimalPad)
                    apertureFields
                }
            } else if type == .visualTelescope {
                Section("Optics") {
                    apertureFields
                }
            } else {
                Section("Optics") {
                    apertureFields
                    Text("Aperture is optional for Smart / EAA telescopes.")
                        .font(.caption)
                        .appSecondaryForeground()
                }
            }
        }
        .appListBackground()
        .appNavigationTitle(item == nil ? "Add Equipment" : "Edit Equipment")
        .toolbar {
            if item == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appToolbarButtonStyle()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .appToolbarButtonStyle()
            }
        }
        .alert("Cannot Save Equipment", isPresented: validationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "Check the equipment details and try again.")
        }
    }

    private var apertureFields: some View {
        Group {
            TextField("Aperture", text: $aperture)
                .keyboardType(.decimalPad)
            Picker("Unit", selection: $apertureUnit) {
                ForEach(EquipmentApertureUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: apertureUnit) { previousUnit, newUnit in
                guard let convertedText = EquipmentFormatting.convertedApertureInputText(
                    aperture,
                    from: previousUnit,
                    to: newUnit,
                    locale: .current
                ) else {
                    return
                }
                aperture = convertedText
            }
        }
    }

    private var validationAlert: Binding<Bool> {
        Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )
    }

    private func save() {
        do {
            let draft = try EquipmentDraft(
                name: name,
                type: type,
                magnification: numericValue(
                    from: magnification,
                    error: .invalidMagnification
                ),
                aperture: numericValue(
                    from: aperture,
                    error: .invalidAperture
                ),
                apertureUnit: apertureUnit
            )

            if let item {
                item.apply(draft)
            } else {
                modelContext.insert(EquipmentItem(draft: draft))
            }
            try modelContext.save()
            dismiss()
        } catch let error as EquipmentValidationError {
            validationMessage = error.message
        } catch {
            validationMessage = "The equipment could not be saved. Please try again."
        }
    }

    private func numericValue(
        from text: String,
        error: EquipmentValidationError
    ) throws -> Double? {
        switch EquipmentFormatting.decimalInput(from: text, locale: .current) {
        case .blank:
            return nil
        case let .value(value):
            return value
        case .invalid:
            throw error
        }
    }
}
