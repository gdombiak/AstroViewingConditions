"""Live planet observation facts for one night.

Normative procedure: contracts/procedures/planet-observation.md. This computes
night-scoped provider facts; `targets.planet_recommendation` consumes the result
deterministically.

The portable model is the production one, ported from
`LowPrecisionPlanetAstronomyProvider`:

* Schlyter low-precision orbital elements with the `JD - 2451543.5` day number;
* one eccentric-anomaly correction term, not an iterated Kepler solve;
* Earth's elements supply the geocentric Sun vector, which is added to the
  planet's heliocentric vector to get the geocentric one;
* geometric altitude/azimuth with no refraction, parallax or light-time;
* solar elongation as the angle between the geocentric planet and Sun vectors;
* samples by repeated addition of the cadence from `night_start - 7200` while
  the instant stays at or before `night_end + 3600`. The lead endpoint is always
  sampled; the trailing endpoint only when the cadence lands on it, and there is
  no explicit interval-end sample.

Operation ordering follows the Swift source so binary64 results agree.
"""

from __future__ import annotations

import math
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping, NamedTuple

from astro_engine.deep_sky_observation import exceeds_sample_cap
from astro_engine.errors import SampleCapError, ValidationError

CAPABILITY_ID = "astronomy.planet_observation"

DEFAULT_SAMPLE_INTERVAL = 15 * 60.0
LEAD_SECONDS = 2 * 3600.0
TRAIL_SECONDS = 60 * 60.0

# Astronomy-namespace instant window, shared with sun_events/moon_*/planet.
EARLIEST_EPOCH_SECONDS = 946_684_800.0     # 2000-01-01T00:00:00Z
LATEST_EPOCH_SECONDS = 2_524_607_999.0     # 2049-12-31T23:59:59Z

# Bounded live night interval; the same 26 hours the namespace already uses.
MAX_SPAN_SECONDS = 26 * 3600.0

# One day of one-minute cadence over the sampling span. Production asks for one
# astronomical night at 900 s — at most ~70 samples.
MAX_SAMPLE_COUNT = 1_440

# The production user-facing candidates. `earth` is in the model only to supply
# the geocentric Sun vector and is never a target.
SUPPORTED_TARGET_IDS = ("venus", "mars", "jupiter", "saturn")

# Swift `Date` counts seconds from 2001-01-01T00:00:00Z; matching the scale keeps
# sample arithmetic bit-identical, as in targets.deep_sky_windows.
_REFERENCE_EPOCH = 978_307_200.0
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
_PATTERN = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", re.ASCII)


class Sample(NamedTuple):
    time: float
    """Swift reference-epoch seconds."""
    altitude: float
    azimuth: float
    solar_elongation: float


def _radians(degrees: float) -> float:
    return degrees * math.pi / 180


def _degrees(radians: float) -> float:
    return radians * 180 / math.pi


def _normalized_degrees(degrees: float) -> float:
    return math.fmod(math.fmod(degrees, 360.0) + 360.0, 360.0)


def _normalized_radians(radians: float) -> float:
    two_pi = 2 * math.pi
    return math.fmod(math.fmod(radians, two_pi) + two_pi, two_pi)


def _elements(body: str, d: float) -> tuple[float, float, float, float, float, float]:
    """`(node, inclination, argument_of_perihelion, a, e, mean_anomaly)`."""
    if body == "earth":
        return (0.0, 0.0, 282.9404 + 4.70935e-5 * d, 1.0,
                0.016709 - 1.151e-9 * d, 356.0470 + 0.9856002585 * d)
    if body == "venus":
        return (76.6799 + 2.46590e-5 * d, 3.3946 + 2.75e-8 * d, 54.8910 + 1.38374e-5 * d,
                0.723330, 0.006773 - 1.302e-9 * d, 48.0052 + 1.6021302244 * d)
    if body == "mars":
        return (49.5574 + 2.11081e-5 * d, 1.8497 - 1.78e-8 * d, 286.5016 + 2.92961e-5 * d,
                1.523688, 0.093405 + 2.516e-9 * d, 18.6021 + 0.5240207766 * d)
    if body == "jupiter":
        return (100.4542 + 2.76854e-5 * d, 1.3030 - 1.557e-7 * d, 273.8777 + 1.64505e-5 * d,
                5.20256, 0.048498 + 4.469e-9 * d, 19.8950 + 0.0830853001 * d)
    if body == "saturn":
        return (113.6634 + 2.38980e-5 * d, 2.4886 - 1.081e-7 * d, 339.3939 + 2.97661e-5 * d,
                9.55475, 0.055546 - 9.499e-9 * d, 316.9670 + 0.0334442282 * d)
    raise _invalid()


