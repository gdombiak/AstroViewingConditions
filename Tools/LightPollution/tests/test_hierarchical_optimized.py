"""Equivalence: optimized multi-variant path vs reference build_tree_for_block."""

import numpy as np

from light_pollution.hierarchical import HierarchicalConfig, build_tree_for_block, tree_stats
from light_pollution.hierarchical_optimized import (
    analyze_root_multi_variant,
    build_root_tree_optimized,
    precompute_node,
    select_from_analysis,
    topology_signature,
    trees_equivalent,
)
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params, UInt16Params

BANDS = [
    {"id": "very_bright", "min_mag": None, "max_mag": 18.5},
    {"id": "bright", "min_mag": 18.5, "max_mag": 19.5},
    {"id": "transitional", "min_mag": 19.5, "max_mag": 20.5},
    {"id": "rural", "min_mag": 20.5, "max_mag": 21.3},
    {"id": "dark", "min_mag": 21.3, "max_mag": 21.75},
    {"id": "very_dark", "min_mag": 21.75, "max_mag": None},
]


def _cfg(a, **kw):
    return HierarchicalConfig(
        root_cells=a.shape[0],
        finest_cells=kw.get("finest_cells", 3),
        error_budget=kw.get("budget", 0.1),
        policy=kw.get("policy", "error"),
        storage=kw.get("storage", "uint8"),
        u8=UInt8Params(m_min=16.0, m_max=22.5),
        u16=UInt16Params(),
        nodata=DEFAULT_NODATA,
        pristine_default=22.0,
        product_bands=kw.get("bands", BANDS),
    )


def _eq(a, **kw):
    cfg = _cfg(a, **kw)
    ref = build_tree_for_block(a, 0, 0, cfg)
    opt = build_root_tree_optimized(a, cfg)
    assert trees_equivalent(ref, opt), (topology_signature(ref), topology_signature(opt))
    assert tree_stats(ref)["type_counts"] == tree_stats(opt)["type_counts"]
    assert tree_stats(ref)["ser_bytes"] == tree_stats(opt)["ser_bytes"]
    assert tree_stats(ref)["budget_violating_leaves"] == tree_stats(opt)["budget_violating_leaves"]


def test_eq_uniform_dark():
    a = np.full((24, 24), 22.0, dtype=np.float32)
    _eq(a, budget=0.05)
    _eq(a, budget=0.2, finest_cells=6)


def test_eq_bright_core():
    a = np.full((48, 48), 22.0, dtype=np.float32)
    a[4:12, 4:12] = 18.0
    for b in (0.05, 0.10, 0.20):
        for pol in ("error", "product"):
            for fin in (3, 6):
                _eq(a, budget=b, policy=pol, finest_cells=fin)


def test_eq_mixed_nodata():
    a = np.full((24, 24), 21.0, dtype=np.float32)
    a[0:3, 0:3] = DEFAULT_NODATA
    _eq(a, budget=0.05)


def test_eq_uint16():
    a = np.full((24, 24), 21.5, dtype=np.float32)
    a[0:6, 0:6] = 19.0
    _eq(a, storage="uint16", budget=0.1)


def test_multi_variant_matches_independent():
    a = np.full((24, 24), 22.0, dtype=np.float32)
    a[2:8, 2:8] = 18.5
    variants = [
        {"key": "a", "storage": "uint8", "budget": 0.05, "policy": "error", "finest_cells": 3},
        {"key": "b", "storage": "uint8", "budget": 0.2, "policy": "product", "finest_cells": 6},
    ]
    multi = analyze_root_multi_variant(
        a, variants, DEFAULT_NODATA, 22.0,
        UInt8Params(m_min=16, m_max=22.5), UInt16Params(), BANDS,
    )
    for v in variants:
        cfg = _cfg(a, storage=v["storage"], budget=v["budget"], policy=v["policy"], finest_cells=v["finest_cells"])
        ref = build_tree_for_block(a, 0, 0, cfg)
        assert multi[v["key"]]["ser_bytes"] == ref.ser_bytes
        assert multi[v["key"]]["type_counts"] == tree_stats(ref)["type_counts"]
