"""Oregon milestone end-to-end pipeline."""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

from .adaptive_tiles import AdaptiveConfig, encode_adaptive
from .census import census_adaptive_quantized
from .crop import build_region_crop, load_crop, load_region_config
from .disk import ensure_space, free_bytes, human_bytes
from .grid import GeoGrid
from .metrics import assign_product_band, band_agreement, compute_error_metrics, top_absolute_errors
from .nodata import DEFAULT_NODATA, valid_mask
from .paths import CACHE, CONFIG, DEFAULT_SOURCE, OUTPUT, ROOT
from .quantize import (
    UInt8Params,
    UInt16Params,
    dequantize_uint8,
    dequantize_uint16,
    quantize_uint8,
    quantize_uint16,
)
from .reconstruct import reconstruct_uniform_integer_factor
from .reduce import METHODS, TARGET_DEGREES, reduce_array
from .report import write_json, write_markdown_summary
from .sizes import (
    GLOBAL_HEIGHT,
    GLOBAL_WIDTH,
    bytes_to_mib,
    reduced_dimensions,
    size_report_fields,
    sparse_global_size_preliminary,
    uniform_global_size_exact,
    uniform_region_payload,
)
from .source import gdal_version, inspect_source, require_osgeo, streaming_global_minmax
from .sparse_tiles import SparseTileConfig, decode_sparse, encode_sparse
from .viewer_export import export_error_png, export_raster_for_viewer
from .hierarchical import HierarchicalConfig
from .hierarchical_oregon import encode_oregon_via_full_roots
from .hierarchical_serialize import SerConfig, total_global_bytes
from .hierarchical import n_root_cols, n_root_rows
from .sizes import bytes_to_mib as _btm  # noqa — used via sizes.bytes_to_mib already


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def run_inspect(source: Path, out_dir: Path, sha256: bool = True) -> dict[str, Any]:
    require_osgeo()
    meta = inspect_source(source, compute_sha256=sha256)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_json(out_dir / "source_metadata.json", meta)
    if not meta["validation"]["ok"]:
        raise RuntimeError(f"Source validation failed: {meta['validation']['issues']}")
    print("Source OK:", meta["width"], "x", meta["height"], meta["dtype"])
    return meta


def run_global_minmax(source: Path, out_dir: Path) -> dict[str, Any]:
    print("Streaming global min/max scan...")
    stats = streaming_global_minmax(source)
    write_json(out_dir / "global_minmax.json", stats)
    print("Global valid min/max:", stats["min"], stats["max"])
    return stats


