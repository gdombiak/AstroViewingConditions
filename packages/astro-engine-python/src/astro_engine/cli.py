"""JSON CLI for the public 1.0 capability allow-list.

Stdout is JSON:
- successful capability invocation → ok:true envelope, exit 0
- successful --engine-version → {"engine_semver":"<version>"} (no ok), exit 0
- validation/input → ok:false, error.code, exit 2
- engine/runtime (including --engine-version bootstrap failure) →
  ok:false, error.code=engine_failure, exit 1; omit engine_semver if unknown
Usage / unknown capability → no stdout JSON, exit 3.
Stderr is diagnostics only.

The CLI owns argv, byte/file limits, JSON decoding, the public envelope,
the allow-list, exit-code mapping, stdout/stderr discipline, and
engine_semver insertion. Capability semantics live in
`astro_engine._capability.evaluate_capability`.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any, Mapping, TextIO

from astro_engine._capability import CapabilityHost, evaluate_capability
from astro_engine.catalog import CAPABILITY_ID as CATALOG_ID
from astro_engine.contracts import ContractsRootError, engine_semver
from astro_engine.errors import ValidationError
from astro_engine.fog import CAPABILITY_ID as FOG_ID
from astro_engine.grid import CAPABILITY_ID as GRID_ID
from astro_engine.observing_window import CAPABILITY_ID as WINDOW_ID
from astro_engine.targets import CAPABILITY_ID as TARGETS_ID
from astro_engine.equipment import CAPABILITY_ID as EQUIPMENT_ID
from astro_engine.filter_recommendations_by_equipment import (
    CAPABILITY_ID as FILTER_RECOMMENDATIONS_BY_EQUIPMENT_ID,
)
from astro_engine.location_compare import CAPABILITY_ID as COMPARE_ID
from astro_engine.observing_night import CAPABILITY_ID as OBSERVING_NIGHT_ID
from astro_engine.night_forecast import CAPABILITY_ID as NIGHT_FORECAST_ID
from astro_engine.cloud_timing import CAPABILITY_ID as CLOUD_TIMING_ID
from astro_engine.night_outlook import (
    BEST_NIGHT_CAPABILITY_ID,
    CAPABILITY_ID as NIGHT_OUTLOOK_ID,
)
from astro_engine.iss import CAPABILITY_ID as ISS_ID
from astro_engine.jsonio import JSONCodecError, STDIN_LIMIT_BYTES, dump_json, load_json_bytes
from astro_engine.light_pollution import CAPABILITY_ID as LP_ID
from astro_engine.night_conditions import ANALYZE_CAPABILITY_ID, SCORE_CAPABILITY_ID
from astro_engine.observing_quality import CAPABILITY_ID as OQ_ID, ObservingQualityError
from astro_engine.seeing import CAPABILITY_ID as SEEING_ID
from astro_engine.transparency import CAPABILITY_ID as TRANSPARENCY_ID
from astro_engine.weather import CAPABILITY_ID as WEATHER_ID

EXIT_OK = 0
EXIT_ENGINE = 1
EXIT_VALIDATION = 2
EXIT_USAGE = 3

# Explicit public 1.0 allow-list. Catalog order from capabilities.yaml.
# Not every private `_capability` ID is automatically public.
PUBLIC_CAPABILITY_IDS: tuple[str, ...] = (
    OQ_ID,
    ANALYZE_CAPABILITY_ID,
    SCORE_CAPABILITY_ID,
    FOG_ID,
    SEEING_ID,
    TRANSPARENCY_ID,
    LP_ID,
    WEATHER_ID,
    ISS_ID,
    GRID_ID,
    COMPARE_ID,
    CATALOG_ID,
    TARGETS_ID,
    EQUIPMENT_ID,
    WINDOW_ID,
    "targets.requirements",
    "catalog.solar_system",
    "targets.moon_sensitivity",
    "astronomy.horizontal_position",
    "targets.deep_sky_windows",
    "astronomy.sun_events",
    "astronomy.moon_info",
    "astronomy.moon_series",
    "astronomy.moon_observation",
    "targets.moon_recommendation",
    "astronomy.planet_observation",
    "targets.planet_recommendation",
    "targets.compose_recommendations",
    FILTER_RECOMMENDATIONS_BY_EQUIPMENT_ID,
    OBSERVING_NIGHT_ID,
    NIGHT_FORECAST_ID,
    CLOUD_TIMING_ID,
    NIGHT_OUTLOOK_ID,
    BEST_NIGHT_CAPABILITY_ID,
)

_PUBLIC_ALLOW_LIST = frozenset(PUBLIC_CAPABILITY_IDS)
_BASE_TOP_LEVEL = frozenset({"capability", "injected"})
# night_conditions.analyze fixtures carry clock/time_zone/location at top
# level. `location` is accepted for envelope compatibility; the library
# does not currently consume it.
_EXTRA_TOP_LEVEL = {
    ANALYZE_CAPABILITY_ID: frozenset({"clock", "time_zone", "location"}),
}

PRODUCTION_ATLAS_FILENAME = "light_pollution_global_v1.bin"
_ATLAS_ENV = "ASTRO_ENGINE_ATLAS_PATH"
_PACKAGE_ATLAS = Path(__file__).resolve().parent / "data" / PRODUCTION_ATLAS_FILENAME
_REPO_ATLAS_CANDIDATES = (
    Path("Sources/AstroViewingConditions/Resources/LightPollution")
    / PRODUCTION_ATLAS_FILENAME,
    Path("apps/ios/Sources/AstroViewingConditions/Resources/LightPollution")
    / PRODUCTION_ATLAS_FILENAME,
)
MAX_ATLAS_WALK = 16


class ProductionAtlasMissing(Exception):
    """Default production atlas is not installed. Maps to engine_failure."""


def default_atlas_path(*, start: Path | None = None) -> Path | None:
    """Resolve the production/default LPATLAS1 file. Does not load it.

    Order: `ASTRO_ENGINE_ATLAS_PATH` if it names an existing file; then
    package `astro_engine/data/light_pollution_global_v1.bin` (install
    image, gitignored, not committed); then the existing iOS app resource
    in a repo checkout. Never searches `contracts/fixtures`.
    """
    env = os.environ.get(_ATLAS_ENV)
    if env:
        path = Path(env)
        if path.is_file():
            return path
    if _PACKAGE_ATLAS.is_file():
        return _PACKAGE_ATLAS.resolve()
    return _repo_checkout_atlas(start=start)


def _repo_checkout_atlas(*, start: Path | None = None) -> Path | None:
    here = (start or Path(__file__)).resolve()
    if here.is_file():
        here = here.parent
    for _ in range(MAX_ATLAS_WALK):
        for relative in _REPO_ATLAS_CANDIDATES:
            candidate = here / relative
            if candidate.is_file():
                return candidate.resolve()
        parent = here.parent
        if parent == here:
            break
        here = parent
    return None


def _usage_text() -> str:
    lines = [
        "usage: astro-engine --engine-version",
        "       astro-engine <capability-id> --input -|FILE [--pretty]",
        "       astro-engine light_pollution.lookup --input -|FILE [--pretty] [--atlas-path FILE]",
        "",
        "1.0 allow-list:",
    ]
    lines.extend(f"  {capability}" for capability in PUBLIC_CAPABILITY_IDS)
    return "\n".join(lines) + "\n"


USAGE = _usage_text()


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
    parser.add_argument("--atlas-path", dest="atlas_path")
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
        raise ValidationError(f"cannot read input file: {exc}") from exc
    if size > STDIN_LIMIT_BYTES:
        raise PayloadTooLarge()
    data = path.read_bytes()
    if len(data) > STDIN_LIMIT_BYTES:
        raise PayloadTooLarge()
    return data


class PayloadTooLarge(Exception):
    pass


def _validate_public_envelope(document: Any, argv_capability: str) -> dict[str, Any]:
    if not isinstance(document, dict):
        raise ValidationError("input JSON must be an object")
    allowed = _BASE_TOP_LEVEL | _EXTRA_TOP_LEVEL.get(argv_capability, frozenset())
    extra = set(document) - allowed
    if extra:
        raise ValidationError(f"unexpected top-level keys: {sorted(extra)}")
    if "capability" in document and document["capability"] != argv_capability:
        raise ValidationError(
            "input capability does not match the invoked capability-id"
        )
    if "injected" not in document:
        raise ValidationError("input JSON must contain an 'injected' object")
    injected = document.get("injected")
    if not isinstance(injected, dict):
        raise ValidationError("'injected' must be an object")
    return document


def _capability_host(
    capability: str,
    args: argparse.Namespace,
    document: Mapping[str, Any],
) -> CapabilityHost | None:
    if capability in ("astronomy.sun_events", "astronomy.moon_info", "astronomy.moon_series"):
        path = os.environ.get("ASTRO_ENGINE_EPHEMERIS_PATH")
        return CapabilityHost(ephemeris_path=Path(path)) if path else None
    if capability != LP_ID:
        return None
    if args.atlas_path:
        return CapabilityHost(atlas_path=Path(args.atlas_path))
    injected = document.get("injected")
    if isinstance(injected, Mapping) and "artifact" in injected:
        return None
    path = default_atlas_path()
    if path is None:
        raise ProductionAtlasMissing("production light-pollution atlas is not installed")
    return CapabilityHost(atlas_path=path)


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)

    if args.engine_version:
        if args.capability or args.input_path or args.pretty or args.atlas_path:
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
    if args.capability not in _PUBLIC_ALLOW_LIST:
        print(USAGE, end="", file=sys.stderr)
        print(f"unknown capability: {args.capability}", file=sys.stderr)
        return EXIT_USAGE
    if args.atlas_path and args.capability != LP_ID:
        print(USAGE, end="", file=sys.stderr)
        print(
            "--atlas-path is only valid with light_pollution.lookup",
            file=sys.stderr,
        )
        return EXIT_USAGE
    if not args.input_path:
        _parser().error("--input is required")

    pretty = bool(args.pretty)
    capability = args.capability
    try:
        raw = _read_input_bytes(args.input_path)
        document = _validate_public_envelope(load_json_bytes(raw), capability)
        host = _capability_host(capability, args, document)
        result = evaluate_capability(capability, document, host=host)
        version = engine_semver()
        _write_envelope(
            {
                "capability": capability,
                "engine_semver": version,
                "ok": True,
                "result": result,
            },
            pretty=pretty,
        )
        return EXIT_OK
    except PayloadTooLarge:
        _error_envelope(
            capability,
            "payload_too_large",
            "input exceeds 1 MiB",
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_VALIDATION
    except JSONCodecError as exc:
        _error_envelope(
            capability,
            "validation",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_VALIDATION
    except (ValidationError, ObservingQualityError) as exc:
        _error_envelope(
            capability,
            getattr(exc, "code", "validation") or "validation",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_VALIDATION
    except (ContractsRootError, ProductionAtlasMissing) as exc:
        print(str(exc), file=sys.stderr)
        _error_envelope(
            capability,
            "engine_failure",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_ENGINE
    except Exception as exc:  # noqa: BLE001 — map unexpected failures to exit 1
        print(f"engine failure: {exc}", file=sys.stderr)
        _error_envelope(
            capability,
            "engine_failure",
            str(exc),
            pretty=pretty,
            version=_try_engine_semver(),
        )
        return EXIT_ENGINE


if __name__ == "__main__":
    raise SystemExit(main())
