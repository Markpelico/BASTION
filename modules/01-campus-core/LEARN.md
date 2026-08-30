# LEARN: multi-area OSPF and VRRP, from zero

This file teaches the concepts behind module 1 and drills the interview
questions they generate. Everything references the artifacts in this module, so
every answer can be backed by a file you can open.

## OSPF in one page

OSPF is a link state protocol: every router describes its own links in Link
State Advertisements (LSAs), floods them reliably to everyone in the area, and
then every router independently runs Dijkstra over the identical database to
compute shortest paths. Contrast with distance vector protocols (RIP, EIGRP),
where routers exchange computed routes and trust their neighbors' math.

Key mechanics, all visible in this lab:

- **Hellos and adjacency**: routers multicast hellos to 224.0.0.5 every 10s
  (default). Miss them for the dead interval, 40s, and the neighbor is declared
  down. The adjacency state machine ends at Full, meaning databases are
  synchronized: `artifacts/steady-state/r1_show_ip_ospf_neighbor.txt`.
- **Areas**: LSA flooding and SPF are scoped per area. Area 0 is the backbone;
  every other area must attach to it through an Area Border Router (r3 here).
  The ABR injects summary LSAs (type 3) into each area instead of raw topology,
  so r4 sees LAN1 as an inter area route, `O IA` in its table. Areas exist to
  cap flooding and SPF cost in large networks.
- **Cost**: each interface has a cost, path cost is the sum, lowest wins. This
  lab pins the r1 uplink at 10 and the r2 uplink at 50, which is why traffic
  prefers r1 and why drill 2 has a deterministic failover target.
- **Network types**: on a multi access LAN, OSPF elects a Designated Router to
  reduce n squared adjacencies; you can see r2 as DR from r1's neighbor table
  (`Full/DR`). On point to point links there is nothing to elect, so the router
  links are configured as point to point.
- **Two speeds of failure detection**: a visible failure (interface down)
  triggers an immediate new router LSA and reconvergence in milliseconds
  (drill 2: under 82ms). A silent failure (frozen neighbor, unidirectional
  link) waits for the 40s dead interval. This distinction is the single most
  useful OSPF fact in operations.

## VRRP in one page

