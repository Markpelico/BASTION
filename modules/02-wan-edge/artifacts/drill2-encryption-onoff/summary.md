# Drill 2 summary: what the provider sees

One capture point, inside the provider (ispa's site1 facing interface), across
three phases of identical site to site traffic (pings between the private
overlay subnets). Counts from provider_view_analysis.txt, all read from
ispa_eth1_provider_view.pcap.

| Phase | Provider observes |
|-------|-------------------|
| 1: IPsec up | **22 ESP packets**: two loopback addresses and opaque payload |
| 2: IPsec down, same traffic | **42 cleartext GRE packets**: inner source and destination (10.101.0.100, 10.102.0.100), protocol, ICMP sequence numbers, TTLs all readable |
| 3: ipsec up again | **4 IKEv2 packets** (IKE_SA_INIT and IKE_AUTH exchanges), then ESP resumes |

Phase 2 is the entire justification for encrypted transit in one artifact: the
moment the SAs were deleted, the provider could read the private addressing
plan and every payload byte, plus the OSPF hellos crossing the tunnel. The
overlay kept working (GRE does not care), which is exactly the danger: nothing
breaks when encryption silently disappears, traffic just becomes readable.

The phase 3 capture is also this repo's reference IKEv2 negotiation:
IKE_SA_INIT (Diffie Hellman and nonces, 506 and 514 bytes) followed by
IKE_AUTH (identities and PSK proof, encrypted already), four packets total to
a working child SA in transport mode.

Operational footnote from this lab's boot sequence: strongSwan's auto=start
fired before BGP had converged, so the first IKE SA established over the out
of band management network (visible in the phase 2 teardown log:
172.20.20.x[4500] addresses with 192.0.2.x identities). The renegotiation in
phase 3, after convergence, runs over the real provider path with loopback
addresses, which is what the steady state `ipsec statusall` artifact shows.
The data plane (ESP protecting GRE between loopbacks) always used the real
path: the 22 ESP packets in phase 1 are on the provider link by definition.
