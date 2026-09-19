"""Final deterministic composition of already-scored recommendation candidates.

Normative procedure: contracts/procedures/compose-recommendations.md. Portable
form of the last decision in the production
`DefaultTargetRecommendationService.recommendations(for:limit:)`: order the
candidates globally and truncate to `limit`.

Nothing here scores anything. Every row arrives already scored by whichever
path the host applied to it — `targets.moon_recommendation` or
`targets.planet_recommendation` where a specialized result exists, and the
generic `targets.recommend` path otherwise, including the production
fall-through when a specialized provider returns nothing. Scores and best times
are injected verbatim and are never recomputed, renormalized or reweighted; an
existing specialized Moon or planet score is never rescored.
"""

from __future__ import annotations

import math
from datetime import datetime, timezone
from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.validate import UTC_Z_PATTERN

CAPABILITY_ID = "targets.compose_recommendations"

_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# `best_time` accepts the union of the visibility_window instant ranges the
# three recommendation capabilities can emit. targets.deep_sky_windows and
# targets.moon_recommendation stay inside the plain modern product range;
# targets.planet_recommendation spills -7200 / +4500 around it, so the widest of
# the three is the accepted range here and every production recommendation is
# composable verbatim. Fixed transport literals, not calibration reads.
NIGHT_RANGE_START_EPOCH_SECONDS = 946_684_800.0
NIGHT_RANGE_END_EPOCH_SECONDS = 16_725_225_599.0
SPILL_BEFORE_SECONDS = 2 * 3600.0
SPILL_AFTER_SECONDS = 3600.0 + 900.0

# 1999-12-31T22:00:00Z ... 2500-01-01T01:14:59Z.
EARLIEST_EPOCH_SECONDS = NIGHT_RANGE_START_EPOCH_SECONDS - SPILL_BEFORE_SECONDS
LATEST_EPOCH_SECONDS = NIGHT_RANGE_END_EPOCH_SECONDS + SPILL_AFTER_SECONDS

# One day of one-minute candidate rows, the same 1.0 row cap the other target
# capabilities use.
MAX_ROW_COUNT = 1_440

# `limit` carries no semantic bound: production is `prefix(max(0, limit))` over
# an array the row cap already bounds, so a limit above the cap cannot add work
# or output and a negative one selects nothing. Only the shared engine
# integer-transport magnitude applies — the same targets.moon_recommendation
# convention — which keeps the value exactly representable in binary64 and in a
# Swift `Int` on every supported platform.
INTEGER_MAGNITUDE_LIMIT = 1_000_000_000

# `TargetRecommendation.init` clamps the production score to 0...100, so that is
# the integer domain a composable candidate can carry.
MIN_SCORE = 0
MAX_SCORE = 100


class Candidate(NamedTuple):
    """The minimum frozen row production ordering needs.

    Target metadata, window endpoints, reasons, summaries, astronomy facts,
    weather facts and equipment facts are deliberately absent: none of them can
    change the order, and the host keeps its own recommendation objects.
    """

    key: str
    score: int
    best_time: float


class Selection(NamedTuple):
    """A selected row in final production order.

    `index` is the caller's original position and is the unambiguous mapping
    handle; `key` is echoed caller identity and never participates in ordering.
    """

    index: int
    key: str


def selected(candidates: Sequence[Candidate], limit: int) -> list[Selection]:
    """Score descending, best time ascending, original input index ascending,
    truncated to `max(0, limit)`."""
    order = sorted(
        range(len(candidates)),
        key=lambda index: (-candidates[index].score, candidates[index].best_time, index),
    )
    return [Selection(index, candidates[index].key) for index in order[: max(0, limit)]]


# --- transport ------------------------------------------------------------


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _key(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise _invalid()
    return value


def _integer(value: Any) -> int:
    """The shared engine integer transport, as targets.moon_recommendation
    defines it: JSON booleans are not numbers, and a non-finite, non-integral or
    unsafely large value is not an integer. `5.0` is accepted as `5`, the same
    way targets.recommend accepts an integral moon illumination."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid()
    try:
        number = float(value)
    except OverflowError as exc:
        raise _invalid() from exc
    if not math.isfinite(number) or math.trunc(number) != number:
        raise _invalid()
    if abs(number) > INTEGER_MAGNITUDE_LIMIT:
        raise _invalid()
    return int(number)


def _score(value: Any) -> int:
    """The production recommendation score domain on top of that transport."""
    score = _integer(value)
    if not MIN_SCORE <= score <= MAX_SCORE:
        raise _invalid()
    return score


def _epoch_seconds(value: Any) -> float:
    if not isinstance(value, str) or not UTC_Z_PATTERN.fullmatch(value):
        raise _invalid()
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise _invalid() from exc
    seconds = (parsed - _EPOCH).total_seconds()
    if not EARLIEST_EPOCH_SECONDS <= seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid()
    return seconds


def _parse_candidates(value: Any) -> list[Candidate]:
    """Caller order is semantically significant: it is the last tie breaker, so
    the rows are never sorted or deduplicated during parsing.

    Duplicate `key` values are accepted. One production target can contribute
    more than one candidate (a deep-sky target with several visibility windows),
    production never deduplicates them, and the host maps a selection back
    through `index`, which is unique by construction. This is the one place the
    composition transport deliberately differs from targets.recommend, whose
    keys are its only output handle.
    """
    if not isinstance(value, list):
        raise _invalid()
    if len(value) > MAX_ROW_COUNT:
        raise SampleCapError(f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)")
    rows: list[Candidate] = []
    for row in value:
        if not isinstance(row, Mapping) or set(row) != {"key", "score", "best_time"}:
            raise _invalid()
        rows.append(Candidate(
            _key(row["key"]),
            _score(row["score"]),
            _epoch_seconds(row["best_time"]),
        ))
    return rows


def compose_recommendations(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping):
        raise _invalid()
    if set(input) != {"candidates", "limit"}:
        raise _invalid()

    # Field order matches the Swift transport so a document with more than one
    # defect reports the same code and message on both hosts.
    candidates = _parse_candidates(input["candidates"])
    limit = _integer(input["limit"])

    return {
        "selected": [
            {"index": row.index, "key": row.key}
            for row in selected(candidates, limit)
        ]
    }
