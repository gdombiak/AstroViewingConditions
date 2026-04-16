import SwiftUI
import SharedCode

struct LocationSelectorView: View {
    let locations: [WatchLocationItem]
    var selectedLocation: WatchLocationItem
    let onSelectionChanged: (WatchLocationItem) -> Void

    var body: some View {
        NavigationLink(destination: LocationListView(locations: locations, selectedLocation: selectedLocation, onSelectionChanged: onSelectionChanged)) {
            Label(selectedLocation.name, systemImage: "location.circle")
                .font(.headline)
        }
    }
}

struct LocationListView: View {
    let locations: [WatchLocationItem]
    var selectedLocation: WatchLocationItem
    let onSelectionChanged: (WatchLocationItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(locations) { location in
            Button {
                onSelectionChanged(location)
                dismiss()
            } label: {
                HStack {
                    if location.name == selectedLocation.name {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(location.name)
                }
            }
        }
        .navigationTitle("Select Location")
        .onAppear {
            print("LocationListView: selectedLocation = \(selectedLocation.name) id = \(selectedLocation.id)")
            for loc in locations {
                print("  - \(loc.name) id = \(loc.id), match = \(loc.id == selectedLocation.id)")
            }
        }
    }
}
