from __future__ import annotations

from astro_engine.contracts import engine_semver
from astro_engine.observing_quality import CAPABILITY_ID, assess_observing_quality
from astro_engine.semver import satisfies

from support import (
    assert_engine_applies,
    compare_observing_quality_result,
    iter_oq_fixtures,
    load_policy_fields,
)


def test_engine_semver_is_0_1_0() -> None:
    assert engine_semver() == "0.1.0"


def test_f2_helper_reads_oq_policy_fields_from_contract() -> None:
    oq = load_policy_fields("observing_quality")
    assert oq["score"] == "exact"
    assert oq["light_pollution"] == "null_or_object"
    assert oq["light_pollution.base_penalty"] == "abs_1e9"
    assert oq["light_pollution.applied_penalty"] == "abs_1e9"
    anchor = load_policy_fields("observing_quality_anchor")
    assert anchor["light_pollution.base_penalty"] == "abs_1e12"
    assert anchor["light_pollution.modeled_zenith_sky_brightness"] == "exact"


def test_all_contract_fixtures() -> None:
    fixtures = list(iter_oq_fixtures())
    assert len(fixtures) == 14
    version = engine_semver()
    assert version == "0.1.0"
    for fixture in fixtures:
        assert fixture["meta"]["capability"] == CAPABILITY_ID
        assert fixture["meta"]["origin"] == "manual"
        assert_engine_applies(version, fixture)
        assert satisfies(version, fixture["meta"]["engine_semver"])
        expected = fixture["expected"]
        assert "engine_semver" not in expected
        assert expected["ok"] is True
        assert expected["capability"] == CAPABILITY_ID
        injected = fixture["input"]["injected"]
        actual = assess_observing_quality(
            injected["night_conditions_score"],
            injected.get("modeled_zenith_sky_brightness"),
        )
        compare_observing_quality_result(
            actual,
            expected["result"],
            policy_id=fixture["meta"]["equality"],
        )
