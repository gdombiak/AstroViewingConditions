import Foundation
import AstroEngine

/// Complete WatchConnectivity application-context payload.
///
/// `WCSession.updateApplicationContext` replaces the **entire** dictionary. Type-specific
/// sends (units, locations, conditions) therefore drop any field omitted from the latest
/// write. This snapshot is the single replaceable companion-state document: every publish
/// carries the latest known pieces, and receivers apply only the fields that are present.
public struct WatchCompanionSnapshot: Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var selectedLocation: SelectedLocation?
    public var locations: [CachedLocation]?
    public var conditions: ViewingConditions?
    public var observingQuality: WatchObservingQualityPayload?
    public var unitSystem: UnitSystem?
    public var modeledBrightnessSamples: [ModeledZenithBrightnessSample]
    public var publishedAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        selectedLocation: SelectedLocation? = nil,
        locations: [CachedLocation]? = nil,
        conditions: ViewingConditions? = nil,
        observingQuality: WatchObservingQualityPayload? = nil,
        unitSystem: UnitSystem? = nil,
        modeledBrightnessSamples: [ModeledZenithBrightnessSample] = [],
        publishedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.selectedLocation = selectedLocation
        self.locations = locations
        self.conditions = conditions
        self.observingQuality = observingQuality
        self.unitSystem = unitSystem
        self.modeledBrightnessSamples = modeledBrightnessSamples
        self.publishedAt = publishedAt
    }

    public var hasAnyField: Bool {
        selectedLocation != nil
            || locations != nil
            || conditions != nil
            || observingQuality != nil
            || unitSystem != nil
            || !modeledBrightnessSamples.isEmpty
    }
}

/// Accumulates last-known companion pieces so each application-context write is complete.
public struct WatchCompanionSnapshotAccumulator: Sendable {
    public var selectedLocation: SelectedLocation?
    public var locations: [CachedLocation]?
    public var conditions: ViewingConditions?
    public var observingQuality: WatchObservingQualityPayload?
    public var unitSystem: UnitSystem?
    public var modeledBrightnessSamples: [ModeledZenithBrightnessSample]

    public init(
        selectedLocation: SelectedLocation? = nil,
        locations: [CachedLocation]? = nil,
        conditions: ViewingConditions? = nil,
        observingQuality: WatchObservingQualityPayload? = nil,
        unitSystem: UnitSystem? = nil,
        modeledBrightnessSamples: [ModeledZenithBrightnessSample] = []
    ) {
        self.selectedLocation = selectedLocation
        self.locations = locations
        self.conditions = conditions
        self.observingQuality = observingQuality
        self.unitSystem = unitSystem
        self.modeledBrightnessSamples = modeledBrightnessSamples
    }

    public mutating func setSelectedLocation(_ location: SelectedLocation) {
        selectedLocation = location
        if let conditions,
           !WatchConditionsPushAcceptance.conditionsMatch(conditions, selected: location) {
            self.conditions = nil
            observingQuality = nil
        }
    }

    public mutating func setLocations(
        _ locations: [CachedLocation],
        brightnessSamples: [ModeledZenithBrightnessSample] = []
    ) {
        self.locations = locations
        if !brightnessSamples.isEmpty {
            modeledBrightnessSamples = brightnessSamples
        }
    }

    public mutating func setConditions(
        _ conditions: ViewingConditions,
        observingQuality: WatchObservingQualityPayload?
    ) {
        self.conditions = conditions
        self.observingQuality = observingQuality
    }

    public mutating func setUnitSystem(_ unitSystem: UnitSystem) {
        self.unitSystem = unitSystem
    }

    public func snapshot(publishedAt: Date = Date()) -> WatchCompanionSnapshot {
        WatchCompanionSnapshot(
            selectedLocation: selectedLocation,
            locations: locations,
            conditions: conditions,
            observingQuality: observingQuality,
            unitSystem: unitSystem,
            modeledBrightnessSamples: modeledBrightnessSamples,
            publishedAt: publishedAt
        )
    }
}

/// Dictionary codec for `WCSession` application context.
public enum WatchCompanionSnapshotCodec: Sendable {
    public static let typeKey = "type"
    public static let messageType = "companionSnapshot"
    public static let schemaVersionKey = "schemaVersion"
    public static let selectedLocationKey = "selectedLocation"
    public static let locationsKey = "locations"
    public static let conditionsKey = "conditions"
    public static let observingQualityKey = "observingQuality"
    public static let unitSystemKey = "unitSystem"
    public static let publishedAtKey = "publishedAt"

