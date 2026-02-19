# Astro Viewing Conditions

An open-source iOS app for astronomy enthusiasts to check viewing conditions for stargazing.

> 📚 **New to this project?** Check out [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) for complete architecture, implementation plan, and how to resume development.

---

## Features

- **Real-time Weather Data**: Cloud cover, humidity, wind, temperature, and visibility
- **Astronomical Information**: Sun and moon rise/set times, moon phase with visual representation
- **ISS Pass Predictions**: Track when the International Space Station will be visible
- **Fog Score**: Calculated based on humidity, temperature, dew point, and visibility
- **Location Management**: Save favorite observing locations or use current location
- **Unit Preferences**: Toggle between Metric and Imperial units

## Data Sources

- **Open-Meteo API**: Weather forecasts (free, no API key required)
- **SunCalc Swift Package**: Astronomical calculations (sun/moon positions and phases)
- **Open Notify API**: ISS pass predictions (free, no API key required)

## Requirements

- iOS 18.0+
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
   open Package.swift
   ```

3. Build and run on your iOS device or simulator.

## Architecture

The app follows MVVM architecture with SwiftUI:

- **Features/**: UI organized by feature (Dashboard, Locations, Settings)
- **Core/**: Business logic, services, and data models
- **SwiftData**: Persistence for saved locations only (no caching of weather data)

## License

This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).

This license ensures that:
- The app remains open source
- Anyone distributing the app must share their modifications
- Commercial exploitation is prevented while keeping the project free for the community

See [LICENSE](LICENSE) for full details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

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
