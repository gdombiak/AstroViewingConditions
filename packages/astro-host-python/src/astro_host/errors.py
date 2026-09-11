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


class LocationStoreError(Exception):
    """Base for location-store failures. ``code`` maps to the CLI error.code."""

    def __init__(self, message: str, *, code: str = "host_failure") -> None:
        super().__init__(message)
        self.code = code


class LocationStoreCorruptError(LocationStoreError):
    def __init__(self, message: str) -> None:
        super().__init__(message, code="corrupt")


class LocationStoreUnsupportedSchemaError(LocationStoreError):
    def __init__(self, message: str, *, schema_version: object) -> None:
        super().__init__(message, code="unsupported_schema")
        self.schema_version = schema_version


class LocationConflictError(LocationStoreError):
    def __init__(self, message: str, *, normalized: str) -> None:
        super().__init__(message, code="conflict")
        self.normalized = normalized


class LocationNotFoundError(LocationStoreError):
    def __init__(self, message: str, *, query: str) -> None:
        super().__init__(message, code="not_found")
        self.query = query


class InvalidLocationError(LocationStoreError):
    def __init__(self, message: str) -> None:
        super().__init__(message, code="invalid_request")


class NoSelectedLocationError(LocationStoreError):
    def __init__(self, message: str = "no selected location") -> None:
        super().__init__(message, code="no_selected_location")


class InvalidPlaceCandidateError(LocationStoreError):
    def __init__(self, message: str) -> None:
        super().__init__(message, code="invalid_request")


class PlaceProviderError(Exception):
    def __init__(self, failure: ProviderFailure) -> None:
        super().__init__(failure.message)
        self.failure = failure
        self.code = "provider_failure"


class InvalidProviderTimezoneError(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.code = "invalid_provider_timezone"


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