    public static func encode(_ snapshot: WatchCompanionSnapshot) -> [String: Any]? {
        guard snapshot.schemaVersion > 0 else { return nil }
        var payload: [String: Any] = [
            typeKey: messageType,
            schemaVersionKey: snapshot.schemaVersion,
            publishedAtKey: snapshot.publishedAt,
        ]
        if let selectedLocation = snapshot.selectedLocation,
           let data = encodeJSON(selectedLocation) {
            payload[selectedLocationKey] = data
        }
        if let locations = snapshot.locations,
           let data = encodeJSON(locations) {
            payload[locationsKey] = data
        }
        if let conditions = snapshot.conditions,
           let data = encodeJSON(conditions) {
            payload[conditionsKey] = data
        }
        if let observingQuality = snapshot.observingQuality,
           let data = encodeJSON(observingQuality) {
            payload[observingQualityKey] = data
        }
        if let unitSystem = snapshot.unitSystem,
           let data = encodeJSON(unitSystem.rawValue) {
            payload[unitSystemKey] = data
        }
        if let samplesData = WatchLocationsBrightnessPriming.encodeSamples(
            snapshot.modeledBrightnessSamples
        ) {
            payload[WatchLocationsBrightnessPriming.replyPayloadKey] = samplesData
        }
        return payload
    }

    /// Decodes a versioned snapshot. Unknown future schema versions still apply known keys.
    /// A corrupt optional field is omitted rather than failing the whole document.
    public static func decode(_ payload: [String: Any]) -> WatchCompanionSnapshot? {
        guard let type = payload[typeKey] as? String, type == messageType else {
            return nil
        }
        let version: Int
        if let intVersion = payload[schemaVersionKey] as? Int {
            version = intVersion
        } else if let number = payload[schemaVersionKey] as? NSNumber {
            version = number.intValue
        } else {
            return nil
        }
        guard version >= 1 else { return nil }

        let publishedAt = payload[publishedAtKey] as? Date ?? Date()
        return WatchCompanionSnapshot(
            schemaVersion: version,
            selectedLocation: decodeJSON(payload[selectedLocationKey]),
            locations: decodeJSON(payload[locationsKey]),
            conditions: decodeJSON(payload[conditionsKey]),
            observingQuality: decodeJSON(payload[observingQualityKey]),
            unitSystem: decodeUnitSystem(payload[unitSystemKey]),
            modeledBrightnessSamples: WatchLocationsBrightnessPriming.decodeSamples(from: payload),
            publishedAt: publishedAt
        )
    }

    /// Interprets a pre-snapshot type-specific dictionary as a **partial** snapshot.
    /// Missing keys stay nil so apply policy cannot treat them as a conditions wipe.
    public static func decodeLegacy(_ payload: [String: Any]) -> WatchCompanionSnapshot? {
        guard let type = payload[typeKey] as? String, type != messageType else {
            return nil
        }
        var snapshot = WatchCompanionSnapshot(publishedAt: Date())
        switch type {
        case "savedLocations", "locationSync", "selectedLocation":
            snapshot.locations = decodeJSON(payload[locationsKey])
            snapshot.selectedLocation = decodeJSON(payload[selectedLocationKey])
            snapshot.modeledBrightnessSamples = WatchLocationsBrightnessPriming.decodeSamples(
                from: payload
            )
        case "conditions":
            snapshot.conditions = decodeJSON(payload[conditionsKey])
            snapshot.observingQuality = decodeJSON(payload[observingQualityKey])
            snapshot.selectedLocation = decodeJSON(payload[selectedLocationKey])
        case "unitSystem":
            snapshot.unitSystem = decodeUnitSystem(payload[unitSystemKey])
        default:
            return nil
        }
        return snapshot.hasAnyField ? snapshot : nil
    }

    public static func decodeAny(_ payload: [String: Any]) -> WatchCompanionSnapshot? {
        decode(payload) ?? decodeLegacy(payload)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decodeJSON<T: Decodable>(_ value: Any?) -> T? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeUnitSystem(_ value: Any?) -> UnitSystem? {
        if let data = value as? Data,
           let raw = try? JSONDecoder().decode(String.self, from: data) {
            return UnitSystem(rawValue: raw)
        }
        if let raw = value as? String {
            return UnitSystem(rawValue: raw)
        }
        return nil
    }
}

/// Fields a receiver may apply from a snapshot without touching omitted companion files.
public struct WatchCompanionSnapshotApplyPlan: Sendable {
    public var selectedLocation: SelectedLocation?
    public var locations: [CachedLocation]?
    public var unitSystem: UnitSystem?
    public var modeledBrightnessSamples: [ModeledZenithBrightnessSample]
    public var conditions: ViewingConditions?
    public var observingQuality: WatchObservingQualityPayload?

    public init(
        selectedLocation: SelectedLocation? = nil,
        locations: [CachedLocation]? = nil,
        unitSystem: UnitSystem? = nil,
        modeledBrightnessSamples: [ModeledZenithBrightnessSample] = [],
        conditions: ViewingConditions? = nil,
        observingQuality: WatchObservingQualityPayload? = nil
    ) {
        self.selectedLocation = selectedLocation
        self.locations = locations
        self.unitSystem = unitSystem
        self.modeledBrightnessSamples = modeledBrightnessSamples
        self.conditions = conditions
        self.observingQuality = observingQuality
    }

