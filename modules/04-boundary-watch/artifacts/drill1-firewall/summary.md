# Drill 1 summary: the boundary under legitimate and hostile traffic

Legitimate traffic (outside fetching the published web service, inside
browsing out through NAT) and hostile traffic (an nmap port scan and an hping3
SYN flood from outside) crossed the boundary while the monitoring plane
recorded everything. Numbers from analysis.txt and the artifacts here.

## What the firewall allowed and denied

| Traffic | Result | Evidence |
|---------|--------|----------|
| outside to inside :80 (published) | allowed, HTTP 200 x5 | legit_web_fetches.txt |
| inside to outside (browsing, ping) | allowed via NAT | inside_outbound_ping.txt |
| outside nmap scan (ports 22,25,443,3389,...) | dropped and logged | outside_portscan.txt |
| outside SYN flood at :22 | dropped and logged | outside_syn_flood.txt |
| **total denied packets** | **149**, counted by nft | fw_ruleset_with_counters.txt |

## The monitoring plane caught it all

- **Syslog**: 149 denied events reached the collector over UDP 514, each with
  full packet detail. The path is nft `log group 1` to NFLOG, ulogd bridging
  NFLOG to syslog, rsyslog forwarding to the collector. A sample denied SMTP
  probe from the nmap scan:
  ```
  ulogd: FW-DENY-OUTSIDE: IN=eth2 OUT=eth1 SRC=203.0.113.100 DST=10.10.10.100
         PROTO=TCP SPT=52282 DPT=25 SYN
  ```
  The scan is legible port by port in collector_denies.txt: probes to 25, 443,
  and DNS to a nonexistent host, all dropped.

- **NetFlow**: softflowd exported flow records to the collector's nfcapd;
  nfdump produced top talkers (netflow_top_talkers.txt):
  ```
  Src IP           Flows   Packets   Bytes
  203.0.113.100    321     670       28212   (the outside scanner and client)
  10.10.10.100     313     335       18541   (the web server replying)
  203.0.113.1      8       19        1452    (NATed inside traffic)
  ```
  642 flows total. The scanner is the top talker by flow count, which is
  exactly the signature of a port scan: many flows, few packets each.

## The lesson in the numbers

The firewall's job is binary (allow or drop), but the monitoring plane is what
makes it operable: the nft counters say how much was dropped, syslog says
exactly what and from where (the nmap scan reconstructed packet by packet),
and NetFlow says who the top talkers were without storing payload. Three views
of the same boundary, each answering a different question an operator asks.
