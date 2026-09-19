import numpy as np
import pytest

from light_pollution.metrics import compute_error_metrics
from light_pollution.nodata import DEFAULT_NODATA


def test_metrics_known_error():
    o = np.array([[20.0, 21.0], [22.0, DEFAULT_NODATA]], dtype=np.float64)
    c = np.array([[20.04, 21.0], [22.0, 22.0]], dtype=np.float64)
    m = compute_error_metrics(o, c)
    assert m["n_both_valid"] == 3
    assert m["nodata_disagreement_count"] == 1
    assert m["mean_signed_error"] == pytest.approx(0.04 / 3)
    assert m["max_ae"] == pytest.approx(0.04)
    assert m["pct_within"]["0.05"] == pytest.approx(100.0)
    assert m["pct_within"]["0.02"] == pytest.approx(200.0 / 3.0)
