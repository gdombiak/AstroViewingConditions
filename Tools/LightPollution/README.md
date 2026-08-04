# Light Pollution Atlas Validation Harness

Mac-only offline tooling to measure compact representations of **David Lorenz’s 2025 global zenith-sky-brightness atlas** for a future light-pollution-aware feature in Astro Viewing Conditions.

**Scope:** Fidelity validation is **Oregon-focused** (reconstruction, metrics, named points, viewer). The harness also runs **worldwide streaming censuses** and can generate a **production LPATLAS1 binary** for offline app lookup. Wiring the binary into observing-quality scoring / UI is a separate product step.

For the completed experiment’s headline results and recommendation, see [VALIDATION_RESULTS.md](VALIDATION_RESULTS.md). That document also defines the **[atlas update procedure](VALIDATION_RESULTS.md#updating-to-a-new-atlas-release)** (incumbent 2025 configuration, revalidation steps, and review triggers). Detailed generated reports live under ignored `output/`.

Binary layout: [BINARY_FORMAT.md](BINARY_FORMAT.md).

## Attribution

Source values are **modeled zenith sky brightness** in **magnitudes per square arcsecond** (mag/arcsec²). Larger values mean darker skies. These are **not** Bortle classes.

Atlas by [David Lorenz](https://djlorenz.github.io/astronomy/lp/) — product used here: **zenith_brightness_v22_2025** (2025 global zenith-brightness GeoTIFF). **Explicit permission to use the work and TIFF files was obtained directly from the author.** This harness and any derived offline binary do **not** themselves grant third-party redistribution rights.

**In-app attribution (when the atlas is productized):** surface David Lorenz / Light Pollution Atlas credit in About or data-source UI, linking to https://djlorenz.github.io/astronomy/lp/.

## Prerequisites

- macOS with Homebrew
- **GDAL** with Python bindings (`osgeo`)
- **Homebrew Python 3** (e.g. `/opt/homebrew/bin/python3`)
- NumPy, pytest

### Verify GDAL Python bindings

```bash
/opt/homebrew/bin/python3 -c "from osgeo import gdal; print(gdal.__version__)"
```

If `osgeo` fails on another interpreter (e.g. `/usr/bin/python3`), use Homebrew `python3` or set `PYTHONPATH` to the Homebrew GDAL site-packages. The harness refuses to run without `osgeo`.

### Python environment

```bash
cd Tools/LightPollution
/opt/homebrew/bin/python3 -m venv --system-site-packages .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Consistent invocation** (after activating the venv, or via `.venv/bin/python`):

```bash
.venv/bin/python -m light_pollution <command> [options]
```

## Source GeoTIFF

Default path: `~/Downloads/zenith_brightness_v22_2025.tiff`

Do **not** commit this file (~2.9 GB).

### Inspect

```bash
cd Tools/LightPollution
.venv/bin/python -m light_pollution inspect --source ~/Downloads/zenith_brightness_v22_2025.tiff
# faster (skip SHA-256):
.venv/bin/python -m light_pollution inspect --skip-sha256
```

Or with GDAL CLI:

```bash
gdalinfo ~/Downloads/zenith_brightness_v22_2025.tiff
```

Expected (2025): EPSG:4326, 43,200×16,801 Float32, 1/120°, origin (−180, 75), NoData ≈ 9.96921e36, units mag/arcsec².

## Oregon crop

Primary fidelity extent: lon −125…−116, lat 42…47 (`config/regions/oregon.json`).

```bash
.venv/bin/python -m light_pollution build-crop --source ~/Downloads/zenith_brightness_v22_2025.tiff
```

Cache: `cache/oregon/source_crop.npy` (+ GeoTIFF + meta). Reused by later steps.

## Full Oregon pipeline

```bash
.venv/bin/python -m light_pollution run-oregon --source ~/Downloads/zenith_brightness_v22_2025.tiff
# optional:
#   --skip-sha256
#   --skip-global-minmax   # conservative UInt8 bounds (not preferred)
#   --force-crop
```

This will:

1. Validate source + provenance (path, size, SHA-256, metadata, GDAL version, timestamp)
2. Streaming global min/max for safe quantization bounds
3. Build/reuse Oregon crop
4. Generate **uniform spatial**, **quantization**, **sparse**, **fixed-tile adaptive**, and **hierarchical adaptive** candidates
5. Reconstruct each to the source-aligned Oregon grid (nearest-neighbor on the metric path)
6. For hierarchical candidates: encode **full global roots** intersecting Oregon, then crop reconstruction for metrics/viewer
7. Write metrics, named points, top-error tables, size estimates, viewer assets
8. When census JSON already exists under `output/`, **merge census-derived global sizes** into hierarchical (and related) reports in preference to Oregon-scaled placeholders

Outputs under `output/oregon/` (gitignored). A committed summary of the completed experiment is in [VALIDATION_RESULTS.md](VALIDATION_RESULTS.md).

## Worldwide censuses (no full-world reconstructed rasters)

Streaming passes over the global GeoTIFF estimate packaging size without writing full-world candidate rasters.

### Fixed-tile adaptive census

```bash
.venv/bin/python -m light_pollution world-adaptive-census \
  --source ~/Downloads/zenith_brightness_v22_2025.tiff
# optional: --skip-minmax
```

- Writes: `output/world_adaptive_quant_census.json`
- Exact worldwide size model for **fixed-tile adaptive** UInt8/UInt16 variants (same builder semantics as Oregon adaptive candidates).

### Hierarchical adaptive census

```bash
# Optional: one root-row benchmark + equivalence samples
.venv/bin/python -m light_pollution hierarchical-benchmark \
  --source ~/Downloads/zenith_brightness_v22_2025.tiff \
  --workers 8 --root-j 4

# Full worldwide hierarchical census (multiprocess)
.venv/bin/python -m light_pollution world-hierarchical-census \
  --source ~/Downloads/zenith_brightness_v22_2025.tiff \
  --workers 8
# --no-resume   # ignore checkpoints and recompute all root rows
```

- Writes: `output/world_hierarchical_census.json`
- Checkpoints: `output/hierarchical_census_checkpoint/row_*.json` (atomic per root row; resume is default unless `--no-resume`)
- Parent process performs GDAL reads; workers analyze roots. `--workers` defaults to `min(8, cpu_count - 1)`.

### Legacy sparse tile-type census

```bash
.venv/bin/python -m light_pollution world-tile-census \
  --source ~/Downloads/zenith_brightness_v22_2025.tiff
```

- Writes: `output/world_tile_census.json` (simple sparse representation counts; not a full hierarchical encode).

## Global size reporting (authoritative rules)

| Candidate class | How global size is obtained | Authority |
|-----------------|----------------------------|-----------|
| **Uniform** (spatial ± quantize) | Exact output width/height from **source dimensions** and reduction factor (`uniform_global_size_exact`), including floor edge policy (e.g. leftover row for height 16,801), × bytes/cell + metadata | **Exact** under that layout |
| **Sparse** fixed-resolution | Oregon payload scaled by area/cell ratio unless a dedicated sparse worldwide census applies | **Preliminary** Oregon-scaled unless a census exists |
| **Fixed-tile adaptive** | Streaming `world-adaptive-census` | **Census-derived** — takes precedence over Oregon-scaled adaptive estimates |
| **Hierarchical adaptive** | Streaming `world-hierarchical-census` | **Census-derived** — takes precedence over Oregon-scaled placeholders |

**Do not** treat Oregon-scaled fixed-adaptive MiB figures (often hundreds of MiB in generated Oregon-only tables) as the packaging size. Earlier exact worldwide fixed-adaptive census results are on the order of **~87–138 MiB** depending on budget/storage; always prefer `output/world_adaptive_quant_census.json` when present, and label any remaining Oregon-scaled figures as preliminary.

## Production global binary (LPATLAS1)

Selected representation: **`hierarchical_adaptive_uint8_budget0.1_error_cap0.025`**
(UInt8 quantized hierarchical adaptive, 0.10 mag error target, 0.025° finest cap, no native fallback).

Format specification: [BINARY_FORMAT.md](BINARY_FORMAT.md).

### Generate

```bash
.venv/bin/python -m light_pollution generate-global \
  --source ~/Downloads/zenith_brightness_v22_2025.tiff \
  --output output/artifacts/light_pollution_global_v1.bin \
  --report output/artifacts/light_pollution_global_v1.manifest.json \
  --workers 8 \
  --skip-sha256
```

- Writes the binary **atomically** (temp file then replace).
- Manifest records source metadata, algorithm, quant range, root stats, size, and attribution.
- Does **not** load the entire Float32 raster at once (windowed roots).
- Generated path is **gitignored** (`output/artifacts/`). Decide deliberately before committing a binary.

### Inspect and lookup

```bash
.venv/bin/python -m light_pollution artifact-info \
  --artifact output/artifacts/light_pollution_global_v1.bin

.venv/bin/python -m light_pollution lookup \
  --artifact output/artifacts/light_pollution_global_v1.bin \
  --latitude 45.45 --longitude -122.75
```

### Cross-surface scoring architecture

See [CROSS_SURFACE_ARCHITECTURE.md](CROSS_SURFACE_ARCHITECTURE.md): hybrid model (main app local LPATLAS1; widgets/watch planned via shared calculator + brightness/score payloads, not necessarily embedding the 10 MiB artifact). Composition root owns bootstrap—not feature views.

**Phase 1 foundation (SharedCode):** `LightPollutionDatasetIdentity`, `ModeledZenithBrightnessSample`, `ModeledZenithBrightnessValidity` (shared 1000 m haversine + dataset checks), `ModeledZenithBrightnessResolver`.

**Phase 2 (SharedCode):** durable saved-location companion metadata in App Group `savedLocationModeledBrightness.json`; sole-writer `SavedLocationModeledBrightnessCoordinator`; read-only `SavedLocationModeledBrightnessReading`. Not iCloud; no widget score changes yet.

**Phase 3 (SharedCode):** Current Location companion `currentLocationModeledBrightness.json`; sole-writer `CurrentLocationModeledBrightnessCoordinator`; injected `CurrentLocationBrightnessPublishing` from GPS resolve; read-only `CurrentLocationModeledBrightnessReading`.

**Phase 4A (SharedCode + iOS widgets, on feature branch):** `CrossSurfaceObservingQualityResolver` + enriched `WidgetNightSummary` dual scores for Night Conditions and Three-Night Outlook; no watch transport yet.

### Production app packaging

The validated production artifact is **copied into the iOS app target** (not generated at build time):

| Item | Value |
|------|--------|
| Source of truth (tooling) | `output/artifacts/light_pollution_global_v1.bin` (gitignored) |
| Bundled app resource | `Sources/AstroViewingConditions/Resources/LightPollution/light_pollution_global_v1.bin` (**committed**) |
| Bytes | 10,328,230 |
| SHA-256 | `b9c60e83d866f28e781dcc89a4ad302597012cdb9df6c94743efdd44be86dce4` |
| Targets | Main iOS app only (not widget/watch in this phase) |

Regenerate tooling output with `generate-global`, verify size/SHA-256, then replace the Resources copy and update `BundledLightPollutionResource` constants if needed. Runtime falls back to the night-conditions score when the resource is missing or fails validation.

### Dense urban validation

Deterministic multi-city fidelity study (source TIFF vs LPATLAS1; does **not** regenerate the artifact):

```bash
.venv/bin/python -m light_pollution urban-validation \
  --source ~/Downloads/zenith_brightness_v22_2025.tiff \
  --artifact output/artifacts/light_pollution_global_v1.bin \
  --output output/urban_validation
```

Region boxes and sampling: `config/urban_validation_regions.json`.  
Generated reports (gitignored): `output/urban_validation/`.

### Cross-language fixture

Tiny synthetic artifact (checked in under `fixtures/`) is produced by Python and consumed by Swift unit tests so both languages share one serializer:

- `fixtures/lpatlas1_tiny_constant.bin`
- `fixtures/lpatlas1_tiny_constant.lookups.json`

Named geographic validation points (no embedded results): `config/points/global_validation_points.json`.

### Swift runtime

`BinaryLightPollutionProvider` in SharedCode implements `LightPollutionProviding` and reads LPATLAS1 without TIFF/GDAL. It is **not** wired into `NightQualityAnalyzer` / observing score yet.

## Hierarchical budget semantics

- The configured **maximum absolute error** budget drives which representation a node may use and when it subdivides.
- The budget is **not** a global guarantee once the **finest spatial cap** is reached (no native 0.0083° fallback).
- A candidate must **not** be described as meeting its budget if any leaf or valid-cell violations remain.
- Always report **violating-leaf %** and **violating-valid-cell %** separately from mean error metrics.

Fixed-tile adaptive differs: it may use **native-resolution** tile payloads to satisfy the configured max-AE budget (see [AGENTS.md](AGENTS.md)).

## Formulas

**Linear brightness**

\[
L = 10^{-0.4 m},\quad m = -2.5 \log_{10} L
\]

**Preferred aggregation:** mean of \(L\) over valid cells, convert back to \(m\).

**Baseline:** direct mean of \(m\) (labeled `mag_avg` only).

**NoData:** excluded from aggregates; all-NoData tiles ≠ valid pristine/default tiles.

**Constant under max-error selection:** min/max midpoint (minimax), distinct from linear-brightness spatial aggregation.

## Tests

Synthetic only — **does not** need the 2.9 GB source:

```bash
cd Tools/LightPollution
.venv/bin/python -m pytest -q
```

## Viewer

After `run-oregon` (and optional consolidation of census sizes into the Oregon summary):

```bash
.venv/bin/python -m light_pollution serve-viewer --port 8765
```

Open <http://127.0.0.1:8765/viewer/>

Static HTML/JS; no permanent backend. Offline raster comparison works without external basemap tiles. Optional hierarchy leaf overlay for hierarchical candidates.

## Candidate families

| Family | Notes |
|--------|--------|
| Uniform spatial | 0.025° / 0.05° / 0.1° × nearest, mag_avg (baseline), linear_avg |
| Quantization | UInt8 / UInt16 on full Oregon crop and on reduced grids |
| Sparse fixed-res | Tiles on 0.05° conceptual grid; Float32 and UInt8 variants |
| Fixed-tile adaptive | Fixed ~0.5° tiles; default/constant/0.1°/0.05°/0.025°/native; Float32 baseline + UInt8/UInt16; **native fallback** allowed to meet budget |
| Hierarchical adaptive | Quadtree on 768-cell roots; min-byte selection; error vs product policies; finest caps 0.025°/0.05°; **no native fallback** |

## Adding regions later

1. Add `config/regions/<id>.json` with lon/lat bounds  
2. Add `config/points/<id>_points.json` if desired  
3. Extend crop/pipeline similarly (crop → candidates; hierarchical still uses full roots intersecting the window)

## Layout

- `light_pollution/` — Python package  
- `config/` — regions, points, bands, quantization, hierarchical  
- `tests/` — unit tests (synthetic)  
- `viewer/` — browser UI  
- `cache/`, `output/` — ignored generated data  
- `AGENTS.md` — durable agent rules  
- `VALIDATION_RESULTS.md` — committed experiment summary  

## Updating to a new atlas release

When a new zenith-brightness GeoTIFF is released, revalidate against the **2025 incumbent** hierarchical configuration (UInt8, error-only, 0.10-mag budget, 0.025° finest cap) before packaging. Full procedure, comparison steps, reevaluation triggers, and cache/version rules: **[VALIDATION_RESULTS.md — Updating to a new atlas release](VALIDATION_RESULTS.md#updating-to-a-new-atlas-release)**.

## Non-goals

No production Swift changes, no app bundling, no scoring UI, no server, no historical atlas years, no Bortle labeling, no final app storage format lock-in from this harness alone.
