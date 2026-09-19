# Astro Viewing Conditions - Product Roadmap

> Canonical product roadmap. This file is the source of truth for product priority, release sequencing, and future feature direction. Detailed feature specs may live in separate files, but they should point back here for priority.

## Product Direction

Help amateur astronomers decide where, when, and what to observe without requiring a custom backend. Favor useful field guidance, local astronomical calculations, transparent data sources, and graceful behavior when a network service is unavailable.

The strategic path for the next product work is:

1. Make scores, difficulty, and personalized guidance easier to understand.
2. Make recommendations location-realistic with simple horizon constraints.
3. Turn trustworthy recommendations into an actionable observing plan.

Additional product principles, known gaps, and unscheduled explorations are collected in [Further Ideas to Consider](#further-ideas-to-consider). They do not change the next-feature priority above.

## Current Product

### Conditions and Night Planning

- [x] Three-day hourly weather forecast from Open-Meteo
- [x] Night-quality assessment using cloud cover, transparency, seeing, moonlight, fog risk, wind, and nighttime windows
- [x] Environmental **Observing Quality** that adjusts Night Conditions with offline modeled light pollution, preserves the exact Night Conditions score when brightness is unavailable, and does not apply Moon effects twice
- [x] Seeing from hourly temperature stability and 200 hPa wind, plus transparency from cloud layers and visibility
- [x] Sunset, sunrise, astronomical darkness, moonrise/moonset, lunar phase, and illumination
- [x] Today, Tomorrow, and Day After anchored to the selected location's local date
- [x] Best observing spot search with coherent Observing Quality ranking when all candidates have valid modeled brightness, whole-search Night Conditions fallback otherwise, suitability checks, and a clean recommended-only default map
- [x] Shared condition fetching and local-midnight cache expiration across the app and companion surfaces
- [x] Timeouts and useful fallback behavior for weather, geocoding, location, time-zone, and ISS requests

### Best Targets

- [x] Ranked recommendations for the Moon, Venus, Mars, Jupiter, Saturn, and a curated deep-sky catalog
- [x] Double stars, open and globular clusters, planetary and diffuse nebulae, and galaxies
- [x] Scoring based on altitude, visibility window, darkness, weather, moonlight, and difficulty
- [x] Easy, Standard, and Challenge observing-intent labels
- [x] Best observing time, compass direction, and approximate maximum altitude
- [x] Dashboard picks plus a complete Best Targets list
- [x] Detail views explaining why a target was recommended, how to find it, useful equipment, and observing technique
- [x] Poor-conditions planning notice and target-specific bright-Moon guidance
- [x] Credited offline thumbnails and full-screen reference imagery for supported targets
- [x] Interpolated visibility-window boundaries and corrected planetary position epoch handling
- [x] Moon recommendations suppressed when the Moon remains below the horizon during the useful observing window

The catalog is intentionally curated rather than a complete Messier/NGC database. Recommendations should remain understandable and field-useful as it grows.

The numeric **Target score** intentionally remains separate from environmental Observing Quality and equipment suitability. Equipment personalization affects suitability guidance and filtering, not Target score or ranking. Target-specific or equipment-aware light-pollution scoring is intentionally out of current product scope; reconsider it only if user feedback demonstrates a recommendation problem and a reliable catalog-wide approach can be developed.

### Equipment Personalization

- [x] Persistent saved profiles for binoculars, visual telescopes, and Smart / EAA telescopes, with Naked Eye available as a built-in capability
- [x] Session equipment selection using all saved equipment, Naked Eye only, or a custom set
- [x] Target-specific matching with Excellent, Good, Challenging, and Poor fit labels
- [x] Optional minimum-suitability filtering without changing numeric target scores or relative ordering
- [x] Personalized equipment guidance in Target Details
- [x] Shared equipment selection and filtering behavior between the Dashboard and View All

Equipment suitability is deliberately separate from the intrinsic Easy, Standard, or Challenge observing intent. The current implementation does not calculate optical field of view; model focal length, eyepieces, filters, cameras, mounts, or imaging trains; persist the session selection as an observing plan; or personalize widget and Watch recommendations. Further equipment expansion should require evidence that it materially improves recommendations without imposing excessive setup burden.

### Locations

- [x] Current-location support
- [x] Search, map, and manual-coordinate entry
- [x] Saved observing locations
- [x] Rename saved locations
- [x] Drag to arrange saved locations
- [x] Preserve location order in the dashboard picker and Apple Watch sync
- [x] Display modeled light-pollution category and zenith sky brightness for saved locations without adding derived brightness to the saved-location or iCloud schema

### ISS

- [x] Optional visible-pass predictions using a user-supplied N2YO API key
- [x] Rise/set range, peak time, compass direction, and elevation
- [x] Start-to-end sky path when supplied by N2YO
- [x] Keep a pass visible while it is in progress
- [x] Distinct no-pass, rejected-key, rate-limit, invalid-response, and timeout messages

### Companion Experiences

- [x] Adaptive small and medium **Tonight at a Glance** conditions widget
- [x] Medium **Tonight’s Targets** and **Three-Night Outlook** Home Screen widgets
- [x] Apple Watch dashboard and location selector
- [x] Inline, circular, corner, and rectangular watchOS complications
- [x] Selected location, saved locations, unit preferences, and cached-condition exchange between iPhone and Apple Watch
- [x] Observing Quality on conditions widgets, the Apple Watch dashboard, and score-bearing complications using validated companion/transferred brightness with exact Night Conditions fallback

### Presentation and Accessibility

- [x] Consistent dashboard card styling
- [x] Improved cloud-symbol contrast in Light Mode
- [x] Clearer Moon illumination labeling
- [x] Adaptive layouts for target details and narrow ISS pass rows
- [x] Dynamic Type layout improvements through the largest standard iOS Text Size setting
- [x] Improved semantic contrast for direction and altitude beside Best Targets observing windows
- [x] Observer guide for scores, difficulty labels, observing windows, and ISS paths
- [x] Persistent dim-red Field Mode for telescope use, available from Settings and the Dashboard while widgets and watchOS retain their normal presentation

## Recent Release: 2.3.1

Improved Apple Watch complication reliability:

- Restored long-term complication freshness with best-effort Watch background refresh scheduling, iPhone refresh requests, and direct Watch acquisition fallback.
- Made WatchConnectivity updates complete, versioned companion snapshots so replaceable application-context writes cannot discard pending conditions data.
- Preserved selected-location ordering and coherent conditions / Observing Quality persistence across background launches, legacy payloads, and iOS process restarts.

## Previous Release: 2.3.0

Made environmental conditions more location-realistic and kept companion displays in sync:

- Added modeled light pollution and the new **Observing Quality** score, which adjusts Night Conditions when valid atlas data is available and otherwise uses Night Conditions unchanged.
- Updated Best Nearby Area to rank with Observing Quality when the full comparison set has valid brightness, with a coherent Night Conditions fallback for the entire search when it does not.
- Added modeled light-pollution information to saved locations.
- Brought validated Observing Quality to the conditions and outlook widgets, Apple Watch dashboard, and score-bearing complications, with freshness, fallback, and synchronization improvements across iPhone, widgets, and Watch.

## Earlier Release: 2.2.0

Improved large-text readability and added Home Screen planning views:

- Added Dynamic Type layout adjustments through the largest standard iOS Text Size setting. Accessibility-size layouts may show a reduced amount of widget detail; broader accessibility validation remains ongoing.
- Added the adaptive small and medium **Tonight at a Glance** conditions widget, medium **Tonight’s Targets** widget, and medium **Three-Night Outlook** widget.
- Improved semantic contrast for the direction and altitude shown beside Best Targets observing windows.
- Refined the **My Equipment** editor with Visual Telescope and millimeter defaults, type-specific examples and aperture guidance, and preserved entered text when the type changes.

## Earlier Release: 2.1.0

Made Best Targets more useful for the equipment an observer has available:

- Added a persistent **My Equipment** inventory for binoculars, visual telescopes, and Smart / EAA telescopes. Naked Eye remains built in rather than stored.
- Added session-level equipment selection and catalog-driven Excellent, Good, Challenging, or Poor fit guidance, including an optional suitability filter. Conditions scores and their relative ordering remain unchanged.
- Completed curated Target Details guidance for every named deep-sky catalog target, with target-specific locating, equipment, and observing notes.
- Updated Venus scoring so a suitably high, sufficiently long, well-separated twilight window can be recommended while weather and the existing safeguards still apply.

## Next Feature Release

The recommended next major Best Targets feature is simple horizon constraints per saved location. Equipment-aware matching and filtering are already implemented; equipment does not alter numeric scoring or ordering.

### Simple Horizon Constraints

**Goal**: Account for trees, buildings, hills, and other site-specific obstructions.

**User value**:

- A target may be astronomically visible but blocked by trees, buildings, roofs, or hills at the observer's actual position.
- Saved observing sites become meaningfully different beyond latitude/longitude/elevation.

**Initial scope**:

- Store profiles only on saved locations, using eight sectors: N, NE, E, SE, S, SW, W, and NW.
- Record one approximate minimum clear altitude per sector through manual editing, with interpolation between adjacent sectors.
- Preserve current behavior for locations without a profile. Current Location remains unconstrained unless the user saves it.
- Prefer clear portions of each target's visibility window and apply the same rules to deep-sky objects, the Moon, and planets.
- Initially retain, clearly warn about, and conservatively down-rank fully blocked targets instead of silently hiding them.
- Regenerate Tonight’s Targets widget data when the selected saved location's profile changes.

**Design constraints**:

- A profile describes the observer's setup position, not necessarily an entire property or observing site.
- Profile edits must update recommendations without requiring a weather refresh.
- Persistence and shared snapshots must remain compatible with existing saved locations.
- Obstruction warnings and explanations must be understandable to non-experts.
- Field validation must precede final decisions about penalties, score caps, or filtering.

**Deferred from the initial release**:

- Phone-assisted compass and altitude capture
- Hard exclusion of blocked targets
- Complex or high-resolution skyline drawing
- Watch horizon editing or presentation

### Best Targets Explainability and Cleanup

As a small polish item, make the distinction among the numeric target suitability score, intrinsic Easy / Standard / Challenge intent, and equipment fit discoverable inside the app.

## Light-Pollution Product Boundary

The offline David Lorenz 2025 atlas and environmental Observing Quality are implemented; this is the completed light-pollution feature. Target score intentionally does not use the light-pollution atlas and remains separate from environmental Observing Quality and equipment suitability. Target-specific or equipment-aware light-pollution scoring is intentionally out of scope because selectively modeled adjustments would make catalog scores less consistently comparable. Reconsider it only if user feedback demonstrates a real recommendation problem and a reliable catalog-wide approach can be developed.

Preserve the atlas's modeled zenith-sky-brightness semantics and do not present values as direct Bortle classifications. Follow the canonical atlas update, permission, packaging, and validation procedure in `tools/light-pollution/VALIDATION_RESULTS.md` rather than reopening the completed feasibility experiment.

## Later Product Backlog

### Imaging Windows

Add a focused astrophotography-oriented view that answers: when tonight is it dark, clear, stable, low-wind, and low-moon enough to image? This should build on seeing/transparency, sun/moon timing, and night-quality scoring rather than become a separate app mode.

### Tonight's Plan

Turn Best Targets into an ordered observing sequence. This becomes most valuable after equipment and horizon constraints are available, because the plan can then say what to observe, what to wait for, and what to skip at a specific site with specific gear.

### Go / No-Go Notification

Add an optional evening verdict notification once the score and recommendations are trustworthy enough. The best version should include why: clear window, moon impact, and a few strong target suggestions.

### Observation Log and Catalog Progress

Add lightweight local observation notes, optional weather-at-time capture, and progress through supported catalogs such as Messier targets. Keep it exportable and local-first.

### Pointing Helper

Explore a compass or device-orientation helper for selected targets using the app's existing altitude/azimuth calculations. Treat this as lower priority because compass reliability and UX need careful validation.

## Lower-Priority Astronomy Ideas

These remain valuable but are lower priority than the next-release foundation above.

### Meteor Shower Calendar

- [ ] Curated annual shower calendar with activity dates, peak, expected zenithal hourly rate, and parent body
- [ ] Location-aware best viewing window
- [ ] Moon altitude and illumination warning at the predicted peak
- [ ] Upcoming-shower dashboard summary

### Celestial Events

- [ ] Eclipses, conjunctions, oppositions, equinoxes, and solstices
- [ ] Location and time-zone-aware visibility notes
- [ ] Calendar/list view and optional reminders
- [ ] Maintain a documented, authoritative source and update process for event data

### Expanded Target Planning

- [ ] Carefully expand the curated deep-sky catalog while retaining verified metadata and imagery rights
- [ ] Add constellation and star-hopping context where it materially helps observers
- [ ] Shareable observing plan or conditions summary

## Reliability, Validation, and Release Polish

- [ ] Field-check target windows and compass guidance at low, middle, and high latitudes
- [ ] Test seasonal catalogs in both hemispheres
- [ ] Add regression cases for polar day/night, twilight-only windows, Moon rise/set boundaries, and objects skimming the horizon
- [ ] Review scoring thresholds against real observing sessions and document any recalibration
- [ ] Add UI tests for selecting forecast days, opening target details, renaming/reordering locations, and ISS error states
- [x] Add widget timeline tests
- [ ] Create a WatchConnectivity integration checklist covering first launch, unreachable phone, stale cache, and selection changes on both devices
- [ ] Run watchOS UI smoke tests and location-permission edge cases
- [ ] Continue the Swift concurrency and main-actor audit
- [ ] Make target score, intrinsic difficulty, and equipment-fit explanations discoverable inside the app
- [ ] Improve onboarding for location permission, forecast interpretation, and Best Targets
- [ ] Continue VoiceOver, Dynamic Type, contrast, and reduced-motion review
- [ ] Refine empty and stale-data states across iPhone, widgets, and Apple Watch
- [ ] Complete App Store screenshots, description, privacy details, and release notes

## Later / Exploratory

- Aurora forecast integration
- Satellite predictions beyond the ISS
- Dark-sky site discovery
- Additional widget sizes and richer Lock Screen surfaces
- Exportable observing history

These require data-source, privacy, maintenance, and user-value evaluation before implementation.

## Further Ideas to Consider

This section records durable direction, known product problems, and unscheduled explorations. It is not a release plan and does not change the next-feature priority: **Simple Horizon Constraints** remains the next engineering foundation. Promote an exploration only when its user value, data/privacy story, and explainability are clear.

### Product Direction / Principles

Astro Conditions is a field decision helper, not a planetarium or a deep numerical weather workbench. It helps amateur observers answer:

1. How good will the sky be?
2. When is the useful window?
3. What is worth looking at from *this* place, on *this* night, with *this* gear?

It serves backyard and multi-site observers, smart / EAA users, and new observers who need realistic expectations. Astrophotography is an adjacent use case; Imaging Windows should remain a focused view built on the same conditions data, not a separate app mode.

Preserve these qualities as the product grows:

- **Separated, explainable truths.** Night Conditions, Observing Quality, Target score, and equipment fit answer different questions and must not become one opaque score. Keep Moon treatment non-duplicative, modeled brightness scientifically honest, and the exact Night Conditions fallback when brightness is unavailable.
- **Local-first field guidance.** Avoid an unnecessary custom backend; retain useful offline behavior, transparent data sources, and honest stale-data states. Widgets are primarily planning surfaces, while Watch and Field Mode are primarily current, in-the-field surfaces.
- **Curated expectations.** Keep a small, useful catalog with finding guidance, equipment fit, credited imagery, and realistic visual expectations—not the appearance of long-exposure astrophotography. Do not pursue catalog completeness for its own sake.
- **Decision over display.** Best Nearby, saved sites, equipment, target timing, and future horizon constraints should help an observer decide whether to go out, where to go, and how to use the session—not merely show more maps or numbers.
- **Explainable recommendations.** Recommendations and any future mixed judgment should show their inputs. Do not replace accountable guidance with an unexplainable chat layer, custom weather model, or social/live-site-report dependency.

### Known Product Gaps

- **Smoke / haze / dirty-air correctness.** A clear-cloud forecast must not conceal materially poor observing conditions from smoke, haze, or dirty air. Night Conditions needs a conservative transparency-integrity input and fallback semantics when a source is unavailable; missing data is not pristine air.
- **Longer planning horizon.** Three detailed hourly days are useful for execution, but observers also need a thin seven-day view to choose which upcoming night is worth planning around and why.
- **Southern catalog coverage.** The curated catalog needs southern showpieces under the same standard for rights, finding guidance, equipment fit, and realistic appearance—not an uncurated expansion.
- **No direct “is it worth the drive?” comparison.** Existing sites and Best Nearby do not yet compare home, saved site, and nearby option by observing improvement, travel effort, and target suitability.
- **A gap between Target score and a possible personal judgment.** Target score should stay pure. If feedback shows a need, a separate, explainable site + gear + target judgment may help without changing Target score semantics.

### Exploratory Ideas

These are unscheduled directions. Several deepen the established backlog rather than define competing feature specifications.

#### Session Timeline / Tonight's Plan

Deepen [Tonight's Plan](#tonights-plan) into a time-ordered observing sequence using target windows, Moon timing, hourly conditions, equipment fit, and eventually horizon constraints: what to observe now, what to wait for, and when to stop. A session-length preference can keep the result practical. Simple Horizon Constraints makes this plan location-realistic; it remains the foundation before this exploration.

#### “Is it worth the drive?” comparison

Compare home, a saved site, and Best Nearby with deltas—not another map: Observing Quality change, travel effort, available session time, and targets whose suitability changes with site and gear. The result should answer whether the improvement justifies the trip. Horizon constraints can later make the comparison more realistic.

#### Seven days for decisions, three days for detail

Add a thin week-ahead decision outlook that identifies promising and poor nights and explains the drivers (for example Moon, clouds, or both), while retaining detailed hourly dashboards only for the current three-day window. This deepens the existing outlook surfaces rather than creating seven full dashboards.

#### Smoke / haze transparency input

Treat smoke, haze, and dirty air as a Night Conditions correctness improvement, using an appropriate public PM2.5, aerosol, or smoke source if it can be evaluated and maintained honestly. Surface “clear of clouds but dirty” conditions alongside current transparency inputs, use conservative behavior when the source is missing, and do not imply research-grade seeing precision.

#### Expected appearance

Deepen Target Details with equipment-aware descriptions or simple schematics of what success looks like: for example, whether a feature is visible, stars resolve, or a nebula remains faint. Keep an explicit distinction between visual observing and long-exposure astrophotography. This supports realistic expectations for new observers without changing the curated-catalog standard.

#### Intent-specific quality verdicts

Validate whether observers benefit from intent-specific guidance built on the same inputs: visual deep sky, planets / Moon / doubles, EAA / smart scope, and later the existing [Imaging Windows](#imaging-windows) direction. A night can differ across those uses, but multiple new headline verdicts should be adopted only if the value outweighs UI complexity; they do not replace the existing distinct scores.

#### Separate target / site / equipment judgment

If usage or feedback shows that Target score alone leaves an important decision unanswered, consider an explainable mixed judgment with terminology less probabilistic than “odds.” It could show why a target is challenging at a particular site with particular gear and Moon conditions. It must remain separate from the pure Target score, avoid claims of calibrated probability, and preserve its factors for inspection.

#### Smart / EAA and equipment × weather guidance

Explore practical advice for a chosen instrument—such as framing, Moon tolerance, wind, dew, fog, or seeing—without becoming hardware-control software or implying precise performance prediction. An EAA-oriented queue would deepen Best Targets; practical gear advice should remain advisory and should not add equipment fields unless real use demonstrates a need.

#### Goal-first, seasonal, and personal planning

Explore a goal-first inversion of the UI (goal to next useful window), a site- and goal-aware seasonal “next excellent night,” and on-device calibration from lightweight observation feedback. These deepen [Observation Log and Catalog Progress](#observation-log-and-catalog-progress), [Celestial Events](#celestial-events), and [Meteor Shower Calendar](#meteor-shower-calendar), rather than duplicating them. Long-term goals such as showing Saturn “this month” require planning semantics beyond the forecast horizon. Sparse feedback must not be used to infer specific environmental causes or alter global Target score semantics; keep any personalization local-first and exportable.

#### Southern showpieces and field guidance

Deepen [Expanded Target Planning](#expanded-target-planning) with a carefully selected southern set (for example Omega Centauri, 47 Tucanae, Carina/Crux showpieces, and the Magellanic Clouds), subject to the existing catalog-quality bar. A simple session sky strip or compass-oriented guidance can deepen [Pointing Helper](#pointing-helper) without becoming a full atlas or relying on unreliable AR.

#### Watch and field-use follow-ups

Keep Watch focused on present context: observing-window status, current target direction, time remaining, and simple go / wait / pack-up guidance. Treat complication refinement, haptics, Live Activity, Dynamic Island, and fuller session orchestration as separate possible follow-ups with different scope and value; none is automatically bundled with the others.

### Suggested Exploratory Consideration Order

Not a committed release sequence. After Simple Horizon Constraints, evaluate these product problems in roughly this order:

1. **Smoke / haze transparency input** — correct a trust-breaking Night Conditions gap.
2. **Session Timeline / Tonight's Plan** — turn trustworthy recommendations into a usable, time-ordered session.
3. **“Is it worth the drive?” comparison** — make site choice comparative, practical, and target-aware.
4. **Seven-day decision outlook** — support planning without expanding every day into hourly detail.
5. **Expected appearance** — strengthen realistic, equipment-aware expectation-setting.
6. **Intent-specific quality** — validate the need and UI cost of intent-specific verdicts.
7. **Separate target / site / equipment judgment** — only if use or feedback establishes the need.
8. **Remaining explorations** — southern catalog growth, smart / EAA guidance, goal-first and seasonal planning, personalization, pointing guidance, and Watch follow-ups.

Simple Horizon Constraints remains the next engineering foundation because it improves later target timing, Session Timeline, worth-the-drive comparisons, and pointing guidance. The product value is the resulting field decision, not the octant editor itself.

## Explicit Non-Goals for Now

- No custom server solely to reproduce calculations that can run locally.
- No dependence on an external visible-planets API; the app already calculates supported planet positions locally.
- No claim that a recommendation score guarantees visibility. Terrain, local light pollution, smoke, equipment, eyesight, and atmospheric steadiness remain important.
- No uncurated object dump that makes the target list harder to use in the field.
- No phone-assisted or high-resolution horizon editor until the simple directional model proves valuable.
- No additional equipment inputs or equipment-driven numeric ranking without evidence that they materially improve recommendations.

## Release Readiness Checklist

- [ ] iOS and watchOS builds succeed in Release configuration
- [ ] Core unit and UI test suites pass
- [ ] Target catalog metadata and bundled-image attributions are verified
- [ ] Forecast and recommendation behavior is spot-checked in multiple time zones and hemispheres
- [ ] Widget and watch stale-data behavior is checked on physical devices
- [ ] Observer documentation and App Store copy match the shipped behavior
