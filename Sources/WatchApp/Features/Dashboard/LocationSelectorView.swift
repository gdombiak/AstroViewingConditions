import SwiftUI
import SharedCode

enum LocationOption: Identifiable {
    case current
    case saved(CachedLocation)
    
    var id: UUID? {
        switch self {
        case .current: return nil
        case .saved(let location): return location.id
        }
    }
    
    var name: String {
        switch self {
        case .current: return "Current Location"
        case .saved(let location): return location.name
        }
    }
    
    var coordinate: Coordinate? {
        switch self {
        case .current: return nil
        case .saved(let location): return location.coordinate
        }
    }
    
    static func == (lhs: LocationOption, rhs: LocationOption) -> Bool {
        switch (lhs, rhs) {
        case (.current, .current): return true
        case (.saved(let l), .saved(let r)): return l.id == r.id
        default: return false
        }
    }
    
    static func fromLocations(saved: [CachedLocation]) -> [LocationOption] {
        [.current] + saved.map { .saved($0) }
    }
}

struct LocationSelectorView: View {
    let locations: [LocationOption]
    var selectedLocation: SelectedLocation?
    let onSelectionChanged: (LocationOption) -> Void

    var body: some View {
        NavigationLink(destination: LocationListView(locations: locations, selectedLocation: selectedLocation, onSelectionChanged: onSelectionChanged)) {
            Label(selectedLocation?.name ?? "Current Location", systemImage: "location.circle")
                .font(.headline)
        }
    }
}

struct LocationListView: View {
    let locations: [LocationOption]
    var selectedLocation: SelectedLocation?
    let onSelectionChanged: (LocationOption) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(locations) { location in
            Button {
                onSelectionChanged(location)
                dismiss()
            } label: {
                HStack {
                    if case .saved(let loc) = location, loc.id != nil, loc.id == selectedLocation?.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                    if case .current = location, selectedLocation?.source == .currentGPS {
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
