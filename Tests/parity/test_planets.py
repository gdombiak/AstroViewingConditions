"""Contract and fail-closed checks for the planet observation/recommendation slice."""
import json
import subprocess
from copy import deepcopy
from datetime import datetime, timedelta, timezone

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from astro_engine.errors import ValidationError
from astro_engine._capability import evaluate_capability
from compare import compare_envelope, compare_value, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import ensure_eval_binary, run_swift_eval

CASES = [f for f in iter_deterministic_fixtures()
         if f["meta"]["capability"] == "targets.planet_recommendation"]

SUPPORTED = ("venus", "mars", "jupiter", "saturn")


@pytest.mark.parametrize("fixture", CASES, ids=lambda f: f["id"])
def test_planet_recommendation_exact_both_directions(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope("targets.planet_recommendation", fixture["input"])
    for actual, expected in ((swift, fixture["expected"]), (python, fixture["expected"]),
                             (swift, python), (python, swift)):
        compare_envelope(actual, expected, policy_id="planet_recommendation")


def test_planet_catalog_and_fixture_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text()
    catalog_ids = [line.split(": ", 1)[1] for line in catalog.splitlines() if line.startswith("  - id: ")]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-2:] == ["astronomy.planet_observation", "targets.planet_recommendation"]
    for capability, equality in (("astronomy.planet_observation", "astronomy_planet_observation"),
                                 ("targets.planet_recommendation", "planet_recommendation")):
        block = catalog.split(f"  - id: {capability}\n", 1)[1].split("  - id:", 1)[0]
        assert 'since: "1.0.0"' in block
        assert "hosts: [ios, cli]" in block
        assert f"equality: {equality}" in block
    # Exact parity is conditioned on frozen provider facts, the same way
    # targets.moon_recommendation's is. See the composition boundary in the procedure.
    recommendation_block = catalog.split("  - id: targets.planet_recommendation\n", 1)[1]
    assert ("requires_injected: [planet_observation, hourly_ratings, cloud_cover_score]"
            in recommendation_block)
    for name, capability in (("planet-observation", "astronomy.planet_observation"),
                             ("planet-recommendation", "targets.planet_recommendation")):
        text = (contracts_root() / f"procedures/{name}.md").read_text()
        assert "Composition boundary" in text
        assert capability in text
    observation_fields = load_policy_fields("astronomy_planet_observation")
    assert observation_fields["observation"] == "null_or_object"
    assert observation_fields["observation.samples[].azimuth"] == "cyclic_azimuth_abs_0_01"
    assert observation_fields["observation.samples[].altitude"] == "abs_1e4"
    assert load_policy_fields("planet_recommendation")["recommendation"] == "null_or_object"
    assert len(CASES) == 79
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["equality"] == "planet_recommendation"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_planets_are_not_routed_through_the_generic_target_scorer():
    """Specialized planet scoring exists deliberately; targets.recommend is a
    different capability with a different calibration file."""
    scoring = json.loads((contracts_root() / "data/calibration/planet-recommendation.json").read_text())
    generic = json.loads((contracts_root() / "data/calibration/target-scoring.json").read_text())
    assert scoring["weights"] == {"altitude": 45, "weather": 30, "visibility": 12, "convenience": 13}
    assert scoring["weights"] != generic.get("weights")


def _oversized(kind):
    base = deepcopy(next(f for f in CASES if f["id"] == "jupiter-ordinary-night-v1")["input"])
    start = datetime(2026, 3, 1, 20, tzinfo=timezone.utc)
    times = [(start + timedelta(minutes=index)).strftime("%Y-%m-%dT%H:%M:%SZ")
             for index in range(1441)]
    if kind == "samples":
        base["injected"]["samples"] = [
            {"time": time, "altitude": 40.0, "azimuth": 180.0, "solar_elongation": 45.0}
            for time in times
        ]
    else:
        base["injected"]["hourly_ratings"] = [{"time": time, "score": 1.0} for time in times]
    return base


