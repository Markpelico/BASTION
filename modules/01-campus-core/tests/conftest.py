"""Helpers for running assertions against the live campus-core lab."""
import json
import subprocess

LAB = "clab-bastion-campus"


def dexec(node: str, *cmd: str, check: bool = True) -> str:
    """Run a command inside a lab container and return stdout."""
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


def ospf_full_neighbors(node: str) -> int:
    """Count OSPF neighbors in Full state, tolerant of FRR JSON field naming."""
    data = vtysh_json(node, "show ip ospf neighbor json")
    neighbors = data.get("neighbors") or data.get("default", {}).get("neighbors", {})
    count = 0
    for entries in neighbors.values():
        for entry in entries:
            state = (entry.get("nbrState") or entry.get("state")
                     or entry.get("converged") or "")
            if state.startswith("Full"):
                count += 1
    return count
