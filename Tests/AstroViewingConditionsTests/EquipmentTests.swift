import SwiftData
import XCTest
@testable import SharedCode
@testable import AstroViewingConditions

@MainActor
final class EquipmentTests: XCTestCase {
    func testSmartEAAApertureThresholdPairAcceptsAbsentEqualAndIncreasingValues() {
        let absent = TargetEquipmentRequirement()
        let equal = TargetEquipmentRequirement(
            practicalSmartEAAApertureMillimeters: 30,
            preferredSmartEAAApertureMillimeters: 30
        )
        let increasing = TargetEquipmentRequirement(
            practicalSmartEAAApertureMillimeters: 30,
            preferredSmartEAAApertureMillimeters: 50
        )

        XCTAssertNil(absent.practicalSmartEAAApertureMillimeters)
        XCTAssertNil(absent.preferredSmartEAAApertureMillimeters)
        XCTAssertEqual(equal.practicalSmartEAAApertureMillimeters, 30)
        XCTAssertEqual(equal.preferredSmartEAAApertureMillimeters, 30)
        XCTAssertEqual(increasing.practicalSmartEAAApertureMillimeters, 30)
        XCTAssertEqual(increasing.preferredSmartEAAApertureMillimeters, 50)
    }

    func testSmartEAAApertureThresholdPairValidationRejectsMalformedStates() {
        XCTAssertFalse(
            TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(
                practical: 30,
                preferred: nil
            )
        )
        XCTAssertFalse(
            TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(
                practical: nil,
                preferred: 50
            )
        )
        XCTAssertFalse(
            TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(
                practical: 50,
                preferred: 30
            )
        )
        for values in [(0.0, 30.0), (-1.0, 30.0), (.nan, 30.0), (30.0, .infinity)] {
            XCTAssertFalse(
                TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(
                    practical: values.0,
                    preferred: values.1
                )
            )
        }
    }

    func testCatalogSmartEAAApertureThresholdPairsRemainValid() {
        let targets = [
            catalogTarget(id: "m77"),
            catalogTarget(id: "m45"),
            catalogTarget(id: "m101"),
            catalogTarget(id: "generic-galaxy")
        ]

        for target in targets {
            let requirement = target.equipmentRequirement
            XCTAssertTrue(
                TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(
                    practical: requirement.practicalSmartEAAApertureMillimeters,
                    preferred: requirement.preferredSmartEAAApertureMillimeters
                ),
                target.id
            )
        }
    }

    func testEquipmentTypeCodableRoundTrip() throws {
        for type in EquipmentType.allCases {
            let data = try JSONEncoder().encode(type)
            XCTAssertEqual(try JSONDecoder().decode(EquipmentType.self, from: data), type)
        }
    }

    func testMillimeterInputIsStoredWithoutConversion() throws {
        let draft = try EquipmentDraft(
            name: "  10x50 Roof Prism  ",
            type: .binoculars,
            magnification: 10,
            aperture: 50,
            apertureUnit: .millimeters
        )

        XCTAssertEqual(draft.name, "10x50 Roof Prism")
        XCTAssertEqual(draft.magnification, 10)
        XCTAssertEqual(draft.apertureMillimeters, 50)
        XCTAssertEqual(draft.apertureUnit, .millimeters)
    }

    func testLocaleAwareDecimalParsingAcceptsEnglishAndSpanishInput() {
        XCTAssertEqual(
            EquipmentFormatting.decimalInput(from: "5.5", locale: Locale(identifier: "en_US")),
            .value(5.5)
        )
        XCTAssertEqual(
            EquipmentFormatting.decimalInput(from: "5,5", locale: Locale(identifier: "es_AR")),
            .value(5.5)
        )
    }

