"""Shared validation errors for scoring capabilities.

ObservingQualityError stays F2-specific. New Phase 6 modules raise
ValidationError rather than broadening that name.
"""

from __future__ import annotations


class ValidationError(ValueError):
    """Input/document failed a capability contract check."""
