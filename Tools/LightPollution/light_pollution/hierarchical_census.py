"""Streaming worldwide hierarchical census with multi-variant cache + multiprocessing."""

from __future__ import annotations

import json
import os
import time
from concurrent.futures import FIRST_COMPLETED, ProcessPoolExecutor, wait
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

from .hierarchical import (
    GLOBAL_HEIGHT,
    GLOBAL_WIDTH,
    ROOT_CELLS,
    materialize_logical_root,
    n_root_cols,
    n_root_rows,
)
from .hierarchical_optimized import analyze_root_multi_variant
from .hierarchical_serialize import SerConfig, total_global_bytes
from .paths import CONFIG, OUTPUT
from .quantize import UInt8Params, UInt16Params
from .report import write_json
from .sizes import bytes_to_mib
from .source import open_dataset, require_osgeo


def default_variants() -> list[dict[str, Any]]:
    variants = []
    for st in ("uint8",):
        for b in (0.05, 0.10, 0.20):
            for pol in ("error", "product"):
                for fin, cap in ((3, "0.025"), (6, "0.05")):
                    variants.append({
                        "key": f"{st}_budget{b}_{pol}_cap{cap}",
                        "storage": st,
                        "budget": b,
                        "policy": pol,
                        "finest_cells": fin,
                    })
    variants.append({
        "key": "uint16_budget0.1_error_cap0.025",
        "storage": "uint16",
        "budget": 0.10,
        "policy": "error",
        "finest_cells": 3,
    })
    return variants


def _worker_root(payload: dict[str, Any]) -> dict[str, Any]:
    """Process one root in a worker (no GDAL)."""
    logical = np.frombuffer(payload["arr"], dtype=np.float32).reshape(payload["shape"])
    u8 = UInt8Params(**payload["u8"])
    u16 = UInt16Params(**payload["u16"])
    stats = analyze_root_multi_variant(
        logical,
        payload["variants"],
        nodata=payload["nodata"],
        pristine=payload["pristine"],
        u8=u8,
        u16=u16,
        product_bands=payload["bands"],
    )
    return {
        "root_i": payload["root_i"],
        "root_j": payload["root_j"],
        "stats": stats,
    }


def _atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2, default=str) + "\n")
    tmp.replace(path)


