"""Live lunar observation facts for one night.

Normative procedure: contracts/procedures/moon-observation.md. This computes night-scoped provider facts; `targets.moon_recommendation` consumes
the result deterministically.

The portable model is the production SunCalc one, ported in `suncalc_moon.py`:

* geocentric direction with SunCalc's refraction and no topocentric parallax;
* phase and illumination sampled once at the night midpoint;
* rise/set from an hourly quadratic-interpolation search over the geometric
  altitude against `asin(R_earth/r) - refraction_at_horizon - asin(R_moon/r)`;
* position samples by repeated addition of the cadence, plus an explicit sample
  at the interval end when the loop did not already land on it.

The MoonTimes/quadratic search is translated from SunCalc / commons-suncalc.
Copyright © 2021 Nikolaj Banke Jensen; Copyright (C) 2017 Richard "Shred" Körber.
Modified 2026 for Python. Licensed under Apache-2.0; see LICENSE-SunCalc and
NOTICE-SunCalc distributed with this package.

"""

from __future__ import annotations

import math
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping, NamedTuple

from astro_engine.deep_sky_observation import exceeds_sample_cap
from astro_engine.errors import SampleCapError, ValidationError

CAPABILITY_ID = "astronomy.moon_observation"

DEFAULT_SAMPLE_INTERVAL = 30 * 60.0

# Astronomy-namespace instant window, shared with sun_events/moon_info/moon_series.
EARLIEST_EPOCH_SECONDS = 946_684_800.0     # 2000-01-01T00:00:00Z
LATEST_EPOCH_SECONDS = 2_524_607_999.0     # 2049-12-31T23:59:59Z

# Bounded live interval; the same 26 hours astronomy.sun_events allows.
MAX_SPAN_SECONDS = 26 * 3600.0

# One day of one-minute cadence. Production asks for one astronomical night at
# 1800 s — at most ~53 samples — so this bounds ephemeris work generously.
MAX_SAMPLE_COUNT = 1_440

# commons-suncalc constants, reproduced verbatim.
EARTH_MEAN_RADIUS_KM = 6371.0
MOON_MEAN_RADIUS_KM = 1737.1
REFRACTION_AT_HORIZON = math.pi / (math.tan(math.radians(7.31 / 4.4)) * 10800.0)

_PATTERN = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", re.ASCII)
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


class MoonTimes(NamedTuple):
    rise: float | None
    """Epoch seconds, or None."""
    set: float | None
    always_up: bool
    always_down: bool


class _Quadratic:
    """commons-suncalc `QuadraticInterpolation`, including its root selection.

    Arithmetic runs through numpy float64 so a degenerate `a == 0` divides to
    IEEE infinity/NaN exactly as Swift does, instead of raising.
    """

    def __init__(self, y_minus: float, y0: float, y_plus: float) -> None:
        import numpy as np

        with np.errstate(divide="ignore", invalid="ignore"):
            a = np.float64(0.5 * (y_plus + y_minus) - y0)
            b = np.float64(0.5 * (y_plus - y_minus))
            c = np.float64(y0)
            self.xe = float(-b / (2.0 * a))
            self.ye = float((a * self.xe + b) * self.xe + c)
            discriminant = float(b * b - 4.0 * a * c)
            if discriminant >= 0.0:
                dx = float(0.5 * np.sqrt(np.float64(discriminant)) / np.abs(a))
                self._root1 = self.xe - dx
                self._root2 = self.xe + dx
                self.number_of_roots = (abs(self._root1) <= 1.0) + (abs(self._root2) <= 1.0)
            else:
                self._root1 = math.nan
                self._root2 = math.nan
                self.number_of_roots = 0

    @property
    def root1(self) -> float:
        return self._root2 if self._root1 < -1.0 else self._root1

    @property
    def root2(self) -> float:
        return self._root2


def moon_times(sampler, latitude: float, longitude: float, start: float, duration: float) -> MoonTimes:
    """Hourly quadratic search for the first rise and set in `[start, start+duration)`.

    `always_up` / `always_down` are seeded from the sign at hour 0 and cleared
    only by the opposite event, so a rise can coexist with `always_up`. That is
    the production behavior and is preserved.
    """

    def height(hour: float) -> float:
        moment = _EPOCH + timedelta(seconds=start + hour * 60 * 60)
        _, _, geometric, distance = sampler.moon_horizontal(latitude, longitude, moment)
        corrected = (
            math.asin(EARTH_MEAN_RADIUS_KM / distance)
            - REFRACTION_AT_HORIZON
            - math.asin(MOON_MEAN_RADIUS_KM / distance)
        )
        return geometric - corrected

    rise: float | None = None
    setting: float | None = None
    hour = 0.0
    limit_hours = duration / (60 * 60)
    max_hours = math.ceil(limit_hours)

    y_minus = height(hour - 1.0)
    y0 = height(hour)
    y_plus = height(hour + 1.0)
    always_up = y0 > 0.0
    always_down = not always_up

    while hour <= max_hours:
        quadratic = _Quadratic(y_minus, y0, y_plus)
        if quadratic.number_of_roots == 1:
            root = quadratic.root1 + hour
            if y_minus < 0.0:
                if rise is None and 0.0 <= root < limit_hours:
                    rise = root
                    always_down = False
            else:
                if setting is None and 0.0 <= root < limit_hours:
                    setting = root
                    always_up = False
        elif quadratic.number_of_roots == 2:
            if rise is None:
                root = hour + (quadratic.root2 if quadratic.ye < 0.0 else quadratic.root1)
                if 0.0 <= root < limit_hours:
                    rise = root
                    always_down = False
            if setting is None:
                root = hour + (quadratic.root1 if quadratic.ye < 0.0 else quadratic.root2)
                if 0.0 <= root < limit_hours:
                    setting = root
                    always_up = False

        if rise is not None and setting is not None:
            break

        hour += 1
        y_minus = y0
        y0 = y_plus
        y_plus = height(hour + 1.0)

    return MoonTimes(
        rise=None if rise is None else start + rise * 60 * 60,
        set=None if setting is None else start + setting * 60 * 60,
        always_up=always_up,
        always_down=always_down,
    )


