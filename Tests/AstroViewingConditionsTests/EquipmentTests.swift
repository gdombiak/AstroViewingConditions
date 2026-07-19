import SwiftData
import XCTest
@testable import SharedCode

@MainActor
final class EquipmentTests: XCTestCase {
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

        XCTAssertEqual(try XCTUnwrap(draft.apertureMillimeters), 127, accuracy: 0.000_001)
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

    func testSmartTelescopeAllowsMissingApertureButRejectsInvalidProvidedValue() throws {
        let draft = try EquipmentDraft(
            name: "Seestar",
            type: .smartTelescope,
            magnification: nil,
            aperture: nil,
            apertureUnit: .millimeters
        )
        XCTAssertNil(draft.apertureMillimeters)
        XCTAssertEqual(draft.apertureUnit, .millimeters)

        XCTAssertValidationError(.invalidAperture) {
            _ = try EquipmentDraft(name: "Seestar", type: .smartTelescope, magnification: nil, aperture: .infinity, apertureUnit: .millimeters)
        }
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
            fromMillimeters: try XCTUnwrap(item.apertureMillimeters),
            unit: item.apertureUnit,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(displayed, "150")

        let editedDraft = try EquipmentDraft(
            name: item.name,
            type: item.type,
            magnification: item.magnification,
            aperture: numericValue(from: displayed, locale: Locale(identifier: "en_US")),
            apertureUnit: item.apertureUnit
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
                fromMillimeters: try XCTUnwrap(item.apertureMillimeters),
                unit: item.apertureUnit,
                locale: Locale(identifier: "en_US")
            )
            XCTAssertEqual(displayed, "5")

            item.apply(try EquipmentDraft(
                name: item.name,
                type: item.type,
                magnification: item.magnification,
                aperture: numericValue(from: displayed, locale: Locale(identifier: "en_US")),
                apertureUnit: item.apertureUnit
            ))
        }

        XCTAssertEqual(try XCTUnwrap(item.apertureMillimeters), 127, accuracy: 0.000_001)
        XCTAssertEqual(item.apertureUnit, .inches)
    }

    func testUnknownPersistedApertureUnitDefaultsToMillimeters() {
        let item = EquipmentItem(
            name: "Legacy Telescope",
            equipmentTypeRawValue: EquipmentType.visualTelescope.rawValue,
            magnification: nil,
            apertureMillimeters: 127,
            apertureUnitRawValue: "unknown-unit"
        )

        XCTAssertEqual(item.apertureUnit, .millimeters)
    }

    func testSmartTelescopeWithoutAperturePreservesChosenUnitPreference() throws {
        let item = EquipmentItem(draft: try EquipmentDraft(
            name: "Smart Scope",
            type: .smartTelescope,
            magnification: nil,
            aperture: nil,
            apertureUnit: .inches
        ))

        XCTAssertNil(item.apertureMillimeters)
        XCTAssertEqual(item.apertureUnit, .inches)
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
}
