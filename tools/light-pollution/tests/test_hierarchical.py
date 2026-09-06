import numpy as np

from light_pollution.hierarchical import (
    HierarchicalConfig,
    analyze_budget_violations,
    build_tree_for_block,
    collect_leaves,
    n_root_cols,
    n_root_rows,
    reconstruct_tree,
    root_index_for_cell,
    roots_intersecting_window,
    tree_stats,
)
from light_pollution.hierarchical_serialize import (
    SerConfig,
    cost_all_nodata,
    cost_default_or_constant,
    total_global_bytes,
)
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params


def _cfg(**kw):
    base = dict(
        root_cells=24,
        finest_cells=3,
        error_budget=0.05,
        policy="error",
        storage="uint8",
        u8=UInt8Params(m_min=16.0, m_max=22.5),
        nodata=DEFAULT_NODATA,
        pristine_default=22.0,
    )
    base.update(kw)
    return HierarchicalConfig(**base)


def test_root_index_corners():
    assert root_index_for_cell(0, 0) == (0, 0)
    assert n_root_cols() == 57
    assert n_root_rows() == 22
    # oregon-ish
    roots = roots_intersecting_window(6600, 3360, 1080, 600)
    assert len(roots) >= 1
    assert all(isinstance(t, tuple) and len(t) == 2 for t in roots)


def test_uniform_dark_collapses():
    a = np.full((24, 24), 22.0, dtype=np.float32)
    tree = build_tree_for_block(a, 0, 0, _cfg())
    assert tree.type in ("default_pristine", "constant")
    assert tree.type != "children"
    recon = reconstruct_tree(tree, a.shape, _cfg())
    assert np.allclose(recon, 22.0, atol=0.05)


def test_bright_core_local_refine():
    a = np.full((48, 48), 22.0, dtype=np.float32)
    a[4:10, 4:10] = 18.0
    cfg = _cfg(root_cells=48, finest_cells=3, error_budget=0.1)
    tree = build_tree_for_block(a, 0, 0, cfg)
    leaves = collect_leaves(tree)
    # at least one non-default leaf near bright core
    types = {L.type for L in leaves}
    assert tree.type == "children" or any(L.type != "default_pristine" for L in leaves)
    # sibling dark area should include default leaves
    assert any(L.type in ("default_pristine", "constant") for L in leaves)
    recon = reconstruct_tree(tree, a.shape, cfg)
    # dark corner far from core should stay near 22
    assert abs(float(recon[40, 40]) - 22.0) < 0.1


def test_min_byte_prefers_children_over_fine_grid_sometimes():
    # Mostly dark with small bright: children often smaller than fine grid of whole parent
    a = np.full((24, 24), 22.0, dtype=np.float32)
    a[0:3, 0:3] = 18.0
    cfg = _cfg(error_budget=0.05, finest_cells=3)
    tree = build_tree_for_block(a, 0, 0, cfg)
    # Either children or a viable leaf; ser_bytes should be modest
    assert tree.ser_bytes < 24 * 24  # less than full uint8 dump


def test_budget_violation_explicit_at_finest():
    # Mixed leaf that cannot meet 0.01 budget
    a = np.array([[18.0, 22.0], [18.0, 22.0]], dtype=np.float32)
    # pad to 3x3 finest
    b = np.full((3, 3), 22.0, dtype=np.float32)
    b[0:2, 0:2] = a
    cfg = _cfg(error_budget=0.01, finest_cells=3)
    tree = build_tree_for_block(b, 0, 0, cfg)
    recon = reconstruct_tree(tree, b.shape, cfg)
    viol = analyze_budget_violations(b, recon, tree, cfg)
    # may or may not violate depending on structure; if max ae > budget must flag
    mae = float(np.max(np.abs(recon[b < 1e30] - b[b < 1e30])))
    if mae > 0.01 + 1e-6:
        # tree should record violation on some path
        st = tree_stats(tree)
        assert st["budget_violating_leaves"] >= 1 or not viol["meets_configured_budget"]


def test_product_policy_differs():
    a = np.full((24, 24), 21.0, dtype=np.float32)
    a[0:6, 0:6] = 18.0
    bands = [
        {"id": "very_bright", "min_mag": None, "max_mag": 18.5},
        {"id": "bright", "min_mag": 18.5, "max_mag": 19.5},
        {"id": "transitional", "min_mag": 19.5, "max_mag": 20.5},
        {"id": "rural", "min_mag": 20.5, "max_mag": 21.3},
        {"id": "dark", "min_mag": 21.3, "max_mag": 21.75},
        {"id": "very_dark", "min_mag": 21.75, "max_mag": None},
    ]
    e = build_tree_for_block(a, 0, 0, _cfg(policy="error", error_budget=0.5, product_bands=bands))
    p = build_tree_for_block(a, 0, 0, _cfg(policy="product", error_budget=0.5, product_bands=bands))
    # product may refine more (more nodes) for same loose budget
    assert tree_stats(p)["n_nodes"] >= tree_stats(e)["n_nodes"]


def test_finest_cap_0_05():
    a = np.full((24, 24), 20.0, dtype=np.float32)
    a[0:4, 0:4] = 18.0
    cfg = _cfg(finest_cells=6, error_budget=0.01)
    tree = build_tree_for_block(a, 0, 0, cfg)
    for L in collect_leaves(tree):
        assert min(L.h, L.w) >= 6 or min(L.h, L.w) == min(a.shape)  # no 3-cell leaves


def test_uint8_roundtrip_and_byte_accounting():
    a = np.full((12, 12), 21.5, dtype=np.float32)
    cfg = _cfg(root_cells=12, finest_cells=3)
    tree = build_tree_for_block(a, 0, 0, cfg)
    recon = reconstruct_tree(tree, a.shape, cfg)
    assert recon.shape == a.shape
    assert tree.ser_bytes >= cost_all_nodata(SerConfig())
    # default/constant costs
    assert cost_default_or_constant(SerConfig(), "uint8", False, 12 * 12) == 1 + 1


def test_packed_nodata_mixed():
    a = np.full((12, 12), 21.0, dtype=np.float32)
    a[0:2, 0:2] = DEFAULT_NODATA
    cfg = _cfg(root_cells=12)
    tree = build_tree_for_block(a, 0, 0, cfg)
    recon = reconstruct_tree(tree, a.shape, cfg)
    assert np.all(recon[0:2, 0:2] == DEFAULT_NODATA)


def test_padding_all_nodata_cheap():
    a = np.full((12, 12), DEFAULT_NODATA, dtype=np.float32)
    tree = build_tree_for_block(a, 0, 0, _cfg(root_cells=12))
    assert tree.type == "all_nodata"
    assert tree.ser_bytes == cost_all_nodata(SerConfig())


def test_total_global_bytes_formula():
    tot = total_global_bytes(1000, 1254, SerConfig())
    assert tot["total_bytes"] == 256 + 1254 * 20 + 1000


def test_shared_builder_deterministic():
    a = np.full((24, 24), 21.8, dtype=np.float32)
    a[10:13, 10:13] = 19.0
    cfg = _cfg()
    t1 = build_tree_for_block(a, 0, 0, cfg)
    t2 = build_tree_for_block(a.copy(), 0, 0, cfg)
    assert t1.type == t2.type
    assert t1.ser_bytes == t2.ser_bytes
