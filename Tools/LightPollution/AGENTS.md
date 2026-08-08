# Light Pollution Tooling — Agent Rules

Durable constraints for work under `Tools/LightPollution/`.

## Never

- Commit source GeoTIFFs, TIFF crops, large caches, or full-world generated rasters.
- Average magnitude values directly in the **preferred** aggregation path (linear-brightness average is required).
- Call atlas values or product test bands "Bortle classes."
- Modify production Swift code or app resources unless explicitly requested.
- Fold light pollution into `NightQualityAnalyzer`, or reuse the environmental Observing Quality penalty as Best Targets scoring. Target-specific Best Targets light-pollution integration may change only when explicitly in scope.
- Re-implement Observing Quality penalty anchors or fallback behavior outside `ObservingQualityCalculator`.
- Regenerate or replace the committed production binary merely because tooling was run. Atlas adoption requires the release procedure in `VALIDATION_RESULTS.md` and explicit permission review for that source release.
- Add the production atlas to widgets, watch, watch-widget/complications, or SharedCode. It is a main-iOS-app-only resource.
- Load the complete global raster into memory.
- Write multiple full-world reconstructed candidate rasters during validation.
- Claim that a hierarchical candidate **meets** its configured max-error budget when any finest-cap leaf or valid-cell violations remain.

## Always

- Preserve reproducibility: record source provenance (path, size, SHA-256, metadata), GDAL version, config, crop transform, and timestamps in reports.
- Exclude NoData correctly; keep **all-NoData tiles** distinct from **valid pristine/default** tiles.
- Compare reconstructed candidates on a common source-aligned grid without metric-path interpolation that conceals resolution.
- Keep large generated outputs under ignored `cache/` and `output/` directories.
- Prefer windowed/streaming I/O and reuse cached Oregon intermediates.
- Prefer **census-derived** global sizes over Oregon-scaled estimates when the applicable census JSON exists (`world-adaptive-census`, `world-hierarchical-census`).
- Report hierarchical **violating-leaf %** and **violating-valid-cell %** separately from mean error metrics.
- Keep the committed artifact identity, runtime constants, dataset revision, validation record, XcodeGen membership, archive inspection, and attribution aligned when an atlas release is deliberately adopted.
- Use `VALIDATION_RESULTS.md#updating-to-a-new-atlas-release` as the canonical adoption/release procedure; link to it rather than duplicating partial checklists.

## Adaptive variants (do not conflate)

### Fixed-tile adaptive (`adaptive_*`)

- Fixed source-aligned tiles (e.g. ~0.5°).
- Acceptance uses **maximum absolute reconstruction error** against the configured budget (percentiles are diagnostic only).
- **Native-resolution tile fallback is allowed** so a tile can satisfy the configured max-AE budget.
- Worldwide packaging size: `world-adaptive-census` (exact under that census model).

### Hierarchical adaptive (`hierarchical_adaptive_*`)

- Separate algorithm (quadtree / multi-resolution roots). Do not rename or treat as the same as fixed-tile adaptive.
- **No native 0.0083° fallback**; finest caps are 0.025° or 0.05°.
- The max-error budget drives subdivision and representation choice but is **not** a global guarantee at the finest cap.
- Unresolved finest-cap violations must be recorded; never claim guaranteed budget compliance when violations remain.
- Oregon fidelity uses **full global roots** intersecting the region, then crops; worldwide size: `world-hierarchical-census`.

## Preferred science

- Larger mag/arcsec² ⇒ darker sky.
- Preferred reduction: convert mag → linear brightness → aggregate valid cells → convert back to mag.
- Direct magnitude averaging is allowed only as a labeled baseline.
- Constant approximation under a max-error constraint uses min/max midpoint (minimax), not linear-brightness averaging.
