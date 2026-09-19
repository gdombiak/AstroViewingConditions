from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

import pytest

from astro_engine.contracts import contracts_root
from astro_engine.errors import ValidationError
from astro_engine.iss import decode_iss, iss_pass_id

from support import load_fixture

N2YO = Path("fixtures/providers/n2yo/visualpasses")
ISS_DECODE = Path("fixtures/capabilities/iss-decode")
NAMED_FIXTURES = ("two-passes", "empty-passes-array", "nil-passes")
PASS_ONE_ID = "4744917124793761792-4643985272004935680"
PASS_TWO_ID = "4744917487181627392-4646096334330265600"


def _provider(name: str) -> dict:
    path = contracts_root() / N2YO / f"{name}.json"
    return json.loads(path.read_text(encoding="utf-8"))


def _expected(name: str) -> dict:
    return load_fixture(contracts_root() / ISS_DECODE / name)["expected"]["result"]


def test_named_n2yo_fixtures_are_contract_owned() -> None:
    root = contracts_root() / N2YO
    for name in NAMED_FIXTURES:
        path = root / f"{name}.json"
        assert path.is_file(), name
        assert "packages" not in path.parts
        assert path.parts[-4:] == ("providers", "n2yo", "visualpasses", f"{name}.json")


@pytest.mark.parametrize("name", NAMED_FIXTURES)
def test_named_n2yo_fixtures(name: str) -> None:
    result = decode_iss(_provider(name))
    assert result == _expected(name)


def test_two_passes_literal_ids_and_domain_fields() -> None:
    raw = _provider("two-passes")
    result = decode_iss(raw)
    assert result["passes"][0]["id"] == PASS_ONE_ID
    assert result["passes"][1]["id"] == PASS_TWO_ID
    assert result["passes"][0]["id"] == iss_pass_id(
        rise_time_unix=1_700_000_000, duration=300
    )
    first = result["passes"][0]
    assert first["rise_time"] == "2023-11-14T22:13:20Z"
    assert first["duration"] == 300
    assert first["max_elevation"] == 45.0
    assert first["max_time"] == "2023-11-14T22:18:20Z"
    assert first["end_time"] == "2023-11-14T22:23:20Z"
    assert first["start_direction"] == "NE"
    assert first["max_direction"] == "E"
    assert first["end_direction"] == "SE"
    assert first["start_elevation"] == 10
    assert first["end_elevation"] == 10
    assert "start_az" not in first
    assert "mag" not in first
    assert "satid" not in result
    assert "info" not in result


def test_empty_and_nil_passes_are_distinct_raw_envelopes() -> None:
    empty_raw = _provider("empty-passes-array")
    nil_raw = _provider("nil-passes")
    assert empty_raw["passes"] == []
    assert "passes" not in nil_raw
    assert decode_iss(empty_raw) == {"passes": []}
    assert decode_iss(nil_raw) == {"passes": []}


def test_null_passes_also_map_to_empty_collection() -> None:
    payload = deepcopy(_provider("nil-passes"))
    payload["passes"] = None
    assert decode_iss(payload) == {"passes": []}


def test_root_must_be_object() -> None:
    with pytest.raises(ValidationError, match="object"):
        decode_iss([])
    with pytest.raises(ValidationError, match="info"):
        decode_iss({"passes": []})


def test_passes_must_be_an_array_when_present() -> None:
    payload = deepcopy(_provider("nil-passes"))
    payload["passes"] = "nope"
    with pytest.raises(ValidationError, match="passes"):
        decode_iss(payload)


def test_required_pass_numeric_and_string_types() -> None:
    payload = deepcopy(_provider("two-passes"))
    payload["passes"][0]["startUTC"] = "1700000000"
    with pytest.raises(ValidationError, match="startUTC"):
        decode_iss(payload)
    bool_utc = deepcopy(_provider("two-passes"))
    bool_utc["passes"][0]["duration"] = True
    with pytest.raises(ValidationError, match="duration"):
        decode_iss(bool_utc)
    missing_mag = deepcopy(_provider("two-passes"))
    del missing_mag["passes"][0]["mag"]
    with pytest.raises(ValidationError, match="mag"):
        decode_iss(missing_mag)
    missing_compass = deepcopy(_provider("two-passes"))
    missing_compass["passes"][0]["startAzCompass"] = 1
    with pytest.raises(ValidationError, match="startAzCompass"):
        decode_iss(missing_compass)
