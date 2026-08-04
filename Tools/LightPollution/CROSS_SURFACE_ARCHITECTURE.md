# Observing quality — cross-surface architecture

**Status:** Design for consistent public scoring after LPATLAS1 packaging.  
**Dashboard is the only UI surface adjusted in the current phase.**

## Final intended steady-state invariant

For the same location and observing night, **every supported public score surface** must normally present the same public observing-quality result.

That means each surface must receive either:

1. **The same modeled zenith sky brightness** (from LPATLAS1 or a synchronized value derived from it) and compute:

   `ObservingQualityCalculator.assess(nightConditionsScore, brightness)` → `ObservingQualityAssessment`

   or

2. **A finalized `ObservingQualityAssessment` / public score** already produced from that brightness and the same night-conditions score via the shared calculator.

Do **not** re-implement penalty anchors or interpolation in payload builders or target-specific code.

Single scoring implementation:

`ObservingQualityCalculator` ← `ObservingQualityService` / `ObservingQualityEnvironment`

### Exceptional degradation (not steady state)

Unadjusted **night-conditions score only** (missing brightness / missing assessment) is an **exceptional** missing-, stale-, or failed-data path:

- same semantics as app `lightPollutionReadiness == .unavailable`;
- `lightPollution == nil`; score equals `nightConditionsScore` exactly;
- **not** the desired permanent behavior for widgets, watch, or complications.

Later rollout **must** define freshness/staleness indicators or retention rules so secondary surfaces do not **routinely** disagree with the main app for the same location/night when the phone has already computed OQ.

---

## Current phased-rollout behavior

| Surface | Now (feature branch) | Public score |
|---------|----------------------|--------------|
| Main iOS dashboard | LPATLAS1 bundled; process composition root bootstraps provider | **Observing quality** (or pending until ready; then OQ or exact night fallback) |
| Best Targets (in-app) | Unchanged | Still driven by **night-conditions** context |
| Best Nearby | Unchanged | Night-conditions based ranking |
| iOS widgets | Phase 4A on feature branch | **Observing quality** when Phase 2/3 companions valid; else exact night |
| Watch dashboard / complications | Phase 4B on feature branch (**saved locations only**) | Phone transports optional OQ block; watch **recomputes** via `CrossSurfaceObservingQualityResolver`; else exact night |
| Watch Current Location | Night-only until Phase 4C | Exact night (no Phase 3 brightness transport in 4B) |

**Same-input/same-score across all public surfaces is the final goal.** Phase 4B is implemented on the feature branch, not marked shipped/released.

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

| Target | Artifact now | Steady-state preference |
|--------|--------------|-------------------------|
| Main iOS app | **Yes** (bundled) | Keep local lookup |
| SharedCode.framework | No | No |
| iOS widgets | No | Prefer **no** full artifact if phone snapshots + brightness suffice |
| watchOS app / widget | No | Prefer **no** full artifact; sync brightness/assessment from phone |

---

## Selected distribution model: **Hybrid**

### Main iOS app (implemented)

- **Composition root:** `ContentView` owns `ObservingQualitySession` and calls `bootstrap(preferredBundles:)` once per process.
- **Not** owned by `DashboardView`.
- Default `DashboardViewModel` without injection uses `UnavailableObservingQualityEnvironment` (`.unavailable`, exact night fallback)—**never** an unbootstrapped `.loading` session.
- Loads bundled `light_pollution_global_v1.bin` → `BinaryLightPollutionProvider` (eager validate, ~0.5s, async).
- Dashboard: readiness + `assess(night, lat, lon)`.
- **Pending (`.loading`):** `NightQualityCardHeadlinePending` — do not flash night-only score as final OQ.
- **Unavailable:** exact night-score fallback, `lightPollution == nil`.

### iOS widgets (deferred activation)

Widgets already:

1. Read location from App Group  
2. Optionally use cached `WidgetNightSummary` (finalized score snapshot)  
3. Else fetch conditions via `SharedConditionsRepository` and rebuild summary  

**Steady-state path:**

- Phone produces widget snapshots with **observing-quality public score** (and ideally `modeledZenithSkyBrightness`) via the shared calculator.
- Widget displays that finalized score when the snapshot is fresh for the selected location/night.
- **Exceptional path:** stale/missing snapshot or rebuild without brightness → night-score-only **until** the phone refreshes; surface must treat this as degraded/stale, not as “equal to dashboard forever.”
- **Alternative** if snapshot freshness is inadequate: bundle LPATLAS1 in the widget and run local `ObservingQualityService` (~10 MiB).

