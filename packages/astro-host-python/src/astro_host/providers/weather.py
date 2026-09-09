"""Small weather-provider boundary for ``agent.conditions``."""

from __future__ import annotations

from typing import Protocol

from astro_host.models import WeatherProviderResponse, WeatherQuery


class WeatherProvider(Protocol):
    name: str

    async def fetch(self, query: WeatherQuery) -> WeatherProviderResponse: ...
