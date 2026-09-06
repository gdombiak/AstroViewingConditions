"""Frozen production cases plus resolver/evaluator composition and data ownership."""
import json
import math

import pytest

from astro_engine._capability import evaluate_capability
from astro_engine.contracts import contracts_root, load_canonical_data
from astro_engine.equipment import match_equipment
from astro_engine.errors import ValidationError
from astro_engine.target_metadata import evaluate_metadata, solar_system_candidates

FIXTURES = sorted((contracts_root() / 'fixtures/capabilities/target-metadata').iterdir())


@pytest.mark.parametrize('directory', FIXTURES, ids=lambda p: p.name)
def test_manual_fixtures(directory):
    document = json.loads((directory / 'input.json').read_text())
    expected = json.loads((directory / 'expected.json').read_text())
    if expected['ok']:
        assert evaluate_capability(document['capability'], document) == expected['result']
    else:
        with pytest.raises(ValidationError, match=expected['error']['message']):
            evaluate_capability(document['capability'], document)


@pytest.mark.parametrize('aperture,level', [(30, 'good'), (50, 'excellent')])
def test_m77_composes_with_match_without_metadata_lookup(aperture, level):
    resolved = evaluate_metadata('targets.requirements', {'id': 'm77'})
    result = match_equipment({**resolved, 'capabilities': [
        {'key': 'seestar', 'type': 'smartTelescope', 'aperture_mm': aperture},
    ]})
    assert result['match']['level'] == level
    assert result['match']['mode'] == 'electronicallyAssisted'


@pytest.mark.parametrize('value', [math.nan, math.inf, -math.inf])
def test_nonfinite_sensitivity_input_rejected(value):
    with pytest.raises(ValidationError):
        evaluate_metadata('targets.moon_sensitivity', {'object_type': 'galaxy', 'surface_brightness': value})


def test_canonical_data_available_without_package_copies():
    rows = solar_system_candidates()
    assert [r['id'] for r in rows] == ['moon', 'venus', 'mars', 'jupiter', 'saturn']
    data = load_canonical_data('catalog/target-requirements.json')
    assert len(data['overrides']) == 20
    # Every canonical requirement is directly accepted by the existing evaluator.
    for row in [data['default'], *data['fallbacks'].values(), *data['overrides'].values()]:
        assert match_equipment({'requirement': row, 'capabilities': []}) == {'match': None}
    rows[0]['id'] = 'changed'
    assert solar_system_candidates()[0]['id'] == 'moon'
