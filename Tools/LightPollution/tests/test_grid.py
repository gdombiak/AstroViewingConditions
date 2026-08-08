import numpy as np

from light_pollution.grid import GeoGrid, nearest_upsample, reduction_factor_for_degrees, window_for_extent


def test_lon_lat_to_cell():
    g = GeoGrid(-180.0, 75.0, 1 / 120, -1 / 120, 43200, 16801, 9.96921e36)
    assert g.lon_to_col(-180.0) == 0
    assert g.lon_to_col(0.0) == 21600
    assert g.lat_to_row(75.0) == 0
    # Oregon sample
    c = g.lon_to_col(-125.0)
    r = g.lat_to_row(47.0)
    assert c == 6600
    assert r == 3360


def test_boundary_lon():
    g = GeoGrid(-180.0, 75.0, 1 / 120, -1 / 120, 43200, 16801, 0.0)
    assert g.lon_to_col(180.0 - 1e-12) == 43199
    assert not g.contains_lon_lat(180.0, 0.0) or g.lon_to_col(179.999) < 43200


def test_window_oregon():
    g = GeoGrid(-180.0, 75.0, 1 / 120, -1 / 120, 43200, 16801, 0.0)
    xoff, yoff, xsize, ysize = window_for_extent(g, -125, -116, 42, 47)
    assert xoff == 6600
    assert yoff == 3360
    assert xsize == 1080
    assert ysize == 600


def test_reduction_factors():
    assert reduction_factor_for_degrees(1 / 120, 0.025) == 3
    assert reduction_factor_for_degrees(1 / 120, 0.05) == 6
    assert reduction_factor_for_degrees(1 / 120, 0.1) == 12


def test_nearest_upsample():
    coarse = np.array([[1.0, 2.0], [3.0, 4.0]], dtype=np.float32)
    up = nearest_upsample(coarse, 2, 2, 4, 4)
    assert up.shape == (4, 4)
    assert up[0, 0] == 1.0
    assert up[0, 1] == 1.0
    assert up[0, 2] == 2.0
    assert up[2, 0] == 3.0
