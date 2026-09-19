"""Malformed LPATLAS1 artifacts must fail at load, not as lookup None."""

from __future__ import annotations

import struct

import pytest

from astro_engine.light_pollution import (
    HEADER_SIZE,
    TAG_COARSE,
    TAG_CONSTANT,
    TAG_DEFAULT_MASK,
    LightPollutionArtifact,
    LightPollutionArtifactError,
    validate_tree_structure,
)
from lp_support import assemble_artifact, contract_tiny_bin


def _load_tiny() -> bytearray:
    return bytearray(contract_tiny_bin().read_bytes())


def _patch_u16(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<H", data, offset, value)


def _patch_u32(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", data, offset, value)


def _patch_f64(data: bytearray, offset: int, value: float) -> None:
    struct.pack_into("<d", data, offset, value)


def _patch_f32(data: bytearray, offset: int, value: float) -> None:
    struct.pack_into("<f", data, offset, value)


def test_rejects_bad_magic() -> None:
    data = bytearray(b"BADMAGIC" + b"\x00" * 128)
    with pytest.raises(LightPollutionArtifactError, match="magic"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_unsupported_version() -> None:
    data = _load_tiny()
    _patch_u16(data, 8, 99)
    with pytest.raises(LightPollutionArtifactError, match="version"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_truncated_header() -> None:
    with pytest.raises(LightPollutionArtifactError, match="truncated"):
        LightPollutionArtifact.from_bytes(b"LPATLAS1" + b"\x00" * 10)


def test_rejects_root_cells_zero() -> None:
    data = _load_tiny()
    _patch_u16(data, 12, 0)
    with pytest.raises(LightPollutionArtifactError, match="root_cells"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_pixel_size_zero() -> None:
    data = _load_tiny()
    _patch_f64(data, 40, 0.0)
    with pytest.raises(LightPollutionArtifactError, match="pixel_size"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_nonfinite_pixel_size() -> None:
    data = _load_tiny()
    _patch_f64(data, 40, float("nan"))
    with pytest.raises(LightPollutionArtifactError, match="non-finite"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_nonfinite_quantization() -> None:
    data = _load_tiny()
    _patch_f32(data, 48, float("nan"))
    with pytest.raises(LightPollutionArtifactError, match="non-finite"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_qmax_le_qmin() -> None:
    data = _load_tiny()
    _patch_f32(data, 48, 20.0)
    _patch_f32(data, 52, 20.0)
    with pytest.raises(LightPollutionArtifactError, match="q_m_max"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_pristine_outside_quant_range() -> None:
    data = _load_tiny()
    _patch_f32(data, 56, 30.0)
    with pytest.raises(LightPollutionArtifactError, match="pristine"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_zero_width() -> None:
    data = _load_tiny()
    _patch_u32(data, 16, 0)
    with pytest.raises(LightPollutionArtifactError, match="width/height"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_inconsistent_n_root_cols() -> None:
    data = _load_tiny()
    _patch_u16(data, 62, 1)
    with pytest.raises(LightPollutionArtifactError, match="inconsistent"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_root_index_offset_inside_header() -> None:
    data = _load_tiny()
    _patch_u32(data, 68, 64)
    with pytest.raises(LightPollutionArtifactError, match="root_index_offset"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_root_data_offset_inside_index() -> None:
    data = _load_tiny()
    _patch_u32(data, 72, HEADER_SIZE)
    with pytest.raises(LightPollutionArtifactError, match="root_data_offset"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_declared_file_size_smaller_than_actual() -> None:
    data = _load_tiny()
    _patch_u32(data, 76, len(data) - 1)
    with pytest.raises(LightPollutionArtifactError, match="file_size"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_declared_file_size_larger_than_actual() -> None:
    data = _load_tiny()
    _patch_u32(data, 76, len(data) + 100)
    with pytest.raises(LightPollutionArtifactError, match="file_size"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_uint64_root_offset_greater_than_int64_max() -> None:
    data = _load_tiny()
    struct.pack_into("<Q", data, HEADER_SIZE, 2**64 - 1)
    struct.pack_into("<I", data, HEADER_SIZE + 8, 1)
    with pytest.raises(LightPollutionArtifactError, match="root blob"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_root_offset_plus_length_out_of_bounds() -> None:
    data = _load_tiny()
    off = struct.unpack_from("<Q", data, HEADER_SIZE)[0]
    struct.pack_into("<QI", data, HEADER_SIZE, off, len(data))
    with pytest.raises(LightPollutionArtifactError):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_zero_length_root_blob() -> None:
    data = _load_tiny()
    struct.pack_into("<I", data, HEADER_SIZE + 8, 0)
    with pytest.raises(LightPollutionArtifactError, match="zero-length"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_root_blob_pointing_into_header() -> None:
    data = _load_tiny()
    struct.pack_into("<QI", data, HEADER_SIZE, 0, 1)
    with pytest.raises(LightPollutionArtifactError, match="root blob"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_invalid_node_tag() -> None:
    data = _load_tiny()
    off = struct.unpack_from("<Q", data, HEADER_SIZE)[0]
    data[off] = 99
    with pytest.raises(LightPollutionArtifactError, match="bad tag"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_truncated_root_blob() -> None:
    data = _load_tiny()
    off = struct.unpack_from("<Q", data, HEADER_SIZE)[0]
    struct.pack_into("<I", data, HEADER_SIZE + 8, 1)
    data[off] = TAG_CONSTANT
    with pytest.raises(LightPollutionArtifactError):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_rejects_coarse_factor_zero() -> None:
    blob = bytes([TAG_COARSE, 0, 0])
    with pytest.raises(LightPollutionArtifactError, match="factor"):
        validate_tree_structure(blob, 768, 768)


def test_rejects_reserved_constant_quantization_code() -> None:
    with pytest.raises(LightPollutionArtifactError, match="quantization code"):
        validate_tree_structure(bytes([TAG_CONSTANT, 255]), 768, 768)


def test_rejects_reserved_coarse_quantization_code() -> None:
    # factor 255 produces a 4x4 grid for a 768-cell root.
    blob = bytes([TAG_COARSE, 255, 0] + [0] * 15 + [255])
    with pytest.raises(LightPollutionArtifactError, match="quantization code"):
        validate_tree_structure(blob, 768, 768)


def test_rejects_truncated_mask_payload() -> None:
    with pytest.raises(LightPollutionArtifactError):
        validate_tree_structure(bytes([TAG_DEFAULT_MASK, 0x00]), 768, 768)


def test_rejects_trailing_garbage() -> None:
    with pytest.raises(LightPollutionArtifactError, match="trailing garbage"):
        validate_tree_structure(bytes([0, 0]), 2, 2)  # TAG_ALL_NODATA + extra


def test_malformed_node_fails_initialization_not_lookup_none() -> None:
    good = LightPollutionArtifact.load(contract_tiny_bin())
    assert good.lookup(74.9125, -179.9125) is not None
    data = _load_tiny()
    off = struct.unpack_from("<Q", data, HEADER_SIZE)[0]
    data[off] = 99
    with pytest.raises(LightPollutionArtifactError, match="bad tag"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_unknown_tag_on_small_artifact() -> None:
    data = assemble_artifact([bytes([99])], root_cells=2, width=2, height=2)
    with pytest.raises(LightPollutionArtifactError, match="bad tag"):
        LightPollutionArtifact.from_bytes(data)
