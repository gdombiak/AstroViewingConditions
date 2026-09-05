"""Production LPATLAS1 binary format: constants, encode, and runtime re-export.

Canonical serialization for hierarchical_adaptive_uint8_budget0.1_error_cap0.025.

Runtime decode/lookup is owned by `astro_engine.light_pollution` (stdlib,
GDAL-free). This module keeps encoding, tree assembly, and production
quantization helpers, and re-exports the engine runtime so existing harness
imports (`LightPollutionArtifact`, `parse_header`, …) stay stable.
"""

from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

import numpy as np

from .hierarchical import (
    GLOBAL_HEIGHT,
    GLOBAL_WIDTH,
    ROOT_CELLS,
    TreeNode,
    n_root_cols,
    n_root_rows,
)
from .masks import packed_mask_nbytes
from .quantize import UInt8Params


def _ensure_astro_engine() -> None:
    """Monorepo bootstrap: Tools does not pip-depend on astro-engine."""
    try:
        import astro_engine.light_pollution  # noqa: F401
        return
    except ImportError:
        pass
    repo_src = Path(__file__).resolve().parents[3] / "packages" / "astro-engine-python" / "src"
    if repo_src.is_dir() and str(repo_src) not in sys.path:
        sys.path.insert(0, str(repo_src))


_ensure_astro_engine()

from astro_engine.light_pollution import (  # noqa: E402
    HEADER_SIZE,
    MAGIC,
    ROOT_INDEX_ENTRY_SIZE,
    TAG_ALL_NODATA,
    TAG_CHILDREN,
    TAG_COARSE,
    TAG_COARSE_MASK,
    TAG_CONSTANT,
    TAG_CONSTANT_MASK,
    TAG_DEFAULT,
    TAG_DEFAULT_MASK,
    VERSION,
    ArtifactHeader,
    LightPollutionArtifact,
    LightPollutionArtifactError,
    lookup_in_blob,
    normalize_longitude,
    parse_header,
    validate_root_index,
    validate_tree_structure,
)

PIXEL_SIZE = 1.0 / 120.0
ORIGIN_LON = -180.0
ORIGIN_LAT = 75.0

# Production quant from global minmax scan of 2025 atlas
PROD_U8 = UInt8Params(m_min=13.01, m_max=22.5, nodata_code=255)
PRISTINE_DEFAULT = 22.0
ERROR_BUDGET = 0.10
FINEST_CELLS = 3


def quantize_code(m: float, params: UInt8Params = PROD_U8) -> int:
    if not math.isfinite(m):
        raise ValueError("non-finite magnitude")
    step = params.step()
    q = int(round((m - params.m_min) / step))
    return max(0, min(params.max_code, q))


def dequantize_code(code: int, params: UInt8Params = PROD_U8) -> float:
    if code < 0 or code > params.max_code:
        raise ValueError(f"invalid code {code}")
    return float(params.m_min + code * params.step())


def lon_lat_to_cell(lon: float, lat: float) -> tuple[int, int] | None:
    if not (math.isfinite(lon) and math.isfinite(lat)):
        return None
    lon = normalize_longitude(lon)
    col = int(math.floor((lon - ORIGIN_LON) / PIXEL_SIZE))
    row = int(math.floor((ORIGIN_LAT - lat) / PIXEL_SIZE))
    if col < 0 or col >= GLOBAL_WIDTH or row < 0 or row >= GLOBAL_HEIGHT:
        return None
    return col, row


def pack_header(
    *,
    file_size: int,
    q_m_min: float = PROD_U8.m_min,
    q_m_max: float = PROD_U8.m_max,
    pristine_default: float = PRISTINE_DEFAULT,
    error_budget: float = ERROR_BUDGET,
    root_cells: int = ROOT_CELLS,
    finest_cells: int = FINEST_CELLS,
) -> bytes:
    ni, nj = n_root_cols(root_cells), n_root_rows(root_cells)
    root_index_offset = HEADER_SIZE
    root_data_offset = HEADER_SIZE + ni * nj * ROOT_INDEX_ENTRY_SIZE
    err_milli = int(round(error_budget * 1000))
    buf = bytearray(HEADER_SIZE)
    struct.pack_into("<8sHHHHIIdddfffHHHHII", buf, 0,
        MAGIC, VERSION, 0, root_cells, finest_cells,
        GLOBAL_WIDTH, GLOBAL_HEIGHT,
        ORIGIN_LON, ORIGIN_LAT, PIXEL_SIZE,
        q_m_min, q_m_max, pristine_default,
        err_milli, ni, nj, HEADER_SIZE,
        root_index_offset, root_data_offset,
    )
    # file_size at offset 76
    struct.pack_into("<I", buf, 76, file_size)
    return bytes(buf)


