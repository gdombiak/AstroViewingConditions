from light_pollution.sizes import (
    GLOBAL_HEIGHT,
    GLOBAL_WIDTH,
    global_reduced_dimensions,
    reduced_dimensions,
    uniform_global_size_exact,
)


def test_reduced_dims_drop_leftover_row():
    # 16801 // 3 = 5600, leftover 1 source row
    w, h = global_reduced_dimensions(3)
    assert w == GLOBAL_WIDTH // 3
    assert h == GLOBAL_HEIGHT // 3
    assert GLOBAL_HEIGHT - h * 3 == 1
    assert GLOBAL_WIDTH % 3 == 0


def test_factors_for_targets():
    # 0.025 -> factor 3, 0.05 -> 6, 0.1 -> 12
    assert global_reduced_dimensions(3) == (14400, 5600)
    assert global_reduced_dimensions(6) == (7200, 2800)
    assert global_reduced_dimensions(12) == (3600, 1400)


def test_uniform_global_size_exact_not_ratio():
    # UInt8 at 0.1° (factor 12)
    s = uniform_global_size_exact(12, bytes_per_cell=1, metadata_overhead=4096)
    assert s["reliability"] == "exact"
    assert s["kind"] == "uniform_exact_from_source_dims"
    assert s["output_width"] == 3600
    assert s["output_height"] == 1400
    assert s["payload_bytes"] == 3600 * 1400
    assert s["total_bytes"] == 3600 * 1400 + 4096
    assert s["leftover_source_rows_dropped"] == 1
    # ~4.8 MiB payload
    assert 4.5 < s["payload_mib"] < 5.5


def test_region_floor_matches_policy():
    # Oregon-like 1080x600 factor 12
    assert reduced_dimensions(1080, 600, 12) == (90, 50)
