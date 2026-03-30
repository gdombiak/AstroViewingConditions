# Astro Viewing Conditions - Feature Roadmap

> Detailed implementation plan for future releases

---

## 1. Visible Planets Tonight

### Description
Show users which planets are currently visible in their night sky, with rise/set times and visibility windows.

### Data Source
- **API**: `api.visibleplanets.dev` (free, no key required)
- **Alternative**: SwiftAstro package for local calculations

### Implementation

#### New Service: `PlanetsService.swift`
```
GET https://api.visibleplanets.dev/v3?latitude={lat}&longitude={lon}&showCoords=true
```

**Response fields to use:**
- `name` - planet name
- `horizonAltitude` - degrees above horizon
- `horizonAzimuth` - compass direction
- `rise` - rise time (ISO 8601)
- `set` - set time (ISO 8601)
- `magnitude` - brightness

#### New Model: `VisiblePlanet.swift`
```swift
struct VisiblePlanet: Identifiable, Codable {
    let id: String
    let name: String
    let horizonAltitude: Double  // degrees
    let horizonAzimuth: Double  // degrees from North
    let rise: Date?
    let set: Date?
    let magnitude: Double       // brightness (-2.5 to +4)
    let constellation: String?   // which constellation
    
    var isVisible: Bool { horizonAltitude > 0 }
}
```

#### UI: PlanetsCard.swift
- List of visible planets with icons
- Show rise/set times
- Color-coded visibility (green=high, yellow=low, gray=not visible)
- Tap for details (altitude, azimuth, magnitude)

#### Integration
- Add to `ViewingConditions` model
- Fetch in `DashboardViewModel.loadConditions()`
- Display in new tab or expandable card on Dashboard

---

## 2. Meteor Shower Calendar

### Description
Display upcoming meteor showers with peak dates, expected rates (ZHR), moon conditions, and best viewing windows.

### Data Source
- **Static data**: Embed annual meteor shower calendar (no API needed)
- **API optional**: NASA or SeaSky for exact peak times

### Implementation

#### New Model: `MeteorShower.swift`
```swift
struct MeteorShower: Identifiable {
    let id: String
    let name: String              // e.g., "Perseids"
    let peakDate: Date
    let activityStart: Date       // when meteor activity begins
    let activityEnd: Date         // when meteor activity ends
    let zhr: Int                  // zenithal hourly rate
    let parentBody: String?       // e.g., "Comet Swift-Tuttle"
    let description: String
    let bestViewing: String       // e.g., "After midnight"
}
```

#### Static Data: meteor_showers.json
Embed all major annual showers:

| Name | Peak | ZHR | Parent |
|------|------|-----|--------|
| Quadrantids | Jan 3-4 | 120 | 2003 EH1 |
| Lyrids | Apr 22-23 | 18 | Comet Thatcher |
| Eta Aquariids | May 5-6 | 50 | Halley's Comet |
| Delta Aquariids | Jul 29-30 | 25 | Comet 96P Machholz |
| Perseids | Aug 12-13 | 100 | Comet Swift-Tuttle |
| Orionids | Oct 21-22 | 20 | Halley's Comet |
| Leonids | Nov 17-18 | 15 | Tempel-Tuttle |
| Geminids | Dec 14-15 | 150 | 3200 Phaethon |
| Ursids | Dec 22-23 | 10 | Comet Tuttle |

#### UI: MeteorShowerCard.swift
- List upcoming showers (next 30 days highlighted)
- Show peak date countdown
- ZHR rating (low/medium/high)
- Moon phase warning (full moon = poor viewing)
- "Best for" indicator

#### Algorithm: MoonInterference()
```swift
func calculateMoonInterference(peakDate: Date, moonPhase: Double) -> InterferenceLevel {
    // Full moon = high interference
    // New moon = low interference
    // Return: low/medium/high
}
```

---

## 3. Celestial Events Calendar

### Description
Show upcoming astronomical events: eclipses, supermoons, planetary conjunctions, equinoxes, solstices.

### Data Source
- **Local calculation**: SunCalc can calculate equinoxes/solstices
- **Static data**: Embed known eclipses (solar/lunar) for next 5 years
- **API optional**: AstronomyAPI.com (requires auth, not free)

### Implementation

