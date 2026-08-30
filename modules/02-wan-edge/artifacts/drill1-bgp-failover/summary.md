# Drill 1 summary: losing the preferred provider

Continuous ping s1h to s2h over the public path (5 packets per second, 40s)
while s1r's link to the preferred provider ispa goes down. All numbers from the
artifacts in this directory.

| Event | Evidence |
|-------|----------|
| pre state: best path via ispa, localpref 200 | pre_show_ip_bgp_prefix_s1r.txt |
| failure: s1r eth1 down at t+10.0s into the ping | timeline.txt |
| loss: **1 packet of 197** (seq 50, in flight at the failure) | ping_s1h_to_s2h.txt |
| seq 51, sent 190ms after the failure, already left via ispb | first frame of s1r_eth2_ispb.pcap |
| post failure best path: 64513 65002, ispa session in Active | post_failure files |
| recovery: BGP UPDATE burst on the ispb link as ispa re establishes | s1r_eth2_ispb.pcap, t about 13.9 |

## Why failover took one ping, not tens of seconds

Two properties compound here:

1. **Directly connected eBGP tears down on interface loss immediately.** No
   waiting for the 90s hold timer: the session resets the moment the link
   reports down. The hold timer exists for silent failures.
2. **The alternate path was already in the BGP table.** s1r had been holding
   ispb's path as a non best route all along (visible in
   pre_show_ip_bgp_s1r.txt). Failover is a local best path recomputation and
   FIB update, not a network wide reconvergence: nothing needed to be learned,
   only re ranked.

The one lost packet is the one that was crossing the dying link. This is the
argument for multihoming with full routes held from both providers: the
failure domain shrinks to packets in flight.
