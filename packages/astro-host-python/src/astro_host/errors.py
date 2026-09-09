"""Typed exceptional failures at the host boundary."""

from __future__ import annotations

from typing import Mapping

from astro_host.models import ProviderFailure, ProviderFailureKind, TimeZoneSource


class InvalidRequestError(ValueError):
    """Caller input cannot identify a valid conditions request."""


class HttpTransportError(Exception):
    def __init__(self, kind: ProviderFailureKind, message: str) -> None:
        super().__init__(message)
        if kind not in {ProviderFailureKind.TIMEOUT, ProviderFailureKind.NETWORK}:
            raise ValueError("HTTP transport errors must be timeout or network failures")
        self.kind = kind


class WeatherProviderError(Exception):
    def __init__(self, failure: ProviderFailure) -> None:
        super().__init__(failure.message)
        self.failure = failure


class TimeZoneCatalogError(RuntimeError):
    """The engine's shared timezone catalogue could not be queried."""

    def __init__(
        self, source: TimeZoneSource, candidate: str, cause: Exception
    ) -> None:
        super().__init__(f"shared engine timezone catalogue failed: {cause}")
        self.source = source
        self.candidate = candidate
        self.cause = cause


class EngineCallError(Exception):
    def __init__(
        self,
        capability: str,
        code: str,
        message: str,
        details: Mapping[str, object] | None = None,
    ) -> None:
        super().__init__(message)
        self.capability = capability
        self.code = code
        self.message = message
        self.details = dict(details or {})
