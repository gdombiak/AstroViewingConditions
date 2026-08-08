"""Packed NoData mask encode/decode and byte accounting."""

from __future__ import annotations

import numpy as np


def packed_mask_nbytes(n_cells: int) -> int:
    """Bytes for a packed bit mask of n_cells bits (MSB-first packbits)."""
    return (int(n_cells) + 7) // 8


def pack_nodata_mask(inv: np.ndarray) -> bytes:
    """Pack boolean NoData mask (True = NoData) with np.packbits."""
    flat = np.asarray(inv, dtype=bool).ravel()
    return np.packbits(flat.astype(np.uint8)).tobytes()


def unpack_nodata_mask(data: bytes, shape: tuple[int, int]) -> np.ndarray:
    """Unpack packbits mask to boolean array of shape (True = NoData)."""
    h, w = shape
    n = h * w
    arr = np.frombuffer(data, dtype=np.uint8)
    bits = np.unpackbits(arr)[:n]
    return bits.reshape(shape).astype(bool)


def mask_payload_bytes(inv: np.ndarray | None, has_mixed: bool) -> int:
    if not has_mixed or inv is None:
        return 0
    return packed_mask_nbytes(int(np.asarray(inv).size))
