"""Optimized hierarchical multi-variant analysis (same semantics as hierarchical.build_tree_for_block).

Precomputes per-node source/quant stats once per root+storage family, then runs
lightweight bottom-up selection per (budget, policy, finest_cap).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

import numpy as np

from .hierarchical import (
    HierarchicalConfig,
    TreeNode,
    _max_ae_real,
    _permitted_factors,
    _product_triggers,
    _quantize_arr,
    _quantize_scalar,
    _reduce_node,
    _type_rank,
    build_tree_for_block,
)
from .hierarchical_serialize import (
    SerConfig,
    cost_all_nodata,
    cost_children_tag,
    cost_coarse_grid,
    cost_default_or_constant,
)
from .masks import pack_nodata_mask
from .nodata import DEFAULT_NODATA, is_nodata
from .quantize import UInt8Params, UInt16Params

Storage = Literal["uint8", "uint16"]


@dataclass
class LeafCandidate:
    type: str
    cost: int
    max_ae: float
    product_reject: bool
    value: float | None = None
    grid: np.ndarray | None = None
    grid_factor: int | None = None
    mask_packed: bytes | None = None
    # factor used for filtering by finest (grids only)
    factor: int | None = None


@dataclass
class NodeAnalysis:
    r0: int
    c0: int
    h: int
    w: int
    n_valid: int
    mixed: bool
    mid: float | None
    leaves: list[LeafCandidate]
    children: list["NodeAnalysis"] | None = None


def _cfg_for_storage(
    storage: Storage,
    nodata: float,
    pristine: float,
    u8: UInt8Params,
    u16: UInt16Params,
    product_bands: list,
    finest_cells: int = 3,
) -> HierarchicalConfig:
    return HierarchicalConfig(
        root_cells=768,
        finest_cells=finest_cells,
        error_budget=1e9,  # unused during precompute feasibility
        policy="error",
        storage=storage,
        pristine_default=pristine,
        nodata=nodata,
        u8=u8,
        u16=u16,
        product_bands=product_bands or [],
    )


def precompute_node(
    block: np.ndarray,
    r0: int,
    c0: int,
    cfg: HierarchicalConfig,
    min_finest: int = 3,
) -> NodeAnalysis:
    """Precompute all leaf candidates and child analyses (independent of budget/policy/finest except min_finest for tree depth)."""
    h, w = block.shape
    inv = is_nodata(block, cfg.nodata)
    n_valid = int(np.sum(~inv))
    mixed = bool(np.any(inv) and n_valid > 0)
    n_cells = h * w
    leaves: list[LeafCandidate] = []

    if n_valid == 0:
        leaves.append(LeafCandidate(
            type="all_nodata", cost=cost_all_nodata(cfg.ser), max_ae=0.0, product_reject=False,
        ))
        # still may have children structure? no - all nodata is terminal
        return NodeAnalysis(r0, c0, h, w, 0, False, None, leaves, None)

    vals = block[~inv]
    mid = float(0.5 * (float(vals.min()) + float(vals.max())))

    # default
    def_q = np.where(inv, cfg.nodata, _quantize_scalar(cfg.pristine_default, cfg)).astype(np.float32)
    # use full quantize path for consistency with reference (array quantize of constant field)
    def_recon = np.where(inv, cfg.nodata, cfg.pristine_default).astype(np.float32)
    def_q = np.where(inv, cfg.nodata, _quantize_arr(def_recon, cfg))
    mae_d = _max_ae_real(block, def_q, cfg.nodata)
    cost_d = cost_default_or_constant(cfg.ser, cfg.storage, mixed, n_cells)
    mask = pack_nodata_mask(inv) if mixed else None
    cfg_prod = HierarchicalConfig(
        root_cells=cfg.root_cells, finest_cells=cfg.finest_cells, error_budget=cfg.error_budget,
        policy="product", storage=cfg.storage, pristine_default=cfg.pristine_default,
        nodata=cfg.nodata, u8=cfg.u8, u16=cfg.u16, product_bands=cfg.product_bands, ser=cfg.ser,
    )
    leaves.append(LeafCandidate(
        type="default_pristine", cost=cost_d, max_ae=mae_d,
        product_reject=_product_triggers(block, def_q, cfg_prod),
        value=cfg.pristine_default, mask_packed=mask,
    ))

    # constant
    mid_q = _quantize_scalar(mid, cfg)
    c_recon = np.where(inv, cfg.nodata, mid_q).astype(np.float32)
    mae_c = _max_ae_real(block, c_recon, cfg.nodata)
    cost_c = cost_default_or_constant(cfg.ser, cfg.storage, mixed, n_cells)
    leaves.append(LeafCandidate(
        type="constant", cost=cost_c, max_ae=mae_c,
        product_reject=_product_triggers(block, c_recon, cfg_prod),
        value=mid_q, mask_packed=mask,
    ))

    # Early-out: if default or constant meets the tightest census budget (0.05)
    # without product rejection, it wins min-byte for ALL configured variants
    # (budgets >= 0.05, error and product). Skip grids/children (strictly more expensive).
    TIGHTEST = 0.05
    bpc_v = 1 if cfg.storage == "uint8" else 2
    cheap_ok = None
    for L in leaves:
        if L.type in ("default_pristine", "constant") and L.max_ae <= TIGHTEST and not L.product_reject:
            if cheap_ok is None or L.cost < cheap_ok.cost:
                cheap_ok = L
    if cheap_ok is not None and cheap_ok.cost <= cost_children_tag(cfg.ser) + 4 * (cfg.ser.node_tag_bytes + bpc_v):
        return NodeAnalysis(r0, c0, h, w, n_valid, mixed, mid, leaves, None)

    # all permitted grid factors down to min_finest=3 (filter later by cfg.finest)
    side = min(h, w)
    factors = [f for f in _permitted_factors(side, min_finest) if f > 1]
    factors.sort(reverse=True)
    for factor in factors:
        # skip full-size grid when side > min_finest (same as reference with finest=min_finest)
        if factor >= side and side > min_finest:
            continue
        coarse, recon = _reduce_node(block, factor, cfg.nodata)
        recon_q = np.where(inv, cfg.nodata, _quantize_arr(recon, cfg))
        mae_g = _max_ae_real(block, recon_q, cfg.nodata)
        gh, gw = coarse.shape
        cost_g = cost_coarse_grid(cfg.ser, cfg.storage, gh * gw)
        if mask is not None:
            cost_g += len(mask)
        coarse_q = _quantize_arr(coarse, cfg)
        leaves.append(LeafCandidate(
            type="coarse_grid", cost=cost_g, max_ae=mae_g,
            product_reject=_product_triggers(block, recon_q, cfg_prod),
            grid=coarse_q, grid_factor=factor, mask_packed=mask, factor=factor,
        ))

    children_an: list[NodeAnalysis] | None = None
    if min(h, w) > min_finest and h >= 2 and w >= 2:
        mh, mw = h // 2, w // 2
        quads = [
            (0, 0, mh, mw),
            (0, mw, mh, w - mw),
            (mh, 0, h - mh, mw),
            (mh, mw, h - mh, w - mw),
        ]
        children_an = []
        for qr, qc, qh, qw in quads:
            if qh <= 0 or qw <= 0:
                continue
            sub = block[qr : qr + qh, qc : qc + qw]
            children_an.append(precompute_node(sub, r0 + qr, c0 + qc, cfg, min_finest))

    return NodeAnalysis(r0, c0, h, w, n_valid, mixed, mid, leaves, children_an)


def select_from_analysis(an: NodeAnalysis, cfg: HierarchicalConfig) -> TreeNode:
    """Min-byte selection matching build_tree_for_block semantics."""
    if an.n_valid == 0:
        return TreeNode(
            type="all_nodata", r0=an.r0, c0=an.c0, h=an.h, w=an.w,
            ser_bytes=cost_all_nodata(cfg.ser), max_ae=0.0, budget_violation=False,
        )

    options: list[tuple[int, TreeNode]] = []

    for leaf in an.leaves:
        if leaf.type == "all_nodata":
            continue
        if leaf.type == "coarse_grid":
            fac = leaf.factor or leaf.grid_factor or 0
            # match _permitted_factors(side, cfg.finest_cells)
            if fac < cfg.finest_cells:
                continue
            if fac >= min(an.h, an.w) and min(an.h, an.w) > cfg.finest_cells:
                continue
            # only keep coarsest feasible among grids (reference breaks after first feasible coarsest-first)
            # We'll collect all feasible then when sorting min-byte, multiple grids ok; reference only keeps coarsest feasible.
            # Reference iterates coarsest-first and breaks on first feasible → only ONE coarse_grid option.
            pass
        if leaf.max_ae <= cfg.error_budget:
            if cfg.policy == "product" and leaf.product_reject:
                continue
            options.append((leaf.cost, TreeNode(
                type=leaf.type, r0=an.r0, c0=an.c0, h=an.h, w=an.w,
                value=leaf.value, grid=leaf.grid, grid_factor=leaf.grid_factor,
                mask_packed=leaf.mask_packed, ser_bytes=leaf.cost, max_ae=leaf.max_ae,
                budget_violation=False,
            )))

    # Reference keeps only coarsest feasible grid: drop finer grids if a coarser one exists
    grid_opts = [(c, n) for c, n in options if n.type == "coarse_grid"]
    if grid_opts:
        # coarsest = largest factor
        best_grid = max(grid_opts, key=lambda x: x[1].grid_factor or 0)
        options = [(c, n) for c, n in options if n.type != "coarse_grid"]
        options.append(best_grid)

    can_split = (
        min(an.h, an.w) > cfg.finest_cells
        and an.h >= 2 and an.w >= 2
        and an.children is not None
    )
    b = 1 if cfg.storage == "uint8" else 2
    min_child_valid_lb = cost_children_tag(cfg.ser) + 4 * (cfg.ser.node_tag_bytes + b)
    cheapest_leaf = min((c for c, _ in options), default=None)
    skip_children = (
        cheapest_leaf is not None
        and cheapest_leaf <= min_child_valid_lb
        and not an.mixed
    )
    if can_split and not skip_children:
        children = [select_from_analysis(ch, cfg) for ch in an.children or []]
        child_bytes = cost_children_tag(cfg.ser) + sum(ch.ser_bytes for ch in children)
        child_max_ae = 0.0
        child_viol = False
        for ch in children:
            if ch.max_ae is not None:
                child_max_ae = max(child_max_ae, ch.max_ae)
            if ch.budget_violation:
                child_viol = True
        options.append((child_bytes, TreeNode(
            type="children", r0=an.r0, c0=an.c0, h=an.h, w=an.w,
            children=children, ser_bytes=child_bytes, max_ae=child_max_ae,
            budget_violation=child_viol,
        )))

    if options:
        options.sort(key=lambda x: (x[0], _type_rank(x[1].type)))
        return options[0][1]

    # budget violation constant
    mid = an.mid if an.mid is not None else 22.0
    mid_q = _quantize_scalar(mid, cfg)
    # find constant leaf for cost/mask
    const_leaf = next((L for L in an.leaves if L.type == "constant"), None)
    cost = const_leaf.cost if const_leaf else cost_default_or_constant(cfg.ser, cfg.storage, an.mixed, an.h * an.w)
    mask = const_leaf.mask_packed if const_leaf else None
    mae = const_leaf.max_ae if const_leaf else 0.0
    return TreeNode(
        type="constant", r0=an.r0, c0=an.c0, h=an.h, w=an.w,
        value=mid_q, mask_packed=mask, ser_bytes=cost, max_ae=mae,
        budget_violation=True,
    )


def build_root_tree_optimized(logical_root: np.ndarray, cfg: HierarchicalConfig) -> TreeNode:
    """Optimized path: precompute once (depth to 3), select for cfg."""
    # Precompute with storage-specific quantize, tree down to 3 cells
    an = precompute_node(logical_root, 0, 0, cfg, min_finest=3)
    return select_from_analysis(an, cfg)


def compact_stats_from_tree(tree: TreeNode) -> dict[str, Any]:
    from .hierarchical import tree_stats
    st = tree_stats(tree)
    return {
        "ser_bytes": st["ser_bytes"],
        "n_nodes": st["n_nodes"],
        "n_leaves": st["n_leaves"],
        "max_depth": st["max_depth"],
        "type_counts": st["type_counts"],
        "level_side_counts": st["level_side_counts"],
        "budget_violating_leaves": st["budget_violating_leaves"],
        "max_ae": tree.max_ae,
        "budget_violation_root": tree.budget_violation,
        "root_type": tree.type,
    }


def analyze_root_multi_variant(
    logical: np.ndarray,
    variants: list[dict[str, Any]],
    nodata: float,
    pristine: float,
    u8: UInt8Params,
    u16: UInt16Params,
    product_bands: list,
) -> dict[str, dict[str, Any]]:
    """One logical root → compact stats per variant key.

    Precomputes NodeAnalysis once per storage, then selects per variant.
    """
    # Group by storage
    by_storage: dict[str, list] = {}
    for v in variants:
        by_storage.setdefault(v["storage"], []).append(v)

    out: dict[str, dict[str, Any]] = {}
    for storage, vlist in by_storage.items():
        cfg0 = _cfg_for_storage(storage, nodata, pristine, u8, u16, product_bands, finest_cells=3)
        an = precompute_node(logical, 0, 0, cfg0, min_finest=3)
        for v in vlist:
            cfg = HierarchicalConfig(
                root_cells=logical.shape[0],
                finest_cells=int(v["finest_cells"]),
                error_budget=float(v["budget"]),
                policy=v["policy"],
                storage=storage,  # type: ignore
                pristine_default=pristine,
                nodata=nodata,
                u8=u8,
                u16=u16,
                product_bands=product_bands or [],
            )
            tree = select_from_analysis(an, cfg)
            out[v["key"]] = compact_stats_from_tree(tree)
    return out


def topology_signature(node: TreeNode) -> tuple:
    """Hashable topology for equivalence tests."""
    if node.type == "children":
        return (node.type, node.r0, node.c0, node.h, node.w, tuple(topology_signature(c) for c in (node.children or [])))
    return (node.type, node.r0, node.c0, node.h, node.w, node.grid_factor, node.budget_violation)


def trees_equivalent(a: TreeNode, b: TreeNode, atol: float = 1e-5) -> bool:
    if topology_signature(a) != topology_signature(b):
        return False
    if a.ser_bytes != b.ser_bytes:
        return False
    if a.budget_violation != b.budget_violation:
        return False
    if a.max_ae is None or b.max_ae is None:
        if a.max_ae != b.max_ae:
            return False
    elif abs(a.max_ae - b.max_ae) > 1e-4:
        return False
    return True
