from __future__ import annotations

import io
import json
import os
import socket
import sys
from pathlib import Path
from subprocess import run

import pytest

from astro_engine._capability import CapabilityHost, evaluate_capability
from astro_engine.cli import (
    EXIT_ENGINE,
    EXIT_OK,
    EXIT_USAGE,
    EXIT_VALIDATION,
    PRODUCTION_ATLAS_FILENAME,
    PUBLIC_CAPABILITY_IDS,
    default_atlas_path,
)
from astro_engine.contracts import load_fixture_ref
from astro_engine.jsonio import STDIN_LIMIT_BYTES
from astro_engine.observing_quality import CAPABILITY_ID
from lp_support import contract_tiny_bin

from compare import compare_envelope
from support import compare_observing_quality_result, iter_capability_fixtures, iter_oq_fixtures

assert STDIN_LIMIT_BYTES == 1_048_576

SRC = Path(__file__).resolve().parents[1] / "src"
CLI_MODULE = [sys.executable, "-m", "astro_engine"]
REPO_LAUNCHER = Path(__file__).resolve().parents[3] / "apps" / "cli" / "astro-engine"

REPRESENTATIVE_FIXTURES: tuple[tuple[str, str, str], ...] = (
    ("observing_quality.assess", "fixtures/capabilities/observing-quality", "home-backyard-v1"),
    ("night_conditions.analyze", "fixtures/capabilities/night-conditions", "four-clear-hours-v1"),
    ("night_conditions.score", "fixtures/capabilities/night-conditions-score", "excellent-zeros-v1"),
    ("fog.score", "fixtures/capabilities/fog", "humidity-95-v1"),
    ("seeing.penalty", "fixtures/capabilities/seeing", "delta-1-v1"),
    ("transparency.penalty", "fixtures/capabilities/transparency", "clear-vis-20km-v1"),
    (
        "light_pollution.lookup",
        "fixtures/capabilities/light-pollution-lookup",
        "tiny-constant-v1",
    ),
    ("weather.decode", "fixtures/capabilities/weather-decode", "happy-path"),
    ("iss.decode", "fixtures/capabilities/iss-decode", "two-passes"),
    ("location.grid", "fixtures/capabilities/location-grid", "nyc-10-5-v1"),
    ("location.compare", "fixtures/capabilities/location-compare", "public-score-wins-v1"),
    ("catalog.deep_sky", "fixtures/capabilities/catalog-deep-sky", "curated-v1"),
    ("targets.recommend", "fixtures/capabilities/targets-recommend", "basic-v1"),
    ("equipment.match", "fixtures/capabilities/equipment-match", "selected-ranking-v1"),
    ("observing_window.select", "fixtures/capabilities/observing-window", "empty-v1"),
    ("targets.requirements", "fixtures/capabilities/target-metadata", "override-m77"),
    ("catalog.solar_system", "fixtures/capabilities/target-metadata", "solar-production-order"),
    ("targets.moon_sensitivity", "fixtures/capabilities/target-metadata", "sensitivity-bright-boundary"),
    ("astronomy.horizontal_position", "fixtures/capabilities/horizontal-position", "catalog-m13-nyc-v1"),
    ("targets.deep_sky_windows", "fixtures/capabilities/deep-sky-windows", "catalog-m13-nyc-v1"),
)

UNIMPLEMENTED_IDS = (
    "astronomy.planet_positions",
    "agent.conditions",
    "light_pollution.validity",
)


