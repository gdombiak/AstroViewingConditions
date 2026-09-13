from pathlib import Path


SKILL = Path(__file__).resolve().parents[2] / ".grok" / "skills" / "astronomer"


def test_skill_uses_authoritative_advisory_and_forbids_recalculation():
    guidance = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    reference = (SKILL / "references" / "operations.md").read_text(encoding="utf-8")
    assert "night_conditions.cloud_advisory" in guidance
    assert "early_heavy" in guidance
    assert "late_heavy" in guidance
    assert "intermittent_heavy" in guidance
    assert "do not\ninfer a timing recommendation" in guidance
    assert "Do not infer eligibility from `cloud_timing` alone" in guidance
    assert "reclassify hourly cloud rows" in guidance
    assert "invent the heavy-cloud interval's clock times" in guidance
    assert "`best_window` may be reported as its own authoritative fact" in guidance
    assert "Preserve degraded and stale-provider caveats" in guidance
    assert "cloud_advisory" in reference
    assert "do not recreate eligibility" in reference
