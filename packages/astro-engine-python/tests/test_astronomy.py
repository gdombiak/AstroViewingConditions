from __future__ import annotations
import builtins
import json
import socket
import hashlib
import pytest
from astro_engine._capability import CapabilityHost, evaluate_capability
from astro_engine.astronomy import CAPABILITY_IDS, SkyfieldAstronomy, default_ephemeris_path, instant
from astro_engine.errors import ValidationError
from astronomy_cases import cases, assert_semantics


@pytest.mark.parametrize('case', cases(), ids=lambda c: c['id'])
def test_astronomy_offline(case, monkeypatch):
    def blocked(*a, **kw): raise AssertionError('astronomy attempted network access')
    class BlockedSocket(socket.socket):
        def __new__(cls, *args, **kwargs):
            raise AssertionError('astronomy attempted network access')
    monkeypatch.setattr(socket, 'socket', BlockedSocket)
    monkeypatch.setattr(socket, 'create_connection', blocked)
    from skyfield.iokit import Loader
    monkeypatch.setattr(Loader, 'download', blocked)
    assert_semantics(case, evaluate_capability(case['capability'], case['input']))


@pytest.mark.parametrize('case', cases(), ids=lambda c: c['id'])
def test_astronomy_public_cli(case, monkeypatch, capsys, tmp_path):
    import astro_engine.cli as cli
    path = tmp_path / 'input.json'
    path.write_text(json.dumps(case['input']))
    def blocked(*a, **kw): raise AssertionError('CLI attempted network access')
    class BlockedSocket(socket.socket):
        def __new__(cls, *args, **kwargs):
            raise AssertionError('astronomy attempted network access')
    monkeypatch.setattr(socket, 'socket', BlockedSocket)
    assert cli.main([case['capability'], '--input', str(path)]) == 0
    captured = capsys.readouterr()
    assert captured.err == ''
    envelope = json.loads(captured.out)
    assert envelope['engine_semver'] == '1.0.0' and envelope['ok'] is True
    assert_semantics(case, envelope['result'])


@pytest.mark.parametrize('value', ['2024-02-30T00:00:00Z', '2023-02-29T00:00:00Z',
    '2024-01-01T24:00:00Z', '2024-01-01T00:00:60Z', '2024-01-01T00:00:00+00:00',
    '2024-01-01T00:00:00.0Z', '1999-12-31T23:59:59Z', '2050-01-01T00:00:00Z', None, True])
def test_astronomy_invalid_time(value):
    with pytest.raises(ValidationError):
        evaluate_capability(CAPABILITY_IDS[1], {'injected': dict(latitude=0, longitude=0, time=value)})


def test_astronomy_valid_leap_day():
    assert instant('2024-02-29T00:00:00Z').day == 29


@pytest.mark.parametrize('key,value', [('latitude', True), ('latitude', 91), ('longitude', -181),
    ('latitude', float('nan')), ('longitude', float('inf')), ('time_zone', 'UTC'), ('elevation', 1),
    ('ephemeris_path', '/tmp/anything')])
def test_astronomy_invalid_facts(key, value):
    facts = dict(latitude=0, longitude=0, time='2024-01-01T00:00:00Z')
    facts[key] = value
    with pytest.raises(ValidationError): evaluate_capability(CAPABILITY_IDS[1], {'injected': facts})


@pytest.mark.parametrize('times', [None, {}, ['2024-01-01T00:00:00Z'] * 2,
    ['2024-01-02T00:00:00Z', '2024-01-01T00:00:00Z'], ['2024-01-01T00:00:00Z'] * 50,
    ['2024-01-01T00:00:00Z', '2024-01-03T00:00:01Z']])
def test_astronomy_invalid_series(times):
    with pytest.raises(ValidationError):
        evaluate_capability(CAPABILITY_IDS[2], {'injected': dict(latitude=0, longitude=0, times=times)})


@pytest.mark.parametrize('end', ['2024-01-01T00:00:00Z', '2023-12-31T23:59:59Z', '2024-01-02T02:00:01Z'])
def test_astronomy_invalid_sun_interval(end):
    with pytest.raises(ValidationError):
        evaluate_capability(CAPABILITY_IDS[0], {'injected': dict(latitude=0, longitude=0, start='2024-01-01T00:00:00Z', end=end)})


def test_astronomy_host_resource_missing_corrupt_and_local(tmp_path, monkeypatch):
    case = next(c for c in cases() if c['id'] == 'full-above')
    good = evaluate_capability(case['capability'], case['input'])
    path = default_ephemeris_path()
    assert path.is_file() and path.stat().st_size == 16788480
    assert hashlib.sha256(path.read_bytes()).hexdigest() == 'a20a7139da04cbc462454634918e9a9ca69127044e2cc9d4f9c16e238d2deedc'
    assert evaluate_capability(case['capability'], case['input'], host=CapabilityHost(ephemeris_path=path)) == good
    missing = tmp_path / 'missing.bsp'
    with pytest.raises(RuntimeError):
        evaluate_capability(case['capability'], case['input'], host=CapabilityHost(ephemeris_path=missing))
    missing.write_bytes(b'not an ephemeris')
    with pytest.raises((ValueError, OSError)):
        evaluate_capability(case['capability'], case['input'], host=CapabilityHost(ephemeris_path=missing))


def test_astronomy_cli_missing_override_is_engine_failure(tmp_path, monkeypatch, capsys):
    import astro_engine.cli as cli
    case = next(c for c in cases() if c['id'] == 'full-above')
    path = tmp_path / 'input.json'; path.write_text(json.dumps(case['input']))
    monkeypatch.setenv('ASTRO_ENGINE_EPHEMERIS_PATH', str(tmp_path / 'missing.bsp'))
    assert cli.main([case['capability'], '--input', str(path)]) == 1
    assert json.loads(capsys.readouterr().out)['error']['code'] == 'engine_failure'


def test_deterministic_scoring_never_invokes_live_astronomy(monkeypatch):
    from fixtures import iter_parity_fixtures
    from compare import compare_envelope
    from python_eval import python_envelope
    def blocked(*a, **kw): raise AssertionError('deterministic scoring called live astronomy')
    monkeypatch.setattr(SkyfieldAstronomy, '__init__', blocked)
    original_import = builtins.__import__
    def guarded(name, *a, **kw):
        assert not name.startswith(('skyfield', 'astro_engine.astronomy')), name
        return original_import(name, *a, **kw)
    monkeypatch.setattr(builtins, '__import__', guarded)
    counts = dict.fromkeys(('night_conditions.analyze', 'night_conditions.score', 'targets.recommend'), 0)
    for fixture in iter_parity_fixtures():
        capability = fixture['meta']['capability']
        if capability not in counts: continue
        actual = python_envelope(capability, fixture["input"])
        compare_envelope(actual, fixture['expected'], policy_id=fixture['meta']['equality'])
        counts[capability] += 1
    assert all(count > 0 for count in counts.values())