def _env(**overrides: str) -> dict[str, str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(SRC) + os.pathsep + env.get("PYTHONPATH", "")
    env.update(overrides)
    return env


def _run(
    args: list[str],
    *,
    stdin: bytes | None = None,
    env: dict[str, str] | None = None,
    argv0: list[str] | None = None,
) -> tuple[int, str, str]:
    completed = run(
        [*(argv0 or CLI_MODULE), *args],
        input=stdin,
        capture_output=True,
        env=env or _env(),
        check=False,
    )
    return completed.returncode, completed.stdout.decode(), completed.stderr.decode()


def _load_named(relative: str, fixture_id: str) -> dict:
    return next(item for item in iter_capability_fixtures(relative) if item["id"] == fixture_id)


def _assert_cli_success(capability: str, fixture: dict) -> dict:
    raw = (fixture["path"] / "input.json").read_bytes()
    code, stdout, stderr = _run([capability, "--input", "-"], stdin=raw)
    assert code == EXIT_OK, (capability, fixture["id"], stderr, stdout)
    assert stderr == ""
    envelope = json.loads(stdout)
    assert envelope["ok"] is True
    assert envelope["capability"] == capability
    assert envelope["engine_semver"] == "1.0.0"
    assert "engine_semver" not in fixture["expected"]
    compare_envelope(envelope, fixture["expected"], policy_id=fixture["meta"]["equality"])
    return envelope


def test_engine_version() -> None:
    code, stdout, stderr = _run(["--engine-version"])
    assert code == EXIT_OK
    assert stderr == ""
    payload = json.loads(stdout)
    assert payload == {"engine_semver": "1.0.0"}


def test_public_allow_list_matches_catalog_order() -> None:
    assert PUBLIC_CAPABILITY_IDS == tuple(item[0] for item in REPRESENTATIVE_FIXTURES) + (
        "astronomy.sun_events", "astronomy.moon_info", "astronomy.moon_series")
    assert len(set(PUBLIC_CAPABILITY_IDS)) == 23


def test_every_public_capability_is_accepted() -> None:
    for capability, relative, fixture_id in REPRESENTATIVE_FIXTURES:
        fixture = _load_named(relative, fixture_id)
        envelope = _assert_cli_success(capability, fixture)
        assert envelope["capability"] == capability


def test_cli_all_observing_quality_contract_fixtures() -> None:
    for fixture in iter_oq_fixtures():
        raw = (fixture["path"] / "input.json").read_bytes()
        code, stdout, stderr = _run(
            [CAPABILITY_ID, "--input", "-"],
            stdin=raw,
        )
        assert code == EXIT_OK, (fixture["id"], stderr, stdout)
        envelope = json.loads(stdout)
        assert envelope["ok"] is True
        assert envelope["capability"] == CAPABILITY_ID
        assert envelope["engine_semver"] == "1.0.0"
        assert "engine_semver" not in fixture["expected"]
        compare_observing_quality_result(
            envelope["result"],
            fixture["expected"]["result"],
            policy_id=fixture["meta"]["equality"],
        )


def test_cli_input_file_and_repo_launcher() -> None:
    fixture = next(f for f in iter_oq_fixtures() if f["id"] == "home-backyard-v1")
    completed = run(
        [sys.executable, str(REPO_LAUNCHER), CAPABILITY_ID, "--input", str(fixture["path"] / "input.json")],
        capture_output=True,
        env=_env(),
        check=False,
    )
    assert completed.returncode == EXIT_OK, completed.stderr.decode()
    envelope = json.loads(completed.stdout.decode())
    compare_observing_quality_result(
        envelope["result"],
        fixture["expected"]["result"],
        policy_id="observing_quality",
    )


def test_pretty_stdout_is_json_and_semantic_content_unchanged() -> None:
    fixture = _load_named("fixtures/capabilities/weather-decode", "happy-path")
    raw = (fixture["path"] / "input.json").read_bytes()
    compact_code, compact_out, compact_err = _run(
        ["weather.decode", "--input", "-"],
        stdin=raw,
    )
    pretty_code, pretty_out, pretty_err = _run(
        ["weather.decode", "--pretty", "--input", "-"],
        stdin=raw,
    )
    assert compact_code == EXIT_OK
    assert pretty_code == EXIT_OK
    assert compact_err == ""
    assert pretty_err == ""
    assert pretty_out.startswith("{\n")
    compact = json.loads(compact_out)
    pretty = json.loads(pretty_out)
    assert pretty["ok"] is True
    assert pretty["capability"] == compact["capability"]
    assert pretty["engine_semver"] == compact["engine_semver"]
    compare_envelope(pretty, fixture["expected"], policy_id="weather_decode")
    compare_envelope(compact, fixture["expected"], policy_id="weather_decode")


def test_unknown_capability_is_usage() -> None:
    code, stdout, stderr = _run(["not.a.capability", "--input", "-"], stdin=b"{}")
    assert code == EXIT_USAGE
    assert stdout == ""
    assert "unknown capability" in stderr
    assert "1.0 allow-list:" in stderr
    for capability in PUBLIC_CAPABILITY_IDS:
        assert capability in stderr


def test_one_one_capability_ids_remain_unknown_on_cli() -> None:
    for capability in UNIMPLEMENTED_IDS:
        code, stdout, stderr = _run([capability, "--input", "-"], stdin=b"{}")
        assert code == EXIT_USAGE, capability
        assert stdout == ""
        assert "unknown capability" in stderr
        assert "1.0 allow-list:" in stderr


def test_known_capability_validation_error_is_json_exit_2() -> None:
    fixture = _load_named("fixtures/capabilities/night-conditions", "missing-moon-timestamp-v1")
    raw = (fixture["path"] / "input.json").read_bytes()
    code, stdout, stderr = _run(["night_conditions.analyze", "--input", "-"], stdin=raw)
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["capability"] == "night_conditions.analyze"
    assert envelope["engine_semver"] == "1.0.0"
    assert envelope["error"]["code"] == "validation"
    compare_envelope(envelope, fixture["expected"], policy_id="engine_error")


def test_malformed_json_is_validation() -> None:
    code, stdout, stderr = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b"{not json",
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "validation"
    assert envelope["engine_semver"] == "1.0.0"


def test_missing_injected_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"capability":"observing_quality.assess"}',
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "validation"