### Watch app (deferred activation)

**Steady-state path:**

- Phone includes modeled zenith brightness or completed assessment in existing WC/App Group payloads.
- Watch applies `ObservingQualityCalculator` in SharedCode with its night score + synchronized brightness (or displays phone-finalized score).

**Exceptional path:** disconnected / missing brightness → night-score fallback with clear staleness semantics—not permanent dual scoring.

### Watch complications

- Timeline entries should store the **final public observing-quality score** from the shared path.
- Refresh must not re-derive with a different brightness epoch than the companion surface for that night.

### Best Nearby (deferred activation)

- Process-local provider (app), initialized once — never per candidate.
- Per candidate: brightness lookup + shared assessor → same public score definition as dashboard.

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
| Future payloads | `modeledZenithSkyBrightness` and/or finalized OQ score |

### Phase 1 foundation (shipped types only)

Application-facing dataset identity for invalidation:

- `datasetID` e.g. `lpatlas1`
- `datasetRevision` (bump on atlas/model content refresh)
- `formatVersion` (bump on binary layout break)

Byte count / SHA-256 remain packaging + integration-test diagnostics only.

**Watch (Phase 4 design):** Current Location brightness must be sampled at **watch-supplied** coordinates; do not assume phone selection equals watch GPS. Validate returns with `ModeledZenithBrightnessValidity.coordinatesMatch`.

**Saved-location metadata (Phase 2 — shipped):** Durable App Group companion file `savedLocationModeledBrightness.json` (`group.com.astroviewing.conditions`), schema v1, keyed by stable `SavedLocation.id`. Samples are Phase 1 `ModeledZenithBrightnessSample` values (not OQ scores).

- **Sole writer:** `SavedLocationModeledBrightnessCoordinator` actor (in-memory document after first load; sticky unsupported-schema write-disable).
- **Authoritative sync:** full snapshot from `LocationStorageService.publishLocationsToWatch` (enqueue) + composition-root backfill after bootstrap (`currentProvider()`, no second atlas load).
- **Lifecycle:** rename preserves (ID stable); coord change uses Phase 1 1000 m validity; delete pruned via snapshot; create enriched when provider ready; dataset revision refreshes lazily via resolver; **not** mirrored via iCloud.
- **Readers:** `SavedLocationModeledBrightnessReading.loadValidSample` (Phase 4 widget use; no write).

**Current Location metadata (Phase 3 — shipped):** Separate App Group file `currentLocationModeledBrightness.json` (schema v1, optional single sample with `savedLocationID == nil`).

- **Sole writer:** `CurrentLocationModeledBrightnessCoordinator` (own process-local revision stream).
- **Publication:** injected `CurrentLocationBrightnessPublishing` from `DashboardLocationLoader` after still-current GPS resolve; production `AppCurrentLocationBrightnessPublisher` stamps revision then `currentProvider()` + enqueue (no second atlas load). App boundary rejects invalid geo and unresolved placeholder `(0,0)` without changing Phase 1.
- **Retain** sample when switching to a saved location; re-validate on return via Phase 1 1000 m rules.
- **Readers:** `CurrentLocationModeledBrightnessReading` for later widgets.

**Cross-surface OQ on iOS widgets (Phase 4A — implemented on feature branch):** Shared `CrossSurfaceLocationContext`, versioned `CrossSurfaceObservingQualitySnapshot`, pure `CrossSurfaceObservingQualityResolver`, and `WidgetNightSummaryPublisher.makeEnriched(from:location:brightness:)` for both phone and widget `widgetConditions.json` writers. Night Conditions + Three-Night Outlook headlines use observing quality when Phase 2/3 companions are valid; otherwise exact night score.

**Watch saved-location OQ (Phase 4B — implemented on feature branch, not shipped):** Optional versioned `WatchObservingQualityPayload` (payloadVersion 1) travels **beside** existing `ViewingConditions` over WatchConnectivity (`observingQuality` key) on phone push and `requestConditions` reply. Built only via `WatchObservingQualityPayloadBuilder.makeSavedLocationPayload` when authoritative `SelectedLocation.Source.saved`, matching conditions location, and a valid Phase 2 sample resolves to brightness **available**.