#### New Model: `CelestialEvent.swift`
```swift
struct CelestialEvent: Identifiable {
    let id: String
    let title: String             // "Total Lunar Eclipse"
    let date: Date
    let type: EventType           // .eclipse, .supermoon, .conjunction, .equinox, .solstice
    let description: String
    let visibility: String        // "Visible from Americas"
    let importance: Importance    // .major, .minor
}

enum EventType: String, Codable {
    case solarEclipse
    case lunarEclipse
    case supermoon
    case blueMoon
    case conjunction
    case opposition
    case equinox
    case solstice
    case comet
}
```

#### Static Data: celestial_events.json
```
2025:
  - Mar 14: Total lunar eclipse
  - Mar 20: Vernal equinox
  - Sep 7: Total - Sep 22: Autumnal equ lunar eclipse
 inox
  - Dec 21: Winter solstice

2026:
  - Mar 3: Total solar eclipse
  - Sep 12: Partial solar eclipse
  
2027:
  - Feb 17: Total lunar eclipse
  - Aug 12: Total solar eclipse
```

#### UI: EventsCalendarView.swift
- Monthly calendar view
- Event dots on dates
- Tap date to see events
- "Tonight's events" quick view on Dashboard

---

## 4. Home Screen Widgets

### Description
iOS widgets for quick glance on stargazing conditions without opening the app.

### Implementation (WidgetKit)

#### Widget Sizes
1. **Small**: Tonight's stargazing score (1-5 stars)
2. **Medium**: Score + cloud cover + moon phase
3. **Large**: Full conditions summary

#### New Target: AstroViewingConditionsWidget
```
AstroViewingConditions/
├── AstroViewingConditionsWidget/
│   ├── AstroViewingConditionsWidget.swift
│   ├── StargazingWidget.swift       # Small
│   ├── ConditionsWidget.swift       # Medium  
│   ├── FullWidget.swift             # Large
│   └── Assets.xcassets/
```

#### Data Sharing
- Use App Groups for shared UserDefaults
- Store latest conditions in shared container
- Widget reads from shared container

#### Widget Timeline
- Update every 30 minutes during daylight
- Update more frequently at night (15 min)
- Use `TimelineProvider` with placeholder/snapshot/getTimeline

#### Implementation Steps
1. Add WidgetKit to dependencies
2. Create widget extension target in project.yml
3. Define widget configurations
4. Implement TimelineProvider
5. Create widget views
6. Add App Groups entitlement
7. Update main app to write to shared container

---

## 5. Planetary Visibility with SwiftAstro

### Description
Local calculation of planet positions using SwiftAstro package (no external API needed).

### Data Source
- **Package**: SwiftAstro (SPM) - https://github.com/ncke/swiftastro
- Free, accurate planetary positions

### Implementation

#### Add Dependency
```yaml
packages:
  SwiftAstro:
    url: https://github.com/ncke/swiftastro.git
    from: "1.0.0"
```

#### New Service: `PlanetaryPositionsService.swift`
```swift
import SwiftAstro

class PlanetaryPositionsService {
    
    func calculatePositions(for date: Date, latitude: Double, longitude: Double) -> [PlanetPosition] {
        let time = SwiftAstro.Time(date: date)
        
        let planets: [Planet] = [.mercury, .venus, .mars, .jupiter, .saturn]
        
        return planets.map { planet in
            let (ra, decl) = planet.geocentricPosition(t: time)
            let (alt, az) = calculateAltitudeAzimuth(
                ra: ra, decl: decl,
                latitude: latitude, longitude: longitude,
                time: time
            )
            
            return PlanetPosition(
                planet: planet,
                altitude: alt,
                azimuth: az,
                magnitude: getMagnitude(for: planet),
                rise: calculateRiseTime(planet: planet, latitude: latitude, longitude: longitude, date: date),
                set: calculateSetTime(planet: planet, latitude: latitude, longitude: longitude, date: date)
            )
        }
    }
}
```

#### New Model: `PlanetPosition.swift`
```swift
struct PlanetPosition: Identifiable {
    let id = UUID()
    let planet: Planet
    let altitude: Double    // degrees above horizon
    let azimuth: Double     // degrees from north
    let magnitude: Double
    let rise: Date?
    let set: Date?
    
    var isVisible: Bool { altitude > 0 }
}
```

#### Integration
- Can be used as fallback if VisiblePlanets API unavailable
- Works offline
- More accurate for precise calculations

---

## 6. Additional Enhancements

### 6.1 Deep Sky Objects (DSO) Visibility
- Show best visible nebulae, galaxies, clusters based on conditions
- Use Messier catalog (110 objects)
- Filter by: visible now, clear skies, darkness level

### 6.2 Astronomical Twilight Indicator
- Show "astronomical twilight" times (when sky is truly dark)
- Better than just "sunset" for serious stargazers
- Calculated via SunCalc

