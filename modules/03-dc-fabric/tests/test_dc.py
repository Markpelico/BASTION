"""Validation suite for module 3: run against the deployed bastion-dc lab."""
import pytest

from conftest import dexec, vtysh, vtysh_json, established, host_mac, resolved_mac

IPV4 = "ipv4Unicast"
EVPN = "l2VpnEvpn"

EXPECTED_SESSIONS = {"l1": 2, "l2": 2, "l3": 2, "sp1": 3, "sp2": 3}


@pytest.mark.parametrize("node,expected", sorted(EXPECTED_SESSIONS.items()))
def test_underlay_unnumbered_sessions(node, expected):
    assert established(node, IPV4) == expected


@pytest.mark.parametrize("node,expected", sorted(EXPECTED_SESSIONS.items()))
def test_evpn_sessions(node, expected):
    assert established(node, EVPN) == expected


def test_ecmp_two_paths_to_remote_vtep():
    data = vtysh_json("l1", "show ip route 10.255.255.2/32 json")
    routes = data.get("10.255.255.2/32", [])
    assert routes, "l1 must reach l2's VTEP loopback"
    nexthops = [n for n in routes[0].get("nexthops", []) if n.get("fib") or n.get("active")]
    assert len(nexthops) == 2, f"expected ECMP over both spines: {nexthops}"


def test_leaf1_carries_both_vnis():
    data = vtysh_json("l1", "show evpn vni json")
    assert "10010" in data and "10020" in data, f"l1 should hold both VNIs: {list(data)}"


def test_tenant_a_ping_across_fabric():
    out = dexec("hA1", "ping", "-c", "3", "-W", "2", "172.16.1.102")
    assert " 0% packet loss" in out


def test_tenant_b_ping_across_fabric_same_addresses():
    out = dexec("hB1", "ping", "-c", "3", "-W", "2", "172.16.1.102")
    assert " 0% packet loss" in out


def test_overlapping_ip_resolves_to_different_hosts_per_tenant():
    """172.16.1.102 exists in both tenants. hA1 must reach hA2's NIC and hB1
    must reach hB3's NIC: same address, different MAC, full isolation."""
    mac_seen_by_a = resolved_mac("hA1", "172.16.1.102")
    mac_seen_by_b = resolved_mac("hB1", "172.16.1.102")
    assert mac_seen_by_a == host_mac("hA2")
    assert mac_seen_by_b == host_mac("hB3")
    assert mac_seen_by_a != mac_seen_by_b


def test_remote_mac_learned_via_bgp_not_flooding():
    """hA2's MAC must appear on l1 as a remote EVPN entry pointing at l2's
    VTEP, learned from a type 2 route (the VXLAN device has learning off)."""
    dexec("hA1", "ping", "-c", "1", "-W", "2", "172.16.1.102")
    mac = host_mac("hA2")
    data = vtysh_json("l1", "show evpn mac vni 10010 json")
    entry = data.get("macs", data).get(mac)
    assert entry, f"{mac} not in l1's VNI 10010 MAC table"
    assert entry.get("type") == "remote", entry
    assert entry.get("remoteVtep") == "10.255.255.2", entry


def test_type3_flood_routes_present():
    out = vtysh("l1", "show bgp l2vpn evpn route type 3")
    assert "10.255.255.2" in out, "IMET route from l2 missing"
    assert "10.255.255.3" in out, "IMET route from l3 missing"


def test_anycast_gateway_answers_on_both_leaves():
    for host in ("hA1", "hA2"):
        out = dexec(host, "ping", "-c", "2", "-W", "2", "172.16.1.1")
        assert " 0% packet loss" in out, f"{host} cannot reach the anycast gateway"
