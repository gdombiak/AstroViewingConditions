import numpy as np

from light_pollution.hierarchical import HierarchicalConfig, build_tree_for_block, tree_stats
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params


def test_synthetic_multi_root_census_behavior():
    """In-memory multi-block census using same builder."""
    u8 = UInt8Params(m_min=16.0, m_max=22.5)
    blobs = 0
    types = {}
    for bi in range(2):
        for bj in range(2):
            a = np.full((12, 12), 22.0, dtype=np.float32)
            if bi == 0 and bj == 0:
                a[0:3, 0:3] = 18.0
            cfg = HierarchicalConfig(
                root_cells=12, finest_cells=3, error_budget=0.1, storage="uint8", u8=u8,
                nodata=DEFAULT_NODATA, pristine_default=22.0,
            )
            tree = build_tree_for_block(a, 0, 0, cfg)
            st = tree_stats(tree)
            blobs += st["ser_bytes"]
            for k, v in st["type_counts"].items():
                types[k] = types.get(k, 0) + v
    assert blobs > 0
    assert types.get("default_pristine", 0) + types.get("constant", 0) >= 1
    # bright block uses more structure
    assert "children" in types or "coarse_grid" in types or types.get("constant", 0) >= 1
