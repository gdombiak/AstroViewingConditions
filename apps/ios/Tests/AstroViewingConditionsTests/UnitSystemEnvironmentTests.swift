import SharedCode
import SwiftUI
import UIKit
import XCTest
@testable import AstroViewingConditions

@MainActor
final class UnitSystemEnvironmentTests: XCTestCase {
    func testUnitSystemEnvironmentValuesDefaultAndAssignment() {
        var values = EnvironmentValues()
        XCTAssertEqual(values.unitSystem, .metric)

        values.unitSystem = .imperial
        XCTAssertEqual(values.unitSystem, .imperial)

        values.unitSystem = .metric
        XCTAssertEqual(values.unitSystem, .metric)
    }

    func testSharedPreferenceUpdatesBothMountedViewsAndPublishesOnce() async throws {
        var published: [UnitSystem] = []
        let preference = UnitSystemPreference(selection: .imperial) { published.append($0) }
        var bindings: [Int: Binding<UnitSystem>] = [:]
        var observed: [Int: [UnitSystem]] = [:]
        let updates = [
            expectation(description: "Both views load Imperial"),
            expectation(description: "Both views update to Metric"),
            expectation(description: "Both views update back to Imperial")
        ]
        updates.forEach { $0.expectedFulfillmentCount = 2 }

        let host = UIHostingController(rootView: VStack {
            ForEach(0..<2) { index in
                UnitSystemPreferenceProbe(preference: preference) { selection, binding in
                    bindings[index] = binding
                    observed[index, default: []].append(selection)
                    let updateIndex = observed[index, default: []].count - 1
                    if updates.indices.contains(updateIndex) {
                        updates[updateIndex].fulfill()
                    }
                }
            }
        })
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        await fulfillment(of: [updates[0]], timeout: 5)
        XCTAssertTrue(published.isEmpty)

        let firstWindow = try XCTUnwrap(bindings[0])
        firstWindow.wrappedValue = .metric
        await fulfillment(of: [updates[1]], timeout: 5)
        XCTAssertEqual(published, [.metric])

        let secondWindow = try XCTUnwrap(bindings[1])
        secondWindow.wrappedValue = .metric
        secondWindow.wrappedValue = .imperial
        await fulfillment(of: [updates[2]], timeout: 5)

        XCTAssertEqual(observed[0], [.imperial, .metric, .imperial])
        XCTAssertEqual(observed[1], [.imperial, .metric, .imperial])
        XCTAssertEqual(published, [.metric, .imperial])
    }
}

private struct UnitSystemPreferenceProbe: View {
    @Bindable var preference: UnitSystemPreference
    let observe: (UnitSystem, Binding<UnitSystem>) -> Void

    var body: some View {
        Color.clear
            .onChange(of: preference.selection, initial: true) { _, selection in
                observe(selection, $preference.selection)
            }
    }
}