    func testLocaleAwareDecimalParsingRejectsInvalidTextAndPreservesBlankInput() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(EquipmentFormatting.decimalInput(from: "5mm", locale: locale), .invalid)
        XCTAssertEqual(EquipmentFormatting.decimalInput(from: "5.5.1", locale: locale), .invalid)
        XCTAssertEqual(EquipmentFormatting.decimalInput(from: "  \n", locale: locale), .blank)
    }

    func testApertureUnitToggleConvertsFiveInchesToMillimeters() {
        XCTAssertEqual(
            EquipmentFormatting.convertedApertureInputText(
                "5",
                from: .inches,
                to: .millimeters,
                locale: Locale(identifier: "en_US")
            ),
            "127"
        )
    }

    func testApertureUnitToggleConvertsMillimetersToFiveInches() {
        XCTAssertEqual(
            EquipmentFormatting.convertedApertureInputText(
                "127",
                from: .millimeters,
                to: .inches,
                locale: Locale(identifier: "en_US")
            ),
            "5"
        )
    }

    func testApertureUnitToggleConvertsDecimalTextInEnglishAndSpanishLocales() {
        XCTAssertEqual(
            EquipmentFormatting.convertedApertureInputText(
                "5.5",
                from: .inches,
                to: .millimeters,
                locale: Locale(identifier: "en_US")
            ),
            "139.7"
        )
        XCTAssertEqual(
            EquipmentFormatting.convertedApertureInputText(
                "5,5",
                from: .inches,
                to: .millimeters,
                locale: Locale(identifier: "es_AR")
            ),
            "139,7"
        )
    }

    func testApertureUnitTogglePreservesPhysicalValueWithoutDrift() throws {
        let locale = Locale(identifier: "en_US")
        var text = "5"
        var unit = EquipmentApertureUnit.inches

        for _ in 0..<4 {
            let nextUnit: EquipmentApertureUnit = unit == .inches ? .millimeters : .inches
            text = try XCTUnwrap(
                EquipmentFormatting.convertedApertureInputText(
                    text,
                    from: unit,
                    to: nextUnit,
                    locale: locale
                )
            )
            unit = nextUnit
        }

        XCTAssertEqual(unit, .inches)
        XCTAssertEqual(text, "5")
    }

    func testApertureUnitToggleLeavesBlankAndInvalidTextUntouched() {
        let locale = Locale(identifier: "en_US")
        XCTAssertNil(
            EquipmentFormatting.convertedApertureInputText(
                "  ",
                from: .inches,
                to: .millimeters,
                locale: locale
            )
        )
        XCTAssertNil(
            EquipmentFormatting.convertedApertureInputText(
                "5.",
                from: .inches,
                to: .millimeters,
                locale: locale
            )
        )
    }

    func testInchApertureIsNormalizedToMillimeters() throws {
        let draft = try EquipmentDraft(
            name: "Five Inch Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 5,
            apertureUnit: .inches
        )

        XCTAssertEqual(draft.apertureMillimeters, 127, accuracy: 0.000_001)
    }

    func testBinocularsRequirePositiveMagnificationAndAperture() throws {
        XCTAssertValidationError(.missingMagnification) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: nil, aperture: 50, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidMagnification) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: 0, aperture: 50, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.missingAperture) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: 10, aperture: nil, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: 10, aperture: -50, apertureUnit: .millimeters)
        }
    }

    func testVisualTelescopeRequiresPositiveAperture() throws {
        XCTAssertValidationError(.missingAperture) {
            _ = try EquipmentDraft(name: "Dobsonian", type: .visualTelescope, magnification: nil, aperture: nil, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Dobsonian", type: .visualTelescope, magnification: nil, aperture: 0, apertureUnit: .millimeters)
        }
    }

    func testSmartTelescopeRequiresPositiveAperture() throws {
        XCTAssertValidationError(.missingAperture) {
            _ = try EquipmentDraft(name: "Seestar S30 Pro", type: .smartTelescope, magnification: nil, aperture: nil, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Seestar S30 Pro", type: .smartTelescope, magnification: nil, aperture: .infinity, apertureUnit: .millimeters)
        }

        let draft = try EquipmentDraft(name: "Seestar S30 Pro", type: .smartTelescope, magnification: nil, aperture: 30, apertureUnit: .millimeters)
        XCTAssertEqual(draft.apertureMillimeters, 30)
    }

    func testValidationRejectsBlankNamesAndNonFiniteValues() throws {
        XCTAssertValidationError(.blankName) {
            _ = try EquipmentDraft(name: " \n\t ", type: .visualTelescope, magnification: nil, aperture: 80, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidMagnification) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: .nan, aperture: 50, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Scope", type: .visualTelescope, magnification: nil, aperture: -.infinity, apertureUnit: .inches)
        }
    }

    func testValidationRejectsZeroNegativeNaNAndInfinityValues() {
        XCTAssertValidationError(.invalidMagnification) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: -10, aperture: 50, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidMagnification) {
            _ = try EquipmentDraft(name: "Binoculars", type: .binoculars, magnification: .infinity, aperture: 50, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Telescope", type: .visualTelescope, magnification: nil, aperture: .nan, apertureUnit: .millimeters)
        }
        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Telescope", type: .visualTelescope, magnification: nil, aperture: -1, apertureUnit: .millimeters)
        }
    }

    func testBinocularMagnificationAboveOneHundredIsRejected() {
        XCTAssertValidationError(.magnificationTooHigh) {
            _ = try EquipmentDraft(
                name: "High Power Binoculars",
                type: .binoculars,
                magnification: 101,
                aperture: 50,
                apertureUnit: .millimeters
            )
        }
    }

    func testBinocularApertureAboveThreeHundredMillimetersIsRejected() {
        XCTAssertValidationError(.apertureTooLarge) {
            _ = try EquipmentDraft(
                name: "Large Binoculars",
                type: .binoculars,
                magnification: 20,
                aperture: 301,
                apertureUnit: .millimeters
            )
        }
    }

    func testTelescopeApertureAboveTwoThousandMillimetersIsRejected() {
        XCTAssertValidationError(.apertureTooLarge) {
            _ = try EquipmentDraft(
                name: "Large Telescope",
                type: .visualTelescope,
                magnification: nil,
                aperture: 2_001,
                apertureUnit: .millimeters
            )
        }
    }

    func testInchApertureIsNormalizedBeforeRangeValidation() throws {
        XCTAssertValidationError(.apertureTooLarge) {
            _ = try EquipmentDraft(
                name: "Large Binoculars",
                type: .binoculars,
                magnification: 20,
                aperture: 12,
                apertureUnit: .inches
            )
        }

        let validDraft = try EquipmentDraft(
            name: "Large Binoculars",
            type: .binoculars,
            magnification: 20,
            aperture: 11.8,
            apertureUnit: .inches
        )
        XCTAssertEqual(validDraft.apertureMillimeters, 299.72, accuracy: 0.000_001)
    }

    func testCombinedBinocularInputIsRecognizedAsSeparateFieldError() {
        for input in ["10×50", "10x50", "10 X 50"] {
            XCTAssertTrue(EquipmentFormatting.isCombinedBinocularInput(input), input)
            XCTAssertEqual(
                EquipmentFormatting.decimalInput(from: input, locale: Locale(identifier: "en_US")),
                .invalid
            )
        }
    }

    func testValidTenByFiftyBinocularsKeepSeparateMagnificationAndAperture() throws {
        let draft = try EquipmentDraft(
            name: "10×50 Binoculars",
            type: .binoculars,
            magnification: 10,
            aperture: 50,
            apertureUnit: .millimeters
        )

        XCTAssertEqual(draft.magnification, 10)
        XCTAssertEqual(draft.apertureMillimeters, 50)
    }

    func testPersistentOpticsFieldLabelsMatchEquipmentType() {
        XCTAssertEqual(
            EquipmentFormPresentation.opticsFields(for: .binoculars),
            [.magnification, .aperture]
        )
        XCTAssertEqual(
            EquipmentFormPresentation.opticsFields(for: .visualTelescope),
            [.aperture]
        )
        XCTAssertEqual(
            EquipmentFormPresentation.opticsFields(for: .smartTelescope),
            [.aperture]
        )
        XCTAssertEqual(EquipmentFormPresentation.label(for: .name), "Name")
        XCTAssertEqual(EquipmentFormPresentation.nameAccessibilityLabel, "Equipment name")
        XCTAssertEqual(EquipmentFormPresentation.label(for: .magnification), "Magnification")
        XCTAssertEqual(EquipmentFormPresentation.label(for: .aperture), "Aperture")
    }

    func testLiveBinocularSummaryFormatsIntegersAndLocalizedDecimals() {
        XCTAssertEqual(
            EquipmentFormPresentation.binocularSizeSummary(
                magnificationText: "10",
                apertureText: "50",
                apertureUnit: .millimeters,
                locale: Locale(identifier: "en_US")
            ),
            "Binocular size: 10×50"
        )
        XCTAssertEqual(
            EquipmentFormPresentation.binocularSizeSummary(
                magnificationText: "10.5",
                apertureText: "50.25",
                apertureUnit: .millimeters,
                locale: Locale(identifier: "en_US")
            ),
            "Binocular size: 10.5×50.25"
        )
        XCTAssertEqual(
            EquipmentFormPresentation.binocularSizeSummary(
                magnificationText: "10,5",
                apertureText: "50,25",
                apertureUnit: .millimeters,
                locale: Locale(identifier: "es_AR")
            ),
            "Binocular size: 10,5×50,25"
        )
    }

    func testLiveBinocularSummaryNormalizesInchApertureAndUpdatesWithUnitChanges() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(
            EquipmentFormPresentation.binocularSizeSummary(
                magnificationText: "10",
                apertureText: "2",
                apertureUnit: .inches,
                locale: locale
            ),
            "Binocular size: 10×50.8"
        )
        XCTAssertEqual(
            EquipmentFormPresentation.binocularSizeSummary(
                magnificationText: "10",
                apertureText: "50.8",
                apertureUnit: .millimeters,
                locale: locale
            ),
            "Binocular size: 10×50.8"
        )
        XCTAssertEqual(
            EquipmentFormPresentation.binocularSizeSummary(
                magnificationText: "8",
                apertureText: "1.65",
                apertureUnit: .inches,
                locale: locale
            ),
            "Binocular size: 8×41.91"
        )
    }

    func testLiveBinocularSummaryRejectsBlankInvalidAndOutOfRangeInput() {
        let locale = Locale(identifier: "en_US")
        for values in [("", "50"), ("10", ""), ("0", "50"), ("-10", "50"), ("10", "0"), ("10", "-50"), ("nan", "50"), ("10", "infinity"), ("101", "50"), ("10", "301")] {
            XCTAssertNil(
                EquipmentFormPresentation.binocularSizeSummary(
                    magnificationText: values.0,
                    apertureText: values.1,
                    apertureUnit: .millimeters,
                    locale: locale
                ),
                "Expected no summary for \(values.0)×\(values.1)"
            )
        }
    }

    func testBinocularApertureHelperTextReflectsSelectedUnit() {
        XCTAssertEqual(
            EquipmentFormPresentation.binocularApertureHelperText(for: .millimeters),
            "Enter the second number in 10×50 binoculars."
        )
        XCTAssertEqual(
            EquipmentFormPresentation.binocularApertureHelperText(for: .inches),
            "Enter the objective aperture in inches. It will be shown in standard millimeter notation below."
        )
    }

    func testSwitchingAwayFromBinocularsClearsMagnificationText() {
        XCTAssertEqual(
            EquipmentFormPresentation.magnificationText(
                afterChangingTo: .visualTelescope,
                currentText: "10"
            ),
            ""
        )
        XCTAssertEqual(
            EquipmentFormPresentation.magnificationText(
                afterChangingTo: .smartTelescope,
                currentText: "10"
            ),
            ""
        )
        XCTAssertEqual(
            EquipmentFormPresentation.magnificationText(
                afterChangingTo: .binoculars,
                currentText: "10"
            ),
            "10"
        )
    }

    func testMultipleItemsPersistAndCanBeDeleted() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let binoculars = EquipmentItem(draft: try EquipmentDraft(
            name: "10x50",
            type: .binoculars,
            magnification: 10,
            aperture: 50,
            apertureUnit: .millimeters
        ))
        let secondBinoculars = EquipmentItem(draft: try EquipmentDraft(
            name: "15x70",
            type: .binoculars,
            magnification: 15,
            aperture: 70,
            apertureUnit: .millimeters
        ))
        let telescope = EquipmentItem(draft: try EquipmentDraft(
            name: "Five Inch Refractor",
            type: .visualTelescope,
            magnification: nil,
            aperture: 5,
            apertureUnit: .inches
        ))

        context.insert(binoculars)
        context.insert(secondBinoculars)
        context.insert(telescope)
        try context.save()

        let readContext = ModelContext(container)
        let savedItems = try readContext.fetch(FetchDescriptor<EquipmentItem>())
        XCTAssertEqual(savedItems.count, 3)
        XCTAssertEqual(savedItems.filter { $0.type == .binoculars }.count, 2)
        XCTAssertEqual(
            try XCTUnwrap(savedItems.first { $0.name == "Five Inch Refractor" }?.apertureMillimeters),
            127,
            accuracy: 0.000_001
        )
        XCTAssertEqual(savedItems.first { $0.name == "Five Inch Refractor" }?.apertureUnit, .inches)

        let itemToDelete = try XCTUnwrap(savedItems.first { $0.id == secondBinoculars.id })
        readContext.delete(itemToDelete)
        try readContext.save()

        let remainingItems = try ModelContext(container).fetch(FetchDescriptor<EquipmentItem>())
        XCTAssertEqual(remainingItems.count, 2)
        XCTAssertFalse(remainingItems.contains { $0.id == secondBinoculars.id })
    }

    func testMillimeterUnitPreferenceRoundTripsThroughPersistenceAndEditing() throws {
        let initialDraft = try EquipmentDraft(
            name: "Six Inch Newtonian",
            type: .visualTelescope,
            magnification: nil,
            aperture: 150,
            apertureUnit: .millimeters
        )
        let item = EquipmentItem(draft: initialDraft)

        XCTAssertEqual(item.apertureUnit, .millimeters)
        let displayed = EquipmentFormatting.apertureInputText(
            fromMillimeters: item.apertureMillimeters,
            unit: try XCTUnwrap(item.apertureUnit),
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(displayed, "150")

        let editedDraft = try EquipmentDraft(
            name: item.name,
            type: try XCTUnwrap(item.type),
            magnification: item.magnification,
            aperture: numericValue(from: displayed, locale: Locale(identifier: "en_US")),
            apertureUnit: try XCTUnwrap(item.apertureUnit)
        )
        item.apply(editedDraft)
        XCTAssertEqual(item.apertureMillimeters, 150)
        XCTAssertEqual(item.apertureUnit, .millimeters)
    }

    func testInchUnitPreferenceRoundTripsWithoutConversionDrift() throws {
        let item = EquipmentItem(draft: try EquipmentDraft(
            name: "Five Inch Refractor",
            type: .visualTelescope,
            magnification: nil,
            aperture: 5,
            apertureUnit: .inches
        ))

        for _ in 0..<3 {
            let displayed = EquipmentFormatting.apertureInputText(
                fromMillimeters: item.apertureMillimeters,
                unit: try XCTUnwrap(item.apertureUnit),
                locale: Locale(identifier: "en_US")
            )
            XCTAssertEqual(displayed, "5")

            item.apply(try EquipmentDraft(
                name: item.name,
                type: try XCTUnwrap(item.type),
                magnification: item.magnification,
                aperture: numericValue(from: displayed, locale: Locale(identifier: "en_US")),
                apertureUnit: try XCTUnwrap(item.apertureUnit)
            ))
        }

        XCTAssertEqual(item.apertureMillimeters, 127, accuracy: 0.000_001)
        XCTAssertEqual(item.apertureUnit, .inches)
    }

    func testUnknownPersistedApertureUnitIsQuarantined() {
        let item = EquipmentItem(
            name: "Legacy Telescope",
            equipmentTypeRawValue: EquipmentType.visualTelescope.rawValue,
            magnification: nil,
            apertureMillimeters: 127,
            apertureUnitRawValue: "unknown-unit"
        )

        XCTAssertNil(item.apertureUnit)
        XCTAssertTrue(item.persistedValidation.issues.contains(.unknownApertureUnit))
        XCTAssertNil(item.matchingCapability)
    }

    func testSmartTelescopeWithAperturePreservesChosenUnitPreference() throws {
        let item = EquipmentItem(draft: try EquipmentDraft(
            name: "Seestar S30 Pro",
            type: .smartTelescope,
            magnification: nil,
            aperture: 30,
            apertureUnit: .millimeters
        ))

        XCTAssertEqual(item.apertureMillimeters, 30)
        XCTAssertEqual(item.apertureUnit, .millimeters)
    }

    func testEquipmentItemMapsOnlyNormalizedMatchingCapabilities() throws {
        let item = EquipmentItem(draft: try EquipmentDraft(
            name: "10×50",
            type: .binoculars,
            magnification: 10,
            aperture: 2,
            apertureUnit: .inches
        ))

        let capability = try XCTUnwrap(item.matchingCapability)
        XCTAssertEqual(capability.id, .savedEquipment(item.id))
        XCTAssertEqual(capability.magnification, 10)
        XCTAssertEqual(try XCTUnwrap(capability.apertureMillimeters), 50.8, accuracy: 0.000_001)
    }

    func testUnknownPersistedTypeDoesNotBecomeBinocularsOrEnterMatching() {
        let item = EquipmentItem(
            name: "Legacy Optic",
            equipmentTypeRawValue: "future-optic",
            magnification: 10,
            apertureMillimeters: 50,
            apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue
        )

        XCTAssertNil(item.type)
        XCTAssertTrue(item.persistedValidation.issues.contains(.unknownType))
        XCTAssertNil(item.matchingCapability)
        XCTAssertEqual(item.detailText, "Unavailable — repair or delete")
    }

    func testMalformedPersistedNumericValuesAreQuarantinedAndFormattersAreTotal() {
        let invalidValues: [Double] = [0, -1, .nan, .infinity, -.infinity, Double.greatestFiniteMagnitude]
        for value in invalidValues {
            let item = EquipmentItem(
                name: "Persisted Binoculars",
                equipmentTypeRawValue: EquipmentType.binoculars.rawValue,
                magnification: value,
                apertureMillimeters: value,
                apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue
            )

            XCTAssertFalse(item.persistedValidation.isAvailable, "Expected quarantine for \(value)")
            XCTAssertNil(item.matchingCapability)
            XCTAssertFalse(EquipmentFormatting.millimeters(value).isEmpty)
            XCTAssertFalse(EquipmentFormatting.decimalText(value, locale: Locale(identifier: "en_US")).isEmpty)
        }
    }

    func testBlankNameMissingMagnificationAndOversizedValuesAreQuarantined() {
        let cases = [
            EquipmentItem(name: "  ", equipmentTypeRawValue: EquipmentType.visualTelescope.rawValue, magnification: nil, apertureMillimeters: 100, apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue),
            EquipmentItem(name: "Binoculars", equipmentTypeRawValue: EquipmentType.binoculars.rawValue, magnification: nil, apertureMillimeters: 50, apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue),
            EquipmentItem(name: "Binoculars", equipmentTypeRawValue: EquipmentType.binoculars.rawValue, magnification: 101, apertureMillimeters: 50, apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue),
            EquipmentItem(name: "Scope", equipmentTypeRawValue: EquipmentType.visualTelescope.rawValue, magnification: nil, apertureMillimeters: 2_001, apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue)
        ]

        for item in cases {
            XCTAssertFalse(item.persistedValidation.isAvailable)
            XCTAssertNil(item.matchingCapability)
        }
        XCTAssertEqual(cases[0].inventoryDisplayName, "Unnamed Equipment")
    }

    func testRepairingInvalidRecordMakesItMatchable() throws {
        let item = EquipmentItem(
            name: "Legacy Optic",
            equipmentTypeRawValue: "future-optic",
            magnification: .nan,
            apertureMillimeters: .infinity,
            apertureUnitRawValue: "future-unit"
        )
        XCTAssertNil(item.matchingCapability)

        item.apply(try EquipmentDraft(
            name: "Repaired 10×50",
            type: .binoculars,
            magnification: 10,
            aperture: 50,
            apertureUnit: .millimeters
        ))

        XCTAssertTrue(item.persistedValidation.isAvailable)
        XCTAssertNotNil(item.matchingCapability)
    }

    func testFailedAddSaveRemovesRejectedInsertion() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let draft = try EquipmentDraft(
            name: "Rejected Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 150,
            apertureUnit: .millimeters
        )

        XCTAssertThrowsError(
            try EquipmentPersistence.save(
                draft: draft,
                editing: nil,
                in: context,
                performSave: { _ in throw EquipmentPersistenceTestError.rejected }
            )
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<EquipmentItem>()).isEmpty)
    }

    func testFailedEditSaveRestoresEveryOriginalFieldAndCapability() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let item = EquipmentItem(draft: try EquipmentDraft(
            name: "Original 10×50",
            type: .binoculars,
            magnification: 10,
            aperture: 2,
            apertureUnit: .inches
        ))
        context.insert(item)
        try context.save()
        let originalCapability = try XCTUnwrap(item.matchingCapability)
        let rejectedDraft = try EquipmentDraft(
            name: "Rejected Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 200,
            apertureUnit: .millimeters
        )

        XCTAssertThrowsError(
            try EquipmentPersistence.save(
                draft: rejectedDraft,
                editing: item,
                in: context,
                performSave: { _ in throw EquipmentPersistenceTestError.rejected }
            )
        )

        XCTAssertEqual(item.name, "Original 10×50")
        XCTAssertEqual(item.type, .binoculars)
        XCTAssertEqual(item.magnification, 10)
        XCTAssertEqual(item.apertureMillimeters, 50.8, accuracy: 0.000_001)
        XCTAssertEqual(item.apertureUnit, .inches)
        XCTAssertEqual(item.matchingCapability, originalCapability)
    }

    func testFailedEditRestoresUncommittedScreenEntrySnapshotAndPreservesUnrelatedPendingChanges() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let item = EquipmentItem(draft: try EquipmentDraft(
            name: "Committed Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 100,
            apertureUnit: .millimeters
        ))
        let unrelated = EquipmentItem(draft: try EquipmentDraft(
            name: "Committed Binoculars",
            type: .binoculars,
            magnification: 8,
            aperture: 42,
            apertureUnit: .millimeters
        ))
        context.insert(item)
        context.insert(unrelated)
        try context.save()

        item.apply(try EquipmentDraft(
            name: "Screen Entry Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 125,
            apertureUnit: .millimeters
        ))
        unrelated.name = "Pending Binocular Rename"
        let pendingInsertion = EquipmentItem(draft: try EquipmentDraft(
            name: "Pending Smart Scope",
            type: .smartTelescope,
            magnification: nil,
            aperture: 50,
            apertureUnit: .millimeters
        ))
        context.insert(pendingInsertion)

        XCTAssertThrowsError(
            try EquipmentPersistence.save(
                draft: EquipmentDraft(name: "Rejected Edit", type: .visualTelescope, magnification: nil, aperture: 200, apertureUnit: .millimeters),
                editing: item,
                in: context,
                performSave: { _ in throw EquipmentPersistenceTestError.rejected }
            )
        )

        XCTAssertEqual(item.name, "Screen Entry Scope")
        XCTAssertEqual(item.apertureMillimeters, 125)
        XCTAssertEqual(unrelated.name, "Pending Binocular Rename")
        XCTAssertTrue(try context.fetch(FetchDescriptor<EquipmentItem>()).contains { $0 === pendingInsertion })
        XCTAssertTrue(context.hasChanges)
    }

    func testFailedAddCancelsOnlyRejectedInsertionAndPreservesUnrelatedPendingChanges() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let unrelated = EquipmentItem(draft: try EquipmentDraft(
            name: "Existing Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 100,
            apertureUnit: .millimeters
        ))
        context.insert(unrelated)
        try context.save()
        unrelated.name = "Pending Existing Scope"
        let pendingInsertion = EquipmentItem(draft: try EquipmentDraft(
            name: "Pending Binoculars",
            type: .binoculars,
            magnification: 10,
            aperture: 50,
            apertureUnit: .millimeters
        ))
        context.insert(pendingInsertion)

        XCTAssertThrowsError(
            try EquipmentPersistence.save(
                draft: EquipmentDraft(name: "Rejected Addition", type: .visualTelescope, magnification: nil, aperture: 150, apertureUnit: .millimeters),
                editing: nil,
                in: context,
                performSave: { _ in throw EquipmentPersistenceTestError.rejected }
            )
        )

        let fetched = try context.fetch(FetchDescriptor<EquipmentItem>())
        XCTAssertEqual(unrelated.name, "Pending Existing Scope")
        XCTAssertTrue(fetched.contains { $0 === pendingInsertion })
        XCTAssertFalse(fetched.contains { $0.name == "Rejected Addition" })
        XCTAssertTrue(context.hasChanges)
    }

    func testFailedRepairRestoresInvalidQuarantineState() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let item = EquipmentItem(
            name: "Legacy Optic",
            equipmentTypeRawValue: "future-optic",
            magnification: 10,
            apertureMillimeters: 50,
            apertureUnitRawValue: EquipmentApertureUnit.millimeters.rawValue
        )
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(
            try EquipmentPersistence.save(
                draft: EquipmentDraft(name: "Repair", type: .binoculars, magnification: 10, aperture: 50, apertureUnit: .millimeters),
                editing: item,
                in: context,
                performSave: { _ in throw EquipmentPersistenceTestError.rejected }
            )
        )
        XCTAssertNil(item.type)
        XCTAssertNil(item.matchingCapability)
    }

    func testSuccessfulRetryPersistsExactlyOnceAfterFailure() throws {
        let container = try ModelContainer(
            for: EquipmentItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let draft = try EquipmentDraft(
            name: "Retry Scope",
            type: .visualTelescope,
            magnification: nil,
            aperture: 150,
            apertureUnit: .millimeters
        )
        var successfulSaves = 0

        XCTAssertThrowsError(
            try EquipmentPersistence.save(
                draft: draft,
                editing: nil,
                in: context,
                performSave: { _ in throw EquipmentPersistenceTestError.rejected }
            )
        )
        try EquipmentPersistence.save(
            draft: draft,
            editing: nil,
            in: context,
            performSave: { context in
                try context.save()
                successfulSaves += 1
            }
        )

        XCTAssertEqual(successfulSaves, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EquipmentItem>()).map(\.name), ["Retry Scope"])
    }

    func testNakedEyeTargetMatchesBuiltInCapability() {
        let result = EquipmentMatchingService().match(
            target: catalogTarget(id: "moon", type: .moon),
            using: [.nakedEye]
        )

        XCTAssertEqual(result?.bestCapability, .nakedEye)
        XCTAssertEqual(result?.level, .excellent)
        XCTAssertEqual(result?.observingMode, .nakedEye)
    }

    func testNakedEyeSemanticStatesMapWithoutDisplayStringLogic() {
        let matcher = EquipmentMatchingService()

        XCTAssertEqual(catalogTarget(id: "m31").equipmentRequirement.nakedEyeSuitability, .challenging)
        XCTAssertEqual(matcher.match(target: catalogTarget(id: "m31"), using: [.nakedEye])?.level, .challenging)
        XCTAssertEqual(catalogTarget(id: "m42", deepSkyObjectType: .diffuseNebula).equipmentRequirement.nakedEyeSuitability, .challenging)
        XCTAssertEqual(matcher.match(target: catalogTarget(id: "m42", deepSkyObjectType: .diffuseNebula), using: [.nakedEye])?.level, .challenging)
        XCTAssertEqual(catalogTarget(id: "m45", deepSkyObjectType: .openCluster).equipmentRequirement.nakedEyeSuitability, .preferred)
        XCTAssertEqual(matcher.match(target: catalogTarget(id: "m45", deepSkyObjectType: .openCluster), using: [.nakedEye])?.level, .excellent)
    }

    func testUnreviewedMarginalTargetsRemainUnsupportedForNakedEye() {
        let matcher = EquipmentMatchingService()
        for (id, subtype) in [
            ("m13", DeepSkyObjectType.globularCluster),
            ("m5", .globularCluster),
            ("double-cluster", .openCluster),
            ("m33", .galaxy),
            ("m92", .globularCluster)
        ] {
            let target = catalogTarget(id: id, deepSkyObjectType: subtype)
            XCTAssertEqual(target.equipmentRequirement.nakedEyeSuitability, .unsupported, id)
            XCTAssertEqual(matcher.match(target: target, using: [.nakedEye])?.level, .poor, id)
        }
    }

    func testBinocularMagnificationBoundsAndOutsideValuesChangeSuitability() {
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "m45", deepSkyObjectType: .openCluster)

        XCTAssertEqual(matcher.match(target: target, using: [capability(name: "7×50", type: .binoculars, magnification: 7, aperture: 50)])?.level, .excellent)
        XCTAssertEqual(matcher.match(target: target, using: [capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)])?.level, .excellent)
        XCTAssertEqual(matcher.match(target: target, using: [capability(name: "Low", type: .binoculars, magnification: 6.99, aperture: 50)])?.reason, .binocularMagnificationTooLow)
        XCTAssertEqual(matcher.match(target: target, using: [capability(name: "High", type: .binoculars, magnification: 10.01, aperture: 50)])?.reason, .binocularMagnificationTooHigh)
        XCTAssertEqual(matcher.match(target: target, using: [capability(name: "Low", type: .binoculars, magnification: 6.99, aperture: 50)])?.level, .challenging)
        XCTAssertEqual(matcher.match(target: target, using: [capability(name: "High", type: .binoculars, magnification: 10.01, aperture: 50)])?.level, .challenging)
    }

    func testMissingAndInvalidBinocularMagnificationAreChallengingWithAccurateReason() {
        let target = catalogTarget(id: "m45", deepSkyObjectType: .openCluster)
        for value in [nil, 0, -1, .nan, .infinity] as [Double?] {
            let result = EquipmentMatchingService().match(
                target: target,
                using: [capability(name: "Unknown", type: .binoculars, magnification: value, aperture: 50)]
            )
            XCTAssertEqual(result?.level, .challenging)
            XCTAssertEqual(result?.reason, .binocularMagnificationUnknown)
            XCTAssertTrue(result?.explanation.contains("valid binocular magnification") == true)
        }
    }

    func testApertureAndMagnificationLimitationsAreEvaluatedIndependently() {
        let target = catalogTarget(id: "m45", deepSkyObjectType: .openCluster)
        let adequateApertureBadPower = capability(name: "20×50", type: .binoculars, magnification: 20, aperture: 50)
        let inadequateApertureGoodPower = capability(name: "8×20", type: .binoculars, magnification: 8, aperture: 20)

        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [adequateApertureBadPower])?.reason, .binocularMagnificationTooHigh)
        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [inadequateApertureGoodPower])?.reason, .apertureLimited)
    }

    func testMultipleBinocularsChooseSemanticFitIndependentOfInputOrderAndNames() {
        let target = catalogTarget(id: "m45", deepSkyObjectType: .openCluster)
        let goodID = EquipmentCapabilityID.savedEquipment(UUID())
        let poorID = EquipmentCapabilityID.savedEquipment(UUID())
        let good = capability(id: goodID, name: "Zulu", type: .binoculars, magnification: 8, aperture: 50)
        let poor = capability(id: poorID, name: "Alpha", type: .binoculars, magnification: 20, aperture: 50)
        let matcher = EquipmentMatchingService()

        XCTAssertEqual(matcher.match(target: target, using: [poor, good])?.bestCapability.id, goodID)
        XCTAssertEqual(matcher.match(target: target, using: [good, poor])?.bestCapability.id, goodID)
        XCTAssertTrue(matcher.match(target: target, using: [poor, good])?.explanation.hasPrefix("Best selected match") == true)
    }

    func testVerifiedTargetRequirementOverridesAndDeferrals() {
        let m30 = catalogTarget(id: "m30", deepSkyObjectType: .globularCluster).equipmentRequirement
        let m82 = catalogTarget(id: "m82").equipmentRequirement
        let m16 = catalogTarget(id: "m16", deepSkyObjectType: .diffuseNebula).equipmentRequirement
        let m64 = catalogTarget(id: "m64").equipmentRequirement
        let m20 = catalogTarget(id: "m20", deepSkyObjectType: .diffuseNebula).equipmentRequirement
        let albireo = catalogTarget(id: "albireo", deepSkyObjectType: .doubleStar).equipmentRequirement
        let epsilon = catalogTarget(id: "epsilon-lyrae", deepSkyObjectType: .doubleStar).equipmentRequirement

        XCTAssertEqual(m30.binocularSuitability, .practical)
        XCTAssertEqual(m30.practicalBinocularApertureMillimeters, 50)
        XCTAssertEqual(m82.binocularSuitability, .practical)
        XCTAssertEqual(m16.practicalBinocularApertureMillimeters, 42)
        XCTAssertEqual(m64.binocularSuitability, .unsuitable)
        XCTAssertEqual(m64.practicalVisualApertureMillimeters, 100)
        XCTAssertEqual(m64.practicalSmartEAAApertureMillimeters, 40)
        XCTAssertEqual(m20.binocularSuitability, .practical)
        XCTAssertEqual(m20.preferredBinocularMagnification, 15...20)
        XCTAssertEqual(m20.practicalBinocularApertureMillimeters, 70)
        XCTAssertEqual(albireo.practicalVisualApertureMillimeters, 50)
        XCTAssertEqual(albireo.preferredVisualApertureMillimeters, 50)
        XCTAssertFalse(albireo.magnificationBenefit)
        XCTAssertEqual(epsilon.practicalVisualApertureMillimeters, 75)
        XCTAssertEqual(epsilon.preferredVisualApertureMillimeters, 100)
    }

    func testM20SixteenBySeventyIsGoodButNeverExcellent() {
        let target = catalogTarget(id: "m20", deepSkyObjectType: .diffuseNebula)
        let tenByFifty = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let sixteenBySeventy = capability(name: "16×70", type: .binoculars, magnification: 16, aperture: 70)

        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [tenByFifty])?.level, .challenging)
        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [sixteenBySeventy])?.level, .good)
    }

    func testWideTargetPrefersBinocularsOverLargerVisualTelescope() {
        let binoculars = capability(name: "10×50 binoculars", type: .binoculars, magnification: 10, aperture: 50)
        let telescope = capability(name: "Large Dob", type: .visualTelescope, aperture: 300)
        let result = EquipmentMatchingService().match(target: catalogTarget(id: "m45"), using: [telescope, binoculars])

        XCTAssertEqual(result?.bestCapability.id, binoculars.id)
        XCTAssertEqual(result?.level, .excellent)
        XCTAssertEqual(result?.reason, .wideField)
    }

    func testEightByFortyTwoBinocularsArePreferredOverLargeTelescopeForM45() {
        let binoculars = capability(name: "8×42", type: .binoculars, magnification: 8, aperture: 42)
        let telescope = capability(name: "Large Dob", type: .visualTelescope, aperture: 300)
        let result = EquipmentMatchingService().match(target: catalogTarget(id: "m45"), using: [telescope, binoculars])

        XCTAssertEqual(result?.bestCapability.id, binoculars.id)
        XCTAssertEqual(result?.level, .good)
        XCTAssertEqual(result?.reason, .wideField)
    }

    func testLargeVisualTelescopeIsNotExcellentForVeryWideM31() {
        let telescope = capability(name: "Large Dob", type: .visualTelescope, aperture: 300)
        let result = EquipmentMatchingService().match(target: catalogTarget(id: "m31"), using: [telescope])

        XCTAssertEqual(result?.level, .good)
        XCTAssertEqual(result?.reason, .framingLimited)
    }

    func testCompactTargetRewardsVisualApertureAndMagnification() {
        let modest = capability(name: "Small scope", type: .visualTelescope, aperture: 80)
        let larger = capability(name: "Heritage P150", type: .visualTelescope, aperture: 150)
        let target = catalogTarget(id: "jupiter", type: .planet)

        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [modest])?.level, .good)
        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [larger])?.level, .excellent)
    }

    func testLargeVisualTelescopeRemainsExcellentForMediumTarget() {
        let telescope = capability(name: "Large Dob", type: .visualTelescope, aperture: 300)
        let result = EquipmentMatchingService().match(target: catalogTarget(id: "generic-galaxy"), using: [telescope])

        XCTAssertEqual(result?.level, .excellent)
    }

    func testRenamingCapabilitiesDoesNotChangeBestMatch() {
        let binocularID = EquipmentCapabilityID.savedEquipment(UUID())
        let telescopeID = EquipmentCapabilityID.savedEquipment(UUID())
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "m45")
        let original = matcher.match(
            target: target,
            using: [
                capability(id: binocularID, name: "Alpha", type: .binoculars, magnification: 8, aperture: 42),
                capability(id: telescopeID, name: "Zeta", type: .visualTelescope, aperture: 300)
            ]
        )
        let renamed = matcher.match(
            target: target,
            using: [
                capability(id: binocularID, name: "Zulu", type: .binoculars, magnification: 8, aperture: 42),
                capability(id: telescopeID, name: "Alpha", type: .visualTelescope, aperture: 300)
            ]
        )

        XCTAssertEqual(original?.bestCapability.id, binocularID)
        XCTAssertEqual(renamed?.bestCapability.id, binocularID)
    }

    func testReversingCapabilitiesDoesNotChangeBestMatch() {
        let binoculars = capability(name: "Binoculars", type: .binoculars, magnification: 8, aperture: 42)
        let telescope = capability(name: "Telescope", type: .visualTelescope, aperture: 300)
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "m45")

        let forward = matcher.match(target: target, using: [binoculars, telescope])
        let reverse = matcher.match(target: target, using: [telescope, binoculars])

        XCTAssertEqual(forward?.bestCapability.id, binoculars.id)
        XCTAssertEqual(reverse?.bestCapability.id, binoculars.id)
    }

    func testGenuinelyEqualFitsUseStableCapabilityIdentifier() {
        let firstID = EquipmentCapabilityID.savedEquipment(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let secondID = EquipmentCapabilityID.savedEquipment(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let first = capability(id: firstID, name: "Zebra", type: .visualTelescope, aperture: 150)
        let second = capability(id: secondID, name: "Alpha", type: .visualTelescope, aperture: 150)
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "jupiter", type: .planet)

        XCTAssertEqual(matcher.match(target: target, using: [first, second])?.bestCapability.id, firstID)
        XCTAssertEqual(matcher.match(target: target, using: [second, first])?.bestCapability.id, firstID)
    }

    func testUnknownRequirementDoesNotTreatZeroApertureAsSufficient() {
        let telescope = capability(name: "Large Dob", type: .visualTelescope, aperture: 300)
        let result = EquipmentMatchingService().match(
            target: catalogTarget(id: "unclassified-satellite", type: .satellite),
            using: [telescope]
        )

        XCTAssertEqual(result?.level, .challenging)
        XCTAssertEqual(result?.reason, .unknownRequirement)
    }

    func testLargerBinocularApertureImprovesFaintDeepSkyFit() {
        let smaller = capability(name: "8×42", type: .binoculars, magnification: 8, aperture: 42)
        let larger = capability(name: "10×70", type: .binoculars, magnification: 10, aperture: 70)
        let target = catalogTarget(id: "m33")

        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [smaller])?.level, .challenging)
        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [larger])?.level, .good)
    }

    func testBrightWideTargetKeepsCommonBinocularsGoodOrExcellent() {
        let eightByFortyTwo = capability(name: "8×42", type: .binoculars, magnification: 8, aperture: 42)
        let tenByFifty = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let target = catalogTarget(id: "m45")

        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [eightByFortyTwo])?.level, .good)
        XCTAssertEqual(EquipmentMatchingService().match(target: target, using: [tenByFifty])?.level, .excellent)
    }

    func testM77IsChallengingVisuallyButGoodElectronicallyAssistedWithSeestarAperture() {
        let modestVisual = capability(name: "Heritage P100", type: .visualTelescope, aperture: 100)
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let target = catalogTarget(id: "m77")

        let visualResult = EquipmentMatchingService().match(target: target, using: [modestVisual])
        let smartResult = EquipmentMatchingService().match(target: target, using: [smart])

        XCTAssertEqual(visualResult?.level, .challenging)
        XCTAssertEqual(visualResult?.observingMode, .visual)
        XCTAssertEqual(smartResult?.level, .good)
        XCTAssertEqual(smartResult?.observingMode, .electronicallyAssisted)
        XCTAssertTrue(smartResult?.explanation.contains("electronically assisted") == true)
    }

    func testSmartEAASuitabilityMetadataDrivesRepresentativeMatches() {
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let matcher = EquipmentMatchingService()
        let m77 = catalogTarget(id: "m77")
        let m45 = catalogTarget(id: "m45")
        let jupiter = catalogTarget(id: "jupiter", type: .planet)

        XCTAssertEqual(m77.equipmentRequirement.smartEAASuitability, .preferred)
        XCTAssertEqual(m77.equipmentRequirement.practicalSmartEAAApertureMillimeters, 30)
        XCTAssertEqual(m77.equipmentRequirement.preferredSmartEAAApertureMillimeters, 50)
        XCTAssertEqual(m45.equipmentRequirement.smartEAASuitability, .supported)
        XCTAssertEqual(jupiter.equipmentRequirement.smartEAASuitability, .poorMatch)
        XCTAssertEqual(matcher.match(target: m77, using: [smart])?.level, .good)
        XCTAssertEqual(matcher.match(target: m45, using: [smart])?.level, .good)
        XCTAssertEqual(matcher.match(target: jupiter, using: [smart])?.level, .poor)
    }

    func testPreferredSmartEAAUsesApertureToDifferentiateExcellentGoodAndChallenging() {
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "m77")
        let belowPractical = capability(name: "Small Smart Scope", type: .smartTelescope, aperture: 20)
        let practical = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let preferred = capability(name: "Large Smart Scope", type: .smartTelescope, aperture: 50)

        XCTAssertEqual(matcher.match(target: target, using: [belowPractical])?.level, .challenging)
        XCTAssertEqual(matcher.match(target: target, using: [belowPractical])?.reason, .apertureLimited)
        XCTAssertEqual(matcher.match(target: target, using: [practical])?.level, .good)
        XCTAssertEqual(matcher.match(target: target, using: [preferred])?.level, .excellent)
        XCTAssertEqual(matcher.match(target: target, using: [preferred])?.reason, .electronicAssistance)
    }

    func testSupportedSmartEAATargetsNeverBecomeExcellentFromAperture() {
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "m45")
        let belowPractical = capability(name: "Small Smart Scope", type: .smartTelescope, aperture: 20)
        let adequate = capability(name: "Large Smart Scope", type: .smartTelescope, aperture: 60)

        XCTAssertEqual(matcher.match(target: target, using: [belowPractical])?.level, .challenging)
        XCTAssertEqual(matcher.match(target: target, using: [adequate])?.level, .good)
        XCTAssertEqual(matcher.match(target: target, using: [adequate])?.reason, .electronicSupport)
    }

    func testSmartEAAPoorMatchAndInvalidApertureRemainPoor() {
        let matcher = EquipmentMatchingService()
        let target = catalogTarget(id: "jupiter", type: .planet)
        let small = capability(name: "Small Smart Scope", type: .smartTelescope, aperture: 10)
        let large = capability(name: "Large Smart Scope", type: .smartTelescope, aperture: 300)
        let missing = capability(name: "Incomplete Smart Scope", type: .smartTelescope, aperture: nil)
        let nonFinite = capability(name: "Invalid Smart Scope", type: .smartTelescope, aperture: .nan)

        XCTAssertEqual(matcher.match(target: target, using: [small])?.level, .poor)
        XCTAssertEqual(matcher.match(target: target, using: [small])?.reason, .modeMismatch)
        XCTAssertEqual(matcher.match(target: target, using: [large])?.level, .poor)
        XCTAssertEqual(matcher.match(target: target, using: [large])?.reason, .modeMismatch)
        XCTAssertEqual(matcher.match(target: target, using: [missing])?.level, .poor)
        XCTAssertEqual(matcher.match(target: target, using: [nonFinite])?.level, .poor)
    }

    func testBroadPreferredSmartEAAIsConservativelyCappedAtGood() {
        let target = catalogTarget(id: "m101")
        let smart = capability(name: "Large Smart Scope", type: .smartTelescope, aperture: 80)
        let result = EquipmentMatchingService().match(target: target, using: [smart])

        XCTAssertEqual(result?.level, .good)
        XCTAssertEqual(result?.reason, .framingLimited)
        XCTAssertEqual(
            result?.explanation,
            "Using “Large Smart Scope”: Good for electronically assisted observing. This broad target may require a wider field than the equipment provides."
        )
    }

    func testNakedEyeExplanationUsesNaturalWording() {
        let result = EquipmentMatchingService().match(
            target: catalogTarget(id: "moon", type: .moon),
            using: [.nakedEye]
        )

        XCTAssertEqual(result?.explanation, "Excellent for naked-eye observing.")
    }

    func testSmartEAAIsPoorForAHighMagnificationVisualTarget() {
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let result = EquipmentMatchingService().match(
            target: catalogTarget(id: "jupiter", type: .planet),
            using: [smart]
        )

        XCTAssertEqual(result?.level, .poor)
        XCTAssertEqual(result?.reason, .modeMismatch)
    }

    func testNakedEyeSupportsPlanetsByCaseInsensitiveID() {
        let matcher = EquipmentMatchingService()
        for id in ["JUPITER", "Saturn", "mars", "vEnUs"] {
            let result = matcher.match(target: catalogTarget(id: id, type: .planet), using: [.nakedEye])
            XCTAssertEqual(result?.level, .good, "Expected Naked Eye support for \(id)")
            XCTAssertEqual(result?.observingMode, .nakedEye)
        }
    }

    func testVisualTelescopeIsPreferredOverNakedEyeForPlanetaryDetail() {
        let telescope = capability(name: "Heritage P150", type: .visualTelescope, aperture: 150)
        let result = EquipmentMatchingService().match(
            target: catalogTarget(id: "jupiter", type: .planet),
            using: [.nakedEye, telescope]
        )

        XCTAssertEqual(result?.bestCapability.id, telescope.id)
        XCTAssertEqual(result?.level, .excellent)
    }

    func testOverridesDifferentiateM31M77M45M36AndM38() {
        let binoculars = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let matcher = EquipmentMatchingService()

        XCTAssertEqual(catalogTarget(id: "m45").equipmentRequirement.framing, .veryWide)
        XCTAssertEqual(catalogTarget(id: "m36").equipmentRequirement.framing, .medium)
        XCTAssertEqual(catalogTarget(id: "m38").equipmentRequirement.framing, .wide)
        XCTAssertEqual(catalogTarget(id: "m77").equipmentRequirement.practicalVisualApertureMillimeters, 150)
        XCTAssertEqual(matcher.match(target: catalogTarget(id: "m31"), using: [binoculars])?.level, .excellent)
        XCTAssertEqual(matcher.match(target: catalogTarget(id: "m77"), using: [binoculars])?.level, .poor)
    }

    func testSessionSelectionAllModeAndCustomModeHandleInventoryChanges() {
        let first = capability(name: "Binoculars", type: .binoculars, magnification: 10, aperture: 50)
        let second = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var selection = EquipmentSessionSelection()

        XCTAssertEqual(selection.selectedCapabilities(from: [first]).count, 2)
        XCTAssertEqual(selection.selectedCapabilities(from: [first, second]).count, 3)

        selection.selectNakedEyeOnly()
        selection.toggle(first.id, inventory: [first, second])
        XCTAssertEqual(selection.selectedCapabilities(from: [first, second]).map(\.id), [.nakedEye, first.id])

        let third = capability(name: "Smart scope", type: .smartTelescope, aperture: 30)
        XCTAssertFalse(selection.selectedCapabilities(from: [first, second, third]).contains { $0.id == third.id })

        selection.reconcile(with: [second, third])
        XCTAssertEqual(selection.selectedCapabilities(from: [second, third]).map(\.id), [.nakedEye])
    }

    func testSetSelectedIsIdempotentForAlreadySelectedAndDeselectedCapabilities() {
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var selection = EquipmentSessionSelection()

        selection.setSelected(true, for: telescope.id, inventory: [telescope])
        XCTAssertEqual(selection.mode, .allEquipment)
        XCTAssertEqual(selection.selectedCapabilities(from: [telescope]).map(\.id), [.nakedEye, telescope.id])

        selection.selectNakedEyeOnly()
        selection.setSelected(false, for: telescope.id, inventory: [telescope])
        XCTAssertEqual(selection.mode, .custom)
        XCTAssertEqual(selection.selectedCapabilities(from: [telescope]).map(\.id), [.nakedEye])
    }

    func testSetSelectedConvertsAllEquipmentToCustomAndPreservesOtherCapabilities() {
        let binoculars = capability(name: "Binoculars", type: .binoculars, magnification: 10, aperture: 50)
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var selection = EquipmentSessionSelection()

        selection.setSelected(false, for: telescope.id, inventory: [binoculars, telescope])

        XCTAssertEqual(selection.mode, .custom)
        XCTAssertEqual(selection.selectedCapabilities(from: [binoculars, telescope]).map(\.id), [.nakedEye, binoculars.id])
    }

    func testSetSelectedUpdatesCustomSelectionAndPreservesFinalCapability() {
        let binoculars = capability(name: "Binoculars", type: .binoculars, magnification: 10, aperture: 50)
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var selection = EquipmentSessionSelection()
        selection.selectNakedEyeOnly()

        selection.setSelected(true, for: telescope.id, inventory: [binoculars, telescope])
        XCTAssertEqual(selection.selectedCapabilities(from: [binoculars, telescope]).map(\.id), [.nakedEye, telescope.id])

        selection.setSelected(false, for: telescope.id, inventory: [binoculars, telescope])
        XCTAssertEqual(selection.selectedCapabilities(from: [binoculars, telescope]).map(\.id), [.nakedEye])

        selection.setSelected(true, for: binoculars.id, inventory: [binoculars, telescope])
        selection.setSelected(false, for: .nakedEye, inventory: [binoculars, telescope])
        XCTAssertEqual(selection.selectedCapabilities(from: [binoculars, telescope]).map(\.id), [binoculars.id])

        selection.setSelected(false, for: binoculars.id, inventory: [binoculars, telescope])
        XCTAssertEqual(selection.selectedCapabilities(from: [binoculars, telescope]).map(\.id), [.nakedEye])
    }

    func testToggleMatchesSetSelectedInverseAndRepeatedAssignmentsRemainStable() {
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var throughToggle = EquipmentSessionSelection()
        var throughSetter = EquipmentSessionSelection()

        throughToggle.toggle(telescope.id, inventory: [telescope])
        throughSetter.setSelected(false, for: telescope.id, inventory: [telescope])
        XCTAssertEqual(throughToggle, throughSetter)

        throughSetter.setSelected(true, for: telescope.id, inventory: [telescope])
        throughSetter.setSelected(true, for: telescope.id, inventory: [telescope])
        XCTAssertTrue(throughSetter.isSelected(telescope.id, inventory: [telescope]))
        throughSetter.setSelected(false, for: telescope.id, inventory: [telescope])
        throughSetter.setSelected(false, for: telescope.id, inventory: [telescope])
        XCTAssertFalse(throughSetter.isSelected(telescope.id, inventory: [telescope]))
    }

    func testInventoryBecomingEmptyResetsMinimumFitAndReconcilesSelection() {
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var selection = EquipmentSessionSelection()
        selection.selectNakedEyeOnly()
        selection.toggle(telescope.id, inventory: [telescope])
        selection.toggle(.nakedEye, inventory: [telescope])

        selection.reconcile(with: [])
        let minimumFit = EquipmentSessionSelection.minimumFitAfterInventoryTransition(
            currentMinimumFit: .excellentOnly,
            previousInventoryIDs: [telescope.id],
            currentInventoryIDs: []
        )

        XCTAssertEqual(minimumFit, .any)
        XCTAssertEqual(selection.selectedCapabilities(from: []).map(\.id), [.nakedEye])
    }

    func testMinimumFitIsPreservedForNonEmptyInventoryChangesAndEdits() {
        let first = capability(name: "Binoculars", type: .binoculars, magnification: 10, aperture: 50)
        let second = capability(name: "Scope", type: .visualTelescope, aperture: 150)

        XCTAssertEqual(
            EquipmentSessionSelection.minimumFitAfterInventoryTransition(
                currentMinimumFit: .goodOrBetter,
                previousInventoryIDs: [first.id, second.id],
                currentInventoryIDs: [first.id]
            ),
            .goodOrBetter
        )
        XCTAssertEqual(
            EquipmentSessionSelection.minimumFitAfterInventoryTransition(
                currentMinimumFit: .excellentOnly,
                previousInventoryIDs: [first.id],
                currentInventoryIDs: [first.id]
            ),
            .excellentOnly
        )
    }

    func testAddingEquipmentToAnEmptyInventoryPreservesAnyMinimumFit() {
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)

        XCTAssertEqual(
            EquipmentSessionSelection.minimumFitAfterInventoryTransition(
                currentMinimumFit: .any,
                previousInventoryIDs: [],
                currentInventoryIDs: [telescope.id]
            ),
            .any
        )
    }

    func testDeselectingFinalSessionCapabilityFallsBackToNakedEye() {
        var selection = EquipmentSessionSelection()
        selection.selectNakedEyeOnly()
        selection.toggle(.nakedEye, inventory: [])

        XCTAssertEqual(selection.selectedCapabilities(from: []).map(\.id), [.nakedEye])
    }

    func testDeletingFinalSelectedSavedEquipmentFallsBackToNakedEye() {
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        var selection = EquipmentSessionSelection()
        selection.selectNakedEyeOnly()
        selection.toggle(telescope.id, inventory: [telescope])
        selection.toggle(.nakedEye, inventory: [telescope])
        selection.reconcile(with: [])

        XCTAssertEqual(selection.selectedCapabilities(from: []).map(\.id), [.nakedEye])
    }

    func testTelescopeOnlyAndBinocularOnlySelectionsRemainValid() {
        let telescope = capability(name: "Scope", type: .visualTelescope, aperture: 150)
        let binoculars = capability(name: "Binoculars", type: .binoculars, magnification: 10, aperture: 50)
        var selection = EquipmentSessionSelection()

        selection.toggle(.nakedEye, inventory: [telescope, binoculars])
        selection.toggle(binoculars.id, inventory: [telescope, binoculars])
        XCTAssertEqual(selection.selectedCapabilities(from: [telescope, binoculars]).map(\.id), [telescope.id])

        selection.selectNakedEyeOnly()
        selection.toggle(binoculars.id, inventory: [telescope, binoculars])
        selection.toggle(.nakedEye, inventory: [telescope, binoculars])
        XCTAssertEqual(selection.selectedCapabilities(from: [telescope, binoculars]).map(\.id), [binoculars.id])
    }

    func testDashboardAndRecreatedViewAllUseSameSessionEquipmentFit() {
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let telescope = capability(name: "Dobsonian", type: .visualTelescope, aperture: 150)
        let inventory = [smart, telescope]
        var dashboardSelection = EquipmentSessionSelection()
        dashboardSelection.selectNakedEyeOnly()
        dashboardSelection.toggle(smart.id, inventory: inventory)
        dashboardSelection.toggle(.nakedEye, inventory: inventory)
        let target = catalogTarget(id: "m77")

        let dashboardFit = dashboardSelection.equipmentFit(for: target, inventory: inventory)
        // A recreated View All receives the Dashboard-owned selection instead
        // of constructing a new one.
        let recreatedViewAllFit = dashboardSelection.equipmentFit(for: target, inventory: inventory)

        XCTAssertEqual(dashboardSelection.selectedCapabilities(from: inventory).map(\.id), [smart.id])
        XCTAssertEqual(dashboardFit, recreatedViewAllFit)
        XCTAssertEqual(dashboardFit?.bestCapability.id, smart.id)
        XCTAssertEqual(dashboardFit?.level, .good)
    }

    func testEquipmentSessionFitRemainsGenericWithoutSavedInventory() {
        let selection = EquipmentSessionSelection()
        let fit = selection.equipmentFit(for: catalogTarget(id: "m45"), inventory: [])

        XCTAssertNil(fit)
    }

    func testAnyEquipmentThresholdPreservesConditionsOrderingAndScores() {
        let binoculars = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let recommendations = [
            recommendation(for: catalogTarget(id: "m45"), score: 90),
            recommendation(for: catalogTarget(id: "jupiter", type: .planet), score: 80),
            recommendation(for: catalogTarget(id: "m77"), score: 70)
        ]
        let transformed = EquipmentSessionSelection().filteredRecommendations(
            recommendations,
            inventory: [binoculars],
            minimumFit: .any
        )

        XCTAssertEqual(transformed.map(\.id), recommendations.map(\.id))
        XCTAssertEqual(transformed.map(\.score), recommendations.map(\.score))
    }

    func testEquipmentFitThresholdsIncludeExpectedLevelsAndPreserveOrder() {
        let tenByFifty = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let bright = recommendation(for: catalogTarget(id: "m45"), score: 90)
        let planet = recommendation(for: catalogTarget(id: "jupiter", type: .planet), score: 80)
        let poor = recommendation(for: catalogTarget(id: "m77"), score: 70)
        let goodOrBetter = EquipmentSessionSelection().filteredRecommendations(
            [bright, planet, poor],
            inventory: [tenByFifty],
            minimumFit: .goodOrBetter
        )

        XCTAssertEqual(goodOrBetter.map(\.id), [bright.id, planet.id])
        XCTAssertTrue(EquipmentFitThreshold.challengingOrBetter.includes(.challenging))
        XCTAssertFalse(EquipmentFitThreshold.challengingOrBetter.includes(.poor))
        XCTAssertEqual(
            EquipmentSessionSelection().filteredRecommendations(
                [bright, planet, poor],
                inventory: [tenByFifty],
                minimumFit: .excellentOnly
            ).map(\.id),
            [bright.id]
        )
    }

    func testEquipmentSuitabilityThresholdPresentationLabelsAndOrder() {
        XCTAssertEqual(EquipmentFitThreshold.excellentOnly.displayName, "Excellent")
        XCTAssertEqual(EquipmentFitThreshold.goodOrBetter.displayName, "Good")
        XCTAssertEqual(EquipmentFitThreshold.challengingOrBetter.displayName, "Challenging")
        XCTAssertEqual(EquipmentFitThreshold.any.displayName, "Any")
        XCTAssertEqual(
            EquipmentFitThreshold.presentationOrder,
            [.excellentOnly, .goodOrBetter, .challengingOrBetter, .any]
        )
        XCTAssertEqual(EquipmentFitThreshold.excellentOnly.dashboardSummary, "Show targets: Excellent only")
        XCTAssertEqual(EquipmentFitThreshold.goodOrBetter.dashboardSummary, "Show targets: Good or better")
        XCTAssertEqual(EquipmentFitThreshold.challengingOrBetter.dashboardSummary, "Show targets: Challenging or better")
        XCTAssertEqual(EquipmentFitThreshold.any.dashboardSummary, "Show targets: Any suitability")
        XCTAssertEqual(
            EquipmentFitThreshold.excellentOnly.dashboardAccessibilitySummary,
            "Show targets with Excellent suitability only."
        )
        XCTAssertEqual(
            EquipmentFitThreshold.goodOrBetter.dashboardAccessibilitySummary,
            "Show targets with Good suitability or better."
        )
        XCTAssertEqual(
            EquipmentFitThreshold.challengingOrBetter.dashboardAccessibilitySummary,
            "Show targets with Challenging suitability or better."
        )
        XCTAssertEqual(
            EquipmentFitThreshold.any.dashboardAccessibilitySummary,
            "Show targets with any equipment suitability."
        )
    }

    func testEquipmentThresholdInclusionSemanticsRemainUnchanged() {
        XCTAssertTrue(EquipmentFitThreshold.goodOrBetter.includes(.excellent))
        XCTAssertTrue(EquipmentFitThreshold.goodOrBetter.includes(.good))
        XCTAssertFalse(EquipmentFitThreshold.goodOrBetter.includes(.challenging))
        XCTAssertFalse(EquipmentFitThreshold.goodOrBetter.includes(.poor))
        XCTAssertTrue(EquipmentFitThreshold.challengingOrBetter.includes(.excellent))
        XCTAssertTrue(EquipmentFitThreshold.challengingOrBetter.includes(.good))
        XCTAssertTrue(EquipmentFitThreshold.challengingOrBetter.includes(.challenging))
        XCTAssertFalse(EquipmentFitThreshold.challengingOrBetter.includes(.poor))
    }

    func testSuitabilityExplanationsUseObservingTerminology() {
        let visual = capability(name: "Heritage P150", type: .visualTelescope, aperture: 150)
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let matcher = EquipmentMatchingService()
        let visualExplanation = matcher.match(
            target: catalogTarget(id: "jupiter", type: .planet),
            using: [visual]
        )?.explanation
        let electronicExplanation = matcher.match(
            target: catalogTarget(id: "m77"),
            using: [smart]
        )?.explanation

        XCTAssertEqual(
            visualExplanation,
            "Using “Heritage P150”: Excellent for visual observing. Useful magnification can reveal more detail."
        )
        XCTAssertEqual(
            electronicExplanation,
            "Using “Seestar S30 Pro”: Good for electronically assisted observing. Electronic capture can reveal faint structure that is difficult to see visually."
        )
        XCTAssertFalse(visualExplanation?.localizedCaseInsensitiveContains("match") == true)
        XCTAssertFalse(electronicExplanation?.localizedCaseInsensitiveContains("match") == true)
    }

    func testChallengingThresholdExcludesOnlyPoorFit() {
        let eightByFortyTwo = capability(name: "8×42", type: .binoculars, magnification: 8, aperture: 42)
        let good = recommendation(for: catalogTarget(id: "m45"), score: 90)
        let challenging = recommendation(for: catalogTarget(id: "m33"), score: 80)
        let poor = recommendation(for: catalogTarget(id: "m77"), score: 70)
        let transformed = EquipmentSessionSelection().filteredRecommendations(
            [good, challenging, poor],
            inventory: [eightByFortyTwo],
            minimumFit: .challengingOrBetter
        )

        XCTAssertEqual(transformed.map(\.id), [good.id, challenging.id])
    }

    func testEquipmentFilteringOccursBeforeDashboardLimitAndUsesBestSelectedFit() {
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let modestVisual = capability(name: "Heritage P100", type: .visualTelescope, aperture: 100)
        let binoculars = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let rejected = (0..<5).map { index in
            recommendation(for: catalogTarget(id: "m77"), score: 95 - index)
        }
        let sixth = recommendation(for: catalogTarget(id: "m45"), score: 60)
        let filtered = EquipmentSessionSelection().filteredRecommendations(
            rejected + [sixth],
            inventory: [binoculars],
            minimumFit: .goodOrBetter
        )

        XCTAssertEqual(filtered.map(\.id), [sixth.id])
        XCTAssertEqual(Array(filtered.prefix(5)).map(\.id), [sixth.id])
        XCTAssertEqual(EquipmentSessionSelection().equipmentFit(for: catalogTarget(id: "m77"), inventory: [smart, modestVisual])?.level, .good)
    }

    func testDashboardAndViewAllShareDashboardOwnedSelectionAndThreshold() {
        let smart = capability(name: "Seestar S30 Pro", type: .smartTelescope, aperture: 30)
        let binoculars = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let inventory = [smart, binoculars]
        let recommendations = [
            recommendation(for: catalogTarget(id: "m77"), score: 90),
            recommendation(for: catalogTarget(id: "m45"), score: 80),
            recommendation(for: catalogTarget(id: "jupiter", type: .planet), score: 70)
        ]
        var dashboardSelection = EquipmentSessionSelection()
        dashboardSelection.selectNakedEyeOnly()
        dashboardSelection.toggle(smart.id, inventory: inventory)
        dashboardSelection.toggle(.nakedEye, inventory: inventory)
        let dashboardThreshold: EquipmentFitThreshold = .goodOrBetter

        let dashboardRecommendations = dashboardSelection.filteredRecommendations(
            recommendations,
            inventory: inventory,
            minimumFit: dashboardThreshold
        )
        // Recreating View All receives the same Dashboard-owned state.
        let recreatedViewAllRecommendations = dashboardSelection.filteredRecommendations(
            recommendations,
            inventory: inventory,
            minimumFit: dashboardThreshold
        )

        XCTAssertEqual(dashboardSelection.selectedCapabilities(from: inventory).map(\.id), [smart.id])
        XCTAssertEqual(dashboardRecommendations, recreatedViewAllRecommendations)
        XCTAssertEqual(dashboardRecommendations.map(\.id), [recommendations[0].id, recommendations[1].id])
        XCTAssertEqual(dashboardThreshold, .goodOrBetter)
    }

    func testNoInventoryBypassesThresholdAndResetToAnyRestoresTargets() {
        let recommendations = [
            recommendation(for: catalogTarget(id: "m45"), score: 90),
            recommendation(for: catalogTarget(id: "m77"), score: 80)
        ]
        let selection = EquipmentSessionSelection()

        XCTAssertEqual(
            selection.filteredRecommendations(recommendations, inventory: [], minimumFit: .excellentOnly),
            recommendations
        )

        let binoculars = capability(name: "10×50", type: .binoculars, magnification: 10, aperture: 50)
        let filtered = selection.filteredRecommendations(
            recommendations,
            inventory: [binoculars],
            minimumFit: .excellentOnly
        )
        XCTAssertEqual(filtered.map(\.id), [recommendations[0].id])
        XCTAssertEqual(
            selection.filteredRecommendations(recommendations, inventory: [binoculars], minimumFit: .any),
            recommendations
        )
    }

    private func XCTAssertValidationError(
        _ expectedError: EquipmentValidationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? EquipmentValidationError, expectedError, file: file, line: line)
        }
    }

    private func numericValue(from text: String, locale: Locale) throws -> Double {
        guard case let .value(value) = EquipmentFormatting.decimalInput(from: text, locale: locale) else {
            XCTFail("Expected a valid numeric input: \(text)")
            return 0
        }
        return value
    }

    private func capability(
        id: EquipmentCapabilityID = .savedEquipment(UUID()),
        name: String,
        type: EquipmentType,
        magnification: Double? = nil,
        aperture: Double? = nil
    ) -> EquipmentCapability {
        EquipmentCapability(
            id: id,
            displayName: name,
            type: type,
            magnification: magnification,
            apertureMillimeters: aperture
        )
    }

    private func catalogTarget(
        id: String,
        type: ObservableTargetType = .deepSky,
        deepSkyObjectType: DeepSkyObjectType = .galaxy
    ) -> ObservableTarget {
        ObservableTarget(
            id: id,
            name: id.uppercased(),
            type: type,
            preferredEquipment: .telescope,
            difficulty: 0.5,
            deepSkyObjectType: type == .deepSky ? deepSkyObjectType : nil
        )
    }

    private func recommendation(for target: ObservableTarget, score: Int) -> TargetRecommendation {
        TargetRecommendation(
            target: target,
            score: score,
            visibilityWindow: TargetVisibilityWindow(
                start: Date(),
                end: Date().addingTimeInterval(3_600),
                bestTime: Date().addingTimeInterval(1_800),
                maxAltitude: 45,
                direction: "S"
            ),
            reasons: [.highAltitude],
            summary: "Test recommendation."
        )
    }
}

private enum EquipmentPersistenceTestError: Error {
    case rejected
}
