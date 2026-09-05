from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from subprocess import run

import pytest

from astro_engine.cli import EXIT_ENGINE, EXIT_OK, EXIT_USAGE, EXIT_VALIDATION
from astro_engine.jsonio import STDIN_LIMIT_BYTES
from astro_engine.observing_quality import CAPABILITY_ID

from support import compare_observing_quality_result, iter_oq_fixtures

assert STDIN_LIMIT_BYTES == 1_048_576

SRC = Path(__file__).resolve().parents[1] / "src"
CLI_MODULE = [sys.executable, "-m", "astro_engine"]
REPO_LAUNCHER = Path(__file__).resolve().parents[3] / "apps" / "cli" / "astro-engine"


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


def test_engine_version() -> None:
    code, stdout, stderr = _run(["--engine-version"])
    assert code == EXIT_OK
    assert stderr == ""
    payload = json.loads(stdout)
    assert payload == {"engine_semver": "0.1.0"}


def test_cli_all_contract_fixtures() -> None:
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
        assert envelope["engine_semver"] == "0.1.0"
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


def test_pretty_stdout_is_json_and_sorted() -> None:
    fixture = next(f for f in iter_oq_fixtures() if f["id"] == "unavailable-brightness-v1")
    code, stdout, stderr = _run(
        [CAPABILITY_ID, "--pretty", "--input", "-"],
        stdin=(fixture["path"] / "input.json").read_bytes(),
    )
    assert code == EXIT_OK
    assert stderr == ""
    assert stdout.startswith("{\n")
    json.loads(stdout)


def test_unknown_capability_is_usage() -> None:
    code, stdout, stderr = _run(["not.a.capability", "--input", "-"], stdin=b"{}")
    assert code == EXIT_USAGE
    assert stdout == ""
    assert "unknown capability" in stderr


def test_phase6_capability_ids_remain_unknown_on_cli() -> None:
    for capability in (
        "fog.score",
        "seeing.penalty",
        "transparency.penalty",
        "night_conditions.analyze",
        "night_conditions.score",
        "light_pollution.lookup",
    ):
        code, stdout, stderr = _run([capability, "--input", "-"], stdin=b"{}")
        assert code == EXIT_USAGE, capability
        assert stdout == ""
        assert "unknown capability" in stderr
        assert "F2 allow-list: observing_quality.assess" in stderr


def test_light_pollution_lookup_remains_unknown_on_cli() -> None:
    code, stdout, stderr = _run(["light_pollution.lookup", "--input", "-"], stdin=b"{}")
    assert code == EXIT_USAGE
    assert stdout == ""
    assert "unknown capability" in stderr
    assert "F2 allow-list: observing_quality.assess" in stderr


def test_malformed_json_is_validation() -> None:
    code, stdout, stderr = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b"{not json",
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "validation"
    assert envelope["engine_semver"] == "0.1.0"


def test_missing_injected_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"capability":"observing_quality.assess"}',
    )
    assert code == EXIT_VALIDATION
    envelope = json.loads(stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "validation"


def test_capability_mismatch_is_validation() -> None:
    code, stdout, _ = _run(
        [CAPABILITY_ID, "--input", "-"],
        stdin=b'{"capability":"weather.decode","injected":{"night_conditions_score":1}}',
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
    import io

    import astro_engine.cli as cli_mod

    def _boom(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("injected failure")

    monkeypatch.setattr(cli_mod, "assess_observing_quality", _boom)

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
    assert envelope["engine_semver"] == "0.1.0"
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
