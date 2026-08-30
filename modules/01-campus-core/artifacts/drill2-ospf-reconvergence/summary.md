# Drill 2 summary: OSPF reconvergence when the preferred link dies

Continuous ping h1 to h2 (5 packets per second, 45s window) while r1's preferred
uplink to r3 (cost 10) is administratively shut down, forcing traffic onto the
backup path through r2 (cost 50). Numbers below are read from the artifacts in
this directory. Times are seconds relative to the capture start.

## Timeline, from r1_eth1_lan.pcap

| Event | Time | Evidence |
|-------|------|----------|
| steady state: requests leave via r1's uplink | up to seq 74, t=16.604 | single copy per request on LAN |
| r1 originates router LSA announcing the dead link | t=16.726338 | ospf.msg 4, src 10.10.0.11 |
| r2 refloods the LSA | t=16.726778 (440 microseconds later) | ospf.msg 4, src 10.10.0.12 |
| first request hairpinned to r2 | t=16.807790 (seq 75) | same seq appears twice: h1 to VMAC, then r1 to r2, 9 microseconds apart |
| **reroute latency** | **under 82ms** | seq 75 is the first ping after the LSA |
| recovery LSA after no shutdown | about t=27.2 | ospf.msg 4 |
| packet loss | **0 of 221** | ping_h1_to_h2.txt |

## Routing table proof, pre vs post failure (r1)

```
before:  O>* 10.40.0.0/24 [110/30] via 10.0.13.2, eth2
after:   O>* 10.40.0.0/24 [110/80] via 10.10.0.12, eth1
```

Cost 30 (10 uplink + 10 r3 to r4 + 10 LAN2) became cost 80 (10 LAN1 + 50 backup
link + 10 + 10). The post failure table also shows the dead path explicitly:
`via 10.0.13.2, eth2 inactive`.

## What the hairpin means

After the failure, r1 (still the VRRP master) receives h1's frames on eth1 and
forwards them back out the same interface to r2: each echo request appears twice
on the LAN segment. No ICMP redirects were observed in the capture, so h1 kept
sending to the virtual MAC the whole time. This is the transient cost of keeping
gateway identity (VRRP) separate from path selection (OSPF): the packets still
get there, one LAN hop less efficiently, until the operator restores the link.

## Why zero loss

An administrative shutdown is a visible failure: zebra reports the interface
down, ospfd originates a new router LSA immediately, and every router runs SPF
within milliseconds. The only way to lose packets here is to be unlucky enough
to have one in flight across the dying link. The 40s dead interval matters for
silent failures (a frozen neighbor, a unidirectional link), not for this one.

## The false alarm worth remembering

FRR 10.7's vtysh prints `No changes found to be committed!` when applying the
shutdown, which reads like the command did nothing. It did: `ip link show eth2`
inside the container confirms `state DOWN`, and the LSA flood in the capture is
the protocol level proof. The message is mgmtd transaction noise about its own
config store, not a statement about the kernel. Verify at the source of truth.
