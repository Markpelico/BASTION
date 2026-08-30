"""Helpers for running assertions against the live dc-fabric lab."""
import json
import subprocess

LAB = "clab-bastion-dc"


def dexec(node: str, *cmd: str, check: bool = True) -> str:
    res = subprocess.run(
        ["docker", "exec", f"{LAB}-{node}", *cmd],
        capture_output=True, text=True, timeout=60,
    )
    if check:
        assert res.returncode == 0, (
            f"{node}: {' '.join(cmd)} exited {res.returncode}: {res.stderr}"
        )
    return res.stdout


def vtysh(node: str, show: str) -> str:
    return dexec(node, "vtysh", "-c", show)


def vtysh_json(node: str, show: str):
    return json.loads(vtysh(node, show))


def established(node: str, family_key: str) -> int:
    data = vtysh_json(node, "show bgp summary json")
    peers = data.get(family_key, {}).get("peers", {})
    return sum(1 for p in peers.values() if p.get("state") == "Established")


def host_mac(node: str) -> str:
    out = dexec(node, "cat", "/sys/class/net/eth1/address")
    return out.strip().lower()


def resolved_mac(host: str, ip: str) -> str:
    """Ping once to populate the neighbor table, then read the entry."""
    dexec(host, "ping", "-c", "1", "-W", "2", ip)
    out = dexec(host, "ip", "neigh", "show", ip)
    for token in out.split():
        if token.count(":") == 5:
            return token.lower()
    raise AssertionError(f"{host}: no resolved MAC for {ip}: {out}")
