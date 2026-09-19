"""LPATLAS1 runtime decode and lookup.

GDAL-free, stdlib-only. This module is the Python owner of runtime
header/index/tree validation and coordinate lookup. The Tools
preprocessing harness may re-export these symbols; it keeps encoding,
tree construction, NumPy, and GDAL.

Malformed artifacts raise LightPollutionArtifactError at load.
Successful lookup returns None for geographic NoData / out of coverage /
non-finite queries, and fails closed to None on unexpected residual
parse errors. It does not materialize a global raster.
"""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from pathlib import Path

CAPABILITY_ID = "light_pollution.lookup"

MAGIC = b"LPATLAS1"
VERSION = 1
HEADER_SIZE = 128
ROOT_INDEX_ENTRY_SIZE = 12
MAX_VALID_QUANT_CODE = 254
NODATA_QUANT_CODE = 255

TAG_ALL_NODATA = 0
TAG_DEFAULT = 1
TAG_DEFAULT_MASK = 2
TAG_CONSTANT = 3
TAG_CONSTANT_MASK = 4
TAG_COARSE = 5
TAG_COARSE_MASK = 6
TAG_CHILDREN = 7

# Match Swift 64-bit Int / UInt32 representable-width checks so hostile
# offsets that Python's arbitrary integers could accept still fail closed.
_INT64_MAX = 2**63 - 1
_UINT32_MAX = 2**32 - 1

_Buffer = bytes | memoryview | bytearray


class LightPollutionArtifactError(ValueError):
    """Malformed LPATLAS1 artifact rejected at load/initialization."""


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
    def quant_step(self) -> float:
        return (self.q_m_max - self.q_m_min) / 254.0


def _ceil_div(num: int, den: int) -> int:
    if den <= 0:
        raise LightPollutionArtifactError("invalid divisor")
    return (num + den - 1) // den


def _round_ties_away(value: float) -> int:
    """Swift `Double.rounded()` (toNearestOrAwayFromZero)."""
    if value >= 0:
        return int(math.floor(value + 0.5))
    return int(math.ceil(value - 0.5))


def normalize_longitude(lon: float) -> float:
    """Map longitude to [-180, 180)."""
    x = math.fmod(lon + 180.0, 360.0)
    if x < 0:
        x += 360.0
    return x - 180.0


def packed_mask_nbytes(n_cells: int) -> int:
    return (int(n_cells) + 7) // 8


def mask_sample_is_nodata(mask: _Buffer, width: int, row: int, col: int) -> bool:
    """Return True if packed mask bit (row, col) is NoData.

    Packing is NumPy `np.packbits` default / MSB-first: flattened
    row-major bit index `row * width + col`; bit 0 of the stream is
    the high bit of byte 0. Matches Swift `maskIsNodata` and
    `BINARY_FORMAT.md`. A truncated mask fails closed to NoData.
    """
    bit_index = row * width + col
    byte_index = bit_index // 8
    bit = 7 - (bit_index % 8)
    if byte_index < 0 or byte_index >= len(mask):
        return True
    return (mask[byte_index] & (1 << bit)) != 0


def parse_header(data: _Buffer) -> ArtifactHeader:
    """Parse and validate LPATLAS1 v1 header invariants.

    Rejects malformed geometry, quantization, and offset layout before any lookup.
    """
    if len(data) < HEADER_SIZE:
        raise LightPollutionArtifactError("truncated header")
    magic = bytes(data[0:8])
    if magic != MAGIC:
        raise LightPollutionArtifactError(f"bad magic {magic!r}")
    version, _flags, root_cells, finest_cells = struct.unpack_from("<HHHH", data, 8)
    if version != VERSION:
        raise LightPollutionArtifactError(f"unsupported version {version}")
    width, height = struct.unpack_from("<II", data, 16)
    origin_lon, origin_lat, pixel_size = struct.unpack_from("<ddd", data, 24)
    q_m_min, q_m_max, pristine = struct.unpack_from("<fff", data, 48)
    err_milli, ni, nj, header_size = struct.unpack_from("<HHHH", data, 60)
    root_index_offset, root_data_offset = struct.unpack_from("<II", data, 68)
    file_size = struct.unpack_from("<I", data, 76)[0]
    if header_size != HEADER_SIZE:
        raise LightPollutionArtifactError(f"unexpected header_size {header_size}")

    if root_cells <= 0:
        raise LightPollutionArtifactError("root_cells must be > 0")
    if finest_cells <= 0 or finest_cells > root_cells:
        raise LightPollutionArtifactError("invalid finest_cells")
    if width <= 0 or height <= 0:
        raise LightPollutionArtifactError("width/height must be > 0")
    if ni <= 0 or nj <= 0:
        raise LightPollutionArtifactError("n_root_cols/n_root_rows must be > 0")

    if not (math.isfinite(origin_lon) and math.isfinite(origin_lat) and math.isfinite(pixel_size)):
        raise LightPollutionArtifactError("non-finite spatial metadata")
    if pixel_size <= 0:
        raise LightPollutionArtifactError("pixel_size must be > 0")
    if not (math.isfinite(q_m_min) and math.isfinite(q_m_max) and math.isfinite(pristine)):
        raise LightPollutionArtifactError("non-finite quantization metadata")
    if q_m_max <= q_m_min:
        raise LightPollutionArtifactError("q_m_max must be > q_m_min")
    if pristine < q_m_min or pristine > q_m_max:
        raise LightPollutionArtifactError("pristine_default outside quantization range")
    quant_step = (q_m_max - q_m_min) / 254.0
    if not math.isfinite(quant_step) or quant_step <= 0:
        raise LightPollutionArtifactError("invalid quant step")

    if _ceil_div(width, root_cells) != ni or _ceil_div(height, root_cells) != nj:
        raise LightPollutionArtifactError(
            "n_root_cols/n_root_rows inconsistent with width/height/root_cells"
        )

    n_roots = ni * nj
    if n_roots <= 0 or n_roots > _INT64_MAX:
        raise LightPollutionArtifactError("invalid n_roots")

    if root_index_offset < HEADER_SIZE:
        raise LightPollutionArtifactError("root_index_offset inside header")
    index_bytes = n_roots * ROOT_INDEX_ENTRY_SIZE
    if index_bytes > _UINT32_MAX:
        raise LightPollutionArtifactError("root index size overflow")
    index_end = root_index_offset + index_bytes
    if index_end < root_index_offset or index_end > _UINT32_MAX:
        raise LightPollutionArtifactError("root index size overflow")
    if root_data_offset < index_end:
        raise LightPollutionArtifactError("root_data_offset overlaps root index")
    if file_size != len(data):
        raise LightPollutionArtifactError("declared file_size mismatch")
    if file_size < root_data_offset:
        raise LightPollutionArtifactError("file_size < root_data_offset")
    if root_data_offset > len(data):
        raise LightPollutionArtifactError("root_data_offset beyond data")
    if index_end > file_size:
        raise LightPollutionArtifactError("root index truncated")

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


