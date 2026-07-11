import SharedCode
import SwiftUI
import MapKit
import SwiftData

public struct LocationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette
    @Query private var savedLocations: [SavedLocation]
    
    @State private var showingAddLocation = false
    @State private var locationToDelete: SavedLocation?
    @State private var showingDeleteConfirmation = false
    @State private var locationToRename: SavedLocation?
    @State private var editedLocationName = ""
    @State private var showingRenamePrompt = false
    @State private var selectedLocation: SavedLocation?
    @State private var showingLocationMap = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if orderedLocations.isEmpty {
                        ContentUnavailableView {
                            Label("No Saved Locations", systemImage: "mappin.slash")
                        } description: {
                            Text("Add your favorite stargazing spots for quick access")
                        } actions: {
                            Button("Add Location") {
                                showingAddLocation = true
                            }
                        }
                    } else {
                        ForEach(orderedLocations) { location in
                            LocationRow(location: location)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedLocation = location
                                    showingLocationMap = true
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        locationToDelete = location
                                        showingDeleteConfirmation = true
                                    } label: {
                                        swipeActionLabel("Delete", systemImage: "trash", destructive: true)
                                    }
                                    .tint(deleteActionTint)

                                    Button {
                                        beginRenaming(location)
                                    } label: {
                                        swipeActionLabel("Rename", systemImage: "pencil", destructive: false)
                                    }
                                    .tint(renameActionTint)
                                }
                        }
                        .onMove(perform: moveLocations)
                    }
                }
                .appListRowSurface()
            }
            .appListBackground()
            .appNavigationTitle("Locations")
            .task {
                persistCurrentOrderIfNeeded()
            }
            .toolbar {
                if !orderedLocations.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .appToolbarButtonStyle()
                    }
                }
                ToolbarItem(placement: toolbarPlacement) {
                    Button(action: { showingAddLocation = true }) {
                        Image(systemName: "plus")
                    }
                    .appToolbarButtonStyle()
                }
            }
            .sheet(isPresented: $showingAddLocation) {
                LocationSearchView()
            }
            .sheet(item: $selectedLocation) { location in
                LocationMapView(location: location)
            }
            .alert("Delete Location?", isPresented: $showingDeleteConfirmation, presenting: locationToDelete) { location in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteLocation(location)
                }
            } message: { location in
                Text("Are you sure you want to delete \"\(location.name)\"?")
            }
            .alert("Rename Location", isPresented: systemRenamePrompt, presenting: locationToRename) { location in
                TextField("Location name", text: $editedLocationName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    renameLocation(location)
                }
                .disabled(trimmedLocationName.isEmpty)
            } message: { _ in
                Text("Enter a new name for this saved location.")
            }
            .overlay {
                if palette.appearance == .field,
                   showingRenamePrompt,
                   let location = locationToRename {
                    FieldRenameLocationDialog(
                        name: $editedLocationName,
                        canSave: !trimmedLocationName.isEmpty,
                        cancel: dismissRenamePrompt,
                        save: {
                            renameLocation(location)
                            dismissRenamePrompt()
                        }
                    )
                }
            }
        }
    }
    
    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .automatic
        #endif
    }

    private var orderedLocations: [SavedLocation] {
        SavedLocation.ordered(savedLocations)
    }

    private var systemRenamePrompt: Binding<Bool> {
        Binding(
            get: { palette.appearance != .field && showingRenamePrompt },
            set: { showingRenamePrompt = $0 }
        )
    }

    private var renameActionTint: Color {
        palette.appearance == .field ? palette.secondaryActionBackground : .blue
    }

    private var deleteActionTint: Color {
        palette.appearance == .field ? palette.destructiveActionBackground : .red
    }

    @ViewBuilder
    private func swipeActionLabel(
        _ title: String,
        systemImage: String,
        destructive: Bool
    ) -> some View {
        if palette.appearance == .field {
            Label(title, systemImage: systemImage)
                .foregroundStyle(destructive ? palette.primaryActionLabel : palette.secondaryText)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private func persistCurrentOrderIfNeeded() {
        guard orderedLocations.contains(where: { $0.sortPosition == nil }) else { return }
        saveOrder(orderedLocations)
    }

    private func moveLocations(from source: IndexSet, to destination: Int) {
        var reordered = orderedLocations
        reordered.move(fromOffsets: source, toOffset: destination)
        saveOrder(reordered)
    }

    private func saveOrder(_ locations: [SavedLocation]) {
        for (position, location) in locations.enumerated() {
            location.sortPosition = position
        }

        do {
            try modelContext.save()
            let cachedLocations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
            WatchConnectivityService.shared.sendLocationsToWatch(cachedLocations)
        } catch {
            print("Failed to save location order: \(error)")
        }
    }
    
    private func deleteLocation(_ location: SavedLocation) {
        modelContext.delete(location)
        do {
            try modelContext.save()
            let locations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
            WatchConnectivityService.shared.sendLocationsToWatch(locations)
        } catch {
            print("Failed to save after deleting location: \(error)")
        }
    }
    
    private var trimmedLocationName: String {
        editedLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginRenaming(_ location: SavedLocation) {
        locationToRename = location
        editedLocationName = location.name
        showingRenamePrompt = true
    }

    private func dismissRenamePrompt() {
        showingRenamePrompt = false
        locationToRename = nil
    }

    private func renameLocation(_ location: SavedLocation) {
        let newName = trimmedLocationName
        guard !newName.isEmpty else { return }

        location.name = newName

        do {
            try modelContext.save()

            if var selected = LocationStorageService.shared.loadSelectedLocation(),
               selected.source == .saved,
               selected.id == location.id {
                selected.name = newName
                LocationStorageService.shared.saveSelectedLocation(selected)
            }

            let locations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
            WatchConnectivityService.shared.sendLocationsToWatch(locations)
        } catch {
            print("Failed to rename location: \(error)")
        }
    }
}

private struct FieldRenameLocationDialog: View {
    @Environment(\.appPalette) private var palette
    @Binding var name: String
    let canSave: Bool
    let cancel: () -> Void
    let save: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            palette.appBackground.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Location")
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter a new name for this saved location.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)

                TextField(
                    "",
                    text: $name,
                    prompt: Text("Location name").foregroundStyle(palette.tertiaryText)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(palette.primaryText)
                .tint(palette.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(palette.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isNameFocused ? palette.accent.opacity(0.8) : palette.border, lineWidth: isNameFocused ? 2 : 1)
                }
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit {
                    if canSave { save() }
                }

                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel, action: cancel)
                        .appSecondaryActionStyle()
                        .frame(maxWidth: .infinity)

                    Button("Save", action: save)
                        .appPrimaryActionStyle()
                        .disabled(!canSave)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(palette.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(palette.border, lineWidth: 1)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
        }
        .onAppear { isNameFocused = true }
    }
}

struct LocationRow: View {
    let location: SavedLocation
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                
                Text(CoordinateFormatters.format(location.coordinate))
                    .font(.caption)
                    .appSecondaryForeground()
                
                if let elevation = location.elevation {
                    Text("Elevation: \(Int(elevation))m")
                        .font(.caption2)
                        .appTertiaryForeground()
                }
            }
            
            Spacer()
            
            if location.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LocationMapView: View {
    @Environment(\.dismiss) private var dismiss
    let location: SavedLocation
    
    @State private var position: MapCameraPosition
    
    init(location: SavedLocation) {
        self.location = location
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))
    }
    
    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }
    
    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Marker(location.name, coordinate: coordinate)
                UserAnnotation()
            }
            .appScreenBackground()
            .appMapStyle()
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .appNavigationTitle(location.name, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LocationsView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
        .appAppearance(fieldModeEnabled: true)
}
