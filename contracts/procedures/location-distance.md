# Location distance

Capability: `location.distance`

Input `injected` is exactly `{from, to}`. Each endpoint is exactly
`{latitude, longitude}` with finite JSON numbers (not Booleans), latitude in
`[-90, 90]` and longitude in `[-180, 180]`. Unknown or missing keys and invalid
coordinates fail with `error.code = validation` and message
`invalid location.distance input`.

Convert degrees to radians. Let `a = sin²((lat2-lat1)/2) +
cos(lat1) cos(lat2) sin²((lon2-lon1)/2)`, clamp `a` to `[0,1]`, and let
`angle = 2 atan2(sqrt(a), sqrt(1-a))`. Return
`{distance_miles: angle * 6,371,000 / 1,609.344}`. This is the shortest
great-circle arc on the same spherical Earth used by `location.grid`.
It is not road distance, travel distance, or a geographic eligibility test.
