from __future__ import annotations

import asyncio
from dataclasses import replace
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import pickle
import subprocess
import sys
import tempfile
import time

import pytest

from astro_host.models import (
    HourlyWeather,
    Location,
    PayloadDiagnostics,
    PayloadState,
    WeatherQuery,
    WeatherSnapshot,
)
from astro_host.weather_cache_file import (
    CACHE_FILENAME,
    FileWeatherCache,
    MAX_ENTRIES,
    default_state_dir,
    default_weather_cache_path,
)


NOW = datetime(2026, 2, 20, 5, tzinfo=timezone.utc)
PROVIDER = "open_meteo"
SRC = Path(__file__).resolve().parents[1] / "src"


def row(hour: int = 8) -> HourlyWeather:
    return HourlyWeather(
        time=datetime(2026, 2, 19, hour, tzinfo=timezone.utc),
        cloud_cover=10,
        humidity=40,
        wind_speed=2.0,
        wind_direction=180,
        temperature=10.0,
        dew_point=4.0,
        visibility=10_000.0,
        low_cloud_cover=5,
        mid_cloud_cover=3,
        high_cloud_cover=2,
        wind_speed_200hpa=30.0,
    )


def snapshot(
    *,
    latitude: float = 34.05,
    days: int = 2,
    past_days: int = 0,
    age: float = 10,
    provider: str = PROVIDER,
    fetched_at: datetime | None = None,
    hourly: tuple[HourlyWeather, ...] | None = None,
    state: PayloadState = PayloadState.COMPLETE,
) -> WeatherSnapshot:
    hours = hourly if hourly is not None else (row(),)
    return WeatherSnapshot(
        query=WeatherQuery(Location(latitude, -118.24), days, past_days),
        provider=provider,
        fetched_at=NOW - timedelta(seconds=age) if fetched_at is None else fetched_at,
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hours,
        diagnostics=PayloadDiagnostics(state, (), len(hours)),
    )


def query(*, latitude: float = 34.05, days: int = 2, past_days: int = 0) -> WeatherQuery:
    return WeatherQuery(Location(latitude, -118.24), days, past_days)


def cache_at(path: Path, *, clock=None) -> FileWeatherCache:
    if clock is None:
        clock = lambda: NOW
    return FileWeatherCache(path, clock=clock)


def put(cache: FileWeatherCache, entry: WeatherSnapshot) -> None:
    asyncio.run(cache.put(entry))


def get(
    cache: FileWeatherCache,
    requested: WeatherQuery | None = None,
    *,
    provider: str = PROVIDER,
) -> WeatherSnapshot | None:
    return asyncio.run(cache.get(
        requested or query(), provider=provider,
    ))


def test_missing_file_is_miss_without_side_effects(tmp_path: Path) -> None:
    path = tmp_path / "nested" / "weather-cache.json"
    store = cache_at(path)
    assert get(store) is None
    assert list(tmp_path.iterdir()) == []
    assert not path.exists()
    assert not path.with_name(path.name + ".lock").exists()


