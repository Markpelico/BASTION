"""Validation suite for the load-balancer stretch module."""
from conftest import curl_vip, sample_backends


def test_vip_answers_l7():
    assert curl_vip(80).startswith("server web")


def test_vip_answers_l4():
    assert curl_vip(8404).startswith("server web")


def test_l7_round_robins_across_both_backends():
    counts = sample_backends(20, port=80)
    assert set(counts) == {"server web1", "server web2"}, counts
    # round robin should be close to even
    assert min(counts.values()) >= 6, counts


def test_stats_page_served():
    from conftest import dexec
    res = dexec("client", "curl", "-s", "--max-time", "4",
                "http://10.20.0.10:8405/stats")
    assert "haproxy" in res.stdout.lower() or "Statistics Report" in res.stdout
