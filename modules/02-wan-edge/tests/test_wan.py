"""Validation suite for module 2: run against the deployed bastion-wan lab."""
import pytest

from conftest import (LAB, dexec, vtysh, bgp_established_peers, bgp_paths,
                      best_path)

EXPECTED_ESTABLISHED = {"s1r": 2, "s2r": 2, "ispa": 3, "ispb": 3}


@pytest.mark.parametrize("node,expected", sorted(EXPECTED_ESTABLISHED.items()))
def test_bgp_sessions_established(node, expected):
    assert bgp_established_peers(node) == expected


def test_s1r_prefers_ispa_by_local_preference():
    best = best_path("s1r", "203.0.113.0/24")
    nexthops = [n.get("ip") for n in best.get("nexthops", [])]
    assert "100.64.11.2" in nexthops, f"best path should use ispa: {nexthops}"
    assert best.get("locPrf") == 200, f"local preference should be 200: {best.get('locPrf')}"


def test_prepend_visible_on_ispb_but_not_best():
    """site1 prepends toward ispb. ispb still holds that path, but prefers the
    2 hop path through ispa, so the prepended path is never advertised onward:
    prepending steers the whole topology, not just the direct neighbor. The
    first run of this suite expected the prepended path to reach s2r, which is
    exactly the wrong mental model; see LEARN.md."""
    paths = bgp_paths("ispb", "198.51.100.0/24")
    aspaths = [p.get("aspath", {}).get("string", "") for p in paths]
    assert "65001 65001 65001 65001" in aspaths, (
        f"prepended path should sit unused in ispb's table: {aspaths}"
    )
    best = best_path("ispb", "198.51.100.0/24")
    assert best.get("aspath", {}).get("string") == "64512 65001", (
        f"ispb should prefer the short path through ispa: {aspaths}"
    )


def test_s2r_reaches_site1_via_ispa():
    """Inbound engineering outcome: s2r's best path to site1 goes through
    ispa, and the only alternative it knows also transits ispa."""
    best = best_path("s2r", "198.51.100.0/24")
    assert best.get("aspath", {}).get("string") == "64512 65001", (
        "inbound engineering should steer s2r via ispa"
    )


def test_ipsec_sa_established():
    out = dexec("s1r", "ipsec", "status")
    assert "ESTABLISHED" in out, f"IKE SA missing:\n{out}"
    assert "INSTALLED, TRANSPORT" in out, f"transport mode child SA missing:\n{out}"


def test_ospf_adjacency_over_tunnel():
    out = vtysh("s1r", "show ip ospf neighbor")
    assert "Full" in out and "gre1" in out, f"OSPF over gre1 not Full:\n{out}"


def test_private_route_learned_over_tunnel():
    out = vtysh("s1r", "show ip route 10.102.0.0/24")
    assert "10.99.0.2" in out, f"private route should point into the tunnel:\n{out}"


def test_public_end_to_end_ping():
    out = dexec("s1h", "ping", "-c", "3", "-W", "2", "203.0.113.100")
    assert " 0% packet loss" in out


def test_private_end_to_end_ping_through_tunnel():
    out = dexec("s1h", "ping", "-c", "3", "-W", "2", "10.102.0.100")
    assert " 0% packet loss" in out


def test_private_prefixes_not_in_bgp():
    out = vtysh("ispa", "show ip bgp")
    assert "10.101.0.0" not in out and "10.102.0.0" not in out, (
        "private overlay prefixes must not leak into the provider BGP table"
    )
