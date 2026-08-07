"""Production LPATLAS1 binary format: constants, encode, decode, lookup.

Canonical serialization for hierarchical_adaptive_uint8_budget0.1_error_cap0.025.
"""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO

import numpy as np

from .hierarchical import (
    GLOBAL_HEIGHT,
    GLOBAL_WIDTH,
    ROOT_CELLS,
    TreeNode,
    n_root_cols,
    n_root_rows,
)
from .masks import packed_mask_nbytes, unpack_nodata_mask
from .quantize import UInt8Params

MAGIC = b"LPATLAS1"
VERSION = 1
HEADER_SIZE = 128
ROOT_INDEX_ENTRY_SIZE = 12
PIXEL_SIZE = 1.0 / 120.0
ORIGIN_LON = -180.0
ORIGIN_LAT = 75.0

TAG_ALL_NODATA = 0
TAG_DEFAULT = 1
TAG_DEFAULT_MASK = 2
TAG_CONSTANT = 3
TAG_CONSTANT_MASK = 4
TAG_COARSE = 5
TAG_COARSE_MASK = 6
TAG_CHILDREN = 7

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


def normalize_longitude(lon: float) -> float:
    """Map longitude to [-180, 180)."""
    x = math.fmod(lon + 180.0, 360.0)
    if x < 0:
        x += 360.0
    return x - 180.0


def lon_lat_to_cell(lon: float, lat: float) -> tuple[int, int] | None:
    if not (math.isfinite(lon) and math.isfinite(lat)):
        return None
    lon = normalize_longitude(lon)
    col = int(math.floor((lon - ORIGIN_LON) / PIXEL_SIZE))
    row = int(math.floor((ORIGIN_LAT - lat) / PIXEL_SIZE))
    if col < 0 or col >= GLOBAL_WIDTH or row < 0 or row >= GLOBAL_HEIGHT:
        return None
    return col, row


@dataclass(frozen=True)
class ArtifactHeader:
    version: int
    root_cells: int
    finest_cells: int
    width: int
    height: int
    origin_lon: float
    origin_lat: float
    pixel_size: float
    q_m_min: float
    q_m_max: float
    pristine_default: float
    error_budget: float
    n_root_cols: int
    n_root_rows: int
    header_size: int
    root_index_offset: int
    root_data_offset: int
    file_size: int

    @property
    def n_roots(self) -> int:
        return self.n_root_cols * self.n_root_rows

    @property
    def u8_params(self) -> UInt8Params:
        return UInt8Params(m_min=self.q_m_min, m_max=self.q_m_max, nodata_code=255)


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


def _ceil_div(num: int, den: int) -> int:
    if den <= 0:
        raise ValueError("invalid divisor")
    return (num + den - 1) // den


