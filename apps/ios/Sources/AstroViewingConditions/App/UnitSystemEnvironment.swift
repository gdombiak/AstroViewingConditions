import SharedCode
import SwiftUI

private struct UnitSystemKey: EnvironmentKey {
    static let defaultValue: UnitSystem = .metric
}

extension EnvironmentValues {
    var unitSystem: UnitSystem {
        get { self[UnitSystemKey.self] }
        set { self[UnitSystemKey.self] = newValue }
    }
}
