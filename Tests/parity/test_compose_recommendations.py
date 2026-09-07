"""Contract, parity and fail-closed checks for the mixed-target composition slice."""
import json
import subprocess

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from astro_engine._capability import evaluate_capability
from astro_engine.errors import SampleCapError, ValidationError
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import ensure_eval_binary, run_swift_eval

CAPABILITY = "targets.compose_recommendations"

CASES = [f for f in iter_deterministic_fixtures()
         if f["meta"]["capability"] == CAPABILITY]


@pytest.mark.parametrize("fixture", CASES, ids=lambda f: f["id"])
def test_compose_recommendations_exact_both_directions(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope(CAPABILITY, fixture["input"])
    for actual, expected in ((swift, fixture["expected"]), (python, fixture["expected"]),
                             (swift, python), (python, swift)):
        compare_envelope(actual, expected, policy_id="compose_recommendations")


def test_compose_catalog_and_fixture_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text()
    catalog_ids = [line.split(": ", 1)[1] for line in catalog.splitlines()
                   if line.startswith("  - id: ")]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-5] == CAPABILITY
    block = catalog.split(f"  - id: {CAPABILITY}\n", 1)[1].split("  - id:", 1)[0]
    assert 'since: "1.0.0"' in block
    assert "hosts: [ios, cli]" in block
    assert "equality: compose_recommendations" in block
    assert "requires_injected: [candidates, limit]" in block

    procedure = (contracts_root() / "procedures/compose-recommendations.md").read_text()
    assert "Composition boundary" in procedure
    assert CAPABILITY in procedure

    fields = load_policy_fields("compose_recommendations")
    assert fields["selected"] == "exact"
    assert fields["selected[].index"] == "exact"
    assert fields["selected[].key"] == "exact"

    assert len(CASES) == 44
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["equality"] == "compose_recommendations"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def _document(candidates, limit):
    return {"capability": CAPABILITY, "injected": {"candidates": candidates, "limit": limit}}


def _swift(document, tmp_path):
    directory = tmp_path / "fixture"
    directory.mkdir(exist_ok=True)
    (directory / "input.json").write_text(json.dumps(document), encoding="utf-8")
    (directory / "meta.yaml").write_text(f"capability: {CAPABILITY}\n", encoding="utf-8")
    code, envelope, stderr = run_swift_eval(directory)
    assert envelope is not None, stderr
    envelope.pop("engine_semver", None)
    return code, envelope


def _python(document):
    return python_envelope(CAPABILITY, document)


def _row(key, score, best_time):
    return {"key": key, "score": score, "best_time": best_time}


def test_specialized_scores_are_never_generically_rescored(tmp_path):
    """A generic re-score would have to read the candidate's target facts.

    The transport has none: a candidate row is exactly key/score/best_time. This
    test pins that a Moon row with a high specialized score outranks better
    placed deep-sky rows, and that the reverse holds for a low planet score, so
    an accidental re-score anywhere in the composition path is observable.
    """
    candidates = [
        _row("m31-w1", 62, "2026-03-01T22:00:00Z"),
        _row("moon", 91, "2026-03-01T23:30:00Z"),
        _row("venus", 18, "2026-03-01T18:30:00Z"),
    ]
    document = _document(candidates, 3)
    code, swift = _swift(document, tmp_path)
    python = _python(document)
    assert code == 0
    assert swift == python
    assert [row["key"] for row in swift["result"]["selected"]] == ["moon", "m31-w1", "venus"]


def test_candidate_input_order_is_the_final_tie_breaker(tmp_path):
    candidates = [_row(key, 66, "2026-03-01T21:00:00Z")
                  for key in ("venus", "m45-w1", "moon", "mars")]
    document = _document(candidates, 10)
    code, swift = _swift(document, tmp_path)
    assert code == 0
    assert swift == _python(document)
    assert [row["index"] for row in swift["result"]["selected"]] == [0, 1, 2, 3]


@pytest.mark.parametrize(
    "limit", [0, -1, 7, 1441, 100_000, 1_000_000_000, -1441, -1_000_000_000])
def test_limit_semantics_agree_on_both_hosts(limit, tmp_path):
    """`limit` has no semantic bound. Above the 1440 row cap it cannot add work
    or output; below zero it selects nothing."""
    candidates = [
        _row("moon", 84, "2026-03-01T21:00:00Z"),
        _row("jupiter", 73, "2026-03-01T23:00:00Z"),
        _row("m31-w1", 61, "2026-03-01T22:00:00Z"),
    ]
    document = _document(candidates, limit)
    code, swift = _swift(document, tmp_path)
    assert code == 0
    assert swift == _python(document)
    assert len(swift["result"]["selected"]) == min(max(0, limit), 3)


def test_duplicate_keys_are_accepted_and_never_deduplicated(tmp_path):
    candidates = [
        _row("m31", 50, "2026-03-01T22:00:00Z"),
        _row("m31", 70, "2026-03-01T22:00:00Z"),
        _row("m31", 50, "2026-03-01T21:00:00Z"),
    ]
    document = _document(candidates, 5)
    code, swift = _swift(document, tmp_path)
    assert code == 0
    assert swift == _python(document)
    assert [row["index"] for row in swift["result"]["selected"]] == [1, 2, 0]


@pytest.mark.parametrize("injected", [
    {"candidates": [], "limit": 5, "tie_breaker": "type"},
    {"candidates": []},
    {"limit": 5},
    {"candidates": [{"key": "moon", "score": 84,
                     "best_time": "2026-03-01T21:00:00Z", "type": "moon"}], "limit": 5},
    {"candidates": [_row("moon", True, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [], "limit": True},
    {"candidates": [_row("moon", 84.5, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [_row("moon", 101, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [_row("moon", -1, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [_row("", 84, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [], "limit": 1_000_000_001},
    {"candidates": [], "limit": -1_000_000_001},
    {"candidates": [_row("moon", 84, "1999-12-31T21:59:59Z")], "limit": 5},
    {"candidates": [_row("moon", 84, "2500-01-01T01:15:00Z")], "limit": 5},
])
def test_invalid_documents_fail_closed_identically(injected, tmp_path):
    document = {"capability": CAPABILITY, "injected": injected}
    expected = {"code": "validation", "message": f"invalid {CAPABILITY} input"}
    with pytest.raises(ValidationError) as excinfo:
        evaluate_capability(CAPABILITY, document)
    assert str(excinfo.value) == expected["message"]

    code, swift = _swift(document, tmp_path)
    assert code == 2
    assert swift["ok"] is False
    assert swift["error"] == expected


def test_row_cap_is_reported_identically(tmp_path):
    rows = [_row(f"t{index}", 50, "2026-03-01T21:00:00Z") for index in range(1441)]
    document = _document(rows, 5)
    message = f"{CAPABILITY} exceeds the 1.0 row cap (1440 rows)"

    with pytest.raises(SampleCapError) as excinfo:
        evaluate_capability(CAPABILITY, document)
    assert str(excinfo.value) == message

    code, swift = _swift(document, tmp_path)
    assert code == 2
    assert swift["error"] == {"code": "sample_cap", "message": message}


def test_public_cli_speaks_the_capability(tmp_path):
    document = _document([_row("moon", 84, "2026-03-01T21:00:00Z")], 5)
    path = tmp_path / "input.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    result = subprocess.run(
        [str(ensure_eval_binary()), CAPABILITY, "--input", str(path)],
        capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    envelope = json.loads(result.stdout)
    assert envelope["result"] == {"selected": [{"index": 0, "key": "moon"}]}
