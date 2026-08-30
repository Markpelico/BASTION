#!/usr/bin/env bash
# Drill 3: satellite conditions. Add 600ms RTT (300ms each way on ispa's two
# site facing interfaces) plus 0.5% loss with tc netem, measure the TCP
# throughput collapse with iperf3, then tune TCP (BBR congestion control and
# larger socket buffers) and measure again. Numbers land in results.txt.
set -euo pipefail
LAB=clab-bastion-wan
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill3-satellite"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

mbps() { jq -r '.end.sum_received.bits_per_second / 1e6 | floor' "$1" 2>/dev/null || echo "?"; }
retrans() { jq -r '.end.sum_sent.retransmits' "$1" 2>/dev/null || echo "?"; }

# A previous run that died mid drill leaves netem applied, which silently
# poisons the next baseline (learned the hard way: a "baseline" once measured
# 600ms RTT). Clean before measuring, and clean again on any exit.
clean_impairment() {
  docker exec $LAB-ispa tc qdisc del dev eth1 root 2>/dev/null || true
  docker exec $LAB-ispa tc qdisc del dev eth2 root 2>/dev/null || true
}
trap clean_impairment EXIT
log "pre clean: removing any leftover impairment and resetting congestion control"
clean_impairment
for h in s1h s2h; do
  docker exec $LAB-$h sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
done

log "starting iperf3 server on s2h"
docker exec -d $LAB-s2h iperf3 -s -1 >/dev/null 2>&1 || true
docker exec -d $LAB-s2h sh -c 'pkill iperf3; sleep 0.5; iperf3 -s -D'
sleep 1

log "baseline RTT and throughput (no impairment)"
docker exec $LAB-s1h ping -c 5 203.0.113.100 > "$ART/rtt_baseline.txt"
docker exec $LAB-s1h iperf3 -c 203.0.113.100 -t 8 -J > "$ART/iperf_baseline.json"

log "applying netem: 300ms delay and 0.5% loss on ispa eth1 and eth2"
docker exec $LAB-ispa tc qdisc replace dev eth1 root netem delay 300ms loss 0.5%
docker exec $LAB-ispa tc qdisc replace dev eth2 root netem delay 300ms loss 0.5%
docker exec $LAB-ispa tc qdisc show dev eth1 > "$ART/netem_config.txt"
docker exec $LAB-ispa tc qdisc show dev eth2 >> "$ART/netem_config.txt"
sleep 1

log "satellite RTT proof and throughput with default TCP (cubic)"
docker exec $LAB-s1h ping -c 5 203.0.113.100 > "$ART/rtt_satellite.txt"
docker exec $LAB-s1h iperf3 -c 203.0.113.100 -t 15 -J > "$ART/iperf_satellite_cubic.json"

log "tuning TCP on both hosts: BBR plus 64MB TCP buffer ceilings"
# net.core.* is not namespaced inside containers; the namespaced
# net.ipv4.tcp_rmem and tcp_wmem ceilings are what TCP autotuning uses.
for h in s1h s2h; do
  docker exec $LAB-$h sysctl -w net.ipv4.tcp_congestion_control=bbr \
      net.ipv4.tcp_rmem="4096 262144 67108864" \
      net.ipv4.tcp_wmem="4096 262144 67108864" >> "$ART/tuning_applied.txt"
done
docker exec $LAB-s2h sh -c 'pkill iperf3; sleep 0.5; iperf3 -s -D'
sleep 1

log "satellite throughput with tuned TCP (bbr, big windows)"
docker exec $LAB-s1h iperf3 -c 203.0.113.100 -t 15 -J > "$ART/iperf_satellite_tuned.json"

log "cleanup: removing netem, restoring cubic"
docker exec $LAB-ispa tc qdisc del dev eth1 root
docker exec $LAB-ispa tc qdisc del dev eth2 root
for h in s1h s2h; do
  docker exec $LAB-$h sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
done
docker exec $LAB-s2h pkill iperf3 || true

{
  echo "results (throughput in Mbps, from iperf3 JSON):"
  echo "  baseline, no impairment:        $(mbps "$ART/iperf_baseline.json") Mbps, $(retrans "$ART/iperf_baseline.json") retransmits"
  echo "  600ms RTT + 0.5% loss, cubic:   $(mbps "$ART/iperf_satellite_cubic.json") Mbps, $(retrans "$ART/iperf_satellite_cubic.json") retransmits"
  echo "  600ms RTT + 0.5% loss, tuned:   $(mbps "$ART/iperf_satellite_tuned.json") Mbps, $(retrans "$ART/iperf_satellite_tuned.json") retransmits"
  echo
  echo "rtt baseline:  $(grep 'rtt min' "$ART/rtt_baseline.txt")"
  echo "rtt satellite: $(grep 'rtt min' "$ART/rtt_satellite.txt")"
} > "$ART/results.txt"
cat "$ART/results.txt" | tee -a "$ART/timeline.txt"
log "done: artifacts in $ART"
