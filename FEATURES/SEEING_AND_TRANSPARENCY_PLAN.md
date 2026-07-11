# Seeing & Transparency Implementation Reference

> Implemented shared night-quality behavior. Product priority and future sequencing live in `FEATURES/FEATURE_ROADMAP.md`.

## Implementation

Open-Meteo hourly requests include `cloud_cover_mid`, `cloud_cover_high`, and `wind_speed_200hPa`. Optional arrays are parsed safely: absent arrays, short arrays, and missing indexed values remain `nil`. Existing cached Codable data remains compatible.

`HourlyForecast` stores:

```swift
public let midCloudCover: Int?
public let highCloudCover: Int?
public let windSpeed200hPa: Double?
```

`NightQualityAssessment.HourlyRating` stores `seeingScore: Double?` and `transparencyScore: Double?`; `Details` stores `seeingScoreAvg: Double?` and `transparencyScoreAvg: Double?`. Averages use only hourly samples where each score is available.

### Seeing

`SeeingCalculator` returns a 0.0–2.0 penalty, where lower is better.

| Temperature change (C/hour) | Penalty |
|---|---:|
| <= 1 | 0.0 |
| <= 2 | 0.5 |
| <= 3 | 1.0 |
| <= 5 | 1.5 |
| > 5 | 2.0 |

| 200 hPa wind (km/h) | Penalty |
|---|---:|
| <= 50 | 0.0 |
| <= 100 | 0.5 |
| <= 150 | 1.0 |
| <= 200 | 1.5 |
| > 200 | 2.0 |

When both components are available, their penalties are averaged equally. When only one is available, it is used directly. When neither is available, seeing is `nil`.

### Transparency

`TransparencyCalculator` returns a 0.0–2.0 penalty. Total cloud cover is the obstruction floor. When all cloud layers are available, their weighted value (low cloud × 50%, mid cloud × 30%, and high cloud × 20%) may increase, but never reduce, that obstruction. Otherwise it uses total cloud cover.

| Effective cloud cover | Penalty |
|---|---:|
| <= 10% | 0.0 |
| <= 30% | 0.5 |
| <= 60% | 1.0 |
| <= 80% | 1.5 |
| > 80% | 2.0 |

| Visibility | Penalty |
|---|---:|
| >= 20,000 m | 0.0 |
| >= 10,000 m | 0.5 |
| >= 5,000 m | 1.0 |
| >= 2,000 m | 1.5 |
| below 2,000 m | 2.0 |

When visibility exists, transparency combines cloud component × 75% plus visibility component × 25%, while never allowing good visibility to reduce the cloud-derived penalty. Poor visibility may worsen transparency. Without visibility, it uses the cloud component. This prevents overcast conditions from being described as clear.

### Night-quality scoring

`NightQualityAnalyzer` selects one formula per hour:

| Available factors | Formula |
|---|---|
| Seeing and transparency | transparency 40%, seeing 20%, fog 15%, moon 15%, surface wind 10% |
| Transparency only | transparency 50%, fog 20%, moon 20%, surface wind 10% |
| Seeing only | raw cloud cover 40%, seeing 20%, fog 15%, moon 15%, surface wind 10% |
| Neither | legacy cloud cover 55%, fog 20%, moon 15%, surface wind 10% |

Hours with total cloud cover of at least 80% apply a Poor-score floor. This prevents excellent seeing or other favorable factors from compensating for an obstructed sky; normal weighted formulas still apply below 80%.

## Fallback behavior

Missing new forecast inputs safely preserve prior scoring behavior. Best Targets receives the improved overall night-quality score through its existing path. Thresholds and weights remain candidates for field calibration.

## UI behavior

`NightQualityCard` shows Seeing and Transparency labels only when their averages are available. A poor average seeing score can add “Poor seeing may limit fine detail.” to the centralized night summary used by iPhone, Home Screen widgets, and Apple Watch.

## Validation

Focused unit coverage validates calculator thresholds, parsing of missing and short optional arrays, legacy and partial-data fallbacks, hourly values, score averages, and summary behavior.

## Future calibration

Field observations can guide later calibration of the thresholds and weights without changing the optional-data fallback contract.
