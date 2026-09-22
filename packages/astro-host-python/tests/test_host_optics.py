from __future__ import annotations

import json
from pathlib import Path

import pytest

from astro_host.cli import EXIT_INVALID_REQUEST, EXIT_OK, main
from astro_host.equipment import MemoryEquipmentStore
from astro_host.errors import InvalidRequestError
from astro_host.eyepieces import MemoryEyepieceStore
from astro_host.optics import explicit_optics, optical_facts, saved_optics

from test_equipment import S30_ID, VIRTUOSO_ID, binoculars, s30, virtuoso
from test_eyepieces import DELOS_ID, PANOPTIC_ID, delos, panoptic


def test_saved_combination_uses_the_engine_result(monkeypatch) -> None:
    equipment = MemoryEquipmentStore()
    eyepieces = MemoryEyepieceStore()
    equipment.save(virtuoso(id=VIRTUOSO_ID, focal_length_mm=750))
    eyepieces.save(delos(id=DELOS_ID, aliases=()))
    sentinel = {
        "magnification": 11,
        "exit_pupil_mm": None,
        "approximate_true_field_of_view_degrees": 4,
    }
    seen = {}

    def fake(payload):
        seen.update(payload)
        return sentinel

    monkeypatch.setattr("astro_host.optics.calculate_optics", fake)
    result = saved_optics(
        equipment,
        eyepieces,
        telescope_query="Virtuoso",
        eyepiece_query="8 mm Delos",
    )
    assert seen == {
        "telescope_focal_length_mm": 750,
        "eyepiece_focal_length_mm": 8,
        "telescope_aperture_mm": 150,
        "afov_degrees": 72,
    }
    assert result["combinations"][0]["optics"] == sentinel
    assert result["telescope"]["id"] == VIRTUOSO_ID
    assert result["combinations"][0]["eyepiece"]["id"] == DELOS_ID


def test_real_engine_reports_virtuoso_delos_and_missing_afov() -> None:
    equipment = MemoryEquipmentStore()
    eyepieces = MemoryEyepieceStore()
    equipment.save(virtuoso(id=VIRTUOSO_ID, focal_length_mm=750))
    eyepieces.save(delos(id=DELOS_ID, aliases=()))
    eyepieces.save(panoptic(id=PANOPTIC_ID, afov_degrees=None, aliases=()))
    result = saved_optics(
        equipment,
        eyepieces,
        telescope_id=VIRTUOSO_ID,
        all_eyepieces=True,
    )
    by_id = {
        row["eyepiece"]["id"]: row["optics"] for row in result["combinations"]
    }
    assert list(by_id) == [DELOS_ID, PANOPTIC_ID]
    assert by_id[DELOS_ID]["magnification"] == 93.75
    assert by_id[DELOS_ID]["exit_pupil_mm"] == 1.6
    assert by_id[DELOS_ID]["approximate_true_field_of_view_degrees"] == 0.768
    assert by_id[PANOPTIC_ID]["magnification"] == 750 / 24
    assert by_id[PANOPTIC_ID]["exit_pupil_mm"] == 150 / (750 / 24)
    assert by_id[PANOPTIC_ID]["approximate_true_field_of_view_degrees"] is None


def test_missing_telescope_focal_length_stays_unavailable() -> None:
    equipment = MemoryEquipmentStore()
    eyepieces = MemoryEyepieceStore()
    equipment.save(virtuoso(id=VIRTUOSO_ID))
    eyepieces.save(delos(id=DELOS_ID, aliases=()))
    result = saved_optics(
        equipment, eyepieces, telescope_id=VIRTUOSO_ID, eyepiece_id=DELOS_ID,
    )
    assert result["telescope"]["focal_length_mm"] is None
    assert result["combinations"][0]["optics"] == {
        "magnification": None,
        "exit_pupil_mm": None,
        "approximate_true_field_of_view_degrees": None,
    }


def test_saved_optics_rejects_binoculars_and_smart_telescopes(monkeypatch) -> None:
    def fail(_payload):
        raise AssertionError("saved non-visual equipment must not reach the engine")

    monkeypatch.setattr("astro_host.optics.calculate_optics", fail)
    eyepieces = MemoryEyepieceStore()
    eyepieces.save(delos(id=DELOS_ID, aliases=()))

    binocular_store = MemoryEquipmentStore()
    binocular_store.save(binoculars())
    with pytest.raises(InvalidRequestError, match="visual telescope"):
        saved_optics(
            binocular_store,
            eyepieces,
            telescope_query="Nikon 10x50",
            eyepiece_id=DELOS_ID,
        )

    smart = MemoryEquipmentStore()
    smart.save(s30(id=S30_ID, aliases=(), focal_length_mm=250))
    with pytest.raises(InvalidRequestError, match="visual telescope"):
        saved_optics(
            smart,
            eyepieces,
            telescope_id=S30_ID,
            all_eyepieces=True,
        )
    assert smart.get(S30_ID).focal_length_mm == 250


