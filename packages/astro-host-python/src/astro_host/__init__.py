"""Public typed API for Astro host composition."""

from astro_host.conditions import ConditionsService
from astro_host.errors import (
    InvalidLocationError,
    LocationConflictError,
    LocationNotFoundError,
    LocationStoreCorruptError,
    LocationStoreError,
    LocationStoreUnsupportedSchemaError,
)
from astro_host.locations import (
    FileLocationStore,
    LocationStore,
    MemoryLocationStore,
    canonicalize_location_id,
    default_locations_path,
    normalize_label,
)
from astro_host.models import (
    ConditionsRequest,
    ConditionsResult,
    Location,
    LocationState,
    SavedLocation,
    SavedLocationDraft,
)

__all__ = [
    "ConditionsRequest",
    "ConditionsResult",
    "ConditionsService",
    "FileLocationStore",
    "InvalidLocationError",
    "Location",
    "LocationConflictError",
    "LocationNotFoundError",
    "LocationState",
    "LocationStore",
    "LocationStoreCorruptError",
    "LocationStoreError",
    "LocationStoreUnsupportedSchemaError",
    "MemoryLocationStore",
    "SavedLocation",
    "SavedLocationDraft",
    "canonicalize_location_id",
    "default_locations_path",
    "normalize_label",
]