def run_hierarchical_world_census(
    source: Path,
    variants: list[dict[str, Any]] | None = None,
    pristine_default: float = 22.0,
    u8: UInt8Params | None = None,
    u16: UInt16Params | None = None,
    product_bands: list | None = None,
    out_path: Path | None = None,
    workers: int | None = None,
    max_in_flight: int | None = None,
    checkpoint_dir: Path | None = None,
    resume: bool = True,
    row_start: int = 0,
    row_end: int | None = None,
) -> dict[str, Any]:
    require_osgeo()
    variants = variants or default_variants()
    u8 = u8 or UInt8Params(m_min=13.01, m_max=22.5)
    u16 = u16 or UInt16Params()
    if product_bands is None:
        product_bands = json.loads((CONFIG / "product_bands.json").read_text())["bands"]

    ds = open_dataset(source)
    band = ds.GetRasterBand(1)
    nodata = float(band.GetNoDataValue() or 9.96921e36)
    rc = ROOT_CELLS
    ni, nj = n_root_cols(rc), n_root_rows(rc)
    n_roots = ni * nj
    if row_end is None:
        row_end = nj

    cpu = os.cpu_count() or 4
    if workers is None:
        workers = max(1, min(8, cpu - 1))
    if max_in_flight is None:
        max_in_flight = max(workers * 2, workers)

    checkpoint_dir = checkpoint_dir or (OUTPUT / "hierarchical_census_checkpoint")
    checkpoint_dir.mkdir(parents=True, exist_ok=True)

    # acc[variant_key]
    acc: dict[str, dict[str, Any]] = {
        v["key"]: {
            "sum_blob_bytes": 0,
            "type_counts": {},
            "level_side_counts": {},
            "n_violating_leaves": 0,
            "n_leaves": 0,
            "max_depth_max": 0,
            "n_roots_done": 0,
        }
        for v in variants
    }

    # resume: load completed rows
    done_rows: set[int] = set()
    if resume:
        for p in sorted(checkpoint_dir.glob("row_*.json")):
            try:
                j = int(p.stem.split("_")[1])
                data = json.loads(p.read_text())
                if data.get("complete") and data.get("variants_keys") == [v["key"] for v in variants]:
                    done_rows.add(j)
                    for k, s in data["acc_delta"].items():
                        if k not in acc:
                            continue
                        a = acc[k]
                        a["sum_blob_bytes"] += s["sum_blob_bytes"]
                        a["n_violating_leaves"] += s["n_violating_leaves"]
                        a["n_leaves"] += s["n_leaves"]
                        a["max_depth_max"] = max(a["max_depth_max"], s["max_depth_max"])
                        a["n_roots_done"] += s["n_roots_done"]
                        for t, c in s["type_counts"].items():
                            a["type_counts"][t] = a["type_counts"].get(t, 0) + c
                        for lv, c in s["level_side_counts"].items():
                            a["level_side_counts"][lv] = a["level_side_counts"].get(lv, 0) + c
            except Exception as e:
                print(f"  skip checkpoint {p}: {e}", flush=True)

    print(
        f"Hierarchical world census roots={ni}x{nj}={n_roots} variants={len(variants)} "
        f"workers={workers} in_flight={max_in_flight} resume_rows={sorted(done_rows)}",
        flush=True,
    )

    u8d = {"m_min": u8.m_min, "m_max": u8.m_max, "nodata_code": u8.nodata_code}
    u16d = {"m_min": u16.m_min, "step": u16.step, "nodata_code": u16.nodata_code}

    t0 = time.time()
    roots_processed = 0

    for j in range(row_start, row_end):
        if j in done_rows:
            print(f"  root row {j+1}/{nj} (checkpoint skip)", flush=True)
            continue
        row_t0 = time.time()
        # materialize all roots in this row (parent GDAL reads)
        payloads = []
        for i in range(ni):
            logical = materialize_logical_root(band, i, j, rc, nodata)
            payloads.append({
                "root_i": i,
                "root_j": j,
                "arr": logical.tobytes(),
                "shape": logical.shape,
                "nodata": nodata,
                "pristine": pristine_default,
                "u8": u8d,
                "u16": u16d,
                "bands": product_bands,
                "variants": variants,
            })

        row_results: list[dict] = []
        with ProcessPoolExecutor(max_workers=workers) as ex:
            # bounded submit
            futs = {}
            idx = 0
            while idx < len(payloads) or futs:
                while idx < len(payloads) and len(futs) < max_in_flight:
                    fut = ex.submit(_worker_root, payloads[idx])
                    futs[fut] = payloads[idx]["root_i"]
                    idx += 1
                if not futs:
                    break
                # wait for any
                done, _ = wait(futs.keys(), return_when=FIRST_COMPLETED)
                for fut in done:
                    row_results.append(fut.result())
                    del futs[fut]

        # deterministic merge by root_i
        row_results.sort(key=lambda r: r["root_i"])
        row_delta = {
            v["key"]: {
                "sum_blob_bytes": 0,
                "type_counts": {},
                "level_side_counts": {},
                "n_violating_leaves": 0,
                "n_leaves": 0,
                "max_depth_max": 0,
                "n_roots_done": 0,
            }
            for v in variants
        }
        for res in row_results:
            for k, st in res["stats"].items():
                for bucket in (acc[k], row_delta[k]):
                    bucket["sum_blob_bytes"] += st["ser_bytes"]
                    bucket["n_violating_leaves"] += st["budget_violating_leaves"]
                    bucket["n_leaves"] += st["n_leaves"]
                    bucket["max_depth_max"] = max(bucket["max_depth_max"], st["max_depth"])
                    bucket["n_roots_done"] += 1
                    for t, c in st["type_counts"].items():
                        bucket["type_counts"][t] = bucket["type_counts"].get(t, 0) + c
                    for lv, c in st["level_side_counts"].items():
                        bucket["level_side_counts"][lv] = bucket["level_side_counts"].get(lv, 0) + c
            roots_processed += 1

        _atomic_write_json(
            checkpoint_dir / f"row_{j}.json",
            {
                "complete": True,
                "root_j": j,
                "variants_keys": [v["key"] for v in variants],
                "acc_delta": row_delta,
                "elapsed_row_sec": time.time() - row_t0,
            },
        )
        elapsed = time.time() - t0
        rows_done = j - row_start + 1
        # estimate remaining
        remaining_rows = sum(1 for jj in range(j + 1, row_end) if jj not in done_rows)
        sec_per_row = elapsed / max(len([jj for jj in range(row_start, j + 1) if jj not in done_rows] or [1]), 1)
        print(
            f"  root row {j+1}/{nj} done in {time.time()-row_t0:.1f}s "
            f"(~{sec_per_row:.1f}s/row, ETA {remaining_rows*sec_per_row/60:.1f} min)",
            flush=True,
        )

    ser = SerConfig()
    results = {}
    for k, a in acc.items():
        tot = total_global_bytes(a["sum_blob_bytes"], n_roots, ser)
        results[k] = {
            **a,
            **tot,
            "total_mib": bytes_to_mib(tot["total_bytes"]),
            "payload_mib": bytes_to_mib(a["sum_blob_bytes"]),
            "meets_configured_budget": a["n_violating_leaves"] == 0,
            "pct_violating_leaves": 100.0 * a["n_violating_leaves"] / max(a["n_leaves"], 1),
        }

    out = {
        "kind": "hierarchical_adaptive_world_census",
        "reliability": "census_shared_builder_multiprocess",
        "root_cells": rc,
        "n_root_cols": ni,
        "n_root_rows": nj,
        "n_roots": n_roots,
        "source_width": GLOBAL_WIDTH,
        "source_height": GLOBAL_HEIGHT,
        "workers": workers,
        "variants": results,
        "elapsed_sec": time.time() - t0,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "note": (
            "Same min-byte hierarchical builder as Oregon (optimized multi-variant precompute). "
            "GDAL reads in parent; workers analyze roots. Deterministic merge by (root_j, root_i)."
        ),
    }
    out_path = out_path or (OUTPUT / "world_hierarchical_census.json")
    write_json(out_path, out)
    print("Wrote", out_path, flush=True)
    return out


