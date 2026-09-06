"""Error metrics and product-band helpers."""

from __future__ import annotations

from typing import Any

import numpy as np

from .nodata import DEFAULT_NODATA, is_nodata, valid_mask


THRESHOLDS = (0.02, 0.05, 0.10, 0.20, 0.30)


def compute_error_metrics(
    original: np.ndarray,
    candidate: np.ndarray,
    nodata: float = DEFAULT_NODATA,
) -> dict[str, Any]:
    o = np.asarray(original, dtype=np.float64)
    c = np.asarray(candidate, dtype=np.float64)
    if o.shape != c.shape:
        raise ValueError(f"Shape mismatch: {o.shape} vs {c.shape}")

    o_nd = is_nodata(o, nodata)
    c_nd = is_nodata(c, nodata)
    both_valid = ~o_nd & ~c_nd
    nodata_disagreement = int(np.sum(o_nd != c_nd))

    result: dict[str, Any] = {
        "n_total": int(o.size),
        "n_both_valid": int(np.sum(both_valid)),
        "n_original_valid": int(np.sum(~o_nd)),
        "n_candidate_valid": int(np.sum(~c_nd)),
        "nodata_disagreement_count": nodata_disagreement,
    }

    if not np.any(both_valid):
        result.update(
            {
                "mean_signed_error": None,
                "mae": None,
                "median_ae": None,
                "rmse": None,
                "p90_ae": None,
                "p95_ae": None,
                "p99_ae": None,
                "max_ae": None,
                "pct_within": {f"{thr:.2f}": None for thr in THRESHOLDS},
            }
        )
        return result

    err = c[both_valid] - o[both_valid]
    ae = np.abs(err)
    result["mean_signed_error"] = float(np.mean(err))
    result["mae"] = float(np.mean(ae))
    result["median_ae"] = float(np.median(ae))
    result["rmse"] = float(np.sqrt(np.mean(err ** 2)))
    result["p90_ae"] = float(np.percentile(ae, 90))
    result["p95_ae"] = float(np.percentile(ae, 95))
    result["p99_ae"] = float(np.percentile(ae, 99))
    result["max_ae"] = float(np.max(ae))
    pct = {}
    n = ae.size
    for thr in THRESHOLDS:
        pct[f"{thr:.2f}"] = float(100.0 * np.sum(ae <= thr) / n)
    result["pct_within"] = pct
    return result


def assign_product_band(mag: float, bands: list[dict[str, Any]], nodata: float = DEFAULT_NODATA) -> str | None:
    if mag is None or not np.isfinite(mag) or abs(mag) >= 1e30 or mag == nodata:
        return None
    for b in bands:
        lo = b.get("min_mag")
        hi = b.get("max_mag")
        if lo is None and hi is not None and mag < hi:
            return b["id"]
        if hi is None and lo is not None and mag >= lo:
            return b["id"]
        if lo is not None and hi is not None and lo <= mag < hi:
            return b["id"]
    return None


def band_agreement(
    original: np.ndarray,
    candidate: np.ndarray,
    bands: list[dict[str, Any]],
    nodata: float = DEFAULT_NODATA,
) -> dict[str, Any]:
    o = np.asarray(original).ravel()
    c = np.asarray(candidate).ravel()
    both = valid_mask(o, nodata) & valid_mask(c, nodata)
    if not np.any(both):
        return {"n": 0, "agree": 0, "agree_pct": None}
    ob = [assign_product_band(float(x), bands, nodata) for x in o[both]]
    cb = [assign_product_band(float(x), bands, nodata) for x in c[both]]
    agree = sum(1 for a, b in zip(ob, cb) if a == b)
    n = len(ob)
    return {"n": n, "agree": agree, "agree_pct": 100.0 * agree / n}



def top_absolute_errors(
    original: np.ndarray,
    candidate: np.ndarray,
    grid,
    bands: list[dict[str, Any]] | None = None,
    nodata: float = DEFAULT_NODATA,
    n: int = 20,
) -> list[dict[str, Any]]:
    """Top-n cells by absolute error with lon/lat and product-band change."""
    o = np.asarray(original, dtype=np.float64)
    c = np.asarray(candidate, dtype=np.float64)
    o_nd = is_nodata(o, nodata)
    c_nd = is_nodata(c, nodata)
    both = ~o_nd & ~c_nd
    if not np.any(both):
        return []
    ae = np.abs(c - o)
    ae_masked = np.where(both, ae, -1.0)
    flat = ae_masked.ravel()
    # top n indices
    if flat.size <= n:
        idx = np.argsort(flat)[::-1]
        idx = idx[flat[idx] >= 0]
    else:
        idx = np.argpartition(flat, -n)[-n:]
        idx = idx[np.argsort(flat[idx])[::-1]]
        idx = idx[flat[idx] >= 0]
    h, w = o.shape
    rows = []
    for k in idx[:n]:
        r = int(k // w)
        col = int(k % w)
        lon, lat = grid.cell_center(r, col)
        ov = float(o[r, col])
        cv = float(c[r, col])
        ob = assign_product_band(ov, bands or [], nodata) if bands else None
        cb = assign_product_band(cv, bands or [], nodata) if bands else None
        rows.append({
            "rank": len(rows) + 1,
            "row": r,
            "col": col,
            "lon": lon,
            "lat": lat,
            "original": ov,
            "candidate": cv,
            "signed_error": cv - ov,
            "abs_error": abs(cv - ov),
            "original_band": ob,
            "candidate_band": cb,
            "band_changed": ob != cb if (ob is not None or cb is not None) else None,
        })
    return rows
