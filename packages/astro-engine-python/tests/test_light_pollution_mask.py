"""MSB-first packbits mask sampling — high-risk LPATLAS1 parity point.

Evidence:
- BINARY_FORMAT.md: "packed NoData mask, ceil(h*w/8) bytes, MSB-first
  packbits, 1=NoData" and "matches NumPy np.packbits on a row-major
  boolean array".
- Swift BinaryLightPollutionProvider.maskIsNodata: bit = 7 - (bitIndex % 8).
- NumPy default packbits bitorder='big': first flattened bit is byte0 MSB
  (0x80). Empirically: [1,0,0,0,0,0,0,0] packs to 0x80; bits 0,7,8 of a
  9-bit mask pack to 0x81 0x80.
"""

from __future__ import annotations

from astro_engine.light_pollution import (
    TAG_CONSTANT_MASK,
    LightPollutionArtifact,
    mask_sample_is_nodata,
    packed_mask_nbytes,
)
from lp_support import assemble_artifact, pack_msb_first


def test_packed_mask_nbytes() -> None:
    assert packed_mask_nbytes(1) == 1
    assert packed_mask_nbytes(7) == 1
    assert packed_mask_nbytes(8) == 1
    assert packed_mask_nbytes(9) == 2
    assert packed_mask_nbytes(768 * 768) == (768 * 768 + 7) // 8


def test_first_bit_is_msb_of_first_byte() -> None:
    mask = b"\x80"
    assert mask_sample_is_nodata(mask, width=8, row=0, col=0) is True
    for col in range(1, 8):
        assert mask_sample_is_nodata(mask, width=8, row=0, col=col) is False


def test_last_bit_of_byte_is_lsb() -> None:
    mask = b"\x01"
    assert mask_sample_is_nodata(mask, width=8, row=0, col=7) is True
    for col in range(7):
        assert mask_sample_is_nodata(mask, width=8, row=0, col=col) is False


def test_byte_boundary_bit_8_is_msb_of_second_byte() -> None:
    mask = b"\x00\x80"
    assert mask_sample_is_nodata(mask, width=8, row=1, col=0) is True
    assert mask_sample_is_nodata(mask, width=8, row=0, col=0) is False


def test_set_vs_unset_roundtrip_matches_msb_first_helper() -> None:
    flags = [False] * 16
    flags[0] = True
    flags[7] = True
    flags[8] = True
    packed = pack_msb_first(flags)
    assert packed == b"\x81\x80"
    assert mask_sample_is_nodata(packed, 8, 0, 0) is True
    assert mask_sample_is_nodata(packed, 8, 0, 7) is True
    assert mask_sample_is_nodata(packed, 8, 1, 0) is True
    assert mask_sample_is_nodata(packed, 8, 0, 1) is False


def test_partial_final_byte_nine_cells() -> None:
    flags = [False] * 9
    flags[8] = True
    packed = pack_msb_first(flags)
    assert packed == b"\x00\x80"
    assert packed_mask_nbytes(9) == 2
    assert mask_sample_is_nodata(packed, 3, 2, 2) is True  # row-major index 8
    assert mask_sample_is_nodata(packed, 3, 0, 0) is False
    assert mask_sample_is_nodata(packed, 3, 2, 1) is False  # index 7


def test_truncated_mask_fails_closed_to_nodata() -> None:
    assert mask_sample_is_nodata(b"", width=8, row=0, col=0) is True


def test_lookup_uses_same_bit_order() -> None:
    flags = [False] * 4
    flags[0] = True
    mask = pack_msb_first(flags)
    payload = bytes([TAG_CONSTANT_MASK, 50]) + mask
    data = assemble_artifact([payload], root_cells=2, width=2, height=2)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    lat = header.origin_lat - 0.5 * header.pixel_size
    lon0 = header.origin_lon + 0.5 * header.pixel_size
    lon1 = header.origin_lon + 1.5 * header.pixel_size
    assert artifact.lookup(lat, lon0) is None
    assert artifact.lookup(lat, lon1) is not None