- **Watch never trusts transported OQ scores.** `WatchObservingQualityCanonicalizer` validates version/source/ID/coords/dataset/plausible brightness, reconstructs `ModeledZenithBrightnessSample`, recomputes with `CrossSurfaceObservingQualityResolver`, and requires recomputed vs transported agreement. Failures → exact night score.
- **Persistence files:** conditions in `watchNightConditions.json`; recomputed snapshot (+ association) in `watchObservingQuality.json`. Transported payload is not display authority.
- **Actor-serialized updates:** `WatchConditionsAcceptedUpdateCoordinator` owns:
  - **Live sequence:** lock-backed `WatchLiveIngressSequencer` claimed via **nonisolated** `claimLiveUpdate()` at **callback/refresh ingress** (before any unstructured `Task`). Task run order cannot reorder events. Persist + `appliedState` + fingerprint + reload run inside `withCurrentToken` (same lock as `claim`): a concurrent claim **waits** for the full commit boundary; a non-current token never writes.
  - **Deferred sequence:** `beginDeferredApplication()` bumps deferred under the same lock as live claims. `applyCached` resolves pure presentation outside the lock, then publishes fingerprint/`appliedState` inside `withAuthorizedCachePublication` (live + deferred re-check).
  - **Manager UI publication:** each applied state carries `WatchConditionsAppliedStateIdentity` (live sequence or cache live+deferred). `WatchConditionsObservablePublisher` (MainActor) applies observables only via `publishIfCurrent`, which re-validates identity under the ingress lock so a delayed `MainActor` hop cannot publish after a newer claim/commit.
- **Persistence:** **staged transactional pair** — encode → write `*.tmp` → backup prior conditions (hard-fail if prior exists but unreadable) → **promote staged temps** to finals → on OQ commit/clear failure **rollback conditions** (prior OQ untouched). Injectable `WatchConditionsPairFileSystem` for tests. Not a single multi-file FS atomic.
- **Persist failure:** coordinator returns `.persistFailed` without changing `appliedState`, fingerprint, or reloading; manager logs and keeps prior UI. A newer ingress claim still invalidates older pending UI publication even if the newer update fails to persist.
- **UI:** watch dashboard overall headline and all score-bearing complications use resolved OQ when associated; early/late half-night, weather, timing stay night-derived.
- **Reload coalescing:** `ObservingQualityDisplayFingerprint` (no timestamps) — one complication timeline reload when material display state changes after **successful** persist.
- **Compatibility:** old phone → new watch (no OQ block) and new phone → old watch (ignores additive key) keep exact night; unknown version / malformed OQ never loses conditions.
- **Out of scope for 4B:** watch Current Location coordinate requests, watch GPS brightness lookup, atlas on watch, Phase 3 Current Location brightness transport, Best Nearby / Tonight’s Targets OQ.

**Watch Current Location OQ (Phase 4C — implemented on feature branch, not shipped):**

- Watch refresh for `.currentGPS` claims live ingress, obtains watch GPS, builds `WatchCurrentLocationRequestContext` (request UUID + coords), and sends it with `requestConditions`.
- Phone uses **watch-supplied** coordinates (not phone-selected GPS) for conditions acquisition and brightness sampling via the process `LightPollutionProviderBootstrap.currentProvider()` — no second atlas load.
- Response may include optional OQ payload **v2** with echoed `requestContext`; v1 saved-location payloads remain supported.
- Unsolicited Current Location pushes are **not** OQ-enriched (correlation required).
- Watch canonicalizer requires request UUID match, nil saved IDs, strict coordinate identity (1e-5°), Phase 1 sample validity (1000 m lookup association via resolver), and recomputed-score agreement; failures → exact night score without losing conditions.
- Durable `watchObservingQuality.json` is restored only via `resolvePersisted`: schema, identity, Phase 1 sample validity, and **canonical recompute agreement** — raw persisted scores are never display authority. Request UUID is not required for restart restore. Night-only live outcomes **clear** the OQ file (no unavailable document).
- Local watch weather fallback remains night-only (no atlas on watch).
- Conditions request continuations use production `WatchRequestLifecycleController` (single-complete registry + injectable timeout scheduler).

**Pending UI (Phase 5):** full-card placeholder remains until score-slot-only refinement; not Phase 1.

---

## Explicitly not in this phase

- Changing widget/watch/complication/Best Nearby/Best Targets **visible** scores  
- Bundling the artifact into widget/watch  
- App Group / WC brightness schema migration  

---

## Regeneration

See `BINARY_FORMAT.md` / README: replace app resource after `generate-global`, update size constants; production does **not** SHA-256 on every launch (integration tests do).
