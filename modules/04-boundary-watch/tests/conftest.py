"""Helpers for running assertions against the live boundary-watch lab."""
import subprocess

LAB = "clab-bastion-boundary"


def dexec(node: str, *cmd: str, check: bool = True, timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", "exec", f"{LAB}-{node}", *cmd],
        capture_output=True, text=True, timeout=timeout,
    )


def out(node: str, *cmd: str) -> str:
    res = dexec(node, *cmd)
    assert res.returncode == 0, f"{node}: {' '.join(cmd)}: {res.stderr}"
    return res.stdout


def reachable(src: str, ip: str, port: str, timeout: int = 4) -> bool:
    """True if a TCP connect to ip:port from src succeeds within timeout."""
    res = dexec(src, "nc", "-z", "-w", str(timeout), ip, port, check=False,
                timeout=timeout + 5)
    return res.returncode == 0
