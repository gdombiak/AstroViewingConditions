import SharedCode
import SwiftData
import SwiftUI

@MainActor
enum EquipmentPersistence {
    @discardableResult
    static func save(
        draft: EquipmentDraft,
        editing item: EquipmentItem?,
        in modelContext: ModelContext,
        performSave: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> EquipmentItem {
        let originalSnapshot = item?.persistedSnapshot
        let savedItem: EquipmentItem
        if let item {
            item.apply(draft)
            savedItem = item
        } else {
            let newItem = EquipmentItem(draft: draft)
            modelContext.insert(newItem)
            savedItem = newItem
        }

        do {
            try performSave(modelContext)
            return savedItem
        } catch {
            if let item, let originalSnapshot {
                item.restore(originalSnapshot)
            } else {
                modelContext.delete(savedItem)
            }
            throw error
        }
    }
}

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

enum EquipmentRowPresentation {
    static func unavailableColor(palette: AppPalette) -> Color {
        palette.statusColor(.caution)
    }
}

private struct EquipmentRow: View {
    @Environment(\.appPalette) private var palette
    let item: EquipmentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.inventoryDisplayName)
                .font(.subheadline)
            if item.persistedValidation.isAvailable, let type = item.type {
                Text("\(type.displayName) · \(item.detailText)")
                    .font(.caption)
                    .appSecondaryForeground()
            } else {
                Label("Unavailable — repair or delete", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(EquipmentRowPresentation.unavailableColor(palette: palette))
            }
        }
    }
}