def test_empty_and_invalid_json_are_misses(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    path.write_text("   \n", encoding="utf-8")
    assert get(cache_at(path)) is None
    path.write_text("{not-json", encoding="utf-8")
    assert get(cache_at(path)) is None


def test_truncated_json_is_miss(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    path.write_text('{"schema_version":1,"entries":[', encoding="utf-8")
    assert get(cache_at(path)) is None


def test_unsupported_schema_version_is_preserved(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    original = '{"schema_version":2,"entries":[{"keep":true}]}\n'
    path.write_text(original, encoding="utf-8")
    store = cache_at(path)
    assert get(store) is None
    put(store, snapshot())
    assert path.read_text(encoding="utf-8") == original


def test_schema_version_bool_is_corrupt_and_self_heals(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    path.write_text('{"schema_version":true,"entries":[]}\n', encoding="utf-8")
    store = cache_at(path)
    assert get(store) is None
    put(store, snapshot())
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["schema_version"] == 1
    assert get(store) == snapshot()


def test_truncated_file_self_heals_on_put(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    path.write_text('{"schema_version":1,"entries":[', encoding="utf-8")
    store = cache_at(path)
    put(store, snapshot())
    assert json.loads(path.read_text(encoding="utf-8"))["schema_version"] == 1
    assert get(store) == snapshot()


def test_one_malformed_snapshot_does_not_poison_sibling(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    good = snapshot()
    put(cache_at(path), good)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"].insert(0, {"provider": "open_meteo"})
    path.write_text(json.dumps(document), encoding="utf-8")
    assert get(cache_at(path)) == good


def test_oversized_json_integer_skips_snapshot_not_sibling(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sibling = snapshot(latitude=45.37)
    put(cache_at(path), snapshot())
    put(cache_at(path), sibling)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"][0]["hourly"][0]["wind_speed"] = 10 ** 400
    path.write_text(json.dumps(document), encoding="utf-8")
    store = cache_at(path)
    assert get(store, query()) is None
    assert get(store, query(latitude=45.37)) == sibling


def test_non_utf8_file_self_heals_on_put(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    path.write_bytes(b"\xff\xfe not utf-8 {")
    store = cache_at(path)
    assert get(store) is None
    put(store, snapshot())
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["schema_version"] == 1
    assert get(store) == snapshot()


BOUNDARY_TS = "9999-12-31T23:59:59-23:59"
ENCODE_OVERFLOW_DT = datetime(
    1, 1, 1, tzinfo=timezone(timedelta(hours=23, minutes=59)),
)


def test_boundary_fetched_at_skips_snapshot_not_sibling(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sibling = snapshot(latitude=45.37)
    put(cache_at(path), snapshot())
    put(cache_at(path), sibling)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"][0]["fetched_at"] = BOUNDARY_TS
    path.write_text(json.dumps(document), encoding="utf-8")
    store = cache_at(path)
    assert get(store, query()) is None
    assert get(store, query(latitude=45.37)) == sibling
    extra = snapshot(latitude=40.0)
    put(store, extra)
    assert get(store, query(latitude=45.37)) == sibling
    assert get(store, query(latitude=40.0)) == extra


def test_boundary_hourly_timestamp_skips_snapshot_not_sibling(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sibling = snapshot(latitude=45.37)
    put(cache_at(path), snapshot())
    put(cache_at(path), sibling)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"][0]["hourly"][0]["time"] = BOUNDARY_TS
    path.write_text(json.dumps(document), encoding="utf-8")
    store = cache_at(path)
    assert get(store, query()) is None
    assert get(store, query(latitude=45.37)) == sibling


def test_boundary_timestamp_on_encode_does_not_escape_put(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sibling = snapshot(latitude=45.37)
    put(cache_at(path), sibling)
    put(cache_at(path), snapshot(fetched_at=ENCODE_OVERFLOW_DT))
    assert get(cache_at(path), query(latitude=45.37)) == sibling
    assert get(cache_at(path), query()) is None


def test_malformed_hourly_row_skips_whole_snapshot(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sibling = snapshot(latitude=45.37)
    put(cache_at(path), snapshot())
    put(cache_at(path), sibling)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"][0]["hourly"][0]["humidity"] = True
    path.write_text(json.dumps(document), encoding="utf-8")
    store = cache_at(path)
    assert get(store, query()) is None
    assert get(store, query(latitude=45.37)) == sibling


def test_put_then_new_instance_round_trips(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    entry = snapshot()
    put(cache_at(path), entry)
    assert get(cache_at(path)) == entry


def test_optional_hourly_fields_round_trip_and_omit_none(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sparse = replace(row(), dew_point=None, visibility=None, low_cloud_cover=None)
    entry = snapshot(hourly=(sparse,))
    put(cache_at(path), entry)
    loaded = get(cache_at(path))
    assert loaded == entry
    raw_row = json.loads(path.read_text(encoding="utf-8"))["entries"][0]["hourly"][0]
    assert "dew_point" not in raw_row
    assert "visibility" not in raw_row
    assert "low_cloud_cover" not in raw_row


def test_exact_lat_lon_identity_through_json(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    entry = snapshot(latitude=34.05)
    put(cache_at(path), entry)
    store = cache_at(path)
    assert get(store, query(latitude=34.05)) == entry
    assert get(store, query(latitude=34.06)) is None


def test_richer_forecast_and_past_coverage(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    put(store, snapshot(days=4))
    assert get(store, query(days=2)) is not None
    assert get(store, query(days=5)) is None
    put(store, snapshot(days=2, past_days=0, age=30))
    assert get(store, query(days=2, past_days=1)) is None
    richer = snapshot(days=2, past_days=1, age=20)
    put(store, richer)
    assert get(store, query(days=2, past_days=1)) == richer
    assert get(store, query(days=2, past_days=0)) is not None


def test_past_zero_and_one_coexist_and_later_put_does_not_drop(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    normal = snapshot(past_days=0, age=30)
    richer = snapshot(past_days=1, age=20)
    later = replace(normal, fetched_at=NOW - timedelta(seconds=5))
    put(store, normal)
    put(store, richer)
    put(store, later)
    assert get(store, query(past_days=1)) == richer
    assert get(store, query(past_days=0)) == later


def test_providers_do_not_collide(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    meteo = snapshot()
    other = replace(meteo, provider="other")
    put(store, meteo)
    put(store, other)
    assert get(store, provider=PROVIDER) == meteo
    assert get(store, provider="other") == other


def test_newest_covering_fetched_at_wins(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    older_rich = snapshot(days=4, age=30)
    newer_narrow = snapshot(days=2, age=5)
    put(store, older_rich)
    put(store, newer_narrow)
    assert get(store, query(days=2)) == newer_narrow


def test_parent_created_only_on_put_and_no_leftover_temps(tmp_path: Path) -> None:
    path = tmp_path / "state" / "weather-cache.json"
    store = cache_at(path)
    assert not path.parent.exists()
    put(store, snapshot())
    assert path.exists()
    leftovers = list(path.parent.glob("*.tmp"))
    assert leftovers == []


def test_future_fetched_at_put_is_ignored(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    future = snapshot(fetched_at=NOW + timedelta(hours=1))
    put(store, future)
    assert get(store) is None
    assert list(tmp_path.iterdir()) == []


def test_entry_cap_keeps_newest_and_just_written(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    oldest = snapshot(latitude=1.0, age=1000)
    put(store, oldest)
    for index in range(MAX_ENTRIES):
        put(store, snapshot(latitude=float(index + 2), age=MAX_ENTRIES - index))
    newest = snapshot(latitude=99.0, age=1)
    put(store, newest)
    document = json.loads(path.read_text(encoding="utf-8"))
    assert len(document["entries"]) == MAX_ENTRIES
    assert get(store, query(latitude=1.0)) is None
    assert get(store, query(latitude=99.0)) == newest


def test_empty_hourly_put_creates_no_file(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    empty = replace(
        snapshot(),
        hourly=(),
        diagnostics=PayloadDiagnostics(PayloadState.EMPTY, (), 0),
    )
    put(cache_at(path), empty)
    assert list(tmp_path.iterdir()) == []
    assert get(cache_at(path)) is None


def test_partial_with_rows_round_trips(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    entry = snapshot(state=PayloadState.PARTIAL)
    put(cache_at(path), entry)
    loaded = get(cache_at(path))
    assert loaded == entry
    assert loaded is not None
    assert loaded.diagnostics.state is PayloadState.PARTIAL
    assert loaded.hourly


def test_repeated_asyncio_run_against_same_instance(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    entry = snapshot()
    asyncio.run(store.put(entry))
    assert asyncio.run(store.get(query(), provider=PROVIDER)) == entry


def test_two_async_tasks_on_one_instance_keep_distinct_entries(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    home = snapshot(latitude=34.05)
    hood = snapshot(latitude=45.37)

    async def both() -> None:
        await asyncio.gather(store.put(home), store.put(hood))

    asyncio.run(both())
    assert get(store, query(latitude=34.05)) == home
    assert get(store, query(latitude=45.37)) == hood


def test_two_os_processes_overlap_puts_keep_distinct_entries(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    home = snapshot(latitude=34.05)
    hood = snapshot(latitude=45.37)
    go = tmp_path / "go"
    workers = [
        _start_put_process(tmp_path, path, home, tmp_path / "ready-home", go),
        _start_put_process(tmp_path, path, hood, tmp_path / "ready-hood", go),
    ]
    deadline = time.time() + 15
    while time.time() < deadline:
        if all(flag.exists() for flag in (tmp_path / "ready-home", tmp_path / "ready-hood")):
            break
        time.sleep(0.01)
    else:
        _fail_workers(workers, "workers did not become ready")
    go.write_text("1", encoding="utf-8")
    results = [worker.wait(timeout=15) for worker in workers]
    if results != [0, 0]:
        _fail_workers(workers, f"workers exited {results}")
    store = cache_at(path)
    assert get(store, query(latitude=34.05)) == home
    assert get(store, query(latitude=45.37)) == hood


def test_os_replace_oserror_fails_open_and_does_not_deadlock(
    tmp_path: Path, monkeypatch,
) -> None:
    path = tmp_path / "weather-cache.json"
    store = cache_at(path)
    first = snapshot(latitude=34.05)
    put(store, first)

    def boom(*_args, **_kwargs):
        raise OSError("replace failed")

    monkeypatch.setattr("astro_host.weather_cache_file.os.replace", boom)
    put(store, snapshot(latitude=45.37))
    assert get(store, query(latitude=34.05)) == first
    assert get(store, query(latitude=45.37)) is None


def test_extra_keys_are_ignored(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    put(cache_at(path), snapshot())
    document = json.loads(path.read_text(encoding="utf-8"))
    document["unexpected"] = True
    document["entries"][0]["extra"] = {"nested": 1}
    document["entries"][0]["hourly"][0]["noise"] = "x"
    path.write_text(json.dumps(document), encoding="utf-8")
    assert get(cache_at(path)) == snapshot()


def test_json_bools_on_numeric_fields_skip_snapshot(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    put(cache_at(path), snapshot())
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"][0]["query"]["location"]["latitude"] = True
    path.write_text(json.dumps(document), encoding="utf-8")
    assert get(cache_at(path)) is None


def test_default_state_dir_uses_env_then_home(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("ASTRO_HOST_STATE_DIR", str(tmp_path / "bot-state"))
    assert default_state_dir() == tmp_path / "bot-state"
    assert default_weather_cache_path() == tmp_path / "bot-state" / CACHE_FILENAME
    monkeypatch.delenv("ASTRO_HOST_STATE_DIR")
    monkeypatch.setattr(Path, "home", lambda *args, **kwargs: tmp_path / "home")
    assert default_state_dir() == tmp_path / "home" / ".astro-host"


def test_default_state_dir_falls_back_when_home_raises(monkeypatch) -> None:
    monkeypatch.delenv("ASTRO_HOST_STATE_DIR", raising=False)

    def boom(*_args, **_kwargs):
        raise RuntimeError("no home")

    monkeypatch.setattr(Path, "home", boom)
    assert default_state_dir() == Path(tempfile.gettempdir()) / "astro-host"


def test_clock_rollback_hides_future_and_keeps_older_covering(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    older = snapshot(age=7200, past_days=0)
    richer = snapshot(
        past_days=1,
        fetched_at=NOW + timedelta(minutes=30),
    )
    put(cache_at(path), older)
    put(cache_at(path, clock=lambda: NOW + timedelta(hours=1)), richer)
    rolled = cache_at(path)
    assert get(rolled, query(past_days=0)) == older
    assert get(rolled, query(past_days=1)) is None


def test_naive_fetched_at_put_does_not_escape_or_replace(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    sibling = snapshot(latitude=45.37)
    put(cache_at(path), sibling)
    put(cache_at(path), replace(snapshot(), fetched_at=NOW.replace(tzinfo=None)))
    assert get(cache_at(path), query(latitude=45.37)) == sibling
    assert get(cache_at(path), query()) is None


def test_non_datetime_fetched_at_put_propagates(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    with pytest.raises(AttributeError):
        put(cache_at(path), replace(snapshot(), fetched_at="not-a-datetime"))


def test_invalid_clock_put_propagates(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    entry = snapshot()
    with pytest.raises(AttributeError):
        put(FileWeatherCache(path, clock=lambda: "not-a-datetime"), entry)
    with pytest.raises(TypeError):
        put(FileWeatherCache(path, clock=lambda: NOW.replace(tzinfo=None)), entry)


def test_put_samples_clock_once_so_identity_survives_intra_call_rollback(
    tmp_path: Path,
) -> None:
    path = tmp_path / "weather-cache.json"
    existing = snapshot(age=10)
    put(cache_at(path), existing)
    instants = [NOW, NOW - timedelta(seconds=1)]
    calls = {"n": 0}

    def clock() -> datetime:
        calls["n"] += 1
        return instants[min(calls["n"], len(instants)) - 1]

    replacement = snapshot(age=0)
    put(FileWeatherCache(path, clock=clock), replacement)
    assert calls["n"] == 1
    assert get(cache_at(path)) == replacement


def test_future_exact_identity_put_preserves_prior_entry(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    valid = snapshot(age=10)
    put(cache_at(path), valid)
    put(cache_at(path), snapshot(fetched_at=NOW + timedelta(hours=1)))
    assert get(cache_at(path)) == valid


def test_clock_injection_controls_future_eligibility(tmp_path: Path) -> None:
    path = tmp_path / "weather-cache.json"
    entry = snapshot(fetched_at=NOW)
    put(cache_at(path, clock=lambda: NOW - timedelta(seconds=1)), entry)
    assert get(cache_at(path, clock=lambda: NOW - timedelta(seconds=1))) is None
    assert not path.exists()
    put(cache_at(path, clock=lambda: NOW), entry)
    assert get(cache_at(path, clock=lambda: NOW)) == entry


def _start_put_process(
    tmp_path: Path,
    cache_path: Path,
    entry: WeatherSnapshot,
    ready: Path,
    go: Path,
) -> subprocess.Popen[bytes]:
    payload = tmp_path / f"{entry.query.location.latitude}.pkl"
    payload.write_bytes(pickle.dumps(entry))
    env = os.environ.copy()
    existing = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(SRC) if not existing else str(SRC) + os.pathsep + existing
    script = """
import asyncio, pickle, sys, time
from pathlib import Path
from astro_host.weather_cache_file import FileWeatherCache
cache, payload, ready, go = sys.argv[1:]
Path(ready).write_text("1", encoding="utf-8")
deadline = time.time() + 15
while not Path(go).exists():
    if time.time() > deadline:
        raise SystemExit("timed out waiting to start")
    time.sleep(0.01)
snapshot = pickle.loads(Path(payload).read_bytes())
asyncio.run(FileWeatherCache(cache).put(snapshot))
"""
    return subprocess.Popen(
        [sys.executable, "-c", script, str(cache_path), str(payload), str(ready), str(go)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _fail_workers(workers: list[subprocess.Popen[bytes]], message: str) -> None:
    details = []
    for worker in workers:
        if worker.poll() is None:
            worker.kill()
        stdout, stderr = worker.communicate(timeout=5)
        details.append(
            f"exit={worker.returncode} stdout={stdout!r} stderr={stderr!r}"
        )
    raise AssertionError(message + " " + " | ".join(details))
