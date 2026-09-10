from __future__ import annotations

import uuid

import pytest

from astro_host.errors import (
    InvalidLocationError,
    LocationConflictError,
    LocationNotFoundError,
    LocationStoreCorruptError,
    LocationStoreError,
    LocationStoreUnsupportedSchemaError,
)
from astro_host.locations import canonicalize_location_id, normalize_label
from astro_host.models import Location, SavedLocation


def test_to_conditions_location_maps_time_zone_to_hint() -> None:
    saved = SavedLocation(
        id="3fa85f64-5717-4562-b3fc-2c963f66afa6",
        name="Home",
        latitude=34.05,
        longitude=-118.24,
        time_zone="America/Los_Angeles",
        aliases=("house",),
        elevation_m=123.5,
    )
    mapped = saved.to_conditions_location()
    assert mapped == Location(
        latitude=34.05,
        longitude=-118.24,
        name="Home",
        location_id=saved.id,
        elevation_m=123.5,
        time_zone_hint="America/Los_Angeles",
    )


def test_normalize_label_strips_nfc_and_casefolds() -> None:
    assert normalize_label(" Home ") == "home"
    assert normalize_label("é") == normalize_label("e\u0301")
    assert normalize_label("Straße") == normalize_label("STRASSE")


def test_canonicalize_location_id_accepts_uppercase() -> None:
    upper = "3FA85F64-5717-4562-B3FC-2C963F66AFA6"
    assert canonicalize_location_id(upper) == str(uuid.UUID(upper))
    with pytest.raises(InvalidLocationError):
        canonicalize_location_id("Home")


def test_error_codes() -> None:
    assert InvalidLocationError("x").code == "invalid_request"
    assert LocationConflictError("x", normalized="home").code == "conflict"
    assert LocationNotFoundError("x", query="q").code == "not_found"
    assert LocationStoreCorruptError("x").code == "corrupt"
    assert LocationStoreUnsupportedSchemaError("x", schema_version=2).code == (
        "unsupported_schema"
    )
    assert LocationStoreError("x").code == "host_failure"
    from astro_host.errors import InvalidRequestError
    assert not issubclass(InvalidLocationError, InvalidRequestError)
