# Seeing & Transparency Feature Plan

## Overview

Add atmospheric seeing and transparency factors to the night quality scoring algorithm. Currently the algorithm considers cloud cover, fog, moon, and wind — but misses two critical factors for telescope use: **seeing** (atmospheric stability) and **transparency** (how clearly light passes through the atmosphere).

---

## Problem Statement

A night with 0% cloud cover, no fog, and no wind can still be terrible for observing if:
- The jet stream is strong (causing atmospheric turbulence / poor seeing)
- High-altitude cirrus clouds are present (reducing transparency)
- Temperature is changing rapidly (causing tube currents and atmospheric instability)

These conditions are invisible to the current scoring algorithm.

---

## Data Sources

Open-Meteo free tier already provides the needed parameters. We just need to request them:

| Parameter | Purpose | Open-Meteo field |
|-----------|---------|-----------------|
| Sea-level pressure | Pressure stability proxy for seeing | `pressure_msl` |
| Mid-level cloud cover | Transparency (altocumulus, altostratus) | `cloudcover_mid` |
| High-level cloud cover | Transparency (cirrus, cirrostratus) | `cloudcover_high` |
| Jet stream wind (80hPa ≈ 18km) | Seeing — strong upper winds = turbulence | `windspeed_80hPa` |

**API change** — add to `hourly` params in `WeatherService.swift`:
```
"pressure_msl",
"cloudcover_mid",
"cloudcover_high",
"windspeed_80hPa"
```

---

## Phase 1: Data Layer

### 1.1 Extend `HourlyForecast` model

```swift
public struct HourlyForecast {
    // existing fields...
    public let pressureMsl: Double?        // hPa
    public let cloudCoverMid: Int?         // %
    public let cloudCoverHigh: Int?        // %
    public let windSpeed80hPa: Double?     // km/h
}
```

### 1.2 Extend `HourlyData` response model

Add corresponding fields with snake_case coding keys:
```swift
public let pressureMsl: [Double]?         // "pressure_msl"
public let cloudcoverMid: [Int]?          // "cloudcover_mid"
public let cloudcoverHigh: [Int]?         // "cloudcover_high"
public let windspeed80hPa: [Double]?      // "windspeed_80hPa"
```

### 1.3 Update `WeatherService.parseHourlyForecasts`

Map the new fields when constructing `HourlyForecast`.

### 1.4 Update batch fetch

Add the same 4 parameters to `fetchForecastBatch` hourly params.

---

## Phase 2: Scoring Algorithms

### 2.1 `SeeingCalculator.swift`

Two-component seeing score, normalized to 0–2 scale (consistent with existing factors):

**Component A: Temperature stability** (50% of seeing score)

Rapid temperature changes between consecutive hours indicate atmospheric turbulence.

| ΔT (°C/hr) | Score |
|------------|-------|
| 0–1 | 0.0 (excellent) |
| 1–2 | 0.5 |
| 2–3 | 1.0 |
| 3–5 | 1.5 |
| 5+ | 2.0 (poor) |

First hour of the night has no prior data → use 0 (neutral).

**Component B: Jet stream** (50% of seeing score)

Strong winds at ~18km altitude shear the atmosphere and degrade seeing.

| Wind at 80hPa (km/h) | Score |
|----------------------|-------|
| 0–100 | 0.0 (excellent) |
| 100–200 | 0.5 |
| 200–300 | 1.0 |
| 300–400 | 1.5 |
| 400+ | 2.0 (poor) |

**Combined seeing score:**
```
seeing = 0.5 × tempStability + 0.5 × jetStream
```

### 2.2 `TransparencyCalculator.swift`

Extends the existing cloud cover score by accounting for clouds at all altitudes.

Current algorithm only uses total `cloudcover`. A night with 0% low clouds but 80% cirrus will report "clear" to the current algorithm — but those high clouds scatter light and reduce contrast.

**Weighted transparency score** (0–2 scale):
```
effectiveClouds = (lowCloud × 0.50 + midCloud × 0.30 + highCloud × 0.20)
```

This maps to the existing cloud score thresholds:
| effectiveClouds % | Score |
|-------------------|-------|
| 0–10% | 0.0 |
| 10–30% | 0.5 |
| 30–60% | 1.0 |
| 60–80% | 1.5 |
| 80–100% | 2.0 |

When mid/high cloud data is unavailable (nil), fall back to the existing `cloudCover`-only calculation.

---

## Phase 3: Integrate into Scoring

### 3.1 Update weights in `NightQualityAnalyzer`

**Current weights:**
| Factor | Weight |
|--------|--------|
| Cloud cover | 55% |
| Fog | 20% |
| Moon | 15% |
| Wind | 10% |

**Proposed weights:**
| Factor | Weight | Rationale |
|--------|--------|-----------|
| Transparency | 35% | Replaces raw cloud cover; more nuanced |
| Seeing | 20% | New — critical for telescope use |
| Fog | 15% | Slightly reduced (seeing covers some overlap) |
| Moon | 15% | Unchanged |
| Wind | 10% | Unchanged |
| Cloud cover (raw) | 5% | Fallback when transparency data unavailable |

