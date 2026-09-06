from light_pollution.source import EXPECTED, validate_source_meta


def test_validate_good_meta():
    meta = {
        "width": EXPECTED["width"],
        "height": EXPECTED["height"],
        "dtype": EXPECTED["dtype"],
        "geotransform": [-180.0, 1 / 120, 0, 75.0, 0, -1 / 120],
        "nodata": 9.96921e36,
        "band_count": 1,
    }
    v = validate_source_meta(meta)
    assert v["ok"]


def test_validate_bad_size():
    meta = {
        "width": 10,
        "height": 10,
        "dtype": "Float32",
        "geotransform": [-180.0, 1 / 120, 0, 75.0, 0, -1 / 120],
        "nodata": 9.96921e36,
        "band_count": 1,
    }
    v = validate_source_meta(meta)
    assert not v["ok"]
