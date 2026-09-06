"""Hand-selected semantic cases, deliberately without numeric output goldens."""
import json
from astro_engine.contracts import contracts_root
from astro_engine.astronomy import instant

SUN_FIELDS = ('sunset', 'civil_twilight_end', 'nautical_twilight_end',
              'astronomical_twilight_end', 'astronomical_twilight_begin',
              'nautical_twilight_begin', 'civil_twilight_begin', 'sunrise')


def cases():
    return json.loads((contracts_root() / 'fixtures/astronomy/cases.json').read_text())


def assert_semantics(case, result):
    input = case['input']['injected']
    semantic = case['semantics']
    if case['capability'] == 'astronomy.sun_events':
        assert set(result) == set(SUN_FIELDS) | {'start', 'end', 'astronomical_night_start', 'astronomical_night_end'}
        assert result['start'] == input['start'] and result['end'] == input['end']
        assert result['astronomical_night_start'] == result['astronomical_twilight_end']
        assert result['astronomical_night_end'] == result['astronomical_twilight_begin']
        for field in SUN_FIELDS:
            if result[field] is not None:
                assert instant(input['start']) <= instant(result[field]) < instant(input['end'])
        if semantic == 'complete_night':
            values = [result[key] for key in SUN_FIELDS]
            assert all(v is not None for v in values)
            assert values == sorted(values)
        if semantic == 'no_events':
            assert all(result[key] is None for key in SUN_FIELDS)
        if semantic == 'no_visual':
            assert result['sunrise'] is None and result['sunset'] is None
            assert all(result[key] is not None for key in SUN_FIELDS if key not in ('sunrise', 'sunset'))
        if semantic == 'no_astronomical':
            assert result['astronomical_night_start'] is None and result['astronomical_night_end'] is None
            assert result['sunrise'] is not None and result['sunset'] is not None
        return
    samples = [result] if case['capability'] == 'astronomy.moon_info' else result['samples']
    times = [input['time']] if 'time' in input else input['times']
    assert [s['time'] for s in samples] == times
    if 'times' in input:
        assert set(result) == {'samples'}
    for sample in samples:
        assert set(sample) == {'time', 'altitude', 'illumination'}
        assert -90 <= sample['altitude'] <= 90.01
        assert type(sample['illumination']) is int and 0 <= sample['illumination'] <= 100
    if semantic.startswith('high'):
        assert result['illumination'] >= 98  # selected near the March 2024 full Moon
        assert (result['altitude'] > 0) == semantic.endswith('above')
    if semantic == 'low':
        assert result['illumination'] <= 1  # April 8, 2024 solar eclipse / new Moon
    if semantic == 'mid':
        assert 45 <= result['illumination'] <= 55
    if semantic == 'crosses_horizon':
        assert min(s['altitude'] for s in samples) < 0 < max(s['altitude'] for s in samples)
