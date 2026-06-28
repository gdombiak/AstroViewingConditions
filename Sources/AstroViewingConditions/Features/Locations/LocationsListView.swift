import SharedCode
import SwiftUI
import MapKit
import SwiftData

public struct LocationsView: View {
    @Environment(\.modelContext) private var modelContext
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
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        beginRenaming(location)
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                        .onMove(perform: moveLocations)
                    }
                }
            }
            .navigationTitle("Locations")
            .task {
                persistCurrentOrderIfNeeded()
            }
            .toolbar {
                if !orderedLocations.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: toolbarPlacement) {
                    Button(action: { showingAddLocation = true }) {
                        Image(systemName: "plus")
                    }
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
            .alert("Rename Location", isPresented: $showingRenamePrompt, presenting: locationToRename) { location in
                TextField("Location name", text: $editedLocationName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    renameLocation(location)
                }
                .disabled(trimmedLocationName.isEmpty)
            } message: { _ in
                Text("Enter a new name for this saved location.")
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

struct LocationRow: View {
    let location: SavedLocation
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                
                Text(CoordinateFormatters.format(location.coordinate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let elevation = location.elevation {
                    Text("Elevation: \(Int(elevation))m")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .navigationTitle(location.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
}
