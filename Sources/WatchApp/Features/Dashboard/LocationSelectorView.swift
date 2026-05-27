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
    let isRefreshingLocations: Bool
    let isRefreshingConditions: Bool
    let onSelectionChanged: (LocationOption) -> Void
    let onRefreshLocations: () -> Void
    let onRefreshConditions: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            NavigationLink(
                destination: LocationListView(
                    locations: locations,
                    selectedLocation: selectedLocation,
                    isRefreshingLocations: isRefreshingLocations,
                    onSelectionChanged: onSelectionChanged,
                    onRefreshLocations: onRefreshLocations
                )
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "location.circle")
                        .font(.caption)
                    Text(selectedLocation?.name ?? "Current Location")
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button(action: onRefreshConditions) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(width: 28, height: 28)
            .background(.regularMaterial)
            .clipShape(Circle())
            .opacity(isRefreshingConditions ? 0.35 : 1)
            .disabled(isRefreshingConditions)
            .buttonStyle(.plain)
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LocationListView: View {
    let locations: [LocationOption]
    var selectedLocation: SelectedLocation?
    let isRefreshingLocations: Bool
    let onSelectionChanged: (LocationOption) -> Void
    let onRefreshLocations: () -> Void
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onRefreshLocations) {
                    if isRefreshingLocations {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingLocations)
            }
        }
    }
}
