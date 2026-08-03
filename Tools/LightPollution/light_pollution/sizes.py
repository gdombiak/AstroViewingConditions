"""Oregon actual sizes and exact global uniform dimensions/payloads."""

from __future__ import annotations

from typing import Any

# Source atlas dimensions (confirmed 2025)
GLOBAL_WIDTH = 43200
GLOBAL_HEIGHT = 16801
GLOBAL_CELLS = GLOBAL_WIDTH * GLOBAL_HEIGHT


def reduced_dimensions(width: int, height: int, factor: int) -> tuple[int, int]:
    """Output size after integer block reduction, dropping leftover edge rows/cols.

    Matches block_reduce / reduce_array policy: out = floor(dim / factor).
    For the 2025 atlas, height 16801 is not divisible by 3, 6, or 12 — the
    final incomplete source row block is dropped.
    """
    if factor < 1:
        raise ValueError("factor must be >= 1")
    return width // factor, height // factor


def global_reduced_dimensions(factor: int) -> tuple[int, int]:
    return reduced_dimensions(GLOBAL_WIDTH, GLOBAL_HEIGHT, factor)


def bytes_to_mib(n: int | float) -> float:
    return float(n) / (1024.0 * 1024.0)


def uniform_global_size_exact(
    factor: int,
    bytes_per_cell: int,
    metadata_overhead: int = 4096,
    index_overhead: int = 0,
) -> dict[str, Any]:
    """Exact global payload from source dims + reduction factor + dtype width.

    Does **not** ratio-scale from Oregon. Oregon and global leftover-edge
    behavior both use floor division; global height leftover is explicit.
    """
    out_w, out_h = global_reduced_dimensions(factor)
    n_cells = out_w * out_h
    payload = n_cells * bytes_per_cell
    total = payload + metadata_overhead + index_overhead
    leftover_rows = GLOBAL_HEIGHT - out_h * factor
    leftover_cols = GLOBAL_WIDTH - out_w * factor
    return {
        "kind": "uniform_exact_from_source_dims",
        "reliability": "exact",
        "source_width": GLOBAL_WIDTH,
        "source_height": GLOBAL_HEIGHT,
        "factor": factor,
        "output_width": out_w,
        "output_height": out_h,
        "output_cells": n_cells,
        "bytes_per_cell": bytes_per_cell,
        "payload_bytes": payload,
        "metadata_overhead_bytes": metadata_overhead,
        "index_overhead_bytes": index_overhead,
        "total_bytes": total,
        "payload_mib": bytes_to_mib(payload),
        "total_mib": bytes_to_mib(total),
        "leftover_source_rows_dropped": leftover_rows,
        "leftover_source_cols_dropped": leftover_cols,
        "note": (
            "Exact cell counts from floor(source_dim/factor). "
            "Not ratio-scaled from a regional crop."
        ),
    }


def uniform_region_payload(width: int, height: int, factor: int, bytes_per_cell: int) -> dict[str, Any]:
    out_w, out_h = reduced_dimensions(width, height, factor)
    n = out_w * out_h
    payload = n * bytes_per_cell
    return {
        "output_width": out_w,
        "output_height": out_h,
        "output_cells": n,
        "payload_bytes": payload,
        "payload_mib": bytes_to_mib(payload),
        "bytes_per_cell": bytes_per_cell,
        "factor": factor,
    }


def sparse_global_size_preliminary(
    oregon_stats: dict[str, Any],
    oregon_cells: int,
) -> dict[str, Any]:
    """Preliminary only — Oregon tile mix is not a reliable final global estimate."""
    scale = GLOBAL_CELLS / max(oregon_cells, 1)
    oregon_total = int(oregon_stats.get("total_estimated_bytes", 0))
    return {
        "kind": "sparse_or_adaptive_preliminary",
        "reliability": "preliminary_only",
        "warning": (
            "Oregon tile-type distribution is NOT a sufficiently reliable final global-size "
            "estimate for sparse/adaptive formats. Prefer streaming quantized adaptive census."
        ),
        "oregon_total_estimated_bytes": oregon_total,
        "oregon_total_mib": bytes_to_mib(oregon_total),
        "naive_scaled_global_bytes": int(round(oregon_total * scale)),
        "naive_scaled_global_mib": bytes_to_mib(oregon_total * scale),
        "scale_factor": scale,
        "mode_or_level_counts_oregon": oregon_stats.get("mode_counts") or oregon_stats.get("level_counts"),
    }


def size_report_fields(size: dict[str, Any]) -> dict[str, Any]:
    """Normalize display fields for summaries."""
    total = size.get("total_bytes") or size.get("estimated_global_total_bytes") or size.get("naive_scaled_global_bytes")
    payload = size.get("payload_bytes") or size.get("estimated_global_payload_bytes")
    return {
        "global_total_bytes": total,
        "global_total_mib": bytes_to_mib(total) if total is not None else None,
        "global_payload_bytes": payload,
        "global_payload_mib": bytes_to_mib(payload) if payload is not None else None,
        "reliability": size.get("reliability") or size.get("kind"),
        "output_width": size.get("output_width"),
        "output_height": size.get("output_height"),
    }
