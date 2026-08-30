# LEARN: EVPN-VXLAN and modern data center fabrics

Concepts behind module 3, grounded in this lab's artifacts.

## Why spine leaf replaced the three tier design

The legacy campus model (core, distribution, access) scales up: bigger boxes
in the middle, spanning tree blocking half the links, failure domains the
size of a building. The Clos (spine leaf) model scales out: every leaf
connects to every spine, every server is exactly two hops from every other,
all links forward (ECMP, no spanning tree in the fabric), and you add
capacity by adding spines. This lab is the smallest honest Clos: 2 spines,
3 leaves, every leaf dual homed.

## The three layers, and which artifact shows each

1. **Underlay** (gets packets between loopbacks): eBGP unnumbered on every
   fabric link. Sessions form over IPv6 link local addresses discovered from
   router advertisements; IPv4 loopback routes are exchanged with IPv6 next
   hops (RFC 5549). Artifact: any route table in this module, e.g. the drill
   2 route files, where 10.255.255.2/32 has fe80:: next hops via eth1 and
   eth2 (that pair is also the ECMP proof).
2. **Overlay control plane** (who is where): BGP's l2vpn evpn address family
   distributes MAC and IP reachability as typed routes. Type 2 = a MAC (and
   optionally IP) lives behind VTEP X. Type 3 = flood traffic for VNI Y to
   VTEP X (how broadcast and unknown unicast, like ARP, get delivered).
   Artifacts: l1_evpn_routes.txt, l1_evpn_macs.txt.
3. **Overlay data plane** (moving the frames): VXLAN wraps the tenant's
   Ethernet frame in UDP port 4789 between VTEP loopbacks, VNI in the
   header. Artifact: vxlan_decode.txt, an outer 10.255.255.1 to .2 UDP
   packet carrying inner 172.16.1.101 to .102 ICMP with VNI 10010.

The division of labor mirrors SDN vocabulary: BGP EVPN is the distributed
control plane, the VXLAN devices with learning off are pure forwarding
state, and FRR programs the kernel FDB from routes (the bridge fdb artifact
shows remote MACs pinned to VTEP addresses, none flood learned).

## Multi tenancy, precisely

Both tenants in this lab use 172.16.1.0/24, both have hosts .101 and .102,
and both use gateway .1. They never collide because:

- On the wire, the VNI separates them: the same inner addresses appear under
  VNI 10010 and 10020 in adjacent captured packets.
- In the leaf kernel, VRFs separate the gateway SVIs: two interfaces both
  numbered 172.16.1.1/24 can coexist because they live in different routing
  tables.
- In the control plane, VNIs scope the type 2 and type 3 routes.

The test suite's sharpest assertion: resolving 172.16.1.102 from tenant A
and from tenant B yields two different physical MAC addresses.

## Anycast gateways

Every leaf answers 172.16.1.1 with the same MAC per tenant (set identically
on each leaf's bridge). A host that migrates between leaves keeps its ARP
cache and its gateway one hop away: no FHRP election, no hairpin to a
remote gateway. This is the data center replacement for VRRP, which module 1
demonstrated in its natural campus habitat.

## Interview drill

1. *Why EVPN instead of flood and learn VXLAN?* Flood and learn scales
   flooding with the number of unknown MACs and gives no authoritative view.
   EVPN makes MAC location a routed fact in BGP: this lab's bridges have
   learning off, so every remote entry provably came from a type 2 route.
2. *Walk me through a ping between hosts on different leaves.* Host ARPs for
   the target (delivered via type 3 flood list or answered from suppression),
   leaf looks up the MAC, finds a type 2 route pointing at the remote VTEP,
   encapsulates in VXLAN with the tenant VNI, underlay ECMPs the UDP packet
   between loopbacks, remote leaf strips the header and delivers. Every step
   has an artifact in this module.
3. *What exactly is in a type 2 and a type 3 route?* Type 2: MAC, optional
   IP, VNI, next hop VTEP. Type 3: VNI and originating VTEP, building the
   ingress replication flood list.
4. *Why BGP unnumbered in the underlay?* No fabric addressing plan, no
   per link configuration beyond declaring the interface a neighbor, and
   IPv4 reachability with IPv6 next hops (RFC 5549). The artifact is any
   fe80:: next hop on an IPv4 route in this module.
5. *Spines share an AS, leaves do not. Why?* Leaves must accept routes that
   transited both spines; identical AS paths through both spines enable
   ECMP; spine to spine peering is unnecessary because spines never
   originate tenant state.
6. *How do overlapping tenant subnets not collide on the leaf itself?* VRFs:
   each tenant SVI lives in its own kernel routing table. On the wire the
   VNI does the same job.
7. *What breaks when a spine dies, and for how long?* At most half the flows
   (ECMP), for at most the hold time (9s here) if the failure is silent;
   interface down failures repath immediately. Drill 2 measured the
   degradation to a single next hop and the zero loss outcome, and explains
   the frozen data plane caveat honestly.
8. *What is an anycast gateway and why does mobility need it?* Same gateway
   IP and MAC on every leaf; a migrating host's traffic never hairpins to a
   distant gateway and its ARP cache stays valid.
9. *Where does this lab stop relative to production?* No L3VNI (routing
   between subnets of one tenant across the fabric would add a symmetric
   IRB layer), no multihomed servers (EVPN ESI lag), no ARP suppression
   tuning. Each is a documented extension point, and naming them
   unprompted is the credibility move.
10. *How would you verify a suspected EVPN problem, tool by tool?* Session
    layer: show bgp l2vpn evpn summary. Route layer: show bgp l2vpn evpn
    route (are the type 2s there). Kernel layer: show evpn mac vni, bridge
    fdb (did zebra install it). Wire layer: capture UDP 4789 and check VNI
    and outer addresses. The module's drills exercise exactly this ladder.
