import numpy as np

from light_pollution.nodata import DEFAULT_NODATA, is_nodata, valid_mask


def test_nodata_threshold():
    a = np.array([21.0, DEFAULT_NODATA, np.nan, 1e36], dtype=np.float64)
    m = is_nodata(a)
    assert list(m) == [False, True, True, True]
    assert list(valid_mask(a)) == [True, False, False, False]