def parse_header(data: bytes) -> ArtifactHeader:
    """Parse and validate LPATLAS1 v1 header invariants.

    Rejects malformed geometry, quantization, and offset layout before any lookup.
    """
    if len(data) < HEADER_SIZE:
        raise ValueError("truncated header")
    magic = data[0:8]
    if magic != MAGIC:
        raise ValueError(f"bad magic {magic!r}")
    version, flags, root_cells, finest_cells = struct.unpack_from("<HHHH", data, 8)
    if version != VERSION:
        raise ValueError(f"unsupported version {version}")
    width, height = struct.unpack_from("<II", data, 16)
    origin_lon, origin_lat, pixel_size = struct.unpack_from("<ddd", data, 24)
    q_m_min, q_m_max, pristine = struct.unpack_from("<fff", data, 48)
    err_milli, ni, nj, header_size = struct.unpack_from("<HHHH", data, 60)
    root_index_offset, root_data_offset = struct.unpack_from("<II", data, 68)
    file_size = struct.unpack_from("<I", data, 76)[0]
    if header_size != HEADER_SIZE:
        raise ValueError(f"unexpected header_size {header_size}")

    if root_cells <= 0:
        raise ValueError("root_cells must be > 0")
    if finest_cells <= 0 or finest_cells > root_cells:
        raise ValueError("invalid finest_cells")
    if width <= 0 or height <= 0:
        raise ValueError("width/height must be > 0")
    if ni <= 0 or nj <= 0:
        raise ValueError("n_root_cols/n_root_rows must be > 0")

    if not (math.isfinite(origin_lon) and math.isfinite(origin_lat) and math.isfinite(pixel_size)):
        raise ValueError("non-finite spatial metadata")
    if pixel_size <= 0:
        raise ValueError("pixel_size must be > 0")
    if not (math.isfinite(q_m_min) and math.isfinite(q_m_max) and math.isfinite(pristine)):
        raise ValueError("non-finite quantization metadata")
    if q_m_max <= q_m_min:
        raise ValueError("q_m_max must be > q_m_min")
    if pristine < q_m_min or pristine > q_m_max:
        raise ValueError("pristine_default outside quantization range")
    quant_step = (q_m_max - q_m_min) / 254.0
    if not math.isfinite(quant_step) or quant_step <= 0:
        raise ValueError("invalid quant step")

    if _ceil_div(width, root_cells) != ni or _ceil_div(height, root_cells) != nj:
        raise ValueError("n_root_cols/n_root_rows inconsistent with width/height/root_cells")

    n_roots = ni * nj
    if n_roots <= 0:
        raise ValueError("invalid n_roots")

    if root_index_offset < HEADER_SIZE:
        raise ValueError("root_index_offset inside header")
    index_bytes = n_roots * ROOT_INDEX_ENTRY_SIZE
    index_end = root_index_offset + index_bytes
    if index_end < root_index_offset:
        raise ValueError("root index size overflow")
    if root_data_offset < index_end:
        raise ValueError("root_data_offset overlaps root index")
    if file_size != len(data):
        raise ValueError("declared file_size mismatch")
    if file_size < root_data_offset:
        raise ValueError("file_size < root_data_offset")
    if root_data_offset > len(data):
        raise ValueError("root_data_offset beyond data")
    if index_end > file_size:
        raise ValueError("root index truncated")

    return ArtifactHeader(
        version=version,
        root_cells=root_cells,
        finest_cells=finest_cells,
        width=width,
        height=height,
        origin_lon=origin_lon,
        origin_lat=origin_lat,
        pixel_size=pixel_size,
        q_m_min=q_m_min,
        q_m_max=q_m_max,
        pristine_default=pristine,
        error_budget=err_milli / 1000.0,
        n_root_cols=ni,
        n_root_rows=nj,
        header_size=header_size,
        root_index_offset=root_index_offset,
        root_data_offset=root_data_offset,
        file_size=file_size,
    )


def validate_root_index(data: bytes, header: ArtifactHeader) -> list[tuple[int, int]]:
    """Validate every root-index entry; return list of (offset, length) as Python ints."""
    ranges: list[tuple[int, int]] = []
    n = header.n_roots
    for i in range(n):
        off = header.root_index_offset + i * ROOT_INDEX_ENTRY_SIZE
        if off + ROOT_INDEX_ENTRY_SIZE > len(data):
            raise ValueError("truncated root index entry")
        blob_off, blob_len = struct.unpack_from("<QI", data, off)
        if blob_len <= 0:
            raise ValueError("zero-length root blob")
        if blob_off < header.root_data_offset:
            raise ValueError("root blob points before root data")
        end = blob_off + blob_len
        if end < blob_off:
            raise ValueError("root blob offset+length overflow")
        if end > header.file_size or end > len(data):
            raise ValueError("root blob out of bounds")
        ranges.append((int(blob_off), int(blob_len)))
    return ranges


