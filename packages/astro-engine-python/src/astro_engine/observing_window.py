"""Production observing-window decisions over already-included scored rows.

Normative procedure: contracts/procedures/observing-window.md. No astronomy.
"""
from __future__ import annotations

from datetime import timedelta
from typing import Any, Mapping

from astro_engine.contracts import night_quality_calibration
from astro_engine.errors import ValidationError
from astro_engine.validate import parse_utc_z, require_finite_number

CAPABILITY_ID = "observing_window.select"


def select_observing_window(input: Mapping[str, Any]) -> dict[str, Any]:
    try:
        return _select(input)
    except (ValidationError, OverflowError, ValueError) as exc:
        raise ValidationError("invalid observing_window.select input") from exc


def _select(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) - {
        "hourly_ratings", "good_rating_threshold"
    }:
        raise ValidationError("invalid input")
    rows = input.get("hourly_ratings")
    if not isinstance(rows, list):
        raise ValidationError("invalid rows")
    ratings = []
    for row in rows:
        if not isinstance(row, Mapping) or set(row) != {"time", "score"}:
            raise ValidationError("invalid row")
        ratings.append((
            parse_utc_z(row["time"], "time"),
            require_finite_number(row["score"], "score"),
        ))
    threshold = (
        require_finite_number(input["good_rating_threshold"], "good_rating_threshold")
        if "good_rating_threshold" in input
        else float(night_quality_calibration()["rating_thresholds"]["fair_max"])
    )
    ratings.sort(key=lambda row: row[0])
    if not ratings:
        return {"best_window": None}
    good_count = sum(score < threshold for _, score in ratings)
    if good_count == 0:
        start = min(ratings, key=lambda row: row[1])[0]
        end = start + timedelta(seconds=3600)
    elif float(good_count) / float(len(ratings)) >= 0.5:
        start, end = ratings[0][0], ratings[-1][0]
    else:
        longest_start = ratings[0][0]
        longest_length = 0
        current_start = None
        current_length = 0
        for time, score in ratings:
            if score < threshold:
                if current_start is None:
                    current_start = time
                current_length += 3600
            else:
                if current_start is not None and current_length > longest_length:
                    longest_start, longest_length = current_start, current_length
                current_start, current_length = None, 0
        if current_start is not None and current_length > longest_length:
            longest_start, longest_length = current_start, current_length
        start = longest_start
        end = start + timedelta(seconds=longest_length)
    # isoformat preserves four-digit years even where strftime('%Y') does not.
    return {
        "best_window": {
            "start": start.isoformat().replace("+00:00", "Z"),
            "end": end.isoformat().replace("+00:00", "Z"),
        }
    }
