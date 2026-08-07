# Astro Viewing Conditions

An open-source iOS and watchOS app for astronomy enthusiasts to check nighttime viewing conditions for stargazing.

> New to this project? Check out [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) for architecture, implementation notes, and how to resume development.
>
> Planning the next release? See the canonical [Product Roadmap](FEATURES/FEATURE_ROADMAP.md).
>
> Using the app at the telescope? See the [Observer Guide](OBSERVER_GUIDE.md) for help interpreting conditions, Best Targets, observing windows, and ISS passes.

---

## Features

- **Real-time Weather Data**: Cloud cover including mid/high layers, humidity, wind including upper-atmosphere wind for observing estimates, temperature, visibility, and hourly forecasts
- **Astronomical Information**: Sun and moon rise/set times, astronomical night timing, and moon phase
- **Night Conditions and Observing Quality**: Clear, scan-friendly Night Conditions from transparency, seeing, cloud cover, moonlight, fog, wind, and nighttime windows, plus environmental Observing Quality adjusted by offline modeled light pollution when valid atlas data is available
- **Best Targets**: Ranked recommendations for the Moon, visible planets, double stars, star clusters, nebulae, and galaxies based on the selected location and night, target altitude, darkness (or a useful Venus twilight window), weather, moonlight, and observing difficulty. Its Target score remains separate from environmental Observing Quality and equipment suitability
- **Equipment Personalization**: Save binoculars, visual telescopes, and Smart / EAA telescopes, then select the equipment available for a session and see Excellent, Good, Challenging, or Poor target-fit guidance without changing conditions scores
- **Best Nearby Area**: Ranks nearby grid points by Observing Quality when every candidate has valid modeled brightness, otherwise falls back coherently to Night Conditions for the whole search; it also checks candidate suitability and shows a clean ranked map
- **Practical Observing Guidance**: See each target's best observing window, compass direction, altitude, suitability score, curated finding tips, equipment guidance, and observing notes
- **Observing Difficulty**: Easy, Standard, and Challenge labels help set expectations; Challenge targets may require darker skies, more aperture, or careful observing techniques
- **Offline Target Images**: Reference images with source and license credits are bundled for many targets and require no network connection
- **ISS Pass Predictions**: With an optional N2YO API key, see rise and set times, peak time and elevation, compass directions, and passes already in progress
- **Fog Score**: Calculated from humidity, temperature, dew point, visibility, and low cloud cover
- **Location Management**: Use current location, save and rename observing locations, arrange them in your preferred order, search by city, enter coordinates, or pick from a map; saved locations show modeled light-pollution category and zenith sky brightness when available
- **Unit Preferences**: Toggle between Metric and Imperial units
- **Field Mode**: Persistent dim-red iOS appearance for telescope use, available from Settings and the Dashboard; widgets and watchOS retain their normal presentation
- **Dynamic Type**: Layouts adapt at larger standard iOS text sizes, including the largest standard Text Size setting
- **iOS Widgets**: Adaptive small and medium **Tonight at a Glance** conditions views, plus medium **Tonight’s Targets** and **Three-Night Outlook** Home Screen widgets backed by shared app data
- **watchOS App**: Apple Watch dashboard with current conditions, night quality, astronomical timing, and location selection
- **watchOS Complications**: Inline, circular, corner, and rectangular complication layouts
- **Cross-Device Sync**: iPhone and Apple Watch exchange selected locations, saved locations, unit preferences, and cached conditions

## Data Sources

- **Open-Meteo API**: Weather forecasts and geocoding (free, no API key required)
- **SunCalc Swift Package**: Astronomical calculations (sun/moon positions and phases)
- **N2YO API**: Optional ISS pass predictions (free API key required)
- **David Lorenz Light Pollution Atlas**: Offline modeled zenith sky brightness from the 2025 `zenith_brightness_v22_2025` product; see [Light Pollution tooling and attribution](Tools/LightPollution/README.md)

Best Targets uses a curated local target catalog and verified local image assets with source and license metadata. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled-image attribution.

Modeled light-pollution values are not Bortle classes. The LPATLAS1 binary is bundled only in the main iOS app; widgets and Apple Watch surfaces consume validated shared or transferred state and fall back safely to Night Conditions.

Best Nearby Area uses weather forecasts plus Apple reverse geocoding to exclude known water, unsuitable, and unchecked candidates. Candidates whose suitability cannot be conclusively verified may still be recommended with a clear warning, so observers must confirm access and conditions before traveling. It does not validate roads, parking, land ownership, legal access, personal safety, or local horizon obstructions.

Forecast dates and times are shown in the selected observing location's local time zone. Saved-location names and ordering are also shared with the paired Apple Watch.

## Requirements

- iOS 18.0+
- watchOS 11.0+
- Xcode 16.0+
- Swift 6.0+

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/gdombiak/AstroViewingConditions.git
   cd AstroViewingConditions
   ```

2. Open in Xcode:
   ```bash
   open AstroViewingConditions.xcodeproj
   ```

   Or use the provided script:
   ```bash
   ./open_in_xcode.sh
   ```

3. Select the `AstroViewingConditions` scheme for iOS or `AstroViewingConditionsWatch` for watchOS.

4. Build and run on a simulator or device.

## Architecture

The app follows a SwiftUI + MVVM architecture with shared domain code:

- **Sources/AstroViewingConditions/**: iOS app UI, dashboard, locations, settings, and iPhone-side WatchConnectivity
- **Sources/SharedCode/**: Cross-platform models, services, storage, caching, formatters, unit conversion, and night-quality logic
- **Sources/Widgets/**: iOS home screen widgets
- **Sources/WatchApp/**: watchOS app UI and watch-side managers
- **Sources/WatchWidget/**: watchOS complications
- **Tests/AstroViewingConditionsTests/**: Unit tests for core behavior
- **project.yml**: XcodeGen project configuration used to define app, widget, watch, shared framework, and test targets

Persistent user data is stored with SwiftData and shared storage helpers. App group storage, cache storage, iCloud key-value storage, and WatchConnectivity support widget timelines and iPhone/Apple Watch sync.

## License

Astro Conditions is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).

Modified versions distributed to others must comply with the AGPL and make the corresponding source code available. Modified versions made available for users to interact with over a network must also provide source access as required by the license.

See [LICENSE](LICENSE) for the complete terms.

## Contributing

Contributions are welcome. Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments

- Weather data provided by [Open-Meteo](https://open-meteo.com/)
- Astronomical calculations powered by [SunCalc](https://github.com/nikolajjensen/SunCalc)
- Optional ISS pass data from [N2YO](https://www.n2yo.com/)
- Modeled zenith sky brightness from [David Lorenz’s Light Pollution Atlas](https://djlorenz.github.io/astronomy/lp/), used with direct permission; redistribution remains subject to the permission applicable to the atlas release

## Support

For bug reports or feature requests, please open an issue on GitHub.
