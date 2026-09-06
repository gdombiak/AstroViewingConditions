"""Oregon evaluation using full global roots (production encoder semantics)."""

from __future__ import annotations

from typing import Any

import numpy as np

from .hierarchical_optimized import build_root_tree_optimized
from .hierarchical import (
    GLOBAL_HEIGHT,
    GLOBAL_WIDTH,
    HierarchicalConfig,
    ROOT_CELLS,
    analyze_budget_violations,
    build_root_tree,  # reference kept for tests
    leaf_overlay_meta,
    materialize_logical_root,
    n_root_cols,
    n_root_rows,
    reconstruct_tree,
    roots_intersecting_window,
    tree_stats,
)
from .hierarchical_serialize import SerConfig, total_global_bytes
from .nodata import DEFAULT_NODATA
from .source import open_dataset, require_osgeo


def encode_oregon_via_full_roots(
    source_path,
    oregon_xoff: int,
    oregon_yoff: int,
    oregon_xsize: int,
    oregon_ysize: int,
    cfg: HierarchicalConfig,
) -> dict[str, Any]:
    """Encode every global root intersecting Oregon; reconstruct and crop.

    Returns recon Oregon array, trees meta, size estimate for *those roots only*
    (full global size comes from world census).
    """
    require_osgeo()
    ds = open_dataset(source_path)
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue() or DEFAULT_NODATA
    cfg.nodata = float(nodata)

    roots = roots_intersecting_window(
        oregon_xoff, oregon_yoff, oregon_xsize, oregon_ysize, cfg.root_cells
    )
    recon_oregon = np.full((oregon_ysize, oregon_xsize), cfg.nodata, dtype=np.float32)
    # also need original mosaic of roots for violation analysis on oregon window
    # use provided oregon original separately in pipeline

    root_results = []
    sum_blob = 0
    all_leaves_overlay = []
    combined_viol = {
        "n_violating_leaves": 0,
        "n_leaves": 0,
        "n_violating_valid_cells": 0,
        "n_valid_cells": 0,
        "violating_aes": [],
        "bright_viol_cells": 0,
    }

    for root_i, root_j in roots:
        logical = materialize_logical_root(band, root_i, root_j, cfg.root_cells, cfg.nodata)
        tree = build_root_tree_optimized(logical, cfg)
        recon_root = reconstruct_tree(tree, logical.shape, cfg)
        stats = tree_stats(tree)
        viol = analyze_budget_violations(logical, recon_root, tree, cfg)
        sum_blob += tree.ser_bytes
        overlay = leaf_overlay_meta(tree, root_i, root_j, cfg.root_cells)
        all_leaves_overlay.extend(overlay)

        # paste into oregon window (vectorized)
        gx0 = root_i * cfg.root_cells
        gy0 = root_j * cfg.root_cells
        is0 = max(0, oregon_yoff - gy0)
        is1 = min(cfg.root_cells, oregon_yoff + oregon_ysize - gy0, GLOBAL_HEIGHT - gy0)
        js0 = max(0, oregon_xoff - gx0)
        js1 = min(cfg.root_cells, oregon_xoff + oregon_xsize - gx0, GLOBAL_WIDTH - gx0)
        if is1 > is0 and js1 > js0:
            or0 = gy0 + is0 - oregon_yoff
            oc0 = gx0 + js0 - oregon_xoff
            recon_oregon[or0 : or0 + (is1 - is0), oc0 : oc0 + (js1 - js0)] = recon_root[is0:is1, js0:js1]

        combined_viol["n_violating_leaves"] += viol["n_violating_leaves"]
        combined_viol["n_leaves"] += viol["n_leaves"]
        # recompute cell stats only on oregon overlap of this root
        ox0 = max(gx0, oregon_xoff)
        oy0 = max(gy0, oregon_yoff)
        ox1 = min(gx0 + cfg.root_cells, oregon_xoff + oregon_xsize, GLOBAL_WIDTH)
        oy1 = min(gy0 + cfg.root_cells, oregon_yoff + oregon_ysize, GLOBAL_HEIGHT)
        # map to local root and oregon
        # simpler: use recon_oregon vs original later in pipeline for cell-level; here root-level viol leaves
        root_results.append({
            "root_i": root_i,
            "root_j": root_j,
            "ser_bytes": tree.ser_bytes,
            "stats": stats,
            "violations": viol,
        })

    n_roots_global = n_root_cols(cfg.root_cells) * n_root_rows(cfg.root_cells)
    # Oregon-only size is not global; report both oregon_roots_blob and placeholder
    size_local = {
        "kind": "hierarchical_oregon_intersecting_roots",
        "reliability": "exact_for_intersecting_roots_only",
        "n_intersecting_roots": len(roots),
        "intersecting_roots_blob_bytes": sum_blob,
        "note": "Full global size from world-hierarchical-census using same builder.",
    }

    meets = all(r["violations"]["meets_configured_budget"] for r in root_results)
    n_vl = sum(r["violations"]["n_violating_leaves"] for r in root_results)
    n_l = sum(r["violations"]["n_leaves"] for r in root_results)

    return {
        "recon": recon_oregon,
        "roots": roots,
        "root_results": root_results,
        "size_local": size_local,
        "overlay_leaves": all_leaves_overlay,
        "sum_blob_bytes": sum_blob,
        "budget_violations_summary": {
            "meets_configured_budget": meets,
            "n_violating_leaves": n_vl,
            "n_leaves": n_l,
            "pct_violating_leaves": 100.0 * n_vl / max(n_l, 1),
            "per_root": [r["violations"] for r in root_results],
        },
        "tree_type_counts_merged": _merge_type_counts(root_results),
    }


def _merge_type_counts(root_results: list[dict]) -> dict[str, int]:
    m: dict[str, int] = {}
    for r in root_results:
        for k, v in r["stats"]["type_counts"].items():
            m[k] = m.get(k, 0) + v
    return m