def test_explicit_numbers_are_passed_through() -> None:
    result = explicit_optics(
        telescope_focal_length_mm=750,
        eyepiece_focal_length_mm=8,
        telescope_aperture_mm=None,
        afov_degrees=72,
    )
    optics = result["combinations"][0]["optics"]
    assert optics["magnification"] == 93.75
    assert optics["exit_pupil_mm"] is None
    assert optics["approximate_true_field_of_view_degrees"] == 0.768
    assert result["telescope"]["id"] is None


def test_invalid_explicit_number_is_rejected() -> None:
    with pytest.raises(InvalidRequestError):
        optical_facts(
            telescope_focal_length_mm=0,
            eyepiece_focal_length_mm=8,
            telescope_aperture_mm=150,
            afov_degrees=72,
        )


def _invoke(tmp_path: Path, operation: str, document: dict, **kwargs):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    import io
    stdout, stderr = io.StringIO(), io.StringIO()
    status = main(
        [operation, "--input", str(path)],
        stdout=stdout,
        stderr=stderr,
        **kwargs,
    )
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def test_cli_eyepiece_round_trip_and_optics(tmp_path: Path) -> None:
    equipment = MemoryEquipmentStore()
    eyepieces = MemoryEyepieceStore()
    equipment.save(virtuoso(id=VIRTUOSO_ID, focal_length_mm=750))
    status, saved, stderr = _invoke(tmp_path, "agent.eyepieces", {
        "action": "save",
        "eyepiece": {
            "name": "8 mm Delos",
            "focal_length_mm": 8,
            "afov_degrees": 72,
            "aliases": ["Delos 8"],
            "id": DELOS_ID,
        },
    }, eyepiece_store=eyepieces)
    assert status == EXIT_OK, stderr
    assert saved["result"]["item"]["id"] == DELOS_ID
    status, listed, _ = _invoke(
        tmp_path, "agent.eyepieces", {"action": "list"}, eyepiece_store=eyepieces,
    )
    assert status == EXIT_OK
    assert listed["result"]["items"][0]["name"] == "8 mm Delos"
    status, optics, _ = _invoke(tmp_path, "agent.optics", {
        "telescope": {"id": VIRTUOSO_ID},
        "eyepieces": "saved",
    }, equipment_store=equipment, eyepiece_store=eyepieces)
    assert status == EXIT_OK
    row = optics["result"]["combinations"][0]["optics"]
    assert row["magnification"] == 93.75
    assert row["exit_pupil_mm"] == 1.6
    assert set(equipment.load().items[0].to_capability_fact().as_engine_row()) == {
        "key", "type", "aperture_mm", "magnification",
    }


def test_cli_explicit_optics_and_invalid_request(tmp_path: Path) -> None:
    status, payload, _ = _invoke(tmp_path, "agent.optics", {
        "telescope_focal_length_mm": 1200,
        "eyepiece_focal_length_mm": 10,
        "telescope_aperture_mm": 200,
    })
    assert status == EXIT_OK
    optics = payload["result"]["combinations"][0]["optics"]
    assert optics["magnification"] == 120
    assert optics["approximate_true_field_of_view_degrees"] is None
    status, rejected, _ = _invoke(tmp_path, "agent.optics", {
        "telescope_focal_length_mm": 750,
        "eyepiece_focal_length_mm": 8,
        "afov_degrees": 200,
    })
    assert status == EXIT_INVALID_REQUEST
    assert rejected["error"]["code"] == "invalid_request"


def test_cli_saved_optics_rejects_smart_telescope_and_binoculars(tmp_path: Path) -> None:
    equipment = MemoryEquipmentStore()
    eyepieces = MemoryEyepieceStore()
    equipment.save(s30(id=S30_ID, aliases=(), focal_length_mm=250))
    equipment.save(binoculars())
    eyepieces.save(delos(id=DELOS_ID, aliases=()))
    status, payload, _ = _invoke(tmp_path, "agent.optics", {
        "telescope": {"id": S30_ID},
        "eyepiece": {"id": DELOS_ID},
    }, equipment_store=equipment, eyepiece_store=eyepieces)
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"
    assert "visual telescope" in payload["error"]["message"]
    assert equipment.get(S30_ID).focal_length_mm == 250
    status, binocular_payload, _ = _invoke(tmp_path, "agent.optics", {
        "telescope": {"query": "Nikon 10x50"},
        "eyepieces": "saved",
    }, equipment_store=equipment, eyepiece_store=eyepieces)
    assert status == EXIT_INVALID_REQUEST
    assert binocular_payload["error"]["code"] == "invalid_request"


def test_cli_eyepiece_is_not_an_equipment_type(tmp_path: Path) -> None:
    status, payload, _ = _invoke(tmp_path, "agent.eyepieces", {
        "action": "save",
        "eyepiece": {
            "name": "8 mm Delos",
            "focal_length_mm": 8,
            "type": "visualTelescope",
        },
    }, eyepiece_store=MemoryEyepieceStore())
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"
