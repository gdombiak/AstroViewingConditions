from __future__ import annotations

import ast
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def test_engine_has_no_host_import_back_edge() -> None:
    engine_root = REPOSITORY_ROOT / "packages" / "astro-engine-python" / "src"
    offenders: list[str] = []
    for path in engine_root.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                names = [node.module or ""]
            else:
                continue
            if any(name == "astro_host" or name.startswith("astro_host.") for name in names):
                offenders.append(str(path.relative_to(REPOSITORY_ROOT)))
    assert offenders == []


def test_launcher_stays_a_thin_host_import() -> None:
    launcher = REPOSITORY_ROOT / "apps" / "cli" / "astro-host"
    source = launcher.read_text(encoding="utf-8")
    assert "from astro_host.cli import main" in source
    assert "subprocess" not in source
    assert "astro_engine.cli" not in source


def test_host_never_uses_engine_cli_or_private_capability_dispatch() -> None:
    host_root = REPOSITORY_ROOT / "packages" / "astro-host-python" / "src"
    source = "\n".join(
        path.read_text(encoding="utf-8") for path in host_root.rglob("*.py")
    )
    assert "astro_engine.cli" not in source
    assert "astro_engine._capability" not in source
    assert "subprocess" not in source


def test_public_exports_include_location_store() -> None:
    import astro_host

    for name in (
        "FileLocationStore",
        "MemoryLocationStore",
        "SavedLocation",
        "SavedLocationDraft",
        "LocationState",
        "ObservingLocationService",
        "PlaceCandidate",
        "canonicalize_location_id",
        "normalize_label",
        "default_locations_path",
    ):
        assert name in astro_host.__all__
        assert hasattr(astro_host, name)
    assert "_encode_document" not in astro_host.__all__


def test_public_exports_include_equipment_store() -> None:
    import astro_host

    for name in (
        "FileEquipmentStore",
        "MemoryEquipmentStore",
        "SavedEquipment",
        "SavedEquipmentDraft",
        "InlineEquipmentDraft",
        "EquipmentOverrideMode",
        "EquipmentState",
        "EquipmentSessionService",
        "compose_active",
        "canonicalize_equipment_id",
        "default_equipment_path",
    ):
        assert name in astro_host.__all__
        assert hasattr(astro_host, name)
    assert "_encode_document" not in astro_host.__all__
    source = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "equipment.py"
    ).read_text(encoding="utf-8")
    assert "match_equipment" not in source
    assert "filter_recommendations_by_equipment" not in source
    session = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "equipment_session.py"
    ).read_text(encoding="utf-8")
    assert "match_equipment" not in session
    assert "filter_recommendations" not in session


def test_public_exports_include_recommendations() -> None:
    import astro_host

    for name in (
        "RecommendationService",
        "RecommendationEngine",
        "RecommendationsResult",
        "HostRecommendationsRequest",
        "MinimumFit",
    ):
        assert name in astro_host.__all__
        assert hasattr(astro_host, name)
    source = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "recommendations.py"
    ).read_text(encoding="utf-8")
    assert "_project_hourly_ratings" not in source
    assert "_project_moon_observation" not in source
    assert "from astro_engine" not in source
    assert "_PLANET_IDS" not in source
    engine = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "engine.py"
    ).read_text(encoding="utf-8")
    assert "_CATALOG_TYPES" not in engine
    assert "self.recorded" not in engine
