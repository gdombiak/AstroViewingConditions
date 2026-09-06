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
    if case['capability'] == 'astronomy.moon_observation':
        assert_moon_observation(case, result)
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


MOON_OBSERVATION_FIELDS = {'night_start', 'night_end', 'phase', 'illumination', 'rise', 'set',
                           'always_up', 'always_down', 'samples'}


def assert_moon_observation(case, result):
    """Structure, cadence and per-case semantics, without any numeric goldens."""
    input = case['input']['injected']
    start, end = instant(input['night_start']), instant(input['night_end'])
    cadence = input.get('sample_interval_seconds', 1800)
    assert set(result) == MOON_OBSERVATION_FIELDS
    assert result['night_start'] == input['night_start'] and result['night_end'] == input['night_end']
    assert 0 <= result['phase'] <= 1
    assert type(result['illumination']) is int and 0 <= result['illumination'] <= 100
    assert type(result['always_up']) is bool and type(result['always_down']) is bool
    assert not (result['always_up'] and result['always_down'])

    samples = result['samples']
    assert len(samples) == case['sample_count']
    times = [instant(s['time']) for s in samples]
    for sample in samples:
        assert set(sample) == {'time', 'altitude', 'azimuth'}
        assert -90 <= sample['altitude'] <= 90.01
        assert 0 <= sample['azimuth'] < 360
    if end < start:
        assert samples == []
    else:
        assert times[0] == start and times[-1] == end
        assert all(a < b for a, b in zip(times, times[1:]))
        # Repeated addition of the cadence, plus an explicit end sample when the
        # loop did not already land on the interval end.
        for index, time in enumerate(times[:-1]):
            assert (time - start).total_seconds() == index * cadence
    limit = max((end - start).total_seconds(), cadence)
    for field in ('rise', 'set'):
        if result[field] is not None:
            assert 0 <= (instant(result[field]) - start).total_seconds() < limit
    # A found event clears the opposite always-flag.
    if result['rise'] is not None:
        assert not result['always_down']
    if result['set'] is not None:
        assert not result['always_up']

    semantic = case['semantics']
    if semantic == 'always_up':
        assert result['always_up'] and result['set'] is None
        assert all(s['altitude'] > 0 for s in samples)
    if semantic == 'always_down':
        assert result['always_down'] and result['rise'] is None
        assert all(s['altitude'] < 0 for s in samples)
    if semantic == 'rises':
        assert result['rise'] is not None
        assert min(s['altitude'] for s in samples) < 0 < max(s['altitude'] for s in samples)
    if semantic == 'sets':
        assert result['set'] is not None
    if semantic == 'new_moon':
        assert result['illumination'] <= 1  # April 8, 2024 solar eclipse / new Moon
        assert min(result['phase'], 1 - result['phase']) <= 0.04
    if semantic == 'no_samples':
        assert samples == []
