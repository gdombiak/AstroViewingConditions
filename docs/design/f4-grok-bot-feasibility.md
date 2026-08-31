# F4 Grok Bot feasibility notes

Gate F **PASS** (2026-08-31). This is an operational record, not an iOS/Python behavior change.

## Environment

- Shared Grok Bot computer (account-wide, not a per-Bot VM)
- `Linux cursor 6.12.94+ x86_64`, user `box`, durable workspace `/workspace`
- `python3` 3.13.5 at `/usr/bin/python3` (`python` is not on PATH)
- `git`, `pip3`, `curl`, `apt-get`, `sudo` present; no Docker/Swift
- Shell/CLI ran on the shared Grok Bot cloud computer, not this Mac.
- Product docs and the Bot say work continues if the laptop is closed; F4 did not observe a scheduled fire in that state.

## Install

`feature/astro-engine-cli` was not on GitHub, so F2 was transferred as a tarball (Python package + contracts + launcher), not cloned from `main`.

- Tree: `/workspace/AstroViewingConditions`
- Launcher: `/workspace/AstroViewingConditions/apps/cli/astro-engine`
- Symlink: `/workspace/bin/astro-engine`
- No venv/pip: the launcher has no third-party deps
- `CONTRACTS_ROOT` resolved by ancestor walk from the checkout

Treat the venv-free `/workspace` tree as replaceable if the computer image is rebuilt.

## CLI checks on the Bot computer

- `astro-engine --engine-version` → `{"engine_semver":"0.1.0"}`, exit 0
- `anchor-17-5-v1` → `ok:true`, score 72, penalties 8.0
- `home-backyard-v1` → `ok:true`, score 66, night 72, base ≈ 6.820636749267599, applied ≈ 5.911218516031919

Goldens were not rewritten. Runtime envelopes include `engine_semver`; `expected.json` does not.

## Skill

- Name: `Astro observing quality` (id `astro-observing-quality`)
- Capability: `observing_quality.assess` only
- Bot: dedicated `Astronomer` (all Bots still share the computer)
- Skills are a **shared account library**, not per-Bot private / no per-Bot enable flag
- Authoritative-source rule: invoke the local CLI; do not silently recompute scores

## Autonomous invocation

Natural prompts that did **not** name `astro-engine`, CLI, shell, Python, or the skill still invoked `/workspace/bin/astro-engine` and used `ok:true` results:

| Prompt inputs | Engine score |
|---|---|
| night 72, brightness 18.5896816253662 | 66 |
| night 80, brightness 17.5 | 72 |
| night 35, brightness 18.5896816253662 | 35 (applied penalty 0.0) |
| night 90, brightness null | 90 (`light_pollution: null`) |

`site_quality` was not added and is not required for this slice.

## Routine

- Name: `F4 observing-quality smoke` on Astronomer
- Fixed inputs: night 72, brightness 18.5896816253662
- Schedule: weekdays 9:00 AM PT, **paused** (no recurring fire)
- Test run invoked the same CLI and returned score 66 / `ok:true`

A clock-fired run with the laptop closed was not waited out; Test run executed on the Bot computer, not the Mac.

## Limitations

- F2/F3 branch is not on `origin`; Bot checkout cannot `git clone` the engine from public `main`
- Manually installed `/workspace` state may not survive computer reset
- Skill evidence rule (dump command + raw stdout) is F4-only and can be relaxed later
- Unattended proof is routine Test run + paused schedule, not a live 9:00 AM fire
