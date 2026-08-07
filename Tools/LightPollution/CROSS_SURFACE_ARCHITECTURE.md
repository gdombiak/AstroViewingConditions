# Observing Quality — cross-surface architecture

**Status:** Implemented current architecture for consistent public scoring after LPATLAS1 packaging.

## Current scoring invariant

For the same location and observing night, surfaces with the same valid modeled-brightness input resolve to the same canonical Observing Quality result.

That means each surface must receive either:

1. **The same modeled zenith sky brightness** (from LPATLAS1 or a synchronized value derived from it) and compute:

   `ObservingQualityCalculator.assess(nightConditionsScore, brightness)` → `ObservingQualityAssessment`

   or

2. **A finalized `ObservingQualityAssessment` / public score** already produced from that brightness and the same Night Conditions score via the shared calculator.

Do **not** re-implement penalty anchors or interpolation in payload builders or target-specific code.

Single scoring implementation:

`ObservingQualityCalculator` ← `ObservingQualityService` / `ObservingQualityEnvironment`

### Exact fallback

Unadjusted **Night Conditions** (missing, stale, mismatched, incompatible, or failed brightness/assessment) is the safe degradation path:

- same semantics as app `lightPollutionReadiness == .unavailable`;
- `lightPollution == nil`; score equals `nightConditionsScore` exactly;
- companion surfaces use validated retained state when available, but never invent or endpoint-clamp brightness to avoid fallback.

---

## Current surface behavior

| Surface | Implementation | Public score |
|---------|----------------|--------------|
| Main iOS dashboard | LPATLAS1 bundled; process composition root bootstraps provider | **Observing Quality** (or pending until ready; then OQ or exact Night Conditions fallback) |
| Best Targets (in-app) | Target-score terminology clarified; scoring unchanged | **Target score**, separate from environmental OQ and equipment suitability |
| Best Nearby | One prepared OQ assessor; whole-search coherent mode | **Observing Quality** when every candidate has valid brightness; otherwise exact Night Conditions for all candidates |
| iOS conditions/outlook widgets | Validated saved-/Current Location companion state; no local atlas | **Observing Quality** when companion brightness is valid; else exact Night Conditions |
| Watch dashboard / complications | Phone transports optional OQ block; watch validates and **recomputes** canonically | **Observing Quality** when the association and brightness are valid; else exact Night Conditions |
| Watch Current Location | Correlated request/response using watch-supplied coordinates | **Observing Quality** when request context and brightness are valid; otherwise exact Night Conditions |

**For the same location/night and the same valid modeled-brightness input, environmental public-score surfaces resolve to the same canonical Observing Quality score.** A surface without valid brightness falls back exactly to Night Conditions, so temporary cross-surface differences caused by data availability are not automatically bugs. Best Targets is intentionally a different score domain.

---

## Process reality

| Process | Can share main-app singleton? |
|---------|--------------------------------|
| Main iOS app | Own process composition root |
| iOS widget extension | **No** — separate process |
| watchOS app / complications | **No** — separate process |

A `LightPollutionProviderBootstrap` instance in the phone app does **not** serve widgets or watch.

---

## Artifact packaging (size ~10 MiB)

**Do not** blindly embed the binary in every target.

| Target | Artifact membership | Invariant |
|--------|---------------------|-----------|
| Main iOS app | **Yes** (bundled) | Keep local lookup |
| SharedCode.framework | No | No |
| iOS widgets | No | Consume validated companion state |
| watchOS app / widget | No | Consume validated synchronized state |

---

## Selected distribution model: **Hybrid**

### Main iOS app (implemented)

- **Composition root:** `ContentView` owns `ObservingQualitySession` and calls `bootstrap(preferredBundles:)` once per process.
- **Not** owned by `DashboardView`.
- Default `DashboardViewModel` without injection uses `UnavailableObservingQualityEnvironment` (`.unavailable`, exact Night Conditions fallback)—**never** an unbootstrapped `.loading` session.
- Loads bundled `light_pollution_global_v1.bin` → `BinaryLightPollutionProvider` (eager validate, ~0.5s, async).
- Dashboard: readiness + `assess(night, lat, lon)`.
- **Pending (`.loading`):** `NightQualityCardHeadlinePending` — do not flash night-only score as final OQ.
- **Unavailable:** exact Night Conditions fallback, `lightPollution == nil`.

### iOS widgets (implemented)

Widgets already:

1. Read location from App Group
2. Optionally use cached `WidgetNightSummary` (finalized score snapshot)
3. Else fetch conditions via `SharedConditionsRepository` and rebuild summary

**Implemented path:**

- Phone and widget summary writers resolve validated saved-/Current Location companion brightness through the shared calculator.
- Widget displays that finalized score when the snapshot is fresh for the selected location/night.
- **Fallback path:** stale/missing snapshot or rebuild without valid brightness → exact Night Conditions. The widget never loads LPATLAS1.

### Watch app (implemented)

**Implemented path:**

