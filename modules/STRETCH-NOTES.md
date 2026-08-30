# Stretch modules: what was built, and what was honestly not labbable

The build plan listed several stretch modules to attempt after the core four.
This file records what actually happened with each, including the ones that
could not be built here. The integrity rule for this repo is that nothing is
faked: a module that cannot run on this machine is documented as such, not
mocked up.

## Built and validated

- **load-balancer** (HAProxy): built, [module 05](05-load-balancer/), 4 tests
  passing, backend failover drill with real measurements. Covers the load
  balancing / ADC area.

## Not labbable on this machine, and why

These were attempted and blocked by the WSL2 kernel, which is a custom
Microsoft build that omits several networking modules. They are documented at
awareness level here rather than faked.

- **MPLS (LDP / L3VPN)**: FRR ships `ldpd`, but MPLS forwarding needs the
  kernel `mpls_router` module and the `net.mpls` sysctl tree. On this WSL2
  kernel (6.6.87.2-microsoft-standard-WSL2), `/proc/sys/net/mpls` does not
  exist and `modprobe mpls_router` fails: the module is not compiled in.
  Without a data plane, any `show mpls table` output would be a control plane
  that never forwards a labeled packet, which would be misleading. Concept
  covered in the wan-edge LEARN.md (label switching, VRFs, MP-BGP L3VPN);
  a real MPLS artifact needs a full Linux kernel host or vendor images.

- **MACsec (802.1AE)**: `ip link add type macsec` returns "Unknown device
  type" on this kernel: the `macsec` module is absent from
  `/lib/modules`. MACsec is hop by hop Layer 2 encryption; the contrast with
  IPsec (end to end, Layer 3) is covered in the wan-edge material. A real
  demo needs a kernel with CONFIG_MACSEC.

- **EIGRP**: FRR's `eigrpd` is alpha quality and EIGRP is Cisco proprietary
  with no production grade free implementation. Not attempted beyond noting
  it; the routing concepts (distance vector, feasible successors, DUAL) are
  interview level knowledge, and OSPF and BGP in the core modules cover
  link state and path vector with real artifacts.

## Deliberately out of scope

- **Splunk Free**: a legitimate stretch (Splunk is named in the posting), but
  heavy (a multi hundred MB container) and slow to bring up, so it was kept out
  to hold the repo lean and CI fast. The monitoring module already demonstrates
  the upstream half of the same pipeline: syslog aggregation to a collector and
  NetFlow into nfdump with a top talkers analysis, which is the transferable
  skill. Splunk would be a drop in replacement for the collector.

## The honest boundary

Everything that could be built for free on this Windows plus WSL2 plus
containerlab toolchain was built and validated live. The gaps above are kernel
and licensing limitations, not skipped work, and each maps to a concept that is
covered at the depth the toolchain allows. The top level README's coverage map
states the same boundary against the job posting.
