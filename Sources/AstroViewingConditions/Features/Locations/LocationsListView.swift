import SwiftUI
import SwiftData

public struct LocationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedLocation.dateAdded, order: .reverse) private var savedLocations: [SavedLocation]
    
    @State private var showingAddLocation = false
    @State private var locationToDelete: SavedLocation?
    @State private var showingDeleteConfirmation = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if savedLocations.isEmpty {
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
                        ForEach(savedLocations) { location in
                            LocationRow(location: location)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        locationToDelete = location
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Locations")
            .toolbar {
                ToolbarItem(placement: toolbarPlacement) {
                    Button(action: { showingAddLocation = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddLocation) {
                LocationSearchView()
            }
            .alert("Delete Location?", isPresented: $showingDeleteConfirmation, presenting: locationToDelete) { location in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteLocation(location)
                }
            } message: { location in
                Text("Are you sure you want to delete \"\(location.name)\"?")
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
    
    private func deleteLocation(_ location: SavedLocation) {
        modelContext.delete(location)
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

#Preview {
    LocationsView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
