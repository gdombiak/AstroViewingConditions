---
name: astronomer
description: Authoritative astronomy observing conditions, target recommendations, observing places, saved locations, and telescope, binocular, or smart-telescope inventory through Astro Host.
when-to-use: Use for questions about how tonight is for astronomy, what to observe, observing sites or coordinates, saved observing locations, and owned or selected observing equipment.
allowed-tools:
  - Shell
user-invocable: true
metadata:
  author: Astro Viewing Conditions
  short-description: Plan an observing session with authoritative Astro facts
---

# Astronomer

Use this skill for astronomy observing conditions, tonight's recommended targets,
place resolution, saved observing locations, and telescope, binocular, or smart-
telescope inventory.

## Runtime

Before the first Astro operation, run the sibling `scripts/astro.py` with its
absolute path, the operation name, and the request JSON on stdin. Locate that
script relative to this `SKILL.md`; do not assume the repository checkout or a
working-directory-relative path. The runner checks or provisions the supported
runtime and invokes `astro-host` by absolute path with isolated persistent state.

Do not tell the user about Python, pip, virtual environments, JSON, downloads, or
shell commands during normal successful operation. If bootstrap fails, say that
the Astronomer runtime could not be prepared, include the concise returned error,
and offer to retry. Never work around bootstrap failure by estimating Astro facts.

Read `references/operations.md` before forming a request. Invoke only these host
operations:

- Conditions questions such as “How is tonight?” use `agent.conditions`.
- “What should I observe tonight?” uses `agent.recommendations`.
- Human place-name resolution uses `agent.places`.
- Saving, selecting, listing, or deleting observing locations uses `agent.locations`.
- Saving, selecting, listing, or deleting equipment uses `agent.equipment`.

Use an aware current UTC `reference_time` for conditions and recommendations.
Do not add `minimum_fit` unless the user explicitly asks for a fit threshold; the
current production default is the host's omitted-value behavior.

## Authority and status

Treat Astro Host and Astro Engine output as authoritative for astronomy facts,
scores, classifications, windows, equipment fit, target membership, and target
order.

- Never calculate, recreate, or embed scoring thresholds or calibration rules.
- Never invent recommended targets, reorder recommendations, or silently omit a
  returned row because it seems unsuitable.
- Explain equipment fit only from returned facts.
- Optional web or educational context must be visibly separate and must not
  override or alter deterministic Astro facts.
- Missing objective facts are a limitation to report, not an invitation to guess.

Preserve these result distinctions in the answer:

- `ok:false` means the operation failed. Do not present it as an astronomy result.
- `ok:true` with `status: unavailable` means the operation succeeded but the
  requested domain answer is unavailable; explain the returned reason.
- A successful degraded or stale-provider result is usable only with its returned
  caveat and provenance stated.
- A successful empty recommendation list means Astro found no qualifying returned
  targets. Do not fill it with model suggestions.

## Location onboarding

When a conditions or recommendations request has no explicit location, first call
`agent.locations` with `get_selected`.

If there is no selected location, ask for a place name or latitude/longitude while
retaining the user's original request. Do not claim access to live GPS.

For a human place name:

1. Call `agent.places` and show the best usable resolved candidate in natural
   language, including enough region information to disambiguate it.
2. Ask whether the user wants to use it once or save it. Do not persist merely
   because a candidate resolved.
3. For save confirmation, pass the exact candidate object returned by
   `agent.places` to `agent.locations` `save_from_candidate`; do not re-geocode or
   reconstruct it. Select it when the user wants it as the default.
4. Resume the original conditions or recommendations request after confirmation.

Explicit coordinates or a candidate chosen for one use belong in the operation's
`location` object and must not mutate saved state. Saving, selecting, renaming, or
deleting a location requires clear user intent.

## Equipment onboarding

Saved equipment is Astro Host state, not conversational memory. Persist equipment
only after the user confirms the complete stored facts: name, instrument type,
aperture and unit, and binocular magnification when applicable. Do not silently
look up or infer technical specifications from the web or from a model name.

Preserve the host's selection behavior: the default is all saved equipment plus
Naked Eye; the user may select one saved item or Naked Eye only. Do not rewrite
that selection on the user's behalf.

For recommendations, omission of `minimum_fit` must remain `any`. A phrase such as
“with my S30” may select or override the named saved equipment for that request,
but must not imply `challengingOrBetter` or any stricter threshold unless the user
explicitly requests one.

## Presentation

Turn structured facts into concise, practical observing guidance. Lead with the
overall conditions or returned target order, then the most decision-useful weather,
Moon, darkness/window, and equipment facts. Keep optional educational context
separate. Mention degraded, stale, unavailable, or empty status plainly.