def run_oregon_pipeline(
    source: Path = DEFAULT_SOURCE,
    skip_sha256: bool = False,
    skip_global_minmax: bool = False,
    force_crop: bool = False,
) -> dict[str, Any]:
    t0 = time.time()
    require_osgeo()
    out_root = OUTPUT / "oregon"
    out_root.mkdir(parents=True, exist_ok=True)
    viewer_dir = out_root / "viewer_data"
    cand_dir = out_root / "candidates"
    cand_dir.mkdir(parents=True, exist_ok=True)

    free = free_bytes(ROOT)
    print(f"Disk free: {human_bytes(free)}")
    ensure_space(ROOT, 200 * 1024 * 1024)

    source_meta = run_inspect(source, out_root, sha256=not skip_sha256)
    if skip_global_minmax:
        global_mm = {
            "min": 13.0,
            "max": 22.0,
            "source": "skipped_scan_using_conservative_bounds",
        }
        write_json(out_root / "global_minmax.json", global_mm)
        gmin, gmax = 13.0, 22.0
    else:
        global_mm = run_global_minmax(source, out_root)
        gmin = float(global_mm["min"])
        gmax = float(global_mm["max"])

    u8_min = min(16.0, np.floor(gmin * 100) / 100 - 0.05)
    u8_max = max(22.5, np.ceil(gmax * 100) / 100 + 0.05)
    u8_params = UInt8Params(m_min=float(u8_min), m_max=float(u8_max), nodata_code=255)
    u16_params = UInt16Params(m_min=16.0, step=0.01, nodata_code=65535)

    quant_cfg = _load_json(CONFIG / "quantization.json")
    pristine_default = float(quant_cfg.get("pristine_default_mag", 22.0))
    bands_cfg = _load_json(CONFIG / "product_bands.json")
    bands = bands_cfg["bands"]
    points_cfg = _load_json(CONFIG / "points" / "oregon_points.json")
    region = load_region_config(CONFIG / "regions" / "oregon.json")

    build_region_crop(source, region, force=force_crop)
    arr, grid, crop_meta = load_crop("oregon")
    nodata = grid.nodata
    oregon_cells = int(arr.size)
    src_h, src_w = arr.shape
    print(f"Oregon crop shape {arr.shape}, cells={oregon_cells}")

    valid = arr[valid_mask(arr, nodata)]
    vmin = float(valid.min())
    vmax = float(valid.max())
    print(f"Oregon value range: {vmin:.4f} .. {vmax:.4f}")

    provenance = {
        "source_path": source_meta["path"],
        "source_name": source_meta["name"],
        "source_size_bytes": source_meta["size_bytes"],
        "source_sha256": source_meta.get("sha256"),
        "source_metadata": {
            k: source_meta[k]
            for k in (
                "width", "height", "dtype", "nodata", "geotransform",
                "block_size", "unit_type", "band_metadata",
            )
            if k in source_meta
        },
        "gdal_version": gdal_version(),
        "crop_transform": crop_meta["grid"],
        "crop_window": crop_meta["window"],
        "global_minmax": global_mm,
        "uint8_params": u8_params.to_dict(),
        "uint16_params": u16_params.to_dict(),
        "pristine_default_mag": pristine_default,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "region": region,
        "constant_method": "minmax_midpoint",
        "mask_encoding": "np.packbits",
    }
    write_json(out_root / "provenance.json", provenance)
    export_raster_for_viewer(viewer_dir, "original", arr, grid.to_dict(), vmin, vmax, nodata)

    candidates: list[dict[str, Any]] = []
    point_rows: list[dict[str, Any]] = []
    top_errors_all: dict[str, list] = {}

    def sample_points(name: str, candidate_arr: np.ndarray) -> list[dict[str, Any]]:
        rows = []
        for p in points_cfg["points"]:
            o = grid.sample_nearest(arr, p["lon"], p["lat"])
            c = grid.sample_nearest(candidate_arr, p["lon"], p["lat"])
            o_ok = abs(o) < 1e30
            c_ok = abs(c) < 1e30
            err = (c - o) if (o_ok and c_ok) else None
            rows.append({
                "candidate": name,
                "point_id": p["id"],
                "name": p["name"],
                "lon": p["lon"],
                "lat": p["lat"],
                "original": o if o_ok else None,
                "candidate_value": c if c_ok else None,
                "signed_error": err,
                "abs_error": abs(err) if err is not None else None,
                "original_band": assign_product_band(o, bands, nodata) if o_ok else None,
                "candidate_band": assign_product_band(c, bands, nodata) if c_ok else None,
            })
        return rows

    def register(
        cid: str,
        family: str,
        reconstructed: np.ndarray,
        oregon_bytes: int,
        global_size: dict[str, Any],
        extra: dict[str, Any] | None = None,
        error_kind: str = "combined",
        collect_top_errors: bool = True,
    ) -> dict[str, Any]:
        metrics = compute_error_metrics(arr, reconstructed, nodata)
        bag = band_agreement(arr, reconstructed, bands, nodata)
        tops = top_absolute_errors(arr, reconstructed, grid, bands, nodata, n=20) if collect_top_errors else []
        top_errors_all[cid] = tops
        rec = {
            "id": cid,
            "family": family,
            "error_kind": error_kind,
            "metrics": metrics,
            "band_agreement": bag,
            "oregon_bytes": oregon_bytes,
            "oregon_mib": bytes_to_mib(oregon_bytes),
            "global_size": global_size,
            "global_size_summary": size_report_fields(global_size),
            "top_errors": tops,
            "extra": extra or {},
        }
        candidates.append(rec)
        export_raster_for_viewer(viewer_dir, cid, reconstructed, grid.to_dict(), vmin, vmax, nodata)
        export_error_png(viewer_dir, f"{cid}_signed_err", arr, reconstructed, nodata, emax=0.3, signed=True)
        export_error_png(viewer_dir, f"{cid}_abs_err", arr, reconstructed, nodata, emax=0.3, signed=False)
        point_rows.extend(sample_points(cid, reconstructed))
        gsum = size_report_fields(global_size)
        print(
            f"  [{cid}] MAE={metrics.get('mae')} maxAE={metrics.get('max_ae')} "
            f"OR={oregon_bytes}B G={gsum.get('global_total_mib')} MiB ({gsum.get('reliability')})"
        )
        return rec

    def pad_recon(recon: np.ndarray) -> np.ndarray:
        if recon.shape == arr.shape:
            return recon
        full = np.full(arr.shape, nodata, dtype=np.float32)
        full[: recon.shape[0], : recon.shape[1]] = recon
        return full

    # ========== Spatial reductions ==========
    print("Generating spatial reduction candidates...")
    for target in TARGET_DEGREES:
        for method in METHODS:
            coarse, cgrid, info = reduce_array(arr, grid, target, method)
            factor = info["factor"]
            recon = pad_recon(reconstruct_uniform_integer_factor(coarse, factor, arr.shape, nodata))
            region_sz = uniform_region_payload(src_w, src_h, factor, 4)
            # actual coarse may match region floor dims
            payload = int(coarse.nbytes)
            gsz = uniform_global_size_exact(factor, bytes_per_cell=4)
            np.save(cand_dir / f"spatial_{target}_{method}.npy", coarse)
            write_json(cand_dir / f"spatial_{target}_{method}.json", {**info, "grid": cgrid.to_dict(), "region_payload": region_sz})
            register(
                f"spatial_{target}_{method}",
                "spatial",
                recon,
                payload,
                gsz,
                extra={**info, "region_payload": region_sz},
                error_kind="spatial_reduction",
            )

    # ========== Quantization only ==========
    print("Quantization-only candidates...")
    codes16, meta16 = quantize_uint16(arr, u16_params, nodata)
    recon16 = dequantize_uint16(codes16, u16_params, nodata)
    register(
        "quant_u16_full",
        "quantization",
        recon16,
        int(codes16.nbytes),
        uniform_global_size_exact(1, bytes_per_cell=2),
        extra=meta16,
        error_kind="quantization_only",
    )
    codes8, meta8 = quantize_uint8(arr, u8_params, nodata)
    recon8 = dequantize_uint8(codes8, u8_params, nodata)
    register(
        "quant_u8_full",
        "quantization",
        recon8,
        int(codes8.nbytes),
        uniform_global_size_exact(1, bytes_per_cell=1),
        extra=meta8,
        error_kind="quantization_only",
    )

    # ========== Full quantized linear_avg matrix: 0.025, 0.05, 0.1 × u8/u16 ==========
    print("Quantized linear_avg matrix (all resolutions)...")
    for target in (0.025, 0.05, 0.1):
        coarse, cgrid, info = reduce_array(arr, grid, target, "linear_avg")
        factor = info["factor"]
        for label, qfun, dqfun, params, bpc in (
            ("u16", quantize_uint16, dequantize_uint16, u16_params, 2),
            ("u8", quantize_uint8, dequantize_uint8, u8_params, 1),
        ):
            codes, qmeta = qfun(coarse, params, nodata)
            deq = dqfun(codes, params, nodata)
            recon = pad_recon(reconstruct_uniform_integer_factor(deq, factor, arr.shape, nodata))
            gsz = uniform_global_size_exact(factor, bytes_per_cell=bpc)
            region_sz = uniform_region_payload(src_w, src_h, factor, bpc)
            register(
                f"spatial_{target}_linear_avg_{label}",
                "spatial+quantization",
                recon,
                int(codes.nbytes),
                gsz,
                extra={"spatial": info, "quant": qmeta, "region_payload": region_sz},
                error_kind="combined",
            )

    # ========== Sparse tiles ==========
    print("Sparse tile candidates...")
    coarse05, cgrid05, info05 = reduce_array(arr, grid, 0.05, "linear_avg")
    factor05 = info05["factor"]
    # Float32 sparse baselines (subset) + production UInt8 sparse
    sparse_jobs = []
    for tile in (16, 32, 64):
        for tol in (0.05, 0.10):
            sparse_jobs.append((tile, tol, "float32"))
    # required production-relevant: sparse 0.05 UInt8
    for tile in (16, 32, 64):
        for tol in (0.05, 0.10, 0.20):
            sparse_jobs.append((tile, tol, "uint8"))

    for tile, tol, storage in sparse_jobs:
        cfg = SparseTileConfig(
            tile_h=tile,
            tile_w=tile,
            tolerance=tol,
            pristine_default=pristine_default,
            nodata=nodata,
            storage=storage,  # type: ignore
            u8=u8_params,
            u16=u16_params,
        )
        tiles, stats = encode_sparse(coarse05, cfg)
        decoded = decode_sparse(tiles, coarse05.shape, cfg)
        recon = pad_recon(reconstruct_uniform_integer_factor(decoded, factor05, arr.shape, nodata))
        gsz = sparse_global_size_preliminary(stats, oregon_cells)
        cid = f"sparse_0.05_t{tile}_tol{tol}_{storage}"
        register(
            cid,
            "sparse",
            recon,
            int(stats["total_estimated_bytes"]),
            gsz,
            extra=stats,
            error_kind="sparse_reconstruction",
        )
        write_json(cand_dir / f"{cid}_stats.json", stats)

    # ========== Adaptive: float32 baseline + UInt8 + UInt16 ==========
    print("Adaptive tile candidates...")
    adaptive_budgets = [0.05, 0.10, 0.20]
    for storage in ("float32", "uint8", "uint16"):
        for budget in adaptive_budgets:
            acfg = AdaptiveConfig(
                tile_source_cells=60,
                error_budget=budget,
                pristine_default=pristine_default,
                nodata=nodata,
                source_pixel_deg=abs(grid.pixel_width),
                storage=storage,  # type: ignore
                u8=u8_params,
                u16=u16_params,
            )
            tiles, recon, stats = encode_adaptive(arr, acfg)
            te = stats.pop("tile_errors")
            write_json(cand_dir / f"adaptive_{storage}_budget{budget}_tile_errors.json", te)
            write_json(cand_dir / f"adaptive_{storage}_budget{budget}_stats.json", stats)
            gsz = sparse_global_size_preliminary(stats, oregon_cells)
            # Attach tile max-error distribution summary
            stats["tile_error_file"] = f"adaptive_{storage}_budget{budget}_tile_errors.json"
            register(
                f"adaptive_{storage}_budget{budget}",
                "adaptive",
                recon,
                int(stats["total_estimated_bytes"]),
                gsz,
                extra=stats,
                error_kind="adaptive_reconstruction",
            )


    # ========== Hierarchical adaptive (additive; full global roots) ==========
    print("Hierarchical adaptive candidates (full intersecting roots from source)...")
    window = crop_meta["window"]
    hier_jobs = []
    for budget in (0.05, 0.10, 0.20):
        for policy in ("error", "product"):
            for finest, cap_label in ((3, "0.025"), (6, "0.05")):
                hier_jobs.append(("uint8", budget, policy, finest, cap_label))
    # UInt16 reference
    hier_jobs.append(("uint16", 0.10, "error", 3, "0.025"))

    for storage, budget, policy, finest, cap_label in hier_jobs:
        hcfg = HierarchicalConfig(
            root_cells=768,
            finest_cells=finest,
            error_budget=budget,
            policy=policy,  # type: ignore
            storage=storage,  # type: ignore
            pristine_default=pristine_default,
            nodata=nodata,
            u8=u8_params,
            u16=u16_params,
            product_bands=bands,
        )
        cid = f"hierarchical_adaptive_{storage}_budget{budget}_{policy}_cap{cap_label}"
        print(f"  building {cid} ...")
        hres = encode_oregon_via_full_roots(
            source,
            window["xoff"],
            window["yoff"],
            window["xsize"],
            window["ysize"],
            hcfg,
        )
        recon = hres["recon"]
        viol = hres["budget_violations_summary"]
        # Cell-level violation stats on Oregon window
        from light_pollution.nodata import is_nodata as _isnd
        o_nd = _isnd(arr, nodata)
        ae = np.abs(recon - arr)
        # leaves not available mosaic-wide; use recon error > budget as cell violation proxy when meets is False
        cell_viol = (~o_nd) & (ae > budget + 1e-9)
        n_cell_viol = int(np.sum(cell_viol))
        n_valid = int(np.sum(~o_nd))
        viol_detail = {
            **viol,
            "oregon_n_violating_valid_cells": n_cell_viol,
            "oregon_pct_violating_valid_cells": 100.0 * n_cell_viol / max(n_valid, 1),
            "meets_configured_budget": bool(viol["meets_configured_budget"]) and n_cell_viol == 0,
        }
        if n_cell_viol > 0:
            vae = ae[cell_viol]
            viol_detail["max_error_among_violating_cells"] = float(np.max(vae))
            viol_detail["p95_error_among_violating_cells"] = float(np.percentile(vae, 95))
            viol_detail["p99_error_among_violating_cells"] = float(np.percentile(vae, 99))
            bright = cell_viol & (arr < 20.5)
            viol_detail["pct_violating_cells_in_bright_lt_20.5"] = 100.0 * float(np.sum(bright)) / n_cell_viol
            viol_detail["violation_concentration"] = (
                "bright_cores" if np.sum(bright) > 0.5 * n_cell_viol else "boundaries_or_mixed"
            )
            # band disagreement in violating cells
            disagree = 0
            for ov, rv in zip(arr[cell_viol], recon[cell_viol]):
                if assign_product_band(float(ov), bands, nodata) != assign_product_band(float(rv), bands, nodata):
                    disagree += 1
            viol_detail["band_disagreement_in_violating_cells"] = disagree
        else:
            viol_detail["max_error_among_violating_cells"] = None
            viol_detail["violation_concentration"] = None

        # Global size: placeholder until census; use intersecting roots only note
        gsz = {
            "kind": "hierarchical_awaiting_or_from_census",
            "reliability": "see_world_hierarchical_census",
            "oregon_intersecting_roots_blob_bytes": hres["sum_blob_bytes"],
            "total_bytes": hres["sum_blob_bytes"],  # temporary for sorting; census overwrites report
            "note": "Oregon metrics from full global roots cropped to Oregon. Global MiB from census.",
        }
        # Try load census if present
        census_path = OUTPUT / "world_hierarchical_census.json"
        if census_path.is_file():
            cen = _load_json(census_path)
            vk = f"{storage}_budget{budget}_{policy}_cap{cap_label}"
            if vk in cen.get("variants", {}):
                v = cen["variants"][vk]
                gsz = {
                    "kind": "hierarchical_census_shared_builder",
                    "reliability": "census_derived",
                    "total_bytes": v["total_bytes"],
                    "payload_bytes": v["sum_blob_bytes"],
                    "total_mib": v["total_mib"],
                    "type_counts": v.get("type_counts"),
                    "meets_configured_budget_global_leaves": v.get("meets_configured_budget"),
                    "pct_violating_leaves_global": v.get("pct_violating_leaves"),
                }

        extra = {
            "hierarchical": True,
            "policy": policy,
            "finest_cells": finest,
            "cap_deg": cap_label,
            "storage": storage,
            "budget": budget,
            "type_counts": hres["tree_type_counts_merged"],
            "budget_violations": viol_detail,
            "roots": hres["roots"],
            "overlay_leaves": hres["overlay_leaves"],
            "meets_configured_budget": viol_detail["meets_configured_budget"],
        }
        write_json(cand_dir / f"{cid}_stats.json", extra)
        write_json(cand_dir / f"{cid}_overlay.json", {"leaves": hres["overlay_leaves"]})
        register(
            cid,
            "hierarchical_adaptive",
            recon,
            int(hres["sum_blob_bytes"]),
            gsz,
            extra=extra,
            error_kind="hierarchical_reconstruction",
        )
        if not viol_detail["meets_configured_budget"]:
            print(f"    BUDGET VIOLATIONS: leaves%={viol_detail.get('pct_violating_leaves')} "
                  f"cells%={viol_detail.get('oregon_pct_violating_valid_cells')} "
                  f"max={viol_detail.get('max_error_among_violating_cells')}")


    default_recon = np.full_like(arr, pristine_default)
    write_json(
        out_root / "pristine_default_error_if_applied_everywhere.json",
        {
            "pristine_default": pristine_default,
            "metrics_vs_all_oregon": compute_error_metrics(arr, default_recon, nodata),
        },
    )

    # Leaders: multi-criteria shortlist
    def global_mib(c: dict) -> float:
        s = c.get("global_size_summary") or {}
        m = s.get("global_total_mib")
        if m is not None:
            return float(m)
        g = c["global_size"]
        b = g.get("total_bytes") or g.get("naive_scaled_global_bytes") or 0
        return bytes_to_mib(b)

    # Prefer production-relevant families for leader table
    preferred = [
        c for c in candidates
        if c["id"].startswith("spatial_") and "linear_avg" in c["id"]
        or c["family"] in ("adaptive", "sparse", "quantization", "spatial+quantization", "hierarchical_adaptive")
    ]
    by_mae = sorted(preferred, key=lambda c: c["metrics"].get("mae") or 1e9)
    by_size = sorted(preferred, key=global_mib)
    leaders = []
    seen = set()
    for c in by_mae[:8] + by_size[:8]:
        if c["id"] in seen:
            continue
        seen.add(c["id"])
        leaders.append({
            "id": c["id"],
            "mae": c["metrics"].get("mae"),
            "p95_ae": c["metrics"].get("p95_ae"),
            "p99_ae": c["metrics"].get("p99_ae"),
            "max_ae": c["metrics"].get("max_ae"),
            "oregon_bytes": c["oregon_bytes"],
            "oregon_mib": c.get("oregon_mib"),
            "global_mib": global_mib(c),
            "global_bytes": (c.get("global_size_summary") or {}).get("global_total_bytes")
                or c["global_size"].get("total_bytes")
                or c["global_size"].get("naive_scaled_global_bytes"),
            "global_reliability": (c.get("global_size_summary") or {}).get("reliability")
                or c["global_size"].get("reliability"),
            "output_width": c["global_size"].get("output_width"),
            "output_height": c["global_size"].get("output_height"),
            "notes": c["family"],
            "worst_error_lonlat": (
                (c["top_errors"][0]["lon"], c["top_errors"][0]["lat"])
                if c.get("top_errors") else None
            ),
        })

    # Explicit comparison picks
    def find(cid: str):
        return next((c for c in candidates if c["id"] == cid), None)

    picks = {
        "smallest_by_global_exact_or_oregon": min(
            candidates,
            key=lambda c: global_mib(c),
        )["id"],
        "best_uniform_u8": None,
        "best_adaptive_u8": None,
        "uniform_0.05_u8": "spatial_0.05_linear_avg_u8",
        "uniform_0.1_u8": "spatial_0.1_linear_avg_u8",
        "best_hierarchical_u8": None,
    }
    uniform_u8 = [c for c in candidates if c["id"].endswith("_linear_avg_u8") and c["id"].startswith("spatial_")]
    if uniform_u8:
        # score: mae + size weight
        picks["best_uniform_u8"] = min(
            uniform_u8,
            key=lambda c: (c["metrics"].get("mae") or 1) * (1 + global_mib(c) / 100),
        )["id"]
    adapt_u8 = [c for c in candidates if c["id"].startswith("adaptive_uint8_")]
    hier_u8 = [c for c in candidates if c["id"].startswith("hierarchical_adaptive_uint8_")]
    if hier_u8:
        picks["best_hierarchical_u8"] = min(
            hier_u8,
            key=lambda c: (
                0 if (c.get("extra") or {}).get("meets_configured_budget") else 1,
                c["metrics"].get("max_ae") or 1,
                c["metrics"].get("mae") or 1,
                global_mib(c),
            ),
        )["id"]
    if adapt_u8:
        picks["best_adaptive_u8"] = min(
            adapt_u8,
            key=lambda c: (c["metrics"].get("max_ae") or 1, c["metrics"].get("mae") or 1, global_mib(c)),
        )["id"]

    u05 = find("spatial_0.05_linear_avg_u8")
    comparison_vs_0_05_u8 = []
    if u05:
        base_mib = global_mib(u05)
        for c in candidates:
            if c["family"] == "adaptive" or "u8" in c["id"]:
                comparison_vs_0_05_u8.append({
                    "id": c["id"],
                    "global_mib": global_mib(c),
                    "beats_0.05_u8_size": global_mib(c) < base_mib,
                    "mae": c["metrics"].get("mae"),
                    "max_ae": c["metrics"].get("max_ae"),
                    "reliability": (c.get("global_size_summary") or {}).get("reliability"),
                })

    summary = {
        "generated_at": provenance["generated_at"],
        "provenance": provenance,
        "oregon_cells": oregon_cells,
        "oregon_shape": list(arr.shape),
        "global_source_dims": {"width": GLOBAL_WIDTH, "height": GLOBAL_HEIGHT},
        "value_range": {"min": vmin, "max": vmax},
        "candidates": candidates,
        "leaders": leaders,
        "picks": picks,
        "comparison_vs_0_05_u8": comparison_vs_0_05_u8,
        "points": point_rows,
        "top_errors": top_errors_all,
        "elapsed_sec": time.time() - t0,
    }
    write_json(out_root / "summary.json", summary)
    write_markdown_summary(out_root / "summary.md", summary)
    write_json(out_root / "points.json", point_rows)
    write_json(out_root / "top_errors.json", top_errors_all)

    manifest = {
        "original": "original",
        "vmin": vmin,
        "vmax": vmax,
        "error_emax": 0.3,
        "candidates": [
            {
                "id": c["id"],
                "family": c["family"],
                "mae": c["metrics"].get("mae"),
                "rmse": c["metrics"].get("rmse"),
                "p95_ae": c["metrics"].get("p95_ae"),
                "p99_ae": c["metrics"].get("p99_ae"),
                "max_ae": c["metrics"].get("max_ae"),
                "pct_within_0_05": (c["metrics"].get("pct_within") or {}).get("0.05"),
                "oregon_bytes": c["oregon_bytes"],
                "oregon_mib": c.get("oregon_mib"),
                "global_size": c["global_size"],
                "global_size_summary": c.get("global_size_summary"),
                "top_errors": c.get("top_errors", [])[:20],
            }
            for c in candidates
        ],
        "grid": grid.to_dict(),
        "points": points_cfg["points"],
        "picks": picks,
        "provenance": {
            "source_name": provenance["source_name"],
            "sha256": provenance["source_sha256"],
            "generated_at": provenance["generated_at"],
        },
    }
    write_json(viewer_dir / "manifest.json", manifest)
    write_json(out_root / "manifest.json", manifest)

    print(f"Done in {summary['elapsed_sec']:.1f}s. Summary: {out_root / 'summary.md'}")
    return summary


