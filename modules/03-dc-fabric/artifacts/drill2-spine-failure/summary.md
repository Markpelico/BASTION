# Drill 2 summary: freezing a spine under traffic

Continuous ping hA1 to hA2 (5 packets per second, 40s) while sp1 is frozen
with docker pause for about 15 seconds: a silent control plane death, the
kind the 9 second hold timer (timers 3 9) exists for.

| Observation | Evidence |
|-------------|----------|
| loss: **0 of 197** | ping_hA1_to_hA2.txt |
| l1's session to sp1 dead after the 9s hold timer, FSM retrying (OpenSent) against the frozen spine | post_failure_bgp_summary_l1.txt |
| route to l2's VTEP degraded from ECMP to a single nexthop via eth2 (sp2) | post_failure_route_l1.txt |
| both nexthops restored after unpause | post_recovery_route_l1.txt |

## Why zero loss, honestly

Three mechanisms stack:

1. **ECMP means half the flows never used sp1.** This particular flow's
   five tuple may hash either way; with two spines, any single spine failure
   puts at most half the flows at risk.
2. **A frozen control plane is not a frozen data plane** (same lesson as
   module 1's VRRP drill): sp1's kernel kept forwarding VXLAN packets the
   entire time its BGP daemon was frozen. Flows crossing sp1 were carried by
   a router that was, from BGP's point of view, dead.
3. **Hold timer expiry cleaned up behind the scenes.** About 9 seconds in,
   l1 and the other leaves withdrew the sp1 paths and pinned everything to
   sp2 (the single nexthop artifact), so even a genuinely dead data plane
   would only have cost the sub second repath after expiry for the flows
   hashed onto it.

The artifact worth staring at is the post failure route: the next hops are
IPv6 link local addresses (fe80::...) for an IPv4 route, which is RFC 5549
in production form: the entire underlay runs without a single configured
point to point IPv4 address.
