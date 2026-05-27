# Astro Viewing Conditions

An open-source iOS and watchOS app for astronomy enthusiasts to check nighttime viewing conditions for stargazing.

> New to this project? Check out [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) for architecture, implementation notes, and how to resume development.

---

## Features

- **Real-time Weather Data**: Cloud cover, humidity, wind, temperature, visibility, and hourly forecasts
- **Astronomical Information**: Sun and moon rise/set times, astronomical night timing, and moon phase
- **Night Quality Analysis**: Clear, scan-friendly assessment of cloud cover, moonlight, wind, fog, and observing quality
- **ISS Pass Predictions**: Track when the International Space Station will be visible
- **Fog Score**: Calculated from humidity, temperature, dew point, visibility, and low cloud cover
- **Location Management**: Use current location, save observing locations, search by city, enter coordinates, or pick from a map
- **Unit Preferences**: Toggle between Metric and Imperial units
- **iOS Widgets**: Home screen viewing-condition widgets backed by shared app data
- **watchOS App**: Apple Watch dashboard with current conditions, night quality, astronomical timing, and location selection
- **watchOS Complications**: Inline, circular, corner, and rectangular complication layouts
- **Cross-Device Sync**: iPhone and Apple Watch exchange selected locations, saved locations, unit preferences, and cached conditions

## Data Sources

- **Open-Meteo API**: Weather forecasts and geocoding (free, no API key required)
- **SunCalc Swift Package**: Astronomical calculations (sun/moon positions and phases)
- **Open Notify API**: ISS pass predictions (free, no API key required)

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

This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).

This license ensures that:
- The app remains open source
- Anyone distributing the app must share their modifications
- Commercial exploitation is prevented while keeping the project free for the community

See [LICENSE](LICENSE) for full details.

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
- ISS data from [Open Notify](http://open-notify.org/)

## Support

For bug reports or feature requests, please open an issue on GitHub.
