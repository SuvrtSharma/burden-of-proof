"""The load generator's own arithmetic: every latency figure depends on it."""

from bench.loadgen import Sample, histogram, percentile, summarise


def test_percentile_is_nearest_rank() -> None:
    xs = list(range(1, 101))            # 1..100
    assert percentile(xs, 50) == 50     # rank ceil(100*0.50) = 50
    assert percentile(xs, 99) == 99     # rank ceil(100*0.99) = 99
    assert percentile(xs, 100) == 100
    assert percentile([7], 99) == 7     # one value: every percentile is that value
    assert percentile([], 50) == 0


def test_percentile_rounds_rank_up_not_down() -> None:
    xs = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    assert percentile(xs, 95) == 100    # rank ceil(9.5) = 10, not 9


def test_histogram_buckets_are_powers_of_two_microseconds() -> None:
    ns = [500, 1_000, 1_999, 2_000, 3_999, 4_000, 1_000_000]
    # 0.5 µs and 1 µs → bucket 0 ([1,2) µs, sub-µs folded in); 1.999 µs → 0; 2 µs, 3.999 µs → 1; 4 µs → 2; 1000 µs → 9
    assert histogram(ns) == {"0": 3, "1": 2, "2": 1, "9": 1}


def test_summary_counts_only_2xx_as_ok() -> None:
    samples = [Sample("balance", 200, 0, 1_000_000), Sample("balance", 500, 10, 2_000_000),
               Sample("bill", 201, 1_500_000_000, 3_000_000), Sample("bill", 0, 20, 4_000_000)]
    s = summarise(samples, seconds=2.0)
    assert (s["overall"]["requests"], s["overall"]["ok"], s["overall"]["errors"]) == (4, 2, 2)
    assert s["overall"]["throughput_rps"] == 1.0          # 2 ok / 2.0 s
    assert s["status_counts"] == {"0": 1, "200": 1, "201": 1, "500": 1}
    assert s["ok_per_second"] == [1, 1, 0]                # starts at 0 s and 1.5 s
