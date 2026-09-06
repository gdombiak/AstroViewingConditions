"""Manual endpoint decisions and strict input failures, independent of Swift."""
import json

import pytest

from astro_engine._capability import evaluate_capability
from astro_engine.contracts import contracts_root
from astro_engine.errors import ValidationError
from astro_engine.observing_window import CAPABILITY_ID, select_observing_window

FIXTURES = sorted((contracts_root() / "fixtures/capabilities/observing-window").iterdir())


@pytest.mark.parametrize("directory", FIXTURES, ids=lambda p: p.name)
def test_manual_fixtures(directory):
    document = json.loads((directory / "input.json").read_text())
    expected = json.loads((directory / "expected.json").read_text())
    if expected["ok"]:
        assert evaluate_capability(CAPABILITY_ID, document) == expected["result"]
    else:
        with pytest.raises(ValidationError) as error:
            evaluate_capability(CAPABILITY_ID, document)
        assert str(error.value) == expected["error"]["message"]


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf")])
def test_rejects_nonfinite_numbers(value):
    for facts in ({"hourly_ratings": [{"time": "2026-09-06T01:00:00Z", "score": value}]},
                  {"hourly_ratings": [], "good_rating_threshold": value}):
        with pytest.raises(ValidationError, match="invalid observing_window.select input"):
            select_observing_window(facts)


def test_analysis_composes_without_changing_analysis_dto():
    directory = contracts_root() / "fixtures/capabilities/night-conditions/four-clear-hours-v1"
    document = json.loads((directory / "input.json").read_text())
    analysis = evaluate_capability("night_conditions.analyze", document)
    assert "best_window" not in analysis
    result = select_observing_window({"hourly_ratings": [
        {"time": row["time"], "score": row["score"]} for row in analysis["hourly_ratings"]]})
    assert result == {"best_window": {"start": analysis["night_start"], "end": analysis["night_end"]}}
    assert result["best_window"] != document["injected"]["night_window"]
