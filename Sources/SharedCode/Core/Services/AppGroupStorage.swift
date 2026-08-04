import Foundation
import os

private let logger = Logger(subsystem: "com.astroviewing.conditions", category: "AppGroupStorage")

extension Notification.Name {
    public static let watchLocationSelected = Notification.Name("watchLocationSelected")
    public static let selectedLocationDidChange = Notification.Name("selectedLocationDidChange")
}

public struct AppGroupStorage: Sendable {
    public static let suiteName = "group.com.astroviewing.conditions"
    
    private static let fileLock = NSRecursiveLock()
    
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }
    
    private static func performFileAccess<T>(_ work: () -> T) -> T {
        fileLock.lock()
        defer { fileLock.unlock() }
        return work()
    }

    private static func performFileAccessAsync<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .utility) {
            performFileAccess(work)
        }.value
    }
    
    // MARK: - Selected Location (unified)
    
    public static func saveSelectedLocation(_ location: SelectedLocation) {
        performFileAccess {
            guard let baseURL = containerURL else { return }
            do {
                let data = try JSONEncoder().encode(location)
                let fileURL = baseURL.appendingPathComponent("selectedLocation.json")
                try data.write(to: fileURL, options: .atomic)
            } catch {
                logger.error("Failed to save selected location: \(error.localizedDescription)")
            }
        }
    }
    
    public static func loadSelectedLocation() -> SelectedLocation? {
        performFileAccess {
            guard let baseURL = containerURL else { return nil }
            let fileURL = baseURL.appendingPathComponent("selectedLocation.json")
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(SelectedLocation.self, from: data)
            } catch {
                logger.warning("Failed to load selected location: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    public static func loadSelectedLocationForWidget() -> SelectedLocation? {
        loadSelectedLocation()
    }
    
    private static func writeWidgetNightSummary(_ summary: WidgetNightSummary) -> Bool {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return false
        }

        do {
            let data = try JSONEncoder().encode(summary)
            let fileURL = baseURL.appendingPathComponent("widgetConditions.json")
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save widget conditions: \(error.localizedDescription)")
            return false
        }
    }

    private static func readWidgetNightSummary() -> WidgetNightSummary? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }

        let fileURL = baseURL.appendingPathComponent("widgetConditions.json")

        do {
            let data = try Data(contentsOf: fileURL)
            return WidgetNightSummary.decodeCachedPayload(data)
        } catch {
            logger.warning("Failed to load widget conditions: \(error.localizedDescription)")
            return nil
        }
    }

    public static func saveWidgetNightSummaryAsync(_ summary: WidgetNightSummary) async {
        await performFileAccessAsync {
            _ = writeWidgetNightSummary(summary)
        }
    }

    public static func loadWidgetNightSummaryAsync() async -> WidgetNightSummary? {
        await performFileAccessAsync {
            readWidgetNightSummary()
        }
    }

    // MARK: - Tonight's Targets Widget

    static func writeWidgetTonightTargetsSummary(
        _ summary: WidgetTonightTargetsSummary,
        baseURL: URL? = containerURL
    ) -> Bool {
        guard let baseURL else {
            logger.error("App Group container not available")
            return false
        }

        do {
            let data = try JSONEncoder().encode(summary)
            let fileURL = baseURL.appendingPathComponent("widgetTonightTargets.json")
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save widget targets: \(error.localizedDescription)")
            return false
        }
    }

    static func readWidgetTonightTargetsSummary(
        baseURL: URL? = containerURL
    ) -> WidgetTonightTargetsSummary? {
        guard let baseURL else {
            logger.error("App Group container not available")
            return nil
        }

        let fileURL = baseURL.appendingPathComponent("widgetTonightTargets.json")

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(WidgetTonightTargetsSummary.self, from: data)
        } catch {
            logger.warning("Failed to load widget targets: \(error.localizedDescription)")
            return nil
        }
    }

    public static func saveWidgetTonightTargetsSummaryAsync(
        _ summary: WidgetTonightTargetsSummary
    ) async {
        await performFileAccessAsync {
            _ = writeWidgetTonightTargetsSummary(summary)
        }
    }

    public static func loadWidgetTonightTargetsSummaryAsync() async -> WidgetTonightTargetsSummary? {
        await performFileAccessAsync {
            readWidgetTonightTargetsSummary()
        }
    }

    // MARK: - Three-Night Outlook Widget

    static func writeWidgetThreeNightOutlookSummary(
        _ summary: WidgetThreeNightOutlookSummary, baseURL: URL? = containerURL
    ) -> Bool {
        guard let baseURL else { return false }
        do {
            try JSONEncoder().encode(summary).write(
                to: baseURL.appendingPathComponent("widgetThreeNightOutlook.json"),
                options: .atomic
            )
            return true
        } catch {
            logger.error("Failed to save three-night outlook: \(error.localizedDescription)")
            return false
        }
    }

    static func readWidgetThreeNightOutlookSummary(
        baseURL: URL? = containerURL
    ) -> WidgetThreeNightOutlookSummary? {
        guard let baseURL else { return nil }
        do {
            let data = try Data(contentsOf: baseURL.appendingPathComponent("widgetThreeNightOutlook.json"))
            return try JSONDecoder().decode(WidgetThreeNightOutlookSummary.self, from: data)
        } catch {
            return nil
        }
    }

    public static func saveWidgetThreeNightOutlookSummaryAsync(
        _ summary: WidgetThreeNightOutlookSummary
    ) async {
        await performFileAccessAsync { _ = writeWidgetThreeNightOutlookSummary(summary) }
    }

    public static func loadWidgetThreeNightOutlookSummaryAsync() async -> WidgetThreeNightOutlookSummary? {
        await performFileAccessAsync { readWidgetThreeNightOutlookSummary() }
    }

    // MARK: - Watch Night Conditions

    public static let watchNightConditionsFileName = "watchNightConditions.json"

    /// Synchronous write (used by accepted-update coordinator pair persistence).
    static func writeWatchNightConditions(
        _ conditions: ViewingConditions,
        baseURL: URL? = containerURL
    ) -> Bool {
        guard let baseURL else {
            logger.error("App Group container not available")
            return false
        }

        do {
            let data = try JSONEncoder().encode(conditions)
            let fileURL = baseURL.appendingPathComponent(watchNightConditionsFileName)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save watch night conditions: \(error.localizedDescription)")
            return false
        }
    }

    static func readWatchNightConditions(baseURL: URL? = containerURL) -> ViewingConditions? {
        guard let baseURL else {
            logger.error("App Group container not available")
            return nil
        }

        let fileURL = baseURL.appendingPathComponent(watchNightConditionsFileName)

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ViewingConditions.self, from: data)
        } catch {
            logger.warning("Failed to load watch night conditions: \(error.localizedDescription)")
            return nil
        }
    }

    public static func saveWatchNightConditionsAsync(_ conditions: ViewingConditions) async {
        await performFileAccessAsync {
            _ = writeWatchNightConditions(conditions)
        }
    }

    public static func loadWatchNightConditionsAsync() async -> ViewingConditions? {
        await performFileAccessAsync {
            readWatchNightConditions()
        }
    }

    // MARK: - Watch Observing Quality (Phase 4B)

    public static let watchObservingQualityFileName = "watchObservingQuality.json"

    static func writeWatchObservingQuality(
        _ document: WatchObservingQualityDocument,
        baseURL: URL? = containerURL
    ) -> Bool {
        guard let baseURL else {
            logger.error("App Group container not available")
            return false
        }
        do {
            let data = try JSONEncoder().encode(document)
            try data.write(
                to: baseURL.appendingPathComponent(watchObservingQualityFileName),
                options: .atomic
            )
            return true
        } catch {
            logger.error("Failed to save watch OQ: \(error.localizedDescription)")
            return false
        }
    }

    static func readWatchObservingQuality(
        baseURL: URL? = containerURL
    ) -> WatchObservingQualityDocument? {
        guard let baseURL else { return nil }
        let fileURL = baseURL.appendingPathComponent(watchObservingQualityFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(WatchObservingQualityDocument.self, from: data)
            guard document.schemaVersion > 0,
                  document.schemaVersion <= WatchObservingQualityDocument.currentSchemaVersion else {
                return nil
            }
            return document
        } catch {
            logger.warning("Failed to load watch OQ: \(error.localizedDescription)")
            return nil
        }
    }

    /// Synchronous clear (best-effort). Prefer `persistWatchConditionsPair` for paired updates.
    static func clearWatchObservingQuality(baseURL: URL? = containerURL) {
        guard let baseURL else { return }
        let fileURL = baseURL.appendingPathComponent(watchObservingQualityFileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    public static func saveWatchObservingQualityAsync(_ document: WatchObservingQualityDocument) async {
        await performFileAccessAsync {
            _ = writeWatchObservingQuality(document)
        }
    }

    public static func loadWatchObservingQualityAsync() async -> WatchObservingQualityDocument? {
        await performFileAccessAsync {
            readWatchObservingQuality()
        }
    }

    public static func clearWatchObservingQualityAsync() async {
        await performFileAccessAsync {
            clearWatchObservingQuality()
        }
    }

    // MARK: - Staged transactional pair (Phase 4B)

    /// Persist conditions + OQ as a **staged transactional pair** with rollback.
    ///
    /// Algorithm:
    /// 1. Encode both payloads (fail → no disk mutation).
    /// 2. Stage to `*.tmp` (individually atomic writes of temps).
    /// 3. If final conditions exist: **must** read and stage backup; failure aborts
    ///    before either final is changed (temps cleaned). “Missing prior” ≠ “read failed.”
    /// 4. Promote staged conditions temp → final (individually atomic write of staged bytes).
    /// 5. Promote staged OQ temp → final, or clear final OQ for night-only.
    /// 6. If step 5 fails: roll back conditions from backup (or remove if no prior);
    ///    prior OQ is untouched so the complete prior pair remains.
    ///
    /// Staged files **are** the commit source (promoted), not decorative.
    static func persistWatchConditionsPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?,
        baseURL: URL? = containerURL,
        fileSystem: any WatchConditionsPairFileSystem = FoundationWatchConditionsPairFileSystem()
    ) throws {
        guard let baseURL else {
            throw WatchConditionsPersistError.containerUnavailable
        }

        let conditionsPath = baseURL.appendingPathComponent(watchNightConditionsFileName).path
        let oqPath = baseURL.appendingPathComponent(watchObservingQualityFileName).path
        let conditionsTmpPath = baseURL.appendingPathComponent(watchNightConditionsFileName + ".tmp").path
        let oqTmpPath = baseURL.appendingPathComponent(watchObservingQualityFileName + ".tmp").path
        let conditionsBakPath = baseURL.appendingPathComponent(watchNightConditionsFileName + ".bak").path

        func cleanupArtifacts() {
            try? fileSystem.removeItem(atPath: conditionsTmpPath)
            try? fileSystem.removeItem(atPath: oqTmpPath)
            try? fileSystem.removeItem(atPath: conditionsBakPath)
        }

        let conditionsData: Data
        let oqData: Data?
        do {
            conditionsData = try JSONEncoder().encode(conditions)
            if let observingQuality {
                oqData = try JSONEncoder().encode(observingQuality)
            } else {
                oqData = nil
            }
        } catch {
            throw WatchConditionsPersistError.encodingFailed(error.localizedDescription)
        }

        // Stage temps — these bytes will be promoted to finals.
        do {
            try fileSystem.writeData(conditionsData, toPath: conditionsTmpPath, options: .atomic)
            if let oqData {
                try fileSystem.writeData(oqData, toPath: oqTmpPath, options: .atomic)
            }
        } catch {
            cleanupArtifacts()
            throw WatchConditionsPersistError.stagingFailed(error.localizedDescription)
        }

        // Prior conditions: distinguish missing vs unreadable.
        let priorConditionsData: Data?
        if fileSystem.fileExists(atPath: conditionsPath) {
            let prior: Data
            do {
                prior = try fileSystem.readData(atPath: conditionsPath)
            } catch {
                cleanupArtifacts()
                throw WatchConditionsPersistError.priorBackupFailed(
                    "Prior conditions exist but cannot be read: \(error.localizedDescription)"
                )
            }
            do {
                try fileSystem.writeData(prior, toPath: conditionsBakPath, options: .atomic)
            } catch {
                cleanupArtifacts()
                throw WatchConditionsPersistError.priorBackupFailed(
                    "Failed to stage prior conditions backup: \(error.localizedDescription)"
                )
            }
            priorConditionsData = prior
        } else {
            priorConditionsData = nil
        }

        // Promote staged conditions → final (read from staged file to prove staging participates).
        do {
            let stagedConditions = try fileSystem.readData(atPath: conditionsTmpPath)
            try fileSystem.writeData(stagedConditions, toPath: conditionsPath, options: .atomic)
        } catch {
            cleanupArtifacts()
            throw WatchConditionsPersistError.commitConditionsFailed(error.localizedDescription)
        }

        // Promote OQ or clear.
        do {
            if oqData != nil {
                let stagedOQ = try fileSystem.readData(atPath: oqTmpPath)
                try fileSystem.writeData(stagedOQ, toPath: oqPath, options: .atomic)
            } else if fileSystem.fileExists(atPath: oqPath) {
                try fileSystem.removeItem(atPath: oqPath)
            }
        } catch {
            // Roll back conditions; leave prior OQ as-is.
            do {
                if let priorConditionsData {
                    try fileSystem.writeData(priorConditionsData, toPath: conditionsPath, options: .atomic)
                } else if fileSystem.fileExists(atPath: conditionsPath) {
                    try fileSystem.removeItem(atPath: conditionsPath)
                }
            } catch {
                cleanupArtifacts()
                throw WatchConditionsPersistError.rollbackFailed(error.localizedDescription)
            }
            cleanupArtifacts()
            if oqData != nil {
                throw WatchConditionsPersistError.commitObservingQualityFailed(error.localizedDescription)
            } else {
                throw WatchConditionsPersistError.clearObservingQualityFailed(error.localizedDescription)
            }
        }

        cleanupArtifacts()
    }
    
    // MARK: - Saved Locations
    
    public static func saveSavedLocations(_ locations: [CachedLocation]) {
        performFileAccess {
            guard let baseURL = containerURL else {
                logger.error("App Group container not available")
                return
            }
            
            do {
                let data = try JSONEncoder().encode(locations)
                let fileURL = baseURL.appendingPathComponent("savedLocations.json")
                try data.write(to: fileURL, options: .atomic)
            } catch {
                logger.error("Failed to save locations: \(error.localizedDescription)")
            }
        }
    }
    
    public static func loadSavedLocations() -> [CachedLocation] {
        performFileAccess {
            guard let baseURL = containerURL else {
                logger.error("App Group container not available")
                return []
            }
            
            let fileURL = baseURL.appendingPathComponent("savedLocations.json")
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode([CachedLocation].self, from: data)
            } catch {
                logger.warning("Failed to load locations: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    // MARK: - Conditions

    private static func writeConditions(_ conditions: ViewingConditions) -> Bool {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return false
        }

        do {
            let data = try JSONEncoder().encode(conditions)
            let fileURL = baseURL.appendingPathComponent("conditions.json")
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save conditions: \(error.localizedDescription)")
            return false
        }
    }

    private static func writeConditionsMetadata(_ metadata: SharedConditionsMetadata) -> Bool {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return false
        }

        do {
            let data = try JSONEncoder().encode(metadata)
            let fileURL = baseURL.appendingPathComponent("conditions-metadata.json")
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save conditions metadata: \(error.localizedDescription)")
            return false
        }
    }

    private static func readConditions() -> ViewingConditions? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }

        let fileURL = baseURL.appendingPathComponent("conditions.json")

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ViewingConditions.self, from: data)
        } catch {
            logger.warning("Failed to load conditions: \(error.localizedDescription)")
            return nil
        }
    }

    private static func readConditionsMetadata() -> SharedConditionsMetadata? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }

        do {
            let data = try Data(contentsOf: baseURL.appendingPathComponent("conditions-metadata.json"))
            return try JSONDecoder().decode(SharedConditionsMetadata.self, from: data)
        } catch {
            logger.warning("Failed to load conditions metadata: \(error.localizedDescription)")
            return nil
        }
    }

    public static func saveConditions(_ conditions: ViewingConditions) {
        performFileAccess {
            _ = writeConditions(conditions)
        }
    }

    public static func loadConditionsMetadataAsync() async -> SharedConditionsMetadata? {
        await performFileAccessAsync {
            readConditionsMetadata()
        }
    }

    /// Keeps the weather payload and its provenance under one file-access lock.
    /// Metadata is written only after `conditions.json` succeeds, so it cannot
    /// describe ISS freshness for weather data that was not persisted.
    public static func saveConditionsAndMetadataAsync(
        _ conditions: ViewingConditions,
        metadata: SharedConditionsMetadata
    ) async -> Bool {
        await performFileAccessAsync {
            guard writeConditions(conditions) else { return false }
            return writeConditionsMetadata(metadata)
        }
    }
    
    public static func loadConditions() -> ViewingConditions? {
        performFileAccess {
            readConditions()
        }
    }

    public static func loadConditionsAsync() async -> ViewingConditions? {
        await performFileAccessAsync {
            readConditions()
        }
    }
    
    public static func clearConditions() {
        performFileAccess {
            guard let baseURL = containerURL else { return }
            
            let conditionsFile = baseURL.appendingPathComponent("conditions.json")
            let conditionsMetadataFile = baseURL.appendingPathComponent("conditions-metadata.json")
            let timestampFile = baseURL.appendingPathComponent("conditionsTimestamp.json")
            
            try? FileManager.default.removeItem(at: conditionsFile)
            try? FileManager.default.removeItem(at: conditionsMetadataFile)
            try? FileManager.default.removeItem(at: timestampFile)
            logger.info("Cleared conditions cache")
        }
    }
    
    // MARK: - Best Spot Settings
    
    public static func saveBestSpotSettings(searchRadius: Double, gridSpacing: Double) {
        performFileAccess {
            guard let baseURL = containerURL else {
                logger.error("App Group container not available")
                return
            }
            
            let data: [String: Any] = [
                "searchRadius": searchRadius,
                "gridSpacing": gridSpacing
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let fileURL = baseURL.appendingPathComponent("bestSpotSettings.json")
                try jsonData.write(to: fileURL, options: .atomic)
            } catch {
                logger.error("Failed to save best spot settings: \(error.localizedDescription)")
            }
        }
    }
    
    public static func loadBestSpotSettings() -> (searchRadius: Double, gridSpacing: Double)? {
        performFileAccess {
            guard let baseURL = containerURL else {
                logger.error("App Group container not available")
                return nil
            }
            
            let fileURL = baseURL.appendingPathComponent("bestSpotSettings.json")
            
            do {
                let data = try Data(contentsOf: fileURL)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let searchRadius = json["searchRadius"] as? Double,
                      let gridSpacing = json["gridSpacing"] as? Double else {
                    return nil
                }
                
                let validatedRadius = BestSpotSettings.validateSearchRadius(searchRadius)
                let validatedSpacing = BestSpotSettings.validateGridSpacing(gridSpacing)
                
                return (validatedRadius, validatedSpacing)
            } catch {
                return nil
            }
        }
    }
    
    // MARK: - Unit System
    
    public static func saveUnitSystem(_ unitSystem: String) {
        performFileAccess {
            guard let baseURL = containerURL else {
                logger.error("App Group container not available")
                return
            }
            
            do {
                let data = try JSONEncoder().encode(unitSystem)
                let fileURL = baseURL.appendingPathComponent("unitSystem.json")
                try data.write(to: fileURL, options: .atomic)
            } catch {
                logger.error("Failed to save unit system: \(error.localizedDescription)")
            }
        }
    }
    
    public static func loadUnitSystem() -> String? {
        performFileAccess {
            guard let baseURL = containerURL else {
                logger.error("App Group container not available")
                return nil
            }
            
            let fileURL = baseURL.appendingPathComponent("unitSystem.json")
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(String.self, from: data)
            } catch {
                return nil
            }
        }
    }
    
}
