# Astro Viewing Conditions - Product Roadmap

> Canonical product roadmap. This file is the source of truth for product priority, release sequencing, and future feature direction. Detailed feature specs may live in separate files, but they should point back here for priority.

## Product Direction

Help amateur astronomers decide where, when, and what to observe without requiring a custom backend. Favor useful field guidance, local astronomical calculations, transparent data sources, and graceful behavior when a network service is unavailable.

The strategic path for the next product work is:

1. Make the score more truthful.
2. Make the app usable in the field.
3. Make recommendations personal.
4. Make recommendations location-realistic.
5. Turn the recommendations into an actionable observing plan.

## Current Product

### Conditions and Night Planning

- [x] Three-day hourly weather forecast from Open-Meteo
- [x] Night-quality assessment using cloud cover, moonlight, fog risk, wind, and nighttime windows
- [x] Sunset, sunrise, astronomical darkness, moonrise/moonset, lunar phase, and illumination
- [x] Today, Tomorrow, and Day After anchored to the selected location's local date
- [x] Best observing spot search with ranked nearby recommendations, suitability checks, and a clean recommended-only default map
- [x] Shared condition fetching and local-midnight cache expiration across the app and companion surfaces
- [x] Timeouts and useful fallback behavior for weather, geocoding, location, time-zone, and ISS requests

### Best Targets

- [x] Ranked recommendations for the Moon, Venus, Mars, Jupiter, Saturn, and a curated deep-sky catalog
- [x] Double stars, open and globular clusters, planetary and diffuse nebulae, and galaxies
- [x] Scoring based on altitude, visibility window, darkness, weather, moonlight, and difficulty
- [x] Easy, standard, and challenge observing-intent labels
- [x] Best observing time, compass direction, and approximate maximum altitude
- [x] Dashboard picks plus a complete Best Targets list
- [x] Detail views explaining why a target was recommended, how to find it, useful equipment, and observing technique
- [x] Poor-conditions planning notice and target-specific bright-Moon guidance
- [x] Credited offline thumbnails and full-screen reference imagery for supported targets
- [x] Interpolated visibility-window boundaries and corrected planetary position epoch handling
- [x] Moon recommendations suppressed when the Moon remains below the horizon during the useful observing window

The catalog is intentionally curated rather than a complete Messier/NGC database. Recommendations should remain understandable and field-useful as it grows.

### Locations

- [x] Current-location support
- [x] Search, map, and manual-coordinate entry
- [x] Saved observing locations
- [x] Rename saved locations
- [x] Drag to arrange saved locations
- [x] Preserve location order in the dashboard picker and Apple Watch sync

### ISS

- [x] Optional visible-pass predictions using a user-supplied N2YO API key
- [x] Rise/set range, peak time, compass direction, and elevation
- [x] Start-to-end sky path when supplied by N2YO
- [x] Keep a pass visible while it is in progress
- [x] Distinct no-pass, rejected-key, rate-limit, invalid-response, and timeout messages

### Companion Experiences

- [x] Small and medium iOS Home Screen widgets
- [x] Apple Watch dashboard and location selector
- [x] Inline, circular, corner, and rectangular watchOS complications
- [x] Selected location, saved locations, unit preferences, and cached-condition exchange between iPhone and Apple Watch

### Presentation and Accessibility

- [x] Consistent dashboard card styling
- [x] Improved cloud-symbol contrast in Light Mode
- [x] Clearer Moon illumination labeling
- [x] Adaptive layouts for target details and narrow ISS pass rows
- [x] Observer guide for scores, difficulty labels, observing windows, and ISS paths

## Next Release

The next release should focus on making the app's core guidance more trustworthy and more useful at the telescope. The recommended sequence is:

1. Finish Seeing & Transparency.
2. Add Field Mode.
3. Add Equipment Profile.
4. Add equipment-aware Best Targets scoring.
5. Add simple horizon constraints per saved location.

Items 1 and 2 are the strongest candidates for the immediate release if scope needs to stay small. Items 3 through 5 can follow as the first personalization release.

### 1. Finish Seeing & Transparency

**Goal**: Improve night-quality scoring with astronomy-specific atmospheric factors before building more features on top of the score.

**User value**:

- A cloudless night with poor upper-atmosphere stability should no longer look deceptively excellent.
- High cloud or haze should affect transparency-sensitive observing.
- Telescope users and astrophotographers get a more credible read on whether the night is worth using.

**Scope**:

- Add Open-Meteo hourly fields for pressure, mid-level clouds, high-level clouds, and upper-atmosphere wind.
- Extend `HourlyForecast`, weather parsing, and batch fetching.
- Add seeing and transparency calculators.
- Integrate the new factors into `NightQualityAnalyzer`.
- Expose seeing/transparency in the night-quality UI at least as concise labels.
- Add unit tests for parsing, fallback behavior, calculator thresholds, and scoring integration.

**Reference**: `FEATURES/SEEING_AND_TRANSPARENCY_PLAN.md` contains the detailed implementation plan.

**Done when**:

- Existing night-quality tests still pass.
- Missing new Open-Meteo fields fall back safely.
- The app explains the new factors without implying forecast certainty.
- Best Targets uses the improved night-quality score through the existing scoring path.

### 2. Field Mode

**Goal**: Make the app comfortable to use at the telescope without damaging night vision.

**User value**:

- Observers can check conditions, targets, and timing outside without bright white UI glare.
- The app feels credible as a field companion, not only a planning dashboard.

