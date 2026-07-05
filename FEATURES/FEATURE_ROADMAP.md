# Astro Viewing Conditions - Feature Roadmap

> Product roadmap reflecting the implementation after release 1.2.1. Completed items describe the current product; future items are directional and do not promise a release date.

## Product Direction

Help amateur astronomers decide where, when, and what to observe without requiring a custom backend. Favor useful field guidance, local astronomical calculations, transparent data sources, and graceful behavior when a network service is unavailable.

## Completed

### Conditions and Night Planning

- [x] Three-day hourly weather forecast from Open-Meteo
- [x] Night-quality assessment using cloud cover, moonlight, fog risk, wind, and nighttime windows
- [x] Sunset, sunrise, astronomical darkness, moonrise/moonset, lunar phase, and illumination
- [x] Today, Tomorrow, and Day After anchored to the selected location's local date
- [x] Best observing spot search
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

## Next Release: Validation and Polish

### Recommendation Quality

- [ ] Field-check target windows and compass guidance at low, middle, and high latitudes
- [ ] Test seasonal catalogs in both hemispheres
- [ ] Add regression cases for polar day/night, twilight-only windows, Moon rise/set boundaries, and objects skimming the horizon
- [ ] Review scoring thresholds against real observing sessions and document any recalibration

### Reliability and Testing

- [ ] Add UI tests for selecting forecast days, opening target details, renaming/reordering locations, and ISS error states
- [ ] Add widget timeline tests
- [ ] Create a WatchConnectivity integration checklist covering first launch, unreachable phone, stale cache, and selection changes on both devices
- [ ] Run watchOS UI smoke tests and location-permission edge cases
- [ ] Continue the Swift concurrency and main-actor audit

### User Experience

- [ ] Make score and difficulty explanations discoverable inside the app
- [ ] Improve onboarding for location permission, forecast interpretation, and Best Targets
- [ ] Continue VoiceOver, Dynamic Type, contrast, and reduced-motion review
- [ ] Refine empty and stale-data states across iPhone, widgets, and Apple Watch
- [ ] Complete App Store screenshots, description, privacy details, and release notes

## Future Astronomy Features

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
- [ ] Explore telescope/aperture preferences without implying guaranteed visibility
- [ ] Add observation notes or a lightweight observing log
- [ ] Consider light-pollution context when a reliable data source and understandable presentation are available

### Notifications and Sharing

- [ ] Optional alerts for unusually favorable observing windows
- [ ] Optional ISS pass reminders
- [ ] Shareable observing plan or conditions summary

## Later / Exploratory

- Aurora forecast integration
- Satellite predictions beyond the ISS
- Dark-sky site discovery
- Additional widget sizes and richer Lock Screen surfaces
- Exportable observing history

These require data-source, privacy, maintenance, and user-value evaluation before implementation.

## Explicit Non-Goals for Now

- No custom server solely to reproduce calculations that can run locally.
- No dependence on an external visible-planets API; the app already calculates supported planet positions locally.
- No claim that a recommendation score guarantees visibility. Terrain, local light pollution, smoke, equipment, eyesight, and atmospheric steadiness remain important.
- No uncurated object dump that makes the target list harder to use in the field.

## Release Readiness Checklist

- [ ] iOS and watchOS builds succeed in Release configuration
- [ ] Core unit and UI test suites pass
- [ ] Target catalog metadata and bundled-image attributions are verified
- [ ] Forecast and recommendation behavior is spot-checked in multiple time zones and hemispheres
- [ ] Widget and watch stale-data behavior is checked on physical devices
- [ ] Observer documentation and App Store copy match the shipped behavior