def validate_root_index(data: _Buffer, header: ArtifactHeader) -> list[tuple[int, int]]:
    """Validate every root-index entry; return list of (offset, length)."""
    ranges: list[tuple[int, int]] = []
    n = header.n_roots
    file_size = header.file_size
    for i in range(n):
        off = header.root_index_offset + i * ROOT_INDEX_ENTRY_SIZE
        if off + ROOT_INDEX_ENTRY_SIZE > len(data):
            raise LightPollutionArtifactError("truncated root index entry")
        blob_off, blob_len = struct.unpack_from("<QI", data, off)
        if blob_off > _INT64_MAX or blob_len > _INT64_MAX:
            raise LightPollutionArtifactError("root blob out of bounds")
        if blob_len <= 0:
            raise LightPollutionArtifactError("zero-length root blob")
        if blob_off < header.root_data_offset:
            raise LightPollutionArtifactError("root blob points before root data")
        if blob_off > file_size or blob_len > file_size - blob_off:
            raise LightPollutionArtifactError("root blob out of bounds")
        end = blob_off + blob_len
        if end < blob_off:
            raise LightPollutionArtifactError("root blob offset+length overflow")
        if end > file_size or end > len(data):
            raise LightPollutionArtifactError("root blob out of bounds")
        ranges.append((int(blob_off), int(blob_len)))
    return ranges


def _mask_len(h: int, w: int) -> int:
    return packed_mask_nbytes(h * w)


