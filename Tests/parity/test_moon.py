"""Contract and fail-closed checks for the lunar observation/recommendation slice."""
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
         if f["meta"]["capability"] == "targets.moon_recommendation"]


@pytest.mark.parametrize("fixture", CASES, ids=lambda f: f["id"])
def test_moon_recommendation_exact_both_directions(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope("targets.moon_recommendation", fixture["input"])
    for actual, expected in ((swift, fixture["expected"]), (python, fixture["expected"]),
                             (swift, python), (python, swift)):
        compare_envelope(actual, expected, policy_id="moon_recommendation")


def test_moon_catalog_and_fixture_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text()
    catalog_ids = [line.split(": ", 1)[1] for line in catalog.splitlines() if line.startswith("  - id: ")]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-2:] == ["astronomy.moon_observation", "targets.moon_recommendation"]
    for capability, equality in (("astronomy.moon_observation", "astronomy_moon_observation"),
                                 ("targets.moon_recommendation", "moon_recommendation")):
        block = catalog.split(f"  - id: {capability}\n", 1)[1].split("  - id:", 1)[0]
        assert 'since: "1.0.0"' in block
        assert "hosts: [ios, cli]" in block
        assert f"equality: {equality}" in block
    # Exact parity is conditioned on frozen provider facts, the same way
    # night_conditions.analyze's is. See the composition boundary in the procedure.
    recommendation_block = catalog.split("  - id: targets.moon_recommendation\n", 1)[1]
    assert ("requires_injected: [moon_observation, best_window, hourly_ratings, cloud_cover_score]"
            in recommendation_block)
    assert "Composition boundary" in (contracts_root() / "procedures/moon-recommendation.md").read_text()
    assert "Composition boundary" in (contracts_root() / "procedures/moon-observation.md").read_text()
    observation = (contracts_root() / "procedures/moon-observation.md").read_text()
    recommendation = (contracts_root() / "procedures/moon-recommendation.md").read_text()
    assert "astronomy.moon_observation" in observation
    assert "targets.moon_recommendation" in recommendation
    assert load_policy_fields("astronomy_moon_observation")["samples[].azimuth"] == "cyclic_azimuth_abs_2"
    assert load_policy_fields("astronomy_moon_observation")["always_up"] == "boolean_exact"
    assert load_policy_fields("moon_recommendation")["recommendation"] == "null_or_object"
    assert len(CASES) == 46
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["equality"] == "moon_recommendation"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_omitted_and_null_best_window_agree():
    omitted = next(f for f in CASES if f["id"] == "omitted-best-window-uses-night-v1")
    explicit = next(f for f in CASES if f["id"] == "null-best-window-uses-night-v1")
    assert omitted["expected"]["result"] == explicit["expected"]["result"]


def test_ignored_observation_fields_do_not_change_the_result():
    """rise/always_up exist for composability with astronomy.moon_observation."""
    ignored = next(f for f in CASES if f["id"] == "rise-and-always-up-do-not-change-result-v1")
    baseline = deepcopy(ignored["input"])
    baseline["injected"]["moon"]["rise"] = None
    baseline["injected"]["moon"]["always_up"] = False
    assert python_envelope("targets.moon_recommendation", baseline)["result"] == ignored["expected"]["result"]


def _oversized(kind):
    base = deepcopy(next(f for f in CASES if f["id"] == "omitted-best-window-uses-night-v1")["input"])
    row = {"time": "2026-08-29T02:00:00Z", "altitude": 5.0, "azimuth": 90.0}
    if kind == "samples":
        base["injected"]["moon"]["samples"] = [
            dict(row, time=f"2026-08-29T{2 + index // 3600:02d}:{index // 60 % 60:02d}:{index % 60:02d}Z")
            for index in range(1441)
        ]
    else:
        base["injected"]["hourly_ratings"] = [
            {"time": f"2026-08-29T{2 + index // 3600:02d}:{index // 60 % 60:02d}:{index % 60:02d}Z",
             "score": 1.0}
            for index in range(1441)
        ]
    return base


@pytest.mark.parametrize("kind", ["samples", "ratings"])
def test_row_cap_is_enforced_before_iteration_in_both_engines(kind, tmp_path):
    """The cap is checked on the array, not discovered by iterating it."""
    document = _oversized(kind)
    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability("targets.moon_recommendation", document)
    assert excinfo.value.code == "sample_cap"
    message = "targets.moon_recommendation exceeds the 1.0 row cap (1440 rows)"
    assert str(excinfo.value) == message

    path = tmp_path / "input.json"
    path.write_text(json.dumps(document))
    result = subprocess.run([str(ensure_eval_binary()), "targets.moon_recommendation",
                             "--input", str(path)], capture_output=True, text=True)
    assert result.returncode == 2
    error = json.loads(result.stdout)["error"]
    assert error == {"code": "sample_cap", "message": message}


