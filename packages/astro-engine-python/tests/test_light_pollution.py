"""LPATLAS1 runtime lookup against the contract-owned tiny fixture."""

from __future__ import annotations

import math
from pathlib import Path

import pytest

from astro_engine.light_pollution import (
    TAG_ALL_NODATA,
    TAG_CHILDREN,
    TAG_COARSE,
    TAG_COARSE_MASK,
    TAG_CONSTANT,
    TAG_CONSTANT_MASK,
    TAG_DEFAULT,
    TAG_DEFAULT_MASK,
    LightPollutionArtifact,
    LightPollutionArtifactError,
    normalize_longitude,
)
from lp_support import (
    assemble_artifact,
    constant_fill,
    contract_tiny_bin,
    contract_tiny_lookups,
    load_lookup_manifest,
    pack_msb_first,
)


LOOKUP_ABS_TOL = 1e-9


def test_tiny_fixture_is_contract_owned() -> None:
    path = contract_tiny_bin()
    assert path.parts[-4:] == ("fixtures", "providers", "lpatlas1", "lpatlas1_tiny_constant.bin")
    assert "Tools" not in path.parts
    assert path.is_file()
    assert contract_tiny_lookups().is_file()


def test_phase5_tools_fixture_copies_remain_byte_identical() -> None:
    contract_bin = contract_tiny_bin().read_bytes()
    contract_json = contract_tiny_lookups().read_bytes()
    tools = Path(__file__).resolve().parents[3] / "Tools" / "LightPollution" / "fixtures"
    assert contract_bin == (tools / "lpatlas1_tiny_constant.bin").read_bytes()
    assert contract_json == (tools / "lpatlas1_tiny_constant.lookups.json").read_bytes()


def test_lookup_manifest_cases() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    manifest = load_lookup_manifest()
    assert manifest["lookups"], "lookup manifest must not be empty"
    for row in manifest["lookups"]:
        got = artifact.lookup(row["lat"], row["lon"])
        expected = row["value"]
        if expected is None:
            assert got is None, row
        else:
            assert got is not None, row
            assert abs(got - expected) <= LOOKUP_ABS_TOL, row


def test_children_quadrants_match_manifest_dequantized_values() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    cases = [
        (74.9125, -179.9125, 18.016535541204018),
        (74.9125, -176.6625, 18.987952840609815),
        (71.6625, -179.9125, 19.996732343838907),
        (71.6625, -176.6625, 21.005511847068007),
    ]
    for lat, lon, expected in cases:
        got = artifact.lookup(lat, lon)
        assert got is not None
        assert abs(got - expected) <= LOOKUP_ABS_TOL


def test_repeated_lookup_is_deterministic() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    first = load_lookup_manifest()["lookups"][0]
    a = artifact.lookup(first["lat"], first["lon"])
    b = artifact.lookup(first["lat"], first["lon"])
    assert a == b


def test_nonfinite_coordinates_return_none() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    assert artifact.lookup(float("nan"), 0.0) is None
    assert artifact.lookup(0.0, float("inf")) is None
    assert artifact.lookup(float("-inf"), 0.0) is None


def test_longitude_180_normalizes_to_minus_180() -> None:
    assert normalize_longitude(180.0) == -180.0
    assert abs(normalize_longitude(190.0) - (-170.0)) < 1e-12
    assert abs(normalize_longitude(-180.0) - (-180.0)) < 1e-12
    assert abs(normalize_longitude(540.0) - (-180.0)) < 1e-12


def test_longitude_wrapping_uses_same_cell_as_canonical() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    canonical = artifact.lookup(74.9125, -179.9125)
    wrapped = artifact.lookup(74.9125, -179.9125 + 360.0)
    assert canonical is not None
    assert wrapped == canonical
    # 180 maps onto the west edge, which is the TL constant of root (0,0).
    assert artifact.lookup(74.9125, 180.0) == artifact.lookup(74.9125, -180.0)


def test_latitude_just_outside_coverage_is_none() -> None:
    data = constant_fill(root_cells=4, width=4, height=4, code=100)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    inside_lat = header.origin_lat - 0.5 * header.pixel_size
    inside_lon = header.origin_lon + 0.5 * header.pixel_size
    assert artifact.lookup(inside_lat, inside_lon) is not None
    assert artifact.lookup(header.origin_lat + header.pixel_size, inside_lon) is None
    last_inside = header.origin_lat - (header.height - 0.5) * header.pixel_size
    south_outside = header.origin_lat - header.height * header.pixel_size - 1e-6
    assert artifact.lookup(last_inside, inside_lon) is not None
    assert artifact.lookup(south_outside, inside_lon) is None


def test_does_not_clamp_latitude_into_dataset() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    assert artifact.lookup(90.0, 0.0) is None
    assert artifact.lookup(-90.0, 0.0) is None


def test_all_nodata_lookup_is_none() -> None:
    blobs = [bytes([TAG_ALL_NODATA])]
    data = assemble_artifact(blobs, root_cells=2, width=2, height=2)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    lat = header.origin_lat - 0.5 * header.pixel_size
    lon = header.origin_lon + 0.5 * header.pixel_size
    assert artifact.lookup(lat, lon) is None


