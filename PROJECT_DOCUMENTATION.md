# Astro Viewing Conditions - Project Documentation

> **Purpose**: This document captures the project context, architecture, and implementation notes so work can be resumed even if the conversation history is lost.

---

## 1. Project Overview

### Goal
Build an open-source iOS and watchOS app for astronomy enthusiasts to assess nighttime viewing conditions, choose worthwhile targets, and plan stargazing sessions. The app combines weather, astronomical information, night-quality analysis, target recommendations, ISS pass predictions, widgets, and Apple Watch glanceable views.

### Target Users
- Amateur astronomers
- Astrophotographers
- Casual stargazers
- Anyone interested in night sky observation

### Platform
- **iOS 18+**
- **watchOS 11+**
- Written in **Swift 6.0**
- Uses **SwiftUI** for UI
- Uses **SwiftData** and shared storage helpers for persistence and app/extension data sharing
- Uses **WidgetKit** for iOS widgets and watchOS complications
- Uses **WatchConnectivity** for iPhone and Apple Watch sync

### License
**AGPL-3.0** - Ensures the app remains open source and prevents commercial exploitation while keeping it free for the astronomy community.

---

## 2. Core Features

### Implemented
- **Weather Data**: Low/mid/high cloud information, humidity, surface wind, 200 hPa wind used by seeing estimation, temperature, visibility, dew point, and hourly forecasts via Open-Meteo
- **Astronomical Data**: Sun/moon rise-set times, astronomical night timing, and moon phase via SunCalc
- **Night Quality Analysis**: Observing assessment based on transparency, seeing, cloud cover, moonlight, fog, wind, and nighttime windows
  - `SeeingCalculator` uses temperature stability and 200 hPa wind; `TransparencyCalculator` uses weighted low/mid/high clouds and visibility.
  - Missing new inputs fall back safely to the previous scoring behavior.
  - Summary generation remains centralized in SharedCode for iPhone, widgets, and Watch.
- **Best Nearby Area**: Ranked nearby observing-area recommendations based on sampled weather forecasts and candidate suitability checks
  - Weather-scores the full generated grid and preserves `allScoredLocations` for diagnostics and future weather-field views
  - Excludes known water/unsuitable and unchecked candidates. Candidates whose suitability cannot be conclusively verified may be recommended with clear verification warnings; observers must confirm access before traveling.
  - The default map renders only the ranked recommended areas so map pins match the Top Areas list
  - Suitability verification expands through ranked candidate bands but caps checks at 40, below the observed iOS/CoreLocation reverse-geocoding throttling threshold
  - If at least one suitable candidate is found before the cap, the app returns the available recommendations even when fewer than the requested count are available
- **Best Targets**: Ranked Moon, planet, double-star, cluster, nebula, and galaxy recommendations for the selected location and forecast night
  - Scores combine visibility, altitude, astronomical darkness (or qualified twilight visibility for Venus), weather, moonlight, and observing difficulty
  - Shows the observing window, direction, maximum altitude, and a concise recommendation rationale
  - Full target details provide curated finding tips, equipment guidance, observing notes, and difficulty guidance for every named deep-sky catalog target
  - Users can save binoculars, visual telescopes, and Smart / EAA telescopes, choose session-available equipment, and filter by explainable equipment suitability without changing conditions scores or ranking
  - Curated target images are bundled locally with attribution and license metadata
- **ISS Pass Predictions**: Visible ISS passes via N2YO with rise/set range, peak time and elevation, compass path, active-pass handling, and service error messages when a user-provided API key is configured
- **Fog Score**: Risk calculated from humidity, temperature-dew point difference, visibility, and low cloud cover
- **Location Management**:
  - Auto-detect current location
  - Save favorite observing locations
  - Rename and reorder saved locations
  - Search by city name
  - Manual coordinate entry
  - Map-based location picker
- **Unit Preferences**: Toggle between Metric and Imperial
- **Field Mode**: Persistent, iOS-only dim red appearance with controls in Settings and the Dashboard toolbar. Light, Dark, and Field Mode share the same persistent native `TabView`; Field Mode changes the semantic palette and UIKit appearance configuration without replacing root views, preserving the selected tab and mounted screen instances.
- **3-Day Forecast**: Today, tomorrow, and day after
- **Location-Local Dates**: Forecast tabs and displayed times follow the selected observing site's time zone
- **iOS Widgets**: Home screen widgets backed by shared cached conditions and selected location data
- **watchOS App**: Apple Watch dashboard with location selection, night quality, current conditions, and astronomical night details
- **watchOS Complications**: Inline, circular, corner, and rectangular complication views
- **iPhone/Watch Sync**: Saved locations, selected location, unit preferences, and cached conditions are exchanged through WatchConnectivity

