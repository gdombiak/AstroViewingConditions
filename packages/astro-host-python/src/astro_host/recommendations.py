"""Host composition for ``agent.recommendations``."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Mapping

from astro_host.conditions import ConditionsService
from astro_host.engine import RecommendationEngine
from astro_host.errors import HostInvariantError
from astro_host.models import (
    ActiveEquipment,
    ConditionsRequest,
    ConditionsResult,
    ConditionsStatus,
    EmptyReason,
    EquipmentFitFacts,
    Location,
    LocationSource,
    MinimumFit,
    RecommendationEquipmentContext,
    RecommendationFamily,
    RecommendationNightContext,
    RecommendationRow,
    RecommendationsResult,
    ScoringPath,
    VisibilityWindow,
)


CANDIDATE_POOL_LIMIT = 100
FINAL_LIMIT = 5
DEFAULT_MINIMUM_FIT = MinimumFit.ANY

SOLAR_SYSTEM_DISPLAY_NAMES = {
    "moon": "Moon",
    "venus": "Venus",
    "mars": "Mars",
    "jupiter": "Jupiter",
    "saturn": "Saturn",
}


@dataclass
class _HostCandidate:
    key: str
    target_id: str
    name: str
    family: RecommendationFamily
    type: str
    object_type: str | None
    score: int
    scoring_path: ScoringPath
    visibility_window: VisibilityWindow
    reasons: tuple[str, ...]
    requirement: Mapping[str, object] | None = None
    is_planet: bool = False


class RecommendationService:
    def __init__(
        self,
        conditions: ConditionsService,
        *,
        engine: RecommendationEngine | None = None,
    ) -> None:
        self._conditions = conditions
        self._engine = engine or RecommendationEngine()

    async def recommend(
        self,
        *,
        location: Location,
        location_source: LocationSource,
        reference_time: datetime,
        observing_date=None,
        force_refresh: bool = False,
        equipment: ActiveEquipment,
        minimum_fit: MinimumFit = DEFAULT_MINIMUM_FIT,
    ) -> RecommendationsResult:
        conditions = await self._conditions.conditions(
            ConditionsRequest(
                location=location,
                reference_time=reference_time,
                observing_date=observing_date,
                force_refresh=force_refresh,
            )
        )
        equipment_context = _equipment_context(equipment, minimum_fit)
        if conditions.status is ConditionsStatus.UNAVAILABLE:
            return _unavailable_result(
                conditions, location, location_source, equipment_context
            )
        _require_ranking_facts(conditions)
        mixed = self._mixed_candidates(conditions, location)
        compose_rows = [
            (row.key, row.score, row.visibility_window.best_time) for row in mixed
        ]
        compose_indices = self._engine.compose_recommendations(
            compose_rows, limit=CANDIDATE_POOL_LIMIT
        )
        pool = _remap(mixed, compose_indices)
        self._attach_requirements(pool)
        filter_indices = self._engine.filter_recommendations(
            [
                (row.key, row.is_planet, row.requirement or {})
                for row in pool
            ],
            equipment,
            minimum_fit.value,
        )
        filtered = _remap(pool, filter_indices)
        visible = filtered[:FINAL_LIMIT]
        rows = tuple(
            self._visible_row(index, row, equipment)
            for index, row in enumerate(visible, start=1)
        )
        empty_reason = _empty_reason(
            conditions.status, len(pool), len(filtered), len(rows)
        )
        return RecommendationsResult(
            status=conditions.status,
            generated_at=conditions.generated_at,
            engine_semver=conditions.engine_semver,
            location_source=location_source,
            location=location,
            night=_night_context(conditions),
            observing_quality_score=(
                None
                if conditions.observing_quality is None
                else conditions.observing_quality.score
            ),
            equipment=equipment_context,
            pool_size=len(pool),
            filtered_size=len(filtered),
            empty_reason=empty_reason,
            recommendations=rows,
            issues=conditions.issues,
            acquisition=conditions.acquisition,
        )

    def _mixed_candidates(
        self, conditions: ConditionsResult, location: Location
    ) -> list[_HostCandidate]:
        selected = conditions.selected_night
        night_conditions = conditions.night_conditions
        assert selected is not None
        assert night_conditions is not None
        night_start = selected.astronomical_night_start
        night_end = selected.astronomical_night_end
        observing_day_start = selected.observing_day_start
        assert night_start is not None
        assert night_end is not None
        assert observing_day_start is not None
        cloud = night_conditions.details["cloud_cover_score"]
        ratings = night_conditions.hourly_ratings
        best_window = night_conditions.best_window
        mixed: list[_HostCandidate] = []
        solar = self._engine.solar_system()
        deep_sky = self._engine.deep_sky()
        moon_facts = self._engine.moon_info(location, observing_day_start)

        for entry in solar:
            target_id = str(entry["id"])
            entry_type = entry.get("type")
            if entry_type == "moon":
                observation = self._engine.moon_observation(
                    location, night_start, night_end
                )
                recommendation = self._engine.moon_recommendation(
                    observation,
                    night_start=night_start,
                    night_end=night_end,
                    cloud_cover_score=cloud,
                    hourly_ratings=ratings,
                    best_window=best_window,
                )
                if recommendation is None:
                    continue
                mixed.append(
                    _specialized_candidate(
                        target_id=target_id,
                        name=SOLAR_SYSTEM_DISPLAY_NAMES.get(target_id, target_id),
                        family=RecommendationFamily.MOON,
                        type="moon",
                        scoring_path=ScoringPath.MOON_RECOMMENDATION,
                        recommendation=recommendation,
                        engine=self._engine,
                    )
                )
            elif entry_type == "planet":
                observation = self._engine.planet_observation(
                    target_id, location, night_start, night_end
                )
                if observation is None:
                    continue
                recommendation = self._engine.planet_recommendation(
                    target_id,
                    observation["samples"],
                    night_start=night_start,
                    night_end=night_end,
                    cloud_cover_score=cloud,
                    hourly_ratings=ratings,
                )
                if recommendation is None:
                    continue
                mixed.append(
                    _specialized_candidate(
                        target_id=target_id,
                        name=SOLAR_SYSTEM_DISPLAY_NAMES.get(target_id, target_id),
                        family=RecommendationFamily.PLANET,
                        type="planet",
                        scoring_path=ScoringPath.PLANET_RECOMMENDATION,
                        recommendation=recommendation,
                        engine=self._engine,
                    )
                )

        dso_rows: list[
            tuple[str, str, float, float, datetime, datetime, datetime, float]
        ] = []
        dso_meta: dict[str, tuple[dict[str, object], VisibilityWindow, float]] = {}
        for entry in deep_sky:
            target_id = str(entry["id"])
            sensitivity = self._engine.moon_sensitivity(
                str(entry["object_type"]),
                None if entry["surface_brightness"] is None else float(entry["surface_brightness"]),
            )
            windows = self._engine.deep_sky_windows(
                target_id, location, night_start, night_end
            )
            for window in windows:
                parsed = self._engine.parse_visibility_window(window)
                key = f"{target_id}@{_instant_key(parsed.start)}@{_instant_key(parsed.end)}"
                dso_rows.append(
                    (
                        key,
                        str(entry["object_type"]),
                        float(entry["difficulty"]),
                        sensitivity,
                        parsed.start,
                        parsed.end,
                        parsed.best_time,
                        parsed.max_altitude,
                    )
                )
                dso_meta[key] = (entry, parsed, sensitivity)
        if dso_rows:
            scores = self._engine.recommend_deep_sky(
                darkness_start=night_start,
                darkness_end=night_end,
                moon=moon_facts,
                cloud_cover_score=cloud,
                hourly_ratings=ratings,
                rows=dso_rows,
            )
            for key, *_rest in dso_rows:
                entry, window, _ = dso_meta[key]
                mixed.append(
                    _HostCandidate(
                        key=key,
                        target_id=str(entry["id"]),
                        name=str(entry["common_name"]),
                        family=RecommendationFamily.DEEP_SKY,
                        type="deepSky",
                        object_type=self._engine.catalog_object_type(str(entry["object_type"])),
                        score=scores[key],
                        scoring_path=ScoringPath.TARGETS_RECOMMEND,
                        visibility_window=window,
                        reasons=(),
                    )
                )
        return mixed

    def _attach_requirements(self, pool: list[_HostCandidate]) -> None:
        cache: dict[str, dict[str, object]] = {}
        for row in pool:
            resolved = cache.get(row.target_id)
            if resolved is None:
                resolved = self._engine.requirements(row.target_id)
                cache[row.target_id] = resolved
            row.requirement = resolved["requirement"]
            row.is_planet = bool(resolved["is_planet"])

    def _visible_row(
        self,
        rank: int,
        row: _HostCandidate,
        equipment: ActiveEquipment,
    ) -> RecommendationRow:
        assert row.requirement is not None
        fit = None
        if equipment.capabilities:
            match = self._engine.match_equipment(
                row.requirement, row.is_planet, equipment
            )
            if match is not None:
                identities = {item.key: item for item in equipment.identities}
                fit = EquipmentFitFacts(
                    key=str(match["key"]),
                    level=str(match["level"]),
                    reason=str(match["reason"]),
                    mode=str(match["mode"]),
                    other_suitable_keys=tuple(
                        str(key) for key in match["other_suitable_keys"]
                    ),
                    identity=identities.get(str(match["key"])),
                )
        return RecommendationRow(
            rank=rank,
            key=row.key,
            target_id=row.target_id,
            name=row.name,
            family=row.family,
            type=row.type,
            object_type=row.object_type,
            score=row.score,
            scoring_path=row.scoring_path,
            visibility_window=row.visibility_window,
            reasons=row.reasons,
            requirement=row.requirement,
            is_planet=row.is_planet,
            equipment_fit=fit,
        )


def _specialized_candidate(
    *,
    target_id: str,
    name: str,
    family: RecommendationFamily,
    type: str,
    scoring_path: ScoringPath,
    recommendation: Mapping[str, object],
    engine: RecommendationEngine,
) -> _HostCandidate:
    window = engine.parse_visibility_window(recommendation["visibility_window"])
    reasons = tuple(str(item) for item in recommendation["reasons"])
    return _HostCandidate(
        key=target_id,
        target_id=target_id,
        name=name,
        family=family,
        type=type,
        object_type=None,
        score=int(recommendation["score"]),
        scoring_path=scoring_path,
        visibility_window=window,
        reasons=reasons,
    )


def _remap(rows: list[_HostCandidate], indices: list[int]) -> list[_HostCandidate]:
    return [rows[index] for index in indices]


def _require_ranking_facts(conditions: ConditionsResult) -> None:
    selected = conditions.selected_night
    missing: list[str] = []
    if selected is None:
        missing.append("selected_night")
    else:
        if selected.astronomical_night_start is None:
            missing.append("astronomical_night_start")
        if selected.astronomical_night_end is None:
            missing.append("astronomical_night_end")
        if selected.observing_day_start is None:
            missing.append("observing_day_start")
    if conditions.night_conditions is None:
        missing.append("night_conditions")
    elif "cloud_cover_score" not in conditions.night_conditions.details:
        missing.append("cloud_cover_score")
    if missing:
        raise HostInvariantError(
            "complete/degraded conditions result is missing ranking facts: "
            + ", ".join(missing),
            details={"missing": missing},
        )


def _night_context(conditions: ConditionsResult) -> RecommendationNightContext:
    selected = conditions.selected_night
    night = conditions.night_conditions
    return RecommendationNightContext(
        selection=None if selected is None else selected.selection,
        state=None if selected is None else selected.state,
        observing_date=None if selected is None else selected.observing_date,
        observing_day_start=None if selected is None else selected.observing_day_start,
        astronomical_night_start=(
            None if selected is None else selected.astronomical_night_start
        ),
        astronomical_night_end=(
            None if selected is None else selected.astronomical_night_end
        ),
        best_window=None if night is None else night.best_window,
        public_score=None if night is None else night.public_score,
        rating=None if night is None else night.rating,
        cloud_timing=None if night is None else night.cloud_timing,
    )


def _equipment_context(
    equipment: ActiveEquipment, minimum_fit: MinimumFit
) -> RecommendationEquipmentContext:
    return RecommendationEquipmentContext(
        source=equipment.source,
        override_applied=equipment.override_applied,
        has_saved_inventory=equipment.has_saved_inventory,
        engine_has_saved_inventory=equipment.engine_has_saved_inventory,
        selection=equipment.selection,
        identities=equipment.identities,
        minimum_fit=minimum_fit,
    )


def _unavailable_result(
    conditions: ConditionsResult,
    location: Location,
    location_source: LocationSource,
    equipment: RecommendationEquipmentContext,
) -> RecommendationsResult:
    return RecommendationsResult(
        status=conditions.status,
        generated_at=conditions.generated_at,
        engine_semver=conditions.engine_semver,
        location_source=location_source,
        location=location,
        night=_night_context(conditions),
        observing_quality_score=(
            None
            if conditions.observing_quality is None
            else conditions.observing_quality.score
        ),
        equipment=equipment,
        pool_size=0,
        filtered_size=0,
        empty_reason=None,
        recommendations=(),
        issues=conditions.issues,
        acquisition=conditions.acquisition,
    )


def _empty_reason(
    status: ConditionsStatus, pool_size: int, filtered_size: int, visible: int
) -> EmptyReason | None:
    if status is ConditionsStatus.UNAVAILABLE or visible:
        return None
    if pool_size == 0:
        return EmptyReason.NO_VISIBLE_CANDIDATES
    if filtered_size == 0:
        return EmptyReason.NONE_MEET_EQUIPMENT_FIT
    return None


def _instant_key(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
