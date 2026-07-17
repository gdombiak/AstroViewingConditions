import Combine
import XCTest
import UIKit
import SwiftUI
@testable import AstroViewingConditions

final class TargetScoreColorProviderTests: XCTestCase {

    func testTargetScoreColorsUseSharedCategories() {
        XCTAssertEqual(TargetScoreColorProvider.category(for: 84), .excellent)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 76), .good)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 55), .fair)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 35), .poor)
    }

    func testFieldModePreferenceDefaultsToDisabledAndPersistsChanges() {
        let suiteName = "FieldModePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(FieldModePreference.load(from: defaults))

        FieldModePreference.save(true, to: defaults)
        XCTAssertTrue(FieldModePreference.load(from: defaults))

        FieldModePreference.save(false, to: defaults)
        XCTAssertFalse(FieldModePreference.load(from: defaults))
    }

    func testNormalAndFieldAppearanceResolveDeterministically() {
        XCTAssertEqual(AppAppearance.resolve(fieldModeEnabled: false), .normal)
        XCTAssertEqual(AppAppearance.resolve(fieldModeEnabled: true), .field)
        XCTAssertEqual(AppAppearance.normal.palette.appearance, .normal)
        XCTAssertEqual(AppAppearance.field.palette.appearance, .field)
        XCTAssertEqual(AppAppearance.resolve(fieldModeEnabled: false).palette.appearance, .normal)
    }

    @MainActor
    func testTogglingFieldModeKeepsWrappedContentStateAlive() {
        let controller = FieldModeController()
        var observedLifetimeIDs: [UUID] = []
        var updateExpectation = expectation(description: "Initial appearance")

        let host = UIHostingController(
            rootView: AppearanceLifetimeHarness(controller: controller) { lifetimeID in
                observedLifetimeIDs.append(lifetimeID)
                updateExpectation.fulfill()
            }
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        wait(for: [updateExpectation], timeout: 2)

        updateExpectation = expectation(description: "Field Mode enabled")
        controller.isFieldModeEnabled = true
        wait(for: [updateExpectation], timeout: 2)

        updateExpectation = expectation(description: "Field Mode disabled")
        controller.isFieldModeEnabled = false
        wait(for: [updateExpectation], timeout: 2)

        XCTAssertEqual(observedLifetimeIDs.count, 3)
        XCTAssertEqual(Set(observedLifetimeIDs).count, 1)
    }

    func testFieldPaletteUsesDimRedDominantCoreColors() throws {
        for color in [AppPalette.field.appBackground, AppPalette.field.elevatedBackground, AppPalette.field.primaryText, AppPalette.field.accent] {
            let components = try XCTUnwrap(UIColor(color).cgColor.components)
            let red = components[0]
            let green = components.count > 2 ? components[1] : red
            let blue = components.count > 2 ? components[2] : red

            XCTAssertGreaterThanOrEqual(red, green)
            XCTAssertGreaterThanOrEqual(red, blue)
        }

        let backgroundComponents = try XCTUnwrap(UIColor(AppPalette.field.appBackground).cgColor.components)
        XCTAssertLessThan(backgroundComponents[0], 0.05)
    }

    func testFieldPrimaryActionHasReadableSemanticContrast() throws {
        let background = try rgbComponents(of: AppPalette.field.primaryActionBackground)
        let label = try rgbComponents(of: AppPalette.field.primaryActionLabel)
        let disabledBackground = try rgbComponents(of: AppPalette.field.subduedFill)

        XCTAssertGreaterThanOrEqual(
            contrastRatio(background, label),
            4.5,
            "background: \(background), label: \(label)"
        )
        XCTAssertGreaterThan(
            abs(background.0 - disabledBackground.0)
                + abs(background.1 - disabledBackground.1)
                + abs(background.2 - disabledBackground.2),
            0.1
        )
    }

    func testFieldTextHierarchyIsReadableAndOrdered() throws {
        let background = try rgbComponents(of: AppPalette.field.elevatedBackground)
        let primaryContrast = contrastRatio(background, try rgbComponents(of: AppPalette.field.primaryText))
        let secondaryContrast = contrastRatio(background, try rgbComponents(of: AppPalette.field.secondaryText))
        let tertiaryContrast = contrastRatio(background, try rgbComponents(of: AppPalette.field.tertiaryText))
        let disabledContrast = contrastRatio(background, try rgbComponents(of: AppPalette.field.disabledText))

        XCTAssertGreaterThanOrEqual(primaryContrast, 4.5)
        XCTAssertGreaterThanOrEqual(secondaryContrast, 3.0)
        XCTAssertGreaterThan(secondaryContrast, tertiaryContrast)
        XCTAssertGreaterThan(tertiaryContrast, disabledContrast)
        XCTAssertGreaterThan(disabledContrast, 1.5)
    }

    func testFieldControlStatesDoNotDependOnWhiteOrHueAlone() throws {
        let background = try rgbComponents(of: AppPalette.field.controlBackground)
        let selectedBackground = try rgbComponents(of: AppPalette.field.selectedControlBackground)
        let selectedText = try rgbComponents(of: AppPalette.field.selectedControlText)
        let unselectedText = try rgbComponents(of: AppPalette.field.unselectedControlText)

        XCTAssertGreaterThanOrEqual(contrastRatio(selectedBackground, selectedText), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(background, unselectedText), 3.0)
        XCTAssertGreaterThan(selectedBackground.0, background.0)
        XCTAssertLessThan(selectedText.0 + selectedText.1 + selectedText.2, 2.0)
    }

    private func rgbComponents(of color: SwiftUI.Color) throws -> (CGFloat, CGFloat, CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let uiColor = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )

        XCTAssertTrue(uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red, green, blue)
    }

    private func contrastRatio(
        _ first: (CGFloat, CGFloat, CGFloat),
        _ second: (CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(color.0)
            + 0.7152 * linearize(color.1)
            + 0.0722 * linearize(color.2)
    }

}

@MainActor
private final class FieldModeController: ObservableObject {
    @Published var isFieldModeEnabled = false
}

private struct AppearanceLifetimeHarness: View {
    @ObservedObject var controller: FieldModeController
    let reportLifetimeID: (UUID) -> Void

    var body: some View {
        AppearanceLifetimeProbe(
            fieldModeEnabled: controller.isFieldModeEnabled,
            reportLifetimeID: reportLifetimeID
        )
        .appAppearance(fieldModeEnabled: controller.isFieldModeEnabled)
    }
}

private struct AppearanceLifetimeProbe: View {
    @State private var lifetimeID = UUID()
    let fieldModeEnabled: Bool
    let reportLifetimeID: (UUID) -> Void

    var body: some View {
        Color.clear
            .onChange(of: fieldModeEnabled, initial: true) { _, _ in
                reportLifetimeID(lifetimeID)
            }
    }
}