Hosts configure one default gateway and never react to routing. First Hop
Redundancy Protocols give that single gateway address a spare. VRRP (RFC 5798,
the open standard; HSRP is Cisco's proprietary equivalent) has routers elect a
Master for a virtual IP plus virtual MAC (00:00:5e:00:01:{vrid}); the Master
answers ARP for the VIP and forwards frames sent to the virtual MAC; Backups
listen to its advertisements (multicast 224.0.0.18, IP protocol 112).

- **Timers**: advertisements every 1s here. A Backup declares the Master dead
  after the master down interval: 3 x advertisement interval + skew time, where
  skew = (256 - priority)/256 seconds, so higher priority backups move faster.
  Drill 1 measured 3.603s against a computed 3.609s.
- **Takeover**: the new Master sends a gratuitous ARP for the VIP from the
  virtual MAC so switches relearn which port owns it. One frame in the capture,
  `arp.isgratuitous`, and the hosts never notice: same gateway IP, same MAC.
- **Preemption**: VRRP preempts by default (highest priority reclaims
  mastership on return). HSRP does not preempt by default: a classic interview
  discriminator. Also: HSRP default timers are 3s hello and 10s hold, so
  standard VRRP fails over faster out of the box.
- **FRR's implementation**: a macvlan subinterface holds the virtual MAC; FRR
  drives it protodown while Backup. Measured consequence (drill 1 probe): the
  virtual MAC stays programmed on the parent interface, so when the bridge
  floods (after the failed master's port went down and its MAC entries were
  flushed), a still Backup router accepts and forwards virtual MAC frames.
  Hardware implementations typically program the virtual MAC only on the
  active router, which is where the textbook multi second blackout comes from.
  Second measured consequence (WHAT-BROKE entry 10): with the VIP configured
  on both macvlans, the Backup's kernel still answers ARP for the VIP with
  its real MAC (default arp_ignore=0 answers for any local address), so hosts
  intermittently learned the wrong gateway MAC. The lab sets arp_ignore=1 and
  arp_announce=2 on the routers, the classic first hop redundancy hardening,
  so only the oper-up macvlan holding the address answers, from the virtual
  MAC.

## The three lessons this module actually measured

1. **Control plane death is not data plane death.** A frozen FRR (docker pause)
   kept forwarding in the kernel for the entire 12s freeze: zero loss, while
   VRRP failed over exactly on schedule around it.
2. **Link state protocols are fast when failures are visible.** An admin down
   produced LSA origination, reflooding in 440 microseconds, and a healed path
   inside one 200ms ping interval.
3. **Implementation details change failure behavior.** The Linux macvlan VRRP
   model plus bridge flooding removed the classic VRRP loss window entirely.
   Knowing why requires reading packets, not vendor docs.

## Interview drill

1. *Walk me through what happens when the active gateway dies mid conversation.*
   Backup misses advertisements, waits the master down interval (3.6s here,
   measured), transitions to Master, sends gratuitous ARP from the virtual MAC;
   hosts keep using the same IP and MAC, so their sessions survive. In this lab
   the loss was zero even before promotion, because the bridge flooded virtual
   MAC frames to the backup, which forwards them (artifact: probe pcap).
2. *VRRP vs HSRP?* Open standard vs Cisco proprietary; VRRP preempts by default
   and advertises at 1s vs HSRP 3s hello and 10s hold; different virtual MAC
   ranges (00:00:5e:00:01:xx vs 00:00:0c:07:acxx); different multicast groups
   (224.0.0.18 proto 112 vs 224.0.0.2 UDP 1985). Concepts identical.
3. *Why do OSPF areas exist, and what does the ABR do?* Scope flooding and SPF;
   the ABR holds a database per area and originates type 3 summaries. In the
   lab r4 sees LAN1 only as O IA via r3.
4. *What is in a router LSA?* The router's own links: neighbors, networks,
   costs. Drill 2's failure event is literally r1 originating a new router LSA
   without the dead link, 400 microseconds later r2 refloods it.
5. *DR and BDR: why, and where in this lab?* Multi access segments would need
   n(n-1)/2 adjacencies; the DR centralizes flooding (everyone syncs with it on
   224.0.0.6). LAN1 elects one (r2 shows as DR in the artifacts); the point to
   point links skip election by configuration.
6. *When does the OSPF dead interval actually matter?* Only for silent
   failures. Visible link loss reroutes in milliseconds (measured 82ms);
   a frozen neighbor costs up to 40s unless you tune timers or run BFD.
7. *How would you make both protocols fail over faster?* VRRP: sub second
   advertisement intervals (FRR supports 10ms granularity), higher backup
   priority to cut skew. OSPF: faster hellos or, properly, BFD for sub second
   liveness without hello load. Tradeoff: false positives under CPU stress.
8. *What is asymmetric routing and where did it appear?* Forward and return
   paths differ. In drill 1A traffic left via r2 and returned via the frozen
   r1's kernel; harmless for ICMP but it breaks naive stateful firewalls, which
   is why boundary devices must sit where both directions pass.
9. *The host's gateway "moved" twice in these drills. What did the host see?*
   Nothing: same VIP, same virtual MAC, one gratuitous ARP updating switch
   learning. That invisibility is the entire point of FHRPs.
10. *Your ping showed zero loss but show vrrp said Backup for three seconds.
    Reconcile that.* Roles describe the control plane; forwarding is decided by
    MAC learning, flooding, and installed routes. The artifacts show the data
    plane healing (bridge flood plus OSPF reroute) seconds before the VRRP
    state machine caught up. Measuring the control plane tells you what the
    protocol did; only the data plane tells you what users felt.
