"""Test-only LPATLAS1 assemblers. Not a second runtime decoder."""

from __future__ import annotations

import json
import struct
from pathlib import Path

from astro_engine.contracts import contracts_root
from astro_engine.light_pollution import (
    HEADER_SIZE,
    MAGIC,
    ROOT_INDEX_ENTRY_SIZE,
    VERSION,
)

TINY_BIN = "fixtures/providers/lpatlas1/lpatlas1_tiny_constant.bin"
TINY_LOOKUPS = "fixtures/providers/lpatlas1/lpatlas1_tiny_constant.lookups.json"


def contract_tiny_bin() -> Path:
    return contracts_root() / TINY_BIN


def contract_tiny_lookups() -> Path:
    return contracts_root() / TINY_LOOKUPS


def load_lookup_manifest() -> dict:
    return json.loads(contract_tiny_lookups().read_text(encoding="utf-8"))


def _ceil_div(num: int, den: int) -> int:
    return (num + den - 1) // den


def pack_header(
    *,
    file_size: int,
    root_cells: int,
    width: int,
    height: int,
    finest_cells: int | None = None,
    origin_lon: float = -180.0,
    origin_lat: float = 75.0,
    pixel_size: float = 1.0 / 120.0,
    q_m_min: float = 13.01,
    q_m_max: float = 22.5,
    pristine_default: float = 22.0,
    error_budget_milli: int = 100,
    n_root_cols: int | None = None,
    n_root_rows: int | None = None,
    header_size: int = HEADER_SIZE,
    root_index_offset: int = HEADER_SIZE,
    root_data_offset: int | None = None,
    version: int = VERSION,
    magic: bytes = MAGIC,
) -> bytes:
    if finest_cells is None:
        finest_cells = 1 if root_cells > 0 else 0
    ni = n_root_cols if n_root_cols is not None else _ceil_div(width, root_cells)
    nj = n_root_rows if n_root_rows is not None else _ceil_div(height, root_cells)
    if root_data_offset is None:
        root_data_offset = root_index_offset + ni * nj * ROOT_INDEX_ENTRY_SIZE
    buf = bytearray(HEADER_SIZE)
    packed_magic = magic[:8].ljust(8, b"\x00")
    struct.pack_into(
        "<8sHHHHIIdddfffHHHHII",
        buf,
        0,
        packed_magic,
        version,
        0,
        root_cells,
        finest_cells,
        width,
        height,
        origin_lon,
        origin_lat,
        pixel_size,
        q_m_min,
        q_m_max,
        pristine_default,
        error_budget_milli,
        ni,
        nj,
        header_size,
        root_index_offset,
        root_data_offset,
    )
    struct.pack_into("<I", buf, 76, file_size)
    return bytes(buf)


def assemble_artifact(
    root_blobs: list[bytes],
    *,
    root_cells: int,
    width: int,
    height: int,
    **header_kw,
) -> bytes:
    ni = header_kw.get("n_root_cols") or _ceil_div(width, root_cells)
    nj = header_kw.get("n_root_rows") or _ceil_div(height, root_cells)
    if len(root_blobs) != ni * nj:
        raise AssertionError(f"expected {ni * nj} blobs, got {len(root_blobs)}")
    root_index_offset = HEADER_SIZE
    root_data_offset = HEADER_SIZE + ni * nj * ROOT_INDEX_ENTRY_SIZE
    index = bytearray()
    payload = bytearray()
    for blob in root_blobs:
        off = root_data_offset + len(payload)
        index.extend(struct.pack("<QI", off, len(blob)))
        payload.extend(blob)
    file_size = root_data_offset + len(payload)
    header = pack_header(
        file_size=file_size,
        root_cells=root_cells,
        width=width,
        height=height,
        n_root_cols=ni,
        n_root_rows=nj,
        root_index_offset=root_index_offset,
        root_data_offset=root_data_offset,
        **{k: v for k, v in header_kw.items() if k not in {"n_root_cols", "n_root_rows"}},
    )
    return header + bytes(index) + bytes(payload)


def pack_msb_first(flags: list[bool]) -> bytes:
    """NumPy packbits / Swift MSB-first mask packing."""
    out = bytearray((len(flags) + 7) // 8)
    for i, flag in enumerate(flags):
        if flag:
            out[i // 8] |= 1 << (7 - (i % 8))
    return bytes(out)


def constant_fill(root_cells: int, width: int, height: int, code: int) -> bytes:
    n_roots = _ceil_div(width, root_cells) * _ceil_div(height, root_cells)
    blobs = [bytes([0])] * n_roots  # TAG_ALL_NODATA
    blobs[0] = bytes([3, code])  # TAG_CONSTANT
    return assemble_artifact(blobs, root_cells=root_cells, width=width, height=height)
