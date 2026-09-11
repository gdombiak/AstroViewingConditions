from __future__ import annotations

import json
from pathlib import Path

import pytest

from astro_engine.catalog import CAPABILITY_ID, load_deep_sky_catalog
from astro_engine.contracts import contracts_root, load_canonical_data
from astro_engine.errors import ValidationError

from compare import compare_envelope
from python_eval import python_envelope
from support import iter_capability_fixtures

FROZEN_IDS = [
    "m13", "m31", "m2", "m30", "m52", "m11", "m36", "m38", "m57", "m27",
    "ngc7009", "ngc7293", "m51", "m64", "m77", "m81", "m82", "m92",
    "albireo", "epsilon-lyrae", "m45", "m42", "double-cluster", "m5",
    "m3", "m16", "m20", "m33", "m101",
]
CATALOG_DIR = "fixtures/capabilities/catalog-deep-sky"


def test_canonical_catalog_is_the_only_source() -> None:
    canonical = contracts_root() / "data" / "catalog" / "deep-sky.json"
    assert canonical.is_file()
    python_root = Path(__file__).resolve().parents[1]
    copies = [
        path
        for path in python_root.rglob("deep-sky.json")
        if path.name == "deep-sky.json"
        and ".venv" not in path.parts
        and "build" not in path.parts
        and "__pycache__" not in path.parts
    ]
    assert copies == []
    swift_root = python_root.parent / "astro-engine-swift"
    swift_copies = [
        path
        for path in swift_root.rglob("deep-sky.json")
        if "Resources" not in path.parts
        and ".build" not in path.parts
        and ".swiftpm" not in path.parts
    ]
    assert swift_copies == []


def test_swift_literal_catalog_was_removed() -> None:
    source = (
        Path(__file__).resolve().parents[2]
        / "astro-engine-swift"
        / "Sources"
        / "AstroEngine"
        / "Catalog"
        / "DeepSkyCatalog.swift"
    )
    text = source.read_text(encoding="utf-8")
    assert 'entry("m13"' not in text
    assert "M13 Hercules Cluster" not in text
    assert "loadResolved" in text


def test_load_preserves_count_order_and_sentinels() -> None:
    entries = load_deep_sky_catalog()
    assert [entry["id"] for entry in entries] == FROZEN_IDS
    assert len(entries) == 29
    assert len({entry["id"] for entry in entries}) == 29
    by_id = {entry["id"]: entry for entry in entries}
    assert by_id["m20"]["right_ascension"] == 18.0433
    assert by_id["m20"]["declination"] == -23.0297
    assert by_id["m20"]["magnitude"] == 6.3
    assert by_id["m64"]["magnitude"] == 8.5
    assert by_id["double-cluster"]["display_type_name_override"] == "Open Cluster Pair"
    assert "display_type_name_override" not in by_id["m13"]
    assert by_id["m36"]["surface_brightness"] is None
    assert by_id["m13"]["object_type"] == "globular_cluster"
    assert by_id["m13"]["recommended_equipment"] == "binoculars"


def test_catalog_capability_uses_canonical_document() -> None:
    fixture = next(iter_capability_fixtures(CATALOG_DIR))
    assert fixture["id"] == "curated-v1"
    actual = python_envelope(CAPABILITY_ID, fixture["input"])
    compare_envelope(actual, fixture["expected"], policy_id="catalog_deep_sky")
    canonical = load_canonical_data("catalog/deep-sky.json")
    assert actual["result"] == canonical


def test_bool_is_rejected_as_a_number(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    catalog_dir = tmp_path / "catalog"
    catalog_dir.mkdir()
    payload = {
        "entries": [
            {
                "id": "m13",
                "common_name": "M13",
                "catalog_name": "M13",
                "object_type": "globular_cluster",
                "constellation": "Hercules",
                "right_ascension": True,
                "declination": 36.4613,
                "magnitude": 5.8,
                "apparent_size": "20 arcmin",
                "surface_brightness": 12.0,
                "difficulty": 0.55,
                "recommended_equipment": "binoculars",
                "observing_intent": "easy",
                "notes": "x",
            }
        ]
    }
    (catalog_dir / "deep-sky.json").write_text(json.dumps(payload), encoding="utf-8")
    monkeypatch.setenv("ASTRO_ENGINE_DATA_ROOT", str(tmp_path))
    with pytest.raises(ValidationError, match="finite JSON number"):
        load_deep_sky_catalog()


def test_numeric_string_is_rejected(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    catalog_dir = tmp_path / "catalog"
    catalog_dir.mkdir()
    payload = {
        "entries": [
            {
                "id": "m13",
                "common_name": "M13",
                "catalog_name": "M13",
                "object_type": "globular_cluster",
                "constellation": "Hercules",
                "right_ascension": "16.6949",
                "declination": 36.4613,
                "magnitude": 5.8,
                "apparent_size": "20 arcmin",
                "surface_brightness": 12.0,
                "difficulty": 0.55,
                "recommended_equipment": "binoculars",
                "observing_intent": "easy",
                "notes": "x",
            }
        ]
    }
    (catalog_dir / "deep-sky.json").write_text(json.dumps(payload), encoding="utf-8")
    monkeypatch.setenv("ASTRO_ENGINE_DATA_ROOT", str(tmp_path))
    with pytest.raises(ValidationError, match="finite JSON number"):
        load_deep_sky_catalog()
