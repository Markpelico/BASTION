#!/usr/bin/env bash
# Collect steady state artifacts from the healthy wan-edge lab.
set -euo pipefail
LAB=clab-bastion-wan
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/steady-state"
mkdir -p "$ART"

for r in s1r s2r ispa ispb; do
  docker exec $LAB-$r vtysh -c 'show bgp summary' > "$ART/${r}_show_bgp_summary.txt"
  docker exec $LAB-$r vtysh -c 'show ip bgp' > "$ART/${r}_show_ip_bgp.txt"
done
docker exec $LAB-s1r vtysh -c 'show ip bgp 203.0.113.0/24' > "$ART/s1r_bestpath_localpref.txt"
docker exec $LAB-ispb vtysh -c 'show ip bgp 198.51.100.0/24' > "$ART/ispb_three_paths_prepend.txt"
docker exec $LAB-s1r vtysh -c 'show ip ospf neighbor' > "$ART/s1r_ospf_over_gre.txt"
docker exec $LAB-s1r vtysh -c 'show ip route' > "$ART/s1r_show_ip_route.txt"
docker exec $LAB-s1r ipsec statusall > "$ART/s1r_ipsec_statusall.txt"
docker exec $LAB-s1r ip -s tunnel show gre1 > "$ART/s1r_gre_tunnel.txt" 2>/dev/null || \
  docker exec $LAB-s1r ip tunnel show > "$ART/s1r_gre_tunnel.txt"
docker exec $LAB-s1h traceroute -n -q1 -w1 203.0.113.100 > "$ART/s1h_traceroute_public.txt" || true
docker exec $LAB-s1h traceroute -n -q1 -w1 10.102.0.100 > "$ART/s1h_traceroute_private.txt" || true
echo "steady state artifacts in $ART"