def test_default_pristine_uses_header_quantization() -> None:
    blobs = [bytes([TAG_DEFAULT])]
    data = assemble_artifact(
        blobs,
        root_cells=2,
        width=2,
        height=2,
        q_m_min=13.01,
        q_m_max=22.5,
        pristine_default=22.0,
    )
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    step = (header.q_m_max - header.q_m_min) / 254.0
    q = (header.pristine_default - header.q_m_min) / step
    code = max(0, min(254, int(math.floor(q + 0.5))))
    expected = header.q_m_min + code * step
    lat = header.origin_lat - 0.5 * header.pixel_size
    lon = header.origin_lon + 0.5 * header.pixel_size
    got = artifact.lookup(lat, lon)
    assert got is not None
    assert abs(got - expected) <= LOOKUP_ABS_TOL


def test_constant_and_constant_mask() -> None:
    mask = pack_msb_first([True, False, False, False])
    blobs = [bytes([TAG_CONSTANT_MASK, 134]) + mask]
    data = assemble_artifact(blobs, root_cells=2, width=2, height=2)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    lat0 = header.origin_lat - 0.5 * header.pixel_size
    lon0 = header.origin_lon + 0.5 * header.pixel_size
    lat1 = header.origin_lat - 0.5 * header.pixel_size
    lon1 = header.origin_lon + 1.5 * header.pixel_size
    assert artifact.lookup(lat0, lon0) is None
    value = artifact.lookup(lat1, lon1)
    assert value is not None
    assert abs(value - (header.q_m_min + 134 * header.quant_step)) <= LOOKUP_ABS_TOL


def test_default_mask_nodata_vs_pristine() -> None:
    mask = pack_msb_first([False, True, False, False])
    blobs = [bytes([TAG_DEFAULT_MASK]) + mask]
    data = assemble_artifact(blobs, root_cells=2, width=2, height=2)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    lat = header.origin_lat - 0.5 * header.pixel_size
    lon_valid = header.origin_lon + 0.5 * header.pixel_size
    lon_nodata = header.origin_lon + 1.5 * header.pixel_size
    assert artifact.lookup(lat, lon_valid) is not None
    assert artifact.lookup(lat, lon_nodata) is None


def test_coarse_grid_samples_local_cell() -> None:
    # 4x4 root, factor 2 → 2x2 codes: TL=10, TR=20, BL=30, BR=40
    payload = bytes([TAG_COARSE, 2, 0, 10, 20, 30, 40])
    data = assemble_artifact([payload], root_cells=4, width=4, height=4)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header

    def sample(row: int, col: int) -> float | None:
        lat = header.origin_lat - (row + 0.5) * header.pixel_size
        lon = header.origin_lon + (col + 0.5) * header.pixel_size
        return artifact.lookup(lat, lon)

    assert abs(sample(0, 0) - (header.q_m_min + 10 * header.quant_step)) <= LOOKUP_ABS_TOL
    assert abs(sample(0, 3) - (header.q_m_min + 20 * header.quant_step)) <= LOOKUP_ABS_TOL
    assert abs(sample(3, 0) - (header.q_m_min + 30 * header.quant_step)) <= LOOKUP_ABS_TOL
    assert abs(sample(3, 3) - (header.q_m_min + 40 * header.quant_step)) <= LOOKUP_ABS_TOL


def test_coarse_mask_overrides_grid() -> None:
    mask = pack_msb_first([True] + [False] * 15)
    payload = bytes([TAG_COARSE_MASK, 2, 0, 10, 20, 30, 40]) + mask
    data = assemble_artifact([payload], root_cells=4, width=4, height=4)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header
    lat = header.origin_lat - 0.5 * header.pixel_size
    lon = header.origin_lon + 0.5 * header.pixel_size
    assert artifact.lookup(lat, lon) is None


def test_children_tl_tr_bl_br_order() -> None:
    # 2x2 children of constants 1,2,3,4
    payload = bytes(
        [
            TAG_CHILDREN,
            TAG_CONSTANT, 1,
            TAG_CONSTANT, 2,
            TAG_CONSTANT, 3,
            TAG_CONSTANT, 4,
        ]
    )
    data = assemble_artifact([payload], root_cells=2, width=2, height=2)
    artifact = LightPollutionArtifact.from_bytes(data)
    header = artifact.header

    def sample(row: int, col: int) -> int:
        lat = header.origin_lat - (row + 0.5) * header.pixel_size
        lon = header.origin_lon + (col + 0.5) * header.pixel_size
        value = artifact.lookup(lat, lon)
        assert value is not None
        code = round((value - header.q_m_min) / header.quant_step)
        return int(code)

    assert sample(0, 0) == 1
    assert sample(0, 1) == 2
    assert sample(1, 0) == 3
    assert sample(1, 1) == 4


def test_info_reports_header_fields() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    info = artifact.info()
    assert info["magic"] == "LPATLAS1"
    assert info["version"] == 1
    assert info["file_size"] == 16438
    assert info["root_cells"] == 768
    assert info["n_roots"] == artifact.header.n_roots


def test_from_bytes_does_not_decode_a_global_raster() -> None:
    artifact = LightPollutionArtifact.load(contract_tiny_bin())
    # Raw bytes + one range per root. Never width*height samples.
    assert artifact.data is not None
    assert len(artifact.root_ranges) == artifact.header.n_roots
    assert artifact.header.width * artifact.header.height > 100_000
    assert len(artifact.root_ranges) < artifact.header.width


def test_malformed_load_raises_not_none() -> None:
    with pytest.raises(LightPollutionArtifactError):
        LightPollutionArtifact.from_bytes(b"LPATLAS1" + b"\x00" * 10)