def test_catalog_requires_injected_object() -> None:
    code, stdout, _ = _run(
        ["catalog.deep_sky", "--input", "-"],
        stdin=b'{"capability":"catalog.deep_sky"}',
    )
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["error"]["code"] == "validation"


def test_capability_mismatch_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"capability":"weather.decode","injected":{"night_conditions_score":1}}',
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "validation"
    assert envelope["capability"] == CAPABILITY_ID


def test_extra_top_level_key_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"injected":{"night_conditions_score":1},"nope":true}',
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "validation"
    assert "nope" in envelope["error"]["message"]


def test_clock_is_rejected_on_observing_quality() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"clock":"2026-03-01T12:00:00Z","injected":{"night_conditions_score":1}}',
    )
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["error"]["code"] == "validation"


def test_non_integral_night_score_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"injected":{"night_conditions_score":72.5,"modeled_zenith_sky_brightness":null}}',
    )
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["ok"] is False


def test_boolean_night_score_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"injected":{"night_conditions_score":true}}',
    )
    assert code == EXIT_VALIDATION


def test_python_nan_constant_is_rejected() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"injected":{"night_conditions_score":1,"modeled_zenith_sky_brightness":NaN}}',
    )
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["error"]["code"] == "validation"


def test_stdin_over_1_mib_is_payload_too_large() -> None:
    oversized = b"{" + (b"a" * (1_048_576)) + b"}"
    assert len(oversized) > 1_048_576
    code, stdout, _ = _run([CAPABILITY_ID, "--input", "-"], stdin=oversized)
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "payload_too_large"
    assert envelope["capability"] == CAPABILITY_ID


def test_file_over_1_mib_is_payload_too_large(tmp_path: Path) -> None:
    path = tmp_path / "too-big.json"
    path.write_bytes(b"{" + (b"a" * 1_048_576) + b"}")
    assert path.stat().st_size > 1_048_576
    code, stdout, _ = _run(["fog.score", "--input", str(path)])
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "payload_too_large"
    assert envelope["capability"] == "fog.score"


