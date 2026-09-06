import numpy as np

from light_pollution.adaptive_tiles import (
    AdaptiveConfig,
    constant_midpoint,
    encode_adaptive,
    select_level_for_block,
)
from light_pollution.metrics import compute_error_metrics
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params, UInt16Params


def test_midpoint_minimax():
    block = np.array([[18.0, 22.0], [18.0, 22.0]], dtype=np.float32)
    recon, mid = constant_midpoint(block, DEFAULT_NODATA)
    assert mid == 20.0
    # max AE is 2.0 for midpoint; mean would also be 20 here
    assert float(np.max(np.abs(recon - block))) == 2.0
    # asymmetric: midpoint better than mean for max error
    block2 = np.array([[10.0, 10.0, 10.0, 20.0]], dtype=np.float32)
    _, mid2 = constant_midpoint(block2, DEFAULT_NODATA)
    assert mid2 == 15.0
    mean = float(np.mean(block2))
    max_mid = max(abs(10 - mid2), abs(20 - mid2))
    max_mean = max(abs(10 - mean), abs(20 - mean))
    assert max_mid <= max_mean


def test_adaptive_max_ae_budget():
    a = np.full((120, 120), 21.9, dtype=np.float32)
    a[10:20, 10:20] = 18.0
    cfg = AdaptiveConfig(tile_source_cells=60, error_budget=0.05, pristine_default=22.0)
    tiles, recon, stats = encode_adaptive(a, cfg)
    m = compute_error_metrics(a, recon)
    assert m["max_ae"] is not None
    assert m["max_ae"] <= cfg.error_budget + 1e-5
    for te in stats["tile_errors"]:
        if te["max_ae"] is not None:
            assert te["max_ae"] <= cfg.error_budget + 1e-5


def test_adaptive_all_nodata_tile():
    a = np.full((60, 60), DEFAULT_NODATA, dtype=np.float32)
    cfg = AdaptiveConfig(tile_source_cells=60, error_budget=0.05)
    tiles, recon, stats = encode_adaptive(a, cfg)
    assert stats["level_counts"]["all_nodata"] == 1
    assert np.all(recon == DEFAULT_NODATA)


def test_adaptive_uint8_uint16_reconstruction():
    a = np.full((60, 60), 21.0, dtype=np.float32)
    a[0:10, 0:10] = 18.5
    u8 = UInt8Params(m_min=16.0, m_max=22.5)
    u16 = UInt16Params(m_min=16.0, step=0.01)
    for storage in ("uint8", "uint16"):
        cfg = AdaptiveConfig(
            tile_source_cells=60,
            error_budget=0.20,
            storage=storage,
            u8=u8,
            u16=u16,
        )
        tiles, recon, stats = encode_adaptive(a, cfg)
        assert stats["storage"] == storage
        assert stats["total_estimated_bytes"] == (
            stats["payload_bytes"] + stats["index_bytes"] + stats["metadata_bytes"]
        )
        m = compute_error_metrics(a, recon)
        assert m["max_ae"] <= cfg.error_budget + 0.05  # allow quant headroom on budget edge
        # byte accounting positive
        assert stats["payload_bytes"] > 0


def test_select_level_prefers_smaller():
    a = np.full((60, 60), 22.0, dtype=np.float32)
    cfg = AdaptiveConfig(tile_source_cells=60, error_budget=0.05, pristine_default=22.0, storage="uint8",
                         u8=UInt8Params(m_min=16.0, m_max=22.5))
    level, nbytes, max_ae = select_level_for_block(a, cfg)
    assert level in ("default_pristine", "constant")
    assert nbytes < 60 * 60  # much smaller than full native uint8
