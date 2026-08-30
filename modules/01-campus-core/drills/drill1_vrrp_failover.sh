#!/usr/bin/env bash
# Drill 1: two VRRP master failure scenarios, measured from h1.
#
# Scenario A, control plane freeze: docker pause r1 stops every FRR process
# (advertisements stop, no graceful resign) but the container's kernel network
# stack keeps forwarding. First run of this drill expected a loss window and
# measured zero loss, which is the correct behavior: VRRP fails over on the
# master down interval while the frozen master's data plane keeps carrying
# packets until the backup's gratuitous ARP moves the virtual MAC.
#
# Scenario B, LAN leg down: ip link set eth1 down inside r1 kills the data
# path together with the advertisements. This one produces the real loss
# window: roughly the master down interval (3 x advertisement interval plus
# skew, about 3.2s here) before r2 takes over.
set -euo pipefail
LAB=clab-bastion-campus
DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$DIR/artifacts/drill1-vrrp-failover"
rm -rf "$BASE"

run_scenario() {
  local name="$1" fail_cmd="$2" recover_cmd="$3"
  local ART="$BASE/$name"
  mkdir -p "$ART"
  : > "$ART/timeline.txt"
  log() { echo "[$(date +%H:%M:%S.%3N)] $*" | tee -a "$ART/timeline.txt"; }

  log "scenario $name: pre state"
  docker exec $LAB-r1 vtysh -c 'show vrrp' > "$ART/pre_show_vrrp_r1.txt"
  docker exec $LAB-r2 vtysh -c 'show vrrp' > "$ART/pre_show_vrrp_r2.txt"

  log "starting capture on h1 eth1 (vrrp, arp, icmp)"
  ip netns exec $LAB-h1 tcpdump -i eth1 -U -w "$ART/h1_eth1.pcap" \
      '(vrrp or arp or icmp)' 2> "$ART/tcpdump.log" &
  local TCPDUMP_PID=$!
  sleep 2

  log "starting 40s ping h1 to h2 at 5 packets per second"
  docker exec $LAB-h1 ping -i 0.2 -w 40 10.40.0.100 > "$ART/ping_h1_to_h2.txt" &
  local PING_PID=$!

  sleep 10
  log "FAILURE: $fail_cmd"
  eval "$fail_cmd" >/dev/null
  sleep 12
  log "post failure state: r2 role"
  docker exec $LAB-r2 vtysh -c 'show vrrp' > "$ART/post_failure_show_vrrp_r2.txt"

  log "RECOVERY: $recover_cmd"
  eval "$recover_cmd" >/dev/null

  wait $PING_PID || true
  log "ping finished"
  sleep 3
  kill $TCPDUMP_PID 2>/dev/null || true
  wait $TCPDUMP_PID 2>/dev/null || true
  docker exec $LAB-r1 vtysh -c 'show vrrp' > "$ART/post_recovery_show_vrrp_r1.txt"
  tail -3 "$ART/ping_h1_to_h2.txt" | tee -a "$ART/timeline.txt"
  log "scenario $name done"
}

run_scenario a-control-plane-freeze \
    "docker pause $LAB-r1" \
    "docker unpause $LAB-r1"

sleep 8

run_scenario b-lan-interface-down \
    "docker exec $LAB-r1 ip link set eth1 down" \
    "docker exec $LAB-r1 ip link set eth1 up"

sleep 8
echo "final roles:"
docker exec $LAB-r1 vtysh -c 'show vrrp' | grep -E 'Status \(v4\)' || true
docker exec $LAB-r2 vtysh -c 'show vrrp' | grep -E 'Status \(v4\)' || true
echo "artifacts in $BASE"