def test_grid_cap_survives_as_grid_cap() -> None:
    payload = {
        "capability": "location.grid",
        "injected": {
            "center": {"latitude": 0.0, "longitude": 0.0},
            "radius_miles": 51,
            "spacing_miles": 3,
        },
    }
    code, stdout, _ = _run(
        ["location.grid", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["capability"] == "location.grid"
    assert envelope["error"]["code"] == "grid_cap"


def test_pathological_tiny_spacing_grid_returns_promptly() -> None:
    import time

    payload = {
        "capability": "location.grid",
        "injected": {
            "center": {"latitude": 0.0, "longitude": 0.0},
            "radius_miles": 50,
            "spacing_miles": 1e-12,
        },
    }
    started = time.perf_counter()
    code, stdout, _ = _run(
        ["location.grid", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    elapsed = time.perf_counter() - started
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["error"]["code"] == "grid_cap"
    assert elapsed < 2.0


def test_weather_decode_accepts_inline_provider_envelope() -> None:
    provider = load_fixture_ref("providers/open-meteo/forecast/happy-path.json")
    document = {"capability": "weather.decode", "injected": provider}
    fixture = _load_named("fixtures/capabilities/weather-decode", "happy-path")
    code, stdout, stderr = _run(
        ["weather.decode", "--input", "-"],
        stdin=json.dumps(document).encode(),
    )
    assert code == EXIT_OK, stderr
    compare_envelope(
        json.loads(stdout),
        fixture["expected"],
        policy_id="weather_decode",
    )


def test_iss_decode_accepts_inline_provider_envelope() -> None:
    provider = load_fixture_ref("providers/n2yo/visualpasses/two-passes.json")
    document = {"capability": "iss.decode", "injected": provider}
    fixture = _load_named("fixtures/capabilities/iss-decode", "two-passes")
    code, stdout, stderr = _run(
        ["iss.decode", "--input", "-"],
        stdin=json.dumps(document).encode(),
    )
    assert code == EXIT_OK, stderr
    compare_envelope(json.loads(stdout), fixture["expected"], policy_id="iss_decode")


def test_light_pollution_ref_escape_is_ref_escape() -> None:
    payload = {
        "capability": "light_pollution.lookup",
        "injected": {
            "latitude": 0,
            "longitude": 0,
            "artifact": {"$ref": "../ENGINE_VERSION"},
        },
    }
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "ref_escape"


def test_light_pollution_host_path_is_not_read(tmp_path: Path) -> None:
    secret = tmp_path / "secret.bin"
    secret.write_bytes(b"not-an-atlas")
    payload = {
        "capability": "light_pollution.lookup",
        "injected": {
            "latitude": 0,
            "longitude": 0,
            "artifact": {"path": str(secret)},
        },
    }
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "validation"
    assert envelope["error"]["code"] != "atlas_invalid"


def _lp_coords() -> dict[str, float]:
    return {"latitude": 74.9125, "longitude": -179.9125}


def _lp_production_envelope() -> bytes:
    return json.dumps(
        {
            "capability": "light_pollution.lookup",
            "injected": _lp_coords(),
        }
    ).encode()


def test_evaluate_capability_host_atlas_without_ref() -> None:
    result = evaluate_capability(
        "light_pollution.lookup",
        {"capability": "light_pollution.lookup", "injected": _lp_coords()},
        host=CapabilityHost(atlas_path=contract_tiny_bin()),
    )
    expected = _load_named(
        "fixtures/capabilities/light-pollution-lookup", "tiny-constant-v1"
    )
    compare_envelope(
        {
            "capability": "light_pollution.lookup",
            "ok": True,
            "result": result,
        },
        expected["expected"],
        policy_id="light_pollution_lookup",
    )


def test_cli_default_atlas_via_env() -> None:
    expected = _load_named(
        "fixtures/capabilities/light-pollution-lookup", "tiny-constant-v1"
    )
    code, stdout, stderr = _run(
        ["light_pollution.lookup", "--input", "-"],
        stdin=_lp_production_envelope(),
        env=_env(ASTRO_ENGINE_ATLAS_PATH=str(contract_tiny_bin())),
    )
    assert code == EXIT_OK, stderr
    compare_envelope(json.loads(stdout), expected["expected"], policy_id="light_pollution_lookup")


def test_cli_atlas_path_override() -> None:
    expected = _load_named(
        "fixtures/capabilities/light-pollution-lookup", "tiny-constant-v1"
    )
    code, stdout, stderr = _run(
        [
            "light_pollution.lookup",
            "--atlas-path",
            str(contract_tiny_bin()),
            "--input",
            "-",
        ],
        stdin=_lp_production_envelope(),
    )
    assert code == EXIT_OK, stderr
    compare_envelope(json.loads(stdout), expected["expected"], policy_id="light_pollution_lookup")


def test_atlas_path_rejected_for_non_lp_capability() -> None:
    code, stdout, stderr = _run(
        ["fog.score", "--atlas-path", str(contract_tiny_bin()), "--input", "-"],
        stdin=b'{"injected":{"humidity":80,"temperature":15,"wind_speed":5}}',
    )
    assert code == EXIT_USAGE
    assert stdout == ""
    assert "--atlas-path is only valid with light_pollution.lookup" in stderr


def test_malformed_atlas_path_is_atlas_invalid(tmp_path: Path) -> None:
    hostile = tmp_path / "hostile.bin"
    hostile.write_bytes(b"not-an-lpatlas1-artifact")
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--atlas-path", str(hostile), "--input", "-"],
        stdin=_lp_production_envelope(),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "atlas_invalid"


def test_nonexistent_atlas_path_is_validation() -> None:
    missing = Path("/tmp/astro-engine-atlas-does-not-exist.bin")
    assert not missing.exists()
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--atlas-path", str(missing), "--input", "-"],
        stdin=_lp_production_envelope(),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "validation"
    assert envelope["capability"] == "light_pollution.lookup"


def test_missing_default_atlas_is_engine_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    import astro_engine.cli as cli_mod

    monkeypatch.setattr(cli_mod, "default_atlas_path", lambda **_kwargs: None)
    monkeypatch.delenv("ASTRO_ENGINE_ATLAS_PATH", raising=False)

    class _Stdin:
        buffer = io.BytesIO(_lp_production_envelope())

    stdout = io.StringIO()
    stderr = io.StringIO()
    monkeypatch.setattr(cli_mod.sys, "stdin", _Stdin())
    monkeypatch.setattr(cli_mod.sys, "stdout", stdout)
    monkeypatch.setattr(cli_mod.sys, "stderr", stderr)
    code = cli_mod.main(["light_pollution.lookup", "--input", "-"])
    assert code == EXIT_ENGINE
    envelope = json.loads(stdout.getvalue())
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "engine_failure"
    assert "atlas" in envelope["error"]["message"]
    assert stderr.getvalue() != ""


def test_default_atlas_path_reuses_ios_production_artifact(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("ASTRO_ENGINE_ATLAS_PATH", raising=False)
    path = default_atlas_path()
    assert path is not None
    assert path.name == PRODUCTION_ATLAS_FILENAME
    assert path.is_file()
    assert "Resources/LightPollution" in str(path)
    assert "contracts/fixtures" not in str(path)


def test_stale_atlas_env_falls_through_to_repo_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    missing = Path("/tmp/astro-engine-stale-atlas-does-not-exist.bin")
    assert not missing.exists()
    monkeypatch.setenv("ASTRO_ENGINE_ATLAS_PATH", str(missing))
    path = default_atlas_path()
    assert path is not None
    assert path.is_file()
    assert path.name == PRODUCTION_ATLAS_FILENAME
    assert "Resources/LightPollution" in str(path)


def test_valid_atlas_env_takes_precedence_over_repo_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tiny = contract_tiny_bin()
    monkeypatch.setenv("ASTRO_ENGINE_ATLAS_PATH", str(tiny))
    path = default_atlas_path()
    assert path is not None
    assert path.is_file()
    assert path.resolve() == tiny.resolve()
    assert path.name != PRODUCTION_ATLAS_FILENAME


def test_stale_atlas_env_does_not_rescue_explicit_bad_atlas_path() -> None:
    missing = Path("/tmp/astro-engine-atlas-does-not-exist.bin")
    assert not missing.exists()
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--atlas-path", str(missing), "--input", "-"],
        stdin=_lp_production_envelope(),
        env=_env(ASTRO_ENGINE_ATLAS_PATH="/tmp/astro-engine-stale-atlas-does-not-exist.bin"),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "validation"


def test_json_artifact_path_still_rejected_when_default_exists() -> None:
    secret = Path("/etc/passwd")
    payload = {
        "capability": "light_pollution.lookup",
        "injected": {**_lp_coords(), "artifact": {"path": str(secret)}},
    }
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["error"]["code"] == "validation"


def test_light_pollution_non_atlas_ref_is_atlas_invalid() -> None:
    payload = {
        "capability": "light_pollution.lookup",
        "injected": {
            "latitude": 0,
            "longitude": 0,
            "artifact": {"$ref": "providers/open-meteo/forecast/happy-path.json"},
        },
    }
    code, stdout, _ = _run(
        ["light_pollution.lookup", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["error"]["code"] == "atlas_invalid"


def test_weather_fixture_missing_is_fixture_missing() -> None:
    payload = {
        "capability": "weather.decode",
        "injected": {"$ref": "providers/open-meteo/forecast/does-not-exist.json"},
    }
    code, stdout, _ = _run(
        ["weather.decode", "--input", "-"],
        stdin=json.dumps(payload).encode(),
    )
    assert code == EXIT_VALIDATION
    assert json.loads(stdout)["error"]["code"] == "fixture_missing"


def test_diagnostics_do_not_contaminate_success_stdout() -> None:
    fixture = next(f for f in iter_oq_fixtures() if f["id"] == "anchor-18-5-v1")
    code, stdout, stderr = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=(fixture["path"] / "input.json").read_bytes(),
    )
    assert code == EXIT_OK
    assert stderr == ""
    json.loads(stdout)
    assert stdout.endswith("}\n") or stdout.endswith("}")


def test_missing_capability_is_usage() -> None:
    code, stdout, stderr = _run([])
    assert code == EXIT_USAGE
    assert stdout == ""
    assert "usage:" in stderr


def test_engine_version_combined_with_capability_is_usage() -> None:
    code, stdout, stderr = _run(["--engine-version", CAPABILITY_ID])
    assert code == EXIT_USAGE
    assert stdout == ""
    assert stderr != ""


def test_engine_failure_emits_json_envelope(monkeypatch: pytest.MonkeyPatch) -> None:
    import astro_engine.cli as cli_mod

    def _boom(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("injected failure")

    monkeypatch.setattr(cli_mod, "evaluate_capability", _boom)

    class _Stdin:
        buffer = io.BytesIO(
            b'{"injected":{"night_conditions_score":1,"modeled_zenith_sky_brightness":null}}'
        )

    monkeypatch.setattr(cli_mod.sys, "stdin", _Stdin())
    stdout = io.StringIO()
    stderr = io.StringIO()
    monkeypatch.setattr(cli_mod.sys, "stdout", stdout)
    monkeypatch.setattr(cli_mod.sys, "stderr", stderr)
    code = cli_mod.main([CAPABILITY_ID, "--input", "-"])
    assert code == EXIT_ENGINE
    envelope = json.loads(stdout.getvalue())
    assert envelope["ok"] is False
    assert envelope["capability"] == CAPABILITY_ID
    assert envelope["engine_semver"] == "1.0.0"
    assert envelope["error"]["code"] == "engine_failure"
    assert "injected failure" in envelope["error"]["message"]
    assert "injected failure" in stderr.getvalue()


def test_missing_contracts_omits_engine_semver() -> None:
    missing = str(Path("/tmp/astro-engine-missing-contracts-does-not-exist"))
    code, stdout, stderr = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"injected":{"night_conditions_score":1}}',
        env=_env(CONTRACTS_ROOT=missing),
    )
    assert code == EXIT_ENGINE
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["capability"] == CAPABILITY_ID
    assert envelope["error"]["code"] == "engine_failure"
    assert "engine_semver" not in envelope
    assert stderr != ""


def test_engine_version_missing_contracts_omits_semver() -> None:
    missing = str(Path("/tmp/astro-engine-missing-contracts-does-not-exist"))
    code, stdout, stderr = _run(
        ["--engine-version"],
        env=_env(CONTRACTS_ROOT=missing),
    )
    assert code == EXIT_ENGINE
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "engine_failure"
    assert "engine_semver" not in envelope
    assert "capability" not in envelope
    assert stderr != ""


def test_cli_capabilities_do_not_open_sockets(monkeypatch: pytest.MonkeyPatch) -> None:
    import astro_engine.cli as cli_mod

    def _blocked(*_args: object, **_kwargs: object) -> socket.socket:
        raise AssertionError("CLI capability must not open a network socket")

    monkeypatch.setattr(socket, "socket", _blocked)

    for capability, relative, fixture_id in REPRESENTATIVE_FIXTURES:
        raw = (_load_named(relative, fixture_id)["path"] / "input.json").read_bytes()

        class _Stdin:
            buffer = io.BytesIO(raw)

        stdout = io.StringIO()
        stderr = io.StringIO()
        monkeypatch.setattr(cli_mod.sys, "stdin", _Stdin())
        monkeypatch.setattr(cli_mod.sys, "stdout", stdout)
        monkeypatch.setattr(cli_mod.sys, "stderr", stderr)
        code = cli_mod.main([capability, "--input", "-"])
        assert code == EXIT_OK, (capability, stderr.getvalue(), stdout.getvalue())


def test_repo_launcher_does_not_mask_internal_import_error(tmp_path: Path) -> None:
    fake_root = tmp_path / "fake"
    pkg = fake_root / "astro_engine"
    pkg.mkdir(parents=True)
    (pkg / "__init__.py").write_text("", encoding="utf-8")
    (pkg / "cli.py").write_text("from not_a_real_astro_engine_module import x\n", encoding="utf-8")
    env = os.environ.copy()
    env["PYTHONPATH"] = str(fake_root)
    completed = run(
        [sys.executable, str(REPO_LAUNCHER), "--engine-version"],
        capture_output=True,
        env=env,
        check=False,
    )
    assert completed.returncode != 0
    err = completed.stderr.decode()
    assert "not_a_real_astro_engine_module" in err
    assert completed.stdout.decode() == ""