- Phone includes modeled zenith brightness plus the completed assessment in existing WatchConnectivity payloads.
- Watch validates version, identity, coordinates, dataset, brightness, and transported-score agreement, then recomputes via `ObservingQualityCalculator`; the transported score is never display authority.

**Exceptional path:** disconnected or missing brightness → exact Night Conditions fallback with clear staleness semantics—not permanent dual scoring.

### Watch complications

- Timeline entries store the **final public Observing Quality score** from the shared path.
- Refresh must not re-derive with a different brightness epoch than the companion surface for that night.

### Best Nearby (implemented)

- Process-local provider (app), initialized once — never per candidate.
- Per candidate: brightness lookup + shared assessor → same public score definition as dashboard.
- The search uses OQ only when every scorable candidate has valid brightness; otherwise all
  ranking, display, category, and comparison values use Night Conditions.

---

## Extension seams

| Type | Role |
|------|------|
| `LightPollutionProviding` | Brightness lookup |
| `LightPollutionDatasetIdentity` | Logical cache identity (`datasetID`, `datasetRevision`, `formatVersion`) — **not** SHA-256 |
| `ModeledZenithBrightnessSample` | Portable versioned brightness + lookup coords + optional `savedLocationID` |
| `ModeledZenithBrightnessValidity` | **Shared** dataset / range / haversine (1000 m) validity — all surfaces must use this |
| `ModeledZenithBrightnessResolver` | Thin sample/resolve over a ready provider (no bundle I/O) |
| `SavedLocationModeledBrightnessCoordinator` | **Sole writer** actor for durable saved-location brightness companion metadata |
| `SavedLocationModeledBrightnessReading` | Public **read-only** facade (widgets/extensions; independent process load) |
| `ObservingQualityEnvironment` | assess + readiness (UI/composition) |
| `ObservingQualityService` / `ObservingQualityAssessing` | Thread-safe assess path |
| `ObservingQualityCalculator` | Pure score |
| `ObservingQualityAssessment` | Result DTO |
| `UnavailableObservingQualityEnvironment` | Safe default (no permanent pending) |
| Widget/watch payloads | Versioned brightness metadata plus Night Conditions and OQ scores |

### Dataset identity and validity

Application-facing dataset identity for invalidation:

- `datasetID` e.g. `lpatlas1`
- `datasetRevision` (bump on atlas/model content refresh)
- `formatVersion` (bump on binary layout break)

Byte count / SHA-256 remain packaging + integration-test diagnostics only.

**Watch Current Location:** brightness is sampled at **watch-supplied** coordinates; do not assume phone selection equals watch GPS. Validate returns with `ModeledZenithBrightnessValidity.coordinatesMatch`.

**Saved-location metadata:** Durable App Group companion file `savedLocationModeledBrightness.json` (`group.com.astroviewing.conditions`), schema v1, keyed by stable `SavedLocation.id`. Samples are `ModeledZenithBrightnessSample` values (not OQ scores and not `SavedLocation` fields).

- **Sole writer:** `SavedLocationModeledBrightnessCoordinator` actor (in-memory document after first load; sticky unsupported-schema write-disable).
- **Authoritative sync:** full snapshot from `LocationStorageService.publishLocationsToWatch` (enqueue) + composition-root backfill after bootstrap (`currentProvider()`, no second atlas load).
- **Lifecycle:** rename preserves (ID stable); coordinate change uses shared 1000 m validity; delete is pruned via snapshot; create is enriched when the provider is ready; dataset revision refreshes lazily via resolver; **not** mirrored via iCloud.
- **Readers:** `SavedLocationModeledBrightnessReading.loadValidSample` (widgets/extensions; no write).

**Current Location metadata:** Separate App Group file `currentLocationModeledBrightness.json` (schema v1, optional single sample with `savedLocationID == nil`).

- **Sole writer:** `CurrentLocationModeledBrightnessCoordinator` (own process-local revision stream).
- **Publication:** injected `CurrentLocationBrightnessPublishing` from `DashboardLocationLoader` after still-current GPS resolve; production `AppCurrentLocationBrightnessPublisher` stamps revision then `currentProvider()` + enqueue (no second atlas load). App boundary rejects invalid geo and unresolved placeholder `(0,0)`. The iOS app resolves GPS only while Current Location is selected.
- **Retain** sample when switching to a saved location; re-validate on return via shared 1000 m rules.
- **Readers:** `CurrentLocationModeledBrightnessReading` for widgets/extensions.

**Cross-surface OQ on iOS widgets:** Shared `CrossSurfaceLocationContext`, versioned `CrossSurfaceObservingQualitySnapshot`, pure `CrossSurfaceObservingQualityResolver`, and `WidgetNightSummaryPublisher.makeEnriched(from:location:brightness:)` for both phone and widget `widgetConditions.json` writers. Night Conditions and Three-Night Outlook headlines use Observing Quality when the appropriate saved-/Current Location companion is valid; otherwise they use the exact Night Conditions score.