@pytest.mark.parametrize("kind", ["span", "sample_cap", "non_advancing", "boolean_latitude",
                                  "end_sample", "fractional", "subsecond", "search_duration",
                                  "inverted_search_duration", "huge_search_duration"])
def test_moon_observation_bounds_agree_in_both_engines(kind, tmp_path):
    injected = {"latitude": 37.7749, "longitude": -122.4194,
                "night_start": "2024-03-25T04:00:00Z", "night_end": "2024-03-25T12:00:00Z"}
    if kind == "span":
        injected["night_end"] = "2024-03-26T07:00:00Z"
        expected = {"code": "validation", "message": "invalid astronomy.moon_observation input"}
    elif kind == "sample_cap":
        injected["sample_interval_seconds"] = 1
        expected = {"code": "sample_cap",
                    "message": "astronomy.moon_observation exceeds the 1.0 sample cap (1440 samples)"}
    elif kind == "non_advancing":
        injected["sample_interval_seconds"] = 1e-12
        expected = {"code": "sample_cap",
                    "message": "astronomy.moon_observation exceeds the 1.0 sample cap (1440 samples)"}
    elif kind == "end_sample":
        injected.update(night_end="2024-03-26T03:59:30Z", sample_interval_seconds=60)
        expected = {"code": "sample_cap",
                    "message": "astronomy.moon_observation exceeds the 1.0 sample cap (1440 samples)"}
    elif kind in ("fractional", "subsecond", "search_duration", "inverted_search_duration", "huge_search_duration"):
        injected["sample_interval_seconds"] = {
            "fractional": 1800.5, "subsecond": 0.5, "search_duration": 93601,
            "inverted_search_duration": 93601, "huge_search_duration": 1e308,
        }[kind]
        if kind == "subsecond":
            injected["night_end"] = "2024-03-25T04:00:01Z"
        if kind == "inverted_search_duration":
            injected["night_end"] = "2024-03-25T03:00:00Z"
        expected = {"code": "validation", "message": "invalid astronomy.moon_observation input"}
    else:
        injected["latitude"] = True
        expected = {"code": "validation", "message": "invalid astronomy.moon_observation input"}
    document = {"capability": "astronomy.moon_observation", "injected": injected}

    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability("astronomy.moon_observation", document)
    assert {"code": excinfo.value.code, "message": str(excinfo.value)} == expected

    path = tmp_path / "input.json"
    path.write_text(json.dumps(document))
    result = subprocess.run([str(ensure_eval_binary()), "astronomy.moon_observation",
                             "--input", str(path)], capture_output=True, text=True)
    assert result.returncode == 2
    assert json.loads(result.stdout)["error"] == expected


@pytest.mark.parametrize("mutation", [
    "null-recommendation", "score", "reason-order", "extra-reason", "window-shift",
    "missing-direction", "null-azimuth", "extra-field",
])
def test_moon_recommendation_equality_fails_closed(mutation):
    expected = next(f["expected"] for f in CASES if f["id"] == "best-window-clips-useful-samples-v1")
    actual = deepcopy(expected)
    recommendation = actual["result"]["recommendation"]
    if mutation == "null-recommendation":
        actual["result"]["recommendation"] = None
    elif mutation == "score":
        recommendation["score"] += 1
    elif mutation == "reason-order":
        recommendation["reasons"] = ["poorWeather", "excellentMoonCraterDetail"]
        expected = deepcopy(expected)
        expected["result"]["recommendation"]["reasons"] = ["excellentMoonCraterDetail", "poorWeather"]
    elif mutation == "extra-reason":
        recommendation["reasons"] = recommendation["reasons"] + ["poorWeather"]
    elif mutation == "window-shift":
        recommendation["visibility_window"]["end"] = "2026-08-29T05:00:01Z"
    elif mutation == "missing-direction":
        del recommendation["visibility_window"]["direction"]
    elif mutation == "null-azimuth":
        recommendation["visibility_window"]["azimuth"] = None
    else:
        recommendation["visible_fraction"] = 0.75
    with pytest.raises(AssertionError):
        compare_envelope(actual, expected, policy_id="moon_recommendation")


