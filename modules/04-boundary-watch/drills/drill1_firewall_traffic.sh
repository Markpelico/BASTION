#!/usr/bin/env bash
# Drill 1: generate legitimate and hostile traffic across the boundary, then
# show the firewall's own record of it: nft counters, the logged denies that
# reached the collector via syslog, and the NetFlow top talkers from nfdump.
set -euo pipefail
LAB=clab-bastion-boundary
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill1-firewall"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "capturing on the collector mgmt interface (syslog + netflow)"
ip netns exec $LAB-collector tcpdump -i eth1 -U -w "$ART/collector_mgmt.pcap" \
    'udp port 514 or udp port 9995' 2>/dev/null &
CPID=$!
sleep 1

log "legitimate: outside fetches the published web service 5 times"
for i in $(seq 1 5); do
  docker exec $LAB-outside curl -s -o /dev/null -w "%{http_code}\n" \
      --max-time 4 http://10.10.10.100/ || echo "curl failed"
done > "$ART/legit_web_fetches.txt"

log "legitimate: inside browses out (NAT), and pings out"
docker exec $LAB-inside curl -s -o /dev/null --max-time 4 http://203.0.113.100/ || true
docker exec $LAB-inside ping -c 3 203.0.113.100 > "$ART/inside_outbound_ping.txt" || true

log "hostile: outside port scans the inside host (should be dropped + logged)"
docker exec $LAB-outside nmap -Pn -p 20-30,80,443,3389 --host-timeout 20s \
    10.10.10.100 > "$ART/outside_portscan.txt" 2>&1 || true

log "hostile: outside floods SYNs at a closed port with hping3"
docker exec $LAB-outside timeout 6 hping3 -S -p 22 -i u20000 -c 120 \
    10.10.10.100 > "$ART/outside_syn_flood.txt" 2>&1 || true

# NetFlow needs softflowd's flows to expire (maxlife 5s) and nfcapd to rotate
# its file (every 10s). Wait past both so the records are on disk before we
# read them. nfcapd is left alone: it rotates on its own timer, and sending
# it a signal terminates the collector.
log "waiting for NetFlow expiry and nfcapd rotation"
sleep 18
log "collecting firewall counters and logs"
docker exec $LAB-fw nft list ruleset > "$ART/fw_ruleset_with_counters.txt"
docker exec $LAB-fw nft list counter inet boundary 2>/dev/null || true

log "collecting syslog on the collector (denies shipped from the firewall)"
docker exec $LAB-collector sh -c 'cat /var/log/lab/*.log 2>/dev/null' > "$ART/collector_syslog_all.txt" || true
grep -E "FW-DENY|FW-INVALID" "$ART/collector_syslog_all.txt" > "$ART/collector_denies.txt" 2>/dev/null || true

log "NetFlow analysis from nfdump (top talkers and top destination ports)"
docker exec $LAB-collector sh -c \
    'nfdump -R /var/cache/nfdump -s srcip/bytes -n 10 2>/dev/null' > "$ART/netflow_top_talkers.txt" || true
docker exec $LAB-collector sh -c \
    'nfdump -R /var/cache/nfdump -s dstport/flows -n 10 2>/dev/null' > "$ART/netflow_top_ports.txt" || true

sleep 2
kill $CPID 2>/dev/null || true
wait $CPID 2>/dev/null || true

{
  echo "== web fetches from outside (expect 200 x5):"
  cat "$ART/legit_web_fetches.txt"
  echo; echo "== denied events captured by the collector (count):"
  wc -l < "$ART/collector_denies.txt" 2>/dev/null || echo 0
  echo "sample:"; head -5 "$ART/collector_denies.txt" 2>/dev/null || true
  echo; echo "== nft deny counters:"
  grep -E "FW-DENY|FW-INVALID|dropped" "$ART/fw_ruleset_with_counters.txt" | head -8
  echo; echo "== NetFlow top talkers:"; head -20 "$ART/netflow_top_talkers.txt"
} > "$ART/analysis.txt"
cat "$ART/analysis.txt" | tee -a "$ART/timeline.txt"
log "done: artifacts in $ART"
