"""Minimal dotted-triple semver comparison for fixture applicability ranges."""

from __future__ import annotations


class SemverError(ValueError):
    pass


def parse(version: str) -> tuple[int, int, int]:
    text = version.strip()
    parts = text.split(".")
    if len(parts) != 3 or any(not p.isdigit() for p in parts):
        raise SemverError(f"unsupported version {version!r}; expected X.Y.Z")
    return int(parts[0]), int(parts[1]), int(parts[2])


def satisfies(version: str, range_expr: str) -> bool:
    """Return True if `version` satisfies a space-separated AND of ops.

    Supported tokens: >=X.Y.Z, >X.Y.Z, <=X.Y.Z, <X.Y.Z, ==X.Y.Z
    """
    actual = parse(version)
    tokens = range_expr.strip().split()
    if not tokens:
        raise SemverError("empty version range")
    for token in tokens:
        if token.startswith(">="):
            if actual < parse(token[2:]):
                return False
        elif token.startswith("<="):
            if actual > parse(token[2:]):
                return False
        elif token.startswith("=="):
            if actual != parse(token[2:]):
                return False
        elif token.startswith(">"):
            if actual <= parse(token[1:]):
                return False
        elif token.startswith("<"):
            if actual >= parse(token[1:]):
                return False
        else:
            raise SemverError(f"unsupported range token {token!r}")
    return True
