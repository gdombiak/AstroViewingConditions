"""Shared validation errors for scoring and decode capabilities.

ObservingQualityError stays F2-specific. Phase 6+ modules raise
ValidationError rather than broadening that name.
"""

from __future__ import annotations


class ValidationError(ValueError):
    """Input/document failed a capability contract check."""

    code = "validation"


class FixtureRefError(ValidationError):
    """Provider `$ref` failed to resolve under `contracts/fixtures`."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class GridCapError(ValidationError):
    """location.grid exceeded the 1.0 iOS geometry cap."""

    code = "grid_cap"


class AtlasInvalidError(ValidationError):
    """LPATLAS1 artifact failed header/DFS validation at load."""

    code = "atlas_invalid"
