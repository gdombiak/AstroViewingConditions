# astro-engine (Python)

Astro Engine 1.0.0 Python library and JSON CLI. Public allow-list is the
thirty-four catalogued capabilities.

Calibration and fixtures are loaded from the repo `contracts/` tree (`CONTRACTS_ROOT` or ancestor walk). Do not copy scoring constants into this package.

F2 tests compare OQ results with a **narrow helper** (`tests/support.py`) that reads the two OQ policy field maps from `contracts/equality-policy.yaml`. That is not the Phase 10 generic parity runner.

```bash
cd packages/astro-engine-python
pip install -e ".[dev]"
pytest
python -m astro_engine --engine-version
python -m astro_engine observing_quality.assess --input ../../contracts/fixtures/capabilities/observing-quality/home-backyard-v1/input.json
```

Phase 15 adds `targets.recommend` for generic frozen target windows and
`equipment.match` for resolved requirements and selected instrument facts.
Both run through the shared library dispatcher, with canonical calibration and
no network or live astronomy. See the corresponding `contracts/procedures/`
documents. This remains unreleased 1.0.0 work.

## Phase 16 live astronomy and offline deployment

`astronomy.sun_events`, `astronomy.moon_info`, and `astronomy.moon_series` are
public under unreleased 1.0.0. Their [normative contract](../../contracts/procedures/astronomy.md)
uses resolved coordinates and whole-second UTC instants. Live outputs are never
substituted into frozen scoring parity. See
[the semantic cases](../../contracts/fixtures/astronomy/cases.json) for requests.

Runtime dependencies are pinned to `skyfield==1.55` and `skyfield-data==7.0.0`.
The latter's wheel is approximately 17 MB; DE421 itself is **16,788,480 bytes**
(16.01 MiB), SHA-256
`a20a7139da04cbc462454634918e9a9ca69127044e2cc9d4f9c16e238d2deedc`.
The data distribution also carries an IERS file; this engine does not read it.
DE421 covers roughly 1900–2053; the capability deliberately accepts 2000–2049.
We use the supported complete kernel rather than creating an undocumented cut
of it. Neither kernel nor dependency wheel is committed to this repository.

`SkyfieldAstronomy` opens the installed `skyfield_data/data/de421.bsp` with
`load_file`, uses `Loader.timescale(builtin=True)`, and closes the kernel after
execution. No cache creation, expiry refresh, live IERS request or first-use
network fetch occurs. Missing/corrupt data is `engine_failure` (CLI exit 1),
not a null astronomical event. Empty Moon series needs no data load.

The library accepts `CapabilityHost(ephemeris_path=...)`. The CLI host resolves
`ASTRO_ENGINE_EPHEMERIS_PATH` as an optional local override; a broken override
fails instead of falling through to another kernel. JSON cannot provide a path.
Deploy the same DE421 bytes at the override if using an operational resource
store. Alternative kernels are operator choices and require revalidation.

For the Grok Bot VM, prepare the wheelhouse **on a compatible Python/platform**
during deployment, then install without an index on the target:

```sh
python -m pip wheel ./packages/astro-engine-python --wheel-dir /path/to/wheelhouse
python -m pip freeze > /path/to/runtime-versions.txt
# Copy the complete wheelhouse, its hashes, and the version-matched contracts tree.
python -m pip install --no-index --find-links /path/to/wheelhouse astro-engine==1.0.0
export CONTRACTS_ROOT=/opt/astro/contracts
python -m astro_engine astronomy.moon_info --input request.json
```

Record wheel hashes and transitive versions with the deployment image; the
NumPy wheel is platform/Python specific. Package entry-point and contract-root
ownership are unchanged: an installed engine still needs the matching external
`contracts/` tree for engine identity/calibration. No real VM deployment is part
of Phase 16. Local validation built a wheel, installed it into a separate venv
with `--no-index`, and executed all 18 live cases with socket construction and
Skyfield downloads blocked. Package tests also block networking and exercise
missing/corrupt/explicit-local ephemeris paths. CI installs dependencies before
running the offline test suite.

Skyfield's bundled leap-second/UT1 prediction tables are pinned with its version.
Update dependencies deliberately and rerun astronomy conformance when those
predictions or leap-second knowledge need refreshing. This is not an automatic
runtime refresh. Skyfield 1.55 currently emits a NumPy 2.5 deprecation warning
in the test runner; numerical validation passes.

### Attribution and retained licenses

Skyfield software is MIT licensed, copyright Brandon Rhodes. skyfield-data
software is MIT licensed, copyright Bruno Bord / PeopleDoc Inc. Their installed
`.dist-info` license files are retained by normal wheel installation; deployments
must preserve those notices and the transitive dependency notices. Data credit
is **NASA/JPL for DE421**, and **IERS for the unused file included in skyfield-data**.
Do not describe the ephemeris as Astro-owned data or infer that the package
software's MIT notice changes the underlying data attribution. No source or
kernel is vendored/relicensed here.

Sources: [Skyfield local loading](https://rhodesmill.org/skyfield/api.html),
[Skyfield time scales](https://rhodesmill.org/skyfield/time.html),
[skyfield-data distribution and copyright](https://pypi.org/project/skyfield-data/),
[JPL ephemeris descriptions](https://ssd.jpl.nasa.gov/planets/eph_export.html).

`observing_window.select` selects production observing windows from already-included
`{time, score}` rows and an optional threshold. See the
[procedure](../../contracts/procedures/observing-window.md) for exact endpoint,
row-count, sorting and tie behavior. It uses no live astronomy and does not change
`night_conditions.analyze`.

`targets.compose_recommendations` performs the final mixed-target decision:
given already-scored candidate rows (`key`, `score`, `best_time`) and a `limit`,
it returns the selected rows in production order — score descending, best time
ascending, caller index ascending — so a host reuses its own recommendation
objects. It never scores anything. See the
[composition procedure](../../contracts/procedures/compose-recommendations.md).

`targets.filter_recommendations_by_equipment` then applies selected capability
facts and the minimum-fit policy to that conditions-ranked list. It composes the
existing equipment matcher and returns a stable subset of original indices/keys;
it does not transport or change scores, windows, reasons or summaries. See the
[equipment-filter procedure](../../contracts/procedures/filter-recommendations-by-equipment.md).

`night_forecast.derive_window` projects supplied twilight clock components onto
the supplied observing local day and following calendar day. It uses the same
shared timezone catalogue as `observing_night.resolve_active`; acquisition and
forecast filtering stay outside the capability. See the
[forecast-window procedure](../../contracts/procedures/night-forecast-window.md).

`night_conditions.classify_cloud_timing` returns one semantic verdict — `none`,
`early_heavy`, `late_heavy` or `intermittent_heavy` — from ordered hourly rows of
time, score and cloud cover. Caller order is part of the rule and rows are never
sorted. It emits no English copy: the summary sentences production builds from
the verdict are host presentation. See the
[cloud-timing procedure](../../contracts/procedures/cloud-timing.md).

The public catalog now contains 34 capabilities; engine/package identity remains
unreleased 1.0.0.

Target metadata is available through `targets.requirements`,
`catalog.solar_system`, and `targets.moon_sensitivity`. For example, pass
`{"capability":"targets.requirements","injected":{"id":"m77"}}` to the CLI;
combine the returned `requirement` and `is_planet` with selected `capabilities`
for `equipment.match`. Canonical catalogs remain under `contracts/data` and must
be available through the existing contracts-root installation mechanism.
See [the metadata procedure](../../contracts/procedures/target-metadata.md).
