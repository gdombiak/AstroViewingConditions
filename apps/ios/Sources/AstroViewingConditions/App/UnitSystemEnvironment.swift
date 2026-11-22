import Observation
import SharedCode
import SwiftUI

@MainActor
@Observable
final class UnitSystemPreference {
    var selection: UnitSystem {
        didSet {
            guard selection != oldValue else { return }
            onChange(selection)
        }
    }

    private let onChange: (UnitSystem) -> Void

    init(selection: UnitSystem, onChange: @escaping (UnitSystem) -> Void) {
        self.selection = selection
        self.onChange = onChange
    }
}

private struct UnitSystemKey: EnvironmentKey {
    static let defaultValue: UnitSystem = .metric
}

extension EnvironmentValues {
    var unitSystem: UnitSystem {
        get { self[UnitSystemKey.self] }
        set { self[UnitSystemKey.self] = newValue }
    }
}
