#!/usr/bin/env bash
# Drill 2: prove what the provider can and cannot read.
# Capture on ispa's site1 facing interface while private traffic crosses the
# GRE over IPsec tunnel, then tear the IPsec SAs down, send the same traffic
# as bare GRE, and bring encryption back (capturing the IKEv2 negotiation).
set -euo pipefail
LAB=clab-bastion-wan
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill2-encryption-onoff"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "starting capture on ispa eth1 (what the provider sees)"
ip netns exec $LAB-ispa tcpdump -i eth1 -U -w "$ART/ispa_eth1_provider_view.pcap" \
    'esp or proto gre or udp port 500 or udp port 4500' 2> "$ART/tcpdump.log" &
TPID=$!
sleep 2

log "phase 1: 10 private pings with IPsec up (provider should see only ESP)"
docker exec $LAB-s1r ipsec status > "$ART/phase1_ipsec_status.txt"
docker exec $LAB-s1h ping -c 10 -i 0.2 10.102.0.100 > "$ART/phase1_ping.txt"
sleep 2

log "phase 2: tearing down IPsec on both sites, same pings as bare GRE"
docker exec $LAB-s1r ipsec down gre || true
docker exec $LAB-s2r ipsec down gre || true
sleep 2
docker exec $LAB-s1h ping -c 10 -i 0.2 10.102.0.100 > "$ART/phase2_ping.txt" || true
sleep 2

log "phase 3: ipsec up (IKEv2 negotiation lands in the capture), pings again"
docker exec $LAB-s1r ipsec up gre > "$ART/phase3_ipsec_up.txt" 2>&1 || true
sleep 2
docker exec $LAB-s1h ping -c 10 -i 0.2 10.102.0.100 > "$ART/phase3_ping.txt"
docker exec $LAB-s1r ipsec status > "$ART/phase3_ipsec_status.txt"
sleep 2

kill $TPID 2>/dev/null || true
wait $TPID 2>/dev/null || true

log "analysis: per phase protocol counts from the provider capture"
{
  echo "esp packets:";  tshark -r "$ART/ispa_eth1_provider_view.pcap" -Y esp  2>/dev/null | wc -l
  echo "cleartext gre packets:"; tshark -r "$ART/ispa_eth1_provider_view.pcap" -Y "gre and not esp" 2>/dev/null | wc -l
  echo "ikev2 packets:"; tshark -r "$ART/ispa_eth1_provider_view.pcap" -Y isakmp 2>/dev/null | wc -l
  echo; echo "what cleartext GRE exposes (inner protocol summary):"
  tshark -r "$ART/ispa_eth1_provider_view.pcap" -Y "gre and not esp" 2>/dev/null | head -8
  echo; echo "IKEv2 exchanges:"
  tshark -r "$ART/ispa_eth1_provider_view.pcap" -Y isakmp 2>/dev/null | head -6
} > "$ART/provider_view_analysis.txt"
cat "$ART/provider_view_analysis.txt" | tee -a "$ART/timeline.txt"
log "done: artifacts in $ART"