@pytest.mark.parametrize("kind", ["samples", "ratings"])
def test_row_cap_is_enforced_before_iteration_in_both_engines(kind, tmp_path):
    """The cap is checked on the array, not discovered by iterating it."""
    document = _oversized(kind)
    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability("targets.planet_recommendation", document)
    assert excinfo.value.code == "sample_cap"
    message = "targets.planet_recommendation exceeds the 1.0 row cap (1440 rows)"
    assert str(excinfo.value) == message

    path = tmp_path / "input.json"
    path.write_text(json.dumps(document))
    result = subprocess.run([str(ensure_eval_binary()), "targets.planet_recommendation",
                             "--input", str(path)], capture_output=True, text=True)
    assert result.returncode == 2
    assert json.loads(result.stdout)["error"] == {"code": "sample_cap", "message": message}


@pytest.mark.parametrize("kind", ["span", "sample_cap", "non_advancing", "boolean_latitude",
                                  "fractional", "huge_cadence", "zero_cadence", "target_id",
                                  "earth", "latitude_range", "instant_range", "unknown_field"])
def test_planet_observation_bounds_agree_in_both_engines(kind, tmp_path):
    injected = {"target_id": "venus", "latitude": 37.7749, "longitude": -122.4194,
                "night_start": "2026-03-01T04:00:00Z", "night_end": "2026-03-01T12:00:00Z"}
    expected = {"code": "validation", "message": "invalid astronomy.planet_observation input"}
    if kind == "span":
        injected["night_end"] = "2026-03-02T07:00:00Z"
    elif kind == "sample_cap":
        injected["sample_interval_seconds"] = 1
        expected = {"code": "sample_cap",
                    "message": "astronomy.planet_observation exceeds the 1.0 sample cap (1440 samples)"}
    elif kind == "non_advancing":
        injected["sample_interval_seconds"] = 1e-12
        expected = {"code": "sample_cap",
                    "message": "astronomy.planet_observation exceeds the 1.0 sample cap (1440 samples)"}
    elif kind == "boolean_latitude":
        injected["latitude"] = True
    elif kind == "fractional":
        injected["sample_interval_seconds"] = 900.5
    elif kind == "huge_cadence":
        injected["sample_interval_seconds"] = 93601
    elif kind == "zero_cadence":
        injected["sample_interval_seconds"] = 0
    elif kind == "target_id":
        injected["target_id"] = "mercury"
    elif kind == "earth":
        injected["target_id"] = "earth"
    elif kind == "latitude_range":
        injected["latitude"] = 90.1
    elif kind == "instant_range":
        injected["night_start"] = "1999-12-31T23:59:59Z"
    else:
        injected["extra"] = 1
    document = {"capability": "astronomy.planet_observation", "injected": injected}

    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability("astronomy.planet_observation", document)
    assert {"code": excinfo.value.code, "message": str(excinfo.value)} == expected

    path = tmp_path / "input.json"
    path.write_text(json.dumps(document))
    result = subprocess.run([str(ensure_eval_binary()), "astronomy.planet_observation",
                             "--input", str(path)], capture_output=True, text=True)
    assert result.returncode == 2
    assert json.loads(result.stdout)["error"] == expected


@pytest.mark.parametrize("mutation", [
    "null-recommendation", "score", "reason-order", "extra-reason", "window-shift",
    "direction", "azimuth", "extra-field",
])
def test_planet_recommendation_equality_fails_closed(mutation):
    expected = next(f["expected"] for f in CASES if f["id"] == "jupiter-ordinary-night-v1")
    actual = deepcopy(expected)
    recommendation = actual["result"]["recommendation"]
    if mutation == "null-recommendation":
        actual["result"]["recommendation"] = None
    elif mutation == "score":
        recommendation["score"] += 1
    elif mutation == "reason-order":
        recommendation["reasons"] = list(reversed(recommendation["reasons"]))
    elif mutation == "extra-reason":
        recommendation["reasons"] = recommendation["reasons"] + ["poorWeather"]
    elif mutation == "window-shift":
        recommendation["visibility_window"]["end"] = "2026-03-02T01:15:01Z"
    elif mutation == "direction":
        recommendation["visibility_window"]["direction"] = "SSW"
    elif mutation == "azimuth":
        recommendation["visibility_window"]["azimuth"] += 1e-9
    else:
        recommendation["visible_fraction"] = 0.75
    with pytest.raises(AssertionError):
        compare_envelope(actual, expected, policy_id="planet_recommendation")


