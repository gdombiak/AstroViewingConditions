# Fog, seeing, and transparency

Numbers live in `contracts/data/calibration/fog.json`, `seeing.json`, and
`transparency.json`. Integer conversion is Swift `Int(Double)` (truncation
toward zero), then `max(…, 0)` before adding. `FogScore` finally clamps the
sum to `[0, 100]`.

Language-neutral factor IDs are **not** the Swift `FogFactor` English raw
values. Mapping:

| ID | Swift case |
|---|---|
| `high_humidity` | `.highHumidity` |
| `low_temp_dew_diff` | `.lowTempDewDiff` |
| `low_visibility` | `.lowVisibility` |
| `high_low_cloud` | `.highLowCloud` |
| `low_wind` | `.lowWind` |

Factors append in this order when their term is **strictly greater than 0**.

## `fog.score` (`FogCalculator.calculate`)

Inputs are one hourly forecast. Omitted optionals skip that term.

```
score = 0
factors = []

if humidity >= 80:
    humidity_score = Int((humidity - 80) / 20 * 40)
    humidity_score = max(humidity_score, 0)
    score += humidity_score
    if humidity_score > 0: factors.append(high_humidity)

if dew_point is present:
    spread = temperature - dew_point
    if spread < 2.0:
        spread_score = Int((2.0 - spread) / 2.0 * 30)
        spread_score = max(spread_score, 0)
        score += spread_score
        if spread_score > 0: factors.append(low_temp_dew_diff)

if visibility is present and visibility < 1000:
    visibility_score = Int((1000 - visibility) / 1000 * 20)
    visibility_score = max(visibility_score, 0)
    score += visibility_score
    if visibility_score > 0: factors.append(low_visibility)

if low_cloud_cover is present and low_cloud_cover >= 70:
    cloud_score = Int((low_cloud_cover - 70) / 30 * 10)
    cloud_score = max(cloud_score, 0)
    score += cloud_score
    if cloud_score > 0: factors.append(high_low_cloud)

if wind_speed < 3.0:
    wind_score = Int((3.0 - wind_speed) / 3.0 * 15)
    wind_score = max(wind_score, 0)
    score += wind_score
    if wind_score > 0: factors.append(low_wind)

return { score: clamp(score, 0, 100), factors }
```

Worked values used as goldens:

- humidity 80, otherwise inert → score 0 (term is 0, factor omitted)
- humidity 95 → `Int(15/20*40) = 30`
- humidity 96 → `Int(16/20*40) = 32`
- dew spread 0.5 °C → `Int(1.5/2*30) = 22`
- visibility 500 m → `Int(500/1000*20) = 10`
- visibility 1000 m → term skipped (`< 1000` is false)
- low cloud 100 → `Int(30/30*10) = 10`
- wind 0 → 15; wind 3.0 → term skipped (`< 3` is false)
- all maxima: 40+30+20+10+15 = 115 → clamp 100

## `seeing.penalty` (`SeeingCalculator.penalty`)

```
temp = previous_temperature.map { table(abs(current - previous)) }
wind = wind_speed_200hpa.map { table(wind) }
components = compact([temp, wind])
if components empty: return null
return clamp(mean(components), 0, 2)
```

Temperature ΔT (°C), first `delta ≤ max`: `(1,0), (2,0.5), (3,1), (5,1.5), else 2`.

200 hPa wind: `(50,0), (100,0.5), (150,1), (200,1.5), else 2`.

Both missing → JSON `null`. One present → that component only.

## `transparency.penalty` (`TransparencyCalculator.penalty`)

Production never returns `null`; missing layers fall back to total cloud.

```
total = clamp(total_cloud_cover, 0, 100) as Double
if low, mid, and high are all present:
    layered = clamp(low,0,100)*0.50 + clamp(mid,0,100)*0.30 + clamp(high,0,100)*0.20
    effective = max(total, layered)
else:
    effective = total
cloud = table_cloud(effective)
if visibility is omitted: return cloud
visibility_c = table_vis(max(visibility, 0))
combined = cloud * 0.75 + visibility_c * 0.25
return clamp(max(cloud, combined), 0, 2)
```

Cloud table (first `cover ≤ max`): `(10,0), (30,0.5), (60,1), (80,1.5), else 2`.

Visibility table (first `vis ≥ min`): `(20000,0), (10000,0.5), (5000,1), (2000,1.5), else 2`.

Haze example: total 0, vis 1000 m, no layers needed for vis-only fallback:
`cloud=0`, vis component 2, combined `0.5`, result `max(0, 0.5)=0.5`.
