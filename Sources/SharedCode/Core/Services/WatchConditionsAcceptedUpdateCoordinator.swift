import Foundation

// MARK: - Persistence / reload / gate abstractions

/// Failure of a staged conditions + OQ pair persistence transaction.
public enum WatchConditionsPersistError: Error, Sendable, Equatable {
    case containerUnavailable
    case encodingFailed(String)
    case stagingFailed(String)
    /// Prior conditions file exists but cannot be read or backed up — abort before final mutation.
    case priorBackupFailed(String)
    case commitConditionsFailed(String)
    case commitObservingQualityFailed(String)
    case clearObservingQualityFailed(String)
    case rollbackFailed(String)
    /// Injectable / test failures with a label.
    case injected(String)
}

/// Writable store for watch conditions + associated OQ document (Phase 4B).
public protocol WatchConditionsPersisting: Sendable {
    /// Persist conditions and associated OQ as a **staged transactional pair**.
    ///
    /// On success both files reflect the new pair (or OQ is absent for night-only).
    /// On failure the prior complete pair remains readable; no partial commit is left
    /// that associates new conditions with a stale OQ document.
    func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws
}

/// Complication timeline reload (injectable for tests).
public protocol WatchComplicationReloadReporting: Sendable {
    func reloadComplications()
}

/// Suspension points for tests (live prepare / persist / deferred cache apply).
public protocol WatchConditionsUpdateGate: Sendable {
    /// After live token is claimed and accept begins, before resolve/persist.
    func beforePersist() async
    /// On deferred cache apply, at entry (before pure resolution).
    func beforeApplyCached() async
    /// After pure cache resolution, immediately before the protected publication section.
    func beforeCachePublication() async
    /// Called **inside** the protected cache publication section (must not claim or await).
    func onCachePublicationEntered()
}

extension WatchConditionsUpdateGate {
    public func beforeCachePublication() async {}
    public func onCachePublicationEntered() {}
}

/// Production gate: no delay.
public struct ImmediateWatchConditionsUpdateGate: WatchConditionsUpdateGate {
    public init() {}
    public func beforePersist() async {}
    public func beforeApplyCached() async {}
    public func beforeCachePublication() async {}
    public func onCachePublicationEntered() {}
}

/// Default App Group-backed persistence for production watch manager.
public struct AppGroupWatchConditionsStore: WatchConditionsPersisting {
    public var baseURL: URL?
    public var fileSystem: any WatchConditionsPairFileSystem

    public init(
        baseURL: URL? = AppGroupStorage.containerURL,
        fileSystem: any WatchConditionsPairFileSystem = FoundationWatchConditionsPairFileSystem()
    ) {
        self.baseURL = baseURL
        self.fileSystem = fileSystem
    }

    public func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws {
        try AppGroupStorage.persistWatchConditionsPair(
            conditions: conditions,
            observingQuality: observingQuality,
            baseURL: baseURL,
            fileSystem: fileSystem
        )
    }
}

// MARK: - Applied state & results

/// Snapshot of dashboard-relevant state after a successful accepted update.
public struct WatchConditionsAppliedState: Sendable {
    public var conditions: ViewingConditions
    public var nightQuality: NightQualityAssessment?
    public var observingQualityHeadline: WatchObservingQualityHeadline?
    public var locationTimeZone: TimeZone?
    public var displayFingerprint: ObservingQualityDisplayFingerprint?
    public var didReloadComplications: Bool
    /// Ordering identity for generation-aware MainActor publication.
    public var identity: WatchConditionsAppliedStateIdentity

    public init(
        conditions: ViewingConditions,
        nightQuality: NightQualityAssessment?,
        observingQualityHeadline: WatchObservingQualityHeadline?,
        locationTimeZone: TimeZone?,
        displayFingerprint: ObservingQualityDisplayFingerprint?,
        didReloadComplications: Bool,
        identity: WatchConditionsAppliedStateIdentity
    ) {
        self.conditions = conditions
        self.nightQuality = nightQuality
        self.observingQualityHeadline = observingQualityHeadline
        self.locationTimeZone = locationTimeZone
        self.displayFingerprint = displayFingerprint
        self.didReloadComplications = didReloadComplications
        self.identity = identity
    }
}

