"""Provider interfaces and the first Open-Meteo implementation."""

from astro_host.providers.http import HttpResponse, HttpTransport, UrllibHttpTransport
from astro_host.providers.open_meteo import OpenMeteoWeatherProvider
from astro_host.providers.weather import WeatherProvider

__all__ = [
    "HttpResponse",
    "HttpTransport",
    "OpenMeteoWeatherProvider",
    "UrllibHttpTransport",
    "WeatherProvider",
]
