"""Repository-relative paths for the harness."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config"
CACHE = ROOT / "cache"
OUTPUT = ROOT / "output"
VIEWER = ROOT / "viewer"
DEFAULT_SOURCE = Path.home() / "Downloads" / "zenith_brightness_v22_2025.tiff"
