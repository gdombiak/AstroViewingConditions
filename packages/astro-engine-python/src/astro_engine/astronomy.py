"""Portable live astronomy. See contracts/procedures/astronomy.md.

Imports of Skyfield/data are lazy: deterministic capability execution never
loads live astronomy resources. No network loader is used for ephemerides.
"""
from __future__ import annotations

from datetime import datetime, timezone
from importlib.resources import files
from pathlib import Path
import re
from typing import Any, Mapping

from astro_engine.errors import ValidationError
from astro_engine.validate import require_finite_number

CAPABILITY_IDS = ("astronomy.sun_events", "astronomy.moon_info", "astronomy.moon_series")
_PATTERN = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", re.ASCII)


def instant(value: Any) -> datetime:
    if not isinstance(value, str) or not _PATTERN.fullmatch(value):
        raise ValidationError("expected whole-second UTC instant")
    try:
        result = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise ValidationError("invalid UTC calendar instant") from exc
    if not 2000 <= result.year < 2050:
        raise ValidationError("astronomy instant outside 2000...2049")
    return result


def utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def default_ephemeris_path() -> Path:
    # Access the asset without skyfield_data's unrelated IERS expiry warnings.
    return Path(str(files("skyfield_data").joinpath("data", "de421.bsp")))


class SkyfieldAstronomy:
    """One invocation owns/closes its kernel; optional path is a host resource."""
    def __init__(self, ephemeris_path: Path | str | None = None):
        from skyfield.api import Loader, load_file
        path = Path(ephemeris_path) if ephemeris_path is not None else default_ephemeris_path()
        if not path.is_file():
            raise RuntimeError("local astronomy ephemeris is not installed")
        # builtin=True reads Skyfield package resources only. Loader's directory
        # already exists; no cache or writable working directory is required.
        self.timescale = Loader(str(path.parent), verbose=False).timescale(builtin=True)
        self.kernel = load_file(str(path))
        try:
            self.earth = self.kernel["earth"]
            self.sun = self.kernel["sun"]
            self.moon = self.kernel["moon"]
        except Exception:
            self.kernel.close()
            raise

    def close(self) -> None:
        self.kernel.close()

    def _horizontal(self, body, t, latitude, longitude):
        import numpy as np
        apparent = self.earth.at(t).observe(body).apparent()
        ra, dec, distance = apparent.radec(epoch="date")
        hour_angle = np.radians(t.gast * 15 + longitude) - ra.radians
        phi = np.radians(latitude)
        altitude = np.arcsin(np.clip(np.sin(phi) * np.sin(dec.radians)
                           + np.cos(phi) * np.cos(dec.radians) * np.cos(hour_angle), -1, 1))
        return altitude, distance.km, apparent

    def moon_info(self, latitude: float, longitude: float, time: datetime) -> dict[str, Any]:
        import numpy as np
        t = self.timescale.from_datetime(time)
        altitude, _, apparent = self._horizontal(self.moon, t, latitude, longitude)
        if altitude >= 0:
            altitude += 0.000296706 / np.tan(altitude + 0.00312537 / (altitude + 0.0890118))
        return {"time": utc(time), "altitude": float(np.degrees(altitude)),
                "illumination": int(float(apparent.fraction_illuminated(self.sun)) * 100)}

    def sun_events(self, latitude: float, longitude: float, start: datetime, end: datetime) -> dict[str, Any]:
        import numpy as np
        from skyfield.searchlib import find_discrete
        first, last = self.timescale.from_datetime(start), self.timescale.from_datetime(end)
        result = {"start": utc(start), "end": utc(end)}
        refraction = np.pi / (10800 * np.tan(np.radians(7.31 / 4.4)))
        for kind, angle in (("visual", None), ("civil", -6), ("nautical", -12), ("astronomical", -18)):
            def above(t):
                altitude, distance, _ = self._horizontal(self.sun, t, latitude, longitude)
                threshold = (-refraction + np.arcsin(6371 / distance) - np.arcsin(695700 / distance)
                             if angle is None else np.radians(angle))
                return altitude >= threshold
            above.step_days = 1 / 288  # bracket crossings independently of either library's output
            times, directions = find_discrete(first, last, above, epsilon=0.05 / 86400)
            rise = setting = None
            for t, up in zip(times, directions):
                value = t.utc_datetime()
                if not start <= value < end:
                    continue
                if up and rise is None:
                    rise = utc(value)
                if not up and setting is None:
                    setting = utc(value)
            if kind == "visual":
                result.update(sunrise=rise, sunset=setting)
            else:
                result[f"{kind}_twilight_begin"] = rise
                result[f"{kind}_twilight_end"] = setting
        result["astronomical_night_start"] = result["astronomical_twilight_end"]
        result["astronomical_night_end"] = result["astronomical_twilight_begin"]
        return result


def evaluate_astronomy(capability: str, input: Mapping[str, Any], *,
                       ephemeris_path: Path | str | None = None) -> dict[str, Any]:
    extra = {CAPABILITY_IDS[0]: {"start", "end"}, CAPABILITY_IDS[1]: {"time"},
             CAPABILITY_IDS[2]: {"times"}}.get(capability)
    if extra is None or set(input) != extra | {"latitude", "longitude"}:
        raise ValidationError("missing or unknown astronomy input keys")
    latitude = require_finite_number(input["latitude"], "latitude")
    longitude = require_finite_number(input["longitude"], "longitude")
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ValidationError("coordinates out of range")
    if capability == CAPABILITY_IDS[0]:
        start, end = instant(input["start"]), instant(input["end"])
        if not 0 < (end - start).total_seconds() <= 26 * 3600:
            raise ValidationError("sun interval must be nonempty and at most 26 hours")
    elif capability == CAPABILITY_IDS[1]:
        time = instant(input["time"])
    else:
        raw = input["times"]
        if not isinstance(raw, list) or len(raw) > 49:
            raise ValidationError("times must contain at most 49 instants")
        times = [instant(t) for t in raw]
        if any(a >= b for a, b in zip(times, times[1:])):
            raise ValidationError("times must increase strictly")
        if times and (times[-1] - times[0]).total_seconds() > 48 * 3600:
            raise ValidationError("moon series spans more than 48 hours")
        if not times:
            return {"samples": []}
    sampler = SkyfieldAstronomy(ephemeris_path)
    try:
        if capability == CAPABILITY_IDS[0]:
            return sampler.sun_events(latitude, longitude, start, end)
        if capability == CAPABILITY_IDS[1]:
            return sampler.moon_info(latitude, longitude, time)
        return {"samples": [sampler.moon_info(latitude, longitude, t) for t in times]}
    finally:
        sampler.close()
