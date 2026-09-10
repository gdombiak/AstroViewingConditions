"""Durable JSON weather cache for ``agent.conditions``.

``get`` / ``put`` take a sidecar ``fcntl.flock`` and then run a synchronous
read-modify-write. Introducing ``await`` inside that locked section is a
contract break: same-loop tasks would interleave, and the event loop would
block on flock without an in-process lock to yield on.
"""

from __future__ import annotations

from datetime import datetime, timezone
from collections.abc import Callable, Mapping
import fcntl
import json
import math
import os
from pathlib import Path
import tempfile
from typing import TypeVar
import uuid

from astro_host.cache import newest_usable_snapshot, same_cache_identity, snapshot_age
from astro_host.models import (
    HourlyWeather,
    Location,
    PayloadDiagnostics,
    PayloadState,
    WeatherQuery,
    WeatherSnapshot,
)


SCHEMA_VERSION = 1
MAX_ENTRIES = 64
CACHE_FILENAME = "weather-cache.json"

_FAIL_OPEN = (OSError, UnicodeDecodeError, json.JSONDecodeError)
_T = TypeVar("_T")

_HOURLY_OPTIONAL_INT = ("low_cloud_cover", "mid_cloud_cover", "high_cloud_cover")
_HOURLY_OPTIONAL_FLOAT = ("dew_point", "visibility", "wind_speed_200hpa")


def default_state_dir() -> Path:
    raw = os.environ.get("ASTRO_HOST_STATE_DIR", "").strip()
    if raw:
        return Path(raw).expanduser()
    try:
        return Path.home() / ".astro-host"
    except (OSError, RuntimeError):
        return Path(tempfile.gettempdir()) / "astro-host"


def default_weather_cache_path() -> Path:
    return default_state_dir() / CACHE_FILENAME


