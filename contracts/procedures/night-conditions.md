# Night conditions (`night_conditions.analyze`)

Anchor: `NightQualityAnalyzer.analyzeNight` after clipping. 1.0 **does not**
call `NightForecastFilter` or SunCalc. Moon, window, clock, and time zone are
injected. Numbers: `contracts/data/calibration/night-quality.json`.

DTO omits `id`, English `summary`, `best_window`, `icon`, `label`, `Color`.
`public_score` is `night_conditions.score` applied to the same assessment.

## Inputs

| Field | Rule |
|---|---|
| `clock` | Instant (host identity; clipping uses `night_window`) |
| `time_zone` | IANA, required |
| `injected.night_window.start` / `.end` | Half-open `[start, end)` |
| `injected.forecasts` | Hourly rows; engine clips |
| `injected.moon_series` | **One object per included forecast hour**, `time` exact ISO-8601 `Z` |

Missing moon timestamp → `ok: false`, `error.code: validation`. Extra moon
samples ignored. Do not interpolate; do not substitute altitude 0.

## Clip then score

```
included = sort(forecasts where start ≤ time < end)
if included is empty:
    return empty-night assessment
for each hour in included:
    moon = moon_series[hour.time]   # required
    score that hour
```

`night_start` / `night_end` for a **non-empty** night are first/last included
hour times, **not** the filter-window instants.

## Empty night

Adapted from `createNoNighttimeDataAssessment` with injected bounds:

| Field | Value |
|---|---|
| `rating` | `poor` |
| `hourly_ratings` | `[]` |
| `trend` | `stable` |
| `first_half_score` / `second_half_score` | JSON `null` (not `0`) |
| `public_score` | `20` |
| `night_start` / `night_end` | injected window start / end |
| `details.cloud_cover_score` | `0` |
| `details.fog_score_avg` | `0` |
| `details.moon_illumination_avg` | `0` (no hours; no dummy `MoonInfo`) |
| `details.wind_speed_avg` | `0` |
| `details.seeing_score_avg` / `transparency_score_avg` | omitted |
| `best_window` | omitted |

Production Swift empty nights still copy `moonInfo.illumination` and sun-event
bounds. 1.0 injected empty nights use the table above.

## Hourly score

```
fog = fog.score(hour)
cloud = first cloud_cover_score_table row with cloud_cover ≤ max
seeing = seeing.penalty(temp, previous_temp or null, wind_200hpa or null)
         previous_temp is the previous *included* hour, else null
has_transparency = low, mid, and high cloud are all present
transparency = transparency.penalty(...) if has_transparency else absent
moon = 0 if altitude ≤ 0 else illumination_bucket * (0.5 + 0.5 * clamp(alt/90, 0, 1))
wind = wind table (first wind_speed ≤ max)
fog_penalty = fog.score / 50.0

switch (transparency, seeing):
  both:     T*0.40 + S*0.20 + fog*0.15 + moon*0.15 + wind*0.10
  T only:   T*0.50 + fog*0.20 + moon*0.20 + wind*0.10
  S only:   cloud*0.40 + S*0.20 + fog*0.15 + moon*0.15 + wind*0.10
  neither:  cloud*0.55 + fog*0.20 + moon*0.15 + wind*0.10

if cloud_cover ≥ 80: hourly = max(weighted, fair_max=1.0)
else hourly = weighted
```

Seeing omitted from the hourly DTO when the calculator returned `null`.
Transparency omitted unless all three layers were present (`has_transparency`),
even though `transparency.penalty` itself never returns null.

`details.cloud_cover_score` is the **mean of hourly cloud-cover percents**
(0…100), not the 0…2 cloud table. That matches production `avgCloudCover`.

After averaging hours: if mean cloud ≥ 80, `avgScore = max(rawAverage, 1.0)`.

Rating: `score < 0.3` excellent; `< 0.7` good; `< 1.0` fair; else poor.

**Averages:** `fog_score_avg` is `Double` of **integer** mean of integer fog
scores. `moon_illumination_avg` is integer division of integer illuminations.
`seeing_score_avg` / `transparency_score_avg` omitted when that compact map is
empty; otherwise mean of defined values.

## Trend

Higher hourly score is worse.

```
if count < 4: return (stable, first_half=0, second_half=0)   # zeros, not null
mid = count / 2   # integer division
first = mean(scores[0 ..< mid])
second = mean(scores[mid ..< count])
diff = second - first
if diff > 0.3: degrading
else if diff < -0.3: improving
else: stable
```

## four-clear-hours

See fixture `four-clear-hours-v1`. Four hours 21:00Z–00:00Z, cloud 0, humidity 0,
wind 3.0, temperature 15, moon altitude −10, illumination 0. No dew / vis /
layers / 200 hPa.

Wind 3.0: fog does not take the `< 3` term; night wind penalty is 0 (`…3 → 0`).

Hour 21:00: no previous temperature, no 200 hPa → seeing null → **neither**.
Hours 22:00–00:00: ΔT = 0 → seeing 0 → **seeing only**. All hourly scores 0.

`avgScore` 0 → excellent. Four hours, halves 0/0, `|diff|<0.3` → stable.
`public_score = 90 + Int((1.0-0)*10) = 100`.
`night_start`/`night_end` are 21:00Z / 00:00Z, not the 20:00Z–05:00Z window.
`details.seeing_score_avg` is the mean of the three defined seeing values (= 0).
First hourly object omits `seeing_score`. All omit `transparency_score`.
