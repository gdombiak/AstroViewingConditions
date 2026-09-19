from __future__ import annotations

import shutil

import pytest

from astro_engine.semver import satisfies
from astro_engine.contracts import engine_semver

from compare import compare_envelope
from fixtures import iter_parity_fixtures
from swift_eval import ensure_eval_binary, resolve_eval_binary, run_swift_eval


@pytest.fixture(scope="session")
def eval_binary():
    if shutil.which("swift") is None and resolve_eval_binary() is None:
        pytest.skip("swift is not available to build astro-engine-eval")
    return ensure_eval_binary()


def test_swift_eval_matches_hand_authored_scoring_fixtures(eval_binary) -> None:
    assert eval_binary.is_file()
    fixtures = list(iter_parity_fixtures())
    version = engine_semver()
    failures: list[str] = []
    for fixture in fixtures:
        meta = fixture["meta"]
        if "swift" not in meta.get("hosts", []):
            continue
        if not satisfies(version, meta["engine_semver"]):
            continue
        code, payload, stderr = run_swift_eval(fixture["path"])
        if payload is None:
            failures.append(f"{fixture['id']}: no JSON stdout (exit {code}): {stderr}")
            continue
        compared = {
            "capability": payload.get("capability"),
            "ok": payload.get("ok"),
        }
        if payload.get("ok") is True:
            compared["result"] = payload.get("result")
        else:
            compared["error"] = payload.get("error")
        try:
            compare_envelope(compared, fixture["expected"], policy_id=meta["equality"])
        except AssertionError as exc:
            failures.append(f"{fixture['id']}: {exc}")
    assert not failures, "\n".join(failures)
