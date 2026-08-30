"""Validation suite for module 1: run against the deployed bastion-campus lab."""
import pytest

from conftest import dexec, vtysh, ospf_full_neighbors

EXPECTED_FULL = {"r1": 2, "r2": 2, "r3": 3, "r4": 1}


@pytest.mark.parametrize("node,expected", sorted(EXPECTED_FULL.items()))
def test_ospf_adjacencies_full(node, expected):
    assert ospf_full_neighbors(node) == expected, (
        f"{node} should have {expected} Full OSPF neighbors"
    )


def test_vrrp_r1_is_master():
    out = vtysh("r1", "show vrrp")
    assert "Master" in out, f"r1 should be VRRP master:\n{out}"


def test_vrrp_r2_is_backup():
    out = vtysh("r2", "show vrrp")
    assert "Backup" in out, f"r2 should be VRRP backup:\n{out}"


def test_h1_default_gateway_is_vip():
    out = dexec("h1", "ip", "route", "show", "default")
    assert "via 10.10.0.1" in out, f"h1 default route should use the VIP:\n{out}"


def test_return_path_prefers_r1():
    """r3 reaches LAN1 via r1 (cost 10) rather than r2 (cost 50)."""
    out = vtysh("r3", "show ip route 10.10.0.0/24")
    assert "10.0.13.1" in out, f"r3 route to LAN1 should point at r1:\n{out}"
    assert "10.0.23.1" not in out, f"r3 should not use the backup path:\n{out}"


def test_interarea_route_on_r4():
    out = vtysh("r4", "show ip route 10.10.0.0/24")
    assert "IA" in out or "10.1.34.1" in out, (
        f"r4 should have an inter area route to LAN1:\n{out}"
    )


def test_end_to_end_ping():
    out = dexec("h1", "ping", "-c", "3", "-W", "2", "10.40.0.100")
    assert " 0% packet loss" in out, f"h1 to h2 ping failed:\n{out}"
