# Light Pollution Global Binary Format v1

**Artifact name:** `light_pollution_global_v1.bin`  
**Endianness:** little-endian  
**Magic:** ASCII `LPATLAS1` (8 bytes)  
**Version:** `1` (u16)

Production configuration encoded by the generator:

| Field | Value |
|-------|--------|
| Algorithm | hierarchical adaptive |
| Storage | UInt8 |
| Policy | error-only |
| Error budget | 0.10 mag |
| Finest cell size | 3 cells ≈ 0.025° |
| Root cell size | 768 cells ≈ 6.4° |
| Native fallback | none |
| Quantization | UInt8 codes 0…254 over `[m_min, m_max]`; 255 reserved (not used for valid samples) |

## Quantization

\[
\mathrm{code} = \mathrm{round}\bigl((m - m_{\min}) / s\bigr),\quad
s = (m_{\max} - m_{\min}) / 254
\]

\[
m = m_{\min} + \mathrm{code} \cdot s
\]

Clamped to 0…254 for valid samples. Out-of-domain / NoData leaves use tag types, not code 255, in v1 (except unused reserved).

## Spatial mapping

Source grid (EPSG:4326):

- `origin_lon = -180`, `origin_lat = +75`
- `pixel_width = +1/120°`, `pixel_height = -1/120°`
- `width = 43200`, `height = 16801`

Cell indices (integer, area convention — northwest corner of cell):

```
col = floor((lon - origin_lon) / pixel_width)
row = floor((origin_lat - lat) / |pixel_height|)
```

Longitude is normalized to `[-180, 180)` before mapping. Latitude outside the source extent yields unavailable.

Root indices:

```
root_i = col // root_cells
root_j = row // root_cells
```

Logical roots are always `root_cells × root_cells`; cells outside the source domain are structural NoData (padding), never stored as dense rasters.

## File layout

```
[Header 128 bytes]
[Root index: n_roots × 12 bytes]
[Root blobs: concatenated DFS trees]
```

### Header (128 bytes)

| Offset | Type | Name | Notes |
|--------|------|------|-------|
| 0 | u8[8] | magic | `LPATLAS1` |
| 8 | u16 | version | 1 |
| 10 | u16 | flags | bit0 reserved |
| 12 | u16 | root_cells | 768 |
| 14 | u16 | finest_cells | 3 |
| 16 | u32 | width | 43200 |
| 20 | u32 | height | 16801 |
| 24 | f64 | origin_lon | -180 |
| 32 | f64 | origin_lat | 75 |
| 40 | f64 | pixel_size | 1/120 |
| 48 | f32 | q_m_min | e.g. 13.01 |
| 52 | f32 | q_m_max | e.g. 22.5 |
| 56 | f32 | pristine_default | 22.0 |
| 60 | u16 | error_budget_milli | 100 → 0.10 mag |
| 62 | u16 | n_root_cols | ceil(width/root_cells) |
| 64 | u16 | n_root_rows | ceil(height/root_cells) |
| 66 | u16 | header_size | 128 |
| 68 | u32 | root_index_offset | 128 |
| 72 | u32 | root_data_offset | 128 + n_roots*12 |
| 76 | u32 | file_size | total bytes |
| 80 | u8[48] | reserved | zero |

### Root index entry (12 bytes)

| Offset | Type | Name |
|--------|------|------|
| 0 | u64 | blob_offset from file start |
| 8 | u32 | blob_length |

Roots are ordered row-major: `root_j * n_root_cols + root_i`.

### Node encoding (DFS inline)

Each node starts with a `u8` tag:

| Tag | Name | Payload |
|-----|------|---------|
| 0 | `all_nodata` | none |
| 1 | `default` | none (fill valid cells with quantized pristine_default) |
| 2 | `default_mask` | packed NoData mask, `ceil(h*w/8)` bytes, MSB-first packbits, 1=NoData |
| 3 | `constant` | `u8` quantized constant |
| 4 | `constant_mask` | `u8` constant + packed mask |
| 5 | `coarse` | `u16` factor; then `u8` grid of shape `(ceil(h/factor), ceil(w/factor))` row-major |
| 6 | `coarse_mask` | same as coarse + packed full-node mask |
| 7 | `children` | four child nodes DFS in order: TL, TR, BL, BR with mid splits `h//2`, `w//2` |

Mask packing matches NumPy `np.packbits` on a row-major boolean array.

## Lookup algorithm

1. Reject non-finite lat/lon → unavailable.  
2. Normalize longitude to `[-180, 180)`.  
3. Map to `col,row`; if outside `[0,width)×[0,height)` → unavailable.  
4. Load root blob for `(root_i, root_j)`.  
5. Walk DFS tree with local coordinates, descending into the correct child or reading a leaf.  
6. For leaf: if local cell is masked/NoData → unavailable; else return dequantized mag/arcsec².

## Validation rules

Parsers **must** reject at **initialization** (before lookup arithmetic):

### Header

- wrong magic or unsupported version;
- `header_size ≠ 128` (v1);
- `root_cells ≤ 0` or `finest_cells ≤ 0` or `finest_cells > root_cells`;
- `width ≤ 0` or `height ≤ 0`;
- `n_root_cols ≤ 0` or `n_root_rows ≤ 0`;
- non-finite `origin_lon`, `origin_lat`, `pixel_size`, `q_m_min`, `q_m_max`, `pristine_default`;
- `pixel_size ≤ 0`;
- `q_m_max ≤ q_m_min`;
- `pristine_default` outside `[q_m_min, q_m_max]` (inclusive; v1 does **not** permit out-of-range clamping);
- quant step `(q_m_max - q_m_min) / 254` non-finite or ≤ 0;
- `ceil(width / root_cells) ≠ n_root_cols` or `ceil(height / root_cells) ≠ n_root_rows`;
- `root_index_offset < 128`;
- root-index byte count overflow or `root_data_offset < root_index_offset + n_roots×12`;
- **declared `file_size` ≠ actual byte length** (v1 exact match);
- `file_size < root_data_offset` or truncated header/index.

### Root index (every entry, once at init)

- UInt64 offset not representable as a platform safe integer for slicing;
- `length ≤ 0` (**zero-length blobs are invalid** in v1; every root has at least one tag byte);
- `offset < root_data_offset` (must not point into header/index);
- `offset + length` overflow or `> file_size`.

Validated ranges should be stored for lookup; do not re-trust raw UInt64 fields on each query.

### Node payloads (eager structural validation at init)

v1 parsers **must** walk every root blob’s DFS tree at initialization and require:

- tags only in `0…7`;
- coarse `factor ≥ 1` (factor `0` is forbidden);
- mask payload length = `ceil(h×w/8)` bytes;
- coarse grid payload length = `ceil(h/factor)×ceil(w/factor)` bytes;
- children have four DFS subtrees for positive-size quadrants;
- **exact blob consumption** (no trailing garbage, no shortfall).

Malformed header/index/node structure fails **initialization**.  
Legitimate geographic NoData / out-of-coverage remains a lookup-time `nil` / `None` result and must never be confused with corruption.

## Versioning

- Bump `version` for any incompatible layout change.
- Reserved header bytes allow additive flags for compatible extensions.

## Licensing note

Atlas values originate from David Lorenz’s Light Pollution Atlas  
(https://djlorenz.github.io/astronomy/lp/). Permission to use the work and TIFF files was obtained directly. This binary is a derived offline packaging; redistribution remains subject to the applicable permission for the release. This harness/format does not itself grant third-party redistribution rights.
