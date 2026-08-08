# Validation results (David Lorenz 2025 zenith brightness)

Concise committed record of the completed offline packaging experiment. Detailed generated tables, rasters, and JSON remain under ignored `output/` (e.g. `output/oregon/`, `output/world_*_census.json`).

This records the validation that selected the committed LPATLAS1 v1 in-app storage format.

## Source

Atlas by [David Lorenz](https://djlorenz.github.io/astronomy/lp/). He is the author of the Light Pollution Atlas products used in this experiment. Redistribution or bundling of each atlas release remains subject to the **applicable license or explicit permission for that release**; this validation harness does **not** grant redistribution rights.

| Property | Value |
|----------|--------|
| Product | David Lorenz 2025 global zenith-sky-brightness atlas |
| Official site | https://djlorenz.github.io/astronomy/lp/ |
| Typical local path | `~/Downloads/zenith_brightness_v22_2025.tiff` (~2.9 GB; **not** committed) |
| Dimensions | **43,200 × 16,801** |
| Type | Float32, one band |
| CRS | WGS 84 / **EPSG:4326** |
| Resolution | **1⁄120°** (30 arcseconds) |
| Units | mag/arcsec² (larger ⇒ darker); **not** Bortle classes |
| Lon / lat coverage | −180°…+180°; +75°…≈−65° |
| License / bundling | Per-release license or explicit permission; **not** conferred by this harness |

## Oregon fidelity extent

- Longitude **−125°…−116°**, latitude **42°…47°** (`config/regions/oregon.json`)
- Full-grid reconstruction metrics, named public points, top-error lists, and viewer compare this window
- Hierarchical Oregon metrics use **full global roots** intersecting this window, then crop

## Exact uniform UInt8 baselines (global size exact from source dims)

| Candidate | Global MiB | Oregon MAE (approx.) | Oregon max AE (approx.) |
|-----------|------------|----------------------|-------------------------|
| 0.025° linear_avg UInt8 | **76.91** | 0.018 | 0.54 |
| 0.05° linear_avg UInt8 | **19.23** | 0.029 | 1.10 |
| 0.1° linear_avg UInt8 | **4.81** | 0.049 | 1.40 |

Uniform global bytes use `uniform_global_size_exact` (source dimensions × reduction factor × bytes/cell + metadata), not Oregon area scaling.

## Hierarchical shortlist (UInt8, error-only; global MiB from worldwide hierarchical census)

| Budget / policy / finest cap | Global MiB | Oregon MAE | Oregon P95 | Oregon max AE |
|------------------------------|------------|------------|------------|---------------|
| 0.05 / error / cap **0.025°** | **15.51** | 0.0217 | 0.0662 | 0.5232 |
| 0.10 / error / cap **0.025°** | **9.61** | 0.0355 | 0.0847 | 0.5232 |
| 0.05 / error / cap **0.05°** | **5.76** | 0.0340 | 0.1380 | 0.8545 |

**Budget semantics:** the max-error budget drives subdivision; it is **not** a global guarantee at the finest cap. These hierarchical candidates retain unresolved finest-cap violations; do not describe them as fully meeting the configured budget. Report viol-leaf % and viol-valid-cell % in generated reports.

## Fixed-tile adaptive (size note)

Fixed-tile adaptive can satisfy a configured max-AE budget via **native** tile fallback. Worldwide packaging size must come from `world-adaptive-census` (order of magnitude **~87–138 MiB** in the exact worldwide census for UInt8 budgets of interest), **not** from Oregon-scaled preliminary MiB figures that can appear as hundreds of MiB in Oregon-only tables.

## Selected production configuration

**UInt8 · error-only policy · 0.10 mag subdivision budget · 0.025° finest cap**

Corresponding candidate id pattern:

`hierarchical_adaptive_uint8_budget0.1_error_cap0.025`

## Production binary (LPATLAS1 v1) — generated locally

Format: [BINARY_FORMAT.md](BINARY_FORMAT.md). Artifact name: `light_pollution_global_v1.bin` (gitignored under `output/artifacts/`).

| Metric | Value |
|--------|--------|
| Artifact size | **10,328,230 bytes ≈ 9.85 MiB** |
| Prior census estimate | **9.61 MiB** (≈ +0.24 MiB / +2.5% vs real DFS payload) |
| Generation (8 workers) | ≈ **247 s** |
| Algorithm | hierarchical_adaptive_uint8_budget0.1_error_cap0.025 |
| Quantization | UInt8 over **[13.01, 22.5]** mag/arcsec²; dequant step ≈ 0.0374 mag |
| Roots | 1254 (22 constant, 535 default_pristine, 697 children) |
| Finest-cap budget violations (roots) | 609 (expected; not a packaging blocker) |

### Global accuracy (deterministic sample, seed=70, N=5000)

| Metric | Value |
|--------|--------|
| Valid samples | 5000 |
| MAE | **0.0235** mag |
| Median AE | 0.0143 mag |
| P90 / P95 / P99 | 0.056 / **0.066** / 0.098 mag |
| Max AE | **0.43** mag |
| % > 0.05 / 0.10 / 0.20 | 11.6% / **0.62%** / 0.06% |

Sky bands (same sample): dark (≥21.5) MAE 0.022; moderate (19–21.5) MAE 0.049, 11.9% >0.10; bright (<19) n=11, MAE 0.084 (sparse in random global sample).

Oregon study remains the denser regional fidelity check (MAE ~0.036, P95 ~0.085); global random sample is **slightly better on average** than Oregon because dark ocean/land dominate the globe.

### Named points (source TIFF vs Python LPATLAS1; Swift matches Python to 1e-6)

| Site | Source | Artifact | \|error\| |
|------|--------|----------|-----------|
| Home (45.45, −122.75) | 18.5897 | 18.5396 | **0.050** |
| Stub Stewart (45.736, −123.192) | 21.3461 | 21.3418 | **0.004** |
| Downtown Portland | 17.9724 | 18.0913 | 0.119 |
| NYC | 16.9655 | 17.0451 | 0.080 |

Out-of-coverage latitudes return unavailable (`nil`); open ocean is typically modeled near pristine (~22), not NoData.

### Runtime (local)

| Path | Timing |
|------|--------|
| Python lookup | ~430–440 µs/point (no root-blob cache) |
| Swift init (mmap) | < 1 ms wall for open |
| Swift lookup | ~230 µs/point warm (2000 pts × 5) |

Single-coordinate app use is effectively instantaneous.

**Permission:** David Lorenz granted explicit permission to use his work and TIFF files. In-app credit appears in Settings → Data Sources → Light Pollution Atlas.

## Dense urban validation (LPATLAS1 v1, unchanged artifact)

Reproducible multi-metro study (`python -m light_pollution urban-validation`, config `config/urban_validation_regions.json`). Generated detail under ignored `output/urban_validation/`.

Headline (N≈59.5k valid urban-grid samples, 26 metros):

| Metric | Urban study | Prior global random |
|--------|-------------|---------------------|
| MAE | **0.050** mag | 0.024 mag |
| P95 | **0.137** mag | 0.066 mag |
| P99 | **0.191** mag | 0.098 mag |
| Max | **0.42** mag | 0.43 mag |
| % > 0.10 | **12.6%** | 0.62% |
| % > 0.20 | **0.74%** | 0.06% |

Errors concentrate on **high/extreme local gradients** (3×3 source range), not root boundaries (mean signed error ≈ 0). Worst metros by P95: Mumbai, Singapore, Miami, SF Bay, Sydney.

**Product impact (approved scoring, unchanged calibration):** rounded observing-quality score changes are almost always **0 or 1** point (never ≥2 in this sample) across NCS 50–93. Nearby pair order reversals under equal NCS are rare (~**0.68%** of pairs with stratified sampling; mostly near-tied sites). Score rounding in the harness matches Swift ties-away-from-zero.

**Recommendation from this study:** keep the current LPATLAS1 artifact for packaging; urban fidelity is weaker than the global random sample but product score impact remains small.

### Production packaging (main iOS app)

| Item | Value |
|------|--------|
| Bundled path | `Sources/AstroViewingConditions/Resources/LightPollution/light_pollution_global_v1.bin` |
| Target | Main iOS app only (not widget/watch) |
| Bytes / SHA-256 | 10,328,230 / `b9c60e83…dce4` |
| Runtime | `LightPollutionProviderBootstrap` (async once) → `ObservingQualityService` for app scoring and companion-state publication |
| Fallback | Missing/failed/out-of-coverage → exact `nightConditionsScore`; no pristine default |

### Rationale

- Visually competitive with uniform **0.05°** UInt8 for Oregon review, with selective **0.025°** detail where the tree refines
- About **half the size** of exact uniform 0.05° UInt8 (~9.6 MiB vs ~19.2 MiB)
- Substantially **lower max absolute error** than uniform 0.05°/0.1° on the Oregon full-root metrics (~0.52 vs ~1.1 / ~1.4)
- **Product-aware** hierarchical variants were larger without a material max-error or violating-cell advantage over error-only counterparts

### Productization status

- LPATLAS1 v1 is the committed production storage format for the 2025 atlas.
- The Swift decoder and app-only resource packaging are implemented.
- Widgets, watch, complications, and SharedCode do not embed the atlas.
- Dashboard, Best Nearby, widgets, watch, and complications use the shared Observing Quality definition when valid brightness is available and preserve the exact Night Conditions score otherwise. Best Targets scoring remains separate and is not light-pollution-aware.

## Where to dig deeper

| Artifact | Location |
|----------|----------|
| Hierarchical rate-vs-fidelity consolidation | `output/oregon/hierarchical_rate_fidelity.md` (gitignored when generated) |
| Oregon summary + viewer | `output/oregon/` |
| Fixed-adaptive world census | `output/world_adaptive_quant_census.json` |
| Hierarchical world census | `output/world_hierarchical_census.json` |
| Commands and formulas | [README.md](README.md) |
| Durable agent rules | [AGENTS.md](AGENTS.md) |

## Updating to a new atlas release

When a newer Lorenz (or successor) zenith-brightness GeoTIFF is published, treat the **2025 incumbent packaging configuration** as the baseline and revalidate before adopting the new file for any packaging or app work.

### Incumbent baseline configuration (2025 experiment)

| Parameter | Value |
|-----------|--------|
| Storage / quantization | **UInt8** |
| Refinement policy | **error-only** (not product-aware) |
| Subdivision max-error budget | **0.10 mag** |
| Finest spatial cap | **0.025°** (no native 0.0083° fallback) |
| Candidate id pattern | `hierarchical_adaptive_uint8_budget0.1_error_cap0.025` |

Uniform baselines (0.025° / 0.05° / 0.1° UInt8) and the hierarchical shortlist above remain the comparison anchors unless a full matrix reevaluation is triggered.

### Per-release validation procedure

For **each** newly released atlas file:

1. **Record provenance** for the new source (and keep the old record): version/date, filename, **SHA-256**, dimensions, CRS, geotransform, extent, pixel resolution, data type, NoData value, global valid min/max (streaming scan), attribution text, and license/permission status for redistribution or bundling.
2. **Compare structure** against the documented 2025 baseline (dimensions, CRS, origin, pixel size, extent, dtype, NoData semantics, band count/units). Note any difference explicitly.
3. **Run the incumbent configuration first** (UInt8, error-only, 0.10-mag budget, 0.025° cap)—do not start by reopening the full candidate matrix.
4. **Re-run Oregon full-root fidelity** for that hierarchical configuration (and the uniform UInt8 baselines as needed): named-point checks, viewer comparisons, top-error inspection, and the **exact worldwide hierarchical census** (`world-hierarchical-census`). Prefer the same commands and Python invocation as in [README.md](README.md).
5. **Compare** new Oregon metrics and census global MiB against the 2025 incumbent numbers in this document (and any prior release notes).
6. **Reopen the full candidate matrix** (other budgets, caps, product-aware policy, uniform alternatives, fixed-tile adaptive, etc.) **only when** source characteristics materially change, measured quality regresses, package size materially grows, or product requirements change—see triggers below.

### Adoption and iOS release procedure

After the validation above is accepted and permission to bundle that specific atlas release is confirmed:

1. **Generate the release candidate and manifest** with the selected configuration using the
   `generate-global` command in [README.md](README.md#generate). Do **not** pass
   `--skip-sha256` for a release candidate: the manifest must contain the source TIFF SHA-256
   as well as the always-generated artifact byte count and SHA-256. Preserve the manifest and
   validation results as release evidence even though `output/` is gitignored.
2. **Validate the generated artifact before copying it into the app:** run `artifact-info`, the
   named `lookup` checks, Python tests, Oregon/full-root validation, worldwide census, and dense
   urban validation as applicable. Confirm the manifest identity independently with
   `wc -c` and `shasum -a 256`; reconcile any difference before adoption.
3. **Replace the committed app resource** at
   `Sources/AstroViewingConditions/Resources/LightPollution/light_pollution_global_v1.bin`.
   A content-only atlas refresh that still uses LPATLAS1 v1 keeps the existing resource name and
   format version. An incompatible binary-layout change requires an explicit format/version,
   parser, filename, project, and compatibility review rather than silent replacement.
4. **Update every production identity and invalidation point:**
   - set `BundledLightPollutionResource.expectedByteCount` and `expectedSHA256` to the new
     artifact identity;
   - increment `LightPollutionDatasetIdentity.current.datasetRevision` for every adopted atlas
     content change so saved-location, Current Location, widget, and watch companion state is
     invalidated; change `formatVersion` only for an incompatible LPATLAS layout change;
   - update `BundledLightPollutionResourceTests`, dataset-identity expectations, committed
     size/SHA-256 documentation, production metrics, and Home/Stub Stewart or other known lookup
     expectations whose modeled values changed;
   - re-check Settings → Data Sources → Light Pollution Atlas and update attribution only when
     the new release's actual credit or permission terms require it. Preserve the permission and
     redistribution caveats; do not infer new rights from an earlier release.
5. **Regenerate and audit the Xcode project** from the repository root with
   `xcodegen generate --spec project.yml`. Replacing the same file under the existing
   main-app-only resource folder should require no membership expansion. Run the command
   twice to confirm stability, inspect the project diff, and verify the atlas has exactly one
   main iOS resources-phase membership and none in widget, watch, watch-widget/complication, or
   SharedCode resources.
6. **Run release-candidate validation:** Python tooling tests; binary-provider and bundled-resource
   tests with checksum verification; modeled-brightness validity/store/coordinator tests; widget
   and watch compatibility/fallback tests; the full iOS unit suite; clean build-for-testing; iOS,
   watchOS, widget, and watch-widget/complication builds; warning inspection; `git diff --check`;
   and a final review of tracked/untracked generation outputs. Tests must prove the newly bundled
   Home/Stub Stewart values (or deliberately updated replacement fixtures), not merely non-`nil`
   lookup results.
7. **Verify the Release archive, not only the source tree:** create the archive with the normal
   release configuration/signing workflow, then confirm the archived atlas is byte-for-byte
   identical to the committed resource and matches the new byte count/SHA-256. It must occur
   exactly once at the main app bundle root and zero times under iOS widget plug-ins, the embedded
   watch app, watch-widget/complication plug-ins, and embedded SharedCode frameworks.
8. **Perform final app/surface smoke checks:** main-app provider readiness, known-location OQ,
   corrupt/missing/out-of-coverage exact Night Conditions fallback, refreshed derived state after
   the dataset-revision bump, widget/watch fallback and recovery, and visible Settings credit.
   Record the accepted source identity, artifact identity, validation metrics, archive membership,
   and release result in this document or the release-validation record before shipping.

### Default reevaluation triggers

These are **review triggers**, not automatic rejection thresholds. A future run may **retain the incumbent configuration** if differences are understood and acceptable (e.g. slightly larger size with explained geographic coverage change).

Open a broader reevaluation when **any** of the following hold relative to the 2025 incumbent (or the last accepted baseline):

| Trigger | Condition |
|---------|-----------|
| Structure | Dimensions, CRS, extent, pixel resolution, data type, or NoData semantics change |
| Size | Exact global encoded size (hierarchical census for the incumbent config) increases by **more than 10%** |
| Oregon MAE | Increases by **more than 0.01 mag** |
| Oregon P95 AE | Increases by **more than 0.02 mag** |
| Oregon max AE | Increases by **more than 0.10 mag** |
| Product bands | Provisional product-band agreement drops by **more than 1 percentage point** |
| Qualitative | Named-point checks or visual urban/rural boundaries regress materially |
| Product | App size or fidelity requirements change |

Also reevaluate if license/permission status for the new release is unclear or more restrictive than previously assumed.

### Caches and outputs across versions

Generated crops, caches, checkpoints, viewer assets, and census JSON are **version-specific**. Do **not** reuse them across atlas versions unless provenance and cache keys **explicitly** match the new source (path, SHA-256, and geotransform/dimensions). When switching sources, clear or isolate `cache/` and `output/` (including `hierarchical_census_checkpoint/`) for that version, or use separate output directories keyed by atlas year/hash.
