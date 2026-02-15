# Astro Viewing Conditions - Project Documentation

> **Purpose**: This document captures the complete project context, architecture, and implementation plan so work can be resumed even if the conversation history is lost.

---

## 1. Project Overview

### Goal
Build an open-source iOS app for astronomy enthusiasts to check nighttime viewing conditions. The app provides real-time weather data, astronomical information, and ISS pass predictions to help users plan their stargazing sessions.

### Target Users
- Amateur astronomers
- Astrophotographers  
- Casual stargazers
- Anyone interested in night sky observation

### Platform
- **iOS 18+**
- Written in **Swift 6.0**
- Uses **SwiftUI** for UI
- **SwiftData** for persistence

### License
**AGPL-3.0** - Ensures the app remains open source and prevents commercial exploitation while keeping it free for the astronomy community.

---

## 2. Core Features

### Implemented ✅
- **Weather Data**: Cloud cover, humidity, wind, temperature, visibility (via Open-Meteo API)
- **Astronomical Data**: Sun/moon rise-set times, moon phase with emoji visualization (via SunCalc library)
- **ISS Pass Predictions**: Next 10 visible passes with duration and max elevation (via Open Notify API)
- **Fog Score**: Calculated risk based on humidity, temperature-dew point difference, visibility, and low cloud cover
- **Location Management**: 
  - Auto-detect current location
  - Save favorite locations
  - Search by city name
  - Manual coordinate entry
  - Map-based location picker
- **Unit Preferences**: Toggle between Metric and Imperial
- **3-Day Forecast**: Today, tomorrow, and day after