### 6.3 Seeing Conditions
- Wind speed impact on telescopic seeing
- Atmospheric turbulence indicator
- Useful for astrophotographers

### 6.4 Best Time to Observe
- Algorithm combining:
  - Astronomical darkness (twilight times)
  - Moon below horizon or crescent
  - Cloud cover forecast
  - Seeing conditions
- Output: "Best observing window: 11PM - 3AM"

---

## Technical Implementation Order

### Phase 1 (Quick Wins)
1. Visible Planets Tonight - API is ready, minimal effort
2. Meteor Shower Calendar - static data, easy implementation

### Phase 2 (Core Value)
3. Celestial Events Calendar
4. Best Time to Observe algorithm

### Phase 3 (Differentiation)
5. Widget support
6. Planetary positions with SwiftAstro

---

## API Reference Summary

### Visible Planets API
```
GET https://api.visibleplanets.dev/v3
Query params:
  - latitude: number
  - longitude: number  
  - showCoords: boolean (optional)
  - time: ISO string (optional, defaults to now)
```

### Open-Meteo (already integrated)
```
GET https://api.open-meteo.com/v1/forecast
```

### SunCalc (already integrated)
- Twilight times
- Moon position
- Sun position

---

## File Structure After Implementation

```
Sources/AstroViewingConditions/
├── Core/
│   ├── Models/
│   │   ├── VisiblePlanet.swift        # NEW
│   │   ├── MeteorShower.swift          # NEW
│   │   ├── CelestialEvent.swift        # NEW
│   │   └── PlanetPosition.swift       # NEW
│   │
│   ├── Services/
│   │   ├── PlanetsService.swift       # NEW - VisiblePlanets API
│   │   ├── PlanetaryPositionsService.swift  # NEW - SwiftAstro
│   │   └── CelestialEventsService.swift     # NEW
│   │
│   └── Utilities/
│       ├── MoonInterference.swift     # NEW
│       └── BestObservingWindow.swift  # NEW
│
├── Features/
│   ├── Dashboard/
│   │   ├── PlanetsCard.swift          # NEW
│   │   ├── MeteorShowerCard.swift     # NEW
│   │   ├── EventsCard.swift           # NEW
│   │   └── BestTimeCard.swift         # NEW
│   │
│   └── Events/
│       └── CelestialEventsView.swift  # NEW
│
├── Resources/
│   ├── meteor_showers.json            # NEW
│   └── celestial_events.json          # NEW
│
AstroViewingConditionsWidget/          # NEW - Widget extension
├── AstroViewingConditionsWidget.swift
├── StargazingWidget.swift
├── ConditionsWidget.swift
└── Assets.xcassets/
```

---

## Testing Strategy

### Unit Tests
- PlanetsService: mock API responses
- MeteorShower: date calculations
- CelestialEvents: event ordering
- BestObservingWindow: algorithm accuracy

### Widget Tests
- Timeline provider updates
- Data sharing via App Groups

---

## Appendix: Visible Planets API Response Example

```json
{
  "data": [
    {
      "name": "Mars",
      "horizonAltitude": 25.5,
      "horizonAzimuth": 145.2,
      "rise": "2025-01-15T20:30:00Z",
      "set": "2025-01-16T04:15:00Z",
      "magnitude": -0.8,
      "constellation": "Aries"
    },
    {
      "name": "Venus",
      "horizonAltitude": 12.3,
      "horizonAzimuth": 235.8,
      "rise": "2025-01-15T06:45:00Z",
      "set": "2025-01-15T17:20:00Z",
      "magnitude": -3.9,
      "constellation": "Sagittarius"
    }
  ],
  "meta": {
    "latitude": 40.7128,
    "longitude": -74.0060,
    "time": "2025-01-15T22:00:00Z"
  }
}
```

---

## Appendix: ZHR Rating Scale

| ZHR | Rating | Description |
|-----|--------|-------------|
| 0-10 | Low | Few meteors, requires patience |
| 11-50 | Medium | Regular meteor activity |
| 51-100 | High | Good meteor shower |
| 100+ | Very High | Exceptional display |

---

## Appendix: Moon Interference Levels

| Moon Phase | Interference | Viewing Quality |
|------------|--------------|-----------------|
| 0-20% | Low | Excellent |
| 21-50% | Medium | Good |
| 51-80% | High | Fair |
| 81-100% | Very High | Poor |

---

This roadmap provides approximately 6-8 months of development work for a dedicated contributor.
