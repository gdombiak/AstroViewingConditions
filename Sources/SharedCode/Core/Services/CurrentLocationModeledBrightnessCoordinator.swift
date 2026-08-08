import Foundation
import os

/// Sole production writer for Current Location modeled brightness metadata.
///
/// Consumes versioned `CurrentLocationBrightnessPublication` values. Revisions are
/// process-local and never persisted. Owns in-memory document state after first load.
public actor CurrentLocationModeledBrightnessCoordinator {
    public static let shared = CurrentLocationModeledBrightnessCoordinator()

    private enum MemoryState: Sendable, Equatable {
        case notLoaded
        case ready(CurrentLocationModeledBrightnessDocument)
        case unsupported(version: Int)
    }

    private struct PendingPublication: Sendable {
        var revision: UInt64
        var anchor: CurrentLocationBrightnessAnchor
        var provider: (any LightPollutionProviding)?
    }

    private var memory: MemoryState = .notLoaded
    private let store: CurrentLocationModeledBrightnessStore
    private var highestAcceptedRevision: UInt64 = 0
    private var pending: PendingPublication?
    private var isSynchronizing = false

    private let logger = Logger(
        subsystem: "com.astroviewing.conditions",
        category: "CurrentLocationModeledBrightness"
    )

    public init(storeBaseURL: URL? = AppGroupStorage.containerURL) {
        self.store = CurrentLocationModeledBrightnessStore(baseURL: storeBaseURL)
    }

    init(store: CurrentLocationModeledBrightnessStore) {
        self.store = store
    }

    // MARK: - Read

    /// Returns a sample only if Phase 1 coordinate validity passes with `maxAge: nil`
    /// and `savedLocationID == nil`.
    public func validSample(
        for anchor: CurrentLocationBrightnessAnchor
    ) -> ModeledZenithBrightnessSample? {
        ensureMemoryLoaded()
        switch memory {
        case .notLoaded, .unsupported:
            return nil
        case .ready(let document):
            guard let sample = document.sample else { return nil }
            guard sample.savedLocationID == nil else { return nil }
            guard ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: anchor.latitude,
                longitude: anchor.longitude,
                maxAge: nil
            ) else {
                return nil
            }
            return sample
        }
    }

    // MARK: - Synchronize

    public func synchronize(
        publication: CurrentLocationBrightnessPublication,
        provider: (any LightPollutionProviding)?
    ) async {
        guard publication.revision > highestAcceptedRevision else {
            return
        }

        ensureMemoryLoaded()

        defer {
            if publication.revision > highestAcceptedRevision {
                highestAcceptedRevision = publication.revision
            }
        }

        guard case .ready(let existing) = memory else {
            // Sticky unsupported: ordering advances via defer; no write.
            return
        }

        var document = existing
        let anchor = publication.anchor

        // Invalid anchor: no provider, clear sample, write cleared document.
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: anchor.latitude,
            longitude: anchor.longitude
        ) else {
            document.sample = nil
            document.schemaVersion = CurrentLocationModeledBrightnessDocument.currentSchemaVersion
            if store.write(document) {
                memory = .ready(document)
            }
            return
        }

        let cached = document.sample
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: anchor.latitude,
            requestLongitude: anchor.longitude,
            cached: cached,
            provider: provider,
            dataset: .current,
            savedLocationID: nil,
            maxAge: nil
        )
        document.sample = resolved
        document.schemaVersion = CurrentLocationModeledBrightnessDocument.currentSchemaVersion
        if store.write(document) {
            memory = .ready(document)
        }
    }

    public func enqueueSynchronize(
        publication: CurrentLocationBrightnessPublication,
        provider: (any LightPollutionProviding)?
    ) {
        guard publication.revision > highestAcceptedRevision else {
            return
        }

        if let pending {
            if publication.revision < pending.revision {
                return
            }
            if publication.revision == pending.revision {
                return
            }
        }

        pending = PendingPublication(
            revision: publication.revision,
            anchor: publication.anchor,
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
            await synchronize(
                publication: .makeForTesting(revision: next.revision, anchor: next.anchor),
                provider: next.provider
            )
        }
    }

    // MARK: - Test ergonomics

    func synchronizeForTesting(
        anchor: CurrentLocationBrightnessAnchor,
        provider: (any LightPollutionProviding)?
    ) async {
        let publication = CurrentLocationBrightnessPublication.makeAuthoritative(anchor: anchor)
        await synchronize(publication: publication, provider: provider)
    }

    // MARK: - Memory

    private func ensureMemoryLoaded() {
        guard case .notLoaded = memory else { return }

        switch store.load() {
        case .missing, .malformed:
            memory = .ready(.empty())
        case .ready(let document):
            memory = .ready(document)
        case .unsupportedSchema(let version):
            logger.error(
                "Unsupported CL companion schema version \(version); write-disabled"
            )
            memory = .unsupported(version: version)
        }
    }

    func resetForTesting(rewriteEmptyDocument: Bool = false) {
        pending = nil
        isSynchronizing = false
        highestAcceptedRevision = 0
        CurrentLocationBrightnessPublicationOrder.resetForTesting()
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

    func hasSampleForTesting() -> Bool {
        guard case .ready(let document) = memory else { return false }
        return document.sample != nil
    }

    func highestAcceptedRevisionForTesting() -> UInt64 {
        highestAcceptedRevision
    }
}