class FileWeatherCache:
    def __init__(
        self,
        path: Path | str,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self.path = Path(path).expanduser().resolve()
        self._clock = clock

    async def get(
        self, query: WeatherQuery, *, provider: str
    ) -> WeatherSnapshot | None:
        try:
            if not self.path.exists():
                return None
            state = self._with_lock(self._load_locked)
        except _FAIL_OPEN:
            return None
        if state.foreign:
            return None
        return newest_usable_snapshot(
            state.entries, query, provider=provider, now=self._clock()
        )

    async def put(self, snapshot: WeatherSnapshot) -> None:
        if not snapshot.hourly:
            return
        now = self._clock()
        if snapshot_age(snapshot, now) is None:
            return
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._with_lock(lambda: self._put_locked(snapshot, now))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            return

    def _lock_path(self) -> Path:
        return self.path.with_name(self.path.name + ".lock")

    def _with_lock(self, body: Callable[[], _T]) -> _T:
        with open(self._lock_path(), "a+", encoding="utf-8") as handle:
            fd = handle.fileno()
            fcntl.flock(fd, fcntl.LOCK_EX)
            try:
                return body()
            finally:
                fcntl.flock(fd, fcntl.LOCK_UN)

    def _load_locked(self) -> _FileState:
        if not self.path.exists():
            return _FileState(())
        raw = self.path.read_bytes()
        try:
            document = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return _FileState(())
        return _decode_document(document)

    def _put_locked(self, snapshot: WeatherSnapshot, now: datetime) -> None:
        state = self._load_locked()
        if state.foreign:
            return
        entries = [
            entry for entry in state.entries if not same_cache_identity(entry, snapshot)
        ]
        entries.append(snapshot)
        entries = _prune(entries, snapshot, now)
        payload = _encode_document(entries)
        tmp_path = self.path.with_name(
            f"{self.path.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
        )
        try:
            with open(tmp_path, "w", encoding="utf-8") as handle:
                handle.write(payload)
                handle.flush()
            os.replace(tmp_path, self.path)
        finally:
            try:
                tmp_path.unlink()
            except OSError:
                pass


class _FileState:
    def __init__(
        self, entries: tuple[WeatherSnapshot, ...], *, foreign: bool = False
    ) -> None:
        self.entries = entries
        self.foreign = foreign


def _prune(
    entries: list[WeatherSnapshot],
    just_written: WeatherSnapshot,
    now: datetime,
) -> list[WeatherSnapshot]:
    kept = [entry for entry in entries if snapshot_age(entry, now) is not None]
    if len(kept) <= MAX_ENTRIES:
        return kept
    others = [
        entry for entry in kept if entry is not just_written
    ]
    others.sort(key=lambda entry: entry.fetched_at, reverse=True)
    if just_written in kept:
        return [just_written, *others[: MAX_ENTRIES - 1]]
    return others[:MAX_ENTRIES]


def _encode_document(entries: list[WeatherSnapshot]) -> str:
    return json.dumps(
        {
            "schema_version": SCHEMA_VERSION,
            "entries": [_encode_snapshot(entry) for entry in entries],
        },
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    ) + "\n"


def _encode_snapshot(snapshot: WeatherSnapshot) -> dict[str, object]:
    location: dict[str, object] = {
        "latitude": snapshot.query.location.latitude,
        "longitude": snapshot.query.location.longitude,
    }
    if snapshot.query.location.name is not None:
        location["name"] = snapshot.query.location.name
    if snapshot.query.location.location_id is not None:
        location["location_id"] = snapshot.query.location.location_id
    if snapshot.query.location.elevation_m is not None:
        location["elevation_m"] = snapshot.query.location.elevation_m
    if snapshot.query.location.time_zone_hint is not None:
        location["time_zone_hint"] = snapshot.query.location.time_zone_hint
    return {
        "diagnostics": {
            "messages": list(snapshot.diagnostics.messages),
            "provider_time_count": snapshot.diagnostics.provider_time_count,
            "state": snapshot.diagnostics.state.value,
        },
        "fetched_at": _utc_z(snapshot.fetched_at),
        "hourly": [_encode_hourly(row) for row in snapshot.hourly],
        "provider": snapshot.provider,
        "provider_timezone": snapshot.provider_timezone,
        "query": {
            "forecast_days": snapshot.query.forecast_days,
            "location": location,
            "past_days": snapshot.query.past_days,
        },
        "utc_offset_seconds": snapshot.utc_offset_seconds,
    }


def _encode_hourly(row: HourlyWeather) -> dict[str, object]:
    encoded: dict[str, object] = {
        "cloud_cover": row.cloud_cover,
        "humidity": row.humidity,
        "temperature": row.temperature,
        "time": _utc_z(row.time),
        "wind_direction": row.wind_direction,
        "wind_speed": row.wind_speed,
    }
    for key in _HOURLY_OPTIONAL_INT + _HOURLY_OPTIONAL_FLOAT:
        value = getattr(row, key)
        if value is not None:
            encoded[key] = value
    return encoded


def _utc_z(value: datetime) -> str:
    if value.tzinfo is None:
        raise ValueError("timestamp must be timezone-aware")
    try:
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except OverflowError as exc:
        raise ValueError("timestamp out of UTC range") from exc


def _decode_document(document: object) -> _FileState:
    if not isinstance(document, Mapping):
        return _FileState(())
    version = document.get("schema_version")
    if isinstance(version, int) and not isinstance(version, bool):
        if version != SCHEMA_VERSION:
            return _FileState((), foreign=True)
    else:
        return _FileState(())
    raw_entries = document.get("entries")
    if not isinstance(raw_entries, list):
        return _FileState(())
    decoded: list[WeatherSnapshot] = []
    for item in raw_entries:
        try:
            snapshot = _decode_snapshot(item)
        except (TypeError, ValueError, KeyError, OverflowError):
            continue
        if snapshot.hourly:
            decoded.append(snapshot)
    return _FileState(tuple(decoded))


def _decode_snapshot(value: object) -> WeatherSnapshot:
    item = _object(value)
    hourly_raw = item.get("hourly")
    if not isinstance(hourly_raw, list) or not hourly_raw:
        raise ValueError("hourly must be a non-empty array")
    hourly = tuple(_decode_hourly(row) for row in hourly_raw)
    diagnostics = _decode_diagnostics(item.get("diagnostics"))
    query_raw = _object(item.get("query"))
    location_raw = _object(query_raw.get("location"))
    return WeatherSnapshot(
        query=WeatherQuery(
            location=Location(
                latitude=_number(location_raw.get("latitude")),
                longitude=_number(location_raw.get("longitude")),
                name=_optional_str(location_raw.get("name")),
                location_id=_optional_str(location_raw.get("location_id")),
                elevation_m=_optional_number(location_raw.get("elevation_m")),
                time_zone_hint=_optional_str(location_raw.get("time_zone_hint")),
            ),
            forecast_days=_int(query_raw.get("forecast_days"), minimum=1),
            past_days=_int(query_raw.get("past_days"), minimum=0),
        ),
        provider=_str(item.get("provider")),
        fetched_at=_timestamp(item.get("fetched_at")),
        provider_timezone=_optional_str(item.get("provider_timezone")),
        utc_offset_seconds=_optional_int(item.get("utc_offset_seconds")),
        hourly=hourly,
        diagnostics=diagnostics,
    )


def _decode_diagnostics(value: object) -> PayloadDiagnostics:
    item = _object(value)
    messages_raw = item.get("messages")
    if not isinstance(messages_raw, list) or any(
        not isinstance(message, str) for message in messages_raw
    ):
        raise ValueError("diagnostics.messages must be an array of strings")
    state = item.get("state")
    if not isinstance(state, str):
        raise ValueError("diagnostics.state must be a string")
    return PayloadDiagnostics(
        state=PayloadState(state),
        messages=tuple(messages_raw),
        provider_time_count=_int(item.get("provider_time_count"), minimum=0),
    )


def _decode_hourly(value: object) -> HourlyWeather:
    item = _object(value)
    optional_int = {
        key: _optional_int(item.get(key)) for key in _HOURLY_OPTIONAL_INT
    }
    optional_float = {
        key: _optional_number(item.get(key)) for key in _HOURLY_OPTIONAL_FLOAT
    }
    return HourlyWeather(
        time=_timestamp(item.get("time")),
        cloud_cover=_int(item.get("cloud_cover")),
        humidity=_int(item.get("humidity")),
        wind_speed=_number(item.get("wind_speed")),
        wind_direction=_int(item.get("wind_direction")),
        temperature=_number(item.get("temperature")),
        **optional_int,
        **optional_float,
    )


def _object(value: object) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        raise ValueError("expected object")
    return value


def _str(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("expected string")
    return value


def _optional_str(value: object) -> str | None:
    if value is None:
        return None
    return _str(value)


def _int(value: object, *, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("expected integer")
    if minimum is not None and value < minimum:
        raise ValueError("integer below minimum")
    return value


def _optional_int(value: object) -> int | None:
    if value is None:
        return None
    return _int(value)


def _number(value: object) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("expected number")
    try:
        result = float(value)
    except OverflowError as exc:
        raise ValueError("number out of float range") from exc
    if not math.isfinite(result):
        raise ValueError("non-finite number")
    return result


def _optional_number(value: object) -> float | None:
    if value is None:
        return None
    return _number(value)


def _timestamp(value: object) -> datetime:
    parsed = datetime.fromisoformat(_str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must be timezone-aware")
    try:
        return parsed.astimezone(timezone.utc)
    except OverflowError as exc:
        raise ValueError("timestamp out of UTC range") from exc
