#!/usr/bin/env python3
"""Skill-facing JSON runner that bootstraps then invokes astro-host."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

from bootstrap import BootstrapError, ensure_runtime


OPERATIONS = (
    "agent.conditions",
    "agent.places",
    "agent.locations",
    "agent.equipment",
    "agent.recommendations",
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="astro.py")
    parser.add_argument("operation", choices=OPERATIONS)
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args(argv)
    try:
        runtime = ensure_runtime()
        command = [runtime["astro_host"], args.operation, "--input", "-"]
        if args.pretty:
            command.append("--pretty")
        environment = {
            **os.environ,
            "ASTRO_HOST_STATE_DIR": runtime["state_dir"],
            "PYTHONNOUSERSITE": "1",
        }
        completed = subprocess.run(
            command,
            input=sys.stdin.buffer.read(),
            stdout=sys.stdout.buffer,
            stderr=sys.stderr.buffer,
            env=environment,
            check=False,
        )
        return completed.returncode
    except (BootstrapError, OSError) as exc:
        print(json.dumps({
            "ok": False,
            "error": {"code": "bootstrap_failed", "message": str(exc)},
        }, separators=(",", ":"), sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