@pytest.mark.parametrize("field,spec,a,b,passes", [
    ("phase", "cyclic_phase_abs_0_002", 0.9995, 0.0005, True),
    ("phase", "cyclic_phase_abs_0_002", 0.0, 0.0021, False),
    ("phase", "cyclic_phase_abs_0_002", 0.5, 0.5015, True),
    ("azimuth", "cyclic_azimuth_abs_2", 359.5, 0.5, True),
    ("azimuth", "cyclic_azimuth_abs_2", 359.0, 1.5, False),
    ("azimuth", "cyclic_azimuth_abs_2", 180.0, None, False),
    ("always_up", "boolean_exact", True, True, True),
    ("always_up", "boolean_exact", True, 1, False),
    ("always_up", "boolean_exact", True, False, False),
])
def test_symmetric_moon_field_boundaries(field, spec, a, b, passes):
    from compare import compare_value
    for left, right in ((a, b), (b, a)):
        if passes:
            compare_value(left, right, {field: spec}, path=field)
        else:
            with pytest.raises(AssertionError):
                compare_value(left, right, {field: spec}, path=field)


# --- rejected Skyfield composed path ---------------------------------------------------
#
# `astronomy.moon_observation` is a live provider capability with tolerance
# parity; `targets.moon_recommendation` is deterministic with exact parity
# conditioned on its injected facts. Running the live capability on each host and
# feeding each host its own result is therefore NOT an exact-parity path: every
# recommendation decision is a strict cut-point on a live quantity, so two
# ephemerides that disagree at all can land on opposite sides of one. That is
# specified in contracts/procedures/moon-recommendation.md, "Composition
# boundary". These tests characterize it rather than hide it: the divergence must
# stay confined to the documented cut-points, and any other source of divergence
# is a real defect.

DECISION_FIELDS = ("score", "reasons")
WINDOW_DECISION_FIELDS = ("start", "end", "best_time", "direction")


def _observation(runner, latitude, longitude, night_start, night_end, tmp_path=None):
    injected = {"latitude": latitude, "longitude": longitude,
                "night_start": night_start, "night_end": night_end}
    return runner("astronomy.moon_observation", injected, tmp_path)


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


def _skyfield_reference(capability, injected, tmp_path=None):
    if capability != "astronomy.moon_observation":
        return _python(capability, injected, tmp_path)
    from moon_skyfield_reference import SkyfieldMoonReference
    from astro_engine.moon_observation import observe, _epoch_seconds, _timestamp
    start, end = (_epoch_seconds(injected[k]) for k in ("night_start", "night_end"))
    sampler = SkyfieldMoonReference()
    try:
        result = observe(sampler, injected["latitude"], injected["longitude"], start, end,
                         injected.get("sample_interval_seconds", 1800))
    finally:
        sampler.close()
    result["night_start"], result["night_end"] = _timestamp(start), _timestamp(end)
    for key in ("rise", "set"):
        if result[key] is not None:
            result[key] = _timestamp(result[key])
    result["samples"] = [dict(time=_timestamp(t), altitude=a, azimuth=z)
                         for t, a, z in result["samples"]]
    return result


def _composed(runner, latitude, longitude, night_start, night_end, tmp_path):
    observation = _observation(runner, latitude, longitude, night_start, night_end, tmp_path)
    document = {
        "night_start": night_start,
        "night_end": night_end,
        "moon": {key: observation[key] for key in
                 ("phase", "illumination", "rise", "set", "always_up", "always_down", "samples")},
        "cloud_cover_score": 10.0,
        "hourly_ratings": [],
    }
    return observation, runner("targets.moon_recommendation", document, tmp_path)


