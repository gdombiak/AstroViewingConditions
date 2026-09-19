"""Unit semantics for targets.filter_recommendations_by_equipment."""
from __future__ import annotations

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.filter_recommendations_by_equipment import (
    CAPABILITY_ID,
    MAX_CANDIDATE_COUNT,
    MAX_CAPABILITY_COUNT,
    Candidate,
    filter_recommendations_by_equipment,
    includes,
    selected,
)


def requirement(naked="unsupported"):
    return {
        "naked_eye_suitability": naked,
        "binocular_suitability": "unsuitable",
        "preferred_binocular_magnification": None,
        "practical_binocular_aperture_mm": None,
        "preferred_binocular_aperture_mm": None,
        "practical_visual_aperture_mm": None,
        "preferred_visual_aperture_mm": None,
        "practical_smart_eaa_aperture_mm": None,
        "preferred_smart_eaa_aperture_mm": None,
        "framing": "medium",
        "magnification_benefit": False,
        "smart_eaa_suitability": "poorMatch",
    }


def row(key, naked="unsupported", is_planet=False):
    return {"key": key, "is_planet": is_planet, "requirement": requirement(naked)}


def evaluate(candidates, capabilities, has_saved_inventory=True, minimum_fit="goodOrBetter"):
    return filter_recommendations_by_equipment({
        "candidates": candidates,
        "capabilities": capabilities,
        "has_saved_inventory": has_saved_inventory,
        "minimum_fit": minimum_fit,
    })["selected"]


def test_threshold_truth_table():
    levels = ("excellent", "good", "challenging", "poor")
    assert [level for level in levels if includes("any", level)] == list(levels)
    assert [level for level in levels if includes("challengingOrBetter", level)] == list(levels[:3])
    assert [level for level in levels if includes("goodOrBetter", level)] == list(levels[:2])
    assert [level for level in levels if includes("excellentOnly", level)] == ["excellent"]


def test_bypasses_and_active_missing_fit():
    rows = [row("moon", "preferred"), row("m77")]
    assert [item["index"] for item in evaluate(rows, [], minimum_fit="any")] == [0, 1]
    assert [item["index"] for item in evaluate(
        rows, [], has_saved_inventory=False, minimum_fit="excellentOnly"
    )] == [0, 1]
    assert evaluate(rows, [], minimum_fit="challengingOrBetter") == []


def test_duplicate_identity_and_order_are_preserved():
    rows = [
        Candidate("m31", False, requirement("preferred")),
        Candidate("m31", False, requirement("challenging")),
        Candidate("moon", False, requirement("preferred")),
    ]
    result = selected(rows, [("0", "nakedEye", None, None)], True, "challengingOrBetter")
    assert [(item.index, item.key) for item in result] == [(0, "m31"), (1, "m31"), (2, "moon")]


@pytest.mark.parametrize("field,value", [
    ("has_saved_inventory", 1),
    ("minimum_fit", "good"),
])
def test_invalid_enums_and_boolean_fail_closed(field, value):
    document = {
        "candidates": [], "capabilities": [],
        "has_saved_inventory": True, "minimum_fit": "any",
    }
    document[field] = value
    with pytest.raises(ValidationError, match=f"invalid {CAPABILITY_ID} input"):
        filter_recommendations_by_equipment(document)


def test_unknown_fields_fail_closed_even_during_bypass():
    bad = row("moon", "preferred")
    bad["score"] = 90
    with pytest.raises(ValidationError, match=f"invalid {CAPABILITY_ID} input"):
        evaluate([bad], [], minimum_fit="any")


def test_unknown_top_requirement_and_capability_fields_fail_closed():
    base = {
        "candidates": [row("moon", "preferred")],
        "capabilities": [],
        "has_saved_inventory": True,
        "minimum_fit": "any",
    }
    for document in (
        {**base, "limit": 5},
        {**base, "candidates": [{**base["candidates"][0], "requirement": {
            **base["candidates"][0]["requirement"], "display_name": "Moon"
        }}]},
        {**base, "capabilities": [{
            "key": "scope", "type": "visualTelescope",
            "aperture_mm": 100, "magnification": None, "display_name": "Scope"
        }]},
    ):
        with pytest.raises(ValidationError, match=f"invalid {CAPABILITY_ID} input"):
            filter_recommendations_by_equipment(document)


@pytest.mark.parametrize("invalid", [float("nan"), float("inf"), -float("inf")])
def test_nonfinite_capability_measurements_fail_closed(invalid):
    with pytest.raises(ValidationError, match=f"invalid {CAPABILITY_ID} input"):
        evaluate([], [{
            "key": "scope", "type": "visualTelescope",
            "aperture_mm": invalid, "magnification": None,
        }], minimum_fit="any")


def test_caps_are_checked_before_iteration():
    with pytest.raises(SampleCapError, match="candidate-row cap"):
        evaluate([None] * (MAX_CANDIDATE_COUNT + 1), [], minimum_fit="any")
    with pytest.raises(SampleCapError, match="capability-row cap"):
        evaluate([], [None] * (MAX_CAPABILITY_COUNT + 1), minimum_fit="any")
