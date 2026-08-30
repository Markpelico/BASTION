"""Helpers for running assertions against the live wan-edge lab."""
import json
import subprocess

LAB = "clab-bastion-wan"


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


def bgp_established_peers(node: str) -> int:
    data = vtysh_json(node, "show bgp summary json")
    peers = data.get("ipv4Unicast", {}).get("peers", {})
    return sum(1 for p in peers.values() if p.get("state") == "Established")


def bgp_paths(node: str, prefix: str) -> list[dict]:
    data = vtysh_json(node, f"show ip bgp {prefix} json")
    return data.get("paths", [])


def best_path(node: str, prefix: str) -> dict:
    for path in bgp_paths(node, prefix):
        if path.get("bestpath", {}).get("overall"):
            return path
    raise AssertionError(f"{node}: no bestpath for {prefix}")
