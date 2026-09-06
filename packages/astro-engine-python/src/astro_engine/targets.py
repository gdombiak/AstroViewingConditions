"""Generic frozen-window recommendations. No provider or astronomy dependencies."""
from __future__ import annotations

import math
from astro_engine.contracts import load_canonical_data
from astro_engine.errors import ValidationError
from astro_engine.validate import parse_utc_z
from astro_engine._phase15_input import obj, array, number, optional_number, enum, key

CAPABILITY_ID = "targets.recommend"
TARGET_TYPES = ("deepSky", "meteorShower", "satellite", "moon", "planet")
OBJECT_TYPES = ("galaxy", "diffuseNebula", "globularCluster", "openCluster", "doubleStar", "planetaryNebula")
_CEILING_KEYS = dict(zip(OBJECT_TYPES, ("galaxy", "diffuse_nebula", "globular_cluster", "open_cluster", "double_star", "planetary_nebula")))


def _clamp(value: float, low: float = 0, high: float = 1) -> float:
    return min(max(value, low), high)


def recommend_targets(inputs: dict) -> dict:
    cal = load_canonical_data("calibration/target-scoring.json")
    try:
        return _recommend(obj(inputs), cal)
    except ValidationError as exc:
        raise ValidationError("invalid targets.recommend input") from exc


def _recommend(inputs: dict, cal: dict) -> dict:
    darkness = obj(inputs.get("darkness_window"))
    dark_start = parse_utc_z(darkness.get("start"), "start")
    dark_end = parse_utc_z(darkness.get("end"), "end")
    cloud = number(inputs.get("cloud_cover_score"))
    moon = obj(inputs.get("moon"))
    moon_alt = number(moon.get("altitude"))
    illumination = number(moon.get("illumination"))
    if not illumination.is_integer():
        raise ValidationError("integer illumination required")
    hours = []
    for value in array(inputs.get("hourly_ratings")):
        row = obj(value)
        hours.append((parse_utc_z(row.get("time"), "time"), number(row.get("score"))))
    limit = number(inputs.get("limit", 5))
    if limit < 0 or not limit.is_integer():
        raise ValidationError("nonnegative integer limit required")
    seen: set[str] = set()
    results = []
    for value in array(inputs.get("candidates")):
        row = obj(value)
        candidate_key = key(row.get("key"), seen)
        kind = enum(row.get("type"), TARGET_TYPES)
        object_type = row.get("object_type")
        if object_type is not None:
            object_type = enum(object_type, OBJECT_TYPES)
        difficulty = number(row.get("difficulty"))
        sensitivity = optional_number(row.get("sensitivity"))
        window = obj(row.get("window"))
        start = parse_utc_z(window.get("start"), "start")
        end = parse_utc_z(window.get("end"), "end")
        best = parse_utc_z(window.get("best_time"), "best_time")
        altitude = optional_number(window.get("max_altitude"))
        overlap_start, overlap_end = max(start, dark_start), min(end, dark_end)
        overlap = (overlap_end - overlap_start).total_seconds() / (end - start).total_seconds() if end > start and overlap_end > overlap_start else 0
        weather_cal = cal["weather"]
        scores = [score for time, score in hours if (start - time).total_seconds() < weather_cal["hourly_rating_seconds"] and time < end]
        # Python 3.12+ sum(float) compensates; the contract requires ordered binary64 addition.
        total = 0.0
        for score in scores:
            total += score
        weather = 1 - _clamp(total / len(scores) / weather_cal["overlap_score_divisor"]) if scores else 1 - _clamp(cloud / weather_cal["cloud_cover_percent_divisor"])
        altitude_component = _clamp((altitude if altitude is not None else cal["altitude"]["missing_max_altitude"]) / cal["altitude"]["reference_degrees"]) * cal["altitude"]["weight"]
        dark_key = "deep_sky_and_meteor_shower" if kind in ("deepSky", "meteorShower") else "satellite" if kind == "satellite" else "moon_and_planet"
        dark_cal = cal["darkness"][dark_key]
        darkness_component = dark_cal["base"] + overlap * dark_cal["overlap_weight"]
        m = cal["moon"]
        ceiling_key = _CEILING_KEYS.get(object_type, "unknown_deep_sky_object_type") if kind == "deepSky" else "meteor_shower" if kind == "meteorShower" else kind
        bounds = cal["target_bounds"]
        sensitivity = _clamp(sensitivity if sensitivity is not None else m["deep_sky_interference_sensitivity"]["default"], bounds["sensitivity_min"], bounds["sensitivity_max"])
        interference = _clamp(illumination / 100) * (m["interference"]["base"] + _clamp(moon_alt / m["altitude_reference_degrees"]) * m["interference"]["altitude_weight"])
        penalty = 0 if moon_alt <= m["zero_when_altitude_at_or_below_degrees"] else interference * m["ceilings"][ceiling_key] * (sensitivity if kind == "deepSky" else 1)
        difficulty_penalty = _clamp(difficulty, bounds["difficulty_min"], bounds["difficulty_max"]) * cal["difficulty_weight"]
        raw = altitude_component + darkness_component + weather * weather_cal["weight"] - penalty - difficulty_penalty
        clamped = _clamp(raw, cal["score"]["min"], cal["score"]["max"])
        whole = math.floor(clamped)
        score = whole + int(clamped - whole >= 0.5)
        results.append((candidate_key, score, best))
    results.sort(key=lambda row: (-row[1], row[2]))  # stable complete ties
    return {"recommendations": [{"key": k, "score": score} for k, score, _ in results[:int(limit)]]}