public enum WatchConditionsAcceptResult: Sendable {
    /// Update was superseded; no files or UI changed for this operation.
    case discardedStale
    /// Staged pair persistence failed; prior applied state and files unchanged.
    case persistFailed(WatchConditionsPersistError)
    /// Persist succeeded and observable state applied (reload may or may not have fired).
    case applied(WatchConditionsAppliedState)
}

/// Token from synchronous live-ingress claim — order is claim order, not Task run order.
public struct WatchConditionsLiveUpdateToken: Sendable, Equatable {
    public let sequence: UInt64

    public init(sequence: UInt64) {
        self.sequence = sequence
    }
}

/// Token from `beginDeferredApplication()` for startup / shared-cache loads.
///
/// Succeeds only when **both**:
/// - `liveGeneration` still equals the current live ingress sequence (no live claim since start);
/// - `deferredSequence` is still the latest deferred start (newer cache starts invalidate older ones).
public struct WatchConditionsDeferredApplicationToken: Sendable, Equatable {
    public let liveGeneration: UInt64
    public let deferredSequence: UInt64

    public init(liveGeneration: UInt64, deferredSequence: UInt64) {
        self.liveGeneration = liveGeneration
        self.deferredSequence = deferredSequence
    }
}

public enum WatchConditionsCacheApplyResult: Sendable {
    /// Cache applied in-memory only (no persistence, no reload).
    case applied(WatchConditionsAppliedState)
    /// Invalidated by a live update and/or a newer deferred cache start.
    case discardedStale
}

// MARK: - Production live-ingress boundary

/// Production seam for claiming live order at **event receipt** (before any unstructured Task).
///
/// WatchConnectivity callbacks and refresh starts must call ``claimLiveUpdate()``
/// synchronously, then schedule async work that carries the token. Task scheduling may
/// reorder processing arbitrarily; sequence numbers already encode arrival order.
public protocol WatchLiveIngressClaiming: Sendable {
    /// Synchronous claim — must not require an actor hop that can reorder events.
    func claimLiveUpdate() -> WatchConditionsLiveUpdateToken
    var currentLiveSequence: UInt64 { get }
}

// MARK: - Coordinator