def _encode_mask(mask: bytes | None, h: int, w: int) -> bytes:
    if mask is None:
        raise ValueError("mask required")
    expected = packed_mask_nbytes(h * w)
    if len(mask) != expected:
        # packbits may pad; ensure exact
        if len(mask) < expected:
            mask = mask + b"\x00" * (expected - len(mask))
        else:
            mask = mask[:expected]
    return mask


def encode_tree_node(node: TreeNode, params: UInt8Params = PROD_U8) -> bytes:
    """Serialize TreeNode to LPATLAS1 DFS payload (no spatial header)."""
    out = bytearray()

    def enc(n: TreeNode) -> None:
        t = n.type
        has_mask = n.mask_packed is not None
        if t == "all_nodata":
            out.append(TAG_ALL_NODATA)
            return
        if t == "default_pristine":
            if has_mask:
                out.append(TAG_DEFAULT_MASK)
                out.extend(_encode_mask(n.mask_packed, n.h, n.w))
            else:
                out.append(TAG_DEFAULT)
            return
        if t == "constant":
            code = quantize_code(float(n.value), params)
            if has_mask:
                out.append(TAG_CONSTANT_MASK)
                out.append(code & 0xFF)
                out.extend(_encode_mask(n.mask_packed, n.h, n.w))
            else:
                out.append(TAG_CONSTANT)
                out.append(code & 0xFF)
            return
        if t == "coarse_grid":
            factor = int(n.grid_factor or 1)
            grid = np.asarray(n.grid)
            # re-quantize float grid to codes
            codes = np.empty(grid.shape, dtype=np.uint8)
            flat = grid.ravel()
            for i, v in enumerate(flat):
                if abs(float(v)) >= 1e30 or not math.isfinite(float(v)):
                    codes.ravel()[i] = 0  # unused if mask; structural
                else:
                    codes.ravel()[i] = quantize_code(float(v), params)
            if has_mask:
                out.append(TAG_COARSE_MASK)
            else:
                out.append(TAG_COARSE)
            out.extend(struct.pack("<H", factor))
            out.extend(codes.tobytes(order="C"))
            if has_mask:
                out.extend(_encode_mask(n.mask_packed, n.h, n.w))
            return
        if t == "children":
            out.append(TAG_CHILDREN)
            kids = n.children or []
            if len(kids) != 4:
                raise ValueError(f"children must have 4 kids, got {len(kids)}")
            for ch in kids:
                enc(ch)
            return
        raise ValueError(f"unknown node type {t}")

    enc(node)
    return bytes(out)


def assemble_artifact(root_blobs: list[bytes], **header_kw) -> bytes:
    """root_blobs ordered row-major (j major outer, i inner)."""
    ni = n_root_cols()
    nj = n_root_rows()
    if len(root_blobs) != ni * nj:
        raise ValueError(f"expected {ni*nj} blobs, got {len(root_blobs)}")
    root_data_offset = HEADER_SIZE + ni * nj * ROOT_INDEX_ENTRY_SIZE
    index = bytearray()
    data = bytearray()
    for blob in root_blobs:
        off = root_data_offset + len(data)
        index.extend(struct.pack("<QI", off, len(blob)))
        data.extend(blob)
    file_size = root_data_offset + len(data)
    header = pack_header(file_size=file_size, **header_kw)
    return header + bytes(index) + bytes(data)


__all__ = [
    "ERROR_BUDGET",
    "FINEST_CELLS",
    "HEADER_SIZE",
    "MAGIC",
    "ORIGIN_LAT",
    "ORIGIN_LON",
    "PIXEL_SIZE",
    "PRISTINE_DEFAULT",
    "PROD_U8",
    "ROOT_INDEX_ENTRY_SIZE",
    "TAG_ALL_NODATA",
    "TAG_CHILDREN",
    "TAG_COARSE",
    "TAG_COARSE_MASK",
    "TAG_CONSTANT",
    "TAG_CONSTANT_MASK",
    "TAG_DEFAULT",
    "TAG_DEFAULT_MASK",
    "VERSION",
    "ArtifactHeader",
    "LightPollutionArtifact",
    "LightPollutionArtifactError",
    "assemble_artifact",
    "dequantize_code",
    "encode_tree_node",
    "lon_lat_to_cell",
    "lookup_in_blob",
    "normalize_longitude",
    "pack_header",
    "parse_header",
    "quantize_code",
    "validate_root_index",
    "validate_tree_structure",
]