**Scope**:

- Add a persistent Field Mode setting.
- Use a dim, dark, red-accented presentation for primary app surfaces.
- Avoid bright flashes during navigation, refresh, sheets, and empty/loading states where practical.
- Provide an easy toggle from Settings and a quick entry point from the dashboard.
- Keep accessibility legible; do not rely on red alone for meaning.

**Done when**:

- Dashboard, Settings, Locations, Best Targets, and target detail sheets are usable in Field Mode.
- The app does not force Field Mode into widgets or watchOS unless explicitly designed for those surfaces.
- Basic Light/Dark/Field Mode previews or manual checks are documented.

### 3. Equipment Profile

**Goal**: Let the user describe what they observe with so recommendations can become personal.

**User value**:

- A binocular user and telescope user should not receive the same implied target suitability.
- The app can explain target fit in a way that matches real observing expectations.

**Scope**:

- Add a simple profile in Settings.
- Start with broad capability categories already present in the domain model: naked eye, binoculars, small telescope, larger telescope.
- Consider optional aperture or instrument notes later, but avoid overfitting the first version.
- Store the profile locally and sync only if there is a clear companion-surface need.

**Done when**:

- The profile is persisted.
- Existing users get a sensible default with no onboarding blocker.
- The UI sets expectations that equipment improves ranking, not guaranteed visibility.

### 4. Equipment-Aware Best Targets

**Goal**: Re-rank and explain Best Targets using the user's equipment profile.

**User value**:

- Faint galaxies and low-surface-brightness nebulae should be down-ranked for modest gear.
- Bright planets, the Moon, double stars, open clusters, and large bright targets should remain useful when appropriate.

**Scope**:

- Extend target recommendation context with user equipment.
- Compare user equipment to each target's recommended equipment and difficulty.
- Adjust score and recommendation reasons conservatively.
- Add copy such as "Good fit for binoculars" or "Better with a larger scope" where useful.
- Add tests around ordering and explanation changes.

**Done when**:

- Recommendations change in predictable, testable ways for different equipment profiles.
- The app avoids hard "visible/not visible" claims.
- Existing Best Targets behavior remains stable when the default profile is used.

### 5. Simple Horizon Constraints

**Goal**: Account for trees, buildings, hills, and other site-specific obstructions.

**User value**:

- A target that is technically above the astronomical horizon but blocked from the user's backyard should be down-ranked or explained.
- Saved observing sites become meaningfully different beyond latitude/longitude/elevation.

**Scope**:

- Add per-saved-location minimum useful altitude by direction.
- Start simple: four or eight direction bands rather than a drawing or AR editor.
- Use target azimuth and altitude to determine whether a target clears the configured local horizon.
- Apply a conservative penalty or warning before hiding targets entirely.

**Done when**:

- Saved locations can store and edit simple horizon constraints.
- Best Targets can explain when a target may be blocked by the local horizon profile.
- Existing locations behave as they do today until constraints are configured.

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
- [ ] Consider light-pollution context when a reliable data source and understandable presentation are available
- [ ] Shareable observing plan or conditions summary

## Reliability, Validation, and Release Polish

- [ ] Field-check target windows and compass guidance at low, middle, and high latitudes
- [ ] Test seasonal catalogs in both hemispheres
- [ ] Add regression cases for polar day/night, twilight-only windows, Moon rise/set boundaries, and objects skimming the horizon
- [ ] Review scoring thresholds against real observing sessions and document any recalibration
- [ ] Add UI tests for selecting forecast days, opening target details, renaming/reordering locations, and ISS error states
- [ ] Add widget timeline tests
- [ ] Create a WatchConnectivity integration checklist covering first launch, unreachable phone, stale cache, and selection changes on both devices
- [ ] Run watchOS UI smoke tests and location-permission edge cases
- [ ] Continue the Swift concurrency and main-actor audit
- [ ] Make score and difficulty explanations discoverable inside the app
- [ ] Improve onboarding for location permission, forecast interpretation, and Best Targets
- [ ] Continue VoiceOver, Dynamic Type, contrast, and reduced-motion review
- [ ] Refine empty and stale-data states across iPhone, widgets, and Apple Watch
- [ ] Complete App Store screenshots, description, privacy details, and release notes

## Later / Exploratory

- Aurora forecast integration
- Satellite predictions beyond the ISS
- Dark-sky site discovery
- Light-pollution map or data integration
- Additional widget sizes and richer Lock Screen surfaces
- Exportable observing history

These require data-source, privacy, maintenance, and user-value evaluation before implementation.

## Explicit Non-Goals for Now

- No custom server solely to reproduce calculations that can run locally.
- No dependence on an external visible-planets API; the app already calculates supported planet positions locally.
- No claim that a recommendation score guarantees visibility. Terrain, local light pollution, smoke, equipment, eyesight, and atmospheric steadiness remain important.
- No uncurated object dump that makes the target list harder to use in the field.
- No full horizon drawing or AR obstruction editor until the simple directional model proves valuable.

## Release Readiness Checklist

- [ ] iOS and watchOS builds succeed in Release configuration
- [ ] Core unit and UI test suites pass
- [ ] Target catalog metadata and bundled-image attributions are verified
- [ ] Forecast and recommendation behavior is spot-checked in multiple time zones and hemispheres
- [ ] Widget and watch stale-data behavior is checked on physical devices
- [ ] Observer documentation and App Store copy match the shipped behavior
