"""Hand-authored rules are the oracle for each independent implementation."""
import json
import pytest
from astro_engine.contracts import contracts_root
from astro_engine._capability import evaluate_capability
from astro_engine.errors import ValidationError
from astro_engine.equipment import match_equipment

_FIXTURES = sorted(p for name in ("targets-recommend", "equipment-match")
                   for p in (contracts_root() / "fixtures/capabilities" / name).iterdir())


@pytest.mark.parametrize("directory", _FIXTURES, ids=lambda p: f"{p.parent.name}/{p.name}")
def test_phase15_fixtures(directory):
    document = json.loads((directory / "input.json").read_text())
    expected = json.loads((directory / "expected.json").read_text())
    if expected["ok"]:
        assert evaluate_capability(document["capability"], document) == expected["result"]
    else:
        with pytest.raises(ValidationError) as error:
            evaluate_capability(document["capability"], document)
        assert str(error.value) == expected["error"]["message"]


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf"), 1e100])
def test_nonfinite_numbers(value):
    with pytest.raises(ValidationError, match="invalid equipment.match input"):
        match_equipment({"requirement": {}, "capabilities": [{"key": "scope", "type": "visualTelescope", "aperture_mm": value}]})
