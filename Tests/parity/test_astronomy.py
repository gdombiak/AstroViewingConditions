"""Live comparisons are separate from frozen deterministic expected.json fixtures."""
import copy
import json
import subprocess
import pytest
from astro_engine._capability import evaluate_capability
from astro_engine.contracts import engine_semver
from astro_engine.semver import satisfies
from astronomy_cases import cases, assert_semantics
from compare import compare_value, load_policy_fields
from swift_eval import ensure_eval_binary


@pytest.mark.parametrize('case', cases(), ids=lambda c: c['id'])
def test_live_astronomy_tolerances(case):
    assert satisfies(engine_semver(), case['engine_semver'])
    result = subprocess.run([str(ensure_eval_binary()), case['capability'], '--input', '-'],
                            input=json.dumps(case['input']), text=True, capture_output=True)
    assert result.returncode == 0, result.stderr + result.stdout
    envelope = json.loads(result.stdout)
    assert envelope['ok'] is True
    assert envelope['capability'] == case['capability']
    assert satisfies(envelope['engine_semver'], case['engine_semver'])
    swift = envelope['result']
    python = evaluate_capability(case['capability'], case['input'])
    assert_semantics(case, swift)
    assert_semantics(case, python)
    fields = load_policy_fields(case['equality'])
    compare_value(swift, python, fields, path='')
    compare_value(python, swift, fields, path='')
    if case['id'] == 'quarter-moon':
        # Coverage of the current library pair's nonzero tolerance, not a numeric golden.
        assert fields['illumination'] == 'integer_abs_1'
        assert abs(swift['illumination'] - python['illumination']) == 1


@pytest.mark.parametrize('field,spec,a,b,passes', [
    ('event', 'null_or_seconds_60', None, None, True),
    ('event', 'null_or_seconds_60', None, '2024-01-01T00:00:00Z', False),
    ('event', 'null_or_seconds_60', '2024-01-01T00:00:00Z', '2024-01-01T00:01:00Z', True),
    ('event', 'null_or_seconds_60', '2024-01-01T00:00:00Z', '2024-01-01T00:01:01Z', False),
    ('altitude', 'abs_0_5', -0.25, 0.25, True),
    ('altitude', 'abs_0_5', -0.25, 0.251, False),
    ('altitude', 'abs_0_5', None, 0, False),
    ('illumination', 'integer_abs_1', 49, 50, True),
    ('illumination', 'integer_abs_1', 49, 51, False),
    ('illumination', 'integer_abs_1', True, 1, False),
])
def test_symmetric_field_boundaries(field, spec, a, b, passes):
    for left, right in [(a, b), (b, a)]:
        if passes:
            compare_value(left, right, {field: spec}, path=field)
        else:
            with pytest.raises(AssertionError):
                compare_value(left, right, {field: spec}, path=field)


def test_series_structure_fails_closed():
    fields = load_policy_fields('astronomy_moon_series')
    original = {'samples': [{'time': '2024-01-01T00:00:00Z', 'altitude': 1, 'illumination': 50}]}
    for change in ('missing', 'extra', 'time', 'length'):
        other = copy.deepcopy(original)
        if change == 'missing': del other['samples'][0]['altitude']
        if change == 'extra': other['samples'][0]['emoji'] = 'moon'
        if change == 'time': other['samples'][0]['time'] = '2024-01-01T01:00:00Z'
        if change == 'length': other['samples'] = []
        for a, b in [(original, other), (other, original)]:
            with pytest.raises(AssertionError): compare_value(a, b, fields, path='')


def test_swift_astronomy_does_not_use_process_timezone():
    import os
    for case in [cases()[0], next(c for c in cases() if c['id'] == 'full-above')]:
        results = []
        for zone in ['UTC', 'Pacific/Kiritimati', 'America/Los_Angeles']:
            result = subprocess.run([str(ensure_eval_binary()), case['capability'], '--input', '-'],
                                    input=json.dumps(case['input']), text=True, capture_output=True,
                                    env={**os.environ, 'TZ': zone})
            assert result.returncode == 0, result.stderr
            results.append(json.loads(result.stdout)['result'])
        assert results[0] == results[1] == results[2]


@pytest.mark.parametrize('document', [
    {'capability': None, 'injected': {'latitude': 0, 'longitude': 0, 'times': []}},
    {'injected': {'latitude': 0, 'longitude': 0, 'times': []}, 'time_zone': 'UTC'},
    {'injected': {'latitude': 0, 'longitude': 0, 'times': [], 'ephemeris_path': '/tmp/file'}},
])
def test_astronomy_envelope_validation_in_both_engines(document):
    from astro_engine.errors import ValidationError
    capability = 'astronomy.moon_series'
    with pytest.raises(ValidationError): evaluate_capability(capability, document)
    result = subprocess.run([str(ensure_eval_binary()), capability, '--input', '-'],
                            input=json.dumps(document), text=True, capture_output=True)
    assert result.returncode == 2
    assert json.loads(result.stdout)['error']['code'] == 'validation'
