# Astro Viewing Conditions - Observer Guide

Astro Viewing Conditions helps you answer three practical questions: how good will the sky be, when is the best observing window, and what is worth looking at from the selected location.

## Choose a Location and Night

Select your current position or one of your saved observing sites from the dashboard. The Today, Tomorrow, and Day After tabs use the selected site's local date and time zone, which is especially important when planning for a distant site.

In Locations you can:

- Add a site by searching for a city, entering coordinates, or choosing a point on the map.
- Swipe a saved site and choose **Rename**.
- Tap **Edit**, then drag sites into your preferred order.

The saved order is used by the dashboard location picker and is shared with a paired Apple Watch.

Saved-location rows also show a modeled light-pollution category and zenith sky brightness in mag/arcsec² when available. Higher values mean darker modeled skies. These atlas estimates are not Bortle classes and can differ from local lights, obstructions, smoke, or recent development. Opening the Locations screen resolves saved-site estimates from their stored coordinates; it does not request Current Location.

## Read the Conditions

**Night Conditions** combines cloud cover, transparency, seeing, moonlight, fog risk, wind, and the useful nighttime period. **Observing Quality** starts with that score and accounts for modeled light pollution. If valid modeled brightness is unavailable, the displayed score falls back exactly to Night Conditions. Moon effects are already part of Night Conditions and are not applied again.

Check the hourly forecast as well as the overall score: a mediocre night can still contain a short clear window.

The Sun & Moon card shows sunset, sunrise, astronomical darkness, moonrise or moonset, the named lunar phase, and the Moon's illuminated percentage. Bright moonlight can reduce contrast in nebulae and galaxies even when the weather is clear.

All forecast dates and times are displayed for the selected observing location.

## Use Best Targets

Best Targets ranks objects for the selected site and night. Depending on what is above the horizon, recommendations can include the Moon, Venus, Mars, Jupiter, Saturn, double stars, open and globular clusters, planetary and diffuse nebulae, and galaxies.

Each recommendation includes:

- A **Target score** out of 100. This is a relative planning score for that object under the predicted conditions—not a guarantee that it will be visible. It is separate from environmental Observing Quality and equipment suitability; Target score intentionally does not use the light-pollution atlas or equipment fit.
- A best observing window, shown in the selected location's local time.
- A compass direction and approximate maximum altitude. An altitude of 0° is the horizon and 90° is directly overhead.
- A short explanation of important factors such as darkness, altitude, clouds, haze, or bright moonlight.

The dashboard shows the leading recommendations. Tap **View All** for the complete list, or tap a target to see why it was recommended, finding tips, suggested equipment, and observing notes. Tap the reference image to inspect it full screen. Images are examples for identification and may not resemble the visual appearance through your equipment.

### Equipment Suitability

Manage **My Equipment**—the inventory of equipment you own—in Settings. Choose **Observation Equipment** from the Dashboard Best Targets section, or use the same control in **View All**. It applies to the selected observing date and starts with Naked Eye plus every saved item; choose **All My Equipment**, **Naked Eye Only**, or a custom multi-selection without changing your inventory.

Target summaries and details may show **Equipment Suitability** as **Excellent**, **Good**, **Challenging**, or **Poor**. Visual and electronically assisted (Smart / EAA) guidance are intentionally described separately; when personalized guidance is unavailable—or the selected equipment is a Poor match—details also show generic **Best equipment** guidance. Suitability guidance is practical planning help, not a visibility promise: weather, sky darkness, Moon conditions, altitude, obstructions, eyesight, and experience still matter.

In Target Details, **Finding tips** cover locating and observing technique, while **Observing notes** describe expected appearance and notable features.

**Target Suitability for Your Equipment** controls the lowest equipment suitability level included. **Good**, for example, includes both Good and Excellent targets. **Any** includes all normal Best Targets regardless of equipment suitability. This setting affects which targets are shown in the Dashboard and View All, but does not change Best Targets conditions scores or the relative conditions-based ordering of targets that remain.

### Add or Edit Equipment

New equipment starts as a **Visual Telescope** with **mm** selected for aperture. The name and aperture examples change with the selected type: Visual Telescope (`e.g. Virtuoso GTi 150P`, `150`), Binoculars (`e.g. Nikon 10×50`, `50`), or Smart/EAA Telescope (`e.g. Seestar S30 Pro`, `30`). The aperture control offers only **mm** and **inches**, with type-specific guidance beneath the field. Changing type keeps the name and aperture text you entered. When editing, saved aperture units are preserved; older entries without a saved unit use millimeters.

### Difficulty Labels

- **Easy**: Generally conspicuous or forgiving for newer observers.
- **Standard**: May need binoculars or a telescope, reasonable sky conditions, and some familiarity with finding objects.
- **Challenge**: May be faint, have low surface brightness, require dark skies or more aperture, or benefit from techniques such as averted vision.

When sky conditions are poor, the app may still show targets for planning. Treat these as the best available choices, not a prediction of a successful observation.

## Find a Better Nearby Area

Best Nearby compares nearby forecast grid points. When modeled brightness is valid for every scorable candidate, ranking, displayed score, category, and comparisons all use Observing Quality. If any candidate lacks valid brightness, the entire result set uses Night Conditions instead; the app never mixes the two score modes in one search. Suitability checks cannot verify roads, parking, ownership, legal access, safety, or local horizon obstructions, so confirm a destination before traveling.

## Use Home Screen Widgets

Widgets use the location selected in Astro Viewing Conditions and the app's cached forecast data. Dates and times use that location's time zone. Refresh the app after changing locations or when a widget asks for an update; the widgets re-evaluate their timelines about hourly and show a clear unavailable message when no selected location, matching forecast, or fresh cached data is available. They retain the normal system appearance when the app uses Field Mode.

- **Night Conditions** is the adaptive small and medium widget; its medium layout is headed **Tonight at a Glance**. Its headline uses Observing Quality when validated companion brightness is available and otherwise falls back exactly to Night Conditions. It also shows the verdict, early-to-late Night Conditions trend, best observing window or a no-night/limiting message, and—when space permits—clouds, seeing, and transparency.
- **Tonight’s Targets** is a medium widget. It shows up to three recommended targets, with score, best time, and, where space permits, category plus compass direction and altitude in degrees. A night with no recommendations says so.
- **Three-Night Outlook** is a medium widget for Tonight, Tomorrow, and Day After. It compares each night's Observing Quality when validated brightness is available, otherwise its exact Night Conditions score, plus verdict and best window or status; it marks the highest available score as **Best**.

The widgets are informational. Tapping one opens Astro Conditions, but it does not navigate to a specific screen or provide controls directly in the widget.

The Apple Watch dashboard and score-bearing complications follow the same Observing Quality rule for saved locations and explicitly requested Current Location updates. The atlas itself is not installed on the watch; invalid, missing, mismatched, or incompatible transferred data falls back exactly to Night Conditions.

## Follow an ISS Pass

ISS predictions require an N2YO API key entered in Settings. When available, each pass shows:

- The rise-to-set time range and date.
- The peak compass direction, elevation, and time.
- The starting and ending directions and elevations.
- Whether a pass is already active.

Choose an open location with a clear horizon in the indicated directions. A message in the card distinguishes no predicted passes from service problems such as a rejected key, request limit, or timeout.

## Plan for Real-World Conditions

Forecasts and calculated positions are planning aids. Local clouds, terrain, trees, buildings, light pollution, smoke, and atmospheric steadiness can differ from the forecast. Check the horizon and weather before traveling, and never look at the Sun without certified solar-observing equipment.