def _straddled_cut_points(swift_observation, python_observation, useful_end_epoch):
    """Documented cut-points on which the two observations disagree."""
    def quarter(observation):
        phase = observation["phase"]
        return min(abs(phase - 0.25), abs(phase - 0.75)) <= 0.08

    def visible(observation):
        return [row["altitude"] > 0 for row in observation["samples"]]

    def sets_early(observation):
        if observation["set"] is None:
            return False
        moment = datetime.strptime(observation["set"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        return moment.timestamp() < useful_end_epoch - 7200

    predicates = {
        "illumination<=8": lambda o: o["illumination"] <= 8,
        "illumination<=45": lambda o: o["illumination"] <= 45,
        "illumination>=90": lambda o: o["illumination"] >= 90,
        "phase<=0.04": lambda o: o["phase"] <= 0.04,
        "phase>=0.96": lambda o: o["phase"] >= 0.96,
        "quarter<=0.08": quarter,
        "set<useful.end-7200": sets_early,
        "altitude>0": visible,
    }
    return sorted(name for name, predicate in predicates.items()
                  if predicate(swift_observation) != predicate(python_observation))


def _decisions_differ(swift_recommendation, python_recommendation):
    if (swift_recommendation is None) != (python_recommendation is None):
        return True
    if swift_recommendation is None:
        return False
    if any(swift_recommendation[field] != python_recommendation[field] for field in DECISION_FIELDS):
        return True
    return any(swift_recommendation["visibility_window"][field]
               != python_recommendation["visibility_window"][field]
               for field in WINDOW_DECISION_FIELDS)


def _sweep_nights():
    """March 2026 covers the illumination straddle on 2026-03-16; the three
    explicit nights place `useful.end - 2h` between the two hosts' set instants."""
    start = datetime(2026, 3, 1, 2, tzinfo=timezone.utc)
    for latitude, longitude in ((40.7, -74.0), (-33.87, 151.21)):
        for day in range(40):
            night_start = start + timedelta(days=day)
            yield (latitude, longitude,
                   night_start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                   (night_start + timedelta(hours=9)).strftime("%Y-%m-%dT%H:%M:%SZ"))
    for night_start, night_end in (("2026-03-01T02:00:00Z", "2026-03-01T12:37:51Z"),
                                   ("2026-03-02T02:00:00Z", "2026-03-02T13:05:08Z"),
                                   ("2026-03-03T02:00:00Z", "2026-03-03T13:28:44Z")):
        yield (40.7, -74.0, night_start, night_end)


def test_rejected_skyfield_composition_divergence_stays_inside_the_documented_cut_points(tmp_path):
    """No divergence source other than the tabulated strict cut-points.

    The sweep is deliberately seeded with nights that do straddle a cut-point, so
    it exercises the branch instead of passing vacuously.
    """
    undocumented = []
    straddles = []
    nights = 0
    for latitude, longitude, first, second in _sweep_nights():
        swift_observation, swift_result = _composed(_swift, latitude, longitude, first, second, tmp_path)
        python_observation, python_result = _composed(_skyfield_reference, latitude, longitude, first, second, tmp_path)
        nights += 1
        if not _decisions_differ(swift_result["recommendation"], python_result["recommendation"]):
            continue
        useful_end = datetime.strptime(second, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        found = _straddled_cut_points(swift_observation, python_observation, useful_end.timestamp())
        if found:
            straddles.extend(found)
        else:
            undocumented.append((latitude, first, swift_result, python_result))
    assert not undocumented, (
        "composed divergence with no straddled cut-point — this is a real defect, not the "
        f"documented provider boundary: {undocumented[:2]}"
    )
    # Both seeded reference-model cut-points must still be reachable, or the procedure's measured
    # evidence needs re-measuring rather than the assertion relaxing.
    assert {"illumination<=8", "set<useful.end-7200"} <= set(straddles), sorted(set(straddles))
    # Ordinary nights must stay overwhelmingly in agreement; a jump here means a
    # new divergence source, not the known provider boundary.
    assert len(straddles) <= nights // 10, f"{len(straddles)} of {nights} nights diverged"


def test_rejected_skyfield_composed_divergence_reproduction(tmp_path):
    """The reproduction quoted in contracts/procedures/moon-recommendation.md.

    Both observations satisfy `astronomy_moon_observation`, yet the composed
    recommendations differ, because illumination straddles the `<= 8` cut-point.
    If a library upgrade changes this, the procedure's measured evidence must be
    re-measured rather than the assertion relaxed.
    """
    night_start, night_end = "2026-03-16T02:00:00Z", "2026-03-16T11:00:00Z"
    swift_observation, swift_result = _composed(_swift, 40.7, -74.0, night_start, night_end, tmp_path)
    python_observation, python_result = _composed(_skyfield_reference, 40.7, -74.0, night_start, night_end, tmp_path)

    fields = load_policy_fields("astronomy_moon_observation")
    compare_value(swift_observation, python_observation, fields, path="")
    compare_value(python_observation, swift_observation, fields, path="")

    assert {swift_observation["illumination"], python_observation["illumination"]} == {8, 9}
    assert _straddled_cut_points(
        swift_observation, python_observation,
        datetime.strptime(night_end, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp(),
    ) == ["illumination<=8"]

    scores = {swift_result["recommendation"]["score"], python_result["recommendation"]["score"]}
    assert scores == {64, 33}, scores
    reasons = sorted([swift_result["recommendation"]["reasons"],
                      python_result["recommendation"]["reasons"]], key=len)
    assert reasons == [["moonBelowUsefulWindow"],
                       ["moonBelowUsefulWindow", "newMoonDarkSky"]], reasons


def test_injecting_one_observation_into_both_hosts_is_exact(tmp_path):
    """The contract that does hold: one frozen provider fact, one exact answer."""
    night_start, night_end = "2026-03-16T02:00:00Z", "2026-03-16T11:00:00Z"
    observation = _observation(_swift, 40.7, -74.0, night_start, night_end, tmp_path)
    document = {
        "night_start": night_start, "night_end": night_end,
        "moon": {key: observation[key] for key in
                 ("phase", "illumination", "rise", "set", "always_up", "always_down", "samples")},
        "cloud_cover_score": 10.0, "hourly_ratings": [],
    }
    swift_result = _swift("targets.moon_recommendation", document, tmp_path)
    python_result = _python("targets.moon_recommendation", document)
    assert swift_result == python_result
