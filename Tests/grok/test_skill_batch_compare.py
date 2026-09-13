from pathlib import Path


SKILL = Path(__file__).resolve().parents[2] / ".grok" / "skills" / "astronomer"


def test_named_place_workflow_and_presentation_boundaries():
    guidance = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    reference = (SKILL / "references" / "operations.md").read_text(encoding="utf-8")
    runner = (SKILL / "scripts" / "astro.py").read_text(encoding="utf-8")
    assert "agent.batch_compare" in guidance and "agent.batch_compare" in reference
    assert '"agent.batch_compare"' in runner
    assert "at most 8 destinations" in guidance
    assert "deduplicate" in guidance
    assert "never Astro score inputs" in guidance
    assert "Engine order" in guidance
    assert "Do not lead with raw coordinates" in guidance
    assert "Official evidence of closure" in guidance
    assert "Unknown access remains explicitly unknown" in guidance
    assert "do not substitute\narbitrary grid coordinates" in guidance
    assert "do not claim native map cards" in guidance
    assert "straight-line" in guidance
