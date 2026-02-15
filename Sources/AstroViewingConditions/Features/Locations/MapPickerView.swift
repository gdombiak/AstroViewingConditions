import SwiftUI
import MapKit

struct MapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onSelect: (CLLocationCoordinate2D) -> Void
    
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var locationManager = LocationManager()
    
    var body: some View {
        NavigationStack {
            Map(position: $position, interactionModes: .all) {
                if let coordinate = selectedCoordinate {
                    Marker("Selected", coordinate: coordinate)
                }
                
                UserAnnotation()
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") {
                        if let coordinate = selectedCoordinate {
                            onSelect(coordinate)
                            dismiss()
                        }
                    }
                    .disabled(selectedCoordinate == nil)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        Button(action: centerOnUserLocation) {
                            Image(systemName: "location.fill")
                                .font(.title2)
                        }
                        Spacer()
                    }
                }
            }
        }
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
    MapPickerView { coordinate in
        print("Selected: \(coordinate)")
    }
}