def _heliocentric(elements: tuple[float, float, float, float, float, float]
                  ) -> tuple[float, float, float]:
    node, inclination, argument_of_perihelion, semi_major_axis, eccentricity, mean_anomaly = elements
    mean_anomaly_radians = _radians(_normalized_degrees(mean_anomaly))
    eccentric_anomaly = mean_anomaly_radians + eccentricity * math.sin(mean_anomaly_radians) * (
        1 + eccentricity * math.cos(mean_anomaly_radians)
    )

    xv = semi_major_axis * (math.cos(eccentric_anomaly) - eccentricity)
    yv = semi_major_axis * math.sqrt(1 - eccentricity * eccentricity) * math.sin(eccentric_anomaly)
    true_anomaly = math.atan2(yv, xv)
    radius = math.sqrt(xv * xv + yv * yv)

    node_radians = _radians(node)
    inclination_radians = _radians(inclination)
    argument = true_anomaly + _radians(argument_of_perihelion)

    x = radius * (math.cos(node_radians) * math.cos(argument)
                  - math.sin(node_radians) * math.sin(argument) * math.cos(inclination_radians))
    y = radius * (math.sin(node_radians) * math.cos(argument)
                  + math.cos(node_radians) * math.sin(argument) * math.cos(inclination_radians))
    z = radius * math.sin(argument) * math.sin(inclination_radians)
    return x, y, z


def _angular_separation(first: tuple[float, float, float],
                        second: tuple[float, float, float]) -> float:
    dot = first[0] * second[0] + first[1] * second[1] + first[2] * second[2]
    first_magnitude = math.sqrt(first[0] * first[0] + first[1] * first[1] + first[2] * first[2])
    second_magnitude = math.sqrt(second[0] * second[0] + second[1] * second[1] + second[2] * second[2])
    if not (first_magnitude > 0 and second_magnitude > 0):
        return 0.0
    cosine = min(max(dot / (first_magnitude * second_magnitude), -1), 1)
    return _degrees(math.acos(cosine))


def position(body: str, latitude: float, longitude: float, reference_seconds: float) -> Sample:
    """Geocentric horizontal coordinates and solar elongation at one instant."""
    jd = (reference_seconds + _REFERENCE_EPOCH) / 86_400 + 2_440_587.5
    # Schlyter's day-number convention: d = JD - 2451543.5, not the J2000.0 epoch.
    d = jd - 2_451_543.5
    sun_geocentric = _heliocentric(_elements("earth", d))
    planet = _heliocentric(_elements(body, d))

    x = planet[0] + sun_geocentric[0]
    y = planet[1] + sun_geocentric[1]
    z = planet[2] + sun_geocentric[2]
    obliquity = _radians(23.4393 - 3.563e-7 * d)

    equatorial_x = x
    equatorial_y = y * math.cos(obliquity) - z * math.sin(obliquity)
    equatorial_z = y * math.sin(obliquity) + z * math.cos(obliquity)
    right_ascension = math.atan2(equatorial_y, equatorial_x)
    declination = math.atan2(
        equatorial_z, math.sqrt(equatorial_x * equatorial_x + equatorial_y * equatorial_y))

    local_sidereal_time = _radians(_normalized_degrees(
        280.460_618_37 + 360.985_647_366_29 * (jd - 2_451_545.0) + longitude
    ))
    hour_angle = _normalized_radians(local_sidereal_time - right_ascension)
    latitude_radians = _radians(latitude)

    # Production does not clamp; Swift `asin` of an out-of-range binary64 sum
    # yields NaN rather than raising, so mirror that instead of clamping.
    sine_altitude = (math.sin(declination) * math.sin(latitude_radians)
                     + math.cos(declination) * math.cos(latitude_radians) * math.cos(hour_angle))
    altitude = math.asin(sine_altitude) if -1.0 <= sine_altitude <= 1.0 else math.nan
    azimuth = math.atan2(
        math.sin(hour_angle),
        math.cos(hour_angle) * math.sin(latitude_radians)
        - math.tan(declination) * math.cos(latitude_radians),
    )

    return Sample(
        time=reference_seconds,
        altitude=_degrees(altitude),
        azimuth=_normalized_degrees(_degrees(azimuth) + 180),
        solar_elongation=_angular_separation((x, y, z), sun_geocentric),
    )


