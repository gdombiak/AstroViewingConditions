import SharedCode
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import AstroViewingConditions

@MainActor
final class UnitSystemEnvironmentTests: XCTestCase {
    func testMountedLocationRowFollowsEnvironmentUnitSystemWithoutRecreation() throws {
        let container = try ModelContainer(
            for: SavedLocation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let location = SavedLocation(
            name: "Probe",
            latitude: 35.2,
            longitude: -111.6,
            elevation: 1165
        )
        container.mainContext.insert(location)
        try container.mainContext.save()

        let probe = UnitSystemProbe()
        let host = UIHostingController(
            rootView: MountedLocationRowHost(location: location, probe: probe)
                .modelContainer(container)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        XCTAssertTrue(
            visibleText(in: host.view).contains("Elevation: 3822 ft"),
            "Imperial environment should format 1165 m as feet"
        )

        probe.unitSystem = .metric
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let metricText = visibleText(in: host.view)
        XCTAssertTrue(
            metricText.contains("Elevation: 1165 m"),
            "Metric environment should format 1165 m as meters; got \(metricText)"
        )
        XCTAssertFalse(metricText.contains("3822 ft"))
    }
}

private struct MountedLocationRowHost: View {
    let location: SavedLocation
    var probe: UnitSystemProbe

    var body: some View {
        LocationRow(location: location)
            .environment(\.unitSystem, probe.unitSystem)
    }
}

@Observable
private final class UnitSystemProbe {
    var unitSystem: UnitSystem = .imperial
}

private func visibleText(in view: UIView) -> [String] {
    var result: [String] = []
    if let label = view as? UILabel, let text = label.text, !text.isEmpty {
        result.append(text)
    }
    if let label = view.accessibilityLabel, !label.isEmpty {
        result.append(label)
    }
    if let elements = view.accessibilityElements {
        for element in elements {
            if let object = element as? NSObject, let label = object.accessibilityLabel, !label.isEmpty {
                result.append(label)
            }
        }
    }
    for subview in view.subviews {
        result.append(contentsOf: visibleText(in: subview))
    }
    return result
}
