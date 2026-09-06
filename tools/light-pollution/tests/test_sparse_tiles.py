import numpy as np

from light_pollution.masks import pack_nodata_mask, packed_mask_nbytes, unpack_nodata_mask
from light_pollution.nodata import DEFAULT_NODATA
from light_pollution.quantize import UInt8Params
from light_pollution.sparse_tiles import SparseTileConfig, decode_sparse, encode_sparse


def test_all_nodata_distinct_from_pristine():
    a = np.full((16, 16), DEFAULT_NODATA, dtype=np.float32)
    cfg = SparseTileConfig(tile_h=16, tile_w=16, tolerance=0.05, pristine_default=22.0)
    tiles, stats = encode_sparse(a, cfg)
    assert stats["mode_counts"]["all_nodata"] == 1
    recon = decode_sparse(tiles, a.shape, cfg)
    assert np.all(recon == DEFAULT_NODATA)

    b = np.full((16, 16), 22.0, dtype=np.float32)
    tiles2, stats2 = encode_sparse(b, cfg)
    assert stats2["mode_counts"]["default_pristine"] == 1
    recon2 = decode_sparse(tiles2, b.shape, cfg)
    assert np.allclose(recon2, 22.0)


def test_mixed_nodata_constant_exact_mask():
    a = np.full((16, 16), 21.0, dtype=np.float32)
    a[0:4, 0:4] = DEFAULT_NODATA
    a[8, 8] = DEFAULT_NODATA
    cfg = SparseTileConfig(tile_h=16, tile_w=16, tolerance=0.05, pristine_default=22.0)
    tiles, stats = encode_sparse(a, cfg)
    assert stats["mode_counts"]["constant"] == 1
    assert "nodata_mask_packed" in tiles[0]
    packed = tiles[0]["nodata_mask_packed"]
    assert len(packed) == packed_mask_nbytes(16 * 16)
    recon = decode_sparse(tiles, a.shape, cfg)
    # NoData positions exact
    assert np.all(recon[0:4, 0:4] == DEFAULT_NODATA)
    assert recon[8, 8] == DEFAULT_NODATA
    # valid positions constant
    assert np.allclose(recon[recon < 1e30], recon[recon < 1e30][0])


def test_packed_mask_roundtrip():
    inv = np.zeros((10, 10), dtype=bool)
    inv[0, 0] = True
    inv[9, 9] = True
    inv[3, 4] = True
    packed = pack_nodata_mask(inv)
    assert len(packed) == packed_mask_nbytes(100)
    back = unpack_nodata_mask(packed, (10, 10))
    assert np.array_equal(inv, back)


def test_sparse_uint8_and_byte_accounting():
    a = np.full((32, 32), 21.5, dtype=np.float32)
    a[0:8, 0:8] = DEFAULT_NODATA
    u8 = UInt8Params(m_min=16.0, m_max=22.5)
    cfg = SparseTileConfig(
        tile_h=16, tile_w=16, tolerance=0.05, storage="uint8", u8=u8, pristine_default=22.0
    )
    tiles, stats = encode_sparse(a, cfg)
    recon = decode_sparse(tiles, a.shape, cfg)
    assert stats["storage"] == "uint8"
    assert stats["mask_encoding"] == "np.packbits"
    # payload must include packed masks for mixed tiles
    assert stats["mask_bytes_accounted"] >= packed_mask_nbytes(16 * 16)
    # NoData preserved
    assert np.all(recon[0:8, 0:8] == DEFAULT_NODATA)
    # byte estimate consistency: re-sum from modes roughly
    assert stats["total_estimated_bytes"] == (
        stats["payload_bytes"] + stats["index_bytes"] + stats["metadata_bytes"]
    )


def test_full_tile_exact_float():
    rng = np.random.default_rng(0)
    a = (18 + 4 * rng.random((32, 32))).astype(np.float32)
    cfg = SparseTileConfig(tile_h=16, tile_w=16, tolerance=0.001)
    tiles, stats = encode_sparse(a, cfg)
    recon = decode_sparse(tiles, a.shape, cfg)
    for t in tiles:
        if t["mode"] == "full":
            r0, c0, h, w = t["r0"], t["c0"], t["h"], t["w"]
            np.testing.assert_allclose(
                recon[r0 : r0 + h, c0 : c0 + w], a[r0 : r0 + h, c0 : c0 + w], rtol=0, atol=1e-5
            )