@pytest.mark.parametrize("field,spec,a,b,passes", [
    ("azimuth", "cyclic_azimuth_abs_0_01", 359.999, 0.005, True),
    ("azimuth", "cyclic_azimuth_abs_0_01", 359.9, 0.0, False),
    ("azimuth", "cyclic_azimuth_abs_0_01", 180.0, None, False),
    ("altitude", "abs_1e4", 10.0, 10.00009, True),
    ("altitude", "abs_1e4", 10.0, 10.0002, False),
])
def test_symmetric_planet_field_boundaries(field, spec, a, b, passes):
    for left, right in ((a, b), (b, a)):
        if passes:
            compare_value(left, right, {field: spec}, path=field)
        else:
            with pytest.raises(AssertionError):
                compare_value(left, right, {field: spec}, path=field)


# --- composition -----------------------------------------------------------
#
# `astronomy.planet_observation` is a live provider capability with tolerance
# parity; `targets.planet_recommendation` is deterministic with exact parity
# conditioned on its injected facts. Both hosts run the *same* production
# orbital-element model here, so composition currently agrees exactly. That is a
# property of the shared model, not a guarantee of the contract: every
# recommendation decision is a strict cut-point on a live quantity, so a host
# that derived the observation from a different model could land on the other
# side of one. See contracts/procedures/planet-recommendation.md,
# "Composition boundary".


def _swift(capability, injected, tmp_path):
    path = tmp_path / "composed.json"
    path.write_text(json.dumps({"capability": capability, "injected": injected}))
    result = subprocess.run([str(ensure_eval_binary()), capability, "--input", str(path)],
                            capture_output=True, text=True)
    envelope = json.loads(result.stdout)
    assert envelope.get("ok") is True, envelope
    return envelope["result"]


def _python(capability, injected, tmp_path=None):
    return evaluate_capability(capability, {"capability": capability, "injected": injected})


def _composed(runner, target_id, latitude, longitude, night_start, night_end, tmp_path):
    observation = runner("astronomy.planet_observation", {
        "target_id": target_id, "latitude": latitude, "longitude": longitude,
        "night_start": night_start, "night_end": night_end,
    }, tmp_path)
    if observation["observation"] is None:
        return observation, None
    document = {
        "target_id": target_id,
        "night_start": night_start,
        "night_end": night_end,
        "samples": observation["observation"]["samples"],
        "cloud_cover_score": 10.0,
        "hourly_ratings": [],
    }
    return observation, runner("targets.planet_recommendation", document, tmp_path)


def _composition_nights():
    for target_id in SUPPORTED:
        for latitude, longitude in ((40.7, -74.0), (-33.87, 151.21), (0.0, 0.0), (64.1, -21.9)):
            for day in (1, 60, 190, 300):
                night_start = datetime(2026, 1, 1, 3, tzinfo=timezone.utc) + timedelta(days=day)
                yield (target_id, latitude, longitude,
                       night_start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                       (night_start + timedelta(hours=8, minutes=7)).strftime("%Y-%m-%dT%H:%M:%SZ"))
    # The boundary nights the ordinary sweep cannot reach: the two-hour sampling
    # lead spills before the earliest supported night instant, and the one-hour
    # trail spills past the latest one. Both must survive composition.
    for target_id in SUPPORTED:
        yield (target_id, 40.7, -74.0, "2000-01-01T00:00:00Z", "2000-01-01T08:00:00Z")
        yield (target_id, 40.7, -74.0, "2049-12-31T14:00:00Z", "2049-12-31T23:59:59Z")


COMPOSITION_NIGHT_COUNT = 4 * 4 * 4 + 2 * len(SUPPORTED)


