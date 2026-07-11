import SharedCode
import SwiftUI
import MapKit

struct MapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPalette) private var palette
    
    let onSelect: (String, CLLocationCoordinate2D) -> Void
    
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var locationName = ""
    @State private var locationManager = LocationManager()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { reader in
                    Map(position: $position, interactionModes: .all) {
                        if let coordinate = selectedCoordinate {
                            Marker("Selected", coordinate: coordinate)
                        }
                        
                        UserAnnotation()
                    }
                    .appMapStyle()
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onTapGesture { location in
                        if let coordinate = reader.convert(location, from: .local) {
                            selectedCoordinate = coordinate
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    TextField("Location name", text: $locationName)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button(action: centerOnUserLocation) {
                            Image(systemName: "location.fill")
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Select") {
                            if let coordinate = selectedCoordinate {
                                let name = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
                                onSelect(name.isEmpty ? "Custom Location" : name, coordinate)
                                dismiss()
                            }
                        }
                        .appPrimaryActionStyle()
                        .disabled(selectedCoordinate == nil)
                    }
                }
                .padding()
                .background {
                    if palette.appearance == .field {
                        palette.elevatedBackground.opacity(0.96)
                    } else {
                        Rectangle().fill(.ultraThinMaterial)
                    }
                }
            }
            .appNavigationTitle("Select Location", displayMode: .inline)
        }
        .appScreenBackground()
    }
    
    private func centerOnUserLocation() {
        Task {
            if locationManager.isAuthorized {
                do {
                    let coordinate = try await locationManager.getCurrentLocation()
                    withAnimation {
                        position = .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        ))
                        selectedCoordinate = coordinate
                    }
                } catch {
                    // Handle error silently
                }
            } else {
                locationManager.requestAuthorization()
            }
        }
    }
}

#Preview {
    MapPickerView { name, coordinate in
        print("Selected: \(name) at \(coordinate)")
    }
}
