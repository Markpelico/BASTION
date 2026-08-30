"""Helpers for the live load-balancer lab."""
import subprocess
import collections

LAB = "clab-bastion-lb"


def dexec(node: str, *cmd: str, timeout: int = 30) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", "exec", f"{LAB}-{node}", *cmd],
        capture_output=True, text=True, timeout=timeout,
    )


def curl_vip(port: int = 80, path: str = "/id") -> str:
    res = dexec("client", "curl", "-s", "--max-time", "4",
                f"http://10.20.0.10:{port}{path}")
    return res.stdout.strip()


def sample_backends(n: int = 20, port: int = 80) -> collections.Counter:
    return collections.Counter(curl_vip(port) for _ in range(n))
