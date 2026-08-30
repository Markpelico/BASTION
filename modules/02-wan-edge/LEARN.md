# LEARN: BGP policy, encrypted WAN, and long fat networks

Concepts behind module 2, grounded in this lab's artifacts.

## BGP in one page

BGP is the routing protocol between autonomous systems, and it optimizes for
policy, not distance. A route carries attributes; routers compare them in a
fixed order, and the two that matter most in practice are the two this lab
exercises:

- **Local preference** (compared first, higher wins, local to your AS): how
  site1 says "send my outbound traffic through ISP A." Artifact:
  `steady-state/s1r_bestpath_localpref.txt` shows localpref 200 on the path
  via 100.64.11.2 winning over the ispb path.
- **AS path length** (compared later, shorter wins, visible to everyone): how
  site1 influences inbound traffic by making the ISP B path look long
  (prepending its own AS three extra times). You cannot command the internet
  inbound, only make alternatives ugly.

Other rules worth knowing cold: eBGP beats iBGP for otherwise equal routes;
next hop must be reachable; BGP advertises only its best path to neighbors.
That last rule explains this lab's most instructive result, below.

## Two findings from this lab worth retelling in interviews

**The prepended path never reached site2.** The naive expectation: s2r sees
site1 via B with a long AS path and via A with a short one. Reality
(`steady-state/ispb_three_paths_prepend.txt`): ispb itself holds the prepended
path (65001 65001 65001 65001), prefers the 2 hop path through ispa
(64512 65001, FRR prints "best (AS Path)"), and therefore advertises only that
onward. s2r never learns the prepended path at all. Prepending does not just
demote a link for one neighbor: it reroutes the whole topology around it, and
routers only propagate what they themselves selected.

**An accidental route leak, caught in the table.** ispb also shows a third
path: 65002 64512 65001, meaning site2 re advertised routes it learned from
ISP A to ISP B. Site2 has no export policy, so it offered itself as transit
between two providers: a textbook BGP route leak, the mechanism behind several
famous internet outages. It is harmless here only because the AS path is long;
real providers filter customer sessions (prefix lists, or communities plus
max prefix) so a small customer cannot become transit. FRR's RFC 8212 default
(eBGP sessions get no routes without explicit policy) exists for exactly this
reason, and this repo satisfies it deliberately with generated route maps.

## GRE over IPsec: why two layers

IPsec ESP in tunnel mode encrypts unicast IP, but routing protocols need
multicast (OSPF hellos to 224.0.0.5) and stable interfaces to run over. GRE
provides the interface: a point to point tunnel that wraps anything in an IP
header (protocol 47). So the pattern is GRE for the routing protocol, IPsec in
transport mode to encrypt the GRE envelope between the same two endpoints.
The provider sees ESP between two loopbacks and nothing else: no OSPF, no
inner addresses, no payload (drill 2's capture proves it, and shows exactly
what leaks when encryption is off: inner ICMP and OSPF in cleartext).

Design details that matter and are visible in the configs:

- Tunnel endpoints are BGP announced loopbacks (192.0.2.1 and .2), so the
  tunnel survives any single uplink failure: the underlay reroutes, the
  overlay never notices.
- The overlay prefixes (10.101.0.0/24, 10.102.0.0/24) exist only in OSPF over
  the tunnel, never in BGP: the provider cannot route to them even if it
  wanted to (test: `test_private_prefixes_not_in_bgp`).
- Tunnel MTU is pinned to 1360: GRE costs 24 bytes, ESP with AES256 SHA256
  costs roughly 60 more, and letting path MTU discovery figure that out
  through an encrypted tunnel is how you get mysterious hangs.
- IKEv2 negotiates the keys (drill 2 captured the IKE_SA_INIT and IKE_AUTH
  exchanges on UDP 500); ESP carries the data. A PSK authenticates the lab;
  certificates would authenticate production.

## Long fat networks: why satellite links break TCP

Throughput of one TCP flow is capped by window divided by RTT. 600ms RTT
(geostationary satellite: 35786 km up, twice, at light speed) with the Linux
default 256KB window caps a flow around 3.5 Mbps no matter how fat the pipe.
Add loss and classic congestion control (cubic) treats every drop as
congestion and collapses its window, on a link where drops are mostly noise.

The two standard fixes, both in drill 3:

- **Bigger windows**: raise the socket buffer ceilings (window scaling is on
  by default; it only helps if buffers are allowed to grow).
- **Model based congestion control**: BBR estimates bandwidth and RTT instead
  of reacting to loss, so random loss does not crater throughput.

This is also why WAN accelerators (Riverbed class boxes) exist: they
terminate TCP locally, spoof ACKs, dedupe and compress across the slow link.
Drill 3 is the physics those boxes are built to fight.

## Interview drill

1. *You multihomed a site to two ISPs. Walk me through steering outbound and
   inbound.* Outbound: local preference on routes learned from the preferred
   provider (localpref 200 in this lab, artifact in steady state). Inbound:
   you cannot set attributes on other people's routers, so you make the
   backup path unattractive: AS path prepend toward B, and be ready to
   explain that distant ASes may still reach you however they like.
2. *Why did your prepended path not appear at the destination?* BGP routers
   advertise only their chosen best path. ispb preferred the short route via
   ispa and propagated that. Prepending changed ispb's choice, which was the
   goal; expecting to see the long path downstream misunderstands propagation.
3. *What is a route leak, and where is one in your lab?* An AS advertising
   routes beyond its intended policy scope, typically a customer re exporting
   one provider's routes to another. s2r does exactly that (65002 64512 65001
   in ispb's table) because the lab gives sites permissive export; providers
   prevent it by filtering customer sessions to their registered prefixes.
4. *Why GRE over IPsec instead of plain IPsec?* Routing protocols need
   multicast and an interface; GRE supplies both, IPsec transport mode
   encrypts the GRE envelope. Plain IPsec tunnel mode would carry the LANs
   but not the OSPF that discovers them.
5. *Why do the tunnel endpoints sit on loopbacks?* Loopbacks never go down
   with a physical interface. BGP reroutes the underlay path between them and
   the tunnel, and everything inside it, survives uplink failure untouched.
6. *eBGP session behavior when the link dies?* Directly connected eBGP resets
   immediately on interface down (no waiting for hold time): drill 1 measures
   the resulting failover. Hold time (90s default in FRR, 3x30s keepalive)
   matters for silent failures, same two speed story as OSPF dead interval.
7. *A satellite link shows 600ms RTT. What does that do to a single TCP flow
   and what do you tune?* Window/RTT caps throughput; drill 3 measured the
   collapse and the recovery from raising buffer ceilings and switching to
   BBR. Mention window scaling, and that loss based congestion control
   misreads link noise as congestion.
8. *What does the provider actually see of your site to site traffic?* ESP
   between two loopbacks plus occasional IKE on UDP 500: drill 2's capture
   from inside the provider. With encryption off, the same capture shows GRE
   with readable inner ICMP and OSPF: that delta is the entire argument for
   encrypting transit.
9. *What is RFC 8212 and why does FRR enforce it?* eBGP sessions must have
   explicit import and export policy or routes are rejected: default deny at
   AS boundaries, because permissive defaults are how route leaks happen.
   Every eBGP neighbor in this repo carries a generated route map.
10. *Your VPN is up but OSPF over the tunnel will not form. First three
    checks?* MTU mismatch on the tunnel interfaces (OSPF checks MTU in DBD),
    multicast actually entering the tunnel (GRE yes, plain IPsec no), and
    whether the IPsec policy is eating GRE (ipsec status, xfrm state). Each
    maps to a layer: interface, protocol, encryption.
