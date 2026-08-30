#!/usr/bin/env python3
"""Config drift checker: compare each router's live running config against the
generated golden config committed in the repo.

The two texts are canonicalized before comparison: noise lines are dropped,
and every statement is prefixed with its enclosing block so a line like
"ip ospf cost 10" is compared as "interface eth2 / ip ospf cost 10". The
comparison is set based: drift means statements present on one side only,
which is exactly what a hand edit on a live router produces.

Usage: driftcheck.py --module 01-campus-core --lab clab-bastion-campus
"""
import argparse
import pathlib
import subprocess
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULES = ROOT / "modules"

NOISE_PREFIXES = (
    "building configuration", "current configuration", "frr version",
    "frr defaults", "hostname", "domainname", "service integrated-vtysh-config",
    "log stdout", "exit", "end", "password", "agentx",
    # zebra mirrors kernel created VRFs into running config as empty shells
    "vrf ",
)


def canonical(text: str) -> set[str]:
    lines: set[str] = set()
    context = ""
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("!"):
            continue
        if any(stripped.lower().startswith(p) for p in NOISE_PREFIXES):
            continue
        if not line.startswith(" "):
            context = stripped
            lines.add(stripped)
        else:
            lines.add(f"{context} / {stripped}")
    return lines


def running_config(lab: str, node: str) -> str:
    res = subprocess.run(
        ["docker", "exec", f"{lab}-{node}", "vtysh", "-c", "show running-config"],
        capture_output=True, text=True, timeout=60,
    )
    if res.returncode != 0:
        raise SystemExit(f"{node}: cannot read running config: {res.stderr}")
    return res.stdout


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--module", required=True)
    ap.add_argument("--lab", required=True, help="container name prefix, e.g. clab-bastion-campus")
    args = ap.parse_args()

    data = yaml.safe_load((MODULES / args.module / "vars.yml").read_text())
    routers = sorted(n for n, node in data["nodes"].items()
                     if node.get("role", "router") == "router")
    drifted = False
    for node in routers:
        golden = canonical((MODULES / args.module / "configs" / node / "frr.conf").read_text())
        live = canonical(running_config(args.lab, node))
        extra = sorted(live - golden)
        missing = sorted(golden - live)
        if extra or missing:
            drifted = True
            print(f"DRIFT on {node}:")
            for line in extra:
                print(f"  + running only: {line}")
            for line in missing:
                print(f"  - golden only:  {line}")
        else:
            print(f"clean: {node}")
    return 1 if drifted else 0


if __name__ == "__main__":
    sys.exit(main())
