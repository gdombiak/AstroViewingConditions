"""Disk space and size estimation safeguards."""

from __future__ import annotations

import os
import shutil
from pathlib import Path


def free_bytes(path: str | Path) -> int:
    usage = shutil.disk_usage(path)
    return int(usage.free)


def ensure_space(path: str | Path, needed_bytes: int, margin: float = 1.25) -> None:
    free = free_bytes(path)
    require = int(needed_bytes * margin)
    if free < require:
        raise RuntimeError(
            f"Insufficient disk space at {path}: need ~{require / 1e6:.1f} MB "
            f"(including margin), have {free / 1e6:.1f} MB free"
        )


def estimate_array_bytes(shape: tuple[int, ...], dtype_bytes: int) -> int:
    n = 1
    for s in shape:
        n *= int(s)
    return n * dtype_bytes


def human_bytes(n: int | float) -> str:
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024 or unit == "TB":
            return f"{n:.2f} {unit}"
        n /= 1024.0
    return f"{n:.2f} TB"
