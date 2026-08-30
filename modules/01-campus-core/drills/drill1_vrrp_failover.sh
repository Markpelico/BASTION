#!/usr/bin/env bash
# Drill 1: crash the VRRP master mid ping and measure the loss window.
#
# docker pause freezes every process in r1 (cgroup freezer): advertisements stop
# without any graceful resign, exactly like a crashed gateway. The backup must
# notice via the master down interval (3 x advertisement interval plus skew).
# docker unpause restores r1, which preempts back to master (higher priority).
set -euo pipefail
LAB=clab-bastion-campus
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill1-vrrp-failover"
mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "pre state: VRRP roles"
docker exec $LAB-r1 vtysh -c 'show vrrp' > "$ART/pre_show_vrrp_r1.txt"
docker exec $LAB-r2 vtysh -c 'show vrrp' > "$ART/pre_show_vrrp_r2.txt"

log "starting capture on h1 eth1 (vrrp, arp, icmp)"
ip netns exec $LAB-h1 tcpdump -i eth1 -U -w "$ART/h1_eth1.pcap" \
    '(vrrp or arp or icmp)' 2> "$ART/tcpdump.log" &
TCPDUMP_PID=$!
sleep 2

log "starting 40s ping h1 to h2 at 5 packets per second"
docker exec $LAB-h1 ping -i 0.2 -w 40 10.40.0.100 > "$ART/ping_h1_to_h2.txt" &
PING_PID=$!

sleep 10
log "FAILURE: docker pause r1 (simulated crash of the VRRP master)"
docker pause $LAB-r1

sleep 12
log "post failure state: r2 role"
docker exec $LAB-r2 vtysh -c 'show vrrp' > "$ART/post_failure_show_vrrp_r2.txt"

log "RECOVERY: docker unpause r1"
docker unpause $LAB-r1

wait $PING_PID || true
log "ping finished"
sleep 3
kill $TCPDUMP_PID 2>/dev/null || true
wait $TCPDUMP_PID 2>/dev/null || true

docker exec $LAB-r1 vtysh -c 'show vrrp' > "$ART/post_recovery_show_vrrp_r1.txt"
docker exec $LAB-r2 vtysh -c 'show vrrp' > "$ART/post_recovery_show_vrrp_r2.txt"
log "done: artifacts in $ART"
tail -3 "$ART/ping_h1_to_h2.txt" | tee -a "$ART/timeline.txt"
