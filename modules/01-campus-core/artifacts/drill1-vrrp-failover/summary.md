# Drill 1 summary: killing the VRRP master, two ways

Continuous ping h1 to h2 (5 packets per second, 40s window) while the VRRP master
r1 fails. Every number below is read from the pcaps and command outputs in this
directory. Times are seconds relative to the start of each scenario's capture.

## Scenario A: control plane freeze (docker pause r1)

`docker pause` freezes every FRR process in r1 (no advertisements, no graceful
resign) but the container's kernel network stack keeps forwarding. This models a
crashed routing stack on an otherwise healthy box.

Measured from `a-control-plane-freeze/h1_eth1.pcap`:

| Event | Time | Evidence |
|-------|------|----------|
| r1 advertisements, priority 200 | every 1.000s until t=11.006 | vrrp filter |
| pause injected | about t=12.0 | timeline.txt |
| r2 first advertisement, priority 100 | t=14.609 | vrrp filter |
| r2 gratuitous ARP for 10.10.0.1 | t=14.609 | arp.isgratuitous |
| **measured master down interval** | **3.603s** | 14.609 minus 11.006 |
| RFC 5798 computed interval | 3.609s | 3 x 1.000s + skew (256-100)/256 |
| packet loss | **0 of 197** | ping_h1_to_h2.txt |

The measured takeover matches the RFC math to within 6ms. Loss was zero because
the frozen master's kernel kept forwarding the whole time: echo replies continued
arriving from r1's real MAC (aa:c1:ab:ed:f8:28) throughout the freeze, and even
after r2 took over the virtual MAC (traffic went out via r2 and returned via r1,
a harmless asymmetry). OSPF never noticed: the 12s freeze is shorter than the 40s
dead interval.

Takeaway: a dead control plane is not a dead router. VRRP failed over on
schedule, but the data plane never needed it.

## Scenario B: LAN leg down (ip link set eth1 down inside r1)

This kills the data path and the advertisements together: the closest thing to
pulling the gateway's LAN cable.

Measured from `b-lan-interface-down/h1_eth1.pcap`:

| Event | Time | Evidence |
|-------|------|----------|
| last echo reply forwarded by r1 | t=11.477 (seq 50) | eth.src flips |
| first echo reply forwarded by r2 | t=11.682 (seq 51) | eth.src flips |
| **return path healed by OSPF** | **204ms** | one ping interval |
| r2 promotion (gratuitous ARP) | t=14.608 | about 3.1s after failure |
| packet loss | **0 of 197** | ping_h1_to_h2.txt |

Two mechanisms, both visible in the capture, explain zero loss during the 3.1s
in which r2 was still officially Backup:

1. **Return path:** r1's interface down triggered an immediate router LSA, and
   r3 rerouted LAN1 traffic through r2 within one ping interval. No dead timer
   involved: link state protocols reconverge fast when the failure is visible.
2. **Forward path:** when r1's bridge port dropped, the bridge flushed its MAC
   table and flooded frames for the virtual MAC to the remaining ports. r2's
   FRR macvlan (which always carries the virtual MAC, protodown while Backup)
   accepted and forwarded them anyway.

The second mechanism is confirmed by a dedicated probe
(`probe_r2_backup_forwarding.pcap`, produced by `drills/probe_backup_forwarding.sh`):
1.6s after the failure, r2 still reported `Status (v4) Backup`
(`probe_r2_role_at_1600ms.txt`) while its eth1 capture shows echo requests
addressed to 00:00:5e:00:01:0a being answered, TTL 61 proving the
h1, r2, r3, r4, h2 path.

Takeaway: the textbook "3 to 4 second VRRP blackout" assumes the backup refuses
virtual MAC frames until promoted, which is how most hardware implementations
behave. FRR's Linux macvlan model leaves the virtual MAC programmed on the
parent interface, so bridge flooding restores the forward path immediately. The
loss window measured here was zero, and the reasons are in the packets.
