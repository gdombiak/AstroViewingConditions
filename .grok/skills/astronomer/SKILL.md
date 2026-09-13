---
name: astronomer
description: Authoritative astronomy observing conditions, target recommendations, observing places, saved locations, and telescope, binocular, or smart-telescope inventory through Astro Host.
when-to-use: Use for questions about how tonight is for astronomy, how the next three nights look, what to observe, observing sites or coordinates, saved observing locations, and owned or selected observing equipment.
allowed-tools:
  - Shell
user-invocable: true
metadata:
  author: Astro Viewing Conditions
  short-description: Plan an observing session with authoritative Astro facts
---

# Astronomer

Use this skill for astronomy observing conditions, the next three nights, tonight's
recommended targets, place resolution, saved observing locations, and telescope,
binocular, or smart-telescope inventory.

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
- “How do the next three nights look?” uses `agent.outlook`. Do not call
  `agent.conditions` three times or invent the three observing dates.
- “Where are good stargazing places near me?” uses web-discovered named places
  followed by `agent.batch_compare`.
- “What should I observe tonight?” uses `agent.recommendations`.
- Human place-name resolution uses `agent.places`.
- Saving, selecting, listing, or deleting observing locations uses `agent.locations`.
- Saving, selecting, listing, or deleting equipment uses `agent.equipment`.

Use an aware current UTC `reference_time` for conditions, outlook, and recommendations.
Use the same aware `reference_time` for `agent.batch_compare`.
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

## Stargazing places near a center

First resolve the selected or user-supplied center through the normal location
onboarding path. For an explicit center, pass its coordinates as `center` for this
one call; do not change the selected saved location.

Use the web/browser/search capabilities actually available in the deployed Grok
environment to find credible **named real-world stargazing destinations**. Prefer
source-backed established stargazing areas, dark-sky sites, parks or recreation
areas with relevant night use, observatories or public observing areas, and
viewpoints known for night-sky use. Resolve reliable coordinates and deduplicate
places. Current Bot discovery policy is **at most 8 destinations**; the Host's
generic transport cap is separate. Never hard-code a city's places. If web
discovery fails, ask for or use user-supplied named candidates; do not substitute
arbitrary grid coordinates.

Assign each place a stable `key`. Pass its name, coordinates, optional source URL,
and optional ordinary Maps/place URL to `agent.batch_compare`. Keep any source
or access details keyed by `key`; they are context, never Astro score inputs.
Present `ranked_destinations` in the returned Engine order. Search popularity,
reviews, and web prose must not rerank Astro results. If all evaluated places
rate poorly, say that none looks worthwhile for the requested night. Describe
the scope as “places I evaluated” or “best conditions among these destinations,”
not an exhaustive search of nearby geography.
If `omitted_candidates` is non-empty, say some discovered destinations could
not be evaluated and name them briefly when useful. If `scoring_mode` is
`night_conditions_fallback`, explain that light pollution was not consistently
available across the set, so ranking used Night Conditions for all places.

Lead with the named destination, approximate **straight-line** distance, Astro
public score and center delta when available, one concise returned condition
reason, and a clickable source or Maps link. Do not lead with raw coordinates or
invent driving distance. Keep access facts (hours, parking, fees, reservations,
roads) separate from Astro conditions. Official evidence of closure for the
requested period must be stated before suggesting travel; good Astro conditions
do not mean access is permitted. Unknown access remains explicitly unknown.
Never imply guaranteed legal access, parking, or safety. A named place is not
necessarily an official observing site. Ordinary clickable Maps URLs are the
baseline; do not claim native map cards, multi-pin maps, or built-in Places
integration until those features are validated in the deployed Bot.

## Location onboarding

When a conditions, outlook, or recommendations request has no explicit location, first call
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
4. Resume the original conditions, outlook, or recommendations request after confirmation.

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
overall conditions, three-night outlook, or returned target order, then the most
decision-useful weather, Moon, darkness/window, and equipment facts. Keep optional
educational context separate. Mention degraded, stale, unavailable, or empty status
plainly. For outlook, preserve each night's structural `available`,
`no_astronomical_night`, or `unavailable` status from Astro Engine. A returned
score may be absent on an `available` night; do not invent one or change the
status. Identify the best night only from `best_index`.

For `agent.conditions`, use `night_conditions.cloud_advisory` as the sole authority
for cloud-timing advice. `early_heavy` means heavy clouds early, with a potentially
better observing opportunity later; `late_heavy` means observing earlier may be
better before heavier clouds arrive; `intermittent_heavy` means a heavy-cloud
period may interrupt otherwise usable conditions, without choosing earlier or
later. If `cloud_advisory` is null or night conditions are unavailable, do not
infer a timing recommendation. Do not infer eligibility from `cloud_timing` alone,
reclassify hourly cloud rows, invent the heavy-cloud interval's clock times, or
read `none` as clear skies. Overall `trend` is not a cloud-timing classification.
`best_window` may be reported as its own authoritative fact, never as the
heavy-cloud interval. Preserve degraded and stale-provider caveats.
Do not turn a `cloud_timing` field in recommendations or outlook into timing
advice; those operations do not return the eligibility fact.
