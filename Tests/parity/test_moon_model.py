"""Adversarial SunCalc port checks, including rejected Skyfield counterexamples."""
from datetime import datetime, timedelta, timezone
import json

import pytest

from test_moon import _python, _swift, _skyfield_reference, _composed, _sweep_nights
from compare import compare_value, load_policy_fields


def _cases():
    for day in ('2000-01-02', '2024-04-08', '2026-03-01', '2049-12-30'):
        for latitude, longitude in ((90, 0), (-90, 0), (80, 179.9), (-80, -179.9),
                                    (66.5, 20), (-66.5, 20), (0, 0), (40.7, -74), (-33.87, 151.21)):
            start = datetime.fromisoformat(day).replace(tzinfo=timezone.utc)
            for duration in (-3600, 0, 93600):
                yield dict(latitude=latitude, longitude=longitude,
                           night_start=start.strftime('%Y-%m-%dT%H:%M:%SZ'),
                           night_end=(start + timedelta(seconds=duration)).strftime('%Y-%m-%dT%H:%M:%SZ'))
    for latitude, longitude, start, end in _sweep_nights():
        yield dict(latitude=latitude, longitude=longitude, night_start=start, night_end=end)
    # Two near-zenith geometries, one from each model; no coordinate-derived expected values.
    for latitude, longitude in ((20.517045369405356, -26.523419481713518),
                                (20.531236821419593, -26.48487145935825)):
        for offset in (-0.001, 0, 0.001):
            yield dict(latitude=latitude + offset, longitude=longitude,
                       night_start='2026-03-01T00:00:00Z', night_end='2026-03-01T00:00:00Z')
    # The overlapping hourly quadratics can discover the same event at different
    # offsets depending on the limit; exercise each second around that boundary.
    for second in range(25, 50):
        yield dict(latitude=40.7, longitude=-74, night_start='2026-08-29T00:00:00Z',
                   night_end=f'2026-08-29T11:46:{second:02d}Z')
    # New-Moon phase wrap and north-azimuth wrap around a transit.
    for minute in range(0, 180, 3):
        start = datetime(2024, 4, 8, 17, tzinfo=timezone.utc) + timedelta(minutes=minute)
        yield dict(latitude=0, longitude=0, night_start=start.strftime('%Y-%m-%dT%H:%M:%SZ'),
                   night_end=start.strftime('%Y-%m-%dT%H:%M:%SZ'))
    yield dict(latitude=40.7, longitude=-74, night_start='2049-12-31T23:59:59Z',
               night_end='2049-12-31T23:59:59Z', sample_interval_seconds=93600)
    yield dict(latitude=51.5, longitude=0, night_start='2026-03-01T00:00:00Z',
               night_end='2026-03-01T01:01:01Z', sample_interval_seconds=137)


def test_production_model_port_adversarial_sweep(tmp_path):
    worst = dict(altitude=0.0, azimuth=0.0, phase=0.0, event_seconds=0.0, illumination=0)
    count = rows = 0
    fields = load_policy_fields('astronomy_moon_observation')
    for injected in _cases():
        swift = _swift('astronomy.moon_observation', injected, tmp_path)
        python = _python('astronomy.moon_observation', injected)
        compare_value(swift, python, fields, path='')
        compare_value(python, swift, fields, path='')
        phase = abs(swift['phase'] - python['phase'])
        worst['phase'] = max(worst['phase'], min(phase, 1 - phase))
        worst['illumination'] = max(worst['illumination'], abs(swift['illumination'] - python['illumination']))
        for field in ('rise', 'set'):
            assert (swift[field] is None) == (python[field] is None), injected
            if swift[field] is not None:
                delta = abs((datetime.fromisoformat(swift[field]) - datetime.fromisoformat(python[field])).total_seconds())
                worst['event_seconds'] = max(worst['event_seconds'], delta)
        for a, b in zip(swift['samples'], python['samples']):
            worst['altitude'] = max(worst['altitude'], abs(a['altitude'] - b['altitude']))
            azimuth = abs(a['azimuth'] - b['azimuth']) % 360
            worst['azimuth'] = max(worst['azimuth'], min(azimuth, 360 - azimuth))
            rows += 1
        count += 1
    # Stronger than the public maximum tolerances: a regression to a different
    # ephemeris must fail even if ordinary cases happen to fit the old policy.
    assert worst['altitude'] < 1e-8
    assert worst['azimuth'] < 1e-6
    assert worst['phase'] < 1e-12
    assert worst['event_seconds'] == 0
    assert worst['illumination'] == 0
    print(f'\n[moon model] {count} intervals, {rows} samples; worst deltas {json.dumps(worst, sort_keys=True)}')


def test_same_model_composition_keeps_all_decisions(tmp_path):
    for latitude, longitude, start, end in _sweep_nights():
        _, swift = _composed(_swift, latitude, longitude, start, end, tmp_path)
        _, python = _composed(_python, latitude, longitude, start, end, tmp_path)
        compare_value(swift, python, load_policy_fields('moon_recommendation'), path='')


@pytest.mark.parametrize('injected,field', [
    (dict(latitude=20.517045369405356, longitude=-26.523419481713518,
          night_start='2026-03-01T00:00:00Z', night_end='2026-03-01T00:00:00Z'), 'azimuth'),
    (dict(latitude=40.7, longitude=-74, night_start='2026-08-29T00:00:00Z',
          night_end='2026-08-29T11:46:30Z'), 'set'),
])
def test_rejected_skyfield_model_breaks_observation_contract(injected, field, tmp_path):
    swift = _swift('astronomy.moon_observation', injected, tmp_path)
    reference = _skyfield_reference('astronomy.moon_observation', injected)
    with pytest.raises(AssertionError):
        compare_value(swift, reference, load_policy_fields('astronomy_moon_observation'), path='')
    if field == 'set':
        assert swift['set'] is not None and reference['set'] is None
        assert swift['always_up'] is False and reference['always_up'] is True
    else:
        difference = abs(swift['samples'][0]['azimuth'] - reference['samples'][0]['azimuth'])
        assert min(difference, 360 - difference) > 100


@pytest.mark.parametrize('a,b,passes', [
    ('2050-01-01T00:00:00Z', '2050-01-01T00:01:00Z', True),
    ('2050-01-01T00:00:00Z', '2050-01-01T00:01:01Z', False),
    ('2050-01-02T01:59:58Z', '2050-01-02T01:59:58Z', True),
    ('2050-01-02T01:59:59Z', '2050-01-02T01:59:59Z', False),
    ('1999-12-31T23:59:59Z', '1999-12-31T23:59:59Z', False),
    ('2026-02-30T00:00:00Z', '2026-02-30T00:00:00Z', False),
    ('2050-01-01T00:00:00Z', None, False),
])
def test_moon_event_comparator_bounds(a, b, passes):
    for actual, expected in ((a, b), (b, a)):
        if passes:
            compare_value(actual, expected, {'set': 'null_or_moon_seconds_60'}, path='set')
        else:
            with pytest.raises(AssertionError):
                compare_value(actual, expected, {'set': 'null_or_moon_seconds_60'}, path='set')


@pytest.mark.parametrize('spec,value', [('cyclic_phase_abs_0_002', 1.5),
                                      ('cyclic_azimuth_abs_2', 540.0)])
def test_cyclic_comparison_rejects_out_of_range_equivalents(spec, value):
    with pytest.raises(AssertionError):
        compare_value(value, value, {'angle': spec}, path='angle')
