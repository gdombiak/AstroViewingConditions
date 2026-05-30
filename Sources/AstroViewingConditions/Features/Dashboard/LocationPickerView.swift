import SharedCode
import SwiftUI

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLocation: SelectedLocation?
    let currentLocation: SavedLocation?
    let savedLocations: [SavedLocation]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Current Location") {
                    Button(action: selectCurrentLocation) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("My Current Location")
                                    .font(.headline)
                                
                                if let location = currentLocation {
                                    Text(CoordinateFormatters.format(location.coordinate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Using device location")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedLocation?.source == .currentGPS {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                
                if !savedLocations.isEmpty {
                    Section("Saved Locations") {
                        ForEach(savedLocations) { location in
                            Button(action: { selectSavedLocation(location) }) {
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
                                    
                                    if selectedLocation?.source == .saved, selectedLocation?.id == location.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                    
                                    if location.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func selectCurrentLocation() {
        if let currentLocation {
            selectedLocation = SelectedLocation(
                source: .currentGPS,
                name: currentLocation.name,
                latitude: currentLocation.latitude,
                longitude: currentLocation.longitude
            )
        } else {
            selectedLocation = SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            )
        }
        
        if let selectedLocation {
            LocationStorageService.shared.saveSelectedLocation(selectedLocation)
        }
        dismiss()
    }
    
    private func selectSavedLocation(_ location: SavedLocation) {
        selectedLocation = SelectedLocation(
            source: .saved,
            id: location.id,
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        
        if let selectedLocation {
            LocationStorageService.shared.saveSelectedLocation(selectedLocation)
        }
        dismiss()
    }
}