private struct EquipmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette

    private let item: EquipmentItem?
    @State private var name: String
    @State private var type: EquipmentType?
    @State private var magnification: String
    @State private var aperture: String
    @State private var apertureUnit: EquipmentApertureUnit?
    @State private var fieldErrors: [EquipmentFormField: String] = [:]
    @State private var saveErrorMessage: String?

    init(item: EquipmentItem? = nil) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _type = State(initialValue: item == nil ? .binoculars : item?.type)
        let apertureUnit: EquipmentApertureUnit? = item == nil ? .millimeters : item?.apertureUnit
        _apertureUnit = State(initialValue: apertureUnit)
        _magnification = State(initialValue: item?.magnification.map { EquipmentFormatting.decimalText($0, locale: .current) } ?? "")
        _aperture = State(initialValue: item.map {
            EquipmentFormatting.apertureInputText(
                fromMillimeters: $0.apertureMillimeters,
                unit: apertureUnit ?? .millimeters,
                locale: .current
            )
        } ?? "")
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(EquipmentFormPresentation.label(for: .name))
                        .font(.subheadline)
                    TextField("Seestar S30 Pro", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(EquipmentFormPresentation.nameAccessibilityLabel)
                        .onChange(of: name) { _, _ in
                            fieldErrors[.name] = nil
                        }
                }
                fieldError(for: .name)

                Picker("Type", selection: $type) {
                    Text("Select type").tag(nil as EquipmentType?)
                    ForEach(EquipmentType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                }
                .onChange(of: type) { _, newType in
                    guard let newType else { return }
                    magnification = EquipmentFormPresentation.magnificationText(
                        afterChangingTo: newType,
                        currentText: magnification
                    )
                    fieldErrors[.magnification] = nil
                    fieldErrors[.aperture] = nil
                }
            }

            if type == .binoculars {
                Section("Optics") {
                    magnificationField
                    apertureFields
                    if let binocularSizeSummary {
                        Text(binocularSizeSummary)
                            .font(.caption)
                            .appSecondaryForeground()
                            .accessibilityLabel(
                                binocularSizeSummary
                                    .replacingOccurrences(of: "Binocular size: ", with: "Binocular size ")
                                    .replacingOccurrences(of: "×", with: " by ")
                            )
                    }
                }
            } else if type == .visualTelescope {
                Section("Optics") {
                    apertureFields
                }
            } else {
                Section("Optics") {
                    apertureFields
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
        .alert("Cannot Save Equipment", isPresented: saveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "The equipment could not be saved. Please try again.")
        }
    }

    private var magnificationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(EquipmentFormPresentation.label(for: .magnification))
                .font(.subheadline)
            TextField("10", text: $magnification)
                .keyboardType(.decimalPad)
                .accessibilityLabel("Binocular magnification")
                .accessibilityHint("Enter the first number in a binocular size such as 10 by 50.")
                .onChange(of: magnification) { _, _ in
                    fieldErrors[.magnification] = nil
                }
            fieldError(for: .magnification)
            Text("Enter the first number in 10×50 binoculars.")
                .font(.caption)
                .appSecondaryForeground()
        }
    }

    private var apertureFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(EquipmentFormPresentation.label(for: .aperture))
                .font(.subheadline)
            TextField("50", text: $aperture)
                .keyboardType(.decimalPad)
                .accessibilityLabel("Aperture")
                .onChange(of: aperture) { _, _ in
                    fieldErrors[.aperture] = nil
                }
            fieldError(for: .aperture)

            if type == .binoculars {
                if let apertureUnit {
                    Text(EquipmentFormPresentation.binocularApertureHelperText(for: apertureUnit))
                        .font(.caption)
                        .appSecondaryForeground()
                }
            } else if type == .smartTelescope {
                Text("Enter the aperture of the main astronomical lens or telescope.")
                    .font(.caption)
                    .appSecondaryForeground()
            }

            Picker("Aperture unit", selection: $apertureUnit) {
                Text("Select unit").tag(nil as EquipmentApertureUnit?)
                ForEach(EquipmentApertureUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(Optional(unit))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Aperture unit")
            .onChange(of: apertureUnit) { previousUnit, newUnit in
                guard let previousUnit, let newUnit else { return }
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

    private var binocularSizeSummary: String? {
        guard let apertureUnit else { return nil }
        return EquipmentFormPresentation.binocularSizeSummary(
            magnificationText: magnification,
            apertureText: aperture,
            apertureUnit: apertureUnit,
            locale: .current
        )
    }

    @ViewBuilder
    private func fieldError(for field: EquipmentFormField) -> some View {
        if let error = fieldErrors[field] {
            Text(error)
                .font(.caption)
                .foregroundStyle(palette.statusColor(.negative))
        }
    }

    private var saveErrorAlert: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

    private func save() {
        guard let type else {
            saveErrorMessage = "Choose the correct equipment type before saving this record."
            return
        }
        guard let apertureUnit else {
            saveErrorMessage = "Choose the correct aperture unit before saving this record."
            return
        }
        var errors: [EquipmentFormField: String] = [:]
        let parsedMagnification = numericValue(
            from: magnification,
            field: .magnification,
            equipmentType: type,
            errors: &errors
        )
        let parsedAperture = numericValue(
            from: aperture,
            field: .aperture,
            equipmentType: type,
            errors: &errors
        )

        for error in EquipmentValidation.validationErrors(
            name: name,
            type: type,
            magnification: parsedMagnification,
            aperture: parsedAperture,
            apertureUnit: apertureUnit
        ) where errors[error.field] == nil {
            errors[error.field] = error.inlineMessage(for: type)
        }

        guard errors.isEmpty else {
            fieldErrors = errors
            return
        }

        do {
            let draft = try EquipmentDraft(
                name: name,
                type: type,
                magnification: parsedMagnification,
                aperture: parsedAperture,
                apertureUnit: apertureUnit
            )

            try EquipmentPersistence.save(draft: draft, editing: item, in: modelContext)
            dismiss()
        } catch let error as EquipmentValidationError {
            fieldErrors = [error.field: error.inlineMessage(for: type)]
        } catch {
            print("Failed to save equipment: \(error)")
            saveErrorMessage = "The equipment could not be saved. Please try again."
        }
    }

    private func numericValue(
        from text: String,
        field: EquipmentFormField,
        equipmentType: EquipmentType,
        errors: inout [EquipmentFormField: String]
    ) -> Double? {
        switch EquipmentFormatting.decimalInput(from: text, locale: .current) {
        case .blank:
            return nil
        case let .value(value):
            return value
        case .invalid:
            if equipmentType == .binoculars, EquipmentFormatting.isCombinedBinocularInput(text) {
                errors[field] = "Enter magnification and aperture in separate fields."
            } else {
                let error: EquipmentValidationError = field == .magnification
                    ? .invalidMagnification
                    : .invalidAperture
                errors[field] = error.inlineMessage(for: equipmentType)
            }
            return nil
        }
    }
}
