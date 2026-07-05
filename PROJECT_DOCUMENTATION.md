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
- **Weather Data**: Cloud cover, humidity, wind, temperature, visibility, dew point, and hourly forecasts via Open-Meteo
- **Astronomical Data**: Sun/moon rise-set times, astronomical night timing, and moon phase via SunCalc
- **Night Quality Analysis**: Observing assessment based on cloud cover, moonlight, fog, wind, and nighttime windows
- **Best Targets**: Ranked Moon, planet, double-star, cluster, nebula, and galaxy recommendations for the selected location and forecast night
  - Scores combine visibility, altitude, astronomical darkness, weather, moonlight, and observing difficulty
  - Shows the observing window, direction, maximum altitude, and a concise recommendation rationale
  - Full target details provide finding tips, equipment suggestions, observing notes, and difficulty guidance
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
`SavedLocation` is the core user-owned location model. The app also keeps selected-location and unit preference snapshots for app extensions and watch sync.

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
- `MoonRecommendationService` and `PlanetRecommendationService`: Calculate useful visibility windows for solar-system targets
- `DeepSkyCatalogService`: Supplies the curated deep-sky catalog and observing metadata
- `AsyncTimeout`: Bounds weather, geocoding, location, time-zone, and ISS requests so a failed service does not wait indefinitely

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
- [x] Target detail sheets with observing guidance and credited offline imagery
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

### Known Issues to Address
1. **Concurrency Review**: Continue auditing Swift concurrency, `@unchecked Sendable`, and main-actor boundaries before release.
2. **Map Picker Polish**: Validate map coordinate conversion and UX on current iOS simulator/device combinations.
3. **Offline UX**: Improve messaging when the phone, watch, widgets, or network cannot provide fresh conditions.
4. **Watch Sync Edge Cases**: Test first launch, unreachable phone, stale cache, and selection changes from both devices.
5. **Recommendation Validation**: Continue field-checking observing windows and guidance across seasons, latitudes, polar day/night, and obstructed horizons.

### Nice-to-Have Features
- [ ] Push notifications for optimal viewing conditions
- [ ] Light pollution map integration
- [ ] Dark sky places database
- [ ] Aurora forecast integration
- [ ] Satellite pass predictions other than ISS
- [ ] Custom location notes/photos
- [ ] Export/share conditions report
- [ ] More widget sizes or richer Lock Screen surfaces

### Testing Needs
- [x] Unit tests for key models and utilities
- [x] Unit tests for weather, astronomy, ISS, best spot, and migration helpers
- [x] Unit tests for target scoring, Moon and planet recommendations, catalog metadata, image manifests, and target-detail guidance
- [ ] Widget timeline tests
- [ ] WatchConnectivity tests or integration checklist
- [ ] UI tests for critical iOS paths
- [ ] watchOS UI smoke tests
- [ ] Location permission edge cases

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
  - hourly: cloudcover,cloudcover_low,relativehumidity_2m,windspeed_10m,...
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
- `Sources/AstroViewingConditions/Services/WatchConnectivityService.swift` - iPhone-side watch communication
- `Sources/WatchApp/Features/Dashboard/WatchDashboardView.swift` - Main watchOS UI
- `Sources/WatchApp/Services/WatchConnectivityManager.swift` - Watch-side communication
- `Sources/SharedCode/Core/Services/WeatherService.swift` - Weather API integration
- `Sources/SharedCode/Core/Services/CacheService.swift` - Shared condition cache
- `Sources/SharedCode/Core/Services/LocationStorageService.swift` - Shared selected/saved location snapshots
- `Sources/SharedCode/Core/Services/TargetRecommendationService.swift` - Deep-sky ranking and visibility windows
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
- Best Targets with scores, observing windows, practical guidance, and offline reference images
- Detailed ISS pass paths and error states
- Renameable and reorderable saved locations
- Unit preferences
- iOS widgets
- watchOS app
- watchOS complications
- Shared storage and iPhone/watch sync
- Core unit test coverage

**Next Milestone**: Validate target recommendations in more seasons and latitudes, harden watch/widget edge cases, add UI coverage, and complete final App Store polish.

---

## 10. Contact & Contribution

This is an open-source project. Contributions welcome.

- Repository: https://github.com/gdombiak/AstroViewingConditions
- Issues: Use GitHub issues for bug reports
- Discussions: Use GitHub discussions for feature requests

---

*Last Updated: May 27, 2026*
*Document Version: 1.1*