def observe(body: str, latitude: float, longitude: float, night_start: float, night_end: float,
            sample_interval: float = DEFAULT_SAMPLE_INTERVAL) -> list[Sample] | None:
    """`None` reproduces the production `guard end > start` bail-out."""
    start = night_start - LEAD_SECONDS
    end = night_end + TRAIL_SECONDS
    if not end > start:
        return None

    samples: list[Sample] = []
    time = start
    while time <= end:
        samples.append(position(body, latitude, longitude, time))
        time = time + sample_interval
    return samples


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


def _reference_seconds(value: Any) -> float:
    if not isinstance(value, str) or not _PATTERN.fullmatch(value):
        raise _invalid()
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise _invalid() from exc
    seconds = (parsed - _EPOCH).total_seconds()
    if not EARLIEST_EPOCH_SECONDS <= seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid()
    return seconds - _REFERENCE_EPOCH


def _timestamp(reference_seconds: float) -> str:
    if not math.isfinite(reference_seconds):
        raise _invalid()
    seconds = math.floor(reference_seconds + _REFERENCE_EPOCH)
    # isoformat preserves four-digit years even where strftime('%Y') does not.
    return (_EPOCH + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def evaluate_planet_observation(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping):
        raise _invalid()
    allowed = {"target_id", "latitude", "longitude", "night_start", "night_end",
               "sample_interval_seconds"}
    required = allowed - {"sample_interval_seconds"}
    if set(input) - allowed or not required <= set(input):
        raise _invalid()
    body = input["target_id"]
    if not isinstance(body, str) or body not in SUPPORTED_TARGET_IDS:
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
    if not 0 < sample_interval <= MAX_SPAN_SECONDS:
        raise _invalid()
    night_start = _reference_seconds(input["night_start"])
    night_end = _reference_seconds(input["night_end"])
    if night_end - night_start > MAX_SPAN_SECONDS:
        raise _invalid()
    start = night_start - LEAD_SECONDS
    end = night_end + TRAIL_SECONDS
    if exceeds_sample_cap(start, end, sample_interval, MAX_SAMPLE_COUNT):
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 sample cap ({MAX_SAMPLE_COUNT} samples)"
        )
    # Integral cadence preserves strictly ordered whole-second transport and
    # avoids host-dependent repeated-addition rounding on different epochs.
    if sample_interval != math.trunc(sample_interval):
        raise _invalid()

    samples = observe(body, latitude, longitude, night_start, night_end, sample_interval)
    result: dict[str, Any] = {
        "target_id": body,
        "night_start": _timestamp(night_start),
        "night_end": _timestamp(night_end),
    }
    if samples is None:
        result["observation"] = None
        return result
    result["observation"] = {
        "sample_start": _timestamp(start),
        "sample_end": _timestamp(end),
        "samples": [
            {
                "time": _timestamp(sample.time),
                "altitude": sample.altitude,
                "azimuth": sample.azimuth,
                "solar_elongation": sample.solar_elongation,
            }
            for sample in samples
        ],
    }
    return result
