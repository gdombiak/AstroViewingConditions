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

| Surface | Now | Public score |
|---------|-----|--------------|
| Main iOS dashboard | LPATLAS1 bundled; process composition root bootstraps provider | **Observing quality** (or pending until ready; then OQ or exact night fallback) |
| Best Targets (in-app) | Unchanged | Still driven by **night-conditions** context |
| Best Nearby | Unchanged | Night-conditions based ranking |
| iOS widgets | Unchanged | Night-conditions / existing snapshot scores |
| Watch / complications | Unchanged | Night-conditions based |

**Same-input/same-score across all public surfaces is the final goal, not the current shipping state for non-dashboard surfaces.**

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

**Cross-surface OQ on iOS widgets (Phase 4A — implemented on feature branch):** Shared `CrossSurfaceLocationContext`, versioned `CrossSurfaceObservingQualitySnapshot`, pure `CrossSurfaceObservingQualityResolver`, and `WidgetNightSummaryPublisher.makeEnriched(from:location:brightness:)` for both phone and widget `widgetConditions.json` writers. Night Conditions + Three-Night Outlook headlines use observing quality when Phase 2/3 companions are valid; otherwise exact night score. **Watch transport / UI is Phase 4B–4C.**

**Pending UI (Phase 5):** full-card placeholder remains until score-slot-only refinement; not Phase 1.

---

## Explicitly not in this phase

- Changing widget/watch/complication/Best Nearby/Best Targets **visible** scores  
- Bundling the artifact into widget/watch  
- App Group / WC brightness schema migration  

---

## Regeneration

See `BINARY_FORMAT.md` / README: replace app resource after `generate-global`, update size constants; production does **not** SHA-256 on every launch (integration tests do).
