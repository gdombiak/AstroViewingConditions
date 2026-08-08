import Foundation
import os

/// Sole production writer and lifecycle owner for saved-location modeled brightness metadata.
///
/// Authoritative synchronization consumes a versioned `SavedLocationBrightnessPublication`
/// (from `publishLocationsToWatch` / composition-root backfill). Views must not implement
/// enrich/prune rules themselves.
///
/// **Publication order:** each production snapshot carries a process-local monotonic
/// `revision` stamped synchronously when the snapshot is created. The coordinator tracks
/// `highestAcceptedRevision` and ignores any enqueue/synchronize with a lower revision so
/// delayed unstructured tasks cannot apply stale CRUD results.
///
/// Owns in-memory document state after first load; does not re-decode the file for every
/// `validSample` or mid-`synchronize` step. Revisions are never persisted to disk.
public actor SavedLocationModeledBrightnessCoordinator {
    public static let shared = SavedLocationModeledBrightnessCoordinator()

    private enum MemoryState: Sendable, Equatable {
        case notLoaded
        case ready(SavedLocationModeledBrightnessDocument)
        /// Sticky unsupported future schema — write-disabled for actor lifetime.
        case unsupported(version: Int)
    }

    private struct PendingPublication: Sendable {
        var revision: UInt64
        var locations: [SavedLocationBrightnessAnchor]
        var provider: (any LightPollutionProviding)?
    }

    private var memory: MemoryState = .notLoaded
    private let store: SavedLocationModeledBrightnessStore

    /// Highest publication revision that has been accepted for processing.
    private var highestAcceptedRevision: UInt64 = 0

    /// At most one pending publication — always the **highest-revision** seen while busy.
    private var pending: PendingPublication?
    private var isSynchronizing = false

    private let logger = Logger(
        subsystem: "com.astroviewing.conditions",
        category: "SavedLocationModeledBrightness"
    )

    public init(storeBaseURL: URL? = AppGroupStorage.containerURL) {
        self.store = SavedLocationModeledBrightnessStore(baseURL: storeBaseURL)
    }

    /// Package-internal / test injection of a custom store (e.g. temp directory).
    init(store: SavedLocationModeledBrightnessStore) {
        self.store = store
    }

    // MARK: - Read

    /// Returns a sample only if Phase 1
    /// `isValid(sample:forSavedLocationID:…)` passes with `maxAge: nil`.
    public func validSample(
        for anchor: SavedLocationBrightnessAnchor
    ) -> ModeledZenithBrightnessSample? {
        ensureMemoryLoaded()
        switch memory {
        case .notLoaded, .unsupported:
            return nil
        case .ready(let document):
            guard let sample = document.samplesBySavedLocationID[anchor.id.uuidString] else {
                return nil
            }
            guard ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forSavedLocationID: anchor.id,
                locationLatitude: anchor.latitude,
                locationLongitude: anchor.longitude,
                maxAge: nil
            ) else {
                return nil
            }
            return sample
        }
    }

    // MARK: - Synchronize (versioned production API)

    /// Authoritative sync from a versioned full-list publication.
    ///
    /// Ignores `publication.revision` if it is not strictly greater than
    /// `highestAcceptedRevision`.
    public func synchronize(
        publication: SavedLocationBrightnessPublication,
        provider: (any LightPollutionProviding)?
    ) async {
        guard publication.revision > highestAcceptedRevision else {
            return
        }

        ensureMemoryLoaded()

        // Accept this revision for ordering even when disk writes are disabled
        // (sticky unsupported) so stale lower revisions never apply later.
        defer {
            // Only advance if we still hold ordering rights (no higher revision
            // accepted concurrently — actor isolation makes this linear).
            if publication.revision > highestAcceptedRevision {
                highestAcceptedRevision = publication.revision
            }
        }

        guard case .ready(let existing) = memory else {
            return
        }

        var document = existing
        let locations = publication.locations
        let knownIDs = Set(locations.map(\.id.uuidString))

        document.samplesBySavedLocationID = document.samplesBySavedLocationID.filter {
            knownIDs.contains($0.key)
        }

        for anchor in locations {
            let key = anchor.id.uuidString
            let cached = document.samplesBySavedLocationID[key]
            let resolved = ModeledZenithBrightnessResolver.resolve(
                requestLatitude: anchor.latitude,
                requestLongitude: anchor.longitude,
                cached: cached,
                provider: provider,
                dataset: .current,
                savedLocationID: anchor.id,
                maxAge: nil
            )
            if let resolved {
                document.samplesBySavedLocationID[key] = resolved
            } else if cached != nil {
                document.samplesBySavedLocationID.removeValue(forKey: key)
            }
        }

        document.schemaVersion = SavedLocationModeledBrightnessDocument.currentSchemaVersion
        if store.write(document) {
            memory = .ready(document)
        }
    }

    /// Enqueue a versioned publication. Coalesces to the **highest-revision** pending
    /// snapshot (not merely last arrival). Stale lower revisions do not replace a newer
    /// pending publication's locations or provider.
    public func enqueueSynchronize(
        publication: SavedLocationBrightnessPublication,
        provider: (any LightPollutionProviding)?
    ) {
        guard publication.revision > highestAcceptedRevision else {
            return
        }

        if let pending {
            if publication.revision < pending.revision {
                // Stale: keep higher-revision pending (and its provider).
                return
            }
            if publication.revision == pending.revision {
                // Same revision: keep existing pending; do not thrash provider.
                return
            }
        }

        pending = PendingPublication(
            revision: publication.revision,
            locations: publication.locations,
            provider: provider
        )

        guard !isSynchronizing else { return }
        isSynchronizing = true
        Task {
            await self.drainPendingSynchronizations()
        }
    }

    private func drainPendingSynchronizations() async {
        while true {
            guard let next = pending else {
                isSynchronizing = false
                if pending != nil {
                    isSynchronizing = true
                    continue
                }
                return
            }
            pending = nil
            await synchronize(publication: SavedLocationBrightnessPublication.makeForTesting(
                revision: next.revision,
                locations: next.locations
            ), provider: next.provider)
        }
    }

    // MARK: - Test ergonomics

    /// Test-only: allocates the next process-local revision and synchronizes.
    /// Prefer explicit `makeForTesting(revision:)` for ordering tests.
    func synchronizeForTesting(
        locations: [SavedLocationBrightnessAnchor],
        provider: (any LightPollutionProviding)?
    ) async {
        let publication = SavedLocationBrightnessPublication.makeAuthoritative(locations: locations)
        await synchronize(publication: publication, provider: provider)
    }

    // MARK: - Memory load

    private func ensureMemoryLoaded() {
        guard case .notLoaded = memory else { return }

        switch store.load() {
        case .missing, .malformed:
            memory = .ready(.empty())
        case .ready(let document):
            memory = .ready(document)
        case .unsupportedSchema(let version):
            logger.error(
                "Unsupported companion schema version \(version); metadata write-disabled"
            )
            memory = .unsupported(version: version)
        }
    }

    // MARK: - Test support (internal)

    /// Test-only: reset actor memory, ordering, and optionally rebuild empty v1 on disk.
    func resetForTesting(rewriteEmptyDocument: Bool = false) {
        pending = nil
        isSynchronizing = false
        highestAcceptedRevision = 0
        SavedLocationBrightnessPublicationOrder.resetForTesting()
        if rewriteEmptyDocument {
            _ = store.write(.empty())
            memory = .ready(.empty())
        } else {
            memory = .notLoaded
        }
    }

    func memoryStateDescriptionForTesting() -> String {
        switch memory {
        case .notLoaded: return "notLoaded"
        case .ready: return "ready"
        case .unsupported(let v): return "unsupported(\(v))"
        }
    }

    func readySampleCountForTesting() -> Int? {
        guard case .ready(let document) = memory else { return nil }
        return document.samplesBySavedLocationID.count
    }

    func highestAcceptedRevisionForTesting() -> UInt64 {
        highestAcceptedRevision
    }

    /// Test-only: highest-revision pending, if any.
    func pendingRevisionForTesting() -> UInt64? {
        pending?.revision
    }
}
