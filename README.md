# BASTION

A hands-on network engineering lab, built the way a software engineer builds things:
every topology is code, every router configuration is generated from templates, and
every artifact in this repo came from a live run that you can reproduce with the
runbooks. Nothing here is fabricated.

BASTION targets the technology areas in NSA posting 1261957 (Network Systems Officer):
routing protocols, gateway redundancy, BGP policy, encrypted WAN tunnels, data center
fabrics, boundary security, and network monitoring.

## Modules

| Module | What it demonstrates | Status |
|--------|----------------------|--------|
| [01 campus-core](modules/01-campus-core/) | Multi-area OSPF, VRRP gateway redundancy, failure drills | complete, 10 tests passing |
| [02 wan-edge](modules/02-wan-edge/) | eBGP policy (local-preference, prepend), GRE over IPsec, satellite link emulation | complete, 13 tests passing |
| [03 dc-fabric](modules/03-dc-fabric/) | EVPN-VXLAN spine-leaf, two tenants, anycast gateways | planned |
| [04 boundary-watch](modules/04-boundary-watch/) | nftables zones and NAT, syslog, NetFlow, annotated packet captures | planned |

## How it is built

- **Topologies**: [containerlab](https://containerlab.dev) YAML, one file per module.
- **Network OS**: [FRRouting](https://frrouting.org) in containers, the same routing suite
  used in production at large cloud operators.
- **Configs**: generated from Jinja2 templates plus per-module YAML variables by
  [tools/generate.py](tools/generate.py). No hand-edited router configs in the final state.
- **Validation**: per-module pytest suites assert protocol state (OSPF adjacencies,
  BGP sessions, VRRP roles) and end-to-end reachability against the live lab.
- **Drills**: scripted failure exercises (kill a gateway, kill a link) that capture
  real packet captures and measurements into each module's `artifacts/` directory.

## Environment

Built and run on Windows 11 with Docker and containerlab inside WSL2 (Ubuntu 24.04).
Any Linux host with Docker and containerlab works the same way.

## Quickstart

```
git clone https://github.com/Markpelico/BASTION
cd BASTION
make campus-deploy    # deploy module 1
make campus-test      # pytest against the live lab
make campus-destroy
```

## Repo layout

```
modules/     one directory per lab module: topology, vars, generated configs,
             tests, drills, artifacts, README, LEARN.md
templates/   shared Jinja2 templates for FRR configuration
tools/       config generator, drift checker, style checker
```

## Integrity

Every command output, packet capture, and measurement in this repo was produced by
the live labs on real runs. Each module's README contains a runbook with the exact
commands to reproduce every artifact.