def run_world_tile_census(
    source: Path,
    tile_cells: int = 60,
    tolerance: float = 0.05,
    pristine_default: float = 22.0,
    out_path: Path | None = None,
) -> dict[str, Any]:
    """Legacy simple sparse census (mode counts only)."""
    require_osgeo()
    from .source import open_dataset
    from .nodata import is_nodata

    ds = open_dataset(source)
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue() or DEFAULT_NODATA
    w, h = ds.RasterXSize, ds.RasterYSize
    counts = {"all_nodata": 0, "default_pristine": 0, "constant": 0, "variable": 0}
    n_tiles = 0
    print(f"World tile census {w}x{h}, tile={tile_cells}, tol={tolerance}")
    for r0 in range(0, h, tile_cells):
        rows = min(tile_cells, h - r0)
        strip = band.ReadAsArray(0, r0, w, rows)
        for c0 in range(0, w, tile_cells):
            cols = min(tile_cells, w - c0)
            block = strip[:, c0 : c0 + cols]
            n_tiles += 1
            inv = is_nodata(block, float(nodata))
            if not np.any(~inv):
                counts["all_nodata"] += 1
            else:
                vals = block[~inv]
                if np.all(np.abs(vals - pristine_default) <= tolerance):
                    counts["default_pristine"] += 1
                elif float(vals.max() - vals.min()) <= tolerance:
                    counts["constant"] += 1
                else:
                    counts["variable"] += 1
        if (r0 // tile_cells) % 50 == 0:
            print(f"  census row {r0}/{h} tiles so far {n_tiles}")
    result = {
        "n_tiles": n_tiles,
        "tile_cells": tile_cells,
        "counts": counts,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    out_path = out_path or (OUTPUT / "world_tile_census.json")
    write_json(out_path, result)
    print("Census written to", out_path)
    return result


def run_world_adaptive_quant_census(
    source: Path,
    budgets: list[float] | None = None,
    skip_minmax: bool = False,
) -> dict[str, Any]:
    """Streaming census for quantized adaptive format (UInt8/UInt16)."""
    out_dir = OUTPUT / "oregon"
    out_dir.mkdir(parents=True, exist_ok=True)
    if skip_minmax:
        u8 = UInt8Params(m_min=13.01, m_max=22.5)
    else:
        mm = run_global_minmax(source, out_dir) if not (out_dir / "global_minmax.json").exists() else _load_json(out_dir / "global_minmax.json")
        gmin, gmax = float(mm["min"]), float(mm["max"])
        u8 = UInt8Params(
            m_min=float(min(16.0, np.floor(gmin * 100) / 100 - 0.05)),
            m_max=float(max(22.5, np.ceil(gmax * 100) / 100 + 0.05)),
        )
    u16 = UInt16Params()
    quant_cfg = _load_json(CONFIG / "quantization.json")
    return census_adaptive_quantized(
        source,
        budgets=budgets or [0.05, 0.10, 0.20],
        storages=["uint8", "uint16"],
        tile_cells=60,
        pristine_default=float(quant_cfg.get("pristine_default_mag", 22.0)),
        u8=u8,
        u16=u16,
        out_path=OUTPUT / "world_adaptive_quant_census.json",
    )