def test_same_model_composition_keeps_all_decisions(tmp_path):
    fields = load_policy_fields("planet_recommendation")
    nights = recommended = 0
    before_night_floor = after_night_ceiling = 0
    for target_id, latitude, longitude, start, end in _composition_nights():
        observation, swift = _composed(_swift, target_id, latitude, longitude, start, end, tmp_path)
        _, python = _composed(_python, target_id, latitude, longitude, start, end, tmp_path)
        assert (swift is None) == (python is None)
        nights += 1
        if swift is None:
            continue
        times = [row["time"] for row in observation["observation"]["samples"]]
        before_night_floor += sum(1 for time in times if time < "2000-01-01T00:00:00Z")
        after_night_ceiling += sum(1 for time in times if time > "2049-12-31T23:59:59Z")
        compare_value(swift, python, fields, path="")
        compare_value(python, swift, fields, path="")
        assert swift == python
        recommended += swift["recommendation"] is not None
    assert nights == COMPOSITION_NIGHT_COUNT
    assert recommended > 20, "the sweep must actually produce recommendations"
    # The boundary nights must actually contribute spill-region samples, or the
    # bounded-spill transport limits are never exercised here.
    assert before_night_floor > 0 and after_night_ceiling > 0


def test_lower_bound_observation_result_composes_verbatim_on_both_hosts(tmp_path):
    """The central invariant: a valid observation bundle is consumable as-is.

    The earliest supported night samples from 1999-12-31T22:00:00Z, which is
    outside the deterministic capability's own night-instant range and inside its
    justified sample spill.
    """
    night_start, night_end = "2000-01-01T00:00:00Z", "2000-01-01T08:00:00Z"
    injected = {"target_id": "saturn", "latitude": 40.7, "longitude": -74.0,
                "night_start": night_start, "night_end": night_end}
    swift_observation = _swift("astronomy.planet_observation", injected, tmp_path)
    python_observation = _python("astronomy.planet_observation", injected)
    assert swift_observation == python_observation
    assert swift_observation["observation"]["sample_start"] == "1999-12-31T22:00:00Z"
    samples = swift_observation["observation"]["samples"]
    assert sum(1 for row in samples if row["time"] < night_start) == 8
    # The first sample is above the visible altitude, so a spill-region instant
    # determines the emitted window rather than merely being carried along.
    assert samples[0]["altitude"] >= 8

    document = {"target_id": "saturn", "night_start": night_start, "night_end": night_end,
                "samples": samples, "cloud_cover_score": 10.0,
                "hourly_ratings": [{"time": "1999-12-31T21:00:01Z", "score": 0.4}]}
    swift_result = _swift("targets.planet_recommendation", document, tmp_path)
    python_result = _python("targets.planet_recommendation", document)
    assert swift_result == python_result
    window = swift_result["recommendation"]["visibility_window"]
    assert window["start"] == "1999-12-31T22:00:00Z"
    assert window["start"] < night_start


def test_upper_spill_window_end_agrees_on_both_hosts(tmp_path):
    """The recommendation's own night range reaches 2499-12-31T23:59:59Z, so the
    trail plus the fixed 900 s extension must be emittable by both hosts."""
    document = {
        "target_id": "saturn",
        "night_start": "2499-12-31T15:00:00Z", "night_end": "2499-12-31T23:59:59Z",
        "samples": [
            {"time": "2500-01-01T00:00:00Z", "altitude": 35.0, "azimuth": 170.0,
             "solar_elongation": 45.0},
            {"time": "2500-01-01T00:59:59Z", "altitude": 42.0, "azimuth": 185.0,
             "solar_elongation": 45.0},
        ],
        "cloud_cover_score": 10.0,
        "hourly_ratings": [{"time": "2500-01-01T01:14:59Z", "score": 0.4}],
    }
    swift_result = _swift("targets.planet_recommendation", document, tmp_path)
    python_result = _python("targets.planet_recommendation", document)
    assert swift_result == python_result
    assert swift_result["recommendation"]["visibility_window"]["end"] == "2500-01-01T01:14:59Z"