def validate_tree_structure(blob: bytes, root_h: int, root_w: int) -> None:
    """Eager structural DFS validation; requires exact blob consumption."""
    cur = _Cursor(blob)

    def walk(h: int, w: int) -> None:
        if h <= 0 or w <= 0:
            raise ValueError("invalid node dimensions")
        tag = cur.u8()
        if tag in (TAG_ALL_NODATA, TAG_DEFAULT):
            return
        if tag == TAG_DEFAULT_MASK:
            cur.read(_mask_len(h, w))
            return
        if tag == TAG_CONSTANT:
            if cur.u8() > PROD_U8.max_code:
                raise ValueError("invalid quantization code")
            return
        if tag == TAG_CONSTANT_MASK:
            if cur.u8() > PROD_U8.max_code:
                raise ValueError("invalid quantization code")
            cur.read(_mask_len(h, w))
            return
        if tag in (TAG_COARSE, TAG_COARSE_MASK):
            factor = cur.u16()
            if factor < 1:
                raise ValueError("coarse factor must be >= 1")
            gh, gw = _coarse_shape(h, w, factor)
            codes = cur.read(gh * gw)
            if any(code > PROD_U8.max_code for code in codes):
                raise ValueError("invalid quantization code")
            if tag == TAG_COARSE_MASK:
                cur.read(_mask_len(h, w))
            return
        if tag == TAG_CHILDREN:
            mh, mw = h // 2, w // 2
            dims = [
                (mh, mw),
                (mh, w - mw),
                (h - mh, mw),
                (h - mh, w - mw),
            ]
            for qh, qw in dims:
                if qh > 0 and qw > 0:
                    walk(qh, qw)
            return
        raise ValueError(f"bad tag {tag}")

    walk(root_h, root_w)
    if cur.pos != len(blob):
        raise ValueError("root blob trailing garbage or incomplete tree")


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


def _mask_len(h: int, w: int) -> int:
    return packed_mask_nbytes(h * w)


def _coarse_shape(h: int, w: int, factor: int) -> tuple[int, int]:
    return (math.ceil(h / factor), math.ceil(w / factor))


class _Cursor:
    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos

    def u8(self) -> int:
        if self.pos >= len(self.data):
            raise ValueError("truncated")
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        if self.pos + 2 > len(self.data):
            raise ValueError("truncated")
        v = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def read(self, n: int) -> bytes:
        if self.pos + n > len(self.data):
            raise ValueError("truncated")
        b = self.data[self.pos : self.pos + n]
        self.pos += n
        return b


