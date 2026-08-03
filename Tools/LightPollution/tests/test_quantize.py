import numpy as np
import pytest

from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import (
    UInt8Params,
    UInt16Params,
    dequantize_uint8,
    dequantize_uint16,
    quantize_uint8,
    quantize_uint16,
)


def test_uint16_roundtrip_error_bound():
    params = UInt16Params(m_min=16.0, step=0.01)
    a = np.array([17.123, 20.0, 21.999, DEFAULT_NODATA], dtype=np.float32)
    codes, meta = quantize_uint16(a, params)
    recon = dequantize_uint16(codes, params)
    assert codes[-1] == params.nodata_code
    assert recon[-1] == DEFAULT_NODATA
    err = np.abs(recon[:-1] - a[:-1])
    assert float(err.max()) <= params.theoretical_max_error() + 1e-9
    assert meta["clip_total"] == 0


def test_uint8_clipping_reported():
    params = UInt8Params(m_min=18.0, m_max=20.0)
    a = np.array([17.0, 19.0, 21.0], dtype=np.float32)
    codes, meta = quantize_uint8(a, params)
    assert meta["clip_low_count"] >= 1
    assert meta["clip_high_count"] >= 1
    recon = dequantize_uint8(codes, params)
    assert recon[0] == pytest.approx(params.m_min, abs=params.step())
    assert recon[2] == pytest.approx(params.m_max, abs=params.step())
