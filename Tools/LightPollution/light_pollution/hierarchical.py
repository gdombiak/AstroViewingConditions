"""Hierarchical adaptive encoding (quadtree) — separate from fixed-tile adaptive.

Shared tree builder used by Oregon full-root evaluation and world census.
Selects lowest-byte feasible representation per node (not first-pass ordering).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

import numpy as np

from .brightness import block_reduce_vectorized_linear, linear_to_mag, mag_to_linear
from .hierarchical_serialize import (
    SerConfig,
    cost_all_nodata,
    cost_children_tag,
    cost_coarse_grid,
    cost_default_or_constant,
    bpc,
)
from .masks import pack_nodata_mask, unpack_nodata_mask
from .metrics import assign_product_band
from .nodata import DEFAULT_NODATA, is_nodata, valid_mask
from .quantize import (
    UInt8Params,
    UInt16Params,
    dequantize_uint8,
    dequantize_uint16,
    quantize_uint8,
    quantize_uint16,
)
from .reconstruct import reconstruct_uniform_integer_factor

Storage = Literal["uint8", "uint16"]
Policy = Literal["error", "product"]

# Source atlas
GLOBAL_WIDTH = 43200
GLOBAL_HEIGHT = 16801
ROOT_CELLS = 768
SOURCE_PIXEL_DEG = 1.0 / 120.0


@dataclass
class HierarchicalConfig:
    root_cells: int = ROOT_CELLS
    finest_cells: int = 3  # 0.025°
    error_budget: float = 0.05
    policy: Policy = "error"
    storage: Storage = "uint8"
    pristine_default: float = 22.0
    nodata: float = DEFAULT_NODATA
    u8: UInt8Params = field(default_factory=UInt8Params)
    u16: UInt16Params = field(default_factory=UInt16Params)
    band_disagree_frac: float = 0.05
    dilution_range_mag: float = 0.5
    product_bands: list[dict[str, Any]] = field(default_factory=list)
    ser: SerConfig = field(default_factory=SerConfig)
    # permitted coarse grid cell sizes (source cells per coarse pixel) that divide node
    # factors relative to source: node_side must be divisible by factor for clean grid
    # we use factor = coarse_cell_size when node is multiple of coarse_cell_size


def n_root_cols(root_cells: int = ROOT_CELLS) -> int:
    return (GLOBAL_WIDTH + root_cells - 1) // root_cells


def n_root_rows(root_cells: int = ROOT_CELLS) -> int:
    return (GLOBAL_HEIGHT + root_cells - 1) // root_cells


def root_index_for_cell(col: int, row: int, root_cells: int = ROOT_CELLS) -> tuple[int, int]:
    return col // root_cells, row // root_cells


def roots_intersecting_window(
    xoff: int, yoff: int, xsize: int, ysize: int, root_cells: int = ROOT_CELLS
) -> list[tuple[int, int]]:
    """Return (root_i, root_j) pairs intersecting the source window."""
    c0, c1 = xoff, xoff + xsize - 1
    r0, r1 = yoff, yoff + ysize - 1
    i0, j0 = root_index_for_cell(c0, r0, root_cells)
    i1, j1 = root_index_for_cell(c1, r1, root_cells)
    out = []
    for j in range(j0, j1 + 1):
        for i in range(i0, i1 + 1):
            out.append((i, j))
    return out


def materialize_logical_root(
    band,
    root_i: int,
    root_j: int,
    root_cells: int = ROOT_CELLS,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    """Read real overlap; pad exterior to root_cells x root_cells with NoData."""
    x0 = root_i * root_cells
    y0 = root_j * root_cells
    x1 = min(x0 + root_cells, GLOBAL_WIDTH)
    y1 = min(y0 + root_cells, GLOBAL_HEIGHT)
    out = np.full((root_cells, root_cells), nodata, dtype=np.float32)
    if x0 >= GLOBAL_WIDTH or y0 >= GLOBAL_HEIGHT:
        return out
    w = x1 - x0
    h = y1 - y0
    if w <= 0 or h <= 0:
        return out
    arr = band.ReadAsArray(x0, y0, w, h)
    out[:h, :w] = arr.astype(np.float32)
    return out


def materialize_logical_root_from_array(
    full: np.ndarray,
    x0_global: int,
    y0_global: int,
    root_i: int,
    root_j: int,
    root_cells: int = ROOT_CELLS,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    """Build logical root from a larger array that is a global window starting at x0_global,y0_global."""
    rx0 = root_i * root_cells
    ry0 = root_j * root_cells
    out = np.full((root_cells, root_cells), nodata, dtype=np.float32)
    # intersection of root with available full window
    # full covers [x0_global, x0_global+W) x [y0_global, y0_global+H)
    H, W = full.shape
    # global coords of full
    for local_r in range(root_cells):
        gr = ry0 + local_r
        if gr < y0_global or gr >= y0_global + H or gr >= GLOBAL_HEIGHT:
            continue
        fr = gr - y0_global
        for local_c in range(root_cells):
            gc = rx0 + local_c
            if gc < x0_global or gc >= x0_global + W or gc >= GLOBAL_WIDTH:
                continue
            fc = gc - x0_global
            out[local_r, local_c] = full[fr, fc]
    return out


def _quantize_arr(arr: np.ndarray, cfg: HierarchicalConfig) -> np.ndarray:
    if cfg.storage == "uint8":
        codes, _ = quantize_uint8(arr, cfg.u8, cfg.nodata)
        return dequantize_uint8(codes, cfg.u8, cfg.nodata)
    codes, _ = quantize_uint16(arr, cfg.u16, cfg.nodata)
    return dequantize_uint16(codes, cfg.u16, cfg.nodata)


def _quantize_scalar(v: float, cfg: HierarchicalConfig) -> float:
    return float(_quantize_arr(np.array([[v]], dtype=np.float32), cfg)[0, 0])


def _max_ae_real(original: np.ndarray, recon: np.ndarray, nodata: float) -> float:
    """Max AE on cells that are valid in original (real domain data)."""
    o_nd = is_nodata(original, nodata)
    # only score where original has valid data
    both = ~o_nd & ~is_nodata(recon, nodata)
    if not np.any(~o_nd):
        # all nodata original — require recon also nodata
        if np.all(is_nodata(recon, nodata)):
            return 0.0
        return float("inf")
    # NoData disagreement on originally valid or originally invalid
    if np.any(o_nd != is_nodata(recon, nodata)):
        # allow recon nodata only where original nodata
        if np.any(~o_nd & is_nodata(recon, nodata)):
            return float("inf")
        if np.any(o_nd & ~is_nodata(recon, nodata)):
            return float("inf")
    if not np.any(both):
        return 0.0
    return float(np.max(np.abs(recon[both] - original[both])))


def _product_triggers(
    original: np.ndarray,
    recon: np.ndarray,
    cfg: HierarchicalConfig,
) -> bool:
    """Return True if product-aware policy requires refinement (reject leaf)."""
    if cfg.policy != "product" or not cfg.product_bands:
        return False
    o_nd = is_nodata(original, cfg.nodata)
    if not np.any(~o_nd):
        return False
    vals = original[~o_nd]
    # band span of original
    bands_o = [assign_product_band(float(v), cfg.product_bands, cfg.nodata) for v in vals]
    unique = set(bands_o)
    if len(unique) >= 3:  # spans multiple categories aggressively
        return True
    # disagreement rate recon vs original bands
    rvals = recon[~o_nd]
    disagree = 0
    for ov, rv in zip(vals, rvals):
        if assign_product_band(float(ov), cfg.product_bands, cfg.nodata) != assign_product_band(
            float(rv), cfg.product_bands, cfg.nodata
        ):
            disagree += 1
    if disagree / max(len(vals), 1) >= cfg.band_disagree_frac:
        return True
    # dilution: large range and bright min
    vmin, vmax = float(vals.min()), float(vals.max())
    if (vmax - vmin) >= cfg.dilution_range_mag:
        # if coarse recon much darker than min (bright features lost)
        rmin = float(rvals.min()) if rvals.size else vmax
        if vmin < 20.5 and (rmin - vmin) > 0.3:  # bright core diluted
            return True
    return False


def _reduce_node(block: np.ndarray, factor: int, nodata: float) -> tuple[np.ndarray, np.ndarray]:
    """Return (coarse, recon_to_block_shape)."""
    h, w = block.shape
    # only if divisible
    if h % factor != 0 or w % factor != 0:
        # pad to multiple
        ph = (factor - h % factor) % factor
        pw = (factor - w % factor) % factor
        padded = np.full((h + ph, w + pw), nodata, dtype=np.float32)
        padded[:h, :w] = block
    else:
        padded = block
        ph = pw = 0
    coarse = block_reduce_vectorized_linear(padded, factor, factor, nodata)
    recon = reconstruct_uniform_integer_factor(coarse, factor, padded.shape, nodata)
    return coarse, recon[:h, :w]


def _permitted_factors(node_side: int, finest: int) -> list[int]:
    """Coarse factors (source cells per coarse pixel) for this node."""
    # factors that divide node_side and are >= finest and in {3,6,12,24,...} up to node_side
    out = []
    f = finest
    while f <= node_side:
        if node_side % f == 0:
            out.append(f)
        f *= 2
    return out


@dataclass
class TreeNode:
    type: str
    r0: int
    c0: int
    h: int
    w: int
    # optional fields
    value: float | None = None
    grid: np.ndarray | None = None
    grid_factor: int | None = None
    mask_packed: bytes | None = None
    children: list["TreeNode"] | None = None
    ser_bytes: int = 0
    max_ae: float | None = None
    budget_violation: bool = False


def build_tree_for_block(
    block: np.ndarray,
    r0: int,
    c0: int,
    cfg: HierarchicalConfig,
) -> TreeNode:
    """Recursively build min-byte tree for a logical block (already extracted)."""
    h, w = block.shape
    assert h == w or True  # allow rectangular at edge of recursion if any
    n_cells = h * w
    inv = is_nodata(block, cfg.nodata)
    n_valid = int(np.sum(~inv))
    n_real_valid = n_valid  # padding is nodata

    # --- all nodata ---
    if n_valid == 0:
        return TreeNode(
            type="all_nodata", r0=r0, c0=c0, h=h, w=w,
            ser_bytes=cost_all_nodata(cfg.ser), max_ae=0.0, budget_violation=False,
        )

    options: list[tuple[int, TreeNode]] = []

    # default
    def_recon = np.where(inv, cfg.nodata, cfg.pristine_default).astype(np.float32)
    def_q = np.where(inv, cfg.nodata, _quantize_arr(def_recon, cfg))
    mae = _max_ae_real(block, def_q, cfg.nodata)
    mixed = bool(np.any(inv))
    cost = cost_default_or_constant(cfg.ser, cfg.storage, mixed, n_cells)
    if mae <= cfg.error_budget and not _product_triggers(block, def_q, cfg):
        mask = pack_nodata_mask(inv) if mixed else None
        options.append((cost, TreeNode(
            type="default_pristine", r0=r0, c0=c0, h=h, w=w,
            value=cfg.pristine_default, mask_packed=mask, ser_bytes=cost, max_ae=mae,
        )))

    # constant midpoint
    vals = block[~inv]
    mid = float(0.5 * (float(vals.min()) + float(vals.max())))
    mid_q = _quantize_scalar(mid, cfg)
    c_recon = np.where(inv, cfg.nodata, mid_q).astype(np.float32)
    mae = _max_ae_real(block, c_recon, cfg.nodata)
    cost = cost_default_or_constant(cfg.ser, cfg.storage, mixed, n_cells)
    if mae <= cfg.error_budget and not _product_triggers(block, c_recon, cfg):
        mask = pack_nodata_mask(inv) if mixed else None
        options.append((cost, TreeNode(
            type="constant", r0=r0, c0=c0, h=h, w=w,
            value=mid_q, mask_packed=mask, ser_bytes=cost, max_ae=mae,
        )))

    # coarse grids: try coarsest first; finer grids have more cells (higher cost)
    side = min(h, w)
    factors = [f for f in _permitted_factors(side, cfg.finest_cells) if f > 1 and not (f >= side and side > cfg.finest_cells)]
    factors.sort(reverse=True)  # coarsest (largest factor) first
    for factor in factors:
        coarse, recon = _reduce_node(block, factor, cfg.nodata)
        recon_q = _quantize_arr(recon, cfg)
        recon_q = np.where(inv, cfg.nodata, recon_q)
        mae = _max_ae_real(block, recon_q, cfg.nodata)
        gh, gw = coarse.shape
        cost = cost_coarse_grid(cfg.ser, cfg.storage, gh * gw)
        if mae <= cfg.error_budget and not _product_triggers(block, recon_q, cfg):
            coarse_q = _quantize_arr(coarse, cfg)
            mask = pack_nodata_mask(inv) if mixed else None
            c2 = cost + (len(mask) if mask else 0)
            options.append((c2, TreeNode(
                type="coarse_grid", r0=r0, c0=c0, h=h, w=w,
                grid=coarse_q, grid_factor=factor, mask_packed=mask, ser_bytes=c2, max_ae=mae,
            )))
            break  # finer grids cost more cells; coarser feasible grid is enough for min-byte among grids

    # children — only if needed for min-byte or no leaf options
    can_split = min(h, w) > cfg.finest_cells and h >= 2 and w >= 2
    min_child_lower = cost_children_tag(cfg.ser) + 4 * cost_all_nodata(cfg.ser)
    cheapest_leaf = min((c for c, _ in options), default=None)
    # If a feasible leaf is already cheaper than any possible 4-child tree lower bound
    # with non-trivial children, still may need children when leaves are masked-expensive.
    # Safe skip: cheapest feasible leaf <= tag+4*all_nodata only works if children could be all_nodata —
    # not true for valid data. Lower bound for valid data: tag + 4*(tag+bpc) = 1+4*(1+bpc).
    b = 1 if cfg.storage == "uint8" else 2
    min_child_valid_lb = cost_children_tag(cfg.ser) + 4 * (cfg.ser.node_tag_bytes + b)
    skip_children = (
        cheapest_leaf is not None
        and cheapest_leaf <= min_child_valid_lb
        and not mixed
    )
    if can_split and not skip_children:
        mh, mw = h // 2, w // 2
        # four quadrants (handle odd by giving remainder to bottom/right)
        quads = [
            (0, 0, mh, mw),
            (0, mw, mh, w - mw),
            (mh, 0, h - mh, mw),
            (mh, mw, h - mh, w - mw),
        ]
        children = []
        child_bytes = cost_children_tag(cfg.ser)
        child_max_ae = 0.0
        child_viol = False
        for qr, qc, qh, qw in quads:
            if qh <= 0 or qw <= 0:
                continue
            sub = block[qr : qr + qh, qc : qc + qw]
            ch = build_tree_for_block(sub, r0 + qr, c0 + qc, cfg)
            children.append(ch)
            child_bytes += ch.ser_bytes
            if ch.max_ae is not None:
                child_max_ae = max(child_max_ae, ch.max_ae)
            if ch.budget_violation:
                child_viol = True
        # children always "feasible" as structural option; error is composition of children
        options.append((child_bytes, TreeNode(
            type="children", r0=r0, c0=c0, h=h, w=w,
            children=children, ser_bytes=child_bytes, max_ae=child_max_ae,
            budget_violation=child_viol,
        )))

    if options:
        options.sort(key=lambda x: (x[0], _type_rank(x[1].type)))
        best = options[0][1]
        return best

    # Nothing met budget at finest: emit best-effort constant and flag violation
    mid = float(0.5 * (float(vals.min()) + float(vals.max())))
    mid_q = _quantize_scalar(mid, cfg)
    c_recon = np.where(inv, cfg.nodata, mid_q).astype(np.float32)
    mae = _max_ae_real(block, c_recon, cfg.nodata)
    cost = cost_default_or_constant(cfg.ser, cfg.storage, mixed, n_cells)
    mask = pack_nodata_mask(inv) if mixed else None
    return TreeNode(
        type="constant", r0=r0, c0=c0, h=h, w=w,
        value=mid_q, mask_packed=mask, ser_bytes=cost, max_ae=mae,
        budget_violation=True,
    )


def _type_rank(t: str) -> int:
    order = ["all_nodata", "default_pristine", "constant", "coarse_grid", "children"]
    return order.index(t) if t in order else 99


def build_root_tree(logical_root: np.ndarray, cfg: HierarchicalConfig) -> TreeNode:
    assert logical_root.shape[0] == cfg.root_cells and logical_root.shape[1] == cfg.root_cells
    return build_tree_for_block(logical_root, 0, 0, cfg)


def reconstruct_tree(node: TreeNode, shape: tuple[int, int], cfg: HierarchicalConfig) -> np.ndarray:
    """Reconstruct full array covering the root logical shape."""
    out = np.full(shape, cfg.nodata, dtype=np.float32)
    _paint(node, out, cfg)
    return out


def _paint(node: TreeNode, out: np.ndarray, cfg: HierarchicalConfig) -> None:
    r0, c0, h, w = node.r0, node.c0, node.h, node.w
    if node.type == "all_nodata":
        out[r0 : r0 + h, c0 : c0 + w] = cfg.nodata
    elif node.type in ("default_pristine", "constant"):
        val = cfg.pristine_default if node.type == "default_pristine" else float(node.value)
        block = np.full((h, w), val, dtype=np.float32)
        if node.mask_packed is not None:
            inv = unpack_nodata_mask(node.mask_packed, (h, w))
            block[inv] = cfg.nodata
        out[r0 : r0 + h, c0 : c0 + w] = block
    elif node.type == "coarse_grid":
        factor = node.grid_factor or 1
        coarse = node.grid
        recon = reconstruct_uniform_integer_factor(
            coarse, factor, (coarse.shape[0] * factor, coarse.shape[1] * factor), cfg.nodata
        )
        block = recon[:h, :w].copy()
        if node.mask_packed is not None:
            inv = unpack_nodata_mask(node.mask_packed, (h, w))
            block[inv] = cfg.nodata
        out[r0 : r0 + h, c0 : c0 + w] = block
    elif node.type == "children":
        for ch in node.children or []:
            _paint(ch, out, cfg)
    else:
        raise ValueError(node.type)


def tree_stats(node: TreeNode) -> dict[str, Any]:
    counts: dict[str, int] = {}
    level_counts: dict[int, int] = {}
    n_nodes = 0
    n_leaves = 0
    max_depth = 0
    viol_leaves = 0
    viol_max_aes: list[float] = []

    def walk(n: TreeNode, depth: int) -> None:
        nonlocal n_nodes, n_leaves, max_depth, viol_leaves
        n_nodes += 1
        max_depth = max(max_depth, depth)
        counts[n.type] = counts.get(n.type, 0) + 1
        side = min(n.h, n.w)
        level_counts[side] = level_counts.get(side, 0) + 1
        if n.type == "children":
            for ch in n.children or []:
                walk(ch, depth + 1)
        else:
            n_leaves += 1
            if n.budget_violation:
                viol_leaves += 1
                if n.max_ae is not None:
                    viol_max_aes.append(n.max_ae)

    walk(node, 0)
    return {
        "n_nodes": n_nodes,
        "n_leaves": n_leaves,
        "max_depth": max_depth,
        "type_counts": counts,
        "level_side_counts": {str(k): v for k, v in sorted(level_counts.items(), reverse=True)},
        "ser_bytes": node.ser_bytes,
        "budget_violating_leaves": viol_leaves,
        "violating_leaf_max_aes": viol_max_aes,
    }


def collect_leaves(node: TreeNode) -> list[TreeNode]:
    if node.type == "children":
        out = []
        for ch in node.children or []:
            out.extend(collect_leaves(ch))
        return out
    return [node]


def analyze_budget_violations(
    original_root: np.ndarray,
    recon_root: np.ndarray,
    tree: TreeNode,
    cfg: HierarchicalConfig,
) -> dict[str, Any]:
    """Explicit budget-violation report for a root (or mosaic)."""
    leaves = collect_leaves(tree)
    viol_leaves = [L for L in leaves if L.budget_violation]
    o_nd = is_nodata(original_root, cfg.nodata)
    ae = np.abs(recon_root - original_root)
    # cells belonging to violating leaves
    viol_mask = np.zeros(original_root.shape, dtype=bool)
    for L in viol_leaves:
        viol_mask[L.r0 : L.r0 + L.h, L.c0 : L.c0 + L.w] = True
    viol_valid = viol_mask & ~o_nd
    n_valid = int(np.sum(~o_nd))
    n_viol_cells = int(np.sum(viol_valid))
    report: dict[str, Any] = {
        "n_leaves": len(leaves),
        "n_violating_leaves": len(viol_leaves),
        "pct_violating_leaves": 100.0 * len(viol_leaves) / max(len(leaves), 1),
        "n_valid_cells": n_valid,
        "n_violating_valid_cells": n_viol_cells,
        "pct_violating_valid_cells": 100.0 * n_viol_cells / max(n_valid, 1),
        "meets_configured_budget": len(viol_leaves) == 0,
    }
    if n_viol_cells > 0:
        vae = ae[viol_valid]
        report["max_error_among_violating_cells"] = float(np.max(vae))
        report["p95_error_among_violating_cells"] = float(np.percentile(vae, 95))
        report["p99_error_among_violating_cells"] = float(np.percentile(vae, 99))
        # band disagreement in violating cells
        if cfg.product_bands:
            disagree = 0
            for ov, rv in zip(original_root[viol_valid], recon_root[viol_valid]):
                if assign_product_band(float(ov), cfg.product_bands, cfg.nodata) != assign_product_band(
                    float(rv), cfg.product_bands, cfg.nodata
                ):
                    disagree += 1
            report["band_disagreement_in_violating_cells"] = disagree
            report["band_disagreement_pct_in_violating"] = 100.0 * disagree / n_viol_cells
        # concentration heuristic: bright cores (orig < 20.5) vs dark
        bright = viol_valid & (original_root < 20.5)
        report["pct_violating_cells_in_bright_lt_20.5"] = 100.0 * float(np.sum(bright)) / n_viol_cells
        report["violation_concentration"] = (
            "bright_cores" if np.sum(bright) > 0.5 * n_viol_cells else "boundaries_or_mixed"
        )
    else:
        report["max_error_among_violating_cells"] = None
        report["p95_error_among_violating_cells"] = None
        report["p99_error_among_violating_cells"] = None
        report["violation_concentration"] = None
    return report


def leaf_overlay_meta(tree: TreeNode, root_i: int, root_j: int, root_cells: int = ROOT_CELLS) -> list[dict]:
    """Oregon-viewer leaf rectangles in global cell coords."""
    gx0 = root_i * root_cells
    gy0 = root_j * root_cells
    out = []
    for L in collect_leaves(tree):
        out.append({
            "global_c0": gx0 + L.c0,
            "global_r0": gy0 + L.r0,
            "w": L.w,
            "h": L.h,
            "type": L.type,
            "side": min(L.h, L.w),
            "budget_violation": L.budget_violation,
            "max_ae": L.max_ae,
        })
    return out
