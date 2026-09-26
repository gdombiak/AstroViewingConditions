import Combine
import XCTest
import UIKit
import SwiftUI
import SharedCode
@testable import AstroViewingConditions

final class TargetScoreColorProviderTests: XCTestCase {

    func testTargetScoreColorsUseSharedCategories() {
        XCTAssertEqual(TargetScoreColorProvider.category(for: 84), .excellent)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 76), .good)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 55), .fair)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 35), .poor)
    }

    // MARK: - Target score terminology (Issue #70 Phase 8)

    func testTargetScoreAccessibilityUsesTargetScoreTerminology() {
        let label = TargetScorePresentation.accessibilityLabel(score: 91)
        XCTAssertEqual(label, "Target score 91 out of 100")
        XCTAssertTrue(label.hasPrefix("Target score"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("observing quality"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("night conditions"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("visibility percentage"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("probability"))
    }

    func testTargetScoreAccessibilityDoesNotDuplicateUnlabeledScoreWording() {
        let label = TargetScorePresentation.accessibilityLabel(score: 72)
        // Single labeled form only — not "Score 72" plus a separate "Target score 72".
        XCTAssertEqual(label.components(separatedBy: "72").count - 1, 1)
        XCTAssertFalse(label.hasPrefix("Score "))
    }

    func testTargetDetailsConciseLabelIsTargetScore() {
        XCTAssertEqual(TargetScorePresentation.conciseLabel, "Target score")
        // Dynamic Type: short label should not need truncation at large sizes.
        XCTAssertLessThanOrEqual(TargetScorePresentation.conciseLabel.count, 20)
    }

    func testTargetScoreAccessibilityMatchesRepresentativeFixturesWithoutChangingScore() {
        for score in [45, 64, 79, 80, 91, 100] {
            let label = TargetScorePresentation.accessibilityLabel(score: score)
            XCTAssertEqual(label, "Target score \(score) out of 100")
            XCTAssertTrue(label.contains("\(score)"))
        }
    }

    func testSharedScoreCategoriesAndDashboardBandsAgreeAtEveryBoundary() {
        let cases: [(score: Int, category: TargetScoreCategory, band: BestTargetsScoreBand?)] = [
            (39, .poor, nil), (40, .poor, nil), (44, .poor, nil),
            (45, .fair, .fair), (59, .fair, .fair), (60, .fair, .fair), (64, .fair, .fair),
            (65, .good, .good), (79, .good, .good),
            (80, .excellent, .excellent), (100, .excellent, .excellent)
        ]

        for testCase in cases {
            XCTAssertEqual(TargetScoreCategory.resolve(testCase.score), testCase.category)
            XCTAssertEqual(TargetScoreColorProvider.category(for: testCase.score), testCase.category)
            XCTAssertEqual(
                BestTargetsScoreBand.allCases.first { $0.contains(score: testCase.score) },
                testCase.band
            )
        }
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

    /// Issue #77: the root Field Mode owner must keep following the persisted preference
    /// through repeated Off → On → Off → On → Off transitions. Dashboard and Settings both
    /// write the same UserDefaults key, so the root re-render is the seam they share.
    @MainActor
    func testFieldModeRootViewFollowsRepeatedPreferenceChanges() async throws {
        let suiteName = "FieldModeRootViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: FieldModePreference.key)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var observedAppearances: [AppAppearance] = []
        var expectedAppearance: AppAppearance = .normal
        // Each expectation is consumed only by its expected appearance.
        var updateExpectation: XCTestExpectation? = expectation(description: "Initial .normal appearance")

        let host = UIHostingController(
            rootView: FieldModeRootView {
                PaletteAppearanceProbe { appearance in
                    observedAppearances.append(appearance)
                    guard appearance == expectedAppearance, let pending = updateExpectation else { return }
                    updateExpectation = nil
                    pending.fulfill()
                }
            }.defaultAppStorage(defaults)
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // UserDefaults → @AppStorage → environment propagation is asynchronous; allow
        // headroom for full-suite load.
        let propagationTimeout: TimeInterval = 5
        await fulfillment(of: [try XCTUnwrap(updateExpectation)], timeout: propagationTimeout)

        for (index, isEnabled) in [true, false, true, false].enumerated() {
            // A MainActor `wait(for:)` can resume inside the previous `onChange`.
            // Move the next persisted write to a later main-queue turn.
            await finishSwiftUIUpdateCycle()
            expectedAppearance = isEnabled ? .field : .normal
            let transition = expectation(description: "Transition \(index) to \(expectedAppearance)")
            updateExpectation = transition
            FieldModePreference.save(isEnabled, to: defaults)
            await fulfillment(of: [transition], timeout: propagationTimeout)
        }

        XCTAssertEqual(observedAppearances, [.normal, .field, .normal, .field, .normal])
    }

    /// Issue #77: on iOS 27 an `@AppStorage` on the `App` struct stops re-evaluating the
    /// scene body after its first change. The persisted Field Mode owner has to stay in a
    /// `View` (`FieldModeRootView`); this guards against moving it back.
    func testFieldModePreferenceIsNotOwnedByTheAppStruct() throws {
        let appSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstroViewingConditions/App/AstroViewingConditionsApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            appSource.contains("@AppStorage"),
            "Keep @AppStorage out of the App struct: iOS 27 only re-evaluates it once (#77)."
        )
        XCTAssertTrue(appSource.contains("FieldModeRootView"))
    }

    // MARK: - Navigation title colors (Issue #78)

    /// SwiftUI updates the representable before it has a parent. The stored palette must be
    /// applied once the controller is attached, without any deferred retry.
    @MainActor
    func testNavigationTitleColorControllerAppliesStoredPaletteOnAttachment() throws {
        let controller = NavigationBarTitleColorViewController()
        controller.update(palette: .field)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        assertNoTitleColorOverrides(in: navigation, topItem: root.navigationItem)

        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)

        try assertFieldTitleColors(in: navigation, topItem: root.navigationItem)
    }

    @MainActor
    func testNavigationTitleColorControllerFollowsRepeatedPaletteChanges() throws {
        let controller = NavigationBarTitleColorViewController()
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)

        for palette in [AppPalette.field, .normal, .field, .normal] {
            controller.update(palette: palette)
            if palette.appearance == .field {
                try assertFieldTitleColors(in: navigation, topItem: root.navigationItem)
            } else {
                assertNoTitleColorOverrides(in: navigation, topItem: root.navigationItem)
            }
        }
    }

    private func assertFieldTitleColors(
        in navigation: UINavigationController,
        topItem: UINavigationItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bar = navigation.navigationBar
        let appearances = [
            bar.standardAppearance, bar.scrollEdgeAppearance,
            bar.compactAppearance, bar.compactScrollEdgeAppearance,
            topItem.standardAppearance, topItem.scrollEdgeAppearance,
            topItem.compactAppearance, topItem.compactScrollEdgeAppearance
        ]

        for appearance in appearances {
            let appearance = try XCTUnwrap(appearance, file: file, line: line)
            let inlineColor = try XCTUnwrap(
                appearance.titleTextAttributes[.foregroundColor] as? UIColor, file: file, line: line
            )
            let largeColor = try XCTUnwrap(
                appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor, file: file, line: line
            )
            XCTAssertTrue(inlineColor.matches(AppPalette.field.primaryText), file: file, line: line)
            XCTAssertTrue(largeColor.matches(AppPalette.field.displayTitleText), file: file, line: line)
        }
    }

    private func assertNoTitleColorOverrides(
        in navigation: UINavigationController,
        topItem: UINavigationItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // A cleared appearance reports UIKit's default label color, so "no override" means
        // "not the Field Mode colors" rather than a missing attribute.
        let bar = navigation.navigationBar
        let barAppearances = [
            bar.standardAppearance, bar.scrollEdgeAppearance,
            bar.compactAppearance, bar.compactScrollEdgeAppearance
        ]
        for appearance in barAppearances.compactMap({ $0 }) {
            if let inlineColor = appearance.titleTextAttributes[.foregroundColor] as? UIColor {
                XCTAssertFalse(inlineColor.matches(AppPalette.field.primaryText), file: file, line: line)
            }
            if let largeColor = appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor {
                XCTAssertFalse(largeColor.matches(AppPalette.field.displayTitleText), file: file, line: line)
            }
        }
        XCTAssertNil(topItem.standardAppearance, file: file, line: line)
        XCTAssertNil(topItem.scrollEdgeAppearance, file: file, line: line)
        XCTAssertNil(topItem.compactAppearance, file: file, line: line)
        XCTAssertNil(topItem.compactScrollEdgeAppearance, file: file, line: line)
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

    func testUnavailableEquipmentRowUsesPaletteCautionColor() throws {
        let normal = try rgbComponents(of: EquipmentRowPresentation.unavailableColor(palette: .normal))
        let normalCaution = try rgbComponents(of: AppPalette.normal.statusColor(.caution))
        let field = try rgbComponents(of: EquipmentRowPresentation.unavailableColor(palette: .field))
        let fieldCaution = try rgbComponents(of: AppPalette.field.statusColor(.caution))

        XCTAssertEqual(normal.0, normalCaution.0, accuracy: 0.000_1)
        XCTAssertEqual(normal.1, normalCaution.1, accuracy: 0.000_1)
        XCTAssertEqual(normal.2, normalCaution.2, accuracy: 0.000_1)
        XCTAssertEqual(field.0, fieldCaution.0, accuracy: 0.000_1)
        XCTAssertEqual(field.1, fieldCaution.1, accuracy: 0.000_1)
        XCTAssertEqual(field.2, fieldCaution.2, accuracy: 0.000_1)
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

private struct PaletteAppearanceProbe: View {
    @Environment(\.appPalette) private var palette
    let reportAppearance: (AppAppearance) -> Void

    var body: some View {
        Color.clear
            .onChange(of: palette.appearance, initial: true) { _, appearance in
                reportAppearance(appearance)
            }
    }
}

/// Resume on a later main-queue turn so the next persisted write does not
/// occur inside the previous SwiftUI `onChange` update transaction.
@MainActor
private func finishSwiftUIUpdateCycle() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

private extension UIColor {
    /// Compares resolved RGB components against a SwiftUI color (dark trait, as Field Mode runs).
    func matches(_ color: SwiftUI.Color) -> Bool {
        var lhs: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var rhs: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        guard resolvedColor(with: traits).getRed(&lhs.0, green: &lhs.1, blue: &lhs.2, alpha: &lhs.3),
              UIColor(color).resolvedColor(with: traits).getRed(&rhs.0, green: &rhs.1, blue: &rhs.2, alpha: &rhs.3)
        else { return false }
        return abs(lhs.0 - rhs.0) < 0.000_1 && abs(lhs.1 - rhs.1) < 0.000_1 && abs(lhs.2 - rhs.2) < 0.000_1
    }
}
