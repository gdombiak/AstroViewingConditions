"""Private Python scoring adapter. Does not go through the public CLI."""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine._capability import evaluate_scoring_capability
from astro_engine.errors import ValidationError
from astro_engine.observing_quality import ObservingQualityError


def python_envelope(capability: str, document: Mapping[str, Any]) -> dict[str, Any]:
    try:
        result = evaluate_scoring_capability(capability, document)
        return {
            "capability": capability,
            "ok": True,
            "result": result,
        }
    except (ValidationError, ObservingQualityError) as exc:
        return {
            "capability": capability,
            "ok": False,
            "error": {"code": "validation", "message": str(exc)},
        }