### 3.2 Update `HourlyRating` struct

```swift
public struct HourlyRating {
    // existing fields...
    public let seeingScore: Double
    public let transparencyScore: Double
}
```

### 3.3 Update `Details` struct

```swift
public struct Details {
    // existing fields...
    public let seeingScoreAvg: Double
    public let transparencyScoreAvg: Double
}
```

### 3.4 Update `analyzeNight` method

For each hourly forecast:
1. Calculate `seeingScore` via `SeeingCalculator`
2. Calculate `transparencyScore` via `TransparencyCalculator`
3. Apply new weighted formula
4. Store per-hour scores in `HourlyRating`
5. Average into `Details`

---

## Phase 4: UI (Optional)

### 4.1 Hourly rating detail view

In `NightQualityCard.swift`, expand the hourly breakdown to show:
- Seeing score with icon (🔭 stable / ⚠️ moderate / ❌ turbulent)
- Transparency score with icon (💎 crystal / 🌫️ hazy / ☁️ obscured)

### 4.2 Summary card additions

Add to `NightQualityCard` summary section:
- "Seeing: Good" / "Seeing: Poor"
- "Transparency: Excellent" / "Transparency: Fair"

### 4.3 Color coding

Reuse the existing `Rating` enum thresholds (0.3/0.7/1.0) for per-factor labels:
- 0.0–0.3 → "Excellent" (green)
- 0.3–0.7 → "Good" (blue)
- 0.7–1.0 → "Fair" (orange)
- 1.0+ → "Poor" (red)

---

## Phase 5: Tests

### 5.1 `SeeingCalculatorTests`

- Stable temp + calm jet stream → excellent seeing
- Rapid temp change → poor seeing
- Strong jet stream → poor seeing
- Both factors bad → maximum score
- Missing data → neutral score

### 5.2 `TransparencyCalculatorTests`

- All clear at all levels → 0 score
- Only high clouds present → partial penalty
- Only low clouds present → heavier penalty
- All levels cloudy → maximum score
- Missing mid/high data → falls back to cloudCover

### 5.3 Update `NightQualityAnalyzerTests`

- Existing tests should still pass (fallback behavior)
- Add test with full data pipeline (seeing + transparency)
- Update `testDetailsAreCalculatedCorrectly` to include new fields

### 5.4 Update `WeatherServiceTests`

- Test parsing of new API fields
- Test with missing optional fields

---

## Files to Create

| File | Purpose |
|------|---------|
| `Core/Utilities/SeeingCalculator.swift` | Temperature stability + jet stream scoring |
| `Core/Utilities/TransparencyCalculator.swift` | Multi-altitude cloud transparency scoring |
| `Tests/.../SeeingCalculatorTests.swift` | Seeing algorithm tests |
| `Tests/.../TransparencyCalculatorTests.swift` | Transparency algorithm tests |

## Files to Modify

| File | Changes |
|------|---------|
| `Core/Models/ViewingConditions.swift` | Add `seeingScore`, `transparencyScore` to `HourlyRating` and `Details` |
| `Core/Services/WeatherService.swift` | Add 4 new API params + response fields + parsing |
| `Core/Utilities/NightQualityAnalyzer.swift` | New weights, call new calculators, update scoring formula |
| `Features/Dashboard/NightQualityCard.swift` | (Optional) Display seeing/transparency breakdown |
| `Tests/.../NightQualityAnalyzerTests.swift` | Update for new fields |
| `Tests/.../WeatherServiceTests.swift` | Test new API fields |

---

## Open Questions

1. **Threshold tuning** — The jet stream and temperature thresholds are starting estimates. They should be validated against real-world seeing reports (e.g., ClearDarkSky, Astrometry.net data) after launch.

2. **Pressure stability vs temperature stability** — We could also use pressure change rate (hPa/hr) as a seeing proxy. Pressure is more stable than temperature and may correlate better with seeing. Worth A/B testing.

3. **Weight calibration** — The proposed 35%/20%/15%/15%/10%/5% split is an educated guess. User feedback will determine if seeing should be weighted higher (astrophotographers care more) or lower (casual observers care less).

4. **Visibility as transparency proxy** — Open-Meteo's `visibility` field (already fetched) could supplement the transparency score. Low visibility (< 10km) often indicates haze/aerosols that reduce transparency even when cloud cover is 0%.

---

## Risks

| Risk | Mitigation |
|------|-----------|
| Open-Meteo free tier rate limits | Already handled via batch fetching; 4 extra params don't increase request count |
| Jet stream data unavailable at all locations | Fall back to temperature-only seeing score |
| Weights feel wrong to users | Make weights configurable in settings for future iteration |
| Increased API response size | Negligible — 4 extra numeric arrays per location |