def observe(sampler, latitude: float, longitude: float, start: float, end: float,
            sample_interval: float = DEFAULT_SAMPLE_INTERVAL) -> dict[str, Any]:
    """The portable observation bundle for one interval, in epoch seconds."""
    midpoint = start + max(end - start, 0.0) / 2
    fraction, phase_degrees = sampler.moon_phase(_EPOCH + timedelta(seconds=midpoint))
    times = moon_times(sampler, latitude, longitude, start, max(end - start, sample_interval))

    samples: list[tuple[float, float, float]] = []
    if end >= start:
        time = start
        while time <= end:
            altitude, azimuth, _, _ = sampler.moon_horizontal(
                latitude, longitude, _EPOCH + timedelta(seconds=time))
            samples.append((time, altitude, azimuth))
            time = time + sample_interval
        if not samples or samples[-1][0] != end:
            altitude, azimuth, _, _ = sampler.moon_horizontal(
                latitude, longitude, _EPOCH + timedelta(seconds=end))
            samples.append((end, altitude, azimuth))

    return {
        "phase": min(max((phase_degrees + 180) / 360, 0.0), 1.0),
        "illumination": min(max(int(fraction * 100), 0), 100),
        "rise": times.rise,
        "set": times.set,
        "always_up": times.always_up,
        "always_down": times.always_down,
        "samples": samples,
    }


# --- transport ------------------------------------------------------------


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _number(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid()
    try:
        number = float(value)
    except OverflowError as exc:
        raise _invalid() from exc
    if not math.isfinite(number):
        raise _invalid()
    return number


def _epoch_seconds(value: Any) -> float:
    if not isinstance(value, str) or not _PATTERN.fullmatch(value):
        raise _invalid()
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise _invalid() from exc
    seconds = (parsed - _EPOCH).total_seconds()
    if not EARLIEST_EPOCH_SECONDS <= seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid()
    return seconds


def _timestamp(seconds: float) -> str:
    if not math.isfinite(seconds):
        raise _invalid()
    # isoformat preserves four-digit years even where strftime('%Y') does not.
    return (_EPOCH + timedelta(seconds=math.floor(seconds))).isoformat().replace("+00:00", "Z")


def evaluate_moon_observation(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping):
        raise _invalid()
    allowed = {"latitude", "longitude", "night_start", "night_end", "sample_interval_seconds"}
    if set(input) - allowed or not {"latitude", "longitude", "night_start", "night_end"} <= set(input):
        raise _invalid()
    latitude = _number(input["latitude"])
    longitude = _number(input["longitude"])
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise _invalid()
    sample_interval = (
        _number(input["sample_interval_seconds"])
        if "sample_interval_seconds" in input
        else DEFAULT_SAMPLE_INTERVAL
    )
    # The cadence is also the minimum MoonTimes search duration.
    if not 0 < sample_interval <= MAX_SPAN_SECONDS:
        raise _invalid()
    start = _epoch_seconds(input["night_start"])
    end = _epoch_seconds(input["night_end"])
    if end - start > MAX_SPAN_SECONDS:
        raise _invalid()
    span = end - start
    reserve_end = int(span > 0 and math.fmod(span, sample_interval) != 0)
    # Use Swift's reference epoch for the shared conservative preflight.
    if exceeds_sample_cap(start - 978_307_200.0, end - 978_307_200.0,
                          sample_interval, MAX_SAMPLE_COUNT - reserve_end):
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 sample cap ({MAX_SAMPLE_COUNT} samples)"
        )
    # Integral cadence preserves strictly ordered whole-second transport and
    # avoids host-dependent repeated-addition rounding on different epochs.
    if sample_interval != math.trunc(sample_interval):
        raise _invalid()

    from astro_engine.suncalc_moon import SunCalcMoonAstronomy

    # This analytic production model requires no external ephemeris resource.
    observation = observe(SunCalcMoonAstronomy(), latitude, longitude, start, end, sample_interval)

    return {
        "night_start": _timestamp(start),
        "night_end": _timestamp(end),
        "phase": observation["phase"],
        "illumination": observation["illumination"],
        "rise": None if observation["rise"] is None else _timestamp(observation["rise"]),
        "set": None if observation["set"] is None else _timestamp(observation["set"]),
        "always_up": observation["always_up"],
        "always_down": observation["always_down"],
        "samples": [
            {"time": _timestamp(time), "altitude": altitude, "azimuth": azimuth}
            for time, altitude, azimuth in observation["samples"]
        ],
    }
