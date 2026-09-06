"""Serialization byte-cost models for hierarchical adaptive trees."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

from .masks import packed_mask_nbytes

Storage = Literal["uint8", "uint16"]


@dataclass(frozen=True)
class SerConfig:
    node_tag_bytes: int = 1
    header_bytes: int = 256
    root_index_entry_bytes: int = 20
    mode: str = "dfs_inline"  # or offset_tree


def bpc(storage: Storage) -> int:
    return 1 if storage == "uint8" else 2


def cost_all_nodata(ser: SerConfig) -> int:
    return ser.node_tag_bytes


def cost_default_or_constant(ser: SerConfig, storage: Storage, mixed_mask: bool, n_cells: int) -> int:
    c = ser.node_tag_bytes + bpc(storage)
    if mixed_mask:
        c += packed_mask_nbytes(n_cells)
    return c


def cost_coarse_grid(ser: SerConfig, storage: Storage, n_grid_cells: int) -> int:
    # tag + level_id(1) + payload
    return ser.node_tag_bytes + 1 + n_grid_cells * bpc(storage)


def cost_children_tag(ser: SerConfig) -> int:
    if ser.mode == "offset_tree":
        # tag + 4 * u32 offsets
        return ser.node_tag_bytes + 16
    return ser.node_tag_bytes


def root_index_bytes(n_roots: int, ser: SerConfig) -> int:
    return n_roots * ser.root_index_entry_bytes


def total_global_bytes(sum_root_blobs: int, n_roots: int, ser: SerConfig) -> dict[str, Any]:
    idx = root_index_bytes(n_roots, ser)
    total = ser.header_bytes + idx + sum_root_blobs
    return {
        "header_bytes": ser.header_bytes,
        "root_index_bytes": idx,
        "payload_tree_bytes": sum_root_blobs,
        "total_bytes": total,
        "serialization": ser.mode,
        "n_roots": n_roots,
    }
