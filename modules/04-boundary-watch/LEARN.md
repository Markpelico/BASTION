# LEARN: boundary security and network monitoring

Concepts behind module 4, grounded in this lab's artifacts.

## Zone based firewalling

A boundary firewall thinks in zones (trust levels), not individual addresses:
inside is trusted, outside is untrusted, management is separate. The policy is
written between zones, and the default is drop: anything not explicitly allowed
is denied. This lab's forward chain is exactly that: `policy drop`, then a
small set of accept rules, then logged drops.

Stateful is the other half. The rule `ct state established,related accept`
means you write policy for the first packet of a connection only; the return
traffic is allowed automatically because conntrack remembers the connection.
Without it you would need mirror rules for every reply, and you could not tell
a legitimate response from an unsolicited packet. `ct state invalid drop`
catches packets that match no known connection, a common scan and evasion
signature.

## NAT, and why the private address vanishes

Source NAT rewrites the inside source address to the firewall's outside
address as traffic leaves. The nat_inside and nat_outside captures show it on
one ping: 10.10.10.100 on the inside wire, 203.0.113.1 on the outside wire.
The private address never appears outside, which is both an addressing
necessity (RFC 1918 space is not routable on the outside) and a small privacy
property. Conntrack reverses the translation for return packets.

## Three ways to watch a boundary, and what each answers

1. **Counters** (nft): how much. Every rule can carry a `counter`; the drill's
   FW-DENY-OUTSIDE counter reached 149 packets. Cheap, always on, no detail.
2. **Logs** (syslog): exactly what, and from where. Each denied packet becomes
   a syslog line with addresses, ports, and flags. The drill reconstructs the
   entire nmap scan from these lines. Detailed, but volume grows with events.
3. **Flow records** (NetFlow): who talked to whom, how much, without payload.
   softflowd summarizes each conversation into a record; nfdump ranks them.
   The scanner shows up as many flows of a few packets each, the classic scan
   signature. Compact, retainable, no packet contents.

Packet capture (Wireshark) is the fourth, heaviest view: full contents, used
for forensics, not continuous monitoring. The capture library is the sample.

## Why NFLOG, not kernel log, in this lab

nftables `log` normally writes to the kernel ring buffer, where a syslog
daemon (imklog) picks it up. In a container that does not work: the network
namespace's netfilter log does not surface through the shared kernel ring
buffer, and the container cannot read it. NFLOG (`log group N`) instead
delivers matched packets over a netlink socket, which ulogd reads in userspace
and forwards to syslog. This is the container native path, and it is also how
production systems that want structured firewall logs (ulogd can emit JSON)
are built. The finding is documented honestly in WHAT-BROKE.md.

## Interview drill

1. *Default allow or default deny, and why?* Default deny: you enumerate what
   is permitted, everything else is refused. This lab's forward chain is
   policy drop with a short allowlist. Default allow means every new threat is
   permitted until you notice and block it.
2. *What does stateful add over a stateless packet filter?* Connection
   tracking: you write policy for the first packet, replies are matched to the
   connection automatically, and packets matching no connection (invalid) are
   droppable. Stateless filters need mirror rules and cannot distinguish
   solicited from unsolicited traffic.
3. *Walk me through what happens to a SYN aimed at a blocked port.* It hits the
   forward chain, matches no accept rule, hits the logged drop, is counted and
   NFLOGged, and is silently discarded. The client never gets a SYN,ACK and
   retransmits on its timer: exactly the denied_syn.pcap artifact, contrasted
   with the completed handshake in tcp_handshake.pcap.
4. *How does NAT change what an outside observer sees?* The inside source
   address is replaced by the firewall's outside address; the private address
   never appears outside. The nat_inside and nat_outside captures show the same
   flow with 10.10.10.100 becoming 203.0.113.1.
5. *NetFlow vs full packet capture: when each?* NetFlow for continuous, long
   retention, privacy preserving who-talked-to-whom (no payload, compact);
   capture for deep forensics on a specific incident (full contents, heavy).
   The scan in this lab is obvious in NetFlow (many flows, few packets) without
   capturing a single payload byte.
6. *How would you spot a port scan in flow data?* One source, many
   destinations or destination ports, one or two packets per flow, no
   established replies. The drill's top talkers show the scanner leading by
   flow count with tiny byte counts.
7. *What is a next generation firewall beyond what this lab does?* Application
   identification (not just ports), TLS inspection, IPS signatures, user
   identity. nftables gives the zone, stateful, and NAT foundation; Palo Alto
   and Firepower add the layer 7 intelligence on top.
8. *Your firewall logs are not reaching the collector. How do you diagnose?*
   Layer by layer: does the rule counter increment (is traffic hitting it);
   is the log mechanism producing output (kernel log or NFLOG); is the local
   syslog daemon receiving and forwarding; is the collector reachable and
   listening. This lab hit exactly this and the fix was switching kernel log
   to NFLOG plus ulogd (WHAT-BROKE.md entry 7).
9. *What is a management network for?* Out of band access to devices,
   separated from production traffic, so you can reach a box even when its
   data plane is broken or under attack. Here the collector lives on its own
   segment and the policy lets it manage inside without exposing it to outside.
10. *Where does this lab stop relative to a production boundary?* No IPS or
    application awareness, a preshared everything, single firewall (no HA
    pair), and NetFlow v5 rather than IPFIX. Each is a named, deliberate
    boundary, which is the honest thing to say in an interview.
