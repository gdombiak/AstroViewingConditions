import numpy as np

from light_pollution.masks import pack_nodata_mask, packed_mask_nbytes, unpack_nodata_mask


def test_packbits_byte_count():
    for n in (1, 7, 8, 9, 100, 3600):
        assert packed_mask_nbytes(n) == (n + 7) // 8


def test_pack_unpack_identity():
    rng = np.random.default_rng(1)
    inv = rng.random((17, 13)) > 0.7
    p = pack_nodata_mask(inv)
    assert len(p) == packed_mask_nbytes(17 * 13)
    assert np.array_equal(unpack_nodata_mask(p, (17, 13)), inv)
