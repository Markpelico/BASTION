# BASTION

[![ci](https://github.com/Markpelico/BASTION/actions/workflows/ci.yml/badge.svg)](https://github.com/Markpelico/BASTION/actions/workflows/ci.yml)

A hands-on network engineering lab, built the way a software engineer builds
things: every topology is code, every router configuration is generated from
templates, and every artifact in this repo came from a live run you can
reproduce with the runbooks. Nothing here is fabricated.

BASTION targets the technology areas in NSA posting 1261957 (Network Systems
Officer): routing protocols, gateway redundancy, BGP policy, encrypted WAN
tunnels, data center fabrics, boundary security, load balancing, and network
monitoring. The [coverage map](#coverage-map-nsa-posting-1261957) below states
honestly what is demonstrated here, what is cert study, and what is awareness
level only.

## Modules

| Module | What it demonstrates | Validation |
|--------|----------------------|------------|
| [01 campus-core](modules/01-campus-core/) | Multi-area OSPF, VRRP gateway redundancy | 10 tests, 2 drills |
| [02 wan-edge](modules/02-wan-edge/) | eBGP policy, GRE over IPsec, satellite link emulation | 13 tests, 3 drills |
| [03 dc-fabric](modules/03-dc-fabric/) | EVPN-VXLAN spine-leaf, two tenants, anycast gateways | 18 tests, 2 drills |
| [04 boundary-watch](modules/04-boundary-watch/) | nftables zones and NAT, syslog, NetFlow, packet captures | 7 tests, drill + capture library |
| [05 load-balancer](modules/05-load-balancer/) (stretch) | HAProxy VIP, L4/L7, health-check failover | 4 tests, 1 drill |

52 automated tests across the five modules, all passing on the committed runs.
[modules/STRETCH-NOTES.md](modules/STRETCH-NOTES.md) records the stretch goals
that the WSL2 kernel could not run (MPLS, MACsec) and why they are documented
rather than faked.

## How it is built

- **Topologies**: [containerlab](https://containerlab.dev) YAML, one per module.
- **Network OS**: [FRRouting](https://frrouting.org) in containers, the routing
  suite used in production at large cloud operators; strongSwan for IPsec;
  nftables, softflowd, nfdump, ulogd, and HAProxy for boundary and services.
- **Configs**: generated from Jinja2 templates plus per-module YAML variables by
  [tools/generate.py](tools/generate.py). No hand-edited router configs in the
  final state.
- **Validation**: per-module pytest suites assert protocol state (OSPF
  adjacencies, BGP sessions, EVPN routes, VRRP roles, firewall policy) and end
  to end reachability against the live lab.
- **Drift checking**: [tools/driftcheck.py](tools/driftcheck.py) diffs each
  running config against the generated golden config; clean on every module.
- **Style gate**: [tools/check_style.py](tools/check_style.py) enforces the
  repo's no-dashes rule in CI.
- **CI**: [.github/workflows/ci.yml](.github/workflows/ci.yml) runs the style
  gate, verifies the committed configs regenerate identically, and deploys
  modules 1 and 3 live in the runner to run their suites on every push.

## Coverage map, NSA posting 1261957

Interviewers respect a candidate who knows the boundary of their own artifact.
Here is exactly where each area of the posting sits.

### (a) Demonstrated in this lab, with real artifacts

| Posting area | Where | Evidence |
|--------------|-------|----------|
| Layer 3 routing: OSPF | [campus-core](modules/01-campus-core/) | multi-area, ABR, reconvergence drill with captures |
| Layer 3 routing: BGP | [wan-edge](modules/02-wan-edge/) | eBGP policy (local-pref, prepend), failover, a caught route leak |
| First-hop redundancy: VRRP | [campus-core](modules/01-campus-core/) | master/backup, failover drill measured against RFC 5798 |
| VPN: GRE, IPsec | [wan-edge](modules/02-wan-edge/) | GRE over IPsec, OSPF in the tunnel, provider-view capture |
| VPN: EVPN | [dc-fabric](modules/03-dc-fabric/) | BGP EVPN control plane, type 2/3 routes |
| VXLAN, data center fabric | [dc-fabric](modules/03-dc-fabric/) | spine-leaf, VXLAN capture, overlapping tenants |
| SDN / network automation | whole repo | configs as code, generated, tested, CI, drift checking |
| Load balancing / ADC | [load-balancer](modules/05-load-balancer/) | HAProxy VIP, L4/L7, health-check failover |
| Boundary / firewall | [boundary-watch](modules/04-boundary-watch/) | nftables zones, NAT, stateful, logged denies |
| Monitoring: NetFlow, syslog, Wireshark | [boundary-watch](modules/04-boundary-watch/) | softflowd to nfdump top talkers, syslog collector, annotated pcaps |
| WAN / satellite behavior | [wan-edge](modules/02-wan-edge/) | 600ms RTT emulation, TCP collapse and BBR recovery |

### (b) Covered by certification study, not labbed here

- **Cisco platform specifics** (IOS/IOS-XE command sets, EIGRP, HSRP): the
  concepts are demonstrated with their open equivalents (FRR, VRRP), and the
  vendor layer is CCNA/CCNP study. HSRP vs VRRP and EIGRP vs OSPF differences
  are drilled in the LEARN.md files.
- **Security+ material**: RMF and the ATO process, the governance vocabulary
  around network security, is cert study; the boundary module shows the
  technical controls those frameworks govern.
- **MPLS / L3VPN**: control plane concept covered in the wan-edge LEARN.md;
  a real data plane needs a kernel with MPLS support (see STRETCH-NOTES).

### (c) Awareness level only, not labbable at home

- **Type 1 / HAIPE encryptors** (TACLANE, KG-series): DoD crypto at the enclave
  boundary. Concept understood; hardware cannot be simulated.
- **Cross domain solutions** (data diodes, guards): controlled transfer between
  classification levels. Concept understood.
- **Optical transport** (SONET/SDH, OTN, DWDM), **WAN accelerators** (Riverbed):
  carrier and appliance hardware. The satellite drill shows the TCP physics
  that WAN accelerators exist to fight.
- **Commercial NMS and modeling** (HP NNM, Cisco Prime, Riverbed Modeler): the
  monitoring module shows the same model (polling, flows, thresholds) with free
  tooling.

No entry-level candidate demonstrates all thirteen posting areas; the posting
asks for "several." This repo demonstrates the ones that can be built honestly
and names the boundary for the rest.

## Environment

Built and run on Windows 11 with Docker and containerlab inside WSL2
(Ubuntu 24.04). Any Linux host with Docker and containerlab works the same way.
See [WHAT-BROKE.md](WHAT-BROKE.md) for the real problems hit during the build
and how they were diagnosed.

## Quickstart

```
git clone https://github.com/Markpelico/BASTION
cd BASTION
sudo make campus-deploy && sudo make campus-test && sudo make campus-destroy
```

Every module has the same verb pattern: `<mod>-deploy`, `<mod>-test`,
`<mod>-drill*`, `<mod>-drift`, `<mod>-destroy`. Run as root inside WSL2
(containerlab needs it). Each module README has a full runbook.

## Repo layout

```
modules/     one directory per module: topology, vars, generated configs,
             tests, drills, artifacts, README, LEARN.md
templates/   shared Jinja2 templates for FRR and IPsec configuration
images/      Dockerfiles for the FRR+strongSwan and monitoring images
tools/       config generator, drift checker, style checker
.github/     CI workflow
```

## Integrity

Every command output, packet capture, and measurement in this repo was produced
by the live labs on real runs. Each module README contains a runbook with the
exact commands to reproduce every artifact. Where a technology could not be run
on this toolchain, it is documented as such, never mocked.
