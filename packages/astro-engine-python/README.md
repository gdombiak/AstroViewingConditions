# astro-engine (Python)

F2 slice: `observing_quality.assess` library + JSON CLI.

Calibration and fixtures are loaded from the repo `contracts/` tree (`CONTRACTS_ROOT` or ancestor walk). Do not copy scoring constants into this package.

F2 tests compare OQ results with a **narrow helper** (`tests/support.py`) that reads the two OQ policy field maps from `contracts/equality-policy.yaml`. That is not the Phase 10 generic parity runner.

```bash
cd packages/astro-engine-python
pip install -e ".[dev]"
pytest
python -m astro_engine --engine-version
python -m astro_engine observing_quality.assess --input ../../contracts/fixtures/capabilities/observing-quality/home-backyard-v1/input.json
```