def benchmark_hierarchical_row(
    source: Path,
    root_j: int = 4,
    workers: int | None = None,
    pristine_default: float = 22.0,
    u8: UInt8Params | None = None,
    u16: UInt16Params | None = None,
    product_bands: list | None = None,
) -> dict[str, Any]:
    """Benchmark one root row; estimate full-world time; run equivalence on samples."""
    require_osgeo()
    variants = default_variants()
    u8 = u8 or UInt8Params(m_min=13.01, m_max=22.5)
    u16 = u16 or UInt16Params()
    if product_bands is None:
        product_bands = json.loads((CONFIG / "product_bands.json").read_text())["bands"]

    cpu = os.cpu_count() or 4
    if workers is None:
        workers = max(1, min(8, cpu - 1))

    # Equivalence on synthetic + real 96×96 crops (full 768 reference is too slow for bench)
    from .hierarchical import HierarchicalConfig, build_tree_for_block, materialize_logical_root, tree_stats
    from .hierarchical_optimized import build_root_tree_optimized, trees_equivalent, topology_signature

    ds = open_dataset(source)
    band = ds.GetRasterBand(1)
    nodata = float(band.GetNoDataValue() or 9.96921e36)
    rc = ROOT_CELLS
    ni = n_root_cols(rc)
    nj = n_root_rows(rc)

    eq_ok = 0
    eq_fail = 0
    sample_variants = [
        {"storage": "uint8", "budget": 0.10, "policy": "error", "finest_cells": 3},
        {"storage": "uint8", "budget": 0.05, "policy": "product", "finest_cells": 6},
        {"storage": "uint16", "budget": 0.10, "policy": "error", "finest_cells": 3},
    ]
    # synthetic
    for a in (
        np.full((48, 48), 22.0, dtype=np.float32),
        (lambda x: (x.__setitem__((slice(4, 12), slice(4, 12)), 18.0) or x))(np.full((48, 48), 22.0, dtype=np.float32)),
    ):
        for sv in sample_variants:
            cfg = HierarchicalConfig(
                root_cells=a.shape[0],
                finest_cells=sv["finest_cells"],
                error_budget=sv["budget"],
                policy=sv["policy"],  # type: ignore
                storage=sv["storage"],  # type: ignore
                pristine_default=pristine_default,
                nodata=nodata,
                u8=u8,
                u16=u16,
                product_bands=product_bands,
            )
            ref = build_tree_for_block(a, 0, 0, cfg)
            opt = build_root_tree_optimized(a, cfg)
            if trees_equivalent(ref, opt) and tree_stats(ref)["type_counts"] == tree_stats(opt)["type_counts"]:
                eq_ok += 1
            else:
                eq_fail += 1
                print(f"EQ FAIL synthetic {sv}", flush=True)
    # real 96×96 corner crops from three roots
    for i in (0, ni // 2, ni - 1):
        logical = materialize_logical_root(band, i, root_j, rc, nodata)
        crop = logical[:96, :96].copy()
        for sv in sample_variants:
            cfg = HierarchicalConfig(
                root_cells=96,
                finest_cells=sv["finest_cells"],
                error_budget=sv["budget"],
                policy=sv["policy"],  # type: ignore
                storage=sv["storage"],  # type: ignore
                pristine_default=pristine_default,
                nodata=nodata,
                u8=u8,
                u16=u16,
                product_bands=product_bands,
            )
            ref = build_tree_for_block(crop, 0, 0, cfg)
            opt = build_root_tree_optimized(crop, cfg)
            if trees_equivalent(ref, opt) and tree_stats(ref)["type_counts"] == tree_stats(opt)["type_counts"]:
                eq_ok += 1
            else:
                eq_fail += 1
                print(
                    f"EQ FAIL crop root ({i},{root_j}) {sv}: "
                    f"ref_bytes={ref.ser_bytes} opt_bytes={opt.ser_bytes}",
                    flush=True,
                )
    print(f"Equivalence checks: ok={eq_ok} fail={eq_fail}", flush=True)

    # time one full row with workers (no resume)
    t0 = time.time()
    # Use internal one-row by calling run with row_start/end
    tmp_ckpt = OUTPUT / "hierarchical_bench_ckpt"
    # clear
    import shutil
    if tmp_ckpt.exists():
        shutil.rmtree(tmp_ckpt)
    run_hierarchical_world_census(
        source,
        variants=variants,
        pristine_default=pristine_default,
        u8=u8,
        u16=u16,
        product_bands=product_bands,
        out_path=OUTPUT / "hierarchical_bench_row.json",
        workers=workers,
        checkpoint_dir=tmp_ckpt,
        resume=False,
        row_start=root_j,
        row_end=root_j + 1,
    )
    elapsed = time.time() - t0
    sec_per_root = elapsed / ni
    est_full = sec_per_root * ni * nj

    report = {
        "workers": workers,
        "cpu_count": cpu,
        "root_j": root_j,
        "roots_processed": ni,
        "variants": len(variants),
        "elapsed_sec": elapsed,
        "seconds_per_root": sec_per_root,
        "estimated_full_world_sec": est_full,
        "estimated_full_world_min": est_full / 60,
        "equivalence_ok": eq_ok,
        "equivalence_fail": eq_fail,
        "memory_note": "Peak not sampled; each worker holds one 768² float32 (~2.25 MiB) plus analysis.",
    }
    write_json(OUTPUT / "hierarchical_benchmark.json", report)
    print(json.dumps(report, indent=2), flush=True)
    return report
