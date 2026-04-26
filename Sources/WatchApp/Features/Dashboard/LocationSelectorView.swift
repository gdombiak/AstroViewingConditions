import SwiftUI
import SharedCode

struct LocationSelectorView: View {
    let locations: [WatchLocationItem]
    var selectedLocation: SelectedLocation?
    let onSelectionChanged: (WatchLocationItem) -> Void

    var body: some View {
        NavigationLink(destination: LocationListView(locations: locations, selectedLocation: selectedLocation, onSelectionChanged: onSelectionChanged)) {
            Label(selectedLocation?.name ?? "Current Location", systemImage: "location.circle")
                .font(.headline)
        }
    }
}

struct LocationListView: View {
    let locations: [WatchLocationItem]
    var selectedLocation: SelectedLocation?
    let onSelectionChanged: (WatchLocationItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(locations) { location in
            Button {
                onSelectionChanged(location)
                dismiss()
            } label: {
                HStack {
                    if location.id != nil, location.id == selectedLocation?.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(location.name)
                }
            }
        }
        .navigationTitle("Select Location")
    }
}
