"""Locate immutable production resources in a release wheel or checkout."""

from __future__ import annotations

import os
from pathlib import Path


PRODUCTION_ATLAS_FILENAME = "light_pollution_global_v1.bin"
_ATLAS_ENV = "ASTRO_ENGINE_ATLAS_PATH"
_PACKAGE_ATLAS = (
    Path(__file__).resolve().parent / "resources" / PRODUCTION_ATLAS_FILENAME
)
_REPO_ATLAS_CANDIDATES = (
    Path("Sources/AstroViewingConditions/Resources/LightPollution")
    / PRODUCTION_ATLAS_FILENAME,
    Path("apps/ios/Sources/AstroViewingConditions/Resources/LightPollution")
    / PRODUCTION_ATLAS_FILENAME,
)
MAX_ATLAS_WALK = 16


def default_atlas_path(*, start: Path | None = None) -> Path | None:
    """Resolve the production LPATLAS1 file without loading it.

    Order: `ASTRO_ENGINE_ATLAS_PATH` if it names an existing file; then the
    release-wheel resource; then the existing iOS app resource in a checkout.
    Contract test fixtures are never searched.
    """
    env = os.environ.get(_ATLAS_ENV)
    if env:
        path = Path(env)
        if path.is_file():
            return path
    if _PACKAGE_ATLAS.is_file():
        return _PACKAGE_ATLAS.resolve()
    return _repo_checkout_atlas(start=start)


def _repo_checkout_atlas(*, start: Path | None = None) -> Path | None:
    here = (start or Path(__file__)).resolve()
    if here.is_file():
        here = here.parent
    for _ in range(MAX_ATLAS_WALK):
        for relative in _REPO_ATLAS_CANDIDATES:
            candidate = here / relative
            if candidate.is_file():
                return candidate.resolve()
        parent = here.parent
        if parent == here:
            break
        here = parent
    return None
