from __future__ import annotations

import io
import json
from pathlib import Path

from astro_host.cli import (
    EXIT_FAILURE,
    EXIT_INVALID_REQUEST,
    EXIT_OK,
    main,
)
from astro_host.equipment import MemoryEquipmentStore
from astro_host.models import EquipmentSelectionMode

from test_equipment import S30_ID, VIRTUOSO_ID, s30, virtuoso


def invoke_equipment(
    tmp_path: Path,
    document: dict[str, object],
    *,
    store=None,
    extra_args: list[str] | None = None,
):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    argv = ["agent.equipment", "--input", str(path), *(extra_args or [])]
    status = main(argv, equipment_store=store, stdout=stdout, stderr=stderr)
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def test_cli_list_empty_ok(tmp_path: Path) -> None:
    status, payload, stderr = invoke_equipment(
        tmp_path, {"action": "list"}, store=MemoryEquipmentStore(),
    )
    assert status == EXIT_OK
    assert stderr == ""
    assert payload == {
        "ok": True,
        "operation": "agent.equipment",
        "result": {
            "action": "list",
            "items": [],
            "selection": {"mode": "all_saved"},
        },
    }


def test_cli_save_get_select_delete_round_trip(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    status, saved, _ = invoke_equipment(tmp_path, {
        "action": "save",
        "equipment": {
            "name": "S30 Pro",
            "type": "smartTelescope",
            "aperture": 30,
            "aperture_unit": "millimeters",
            "aliases": ["Seestar"],
        },
    }, store=store)
    assert status == EXIT_OK
    item_id = saved["result"]["item"]["id"]
    assert saved["result"]["selection"] == {"mode": "all_saved"}
    assert saved["result"]["selected_item"] is None
    _, listed, _ = invoke_equipment(tmp_path, {"action": "list"}, store=store)
    assert len(listed["result"]["items"]) == 1
    _, got, _ = invoke_equipment(
        tmp_path, {"action": "get", "id": item_id}, store=store,
    )
    assert got["result"]["item"]["name"] == "S30 Pro"
    _, resolved, _ = invoke_equipment(
        tmp_path, {"action": "resolve", "query": "Seestar"}, store=store,
    )
    assert resolved["result"]["item"]["id"] == item_id
    invoke_equipment(tmp_path, {
        "action": "save",
        "equipment": {
            "name": "Virtuoso",
            "type": "visualTelescope",
            "aperture": 150,
            "aperture_unit": "millimeters",
            "id": VIRTUOSO_ID,
        },
        "select": True,
    }, store=store)
    _, selected, _ = invoke_equipment(
        tmp_path, {"action": "select", "query": "S30 Pro"}, store=store,
    )
    assert selected["result"]["selection"] == {"mode": "item", "id": item_id}
    _, deleted, _ = invoke_equipment(
        tmp_path, {"action": "delete", "id": item_id}, store=store,
    )
    assert deleted["result"]["selection"] == {"mode": "all_saved"}


def test_cli_save_select_true_uses_write_snapshot(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    status, payload, _ = invoke_equipment(tmp_path, {
        "action": "save",
        "select": True,
        "equipment": {
            "name": "S30 Pro",
            "type": "smartTelescope",
            "aperture": 30,
            "aperture_unit": "millimeters",
        },
    }, store=store)
    assert status == EXIT_OK
    item_id = payload["result"]["item"]["id"]
    assert payload["result"]["selection"] == {"mode": "item", "id": item_id}
    assert payload["result"]["selected_item"]["id"] == item_id


def test_cli_save_empty_name_is_exit_2(tmp_path: Path) -> None:
    status, payload, _ = invoke_equipment(tmp_path, {
        "action": "save",
        "equipment": {
            "name": "  ",
            "type": "smartTelescope",
            "aperture": 30,
            "aperture_unit": "millimeters",
        },
    }, store=MemoryEquipmentStore())
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


def test_cli_select_must_be_json_boolean(tmp_path: Path) -> None:
    status, payload, _ = invoke_equipment(tmp_path, {
        "action": "save",
        "select": 1,
        "equipment": {
            "name": "S30 Pro",
            "type": "smartTelescope",
            "aperture": 30,
            "aperture_unit": "millimeters",
        },
    }, store=MemoryEquipmentStore())
    assert status == EXIT_INVALID_REQUEST


def test_cli_corrupt_is_not_empty_ok(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text('{"schema_version":1,"items":[', encoding="utf-8")
    status, payload, _ = invoke_equipment(
        tmp_path,
        {"action": "list"},
        extra_args=["--equipment-path", str(path)],
    )
    assert status == EXIT_FAILURE
    assert payload["ok"] is False
    assert payload["error"]["code"] == "corrupt"
    assert "result" not in payload


def test_cli_unsupported_schema(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text(
        '{"schema_version":0,"items":[],"selection":{"mode":"all_saved"}}\n',
        encoding="utf-8",
    )
    status, payload, _ = invoke_equipment(
        tmp_path,
        {"action": "list"},
        extra_args=["--equipment-path", str(path)],
    )
    assert status == EXIT_FAILURE
    assert payload["error"]["code"] == "unsupported_schema"


def test_cli_override_mode_item_is_invalid_request(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID, aliases=()), select=True)
    status, payload, _ = invoke_equipment(tmp_path, {
        "action": "get_active",
        "equipment": {"mode": "item"},
    }, store=store)
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"
    assert store.get_selected().id == S30_ID


def test_cli_inline_rejects_name_aliases_id(tmp_path: Path) -> None:
    status, payload, _ = invoke_equipment(tmp_path, {
        "action": "get_active",
        "equipment": {
            "inline": {
                "type": "smartTelescope",
                "aperture": 30,
                "aperture_unit": "millimeters",
                "name": "S30",
            }
        },
    }, store=MemoryEquipmentStore())
    assert status == EXIT_INVALID_REQUEST


def test_cli_get_active_inline_empty_store(tmp_path: Path) -> None:
    status, payload, _ = invoke_equipment(tmp_path, {
        "action": "get_active",
        "equipment": {
            "inline": {
                "type": "smartTelescope",
                "aperture": 30,
                "aperture_unit": "millimeters",
            }
        },
    }, store=MemoryEquipmentStore())
    assert status == EXIT_OK
    result = payload["result"]
    assert result["engine_has_saved_inventory"] is True
    assert result["has_saved_inventory"] is False
    assert result["override_applied"] is True
    assert result["capabilities"][0]["key"] == "override"
    assert set(result["capabilities"][0]) == {
        "key", "type", "aperture_mm", "magnification",
    }
    assert result["identities"][0]["key"] == "override"


def test_cli_get_active_naked_eye_only_empty(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    invoke_equipment(tmp_path, {"action": "select_naked_eye"}, store=store)
    status, payload, _ = invoke_equipment(
        tmp_path, {"action": "get_active"}, store=store,
    )
    assert status == EXIT_OK
    result = payload["result"]
    assert result["source"] == "naked_eye_only"
    assert result["has_saved_inventory"] is False
    assert result["engine_has_saved_inventory"] is True
    assert result["capabilities"][0]["type"] == "nakedEye"


def test_cli_select_query_is_one_atomic_call(tmp_path: Path) -> None:
    class _RecordingStore(MemoryEquipmentStore):
        def __init__(self) -> None:
            super().__init__()
            self.calls: list[tuple[str, str]] = []

        def resolve(self, query: str):
            self.calls.append(("resolve", query))
            return super().resolve(query)

        def select(self, id: str):
            self.calls.append(("select", id))
            return super().select(id)

        def select_query(self, query: str):
            self.calls.append(("select_query", query))
            return super().select_query(query)

    store = _RecordingStore()
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID))
    status, payload, _ = invoke_equipment(
        tmp_path, {"action": "select", "query": "Virtuoso"}, store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["selection"]["id"] == VIRTUOSO_ID
    assert store.calls == [("select_query", "Virtuoso")]


def test_cli_mutation_envelope_uses_write_snapshot_not_reread(
    tmp_path: Path, monkeypatch,
) -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID), select=True)

    original_select_query = MemoryEquipmentStore.select_query

    def racing_select_query(self, query: str):
        written = original_select_query(self, query)

        def later_selected():
            self.select(VIRTUOSO_ID)
            return self._document.selection

        monkeypatch.setattr(self, "get_selected", later_selected)
        return written

    monkeypatch.setattr(MemoryEquipmentStore, "select_query", racing_select_query)
    status, payload, _ = invoke_equipment(
        tmp_path, {"action": "select", "query": "S30 Pro"}, store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["selection"] == {"mode": "item", "id": S30_ID}
    assert payload["result"]["item"]["id"] == S30_ID


def test_cli_does_not_open_locations_or_weather(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    status, payload, _ = invoke_equipment(
        tmp_path, {"action": "list"}, store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["items"] == []
    assert not (tmp_path / "locations.json").exists()
    assert not (tmp_path / "weather-cache.json").exists()


def test_cli_get_active_override_mode_rejected_values(tmp_path: Path) -> None:
    for mode in ("item", "custom", "", None):
        document: dict[str, object] = {
            "action": "get_active",
            "equipment": {"mode": mode},
        }
        status, payload, _ = invoke_equipment(
            tmp_path, document, store=MemoryEquipmentStore(),
        )
        assert status == EXIT_INVALID_REQUEST
        assert payload["error"]["code"] == "invalid_request"


def test_cli_select_all_and_naked_eye(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID, aliases=()), select=True)
    _, all_saved, _ = invoke_equipment(
        tmp_path, {"action": "select_all"}, store=store,
    )
    assert all_saved["result"]["selection"] == {"mode": "all_saved"}
    assert all_saved["result"]["selected_item"] is None
    _, naked, _ = invoke_equipment(
        tmp_path, {"action": "select_naked_eye"}, store=store,
    )
    assert naked["result"]["selection"] == {"mode": "naked_eye_only"}
    assert store.get_selected().mode is EquipmentSelectionMode.NAKED_EYE_ONLY
