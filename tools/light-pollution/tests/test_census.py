import numpy as np

from light_pollution.census import census_on_array
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params


def test_census_on_synthetic_raster():
    # mostly pristine with one bright corner tile
    a = np.full((32, 32), 22.0, dtype=np.float32)
    a[0:8, 0:8] = 18.0
    out = census_on_array(
        a,
        budgets=[0.05, 0.20],
        storage="uint8",
        tile_cells=8,
        pristine_default=22.0,
        nodata=DEFAULT_NODATA,
        u8=UInt8Params(m_min=16.0, m_max=22.5),
        source_pixel_deg=1 / 120,
    )
    assert "0.05" in out and "0.2" in out or "0.20" in out
    # key may be str(0.20) == "0.2"
    key05 = "0.05"
    slot = out[key05]
    assert slot["n_tiles"] == 16
    assert sum(slot["level_counts"].values()) == 16
    # most tiles default/constant at 22
    easy = slot["level_counts"].get("default_pristine", 0) + slot["level_counts"].get("constant", 0)
    assert easy >= 12
    assert slot["payload_bytes"] > 0
    assert slot["total_bytes"] > slot["payload_bytes"]
