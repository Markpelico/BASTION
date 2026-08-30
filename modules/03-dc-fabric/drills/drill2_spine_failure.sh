#!/usr/bin/env bash
# Drill 2: freeze one spine mid traffic. The underlay holds ECMP routes over
# both spines; BGP hold time is tuned to 9s (timers 3 9). A frozen spine is a
# silent failure: whether the ping stream suffers depends on which spine the
# flow hashes onto, and recovery is bounded by the hold timer.
set -euo pipefail
LAB=clab-bastion-dc
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill2-spine-failure"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "pre state: l1 ECMP routes and sessions"
docker exec $LAB-l1 vtysh -c 'show ip route 10.255.255.2/32' > "$ART/pre_route_l1.txt"
docker exec $LAB-l1 vtysh -c 'show bgp summary' > "$ART/pre_bgp_summary_l1.txt"

log "starting 40s ping hA1 to hA2 at 5 packets per second"
docker exec $LAB-hA1 ping -i 0.2 -w 40 172.16.1.102 > "$ART/ping_hA1_to_hA2.txt" &
PING_PID=$!

sleep 10
log "FAILURE: docker pause sp1 (silent spine death)"
docker pause $LAB-sp1

sleep 15
log "post failure: l1 routes and sessions (hold timer is 9s)"
docker exec $LAB-l1 vtysh -c 'show ip route 10.255.255.2/32' > "$ART/post_failure_route_l1.txt"
docker exec $LAB-l1 vtysh -c 'show bgp summary' > "$ART/post_failure_bgp_summary_l1.txt"

log "RECOVERY: docker unpause sp1"
docker unpause $LAB-sp1

wait $PING_PID || true
log "ping finished"
sleep 12
docker exec $LAB-l1 vtysh -c 'show ip route 10.255.255.2/32' > "$ART/post_recovery_route_l1.txt"
docker exec $LAB-l1 vtysh -c 'show bgp summary' > "$ART/post_recovery_bgp_summary_l1.txt"
log "done: artifacts in $ART"
tail -3 "$ART/ping_hA1_to_hA2.txt" | tee -a "$ART/timeline.txt"
