"""Semantic classification of *when* heavy cloud interrupts an observing night.

Portable form of the production Swift `NightQualityAnalysisRules.cloudTiming`
rule, now owned by `AstroEngine.CloudTimingClassifier`. Normative procedure:
contracts/procedures/cloud-timing.md.

The verdict is semantics only. The English advice production builds from it
(`CloudTiming.summaryText`) is host presentation and is deliberately not
reproduced here or governed by parity.
"""

from __future__ import annotations

import math
from datetime import datetime
from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.contracts import night_quality_calibration
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.validate import parse_utc_z

CAPABILITY_ID = "night_conditions.classify_cloud_timing"

# One day of one-minute rows, the same 1.0 row cap the other row-transport
# capabilities use. A production observing night is far smaller.
MAX_ROW_COUNT = 1_440

# The shared engine integer transport magnitude: exactly representable in
# binary64 and in a Swift `Int` on every supported platform.
INTEGER_MAGNITUDE_LIMIT = 1_000_000_000

# Exactly one hour between array neighbours; production compares the Date delta
# to this literal, so 3599 and 3601 both break a run.
CONTIGUOUS_STEP_SECONDS = 3_600.0

CLASSIFICATIONS = ("none", "early_heavy", "late_heavy", "intermittent_heavy")


class HourlyRow(NamedTuple):
    """Exactly the three hourly facts the rule reads.

    Fog, moon, wind, seeing, transparency and row identity are deliberately
    absent: the classification never consults them.
    """

    time: datetime
    score: float
    cloud_cover: int


class _HeavyCloudInterval(NamedTuple):
    start_index: int
    hour_count: int
    average_cloud_cover: float
    has_usable_hours_before: bool
    has_usable_hours_after: bool


def classify(rows: Sequence[HourlyRow]) -> str:
    """Caller order **is** the rule's order: rows are never sorted, deduplicated
    or reordered.

    Thresholds come from the shared night-quality calibration: heavy is
    `cloud_floor.cloud_cover_min` inclusive, usable is strictly below
    `rating_thresholds.fair_max`.
    """
    night = night_quality_calibration()
    return _classify(
        rows,
        heavy_cloud_cover_min=int(night["cloud_floor"]["cloud_cover_min"]),
        usable_score_max=float(night["rating_thresholds"]["fair_max"]),
    )


def _classify(
    rows: Sequence[HourlyRow],
    *,
    heavy_cloud_cover_min: int,
    usable_score_max: float,
) -> str:
    interval = _preferred_heavy_cloud_interval(
        rows,
        heavy_cloud_cover_min=heavy_cloud_cover_min,
        usable_score_max=usable_score_max,
    )
    if interval is None:
        return "none"
    before, after = interval.has_usable_hours_before, interval.has_usable_hours_after
    if before and not after:
        return "late_heavy"
    if after and not before:
        return "early_heavy"
    if before and after:
        return "intermittent_heavy"
    return "none"


def _preferred_heavy_cloud_interval(
    rows: Sequence[HourlyRow],
    *,
    heavy_cloud_cover_min: int,
    usable_score_max: float,
) -> _HeavyCloudInterval | None:
    """Eligibility first — a run with no usable hour on either side is dropped
    before ranking — then longest run, then greatest average cloud cover, then
    earliest start index.
    """
    eligible = [
        interval
        for interval in _sustained_heavy_cloud_intervals(
            rows,
            heavy_cloud_cover_min=heavy_cloud_cover_min,
            usable_score_max=usable_score_max,
        )
        if interval.has_usable_hours_before or interval.has_usable_hours_after
    ]
    if not eligible:
        return None
    eligible.sort(
        key=lambda interval: (
            -interval.hour_count,
            -interval.average_cloud_cover,
            interval.start_index,
        )
    )
    return eligible[0]


def _sustained_heavy_cloud_intervals(
    rows: Sequence[HourlyRow],
    *,
    heavy_cloud_cover_min: int,
    usable_score_max: float,
) -> list[_HeavyCloudInterval]:
    """Runs of at least two heavy rows whose consecutive array neighbours are
    exactly one hour apart.

    A single heavy row never qualifies, and any non-heavy row or non-3600 second
    step — including a duplicate or backwards timestamp — closes the current run
    and may open a new one. The usable-hour tests scan the whole prefix and
    suffix around a run, not only its neighbours.
    """
    intervals: list[_HeavyCloudInterval] = []
    run_start_index: int | None = None

    def append_interval(end_index: int) -> None:
        if run_start_index is None or end_index - run_start_index < 1:
            return
        start_index = run_start_index
        run = rows[start_index : end_index + 1]
        intervals.append(_HeavyCloudInterval(
            start_index=start_index,
            hour_count=len(run),
            average_cloud_cover=(
                float(sum(row.cloud_cover for row in run)) / float(len(run))
            ),
            has_usable_hours_before=any(
                row.score < usable_score_max for row in rows[:start_index]
            ),
            has_usable_hours_after=any(
                row.score < usable_score_max for row in rows[end_index + 1 :]
            ),
        ))

    for index in range(len(rows)):
        is_heavy_cloud = rows[index].cloud_cover >= heavy_cloud_cover_min
        follows_previous_hour = index > 0 and (
            (rows[index].time - rows[index - 1].time).total_seconds()
            == CONTIGUOUS_STEP_SECONDS
        )
        if is_heavy_cloud and (run_start_index is None or follows_previous_hour):
            if run_start_index is None:
                run_start_index = index
        else:
            append_interval(index - 1)
            run_start_index = index if is_heavy_cloud else None

    append_interval(len(rows) - 1)
    return intervals


def classify_cloud_timing(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) != {"hourly_ratings"}:
        raise _invalid()
    return {"cloud_timing": classify(_parse_rows(input["hourly_ratings"]))}


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _parse_rows(value: Any) -> list[HourlyRow]:
    if not isinstance(value, list):
        raise _invalid()
    if len(value) > MAX_ROW_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)"
        )
    rows: list[HourlyRow] = []
    for row in value:
        if not isinstance(row, Mapping) or set(row) != {"time", "score", "cloud_cover"}:
            raise _invalid()
        rows.append(HourlyRow(
            _time(row["time"]),
            _number(row["score"]),
            _integer(row["cloud_cover"]),
        ))
    return rows


def _time(value: Any) -> datetime:
    try:
        return parse_utc_z(value, "time")
    except ValidationError as exc:
        raise _invalid() from exc


def _number(value: Any) -> float:
    """Production scores are the weighted 0-2 doubles; only finiteness is
    required, so a threshold-equal `1.0` stays expressible."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid()
    number = float(value)
    if not math.isfinite(number):
        raise _invalid()
    return number


def _integer(value: Any) -> int:
    """`HourlyRating.cloudCover` is an `Int` in production, so the transport is
    the shared integer form: JSON booleans are not numbers, and a non-finite,
    non-integral or unsafely large value is not an integer. `80.0` is accepted
    as `80`."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid()
    number = float(value)
    if not math.isfinite(number) or math.trunc(number) != number:
        raise _invalid()
    if abs(number) > INTEGER_MAGNITUDE_LIMIT:
        raise _invalid()
    return int(number)
