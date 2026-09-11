from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest


REPOSITORY = Path(__file__).resolve().parents[2]
SKILL = REPOSITORY / ".grok" / "skills" / "astronomer"
BOOTSTRAP_PATH = SKILL / "scripts" / "bootstrap.py"


def _load_bootstrap():
    spec = importlib.util.spec_from_file_location("astronomer_bootstrap", BOOTSTRAP_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _manifest(tmp_path: Path, *, runtime_id: str = "test-runtime") -> Path:
    path = tmp_path / f"{runtime_id}.json"
    path.write_text(json.dumps({
        "schema_version": 1,
        "runtime_id": runtime_id,
        "astro_host_version": "0.1.0",
        "astro_engine_version": "1.0.0",
        "python_requires": {"minimum": [3, 11]},
        "dependencies": ["example==1.0"],
        "artifacts": [{
            "filename": "example.whl",
            "url": "https://example.invalid/example.whl",
            "sha256": "0" * 64,
        }],
    }), encoding="utf-8")
    return path


def _fake_host(runtime: Path, *, host="0.1.0", engine="1.0.0") -> None:
    executable = runtime / ".venv" / "bin" / "astro-host"
    executable.parent.mkdir(parents=True)
    executable.write_text(
        "#!/usr/bin/env python3\n"
        "import json\n"
        f"print(json.dumps({{'ok': True, 'astro_host_version': '{host}', "
        f"'astro_engine_version': '{engine}', 'operations': "
        "['agent.conditions', 'agent.locations', 'agent.places', "
        "'agent.equipment', 'agent.recommendations']}))\n",
        encoding="utf-8",
    )
    executable.chmod(0o755)


def test_healthy_runtime_is_idempotent_and_creates_separate_state(tmp_path: Path) -> None:
    bootstrap = _load_bootstrap()
    root = tmp_path / "root"
    target = root / "runtime" / "versions" / "test-runtime"
    _fake_host(target)
    current = root / "runtime" / "current"
    current.parent.mkdir(parents=True, exist_ok=True)
    current.symlink_to(Path("versions") / "test-runtime")

    first = bootstrap.ensure_runtime(
        root=root, manifest_path=_manifest(tmp_path), install=False
    )
    second = bootstrap.ensure_runtime(
        root=root, manifest_path=_manifest(tmp_path), install=False
    )

    assert first["installed"] is False
    assert second["installed"] is False
    assert first["astro_host"] == str(target / ".venv" / "bin" / "astro-host")
    assert Path(first["state_dir"]) == root / "state"
    assert (root / "state").is_dir()


def test_upgrade_switches_atomically_and_preserves_state(tmp_path: Path, monkeypatch) -> None:
    bootstrap = _load_bootstrap()
    root = tmp_path / "root"
    state = root / "state"
    state.mkdir(parents=True)
    locations = state / "locations.json"
    locations.write_text('{"keep":true}\n', encoding="utf-8")
    old = root / "runtime" / "versions" / "old-runtime"
    _fake_host(old, host="0.0.1")
    current = root / "runtime" / "current"
    current.parent.mkdir(parents=True, exist_ok=True)
    current.symlink_to(Path("versions") / "old-runtime")

    def fake_install(staging, _state, _manifest_document, _artifact_dir):
        _fake_host(staging)
        return {
            "ok": True,
            "astro_host_version": "0.1.0",
            "astro_engine_version": "1.0.0",
            "operations": list(bootstrap.REQUIRED_OPERATIONS),
        }

    monkeypatch.setattr(bootstrap, "_install", fake_install)
    result = bootstrap.ensure_runtime(
        root=root, manifest_path=_manifest(tmp_path), install=True
    )

    assert result["installed"] is True
    assert (root / "runtime" / "current").resolve().name.startswith("test-runtime.")
    assert old.is_dir()
    assert locations.read_text(encoding="utf-8") == '{"keep":true}\n'


def test_failed_upgrade_keeps_current_runtime_and_state(tmp_path: Path, monkeypatch) -> None:
    bootstrap = _load_bootstrap()
    root = tmp_path / "root"
    state = root / "state"
    state.mkdir(parents=True)
    equipment = state / "equipment.json"
    equipment.write_text('{"keep":true}\n', encoding="utf-8")
    old = root / "runtime" / "versions" / "old-runtime"
    _fake_host(old, host="0.0.1")
    current = root / "runtime" / "current"
    current.parent.mkdir(parents=True, exist_ok=True)
    current.symlink_to(Path("versions") / "old-runtime")

    def fail(*_args, **_kwargs):
        raise bootstrap.BootstrapError("injected install failure")

    monkeypatch.setattr(bootstrap, "_install", fail)
    with pytest.raises(bootstrap.BootstrapError, match="injected install failure"):
        bootstrap.ensure_runtime(
            root=root, manifest_path=_manifest(tmp_path), install=True
        )

    assert current.resolve() == old.resolve()
    assert equipment.read_text(encoding="utf-8") == '{"keep":true}\n'
    assert {path.name for path in (root / "runtime" / "versions").iterdir()} == {
        "old-runtime"
    }


def test_production_manifest_is_exactly_pinned() -> None:
    document = json.loads((SKILL / "runtime-manifest.json").read_text(encoding="utf-8"))
    assert document["runtime_id"] == "astro-host-0.1.0_engine-1.0.0"
    assert document["astro_host_version"] == "0.1.0"
    assert document["astro_engine_version"] == "1.0.0"
    assert all("==" in item for item in document["dependencies"])
    assert all(item["url"].startswith(
        "https://github.com/gdombiak/AstroViewingConditions/releases/download/"
    ) for item in document["artifacts"])


def test_skill_routes_only_supported_operations_and_preserves_authority_rules() -> None:
    text = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    for operation in (
        "agent.conditions", "agent.places", "agent.locations",
        "agent.equipment", "agent.recommendations",
    ):
        assert operation in text
    assert "agent.batch_compare" not in text
    assert "agent.forecast_horizon" not in text
    assert "Never invent recommended targets" in text
    assert "reorder recommendations" in text
    assert "omission of `minimum_fit` must remain `any`" in text
    assert "Do not silently" in text
