"""Report writing helpers."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, default=_default) + "\n")


def _default(o: Any) -> Any:
    if hasattr(o, "item"):
        try:
            return o.item()
        except Exception:
            pass
    return str(o)


def write_markdown_summary(path: Path, summary: dict[str, Any]) -> None:
    lines = [
        "# Light Pollution Oregon Validation Report",
        "",
        f"Generated: {summary.get('generated_at', '')}",
        "",
        "## Provenance",
        "",
        "```json",
        json.dumps(summary.get("provenance", {}), indent=2, default=str)[:4000],
        "```",
        "",
        "## Picks",
        "",
        "```json",
        json.dumps(summary.get("picks", {}), indent=2),
        "```",
        "",
        "## Leading candidates",
        "",
        "| ID | MAE | P95 | max AE | Oregon MiB | Global MiB | Reliability | Worst lon/lat |",
        "|----|-----|-----|--------|------------|------------|-------------|---------------|",
    ]
    for L in summary.get("leaders", []):
        lines.append(
            f"| `{L.get('id')}` | {L.get('mae')} | {L.get('p95_ae')} | {L.get('max_ae')} | "
            f"{L.get('oregon_mib')} | {L.get('global_mib')} | {L.get('global_reliability')} | "
            f"{L.get('worst_error_lonlat')} |"
        )
    lines.extend(["", "## Top absolute-error cells (per leader)", ""])
    top = summary.get("top_errors") or {}
    for L in summary.get("leaders", [])[:6]:
        cid = L.get("id")
        rows = top.get(cid) or []
        lines.append(f"### `{cid}`")
        lines.append("")
        lines.append("| Rank | Lon | Lat | Original | Candidate | Abs err | Bands |")
        lines.append("|------|-----|-----|----------|-----------|---------|-------|")
        for r in rows[:20]:
            lines.append(
                f"| {r.get('rank')} | {r.get('lon'):.5f} | {r.get('lat'):.5f} | "
                f"{r.get('original'):.4f} | {r.get('candidate'):.4f} | {r.get('abs_error'):.4f} | "
                f"{r.get('original_band')}→{r.get('candidate_band')} |"
            )
        lines.append("")
    lines.extend(["", "## All candidates", ""])
    for c in summary.get("candidates", []):
        m = c.get("metrics") or {}
        g = c.get("global_size_summary") or {}
        lines.append(f"### `{c.get('id')}`")
        lines.append("")
        lines.append(f"- Family: {c.get('family')}")
        lines.append(
            f"- MAE: {m.get('mae')}  P95: {m.get('p95_ae')}  P99: {m.get('p99_ae')}  max AE: {m.get('max_ae')}"
        )
        lines.append(f"- pct within 0.05: {(m.get('pct_within') or {}).get('0.05')}")
        lines.append(f"- Oregon bytes / MiB: {c.get('oregon_bytes')} / {c.get('oregon_mib')}")
        lines.append(
            f"- Global: {g.get('global_total_mib')} MiB "
            f"({g.get('output_width')}×{g.get('output_height')}) reliability={g.get('reliability')}"
        )
        if c.get("top_errors"):
            te = c["top_errors"][0]
            lines.append(
                f"- Worst cell: lon={te.get('lon'):.4f} lat={te.get('lat'):.4f} "
                f"abs_err={te.get('abs_error'):.4f}"
            )
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
