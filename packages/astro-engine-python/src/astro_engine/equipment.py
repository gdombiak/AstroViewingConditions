"""Resolved-requirement equipment matching; inventory and English copy stay host-side."""
from __future__ import annotations

from dataclasses import dataclass
from astro_engine.contracts import load_canonical_data
from astro_engine.errors import ValidationError
from astro_engine._phase15_input import obj, array, number, optional_number, enum, key, boolean

CAPABILITY_ID = "equipment.match"
_LEVELS = ("excellent", "good", "challenging", "poor")


@dataclass(frozen=True)
class Candidate:
    key: str
    level: str
    reason: str
    mode: str
    preference: int
    aperture: float | None
    magnification: float | None


def match_equipment(inputs: dict) -> dict:
    preferences = load_canonical_data("calibration/equipment-matching.json")["preferences"]
    try:
        return _match(obj(inputs), preferences)
    except ValidationError as exc:
        raise ValidationError("invalid equipment.match input") from exc


def _match(inputs: dict, p: dict) -> dict:
    r = dict(obj(inputs.get("requirement")))
    r["naked_eye_suitability"] = enum(r.get("naked_eye_suitability", "unsupported"), ("unsupported", "challenging", "preferred"))
    r["binocular_suitability"] = enum(r.get("binocular_suitability", "unsuitable"), ("unsuitable", "practical", "preferred"))
    r["smart_eaa_suitability"] = enum(r.get("smart_eaa_suitability", "poorMatch"), ("poorMatch", "supported", "preferred"))
    r["framing"] = enum(r.get("framing", "medium"), ("veryWide", "wide", "medium", "compact"))
    r["magnification_benefit"] = boolean(r.get("magnification_benefit", False))
    bounds = r.get("preferred_binocular_magnification")
    if bounds is not None:
        bounds = array(bounds)
        if len(bounds) != 2:
            raise ValidationError("range needs two bounds")
        bounds = [number(x) for x in bounds]
        if bounds[0] <= 0 or bounds[1] < bounds[0]:
            raise ValidationError("invalid range")
    r["preferred_binocular_magnification"] = bounds
    for prefix in ("binocular", "visual", "smart_eaa"):
        a, b = f"practical_{prefix}_aperture_mm", f"preferred_{prefix}_aperture_mm"
        r[a], r[b] = optional_number(r.get(a)), optional_number(r.get(b))
        if any(x is not None and x <= 0 for x in (r[a], r[b])) or (r[a] is not None and r[b] is not None and r[b] < r[a]):
            raise ValidationError("invalid thresholds")
        if prefix == "smart_eaa" and (r[a] is None) != (r[b] is None):
            raise ValidationError("smart thresholds must be paired")
    is_planet = boolean(inputs.get("is_planet", False))
    seen: set[str] = set()
    candidates = []
    for value in array(inputs.get("capabilities")):
        row = obj(value)
        k = key(row.get("key"), seen)
        kind = enum(row.get("type"), ("nakedEye", "binoculars", "visualTelescope", "smartTelescope"))
        aperture = optional_number(row.get("aperture_mm"))
        magnification = optional_number(row.get("magnification"))
        level, reason, mode, preference = _candidate(kind, aperture, magnification, is_planet, r, p)
        candidates.append(Candidate(k, level, reason, mode, preference, aperture, magnification))
    candidates.sort(key=lambda c: (_LEVELS.index(c.level), -c.preference, -(c.aperture or 0), -(c.magnification or 0), c.key.encode("utf-8")))
    if not candidates:
        return {"match": None}
    best = candidates[0]
    return {"match": {"key": best.key, "level": best.level, "reason": best.reason, "mode": best.mode,
                      "other_suitable_keys": [c.key for c in candidates[1:] if c.level in ("excellent", "good")]}}


def _candidate(kind, aperture, magnification, is_planet, r, p):
    mode = "nakedEye" if kind == "nakedEye" else "electronicallyAssisted" if kind == "smartTelescope" else "visual"

    def result(level, reason, preference):
        return level, reason, mode, p[preference]

    if kind == "nakedEye":
        suitability = r["naked_eye_suitability"]
        if suitability == "unsupported":
            return result("poor", "nakedEyeUnsupported", "none")
        if suitability == "challenging":
            return result("challenging", "nakedEyeChallenging", "naked_eye_challenging")
        return result("good" if is_planet else "excellent", "nakedEyePreferred", "naked_eye_preferred")
    broad = r["framing"] in ("veryWide", "wide")
    if kind == "binoculars":
        if r["binocular_suitability"] == "unsuitable":
            return result("poor", "modeMismatch", "none")
        practical, preferred = r["practical_binocular_aperture_mm"], r["preferred_binocular_aperture_mm"]
        if aperture is None or aperture <= 0 or practical is None or preferred is None:
            return result("challenging", "unknownRequirement", "unknown")
        bounds = r["preferred_binocular_magnification"]
        fit = "Unknown" if bounds is None or magnification is None or magnification <= 0 else "TooLow" if magnification < bounds[0] else "TooHigh" if magnification > bounds[1] else "InRange"
        if aperture < practical:
            return result("challenging", "apertureLimited" if fit == "InRange" else "apertureAndMagnificationLimited", "binocular_aperture_limited")
        if fit != "InRange":
            return result("challenging", "binocularMagnification" + fit, "binocular_magnification_limited")
        preferred_fit = r["binocular_suitability"] == "preferred" and aperture >= preferred
        reason = "wideField" if broad else "binocularMagnificationInRange" if aperture >= preferred else "practicalAperture"
        return result("excellent" if preferred_fit else "good", reason, "binocular_preferred" if preferred_fit else "binocular_practical")
    if kind == "visualTelescope":
        practical, preferred = r["practical_visual_aperture_mm"], r["preferred_visual_aperture_mm"]
        if aperture is None or aperture <= 0 or practical is None or preferred is None:
            return result("challenging", "unknownRequirement", "unknown")
        if r["framing"] == "veryWide":
            return result("challenging", "apertureLimited", "aperture_limited") if aperture < practical else result("good", "framingLimited", "very_wide_visual")
        adjustment = p["wide_visual_adjustment"] if r["framing"] == "wide" else 0
        if aperture >= preferred:
            return "excellent", "magnification" if r["magnification_benefit"] else "preferredAperture", mode, p["visual_preferred"] + adjustment
        if aperture >= practical:
            return "good", "practicalAperture", mode, p["visual_practical"] + adjustment
        return result("challenging", "apertureLimited", "aperture_limited")
    if aperture is None or aperture <= 0:
        return result("poor", "apertureLimited", "none")
    suitability = r["smart_eaa_suitability"]
    if suitability == "poorMatch":
        return result("poor", "modeMismatch", "none")
    practical, preferred = r["practical_smart_eaa_aperture_mm"], r["preferred_smart_eaa_aperture_mm"]
    if practical is None or preferred is None:
        return result("challenging", "unknownRequirement", "unknown")
    if aperture < practical:
        return result("challenging", "apertureLimited", "aperture_limited")
    if suitability == "supported":
        return result("good", "electronicSupport", "electronic_supported")
    if aperture >= preferred:
        return result("good" if broad else "excellent", "framingLimited" if broad else "electronicAssistance", "electronic_practical" if broad else "electronic_preferred")
    return result("good", "electronicAssistance", "electronic_practical")
