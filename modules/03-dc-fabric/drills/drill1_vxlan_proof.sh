#!/usr/bin/env bash
# Drill 1: catch VXLAN in the act. Capture on l1's spine uplinks while the
# same destination address, 172.16.1.102, is pinged in tenant A and tenant B.
# The captures must show the same inner destination leaving l1 toward two
# different VTEPs with two different VNIs: multi tenancy on the wire.
set -euo pipefail
LAB=clab-bastion-dc
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill1-vxlan-proof"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "capturing on l1 spine uplinks (udp 4789)"
ip netns exec $LAB-l1 tcpdump -i eth1 -U -w "$ART/l1_eth1_vxlan.pcap" 'udp port 4789' 2>/dev/null &
P1=$!
ip netns exec $LAB-l1 tcpdump -i eth2 -U -w "$ART/l1_eth2_vxlan.pcap" 'udp port 4789' 2>/dev/null &
P2=$!
sleep 2

log "tenant A: hA1 pings 172.16.1.102 (should reach hA2 behind l2, VNI 10010)"
docker exec $LAB-hA1 ping -c 5 -i 0.3 172.16.1.102 > "$ART/ping_tenantA.txt"
log "tenant B: hB1 pings 172.16.1.102 (should reach hB3 behind l3, VNI 10020)"
docker exec $LAB-hB1 ping -c 5 -i 0.3 172.16.1.102 > "$ART/ping_tenantB.txt"
sleep 2
kill $P1 $P2 2>/dev/null || true
wait $P1 $P2 2>/dev/null || true

log "control plane artifacts"
docker exec $LAB-l1 vtysh -c 'show bgp l2vpn evpn summary' > "$ART/l1_evpn_summary.txt"
docker exec $LAB-l1 vtysh -c 'show bgp l2vpn evpn route' > "$ART/l1_evpn_routes.txt"
docker exec $LAB-l1 vtysh -c 'show evpn vni' > "$ART/l1_evpn_vni.txt"
docker exec $LAB-l1 vtysh -c 'show evpn mac vni all' > "$ART/l1_evpn_macs.txt"
docker exec $LAB-l1 bridge fdb show br brA > "$ART/l1_bridge_fdb_tenantA.txt"

log "decoding: one encapsulated frame per tenant, outer and inner headers"
{
  echo "== every VXLAN packet on l1 uplinks (time, outer src -> dst, VNI, inner icmp type):"
  for f in "$ART/l1_eth1_vxlan.pcap" "$ART/l1_eth2_vxlan.pcap"; do
    echo "-- $(basename "$f"):"
    tshark -r "$f" -Y vxlan -T fields -e frame.time_relative -e ip.src -e ip.dst \
      -e vxlan.vni -e icmp.type 2>/dev/null | head -12 || true
  done
  for vni in 10010 10020; do
    echo
    echo "== full decode of the first VNI $vni frame (either uplink, ECMP decides):"
    for f in "$ART/l1_eth1_vxlan.pcap" "$ART/l1_eth2_vxlan.pcap"; do
      tshark -r "$f" -Y "vxlan.vni==$vni" -c 1 -V 2>/dev/null \
        | grep -E "Internet Protocol|Virtual eXtensible|Identifier \(VNI\)|Echo" || true
    done | head -14
  done
} > "$ART/vxlan_decode.txt"
cat "$ART/vxlan_decode.txt" | tee -a "$ART/timeline.txt" | head -30
log "done: artifacts in $ART"