**Watch saved-location OQ:** Optional versioned `WatchObservingQualityPayload` (payloadVersion 1) travels **beside** existing `ViewingConditions` over WatchConnectivity (`observingQuality` key) on phone push and `requestConditions` reply. Built only via `WatchObservingQualityPayloadBuilder.makeSavedLocationPayload` when authoritative `SelectedLocation.Source.saved`, matching conditions location, and a valid saved-location sample resolves to brightness **available**.

- **Watch never trusts transported OQ scores.** `WatchObservingQualityCanonicalizer` validates version/source/ID/coords/dataset/plausible brightness, reconstructs `ModeledZenithBrightnessSample`, recomputes with `CrossSurfaceObservingQualityResolver`, and requires recomputed vs transported agreement. Failures → exact Night Conditions.
- **Persistence files:** conditions in `watchNightConditions.json`; recomputed snapshot (+ association) in `watchObservingQuality.json`. Transported payload is not display authority.
- **Actor-serialized updates:** `WatchConditionsAcceptedUpdateCoordinator` owns:
  - **Live sequence:** lock-backed `WatchLiveIngressSequencer` claimed via **nonisolated** `claimLiveUpdate()` at **callback/refresh ingress** (before any unstructured `Task`). Task run order cannot reorder events. Persist + `appliedState` + fingerprint + reload run inside `withCurrentToken` (same lock as `claim`): a concurrent claim **waits** for the full commit boundary; a non-current token never writes.
  - **Deferred sequence:** `beginDeferredApplication()` bumps deferred under the same lock as live claims. `applyCached` resolves pure presentation outside the lock, then publishes fingerprint/`appliedState` inside `withAuthorizedCachePublication` (live + deferred re-check).
  - **Manager UI publication:** each applied state carries `WatchConditionsAppliedStateIdentity` (live sequence or cache live+deferred). `WatchConditionsObservablePublisher` (MainActor) applies observables only via `publishIfCurrent`, which re-validates identity under the ingress lock so a delayed `MainActor` hop cannot publish after a newer claim/commit.
- **Persistence:** **staged transactional pair** — encode → write `*.tmp` → backup prior conditions (hard-fail if prior exists but unreadable) → **promote staged temps** to finals → on OQ commit/clear failure **rollback conditions** (prior OQ untouched). Injectable `WatchConditionsPairFileSystem` for tests. Not a single multi-file FS atomic.
- **Persist failure:** coordinator returns `.persistFailed` without changing `appliedState`, fingerprint, or reloading; manager logs and keeps prior UI. A newer ingress claim still invalidates older pending UI publication even if the newer update fails to persist.
- **UI:** watch dashboard overall headline and all score-bearing complications use resolved OQ when associated; early/late half-night, weather, timing stay night-derived.
- **Reload coalescing:** `ObservingQualityDisplayFingerprint` (no timestamps) — one complication timeline reload when material display state changes after **successful** persist.
- **Compatibility:** old phone → new watch (no OQ block) and new phone → old watch (ignores additive key) keep exact Night Conditions; unknown version or malformed OQ never loses conditions.

**Watch Current Location OQ:**

- Watch refresh for `.currentGPS` claims live ingress, obtains watch GPS, builds `WatchCurrentLocationRequestContext` (request UUID + coords), and sends it with `requestConditions`.
- Phone uses **watch-supplied** coordinates (not phone-selected GPS) for conditions acquisition and brightness sampling via the process `LightPollutionProviderBootstrap.currentProvider()` — no second atlas load.
- Response may include optional OQ payload **v2** with echoed `requestContext`; v1 saved-location payloads remain supported.
- Unsolicited Current Location pushes are **not** OQ-enriched (correlation required).
- Watch canonicalizer requires request UUID match, nil saved IDs, strict coordinate identity (1e-5°), shared sample validity (1000 m lookup association via resolver), and recomputed-score agreement; failures → exact Night Conditions without losing conditions.
- Durable `watchObservingQuality.json` is restored only via `resolvePersisted`: schema, identity, shared sample validity, and **canonical recompute agreement** — raw persisted scores are never display authority. Request UUID is not required for restart restore. Night-only live outcomes **clear** the OQ file (no unavailable document).
- Local watch weather fallback remains night-only (no atlas on watch).
- Conditions request continuations use production `WatchRequestLifecycleController` (single-complete registry + injectable timeout scheduler).

**Current loading presentation:** the dashboard shows `NightQualityCardHeadlinePending` while the provider is loading rather than flashing an interim Night Conditions score as final OQ.

---

## Explicitly not in this feature

- Changing Best Targets recommendation scores based on light pollution or equipment
- Bundling the artifact into widget/watch
- Redesigning Best Nearby suitability or reverse geocoding

---

## Regeneration

Do not replace the production resource from an ad hoc generator run. Follow the canonical validation, adoption, identity/revision, XcodeGen, target-membership, archive-inspection, attribution, and release-evidence procedure in [VALIDATION_RESULTS.md — Updating to a new atlas release](VALIDATION_RESULTS.md#updating-to-a-new-atlas-release). Production does **not** SHA-256 on every launch; release validation and integration tests verify the checksum.
