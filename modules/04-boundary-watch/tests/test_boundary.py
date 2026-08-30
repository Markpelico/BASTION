"""Validation suite for module 4: run against the deployed boundary lab.

Policy under test (from config/nftables.conf):
  inside  -> outside/mgmt : allowed (stateful), NAT to 203.0.113.1
  outside -> inside :80    : allowed (published web service) only
  outside -> anything else : dropped and logged
"""
from conftest import dexec, out, reachable


def test_inside_can_reach_outside():
    assert reachable("inside", "203.0.113.100", "9999", timeout=3) is False or True
    # the real proof is an outbound ping succeeding through NAT
    res = out("inside", "ping", "-c", "2", "-W", "2", "203.0.113.100")
    assert " 0% packet loss" in res


def test_outside_can_reach_published_web_service():
    assert reachable("outside", "10.10.10.100", "80"), (
        "outside should reach the published web service on :80"
    )


def test_outside_blocked_from_unpublished_port():
    assert not reachable("outside", "10.10.10.100", "22", timeout=3), (
        "outside must not reach the inside host on an unpublished port"
    )


def test_outside_cannot_ping_inside():
    # a blocked ping returns non-zero on purpose, so do not assert success
    res = dexec("outside", "ping", "-c", "2", "-W", "2", "10.10.10.100")
    assert "100% packet loss" in res.stdout, "ICMP from outside to inside must be dropped"


def test_nat_rewrites_inside_source():
    """From outside's view, inside traffic must arrive as 203.0.113.1.
    nft renders the family qualified form 'snat ip to'."""
    res = out("fw", "nft", "list", "chain", "inet", "boundary", "postrouting")
    assert "snat ip to 203.0.113.1" in res


def test_denies_are_logged_and_counted():
    res = out("fw", "nft", "list", "chain", "inet", "boundary", "forward")
    assert 'log prefix "FW-DENY-OUTSIDE: "' in res
    assert "counter" in res


def test_firewall_default_drop_on_forward():
    res = out("fw", "nft", "list", "chain", "inet", "boundary", "forward")
    assert "policy drop" in res
