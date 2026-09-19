"""Quantization and reconstruction for magnitude rasters."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from .nodata import DEFAULT_NODATA, is_nodata, valid_mask


@dataclass(frozen=True)
class UInt16Params:
    m_min: float = 16.0
    step: float = 0.01
    nodata_code: int = 65535

    @property
    def max_code(self) -> int:
        return 65534

    def theoretical_max_error(self) -> float:
        return self.step / 2.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": "uint16",
            "m_min": self.m_min,
            "step": self.step,
            "nodata_code": self.nodata_code,
            "max_valid_code": self.max_code,
            "m_max_representable": self.m_min + self.step * self.max_code,
            "theoretical_max_abs_error": self.theoretical_max_error(),
        }


@dataclass(frozen=True)
class UInt8Params:
    m_min: float = 16.0
    m_max: float = 22.5
    nodata_code: int = 255

    @property
    def max_code(self) -> int:
        return 254

    def step(self) -> float:
        return (self.m_max - self.m_min) / self.max_code

    def theoretical_max_error(self) -> float:
        return self.step() / 2.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": "uint8",
            "m_min": self.m_min,
            "m_max": self.m_max,
            "nodata_code": self.nodata_code,
            "max_valid_code": self.max_code,
            "step": self.step(),
            "theoretical_max_abs_error": self.theoretical_max_error(),
            "mapping": f"code c in 0..{self.max_code} -> m = m_min + c * (m_max-m_min)/{self.max_code}; {self.nodata_code}=NoData",
        }


def quantize_uint16(
    arr: np.ndarray,
    params: UInt16Params | None = None,
    nodata: float = DEFAULT_NODATA,
) -> tuple[np.ndarray, dict[str, Any]]:
    params = params or UInt16Params()
    a = np.asarray(arr, dtype=np.float64)
    valid = valid_mask(a, nodata)
    codes = np.full(a.shape, params.nodata_code, dtype=np.uint16)
    if np.any(valid):
        q = np.rint((a[valid] - params.m_min) / params.step)
        below = q < 0
        above = q > params.max_code
        clip_low = int(np.sum(below))
        clip_high = int(np.sum(above))
        q = np.clip(q, 0, params.max_code)
        codes[valid] = q.astype(np.uint16)
    else:
        clip_low = clip_high = 0
    meta = params.to_dict()
    meta["clip_low_count"] = clip_low
    meta["clip_high_count"] = clip_high
    meta["clip_total"] = clip_low + clip_high
    meta["valid_count"] = int(np.sum(valid))
    return codes, meta


def dequantize_uint16(
    codes: np.ndarray,
    params: UInt16Params | None = None,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    params = params or UInt16Params()
    c = np.asarray(codes)
    out = np.full(c.shape, nodata, dtype=np.float32)
    valid = c != params.nodata_code
    out[valid] = (params.m_min + c[valid].astype(np.float64) * params.step).astype(np.float32)
    return out


def quantize_uint8(
    arr: np.ndarray,
    params: UInt8Params | None = None,
    nodata: float = DEFAULT_NODATA,
) -> tuple[np.ndarray, dict[str, Any]]:
    params = params or UInt8Params()
    a = np.asarray(arr, dtype=np.float64)
    valid = valid_mask(a, nodata)
    codes = np.full(a.shape, params.nodata_code, dtype=np.uint8)
    step = params.step()
    clip_low = clip_high = 0
    if np.any(valid):
        q = np.rint((a[valid] - params.m_min) / step)
        below = q < 0
        above = q > params.max_code
        clip_low = int(np.sum(below))
        clip_high = int(np.sum(above))
        q = np.clip(q, 0, params.max_code)
        codes[valid] = q.astype(np.uint8)
    meta = params.to_dict()
    meta["clip_low_count"] = clip_low
    meta["clip_high_count"] = clip_high
    meta["clip_total"] = clip_low + clip_high
    meta["valid_count"] = int(np.sum(valid))
    return codes, meta


def dequantize_uint8(
    codes: np.ndarray,
    params: UInt8Params | None = None,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    params = params or UInt8Params()
    c = np.asarray(codes)
    out = np.full(c.shape, nodata, dtype=np.float32)
    valid = c != params.nodata_code
    step = params.step()
    out[valid] = (params.m_min + c[valid].astype(np.float64) * step).astype(np.float32)
    return out
