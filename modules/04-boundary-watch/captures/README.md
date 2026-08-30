# Annotated capture library

Every pcap here was produced live by [drills/capture_library.sh](../drills/capture_library.sh)
against the running boundary lab. Open them in Wireshark, or read the field
dumps below. Nothing is canned.

## tcp_handshake.pcap (13 packets)

A full TCP conversation from outside to the published web service on :80.

```
1  203.0.113.100 -> 10.10.10.100   [SYN]        client opens
2  10.10.10.100  -> 203.0.113.100  [SYN, ACK]   server agrees
3  203.0.113.100 -> 10.10.10.100   [ACK]         handshake complete
4+ ...            [PSH, ACK]                      HTTP request and response
```

What to look at: the three way handshake in frames 1 to 3, then the sequence
and acknowledgment numbers advancing as data flows. This is the reference for
"walk me through a TCP handshake," and the contrast case for the next capture.

## denied_syn.pcap (6 packets)

The same kind of SYN, aimed at a blocked port (22), captured on the firewall's
outside interface.

```
203.0.113.100 -> 10.10.10.100  [SYN]   (repeated retransmissions)
203.0.113.100 -> 10.10.10.100  [SYN]
...
```

What to look at: only SYNs, all from the client, never a SYN,ACK. The firewall
dropped each one (policy drop plus the FW-DENY-OUTSIDE rule), so the server
never saw them and the client keeps retransmitting on its timer. A dropped
connection looks exactly like this from the outside: silence, then retries.
Compare with tcp_handshake.pcap, where frame 2 is the SYN,ACK that never comes
here.

## nat_inside.pcap and nat_outside.pcap (8 packets each)

The same ping (inside host to an outside host) captured on both sides of the
firewall at once. This is source NAT proven per packet.

```
nat_inside.pcap  (firewall eth1, inside):   10.10.10.100  <-> 203.0.113.100
nat_outside.pcap (firewall eth2, outside):  203.0.113.1   <-> 203.0.113.100
```

What to look at: the inside capture shows the real client address
10.10.10.100. The outside capture shows the identical ICMP exchange with the
source rewritten to the firewall's outside address 203.0.113.1. The private
address never appears on the outside wire. That single substitution is the
whole of source NAT, and here it is on two interfaces simultaneously.

## netflow_export.pcap (NetFlow v5 records)

softflowd on the firewall exporting flow records to the collector's nfcapd.

```
172.31.0.1 -> 172.31.0.50  UDP 9995   NetFlow v5 export datagrams
```

What to look at: these are not the monitored packets, they are metadata about
them: one record per flow (source, destination, ports, protocol, byte and
packet counts) leaving the firewall for the collector. This is the raw feed
that nfdump turns into the top talkers table in the drill. The export is
bursty: softflowd batches records and sends them when flows expire, which is
why capturing this cleanly needed a controlled burst of traffic (see
WHAT-BROKE.md entry 9). Each datagram here is NetFlow v5 carrying 30 records.

Wireshark and tshark default the NetFlow dissector to port 2055, so tell them
port 9995 is cflow to see the decode:

```
tshark -r netflow_export.pcap -d udp.port==9995,cflow -V
```

