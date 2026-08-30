#!/usr/bin/env bash
# Drill 2: kill the preferred OSPF transit link mid ping and capture the
# reconvergence: the LSA flood is visible in the pcap, and the route on r1
# flips from the direct r3 link (cost 10) to the path through r2 (cost 50).
set -euo pipefail
LAB=clab-bastion-campus
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill2-ospf-reconvergence"
mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "pre state: r1 routes and neighbors"
docker exec $LAB-r1 vtysh -c 'show ip route ospf' > "$ART/pre_show_ip_route_r1.txt"
docker exec $LAB-r1 vtysh -c 'show ip ospf neighbor' > "$ART/pre_show_neighbors_r1.txt"

log "starting captures (ospf and icmp): LAN1 via r1 eth1, and the r2 r3 link"
ip netns exec $LAB-r1 tcpdump -i eth1 -U -w "$ART/r1_eth1_lan.pcap" \
    '(ip proto ospf) or icmp' 2> "$ART/tcpdump_lan.log" &
PID_LAN=$!
ip netns exec $LAB-r3 tcpdump -i eth2 -U -w "$ART/r3_eth2_backup_link.pcap" \
    '(ip proto ospf) or icmp' 2> "$ART/tcpdump_backup.log" &
PID_BK=$!
sleep 2

log "starting 45s ping h1 to h2 at 5 packets per second"
docker exec $LAB-h1 ping -i 0.2 -w 45 10.40.0.100 > "$ART/ping_h1_to_h2.txt" &
PING_PID=$!

sleep 15
log "FAILURE: administratively down r1 eth2 (the preferred cost 10 uplink)"
docker exec $LAB-r1 vtysh -c 'configure terminal' -c 'interface eth2' -c 'shutdown'

sleep 10
log "post failure: r1 routes and neighbors"
docker exec $LAB-r1 vtysh -c 'show ip route ospf' > "$ART/post_failure_show_ip_route_r1.txt"
docker exec $LAB-r1 vtysh -c 'show ip ospf neighbor' > "$ART/post_failure_show_neighbors_r1.txt"

log "RECOVERY: no shutdown on r1 eth2"
docker exec $LAB-r1 vtysh -c 'configure terminal' -c 'interface eth2' -c 'no shutdown'

wait $PING_PID || true
log "ping finished"
sleep 5
kill $PID_LAN $PID_BK 2>/dev/null || true
wait $PID_LAN $PID_BK 2>/dev/null || true

docker exec $LAB-r1 vtysh -c 'show ip route ospf' > "$ART/post_recovery_show_ip_route_r1.txt"
docker exec $LAB-r1 vtysh -c 'show ip ospf neighbor' > "$ART/post_recovery_show_neighbors_r1.txt"
log "done: artifacts in $ART"
tail -3 "$ART/ping_h1_to_h2.txt" | tee -a "$ART/timeline.txt"