@pytest.mark.parametrize("kind,time", [
    ("sample", "1999-12-31T21:59:59Z"),
    ("sample", "2500-01-01T01:00:00Z"),
    ("rating", "1999-12-31T20:59:59Z"),
    ("rating", "2500-01-01T01:15:00Z"),
])
def test_outside_the_justified_spill_fails_closed_in_both_engines(kind, time, tmp_path):
    document = {"capability": "targets.planet_recommendation", "injected": {
        "target_id": "saturn",
        "night_start": "2000-01-01T00:00:00Z", "night_end": "2000-01-01T08:00:00Z",
        "samples": [{"time": "1999-12-31T22:00:00Z", "altitude": 30.0, "azimuth": 170.0,
                     "solar_elongation": 45.0}],
        "cloud_cover_score": 10.0, "hourly_ratings": [],
    }}
    injected = document["injected"]
    if kind == "sample":
        injected["samples"] = [{"time": time, "altitude": 30.0, "azimuth": 170.0,
                                "solar_elongation": 45.0}]
        if time > "2400-01-01T00:00:00Z":
            injected["night_start"], injected["night_end"] = (
                "2499-12-31T15:00:00Z", "2499-12-31T23:59:59Z")
    else:
        injected["hourly_ratings"] = [{"time": time, "score": 0.4}]
        if time > "2400-01-01T00:00:00Z":
            injected["night_start"], injected["night_end"] = (
                "2499-12-31T15:00:00Z", "2499-12-31T23:59:59Z")
            injected["samples"] = [{"time": "2500-01-01T00:00:00Z", "altitude": 30.0,
                                    "azimuth": 170.0, "solar_elongation": 45.0}]
    expected = {"code": "validation", "message": "invalid targets.planet_recommendation input"}

    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability("targets.planet_recommendation", document)
    assert {"code": excinfo.value.code, "message": str(excinfo.value)} == expected

    path = tmp_path / "input.json"
    path.write_text(json.dumps(document))
    result = subprocess.run([str(ensure_eval_binary()), "targets.planet_recommendation",
                             "--input", str(path)], capture_output=True, text=True)
    assert result.returncode == 2
    assert json.loads(result.stdout)["error"] == expected


@pytest.mark.parametrize("field", ["night_start", "night_end"])
def test_night_instants_keep_the_unspilled_range_in_both_engines(field, tmp_path):
    """The spill applies to provider-derived instants, not to the night interval."""
    injected = {
        "target_id": "saturn",
        "night_start": "2000-01-01T00:00:00Z", "night_end": "2000-01-01T08:00:00Z",
        "samples": [{"time": "2000-01-01T02:00:00Z", "altitude": 30.0, "azimuth": 170.0,
                     "solar_elongation": 45.0}],
        "cloud_cover_score": 10.0, "hourly_ratings": [],
    }
    # Inside the sample spill, still outside the night range.
    injected[field] = ("1999-12-31T23:00:00Z" if field == "night_start"
                       else "2500-01-01T00:00:00Z")
    document = {"capability": "targets.planet_recommendation", "injected": injected}
    expected = {"code": "validation", "message": "invalid targets.planet_recommendation input"}

    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability("targets.planet_recommendation", document)
    assert {"code": excinfo.value.code, "message": str(excinfo.value)} == expected

    path = tmp_path / "input.json"
    path.write_text(json.dumps(document))
    result = subprocess.run([str(ensure_eval_binary()), "targets.planet_recommendation",
                             "--input", str(path)], capture_output=True, text=True)
    assert result.returncode == 2
    assert json.loads(result.stdout)["error"] == expected


def test_injecting_one_observation_into_both_hosts_is_exact(tmp_path):
    """The contract that holds regardless of the provider: one frozen fact, one answer."""
    night_start, night_end = "2026-07-18T04:43:38Z", "2026-07-18T11:16:06Z"
    observation = _swift("astronomy.planet_observation", {
        "target_id": "venus", "latitude": 33.8078, "longitude": -118.3183,
        "night_start": night_start, "night_end": night_end,
    }, tmp_path)
    document = {
        "target_id": "venus", "night_start": night_start, "night_end": night_end,
        "samples": observation["observation"]["samples"],
        "cloud_cover_score": 10.0, "hourly_ratings": [],
    }
    assert _swift("targets.planet_recommendation", document, tmp_path) == _python(
        "targets.planet_recommendation", document)
