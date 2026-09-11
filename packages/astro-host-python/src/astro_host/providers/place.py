"""Host-owned place-resolution acquisition. No persistence."""

from __future__ import annotations

from typing import Protocol

from astro_host.models import PlaceProviderResult


class PlaceResolver(Protocol):
    name: str

    async def resolve(self, query: str) -> PlaceProviderResult: ...
