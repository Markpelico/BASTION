#!/usr/bin/env bash
# Build the annotated capture library. Each capture is produced live here, in
# this lab, and paired with a walkthrough in captures/README.md. No canned
# pcaps. tcpdump inside a netns needs a moment to attach before traffic flows,
# so each capture settles for 3s before generating its packets.
set -euo pipefail
LAB=clab-bastion-boundary
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CAP="$DIR/captures"
mkdir -p "$CAP"

capture() { # capture <node> <iface> <outfile> <bpf> ; then caller makes traffic
  local node="$1" iface="$2" outf="$3" bpf="$4"
  ip netns exec $LAB-$node tcpdump -i "$iface" -U -w "$outf" $bpf 2>/dev/null &
  CAP_PID=$!
  sleep 3
}
stop() { sleep 1.5; kill $CAP_PID 2>/dev/null || true; wait $CAP_PID 2>/dev/null || true; }

echo "capture 1: TCP handshake and teardown (outside to published web :80)"
capture outside eth1 "$CAP/tcp_handshake.pcap" "tcp port 80"
docker exec $LAB-outside curl -s -o /dev/null --max-time 4 http://10.10.10.100/ || true
stop

echo "capture 2: denied SYNs at the boundary (outside to a blocked port)"
capture fw eth2 "$CAP/denied_syn.pcap" "tcp port 22"
docker exec $LAB-outside timeout 3 hping3 -S -p 22 -c 6 -i u400000 10.10.10.100 >/dev/null 2>&1 || true
stop

echo "capture 3a: NAT, inside view (real inside source address)"
capture fw eth1 "$CAP/nat_inside.pcap" "icmp"
docker exec $LAB-inside ping -c 4 -i 0.4 203.0.113.100 >/dev/null 2>&1 || true
stop
echo "capture 3b: NAT, outside view (rewritten to the firewall address)"
capture fw eth2 "$CAP/nat_outside.pcap" "icmp"
docker exec $LAB-inside ping -c 4 -i 0.4 203.0.113.100 >/dev/null 2>&1 || true
stop

echo "capture 4: NetFlow v5 export (softflowd to nfcapd, UDP 9995)"
# The export is bursty: a reliable burst of short TCP flows to the open port
# produces plenty of export datagrams while the capture runs, then editcap
# trims the saved pcap to the first 60 packets so the committed artifact stays
# small and readable (see WHAT-BROKE.md entry 9 for why tuning traffic volume
# alone is unreliable).
capture collector eth1 "$CAP/netflow_export.pcap" "udp port 9995"
# A brief high rate burst reliably drives softflowd to export many datagrams
# during the capture window (a light burst can slip between export batches).
docker exec $LAB-outside sh -c 'timeout 4 hping3 -S -p 80 --flood 10.10.10.100 >/dev/null 2>&1' || true
sleep 2
stop
# Trim the saved pcap to the first 60 export datagrams so the committed
# artifact stays small; the full export volume is proven by nfdump in the drill.
if [ "$(tshark -r "$CAP/netflow_export.pcap" 2>/dev/null | wc -l)" -gt 60 ]; then
  editcap -r "$CAP/netflow_export.pcap" "$CAP/netflow_export.trimmed.pcap" 1-60
  mv "$CAP/netflow_export.trimmed.pcap" "$CAP/netflow_export.pcap"
fi

echo "captures written:"
for f in "$CAP"/*.pcap; do
  printf "  %-24s %s packets\n" "$(basename "$f")" "$(tshark -r "$f" 2>/dev/null | wc -l)"
done
