"""Minimal JSON CLI for observing_quality.assess (F2).

Stdout is JSON:
- successful capability invocation → ok:true envelope, exit 0
- successful --engine-version → {"engine_semver":"<version>"} (no ok), exit 0
- validation/input → ok:false, error.code, exit 2
- engine/runtime (including --engine-version bootstrap failure) →
  ok:false, error.code=engine_failure, exit 1; omit engine_semver if unknown
Usage / unknown capability → no stdout JSON, exit 3.
Stderr is diagnostics only.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Mapping, TextIO

from astro_engine.contracts import ContractsRootError, engine_semver
from astro_engine.jsonio import JSONCodecError, STDIN_LIMIT_BYTES, dump_json, load_json_bytes
from astro_engine.observing_quality import CAPABILITY_ID, ObservingQualityError, assess_observing_quality

EXIT_OK = 0
EXIT_ENGINE = 1
EXIT_VALIDATION = 2
EXIT_USAGE = 3

USAGE = """\
usage: astro-engine --engine-version
       astro-engine <capability-id> --input -|FILE [--pretty]

F2 allow-list: observing_quality.assess
"""


class _Parser(argparse.ArgumentParser):
    def print_usage(self, file: TextIO | None = None) -> None:
        print(USAGE, end="", file=file or sys.stderr)

    def print_help(self, file: TextIO | None = None) -> None:
        print(USAGE, end="", file=file or sys.stderr)

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(message, file=sys.stderr)
        raise SystemExit(EXIT_USAGE)


def _parser() -> argparse.ArgumentParser:
    parser = _Parser(add_help=True, prog="astro-engine")
    parser.add_argument("capability", nargs="?")
    parser.add_argument("--engine-version", action="store_true")
    parser.add_argument("--input", dest="input_path")
    parser.add_argument("--pretty", action="store_true")
    return parser


def _write_envelope(payload: Mapping[str, Any], *, pretty: bool) -> None:
    sys.stdout.write(dump_json(payload, pretty=pretty))
    sys.stdout.flush()


def _try_engine_semver() -> str | None:
    """Return ENGINE_VERSION, or None if contracts cannot be resolved.

    Do not fabricate a version. Callers omit `engine_semver` from the envelope
    when this returns None (bootstrap failure).
    """
    try:
        return engine_semver()
    except ContractsRootError:
        return None


def _error_envelope(
    capability: str | None,
    code: str,
    message: str,
    *,
    pretty: bool,
    version: str | None = None,
) -> None:
    payload: dict[str, Any] = {
        "ok": False,
        "error": {"code": code, "message": message},
    }
    if capability is not None:
        payload["capability"] = capability
    if version is not None:
        payload["engine_semver"] = version
    _write_envelope(payload, pretty=pretty)


def _read_input_bytes(input_path: str) -> bytes:
    if input_path == "-":
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = sys.stdin.buffer.read(64 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > STDIN_LIMIT_BYTES:
                raise PayloadTooLarge()
            chunks.append(chunk)
        return b"".join(chunks)
    path = Path(input_path)
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise ObservingQualityError(f"cannot read input file: {exc}") from exc
    if size > STDIN_LIMIT_BYTES:
        raise PayloadTooLarge()
    data = path.read_bytes()
    if len(data) > STDIN_LIMIT_BYTES:
        raise PayloadTooLarge()
    return data


class PayloadTooLarge(Exception):
    pass


def _extract_injected(document: Any, argv_capability: str) -> tuple[Any, Any]:
    if not isinstance(document, dict):
        raise ObservingQualityError("input JSON must be an object")
    allowed_top = {"capability", "injected"}
    extra = set(document) - allowed_top
    if extra:
        raise ObservingQualityError(f"unexpected top-level keys: {sorted(extra)}")
    if "capability" in document and document["capability"] != argv_capability:
        raise ObservingQualityError(
            "input capability does not match the invoked capability-id"
        )
    injected = document.get("injected", document)
    if "injected" not in document:
        raise ObservingQualityError("input JSON must contain an 'injected' object")
    if not isinstance(injected, dict):
        raise ObservingQualityError("'injected' must be an object")
    allowed_injected = {"night_conditions_score", "modeled_zenith_sky_brightness"}
    extra_injected = set(injected) - allowed_injected
    if extra_injected:
        raise ObservingQualityError(
            f"unexpected injected keys: {sorted(extra_injected)}"
        )
    if "night_conditions_score" not in injected:
        raise ObservingQualityError("injected.night_conditions_score is required")
    brightness = injected.get("modeled_zenith_sky_brightness")
    return injected["night_conditions_score"], brightness


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)

    if args.engine_version:
        if args.capability or args.input_path or args.pretty:
            _parser().error("--engine-version cannot be combined with other arguments")
        try:
            version = engine_semver()
        except ContractsRootError as exc:
            print(str(exc), file=sys.stderr)
            _error_envelope(None, "engine_failure", str(exc), pretty=False)
            return EXIT_ENGINE
        _write_envelope({"engine_semver": version}, pretty=False)
        return EXIT_OK

    if not args.capability:
        _parser().error("capability-id is required")
    if args.capability != CAPABILITY_ID:
        print(USAGE, end="", file=sys.stderr)
        print(f"unknown capability: {args.capability}", file=sys.stderr)
        return EXIT_USAGE
    if not args.input_path:
        _parser().error("--input is required")

    pretty = bool(args.pretty)
    try:
        raw = _read_input_bytes(args.input_path)
        document = load_json_bytes(raw)
        night, brightness = _extract_injected(document, args.capability)
        result = assess_observing_quality(night, brightness)
        version = engine_semver()
        _write_envelope(
            {
                "capability": CAPABILITY_ID,
                "engine_semver": version,
                "ok": True,
                "result": result,
            },
            pretty=pretty,
        )
        return EXIT_OK
    except PayloadTooLarge:
        _error_envelope(
            CAPABILITY_ID,
            "payload_too_large",
            "input exceeds 1 MiB",
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_VALIDATION
    except (JSONCodecError, ObservingQualityError) as exc:
        _error_envelope(
            CAPABILITY_ID,
            "validation",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_VALIDATION
    except ContractsRootError as exc:
        print(str(exc), file=sys.stderr)
        _error_envelope(
            CAPABILITY_ID,
            "engine_failure",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_ENGINE
    except Exception as exc:  # noqa: BLE001 — map unexpected failures to exit 1
        print(f"engine failure: {exc}", file=sys.stderr)
        _error_envelope(
            CAPABILITY_ID,
            "engine_failure",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_ENGINE


if __name__ == "__main__":
    raise SystemExit(main())
