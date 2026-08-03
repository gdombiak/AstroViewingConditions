"""Command-line interface for the light-pollution validation harness."""

from __future__ import annotations

import argparse
import http.server
import socketserver
import sys
from pathlib import Path

from .paths import DEFAULT_SOURCE, OUTPUT, ROOT


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="light_pollution",
        description="Oregon-focused fidelity + worldwide census harness for David Lorenz 2025 zenith sky brightness atlas",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_insp = sub.add_parser("inspect", help="Inspect and validate source GeoTIFF")
    p_insp.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_insp.add_argument("--skip-sha256", action="store_true")

    p_mm = sub.add_parser("global-minmax", help="Streaming global min/max scan")
    p_mm.add_argument("--source", type=Path, default=DEFAULT_SOURCE)

    p_crop = sub.add_parser("build-crop", help="Build cached Oregon crop")
    p_crop.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_crop.add_argument("--force", action="store_true")

    p_run = sub.add_parser("run-oregon", help="Full Oregon pipeline (uniform, sparse, fixed-adaptive, hierarchical)")
    p_run.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_run.add_argument("--skip-sha256", action="store_true")
    p_run.add_argument("--skip-global-minmax", action="store_true")
    p_run.add_argument("--force-crop", action="store_true")

    p_census = sub.add_parser(
        "world-tile-census",
        help="Streaming full-world tile census (no full-world candidate rasters)",
    )
    p_census.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_census.add_argument("--tile-cells", type=int, default=60)
    p_census.add_argument("--tolerance", type=float, default=0.05)

    p_acensus = sub.add_parser(
        "world-adaptive-census",
        help="Worldwide fixed-tile adaptive census (UInt8/UInt16); no full-world recon rasters",
    )
    p_acensus.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_acensus.add_argument("--skip-minmax", action="store_true")

    p_hcensus = sub.add_parser(
        "world-hierarchical-census",
        help="Worldwide hierarchical adaptive census (multiprocess, checkpoint/resume); no full-world recon rasters",
    )
    p_hcensus.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_hcensus.add_argument("--workers", type=int, default=None)
    p_hcensus.add_argument("--no-resume", action="store_true")

    p_hbench = sub.add_parser(
        "hierarchical-benchmark",
        help="Benchmark one hierarchical root row + equivalence samples (before full census)",
    )
    p_hbench.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_hbench.add_argument("--workers", type=int, default=None)
    p_hbench.add_argument("--root-j", type=int, default=4, help="Root row index (default 4 ~ mid latitudes)")

    p_gen = sub.add_parser(
        "generate-global",
        help="Generate production light_pollution_global_v1.bin from source TIFF",
    )
    p_gen.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p_gen.add_argument("--output", type=Path, default=None)
    p_gen.add_argument("--report", type=Path, default=None)
    p_gen.add_argument("--workers", type=int, default=None)
    p_gen.add_argument("--skip-sha256", action="store_true")

    p_ainfo = sub.add_parser("artifact-info", help="Inspect LPATLAS1 binary artifact")
    p_ainfo.add_argument("--artifact", type=Path, required=True)

    p_lookup = sub.add_parser("lookup", help="Lookup modeled zenith brightness from artifact")
    p_lookup.add_argument("--artifact", type=Path, required=True)
    p_lookup.add_argument("--latitude", type=float, required=True)
    p_lookup.add_argument("--longitude", type=float, required=True)

    p_serve = sub.add_parser("serve-viewer", help="Serve local viewer over HTTP")
    p_serve.add_argument("--port", type=int, default=8765)
    p_serve.add_argument("--bind", default="127.0.0.1")

    args = parser.parse_args(argv)

    if args.cmd == "inspect":
        from .pipeline import run_inspect
        from .paths import OUTPUT

        run_inspect(args.source, OUTPUT / "oregon", sha256=not args.skip_sha256)
        return 0

    if args.cmd == "global-minmax":
        from .pipeline import run_global_minmax
        from .paths import OUTPUT

        run_global_minmax(args.source, OUTPUT / "oregon")
        return 0

    if args.cmd == "build-crop":
        from .crop import build_region_crop, load_region_config
        from .paths import CONFIG

        region = load_region_config(CONFIG / "regions" / "oregon.json")
        build_region_crop(args.source, region, force=args.force)
        return 0

    if args.cmd == "run-oregon":
        from .pipeline import run_oregon_pipeline

        run_oregon_pipeline(
            source=args.source,
            skip_sha256=args.skip_sha256,
            skip_global_minmax=args.skip_global_minmax,
            force_crop=args.force_crop,
        )
        return 0

    if args.cmd == "world-tile-census":
        from .pipeline import run_world_tile_census

        run_world_tile_census(
            args.source,
            tile_cells=args.tile_cells,
            tolerance=args.tolerance,
        )
        return 0

    if args.cmd == "world-adaptive-census":
        from .pipeline import run_world_adaptive_quant_census

        run_world_adaptive_quant_census(args.source, skip_minmax=args.skip_minmax)
        return 0

    if args.cmd == "world-hierarchical-census":
        from .hierarchical_census import run_hierarchical_world_census
        from .paths import CONFIG, OUTPUT
        import json
        import numpy as np
        bands = json.loads((CONFIG / "product_bands.json").read_text())["bands"]
        quant = json.loads((CONFIG / "quantization.json").read_text())
        from .quantize import UInt8Params, UInt16Params
        mm_path = OUTPUT / "oregon" / "global_minmax.json"
        if mm_path.is_file():
            mm = json.loads(mm_path.read_text())
            gmin, gmax = float(mm["min"]), float(mm["max"])
            u8 = UInt8Params(
                m_min=float(min(16.0, np.floor(gmin * 100) / 100 - 0.05)),
                m_max=float(max(22.5, np.ceil(gmax * 100) / 100 + 0.05)),
            )
        else:
            u8 = UInt8Params(m_min=13.01, m_max=22.5)
        run_hierarchical_world_census(
            args.source,
            u8=u8,
            u16=UInt16Params(),
            pristine_default=float(quant.get("pristine_default_mag", 22.0)),
            product_bands=bands,
            workers=args.workers,
            resume=not args.no_resume,
        )
        return 0

    if args.cmd == "hierarchical-benchmark":
        from .hierarchical_census import benchmark_hierarchical_row
        from .paths import CONFIG, OUTPUT
        import json
        import numpy as np
        bands = json.loads((CONFIG / "product_bands.json").read_text())["bands"]
        quant = json.loads((CONFIG / "quantization.json").read_text())
        from .quantize import UInt8Params, UInt16Params
        mm_path = OUTPUT / "oregon" / "global_minmax.json"
        if mm_path.is_file():
            mm = json.loads(mm_path.read_text())
            gmin, gmax = float(mm["min"]), float(mm["max"])
            u8 = UInt8Params(
                m_min=float(min(16.0, np.floor(gmin * 100) / 100 - 0.05)),
                m_max=float(max(22.5, np.ceil(gmax * 100) / 100 + 0.05)),
            )
        else:
            u8 = UInt8Params(m_min=13.01, m_max=22.5)
        benchmark_hierarchical_row(
            args.source,
            root_j=args.root_j,
            workers=args.workers,
            pristine_default=float(quant.get("pristine_default_mag", 22.0)),
            u8=u8,
            u16=UInt16Params(),
            product_bands=bands,
        )
        return 0

    if args.cmd == "generate-global":
        from .generate_global import generate_global_artifact
        generate_global_artifact(
            source=args.source,
            output_path=args.output,
            report_path=args.report,
            workers=args.workers,
            skip_sha256=args.skip_sha256,
        )
        return 0

    if args.cmd == "artifact-info":
        from .binary_format import LightPollutionArtifact
        import json
        art = LightPollutionArtifact.load(args.artifact)
        print(json.dumps(art.info(), indent=2))
        return 0

    if args.cmd == "lookup":
        from .binary_format import LightPollutionArtifact
        art = LightPollutionArtifact.load(args.artifact)
        v = art.lookup(args.latitude, args.longitude)
        if v is None:
            print("unavailable")
            return 2
        print(f"{v:.10f}")
        return 0

    if args.cmd == "serve-viewer":
        # Serve Tools/LightPollution so viewer/ and output/ are both reachable
        root = str(ROOT)
        handler = http.server.SimpleHTTPRequestHandler
        # Python 3.7+ directory parameter
        def make_handler(*a, **kw):
            return handler(*a, directory=root, **kw)

        with socketserver.TCPServer((args.bind, args.port), make_handler) as httpd:
            url = f"http://{args.bind}:{args.port}/viewer/"
            print(f"Serving {root}")
            print(f"Open {url}")
            print("Press Ctrl+C to stop")
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\nStopped")
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