/// Actor-serialized accepted-update and deferred-cache application for watch conditions/OQ.
///
/// **Live updates:** ``claimLiveUpdate()`` is **nonisolated** and uses a lock-backed
/// ``WatchLiveIngressSequencer``. Call it at callback/refresh **ingress** before starting
/// any `Task`. Persist + apply + fingerprint + reload run inside
/// ``WatchLiveIngressSequencer/withCurrentToken`` so a concurrent claim cannot split
/// persistence from publication (and a discarded op never writes).
///
/// **Deferred cache:** `beginDeferredApplication()` increments `deferredSequence` and
/// captures current live sequence. `applyCached` requires both fields still current.
/// A live claim advances live sequence and invalidates outstanding cache tokens.
///
/// **Persistence:** staged transactional pair (encode → write `*.tmp` → promote temps to
/// finals → rollback conditions on OQ failure). See `AppGroupStorage.persistWatchConditionsPair`.
public actor WatchConditionsAcceptedUpdateCoordinator: WatchLiveIngressClaiming {
    private let store: any WatchConditionsPersisting
    private let reloader: any WatchComplicationReloadReporting
    private let gate: any WatchConditionsUpdateGate
    /// Lock-backed; claim order is independent of actor scheduling.
    private let liveIngress: WatchLiveIngressSequencer

    private var lastDisplayFingerprint: ObservingQualityDisplayFingerprint?

    /// Last successfully applied state (for tests / manager sync).
    private(set) public var appliedState: WatchConditionsAppliedState?

    public init(
        store: any WatchConditionsPersisting,
        reloader: any WatchComplicationReloadReporting,
        gate: any WatchConditionsUpdateGate = ImmediateWatchConditionsUpdateGate(),
        liveIngress: WatchLiveIngressSequencer = WatchLiveIngressSequencer()
    ) {
        self.store = store
        self.reloader = reloader
        self.gate = gate
        self.liveIngress = liveIngress
    }

    /// Synchronous live-ingress claim (preferred). Safe from WC callbacks before `Task { }`.
    /// Blocks while another update is inside the protected commit boundary.
    nonisolated public func claimLiveUpdate() -> WatchConditionsLiveUpdateToken {
        WatchConditionsLiveUpdateToken(sequence: liveIngress.claim())
    }

    /// Latest claimed live sequence (synchronous read).
    nonisolated public var currentLiveSequence: UInt64 {
        liveIngress.current
    }

    /// Latest deferred-cache start sequence (synchronous read).
    nonisolated public var currentDeferredSequence: UInt64 {
        liveIngress.currentDeferred
    }

    /// Publish manager-visible state only if `state.identity` is still current.
    ///
    /// Validation and `mutate` run under the ingress lock (no await). Call from MainActor
    /// so observable mutation is ordered with other MainActor publications.
    nonisolated public func publishIfCurrent(
        _ state: WatchConditionsAppliedState,
        mutate: () -> Void
    ) -> Bool {
        liveIngress.withPublishableIdentity(state.identity, perform: mutate)
    }

    /// Actor-hopping alias of ``claimLiveUpdate()``. Prefer the nonisolated claim at ingress;
    /// do not use this inside competing unstructured Tasks to establish order.
    public func beginLiveUpdate() -> WatchConditionsLiveUpdateToken {
        claimLiveUpdate()
    }

    /// Begin a deferred cache load: bumps deferred sequence and captures live generation.
    public func beginDeferredApplication() -> WatchConditionsDeferredApplicationToken {
        let pair = liveIngress.beginDeferred()
        return WatchConditionsDeferredApplicationToken(
            liveGeneration: pair.liveGeneration,
            deferredSequence: pair.deferredSequence
        )
    }

    /// Complete a previously claimed live update.
    ///
    /// Pure resolve work may run outside the ingress lock. The **commit boundary**
    /// (verify current → persist pair → appliedState → fingerprint → reload) is one
    /// `withCurrentToken` section: concurrent claims wait; a non-current token never writes.
    public func accept(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload?,
        selectedLocation: SelectedLocation?,
        locationTimeZone: TimeZone?,
        reloadComplications: Bool,
        token: WatchConditionsLiveUpdateToken,
        expectedCurrentLocationRequest: WatchCurrentLocationRequestContext? = nil
    ) async -> WatchConditionsAcceptResult {
        // Optional test suspension *before* the commit boundary (not holding the ingress lock).
        await gate.beforePersist()

        // Fast path: already superseded — no pure work required.
        if token.sequence != liveIngress.current {
            return .discardedStale
        }

        // Pure validation/recompute (no I/O, no mutation of applied state).
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: transported,
            selectedLocation: selectedLocation,
            expectedCurrentLocationRequest: expectedCurrentLocationRequest
        )
        let document = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        )
        let nightQuality = NightQualityAnalyzer.analyzeConditions(conditions)
        let headline = Self.makeHeadline(
            outcome: outcome,
            conditions: conditions,
            selectedLocation: selectedLocation,
            nightScore: nightQuality?.calculatedScore ?? 0
        )

        // Protected commit: verify current + persist + publish under one sequencer lock.
        // Concurrent claimLiveUpdate() waits until this returns.
        var applied: WatchConditionsAppliedState?
        do {
            let ran = try liveIngress.withCurrentToken(token.sequence) {
                try store.persistAcceptedPair(conditions: conditions, observingQuality: document)

                var didReload = false
                let newFingerprint = headline?.fingerprint
                if reloadComplications {
                    if newFingerprint != lastDisplayFingerprint {
                        lastDisplayFingerprint = newFingerprint
                        reloader.reloadComplications()
                        didReload = true
                    }
                } else if lastDisplayFingerprint == nil {
                    lastDisplayFingerprint = newFingerprint
                }

                let state = WatchConditionsAppliedState(
                    conditions: conditions,
                    nightQuality: nightQuality,
                    observingQualityHeadline: headline,
                    locationTimeZone: locationTimeZone,
                    displayFingerprint: newFingerprint,
                    didReloadComplications: didReload,
                    identity: .live(sequence: token.sequence)
                )
                appliedState = state
                applied = state
            }
            if !ran {
                // Token not current: withCurrentToken did not call perform — zero writes.
                return .discardedStale
            }
            // Successful write always pairs with .applied (perform completed without throw).
            guard let applied else {
                preconditionFailure("withCurrentToken ran but applied state missing")
            }
            return .applied(applied)
        } catch let error as WatchConditionsPersistError {
            return .persistFailed(error)
        } catch {
            return .persistFailed(.injected(error.localizedDescription))
        }
    }

    /// Apply previously loaded cache in-memory only, if still the latest deferred start
    /// and no live update has intervened.
    ///
    /// Pure resolution runs outside the sequencer lock. Fingerprint seeding and
    /// `appliedState` assignment run inside ``WatchLiveIngressSequencer/withAuthorizedCachePublication``
    /// so a concurrent live claim cannot publish after validation. Never writes disk or reloads.
    public func applyCached(
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?,
        persistedDocument: WatchObservingQualityDocument?,
        locationTimeZone: TimeZone?,
        token: WatchConditionsDeferredApplicationToken
    ) async -> WatchConditionsCacheApplyResult {
        await gate.beforeApplyCached()

        // Pure resolution (no mutation). May race with live claims; publication is re-validated.
        // Durable OQ: full canonical recompute — never trust raw persisted scores as display authority.
        let nightQuality = NightQualityAnalyzer.analyzeConditions(conditions)
        let nightScore = nightQuality?.calculatedScore ?? 0
        let outcome = WatchObservingQualityCanonicalizer.resolvePersisted(
            document: persistedDocument,
            conditions: conditions,
            selectedLocation: selectedLocation
        )
        let headline = Self.makeHeadline(
            outcome: outcome,
            conditions: conditions,
            selectedLocation: selectedLocation,
            nightScore: nightScore
        )
        let candidateState = WatchConditionsAppliedState(
            conditions: conditions,
            nightQuality: nightQuality,
            observingQualityHeadline: headline,
            locationTimeZone: locationTimeZone,
            displayFingerprint: headline?.fingerprint,
            didReloadComplications: false,
            identity: .cache(
                liveGeneration: token.liveGeneration,
                deferredSequence: token.deferredSequence
            )
        )

        // Suspend here in tests: after pure prep, before protected publication.
        await gate.beforeCachePublication()

        // Protected publication: live + deferred currency under the claim lock.
        var published: WatchConditionsAppliedState?
        let authorized = liveIngress.withAuthorizedCachePublication(
            liveGeneration: token.liveGeneration,
            deferredSequence: token.deferredSequence
        ) {
            // Sync test hook only — must not claim, await, or re-enter lock.
            gate.onCachePublicationEntered()

            if lastDisplayFingerprint == nil {
                lastDisplayFingerprint = candidateState.displayFingerprint
            }
            appliedState = candidateState
            published = candidateState
        }

        if !authorized {
            return .discardedStale
        }
        guard let published else {
            preconditionFailure("cache publication ran but applied state missing")
        }
        return .applied(published)
    }

    public var currentFingerprint: ObservingQualityDisplayFingerprint? {
        lastDisplayFingerprint
    }

    // MARK: - Headline mapping

    private static func makeHeadline(
        outcome: WatchObservingQualityCanonicalizer.Outcome,
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?,
        nightScore: Int
    ) -> WatchObservingQualityHeadline? {
        switch outcome {
        case let .enhanced(snapshot, location):
            return WatchObservingQualityHeadline(
                nightConditionsScore: snapshot.nightConditionsScore,
                observingQualityScore: snapshot.observingQualityScore,
                brightnessAvailability: snapshot.brightnessAvailability,
                location: location,
                dataset: snapshot.brightnessDataset
            )
        case let .nightOnly(score, location):
            if let location {
                return .nightOnly(nightScore: score, location: location)
            }
            if let selectedLocation,
               let ctx = CrossSurfaceLocationContext.make(from: selectedLocation) {
                return .nightOnly(nightScore: score, location: ctx)
            }
            let fallback = CrossSurfaceLocationContext(
                source: .saved,
                latitude: conditions.location.latitude,
                longitude: conditions.location.longitude,
                savedLocationID: conditions.location.id
            )
            if fallback.hasConsistentIdentity {
                return .nightOnly(nightScore: score, location: fallback)
            }
            return nil
        }
    }
}