### Data Sources
1. **Open-Meteo API** (https://open-meteo.com/)
   - Free weather forecasts
   - No API key required
   - Hourly resolution up to 3 days

2. **SunCalc Swift Package** (https://github.com/nikolajjensen/SunCalc)
   - Pure Swift astronomical calculations
   - Sun/moon positions and phases
   - Works offline

3. **Open Notify API** (http://open-notify.org/)
   - ISS pass predictions
   - Free, no API key required

---

## 3. Architecture Design

### Design Principles
- **No Backend**: All data comes from client-side APIs and calculations
- **Ephemeral Weather Data**: Conditions are fetched on-demand, never persisted (go stale within hours)
- **Simple Persistence**: Only `SavedLocation` model stored in SwiftData
- **Feature-Based Organization**: Code grouped by functionality, not by type

### Project Structure
```
AstroViewingConditions/
├── Sources/AstroViewingConditions/
│   ├── App/
│   │   ├── AstroViewingConditionsApp.swift    # App entry point
│   │   └── ContentView.swift                   # Main tab container
│   │
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── SavedLocation.swift            # SwiftData model (persistent)
│   │   │   └── ViewingConditions.swift        # Transient data structures
│   │   │
│   │   ├── Services/
│   │   │   ├── WeatherService.swift           # Open-Meteo API client
│   │   │   ├── AstronomyService.swift         # SunCalc wrapper
│   │   │   ├── ISSService.swift               # Open Notify API client
│   │   │   └── LocationManager.swift          # CoreLocation wrapper
│   │   │
│   │   ├── Utilities/
│   │   │   ├── FogCalculator.swift            # Fog risk algorithm
│   │   │   ├── UnitConverter.swift            # Metric/Imperial conversion
│   │   │   └── Formatters.swift               # Date/coordinate formatting
│   │   │
│   │   └── ViewModels/
│   │       └── DashboardViewModel.swift       # Main view state management
│   │
│   └── Features/
│       ├── Dashboard/
│       │   ├── DashboardView.swift            # Main viewing conditions
│       │   ├── DashboardViewModel.swift
│       │   ├── TodayCard.swift                # Current conditions summary
│       │   ├── HourlyForecastView.swift       # Color-coded hourly chart
│       │   ├── SunMoonCard.swift              # Astronomical data display
│       │   ├── ISSCard.swift                  # ISS passes list
│       │   └── FogScoreView.swift             # Fog risk indicator
│       │
│       ├── Locations/
│       │   ├── LocationsListView.swift        # Saved locations list
│       │   ├── LocationSearchView.swift       # Search & add locations
│       │   └── MapPickerView.swift            # Map-based selection
│       │
│       └── Settings/
│           └── SettingsView.swift             # App preferences
│
├── Package.swift                               # SPM manifest
├── README.md
├── LICENSE                                     # AGPL-3.0
└── .gitignore
```

### Data Models

#### Persistent (SwiftData)
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
}
```

#### Transient (In-Memory Only)
```swift
struct ViewingConditions {
    let fetchedAt: Date
    let location: SavedLocation
    let hourlyForecasts: [HourlyForecast]      // 72 hours
    let sunEvents: SunEvents
    let moonInfo: MoonInfo
    let issPasses: [ISSPass]
    let fogScore: FogScore
}
```

---

## 4. Technical Decisions

### Why SwiftUI?
- Modern declarative UI framework
- Native iOS 18 support
- Better integration with SwiftData

### Why SwiftData?
- Apple's modern persistence framework
- Type-safe
- Built-in cloud sync capability (future)
- Minimal boilerplate compared to Core Data

### Why No Backend?
- All required data available via public APIs
- Keeps app simple and maintainable
- No server costs or maintenance
- Fully functional offline with cached data

### Why AGPL-3.0 License?
- Prevents commercial apps from taking the code
- Ensures modifications remain open source
- Protects the astronomy community's investment
- Aligns with open data sources used

---

## 5. Implementation Plan

### Phase 1: Foundation ✅ COMPLETE
- [x] Project setup with SPM
- [x] SwiftData model (SavedLocation)
- [x] Basic tab structure
- [x] Location permission handling

### Phase 2: Data Layer ✅ COMPLETE
- [x] WeatherService (Open-Meteo integration)
- [x] AstronomyService (SunCalc integration)
- [x] ISSService (Open Notify integration)
- [x] FogCalculator
- [x] UnitConverter

### Phase 3: Dashboard UI ✅ COMPLETE
- [x] DashboardViewModel with @Observable
- [x] Today/Tomorrow/DayAfter tabs
- [x] Hourly forecast visualization
- [x] Sun/Moon cards
- [x] ISS pass display
- [x] Pull-to-refresh
- [x] Offline/stale data warning

### Phase 4: Locations Management ✅ COMPLETE
- [x] Favorites list with SwiftData
- [x] Location search (geocoding)
- [x] Map picker
- [x] Manual coordinate entry

### Phase 5: Settings & Polish ✅ COMPLETE
- [x] Unit system toggle
- [x] Settings UI
- [x] Error handling & edge cases
- [x] Accessibility basics

### Phase 6: Open Source ✅ COMPLETE
- [x] GitHub repository structure
- [x] README with screenshots placeholder
- [x] LICENSE (AGPL-3.0)
- [x] Documentation (this file)

---

## 6. Remaining Work (Future Enhancements)

### Known Issues to Address
1. **Concurrency Warnings**: DashboardViewModel has Sendable/data race warnings that need resolution for production
2. **Map Picker**: MapProxy coordinate conversion needs refinement
3. **Error Handling**: Some edge cases (no internet, invalid coordinates) need better UX

### Nice-to-Have Features
- [ ] Widget support for home screen
- [ ] Push notifications for optimal viewing conditions
- [ ] Light pollution map integration
- [ ] Saved locations sync via iCloud
- [ ] Dark sky places database
- [ ] Aurora forecast integration
- [ ] Satellite pass predictions (other than ISS)
- [ ] Custom location notes/photos
- [ ] Export/share conditions report

### Testing Needs
- [ ] Unit tests for services
- [ ] Unit tests for FogCalculator
- [ ] UI tests for critical paths
- [ ] Location permission edge cases

### Polish
- [ ] App icon design
- [ ] Launch screen
- [ ] Onboarding/tutorial for first-time users
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
  - name: String (search query)
  - count: 10
```

### Open Notify ISS
```
GET http://api.open-notify.org/iss-pass.json
Parameters:
  - lat: Double
  - lon: Double
  - n: 10 (number of passes)
```

---

## 8. How to Resume Work

### If You've Lost the Conversation:
1. Read this entire document
2. Check the current code in `/Users/gaston/repo/AstroViewingConditions/`
3. Open in Xcode: `cd /Users/gaston/repo/AstroViewingConditions && open Package.swift`
4. Build and run on iOS Simulator
5. Review TODOs in code and issues mentioned in Section 6

### To Continue Development:
```bash
cd /Users/gaston/repo/AstroViewingConditions
swift build          # Check for compilation errors
swift test           # Run tests (when added)
```

### Key Files to Understand:
- `DashboardView.swift` - Main UI
- `DashboardViewModel.swift` - Business logic
- `WeatherService.swift` - API integration pattern
- `SavedLocation.swift` - Data model

---

## 9. Project Status

**Current Status**: ✅ MVP COMPLETE

The app is fully functional with all core features implemented:
- ✅ Real-time weather data
- ✅ Astronomical calculations
- ✅ ISS pass predictions
- ✅ Location management
- ✅ Unit preferences
- ✅ Clean architecture

**Next Milestone**: Fix concurrency warnings and add comprehensive testing before App Store submission.

---

## 10. Contact & Contribution

This is an open-source project. Contributions welcome!

- Repository: GitHub (to be created)
- Issues: Use GitHub issues for bug reports
- Discussions: GitHub discussions for feature requests

---

*Last Updated: February 14, 2026*
*Document Version: 1.0*
