#!/usr/bin/env python3
"""Idempotently provision the pinned Astro runtime for the Astronomer skill."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import uuid


SKILL_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = SKILL_ROOT / "runtime-manifest.json"
DEFAULT_TIMEOUT_SECONDS = 300
REQUIRED_OPERATIONS = (
    "agent.conditions",
    "agent.locations",
    "agent.places",
    "agent.equipment",
    "agent.recommendations",
)


class BootstrapError(RuntimeError):
    pass


def default_root() -> Path:
    override = os.environ.get("ASTRO_RUNTIME_ROOT", "").strip()
    if override:
        return Path(override).expanduser()
    xdg = os.environ.get("XDG_DATA_HOME", "").strip()
    data_home = Path(xdg).expanduser() if xdg else Path.home() / ".local" / "share"
    return data_home / "astro-viewing-conditions"


def load_manifest(path: Path) -> dict[str, object]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BootstrapError(f"cannot read runtime manifest: {exc}") from exc
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        raise BootstrapError("unsupported runtime manifest")
    required = {
        "runtime_id", "astro_host_version", "astro_engine_version",
        "python_requires", "dependencies", "artifacts",
    }
    if not required.issubset(document):
        raise BootstrapError("runtime manifest is missing required fields")
    return document


def _supported_python(manifest: dict[str, object]) -> None:
    requirement = manifest["python_requires"]
    if not isinstance(requirement, dict):
        raise BootstrapError("invalid python_requires in runtime manifest")
    minimum = requirement.get("minimum")
    if (
        not isinstance(minimum, list)
        or len(minimum) != 2
        or any(not isinstance(item, int) for item in minimum)
    ):
        raise BootstrapError("invalid minimum Python version in runtime manifest")
    if sys.version_info[:2] < tuple(minimum):
        raise BootstrapError(
            f"Astro runtime requires Python {minimum[0]}.{minimum[1]} or newer"
        )


def _host_path(runtime: Path) -> Path:
    return runtime / ".venv" / "bin" / "astro-host"


def _health(runtime: Path, manifest: dict[str, object]) -> dict[str, object] | None:
    host = _host_path(runtime)
    if not host.is_file() or not os.access(host, os.X_OK):
        return None
    try:
        completed = subprocess.run(
            [str(host), "--runtime-info"],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
            env={**os.environ, "PYTHONNOUSERSITE": "1"},
        )
        payload = json.loads(completed.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None
    if (
        completed.returncode != 0
        or not isinstance(payload, dict)
        or payload.get("ok") is not True
        or payload.get("astro_host_version") != manifest["astro_host_version"]
        or payload.get("astro_engine_version") != manifest["astro_engine_version"]
        or payload.get("operations") != list(REQUIRED_OPERATIONS)
    ):
        return None
    return payload


def _run(command: list[str], *, timeout: int = DEFAULT_TIMEOUT_SECONDS) -> None:
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "PYTHONNOUSERSITE": "1", "PIP_DISABLE_PIP_VERSION_CHECK": "1"},
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise BootstrapError(f"runtime installation command failed: {exc}") from exc
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip().splitlines()
        suffix = detail[-1] if detail else f"exit {completed.returncode}"
        raise BootstrapError(f"runtime installation failed: {suffix}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _obtain_artifacts(
    manifest: dict[str, object], destination: Path, artifact_dir: Path | None
) -> list[Path]:
    raw_artifacts = manifest["artifacts"]
    if not isinstance(raw_artifacts, list) or not raw_artifacts:
        raise BootstrapError("runtime manifest has no artifacts")
    paths: list[Path] = []
    for raw in raw_artifacts:
        if not isinstance(raw, dict):
            raise BootstrapError("invalid artifact entry in runtime manifest")
        filename, url, expected = (
            raw.get("filename"), raw.get("url"), raw.get("sha256")
        )
        if not all(isinstance(value, str) and value for value in (filename, url, expected)):
            raise BootstrapError("invalid artifact fields in runtime manifest")
        if Path(filename).name != filename:
            raise BootstrapError("artifact filename must not contain a path")
        if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
            raise BootstrapError(
                "runtime release is not published: artifact hashes are not finalized"
            )
        target = destination / filename
        if artifact_dir is not None:
            source = artifact_dir / filename
            if not source.is_file():
                raise BootstrapError(f"missing local runtime artifact: {filename}")
            shutil.copy2(source, target)
        else:
            request = urllib.request.Request(
                url, headers={"User-Agent": "Astronomer-Astro-Bootstrap/1"}
            )
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    with target.open("wb") as handle:
                        shutil.copyfileobj(response, handle)
            except (OSError, urllib.error.URLError) as exc:
                raise BootstrapError(f"cannot download {filename}: {exc}") from exc
        actual = _sha256(target)
        if actual != expected:
            raise BootstrapError(f"checksum mismatch for {filename}")
        paths.append(target)
    return paths


def _install(
    staging: Path,
    state: Path,
    manifest: dict[str, object],
    artifact_dir: Path | None,
) -> dict[str, object]:
    venv = staging / ".venv"
    _run([sys.executable, "-m", "venv", str(venv)])
    pip = venv / "bin" / "python"
    dependencies = manifest["dependencies"]
    if not isinstance(dependencies, list) or any(
        not isinstance(item, str) or "==" not in item for item in dependencies
    ):
        raise BootstrapError("runtime dependencies must be exact version pins")
    _run([
        str(pip), "-m", "pip", "install", "--isolated", "--no-input",
        "--only-binary=:all:", "--no-deps", *dependencies,
    ])
    downloads = staging / ".artifacts"
    downloads.mkdir()
    wheels = _obtain_artifacts(manifest, downloads, artifact_dir)
    _run([
        str(pip), "-m", "pip", "install", "--isolated", "--no-input",
        "--no-deps", *(str(path) for path in wheels),
    ])
    shutil.rmtree(downloads)
    health = _health(staging, manifest)
    if health is None:
        raise BootstrapError("installed Astro runtime failed its health check")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    return health


def _switch_current(runtime_root: Path, target: Path) -> None:
    current = runtime_root / "current"
    temporary = runtime_root / f".current.{uuid.uuid4().hex}.tmp"
    relative = os.path.relpath(target, runtime_root)
    os.symlink(relative, temporary)
    os.replace(temporary, current)


def ensure_runtime(
    *,
    root: Path | None = None,
    manifest_path: Path = DEFAULT_MANIFEST,
    artifact_dir: Path | None = None,
    install: bool = True,
) -> dict[str, object]:
    manifest = load_manifest(manifest_path)
    _supported_python(manifest)
    base = (root or default_root()).expanduser().resolve()
    runtime_root = base / "runtime"
    versions = runtime_root / "versions"
    state = base / "state"
    runtime_root.mkdir(parents=True, exist_ok=True)
    versions.mkdir(parents=True, exist_ok=True)
    lock_path = runtime_root / ".bootstrap.lock"
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        current = runtime_root / "current"
        health = _health(current, manifest)
        if health is not None:
            state.mkdir(parents=True, exist_ok=True, mode=0o700)
            return _result(current.resolve(), state, manifest, installed=False, health=health)
        if not install:
            raise BootstrapError("supported Astro runtime is not installed")

        runtime_id = manifest["runtime_id"]
        if not isinstance(runtime_id, str) or not runtime_id or "/" in runtime_id:
            raise BootstrapError("invalid runtime_id in runtime manifest")
        # A venv embeds absolute paths in console-script shebangs and must never
        # be renamed after creation.  Create it at a unique final path, validate
        # it there, then atomically switch only the small `current` symlink.
        target = versions / f"{runtime_id}.{uuid.uuid4().hex}"
        target.mkdir()
        try:
            health = _install(target, state, manifest, artifact_dir)
            _switch_current(runtime_root, target)
        except Exception:
            shutil.rmtree(target, ignore_errors=True)
            raise
        return _result(target, state, manifest, installed=True, health=health)


def _result(
    runtime: Path,
    state: Path,
    manifest: dict[str, object],
    *,
    installed: bool,
    health: dict[str, object],
) -> dict[str, object]:
    return {
        "ok": True,
        "installed": installed,
        "runtime_id": manifest["runtime_id"],
        "astro_host": str(_host_path(runtime)),
        "state_dir": str(state),
        "health": health,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="bootstrap.py")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--ensure", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--artifact-dir", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        result = ensure_runtime(
            root=args.root,
            manifest_path=args.manifest,
            artifact_dir=args.artifact_dir,
            install=not args.check,
        )
        print(json.dumps(result, separators=(",", ":"), sort_keys=True))
        return 0
    except (BootstrapError, OSError) as exc:
        print(json.dumps({
            "ok": False,
            "error": {"code": "bootstrap_failed", "message": str(exc)},
        }, separators=(",", ":"), sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
