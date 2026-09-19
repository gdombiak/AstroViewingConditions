from __future__ import annotations

import pytest

from astro_engine.errors import ValidationError
from astro_engine.location_distance import distance_miles, location_distance


def test_distance_cases():
    assert distance_miles(0, 0, 0, 0) == 0
    assert distance_miles(0, 0, 0, 1) == pytest.approx(69.09332413987235, abs=1e-9)
    assert distance_miles(0, 179, 0, -179) == pytest.approx(138.18664827974413, abs=1e-9)
    assert distance_miles(45, -122, -33, 151) == pytest.approx(7651.197289399826, abs=1e-9)


@pytest.mark.parametrize("point", [
    {"latitude": True, "longitude": 0},
    {"latitude": 91, "longitude": 0},
    {"latitude": 0, "longitude": 181},
    {"latitude": 0, "longitude": 0, "name": "extra"},
    {"latitude": "0", "longitude": 0},
])
def test_invalid_coordinate(point):
    with pytest.raises(ValidationError, match="invalid location.distance input"):
        location_distance({"from": point, "to": {"latitude": 0, "longitude": 0}})
