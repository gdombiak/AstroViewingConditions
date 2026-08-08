"""Tests for LPATLAS1 binary format encode/decode/lookup and safety validation."""

from __future__ import annotations

import math
import struct

import pytest

from light_pollution.binary_format import (
    HEADER_SIZE,
    MAGIC,
    PROD_U8,
    ROOT_INDEX_ENTRY_SIZE,
    TAG_ALL_NODATA,
    TAG_COARSE,
    TAG_CONSTANT,
    LightPollutionArtifact,
    assemble_artifact,
    dequantize_code,
    encode_tree_node,
    lon_lat_to_cell,
    lookup_in_blob,
    normalize_longitude,
    pack_header,
    parse_header,
    quantize_code,
    validate_tree_structure,
)
from light_pollution.hierarchical import ROOT_CELLS, TreeNode, n_root_cols, n_root_rows


def _all_nodata_blobs():
    return [bytes([TAG_ALL_NODATA]) for _ in range(n_root_cols() * n_root_rows())]


def _valid_artifact_bytes() -> bytes:
    return assemble_artifact(_all_nodata_blobs())


def _patch_u16(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<H", data, offset, value)


def _patch_u32(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", data, offset, value)


def _patch_f64(data: bytearray, offset: int, value: float) -> None:
    struct.pack_into("<d", data, offset, value)


def _patch_f32(data: bytearray, offset: int, value: float) -> None:
    struct.pack_into("<f", data, offset, value)


def test_quantize_roundtrip_anchors():
    for m in (13.01, 18.5, 21.3, 22.0, 22.5):
        c = quantize_code(m)
        back = dequantize_code(c)
        assert abs(back - m) <= PROD_U8.theoretical_max_error() + 1e-6


def test_normalize_longitude():
    assert normalize_longitude(0) == 0
    assert abs(normalize_longitude(180) - (-180)) < 1e-12 or normalize_longitude(180) == -180
    assert abs(normalize_longitude(190) - (-170)) < 1e-9


def test_lon_lat_to_cell_home():
    cell = lon_lat_to_cell(-122.75, 45.45)
    assert cell is not None
    col, row = cell
    assert col == int(math.floor((-122.75 - (-180)) / (1 / 120)))
    assert row == int(math.floor((75 - 45.45) / (1 / 120)))


def test_header_roundtrip():
    data = _valid_artifact_bytes()
    h = parse_header(data)
    assert h.version == 1
    assert h.width == 43200
    assert data[:8] == MAGIC
    art = LightPollutionArtifact.from_bytes(data)
    assert art.lookup(0.0, 0.0) is None  # all nodata


def test_constant_root_lookup():
    val = 18.5
    node = TreeNode(type="constant", r0=0, c0=0, h=ROOT_CELLS, w=ROOT_CELLS, value=val)
    blob = encode_tree_node(node)
    assert blob[0] == TAG_CONSTANT
    blobs = _all_nodata_blobs()
    blobs[0] = blob
    data = assemble_artifact(blobs)
    art = LightPollutionArtifact.from_bytes(data)
    lon = -180 + 0.5 / 120
    lat = 75 - 0.5 / 120
    v = art.lookup(lat, lon)
    assert v is not None
    assert abs(v - dequantize_code(quantize_code(val))) < 1e-6


def test_malformed_magic():
    data = bytearray(_valid_artifact_bytes())
    data[0:8] = b"BADMAGIC"
    with pytest.raises(ValueError, match="magic"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_truncated_header():
    with pytest.raises(ValueError):
        parse_header(b"LPATLAS1" + b"\x00" * 10)


def test_nonfinite_lookup():
    art = LightPollutionArtifact.from_bytes(_valid_artifact_bytes())
    assert art.lookup(float("nan"), 0.0) is None
    assert art.lookup(0.0, float("inf")) is None


def test_children_tree_lookup():
    kids = []
    values = [18.0, 19.0, 20.0, 21.0]
    for v in values:
        kids.append(TreeNode(type="constant", r0=0, c0=0, h=384, w=384, value=v))
    root = TreeNode(type="children", r0=0, c0=0, h=768, w=768, children=kids)
    blob = encode_tree_node(root)
    # Full artifact header for quant params
    blobs = _all_nodata_blobs()
    blobs[0] = blob
    data = assemble_artifact(blobs)
    h = parse_header(data)
    v = lookup_in_blob(blob, 10, 10, 768, 768, h)
    assert abs(v - dequantize_code(quantize_code(18.0))) < 1e-5
    v = lookup_in_blob(blob, 10, 400, 768, 768, h)
    assert abs(v - dequantize_code(quantize_code(19.0))) < 1e-5


# --- Header / index safety ---


def test_reject_root_cells_zero():
    data = bytearray(_valid_artifact_bytes())
    _patch_u16(data, 12, 0)
    with pytest.raises(ValueError, match="root_cells"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_pixel_size_zero():
    data = bytearray(_valid_artifact_bytes())
    _patch_f64(data, 40, 0.0)
    with pytest.raises(ValueError, match="pixel_size"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_nonfinite_pixel_size():
    data = bytearray(_valid_artifact_bytes())
    _patch_f64(data, 40, float("nan"))
    with pytest.raises(ValueError, match="non-finite"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_qmax_le_qmin():
    data = bytearray(_valid_artifact_bytes())
    _patch_f32(data, 48, 20.0)
    _patch_f32(data, 52, 20.0)
    with pytest.raises(ValueError, match="q_m_max"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_pristine_out_of_range():
    data = bytearray(_valid_artifact_bytes())
    _patch_f32(data, 56, 30.0)  # > q_m_max
    with pytest.raises(ValueError, match="pristine"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_zero_dimensions():
    data = bytearray(_valid_artifact_bytes())
    _patch_u32(data, 16, 0)
    with pytest.raises(ValueError, match="width/height"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_inconsistent_n_root_cols():
    data = bytearray(_valid_artifact_bytes())
    _patch_u16(data, 62, 1)  # n_root_cols wrong
    with pytest.raises(ValueError, match="inconsistent"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_root_index_offset_inside_header():
    data = bytearray(_valid_artifact_bytes())
    _patch_u32(data, 68, 64)
    with pytest.raises(ValueError, match="root_index_offset"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_root_data_offset_inside_index():
    data = bytearray(_valid_artifact_bytes())
    # Place root_data_offset at start of index region
    _patch_u32(data, 72, HEADER_SIZE)
    with pytest.raises(ValueError, match="root_data_offset"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_file_size_smaller_than_actual():
    data = bytearray(_valid_artifact_bytes())
    _patch_u32(data, 76, len(data) - 1)
    with pytest.raises(ValueError, match="file_size"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_file_size_larger_than_actual():
    data = bytearray(_valid_artifact_bytes())
    _patch_u32(data, 76, len(data) + 100)
    with pytest.raises(ValueError, match="file_size"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_oversized_root_offset():
    data = bytearray(_valid_artifact_bytes())
    # First root index entry at offset 128: set UInt64 offset beyond file
    struct.pack_into("<Q", data, HEADER_SIZE, 10**12)
    with pytest.raises(ValueError, match="root blob"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_zero_length_root_blob():
    data = bytearray(_valid_artifact_bytes())
    # length field of first entry at HEADER_SIZE+8
    struct.pack_into("<I", data, HEADER_SIZE + 8, 0)
    with pytest.raises(ValueError, match="zero-length"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_root_blob_into_header():
    data = bytearray(_valid_artifact_bytes())
    # offset into header
    struct.pack_into("<QI", data, HEADER_SIZE, 0, 1)
    with pytest.raises(ValueError, match="root blob"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_truncated_root_blob_payload():
    data = bytearray(_valid_artifact_bytes())
    _off, length = struct.unpack_from("<QI", data, HEADER_SIZE)
    struct.pack_into("<I", data, HEADER_SIZE + 8, length + 50)
    with pytest.raises(ValueError, match="root blob|out of bounds"):
        LightPollutionArtifact.from_bytes(bytes(data))


def test_reject_invalid_node_tag():
    blobs = _all_nodata_blobs()
    blobs[0] = bytes([99])  # invalid tag
    data = assemble_artifact(blobs)
    with pytest.raises(ValueError, match="bad tag"):
        LightPollutionArtifact.from_bytes(data)


def test_reject_coarse_factor_zero():
    # TAG_COARSE + factor 0 + empty would be invalid; one-byte grid expected after factor
    # Structure: tag(1) + u16 factor(0) + then expected ceil(h/f)*ceil(w/f) fails on factor
    blob = bytes([TAG_COARSE, 0, 0])  # factor 0
    with pytest.raises(ValueError, match="factor"):
        validate_tree_structure(blob, ROOT_CELLS, ROOT_CELLS)


def test_reject_truncated_constant_payload():
    with pytest.raises(ValueError):
        validate_tree_structure(bytes([TAG_CONSTANT]), ROOT_CELLS, ROOT_CELLS)


def test_reject_reserved_constant_quantization_code():
    with pytest.raises(ValueError, match="quantization code"):
        validate_tree_structure(bytes([TAG_CONSTANT, 255]), ROOT_CELLS, ROOT_CELLS)


def test_reject_reserved_coarse_quantization_code():
    # factor 255 produces a 4x4 grid for a 768-cell root.
    blob = bytes([TAG_COARSE, 255, 0] + [0] * 15 + [255])
    with pytest.raises(ValueError, match="quantization code"):
        validate_tree_structure(blob, ROOT_CELLS, ROOT_CELLS)


def test_reject_truncated_mask_payload():
    # default_mask requires ceil(768*768/8) bytes after tag
    with pytest.raises(ValueError):
        validate_tree_structure(bytes([2, 0x00]), ROOT_CELLS, ROOT_CELLS)  # TAG_DEFAULT_MASK=2


def test_valid_fixture_loads_if_present():
    from pathlib import Path

    fix = Path(__file__).resolve().parents[1] / "fixtures" / "lpatlas1_tiny_constant.bin"
    assert fix.is_file(), "checked-in fixture must exist"
    art = LightPollutionArtifact.load(fix)
    assert art.header.version == 1
    # Root 0,0 children quadrants produce values; equator is all_nodata
    assert art.lookup(0.0, 0.0) is None
