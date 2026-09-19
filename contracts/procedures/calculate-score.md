# Public night integer (`night_conditions.score`)

Anchor: `BestSpotSearcher.calculateScore` / `NightQualityAssessment.calculatedScore`.
Bases live in `contracts/data/calibration/night-quality.json` `public_score`.

```
base = {excellent: 90, good: 70, fair: 45, poor: 20}[rating]
adjustment = 0
if hourly_scores is nonempty:
    avg = mean(hourly_scores)           # Double
    adjustment = Int((1.0 - avg) * 10)  # Swift Int(Double): trunc toward 0
public = clamp(base + adjustment, 0, 100)
```

`Int(Double)` is **not** banker's rounding and **not** half-away-from-zero.
Examples: `8.5 → 8`, `-1.5 → -1`.

Empty `hourly_scores` (including the empty-night assessment) uses the base only.
Poor + no hours → **20**, not 100.

Worked goldens:

- excellent + `[0,0,0,0]` → `90 + Int(10) = 100`
- poor + `[]` → `20`
- poor + `[2,2]` → avg 2, `20 + Int(-10) = 10`
- excellent + `[0.15]` → `90 + Int(8.5) = 98`
- fair + `[1.0]` → `45 + Int(0) = 45`
