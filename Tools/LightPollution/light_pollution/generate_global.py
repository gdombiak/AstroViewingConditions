"""Generate production light_pollution_global_v1.bin from source GeoTIFF."""

from __future__ import annotations

import hashlib
import json
import os
import time
from concurrent.futures import ProcessPoolExecutor, wait, FIRST_COMPLETED
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

from .binary_format import (
    ERROR_BUDGET,
    FINEST_CELLS,
    PRISTINE_DEFAULT,
    PROD_U8,
    assemble_artifact,
    encode_tree_node,
)
from .hierarchical import (
    ROOT_CELLS,
    HierarchicalConfig,
    materialize_logical_root,
    n_root_cols,
    n_root_rows,
)
from .hierarchical_optimized import build_root_tree_optimized
from .paths import DEFAULT_SOURCE, OUTPUT
from .quantize import UInt8Params, UInt16Params
from .report import write_json
from .source import inspect_source, open_dataset, require_osgeo


def _worker(payload: dict[str, Any]) -> tuple[int, int, bytes, dict[str, Any]]:
    logical = np.frombuffer(payload["arr"], dtype=np.float32).reshape(payload["shape"])
    u8 = UInt8Params(**payload["u8"])
    cfg = HierarchicalConfig(
        root_cells=ROOT_CELLS,
        finest_cells=FINEST_CELLS,
        error_budget=ERROR_BUDGET,
        policy="error",
        storage="uint8",
        pristine_default=PRISTINE_DEFAULT,
        nodata=payload["nodata"],
        u8=u8,
        u16=UInt16Params(),
        product_bands=[],
    )
    tree = build_root_tree_optimized(logical, cfg)
    blob = encode_tree_node(tree, u8)
    stats = {
        "type": tree.type,
        "ser_bytes": len(blob),
        "tree_ser_bytes_field": tree.ser_bytes,
        "budget_violation": tree.budget_violation,
    }
    return payload["root_i"], payload["root_j"], blob, stats


def generate_global_artifact(
    source: Path = DEFAULT_SOURCE,
    output_path: Path | None = None,
    report_path: Path | None = None,
    workers: int | None = None,
    skip_sha256: bool = False,
) -> dict[str, Any]:
    require_osgeo()
    source = Path(source)
    output_path = Path(output_path or (OUTPUT / "artifacts" / "light_pollution_global_v1.bin"))
    report_path = Path(report_path or (OUTPUT / "artifacts" / "light_pollution_global_v1.manifest.json"))
    output_path.parent.mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    print(f"Inspecting source {source}...", flush=True)
    meta = inspect_source(source, compute_sha256=not skip_sha256)
    if not meta["validation"]["ok"]:
        raise RuntimeError(f"source validation failed: {meta['validation']['issues']}")

    ds = open_dataset(source)
    band = ds.GetRasterBand(1)
    nodata = float(band.GetNoDataValue() or 9.96921e36)
    ni, nj = n_root_cols(), n_root_rows()
    n_roots = ni * nj
    cpu = os.cpu_count() or 4
    if workers is None:
        workers = max(1, min(8, cpu - 1))
    print(f"Encoding {n_roots} roots ({ni}x{nj}) workers={workers}", flush=True)

    u8d = {"m_min": PROD_U8.m_min, "m_max": PROD_U8.m_max, "nodata_code": 255}
    blobs: list[bytes | None] = [None] * n_roots
    type_counts: dict[str, int] = {}
    total_blob = 0
    n_viol = 0

    for j in range(nj):
        row_t0 = time.time()
        payloads = []
        for i in range(ni):
            logical = materialize_logical_root(band, i, j, ROOT_CELLS, nodata)
            payloads.append({
                "root_i": i,
                "root_j": j,
                "arr": logical.tobytes(),
                "shape": logical.shape,
                "nodata": nodata,
                "u8": u8d,
            })
        max_in_flight = max(workers * 2, workers)
        futs = {}
        idx = 0
        results = []
        with ProcessPoolExecutor(max_workers=workers) as ex:
            while idx < len(payloads) or futs:
                while idx < len(payloads) and len(futs) < max_in_flight:
                    fut = ex.submit(_worker, payloads[idx])
                    futs[fut] = idx
                    idx += 1
                if not futs:
                    break
                done, _ = wait(futs.keys(), return_when=FIRST_COMPLETED)
                for fut in done:
                    results.append(fut.result())
                    del futs[fut]
        for root_i, root_j, blob, st in results:
            blobs[root_j * ni + root_i] = blob
            total_blob += len(blob)
            type_counts[st["type"]] = type_counts.get(st["type"], 0) + 1
            if st["budget_violation"]:
                n_viol += 1
        print(f"  root row {j+1}/{nj} in {time.time()-row_t0:.1f}s", flush=True)

    if any(b is None for b in blobs):
        raise RuntimeError("missing root blobs")
    artifact = assemble_artifact([b for b in blobs if b is not None])
    tmp = output_path.with_suffix(output_path.suffix + ".tmp")
    tmp.write_bytes(artifact)
    tmp.replace(output_path)

    sha = hashlib.sha256(artifact).hexdigest()
    elapsed = time.time() - t0
    manifest = {
        "artifact": str(output_path),
        "artifact_bytes": len(artifact),
        "artifact_mib": len(artifact) / (1024 * 1024),
        "artifact_sha256": sha,
        "format": "LPATLAS1",
        "format_version": 1,
        "algorithm": "hierarchical_adaptive_uint8_budget0.1_error_cap0.025",
        "root_cells": ROOT_CELLS,
        "finest_cells": FINEST_CELLS,
        "error_budget": ERROR_BUDGET,
        "pristine_default": PRISTINE_DEFAULT,
        "quantization": PROD_U8.to_dict(),
        "n_roots": n_roots,
        "sum_root_blob_bytes": total_blob,
        "root_type_counts": type_counts,
        "n_root_budget_violations": n_viol,
        "source": {
            "path": str(source.resolve()),
            "name": source.name,
            "size_bytes": meta["size_bytes"],
            "sha256": meta.get("sha256"),
            "width": meta["width"],
            "height": meta["height"],
            "nodata": meta["nodata"],
            "geotransform": meta["geotransform"],
            "gdal_version": meta.get("gdal_version"),
        },
        "generation": {
            "elapsed_sec": elapsed,
            "workers": workers,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "tool": "light_pollution.generate_global",
        },
        "attribution": {
            "author": "David Lorenz",
            "site": "https://djlorenz.github.io/astronomy/lp/",
            "permission": "Explicit permission to use work and TIFF files was obtained from the author.",
            "note": "This derived binary does not itself grant redistribution rights to third parties.",
        },
        "census_estimate_mib": 9.61,
        "size_vs_census_note": (
            "Compare artifact_mib to prior hierarchical census estimate (~9.61 MiB). "
            "Differences may arise from actual DFS payload vs cost model (masks, coarse grids)."
        ),
    }
    write_json(report_path, manifest)
    print(f"Wrote {output_path} ({len(artifact)} bytes, {manifest['artifact_mib']:.3f} MiB) in {elapsed:.1f}s", flush=True)
    print(f"Manifest {report_path}", flush=True)
    return manifest