def _coarse_shape(h: int, w: int, factor: int) -> tuple[int, int]:
    # Integer ceil, matching Swift. Do not use float `math.ceil(h / factor)`.
    return ((h + factor - 1) // factor, (w + factor - 1) // factor)


class _Cursor:
    def __init__(self, data: _Buffer, pos: int = 0) -> None:
        self.data = data
        self.pos = pos

    def u8(self) -> int:
        if self.pos >= len(self.data):
            raise LightPollutionArtifactError("truncated")
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        if self.pos + 2 > len(self.data):
            raise LightPollutionArtifactError("truncated")
        v = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def read(self, n: int) -> memoryview:
        if n < 0 or self.pos + n > len(self.data):
            raise LightPollutionArtifactError("truncated")
        buf = self.data
        if not isinstance(buf, memoryview):
            buf = memoryview(buf)
        b = buf[self.pos : self.pos + n]
        self.pos += n
        return b


def validate_tree_structure(blob: _Buffer, root_h: int, root_w: int) -> None:
    """Eager structural DFS validation; requires exact blob consumption."""
    cur = _Cursor(blob)

    def walk(h: int, w: int) -> None:
        if h <= 0 or w <= 0:
            raise LightPollutionArtifactError("invalid node dimensions")
        tag = cur.u8()
        if tag in (TAG_ALL_NODATA, TAG_DEFAULT):
            return
        if tag == TAG_DEFAULT_MASK:
            cur.read(_mask_len(h, w))
            return
        if tag == TAG_CONSTANT:
            if cur.u8() > MAX_VALID_QUANT_CODE:
                raise LightPollutionArtifactError("invalid quantization code")
            return
        if tag == TAG_CONSTANT_MASK:
            if cur.u8() > MAX_VALID_QUANT_CODE:
                raise LightPollutionArtifactError("invalid quantization code")
            cur.read(_mask_len(h, w))
            return
        if tag in (TAG_COARSE, TAG_COARSE_MASK):
            factor = cur.u16()
            if factor < 1:
                raise LightPollutionArtifactError("coarse factor must be >= 1")
            gh, gw = _coarse_shape(h, w, factor)
            n = gh * gw
            if n <= 0 or n > len(blob):
                raise LightPollutionArtifactError("invalid node dimensions")
            codes = cur.read(n)
            if any(code > MAX_VALID_QUANT_CODE for code in codes):
                raise LightPollutionArtifactError("invalid quantization code")
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
        raise LightPollutionArtifactError(f"bad tag {tag}")

    walk(root_h, root_w)
    if cur.pos != len(blob):
        raise LightPollutionArtifactError("root blob trailing garbage or incomplete tree")


def _dequantize(code: int, header: ArtifactHeader) -> float:
    return float(header.q_m_min) + float(code) * header.quant_step


def _quantize_pristine(header: ArtifactHeader) -> int:
    step = header.quant_step
    q = (float(header.pristine_default) - float(header.q_m_min)) / step
    return max(0, min(MAX_VALID_QUANT_CODE, _round_ties_away(q)))


def lookup_in_blob(
    blob: _Buffer,
    local_r: int,
    local_c: int,
    root_h: int,
    root_w: int,
    header: ArtifactHeader,
) -> float | None:
    """Return mag/arcsec² or None if unavailable."""
    cur = _Cursor(blob)
    pristine_code = _quantize_pristine(header)

    def walk(h: int, w: int, r: int, c: int) -> float | None:
        tag = cur.u8()
        if tag == TAG_ALL_NODATA:
            return None
        if tag == TAG_DEFAULT:
            return _dequantize(pristine_code, header)
        if tag == TAG_DEFAULT_MASK:
            mask = cur.read(_mask_len(h, w))
            if mask_sample_is_nodata(mask, w, r, c):
                return None
            return _dequantize(pristine_code, header)
        if tag == TAG_CONSTANT:
            code = cur.u8()
            return _dequantize(code, header)
        if tag == TAG_CONSTANT_MASK:
            code = cur.u8()
            mask = cur.read(_mask_len(h, w))
            if mask_sample_is_nodata(mask, w, r, c):
                return None
            return _dequantize(code, header)
        if tag in (TAG_COARSE, TAG_COARSE_MASK):
            factor = cur.u16()
            if factor < 1:
                raise LightPollutionArtifactError("coarse factor must be >= 1")
            gh, gw = _coarse_shape(h, w, factor)
            n = gh * gw
            codes = cur.read(n)
            if tag == TAG_COARSE_MASK:
                mask = cur.read(_mask_len(h, w))
                if mask_sample_is_nodata(mask, w, r, c):
                    return None
            gr = min(r // factor, gh - 1)
            gc = min(c // factor, gw - 1)
            code = codes[gr * gw + gc]
            return _dequantize(code, header)
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
            raise LightPollutionArtifactError("child not found")
        raise LightPollutionArtifactError(f"bad tag {tag}")

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
                raise LightPollutionArtifactError("coarse factor must be >= 1")
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
        raise LightPollutionArtifactError(f"bad tag skip {tag}")

    return walk(root_h, root_w, local_r, local_c)


@dataclass
class LightPollutionArtifact:
    data: bytes
    header: ArtifactHeader
    root_ranges: list[tuple[int, int]]

    @classmethod
    def from_bytes(cls, data: bytes) -> "LightPollutionArtifact":
        payload = bytes(data)
        header = parse_header(payload)
        ranges = validate_root_index(payload, header)
        rc = header.root_cells
        view = memoryview(payload)
        for off, length in ranges:
            validate_tree_structure(view[off : off + length], rc, rc)
        return cls(data=payload, header=header, root_ranges=ranges)

    @classmethod
    def load(cls, path: Path | str) -> "LightPollutionArtifact":
        return cls.from_bytes(Path(path).read_bytes())

    def _root_view(self, root_i: int, root_j: int) -> memoryview:
        h = self.header
        if root_i < 0 or root_i >= h.n_root_cols or root_j < 0 or root_j >= h.n_root_rows:
            raise LightPollutionArtifactError("root out of range")
        idx = root_j * h.n_root_cols + root_i
        blob_off, blob_len = self.root_ranges[idx]
        return memoryview(self.data)[blob_off : blob_off + blob_len]

    def root_blob(self, root_i: int, root_j: int) -> bytes:
        return bytes(self._root_view(root_i, root_j))

    def lookup(self, latitude: float, longitude: float) -> float | None:
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
        try:
            blob = self._root_view(root_i, root_j)
        except LightPollutionArtifactError:
            return None
        try:
            return lookup_in_blob(blob, local_r, local_c, rc, rc, self.header)
        except LightPollutionArtifactError:
            # Structure already validated at load; residual parse errors fail closed.
            return None

    def info(self) -> dict[str, object]:
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