def lookup_in_blob(
    blob: bytes,
    local_r: int,
    local_c: int,
    root_h: int,
    root_w: int,
    header: ArtifactHeader,
) -> float | None:
    """Return mag/arcsec² or None if unavailable."""
    cur = _Cursor(blob)
    params = header.u8_params
    pristine_code = quantize_code(header.pristine_default, params)

    def sample_mask(mask: bytes, h: int, w: int, r: int, c: int) -> bool:
        inv = unpack_nodata_mask(mask, (h, w))
        return bool(inv[r, c])

    def walk(h: int, w: int, r: int, c: int) -> float | None:
        tag = cur.u8()
        if tag == TAG_ALL_NODATA:
            return None
        if tag == TAG_DEFAULT:
            return dequantize_code(pristine_code, params)
        if tag == TAG_DEFAULT_MASK:
            mask = cur.read(_mask_len(h, w))
            if sample_mask(mask, h, w, r, c):
                return None
            return dequantize_code(pristine_code, params)
        if tag == TAG_CONSTANT:
            code = cur.u8()
            return dequantize_code(code, params)
        if tag == TAG_CONSTANT_MASK:
            code = cur.u8()
            mask = cur.read(_mask_len(h, w))
            if sample_mask(mask, h, w, r, c):
                return None
            return dequantize_code(code, params)
        if tag in (TAG_COARSE, TAG_COARSE_MASK):
            factor = cur.u16()
            if factor < 1:
                raise ValueError("coarse factor must be >= 1")
            gh, gw = _coarse_shape(h, w, factor)
            n = gh * gw
            codes = cur.read(n)
            if tag == TAG_COARSE_MASK:
                mask = cur.read(_mask_len(h, w))
                if sample_mask(mask, h, w, r, c):
                    return None
            gr = min(r // factor, gh - 1)
            gc = min(c // factor, gw - 1)
            code = codes[gr * gw + gc]
            return dequantize_code(code, params)
        if tag == TAG_CHILDREN:
            mh, mw = h // 2, w // 2
            # TL TR BL BR
            quads = [
                (0, 0, mh, mw),
                (0, mw, mh, w - mw),
                (mh, 0, h - mh, mw),
                (mh, mw, h - mh, w - mw),
            ]
            target = 0
            for i, (qr, qc, qh, qw) in enumerate(quads):
                if qh > 0 and qw > 0 and qr <= r < qr + qh and qc <= c < qc + qw:
                    target = i
                    break
            for i, (qr, qc, qh, qw) in enumerate(quads):
                if qh <= 0 or qw <= 0:
                    continue
                if i == target:
                    return walk(qh, qw, r - qr, c - qc)
                skip_node(qh, qw)
            raise ValueError("child not found")
        raise ValueError(f"bad tag {tag}")

    def skip_node(h: int, w: int) -> None:
        tag = cur.u8()
        if tag in (TAG_ALL_NODATA, TAG_DEFAULT):
            return
        if tag == TAG_DEFAULT_MASK:
            cur.read(_mask_len(h, w))
            return
        if tag == TAG_CONSTANT:
            cur.u8()
            return
        if tag == TAG_CONSTANT_MASK:
            cur.u8()
            cur.read(_mask_len(h, w))
            return
        if tag in (TAG_COARSE, TAG_COARSE_MASK):
            factor = cur.u16()
            if factor < 1:
                raise ValueError("coarse factor must be >= 1")
            gh, gw = _coarse_shape(h, w, factor)
            cur.read(gh * gw)
            if tag == TAG_COARSE_MASK:
                cur.read(_mask_len(h, w))
            return
        if tag == TAG_CHILDREN:
            mh, mw = h // 2, w // 2
            dims = [
                (mh, mw),
                (mh, w - mw),
                (h - mh, mw),
                (h - mh, w - mw),
            ]
            for qh, qw in dims:
                if qh > 0 and qw > 0:
                    skip_node(qh, qw)
            return
        raise ValueError(f"bad tag skip {tag}")

    return walk(root_h, root_w, local_r, local_c)


@dataclass
class LightPollutionArtifact:
    data: bytes
    header: ArtifactHeader
    root_ranges: list[tuple[int, int]]

    @classmethod
    def from_bytes(cls, data: bytes) -> "LightPollutionArtifact":
        header = parse_header(data)
        ranges = validate_root_index(data, header)
        rc = header.root_cells
        for off, length in ranges:
            blob = data[off : off + length]
            validate_tree_structure(blob, rc, rc)
        return cls(data=data, header=header, root_ranges=ranges)

    @classmethod
    def load(cls, path: Path | str) -> "LightPollutionArtifact":
        return cls.from_bytes(Path(path).read_bytes())

    def root_blob(self, root_i: int, root_j: int) -> bytes:
        h = self.header
        if root_i < 0 or root_i >= h.n_root_cols or root_j < 0 or root_j >= h.n_root_rows:
            raise ValueError("root out of range")
        idx = root_j * h.n_root_cols + root_i
        blob_off, blob_len = self.root_ranges[idx]
        return self.data[blob_off : blob_off + blob_len]

    def lookup(self, latitude: float, longitude: float) -> float | None:
        # Use header spatial parameters when present (production constants match encoder).
        if not (math.isfinite(latitude) and math.isfinite(longitude)):
            return None
        lon = normalize_longitude(longitude)
        col = int(math.floor((lon - self.header.origin_lon) / self.header.pixel_size))
        row = int(math.floor((self.header.origin_lat - latitude) / self.header.pixel_size))
        if col < 0 or col >= self.header.width or row < 0 or row >= self.header.height:
            return None
        rc = self.header.root_cells
        root_i = col // rc
        root_j = row // rc
        local_c = col - root_i * rc
        local_r = row - root_j * rc
        blob = self.root_blob(root_i, root_j)
        try:
            return lookup_in_blob(blob, local_r, local_c, rc, rc, self.header)
        except ValueError:
            # Structure already validated at load; residual parse errors fail closed.
            return None

    def info(self) -> dict[str, Any]:
        h = self.header
        return {
            "magic": MAGIC.decode(),
            "version": h.version,
            "file_size": len(self.data),
            "width": h.width,
            "height": h.height,
            "root_cells": h.root_cells,
            "finest_cells": h.finest_cells,
            "n_roots": h.n_roots,
            "q_m_min": h.q_m_min,
            "q_m_max": h.q_m_max,
            "pristine_default": h.pristine_default,
            "error_budget": h.error_budget,
            "origin_lon": h.origin_lon,
            "origin_lat": h.origin_lat,
            "pixel_size": h.pixel_size,
        }


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
