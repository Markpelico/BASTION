#!/usr/bin/env bash
# Drill 1: kill the preferred provider link mid ping and watch BGP fail over.
# s1r prefers ispa (local preference 200). Taking s1r eth1 down drops the
# directly connected eBGP session immediately; the path via ispb takes over.
set -euo pipefail
LAB=clab-bastion-wan
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill1-bgp-failover"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "pre state"
docker exec $LAB-s1r vtysh -c 'show bgp summary' > "$ART/pre_show_bgp_summary_s1r.txt"
docker exec $LAB-s1r vtysh -c 'show ip bgp' > "$ART/pre_show_ip_bgp_s1r.txt"
docker exec $LAB-s1r vtysh -c 'show ip bgp 203.0.113.0/24' > "$ART/pre_show_ip_bgp_prefix_s1r.txt"

log "starting captures on s1r uplinks (bgp and icmp)"
ip netns exec $LAB-s1r tcpdump -i eth1 -U -w "$ART/s1r_eth1_ispa.pcap" \
    'tcp port 179 or icmp' 2> "$ART/tcpdump_eth1.log" &
PID1=$!
ip netns exec $LAB-s1r tcpdump -i eth2 -U -w "$ART/s1r_eth2_ispb.pcap" \
    'tcp port 179 or icmp' 2> "$ART/tcpdump_eth2.log" &
PID2=$!
sleep 2

log "starting 40s ping s1h to s2h (public path) at 5 packets per second"
docker exec $LAB-s1h ping -i 0.2 -w 40 203.0.113.100 > "$ART/ping_s1h_to_s2h.txt" &
PING_PID=$!

sleep 10
log "FAILURE: s1r eth1 down (link to preferred provider ispa)"
docker exec $LAB-s1r ip link set eth1 down

sleep 12
log "post failure state"
docker exec $LAB-s1r vtysh -c 'show bgp summary' > "$ART/post_failure_show_bgp_summary_s1r.txt"
docker exec $LAB-s1r vtysh -c 'show ip bgp 203.0.113.0/24' > "$ART/post_failure_show_ip_bgp_prefix_s1r.txt"
docker exec $LAB-s1r vtysh -c 'show ip route 203.0.113.0/24' > "$ART/post_failure_show_ip_route_s1r.txt"

log "RECOVERY: s1r eth1 up"
docker exec $LAB-s1r ip link set eth1 up

wait $PING_PID || true
log "ping finished"
sleep 8
kill $PID1 $PID2 2>/dev/null || true
wait $PID1 $PID2 2>/dev/null || true
docker exec $LAB-s1r vtysh -c 'show bgp summary' > "$ART/post_recovery_show_bgp_summary_s1r.txt"
docker exec $LAB-s1r vtysh -c 'show ip bgp 203.0.113.0/24' > "$ART/post_recovery_show_ip_bgp_prefix_s1r.txt"
log "done: artifacts in $ART"
tail -3 "$ART/ping_s1h_to_s2h.txt" | tee -a "$ART/timeline.txt"