### Data Sources
1. **Open-Meteo API** (https://open-meteo.com/)
   - Free weather forecasts
   - Free geocoding
   - No API key required
   - Hourly resolution up to 3 days

2. **SunCalc Swift Package** (https://github.com/nikolajjensen/SunCalc)
   - Pure Swift astronomical calculations
   - Sun/moon positions and phases
   - Works offline

3. **N2YO API** (https://www.n2yo.com/)
   - Optional ISS pass predictions
   - Free API key required

4. **Curated Local Target Catalog**
   - Moon, naked-eye planets, double stars, star clusters, nebulae, and galaxies
   - Local position and visibility calculations; no target API required at runtime
   - Bundled reference images work offline and retain source/license attribution

---

## 3. Architecture Design

### Design Principles
- **No Custom Backend**: Data comes from public APIs, local calculations, and platform storage/sync services
- **Fresh Forecasts First**: Weather data is fetched on demand and treated as time-sensitive
- **Shared Snapshot Data**: Cached conditions and selected location snapshots are shared with widgets and Apple Watch so glanceable surfaces can render without launching the iOS app
- **Feature-Based Organization**: UI is grouped by product surface and feature
- **Shared Core Module**: Cross-platform models, services, and utilities live in `SharedCode`
- **iOS Appearance Isolation**: Field Mode persistence and semantic visual tokens live in the iOS app target. Light, Dark, and Field Mode use the same persistent native `TabView`; only Field Mode forces a dark scheme and supplies dim-red semantic colors through UIKit appearance configuration without replacing root views. Reusable title, primary-action, card, list, map, and control modifiers cover system boundaries that do not inherit ordinary foreground styles. This keeps the selected tab and mounted screen instances stable, preserving Dashboard state, selected forecast day, loaded conditions, and scroll position when Field Mode changes. Maps use MapKit's supported flat, muted standard style and dark color scheme, but Apple Maps labels, attribution, and other map-renderer details remain system controlled. Widgets, watchOS, model data, caches, and connectivity payloads remain unchanged.

### Project Structure
```
AstroViewingConditions/
├── AstroViewingConditions.xcodeproj/           # Checked-in Xcode project
├── project.yml                                 # XcodeGen source configuration
├── Sources/
│   ├── App/                                    # iOS app plist, entitlements, privacy manifest
│   ├── AstroViewingConditions/
│   │   ├── App/                                # iOS app entry point and tab container
│   │   ├── Features/
│   │   │   ├── Dashboard/                      # Conditions, Best Targets, target details, ISS
│   │   │   ├── Locations/                      # Saved/search/map/manual locations
│   │   │   ├── BestSpot/                       # Best observing spot workflow
│   │   │   └── Settings/                       # App preferences
│   │   ├── Resources/                          # iOS app assets
│   │   └── Services/
│   │       └── WatchConnectivityService.swift  # iPhone-side watch sync
│   │
│   ├── SharedCode/
│   │   └── Core/
│   │       ├── Models/                         # Codable/SwiftData-friendly domain models
│   │       ├── Services/                       # Weather, astronomy, target recommendations, ISS, storage, cache
│   │       └── Utilities/                      # Formatters, units, fog, night quality, time zones
│   │
│   ├── Widgets/                                # iOS WidgetKit extension
│   ├── WatchApp/                               # watchOS app, views, managers, assets
│   └── WatchWidget/                            # watchOS complication extension
│
├── Tests/AstroViewingConditionsTests/          # Unit tests
├── README.md
├── LICENSE
├── build.sh
└── open_in_xcode.sh
```

### Targets
Defined in `project.yml`:

- `SharedCode`: Cross-platform framework for iOS and watchOS
- `AstroViewingConditions`: Main iOS app
- `NightConditionsWidget`: iOS WidgetKit extension
- `AstroViewingConditionsWatch`: watchOS app
- `AstroViewingConditionsWatchWidget`: watchOS complication extension
- `AstroViewingConditionsTests`: iOS unit test bundle

### Data Models and Storage

#### Persistent User Data
`SavedLocation` and `EquipmentItem` are the core user-owned SwiftData models. The app also keeps selected-location and unit preference snapshots for app extensions and watch sync. Equipment inventory remains local to the iOS app; session equipment selection is deliberately non-persistent.

```swift
@Model
class SavedLocation {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var isFavorite: Bool
    var dateAdded: Date
    var sortPosition: Int?
}
```

#### Shared Snapshot Data
`ViewingConditions`, cached locations, selected location, and unit preferences are encoded for app group storage, iCloud key-value storage, widget timelines, and WatchConnectivity messages.

Important services:
- `CacheService`: Stores the latest encoded conditions snapshot
- `AppGroupStorage`: Shares data between the iOS app and extensions
- `LocationStorageService`: Persists selected/saved location snapshots for widgets and watch sync
- `iCloudKeyValueStorage`: Supports lightweight cloud-backed preference/location state
- `MigrationHelper`: Migrates older widget/cache storage into the newer shared storage approach
- `WidgetReloadService`: Requests widget timeline refreshes after relevant data changes
- `TargetRecommendationService`: Scores and ranks the curated targets for a forecast night
- `EquipmentItem` and `EquipmentMatchingService`: Store a user's inventory through SwiftData and compare the selected session equipment with catalog-driven target requirements
- `BestSpotSearcher`: Scores nearby areas, preserves all sampled scores, verifies ranked candidate suitability, and returns recommendable top locations
- `LocationSuitabilityService`: Wraps Apple reverse geocoding for land/water/suitability checks with cached batch lookup support
- `MoonRecommendationService` and `PlanetRecommendationService`: Calculate useful visibility windows for solar-system targets
- `DeepSkyCatalogService`: Supplies the curated deep-sky catalog and observing metadata
- `AsyncTimeout`: Bounds weather, geocoding, location, time-zone, and ISS requests so a failed service does not wait indefinitely
- `NightQualityAnalyzer`: Combines observing factors into hourly and nightly assessments
- `SeeingCalculator`: Produces the optional temperature-stability and 200 hPa wind penalty
- `TransparencyCalculator`: Produces the optional cloud-layer and visibility penalty

---

## 4. Technical Decisions

### Why SwiftUI?
- Modern declarative UI framework
- Native support across iOS and watchOS
- Strong integration with WidgetKit and current Apple platform patterns

### Why SharedCode?
- Weather, astronomy, location scoring, units, formatting, and storage logic are needed by multiple targets
- Keeps iOS, widgets, and watchOS from drifting into separate implementations
- Allows tests to cover shared behavior instead of only app-specific code

### Why SwiftData Plus Shared Storage?
- SwiftData is a good fit for user-managed saved locations inside the app
- Widgets and watchOS need Codable snapshots available outside the main app lifecycle
- App group storage, iCloud key-value storage, and WatchConnectivity handle extension rendering and cross-device sync

### Why No Custom Backend?
- Required data is available via public APIs and local calculations
- Keeps the project simpler to run and maintain
- Avoids server costs and backend account setup
- Allows widgets and watchOS to use recent cached snapshots when the phone app is not active

### Best Nearby Area Recommendation Safety
- `BestSpotResult` keeps both `topLocations` and `allScoredLocations`; default UI uses `topLocations` for recommendation pins and keeps the full scored field available for diagnostics or a future heatmap/weather-field mode.
- `LocationScore.canOpenInMaps` gates destination actions. Known water/unsuitable and unchecked points are not presented as map destinations; recommendations with inconclusive verification are clearly labeled so observers can verify access.
- Candidate suitability checks expand through ranked weather candidates until enough recommendations are found, the ranked list is exhausted, or `BestSpotSearcher.maxSuitabilityCandidateChecks` is reached. The current cap is 40 checks, chosen to stay below the observed iOS/CoreLocation reverse-geocoding throttling threshold and keep all-water/coastal searches responsive.
- If no recommendable candidates are found before the cap, the search reports `noRecommendableLocations`. If some are found but fewer than requested, the available recommendations are returned.
- The feature does not validate roads, parking, ownership, legal access, personal safety, elevation advantage, light pollution, or local horizon obstructions.

### Why AGPL-3.0 License?
- Prevents commercial apps from taking the code
- Ensures modifications remain open source
- Protects the astronomy community's investment
- Aligns with open data sources used

---

## 5. Implementation Plan

### Phase 1: Foundation - Complete
- [x] Project setup with Xcode project and XcodeGen configuration
- [x] SwiftData model for saved locations
- [x] Basic iOS tab structure
- [x] Location permission handling

### Phase 2: Data Layer - Complete
- [x] WeatherService with Open-Meteo integration
- [x] AstronomyService with SunCalc integration
- [x] ISSService with N2YO integration
- [x] FogCalculator
- [x] UnitConverter
- [x] Location time zone resolution
- [x] Shared cache and app group storage helpers
- [x] Curated deep-sky catalog and local Moon/planet position calculations
- [x] Target scoring and observing-window calculation
- [x] Timeouts for network and location-dependent requests

### Phase 3: iOS Dashboard UI - Complete
- [x] DashboardViewModel with observable state
- [x] Today/Tomorrow/DayAfter tabs
- [x] Hourly forecast visualization
- [x] Sun/Moon cards
- [x] ISS pass display
- [x] Night quality card
- [x] Pull-to-refresh
- [x] Offline/stale data handling
- [x] Best Targets dashboard card and complete recommendations list
- [x] Target detail sheets with curated observing guidance for every named deep-sky catalog target and credited offline imagery
- [x] Persistent equipment inventory plus session-level equipment-fit guidance and filtering in Best Targets
- [x] Detailed ISS paths, active passes, empty states, and service errors
- [x] Consistent dashboard card styling and Light Mode cloud-symbol contrast

### Phase 4: Locations Management - Complete
- [x] Favorites list with SwiftData-backed app storage
- [x] Location search using geocoding
- [x] Map picker
- [x] Manual coordinate entry
- [x] Selected location snapshots for widgets and watchOS
- [x] Rename saved locations
- [x] Drag to reorder saved locations and preserve that order in the dashboard picker and watch sync

### Phase 5: Settings & Polish - Complete
- [x] Unit system toggle
- [x] Settings UI
- [x] Error handling and edge cases
- [x] Accessibility basics

### Phase 6: Widgets - Complete
- [x] iOS widget extension
- [x] Small and medium widget layouts
- [x] Shared timeline data backed by cached conditions
- [x] Widget reload service

### Phase 7: watchOS - Complete
- [x] watchOS app target
- [x] Watch dashboard
- [x] Watch location selector
- [x] Watch conditions manager
- [x] Watch location manager
- [x] iPhone/watch connectivity
- [x] watchOS complication extension
- [x] Inline, circular, corner, and rectangular complication layouts

### Phase 8: Open Source - Complete
- [x] GitHub repository structure
- [x] README
- [x] LICENSE (AGPL-3.0)
- [x] Project documentation
- [x] Observer guide

### Phase 9: Target Recommendations - Complete
- [x] Moon and naked-eye planet recommendations
- [x] Curated double stars, clusters, nebulae, and galaxies
- [x] Easy, standard, and challenge observing-intent labels
- [x] Moonlight-aware and poor-weather-aware ranking
- [x] Interpolated visibility-window boundaries and corrected planetary epoch calculations
- [x] Target image viewer with source and license attribution

---

## 6. Remaining Work

Product priority, next-release sequencing, and future feature direction are centralized in [FEATURES/FEATURE_ROADMAP.md](FEATURES/FEATURE_ROADMAP.md). This section keeps engineering follow-up notes only.

### Known Issues to Address
1. **Concurrency Review**: Continue auditing Swift concurrency, `@unchecked Sendable`, and main-actor boundaries before release.
2. **Map Picker Polish**: Validate map coordinate conversion and UX on current iOS simulator/device combinations.
3. **Offline UX**: Improve messaging when the phone, watch, widgets, or network cannot provide fresh conditions.
4. **Watch Sync Edge Cases**: Test first launch, unreachable phone, stale cache, and selection changes from both devices.
5. **Recommendation Validation**: Continue field-checking observing windows and guidance across seasons, latitudes, polar day/night, and obstructed horizons.

### Product Roadmap
- [ ] Maintain product priority in `FEATURES/FEATURE_ROADMAP.md`
- [ ] Keep detailed feature plans, such as `FEATURES/SEEING_AND_TRANSPARENCY_PLAN.md`, aligned with the roadmap instead of creating separate priority lists

### Testing Needs
- [x] Unit tests for key models and utilities
- [x] Unit tests for weather, astronomy, ISS, best spot, and migration helpers
- [x] Unit tests for target scoring, including Venus twilight behavior; Moon and planet recommendations; catalog metadata; image manifests; target-detail guidance; and equipment persistence, matching, and filtering
- [x] Unit tests for Field Mode preference defaults, persistence, appearance resolution, and palette characteristics
- [ ] Widget timeline tests
- [ ] WatchConnectivity tests or integration checklist
- [ ] UI tests for critical iOS paths
- [ ] watchOS UI smoke tests
- [ ] Location permission edge cases

### Field Mode Manual Verification

System-controlled limitations: Field Mode does not recolor status-bar icons or the clock, Apple Maps labels or legal attribution, or the native toggle thumb. The app uses only supported appearance, MapKit, tint, and semantic-color APIs around those elements.

- [ ] Launch with the device in Light Mode and confirm normal system Light appearance.
- [ ] Launch with the device in Dark Mode and confirm normal system Dark appearance.
- [ ] Toggle Field Mode in Settings; confirm the dim red appearance applies immediately and the iOS-only explanation is visible.
- [ ] Toggle Field Mode from the Dashboard toolbar; confirm its VoiceOver label, on/off value, and hint.
- [ ] Navigate the Dashboard day selector, condition cards, Sun/Moon timing, hourly forecast, ISS content, and Best Targets card.
- [ ] Open Locations, add/search/manual/map location flows, and the Dashboard location picker.
- [ ] Open the complete Best Targets list, target details, bundled target imagery, and the full-screen image viewer.
- [ ] Open Best Nearby Area, its map, search settings, results, and error/cancellation paths.
- [ ] Verify the native tab-bar layout remains consistent across Light, Dark, and Field Mode, and that the selected tab is preserved when changing modes.
- [ ] On the Dashboard, select a forecast day, load conditions, and scroll; toggle Field Mode and confirm the Dashboard state, selected day, loaded conditions, and scroll position are preserved.
- [ ] Verify long selected location names truncate at the tail without colliding and VoiceOver announces the complete name.
- [ ] Exercise sheets plus loading, refreshing, stale, offline, empty, and error states; confirm no app-controlled bright background flashes.
- [ ] Relaunch with Field Mode enabled and confirm it persists.
- [ ] Disable Field Mode and confirm the app returns to the device's system Light/Dark behavior.
- [ ] Confirm iOS widgets, the watchOS app, and complications are visually and functionally unchanged.
- [ ] On a physical device at low brightness in a dark room, check essential text, selected controls, borders, and status labels for readable low-glare contrast.

### Polish
- [ ] App icon design review across iOS and watchOS
- [ ] Launch screen
- [ ] Onboarding/tutorial for first-time users
- [ ] In-app access to the observer guide or concise explanations of target scores and difficulty labels
- [ ] Better empty states
- [ ] Animation improvements

---

## 7. API Reference

### Open-Meteo Weather
```
GET https://api.open-meteo.com/v1/forecast
Parameters:
  - latitude: Double
  - longitude: Double
  - hourly: cloudcover,cloudcover_low,cloud_cover_mid,cloud_cover_high,relativehumidity_2m,windspeed_10m,wind_speed_200hPa,...
  - timezone: auto
  - forecast_days: 3
```

### Open-Meteo Geocoding
```
GET https://geocoding-api.open-meteo.com/v1/search
Parameters:
  - name: String
  - count: 10
```

### N2YO ISS
```
GET https://api.n2yo.com/rest/v1/satellite/visualpasses/{id}/{observer_lat}/{observer_lng}/{observer_alt}/{days}/{min_visibility}/&apiKey={apiKey}
Parameters:
  - id: Int (25544 for ISS)
  - observer_lat: Double
  - observer_lng: Double
  - observer_alt: Int
  - days: Int
  - min_visibility: Int
  - apiKey: String
```

---

## 8. How to Resume Work

### If You've Lost the Conversation
1. Read this document.
2. Check the current code in `/Users/gaston/repo/AstroViewingConditions/`.
3. Open the checked-in Xcode project:
   ```bash
   cd /Users/gaston/repo/AstroViewingConditions
   open AstroViewingConditions.xcodeproj
   ```
4. Build the `AstroViewingConditions` scheme on an iOS simulator.
5. Build the `AstroViewingConditionsWatch` scheme on a watchOS simulator.
6. Review TODOs, tests, and known issues in Section 6.

### To Continue Development
```bash
cd /Users/gaston/repo/AstroViewingConditions
./build.sh
xcodebuild -project AstroViewingConditions.xcodeproj -scheme AstroViewingConditions -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

If `project.yml` changes, regenerate the Xcode project with XcodeGen before committing the project file changes.

### Key Files to Understand
- `Sources/AstroViewingConditions/Features/Dashboard/DashboardView.swift` - Main iOS conditions UI
- `Sources/AstroViewingConditions/Features/Dashboard/DashboardViewModel.swift` - iOS dashboard state and loading flow
- `Sources/AstroViewingConditions/Features/Dashboard/TonightsBestTargetsCard.swift` - Dashboard target recommendations
- `Sources/AstroViewingConditions/Features/Dashboard/TargetDetailContentBuilder.swift` - Observer-facing target guidance
- `Sources/AstroViewingConditions/Features/BestSpot/BestSpotView.swift` - Best Nearby Area UI, map annotations, and selected-area presentation
- `Sources/AstroViewingConditions/Features/BestSpot/BestSpotViewModel.swift` - Best Nearby Area state, search flow, and guarded Maps actions
- `Sources/AstroViewingConditions/Services/WatchConnectivityService.swift` - iPhone-side watch communication
- `Sources/WatchApp/Features/Dashboard/WatchDashboardView.swift` - Main watchOS UI
- `Sources/WatchApp/Services/WatchConnectivityManager.swift` - Watch-side communication
- `Sources/SharedCode/Core/Services/WeatherService.swift` - Weather API integration
- `Sources/SharedCode/Core/Services/CacheService.swift` - Shared condition cache
- `Sources/SharedCode/Core/Services/LocationStorageService.swift` - Shared selected/saved location snapshots
- `Sources/SharedCode/Core/Services/TargetRecommendationService.swift` - Deep-sky ranking and visibility windows
- `Sources/SharedCode/Core/Services/BestSpotSearcher.swift` - Nearby-area weather scoring, suitability expansion, and recommendation selection
- `Sources/SharedCode/Core/Services/LocationSuitabilityService.swift` - Reverse-geocoded suitability checks used by Best Nearby Area
- `Sources/SharedCode/Core/Services/MoonRecommendationService.swift` - Moon visibility and recommendation logic
- `Sources/SharedCode/Core/Services/PlanetRecommendationService.swift` - Local planet position and recommendation logic
- `Sources/SharedCode/Core/Services/DeepSkyCatalogService.swift` - Curated target catalog
- `Sources/SharedCode/Core/Models/SavedLocation.swift` - Saved location model
- `project.yml` - Target and scheme definitions

---

## 9. Project Status

**Current Status**: Core observing planner, target recommendations, widgets, and watchOS support complete.

Implemented:
- Real-time weather data
- Astronomical calculations
- ISS pass predictions
- Night quality analysis
- Seeing & Transparency
- Best Nearby Area with checked ranked recommendations and a recommended-only default map
- Best Targets with scores, observing windows, curated target guidance, equipment-fit filtering, and offline reference images
- Persistent My Equipment inventory for binoculars, visual telescopes, and Smart / EAA telescopes
- Detailed ISS pass paths and error states
- Renameable and reorderable saved locations
- Unit preferences
- Persistent iOS-only Field Mode with a semantic dim-red palette, reusable field surfaces and controls, and a stable native tab-bar layout across appearance modes
- iOS widgets
- watchOS app
- watchOS complications
- Shared storage and iPhone/watch sync
- Core unit test coverage

**Next Milestone**: Simple horizon constraints per saved location. See [FEATURES/FEATURE_ROADMAP.md](FEATURES/FEATURE_ROADMAP.md) for the full sequence.

---

## 10. Contact & Contribution

This is an open-source project. Contributions welcome.

- Repository: https://github.com/gdombiak/AstroViewingConditions
- Issues: Use GitHub issues for bug reports
- Discussions: Use GitHub discussions for feature requests

---

*Last Updated: July 21, 2026*
*Document Version: 1.7*
