import numpy as np

from light_pollution.grid import GeoGrid
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params, dequantize_uint8, quantize_uint8
from light_pollution.reconstruct import reconstruct_uniform_integer_factor
from light_pollution.reduce import reduce_array
from light_pollution.sizes import uniform_global_size_exact


def test_0_1_degree_quantized_generation():
    # synthetic source-aligned grid at 1/120°
    h, w = 120, 120  # divisible by 12
    arr = np.linspace(18.0, 22.0, h * w, dtype=np.float32).reshape(h, w)
    grid = GeoGrid(-125.0, 47.0, 1 / 120, -1 / 120, w, h, DEFAULT_NODATA)
    coarse, cgrid, info = reduce_array(arr, grid, 0.1, "linear_avg")
    assert info["factor"] == 12
    assert coarse.shape == (10, 10)
    u8 = UInt8Params(m_min=16.0, m_max=22.5)
    codes, meta = quantize_uint8(coarse, u8, DEFAULT_NODATA)
    deq = dequantize_uint8(codes, u8, DEFAULT_NODATA)
    recon = reconstruct_uniform_integer_factor(deq, 12, arr.shape, DEFAULT_NODATA)
    assert recon.shape == arr.shape
    assert codes.dtype == np.uint8
    assert meta["clip_total"] == 0
    gsz = uniform_global_size_exact(12, 1)
    assert gsz["output_width"] == 3600
    assert gsz["payload_bytes"] == 3600 * 1400
