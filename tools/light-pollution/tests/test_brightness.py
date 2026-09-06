import numpy as np
import pytest

from light_pollution.brightness import (
    aggregate_linear_mean,
    aggregate_magnitude_mean,
    block_reduce_vectorized_linear,
    block_reduce_vectorized_mag,
    linear_to_mag,
    mag_to_linear,
)
from light_pollution.nodata import DEFAULT_NODATA


def test_mag_linear_roundtrip():
    mags = np.array([18.0, 20.0, 21.5, 22.0])
    lin = mag_to_linear(mags)
    back = linear_to_mag(lin)
    np.testing.assert_allclose(back, mags, rtol=0, atol=1e-10)


def test_darker_is_larger_mag_smaller_linear():
    assert mag_to_linear(22.0) < mag_to_linear(18.0)
    assert linear_to_mag(mag_to_linear(22.0)) == pytest.approx(22.0)


def test_linear_aggregation_not_equal_mag_mean():
    # Two very different brightnesses: linear mean is closer to the brighter (lower mag)
    vals = np.array([18.0, 22.0])
    lin_m = aggregate_linear_mean(vals)
    mag_m = aggregate_magnitude_mean(vals)
    assert lin_m < mag_m  # linear mean is brighter overall
    assert mag_m == pytest.approx(20.0)


def test_aggregation_excludes_nodata():
    vals = np.array([21.0, DEFAULT_NODATA, 21.0], dtype=np.float64)
    assert aggregate_linear_mean(vals) == pytest.approx(21.0)
    assert aggregate_magnitude_mean(vals) == pytest.approx(21.0)
    assert aggregate_linear_mean(np.array([DEFAULT_NODATA])) == DEFAULT_NODATA


def test_block_reduce_linear():
    # 2x2 blocks of constant values
    a = np.array(
        [
            [20.0, 20.0, 18.0, 18.0],
            [20.0, 20.0, 18.0, 18.0],
        ],
        dtype=np.float32,
    )
    out = block_reduce_vectorized_linear(a, 2, 2)
    assert out.shape == (1, 2)
    assert out[0, 0] == pytest.approx(20.0)
    assert out[0, 1] == pytest.approx(18.0)


def test_block_reduce_mag_baseline():
    a = np.full((2, 2), 21.0, dtype=np.float32)
    a[0, 0] = 19.0
    out = block_reduce_vectorized_mag(a, 2, 2)
    assert out.shape == (1, 1)
    assert out[0, 0] == pytest.approx(np.mean([19.0, 21.0, 21.0, 21.0]))