    public var replacesConditions: Bool { conditions != nil }
}

/// Independent field application: omitted or rejected conditions never clear last-known-good.
public enum WatchCompanionSnapshotApplyPolicy: Sendable {
    public static func plan(
        snapshot: WatchCompanionSnapshot,
        selectedLocation: SelectedLocation?,
        now: Date = Date()
    ) -> WatchCompanionSnapshotApplyPlan {
        var plan = WatchCompanionSnapshotApplyPlan(
            selectedLocation: snapshot.selectedLocation,
            locations: snapshot.locations,
            unitSystem: snapshot.unitSystem,
            modeledBrightnessSamples: snapshot.modeledBrightnessSamples
        )

        guard let conditions = snapshot.conditions else {
            return plan
        }
        let acceptanceSelection = snapshot.selectedLocation ?? selectedLocation
        guard WatchConditionsPushAcceptance.shouldAccept(
            conditions: conditions,
            selectedLocation: acceptanceSelection,
            now: now
        ) else {
            return plan
        }
        plan.conditions = conditions
        plan.observingQuality = snapshot.observingQuality
        return plan
    }
}

// MARK: - Pending consumption ordering

/// Sequential boundary for pending companion-state consumption.
///
/// `apply` runs to completion before the bound refresh location is returned.
/// Weather acquisition must not start until after this returns.
public enum WatchCompanionPendingContext: Sendable {
    /// Apply the pending snapshot, then return the selection a later refresh must bind.
    ///
    /// Snapshot selection wins. The pre-apply current selection is used only when the
    /// snapshot has no selection. This is not a second apply mechanism — `apply` is the
    /// existing delegate/transition path.
    @discardableResult
    public static func consumeThenBind(
        snapshot: WatchCompanionSnapshot,
        currentSelectedLocation: SelectedLocation?,
        apply: (WatchCompanionSnapshotApplyPlan) -> Void
    ) -> SelectedLocation? {
        let plan = WatchCompanionSnapshotApplyPolicy.plan(
            snapshot: snapshot,
            selectedLocation: snapshot.selectedLocation ?? currentSelectedLocation
        )
        apply(plan)
        return plan.selectedLocation ?? currentSelectedLocation
    }
}

// MARK: - Process-reseed

/// Restores last-known conditions/OQ when reconstructing a snapshot accumulator.
///
/// Prefer the last published `WCSession.applicationContext` snapshot, then persisted
/// repository conditions. Both must still match the current selected location.
public enum WatchCompanionSnapshotReseed: Sendable {
    public struct RestoredConditions: Sendable {
        public let conditions: ViewingConditions
        public let observingQuality: WatchObservingQualityPayload?

        public init(
            conditions: ViewingConditions,
            observingQuality: WatchObservingQualityPayload?
        ) {
            self.conditions = conditions
            self.observingQuality = observingQuality
        }
    }

    public static func restoredConditions(
        selectedLocation: SelectedLocation?,
        sessionSnapshot: WatchCompanionSnapshot?,
        repositoryConditions: ViewingConditions?,
        rebuildObservingQuality: (ViewingConditions, SelectedLocation) -> WatchObservingQualityPayload?
    ) -> RestoredConditions? {
        guard let selectedLocation else { return nil }

        if let sessionConditions = sessionSnapshot?.conditions,
           WatchConditionsPushAcceptance.conditionsMatch(
            sessionConditions,
            selected: selectedLocation
           ) {
            let sessionOQ = sessionSnapshot?.observingQuality
            let oq: WatchObservingQualityPayload?
            if let sessionOQ, observingQualityMatches(
                sessionOQ,
                selected: selectedLocation
            ) {
                oq = sessionOQ
            } else {
                oq = rebuildObservingQuality(sessionConditions, selectedLocation)
            }
            return RestoredConditions(conditions: sessionConditions, observingQuality: oq)
        }

        if let repositoryConditions,
           WatchConditionsPushAcceptance.conditionsMatch(
            repositoryConditions,
            selected: selectedLocation
           ) {
            return RestoredConditions(
                conditions: repositoryConditions,
                observingQuality: rebuildObservingQuality(repositoryConditions, selectedLocation)
            )
        }

        return nil
    }

    private static func observingQualityMatches(
        _ payload: WatchObservingQualityPayload,
        selected: SelectedLocation
    ) -> Bool {
        switch selected.source {
        case .saved:
            return WatchObservingQualitySavedLocationAssociation.matches(
                selected: selected,
                context: payload.location
            )
        case .currentGPS:
            guard payload.location.source == .currentGPS else { return false }
            if selected.latitude == 0, selected.longitude == 0 {
                return true
            }
            return abs(payload.location.latitude - selected.latitude)
                <= WatchConditionsPushAcceptance.locationMatchTolerance
                && abs(payload.location.longitude - selected.longitude)
                <= WatchConditionsPushAcceptance.locationMatchTolerance
        }
    }
}
