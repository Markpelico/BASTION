#!/usr/bin/env bash
# Collect steady state artifacts from the healthy lab: adjacencies, routes,
# VRRP roles, and the macvlan details behind FRR's VRRP implementation.
set -euo pipefail
LAB=clab-bastion-campus
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/steady-state"
mkdir -p "$ART"

for r in r1 r2 r3 r4; do
  docker exec $LAB-$r vtysh -c 'show ip ospf neighbor' > "$ART/${r}_show_ip_ospf_neighbor.txt"
  docker exec $LAB-$r vtysh -c 'show ip route' > "$ART/${r}_show_ip_route.txt"
done
docker exec $LAB-r3 vtysh -c 'show ip ospf database' > "$ART/r3_show_ip_ospf_database.txt"
docker exec $LAB-r1 vtysh -c 'show ip ospf interface eth1' > "$ART/r1_show_ip_ospf_interface_eth1.txt"
docker exec $LAB-r1 vtysh -c 'show vrrp' > "$ART/r1_show_vrrp.txt"
docker exec $LAB-r2 vtysh -c 'show vrrp' > "$ART/r2_show_vrrp.txt"
docker exec $LAB-r1 ip -d link show vrrp4-10 > "$ART/r1_ip_link_vrrp_macvlan.txt"
docker exec $LAB-r2 ip -d link show vrrp4-10 > "$ART/r2_ip_link_vrrp_macvlan.txt"
docker exec $LAB-h1 traceroute -n -q1 -w1 10.40.0.100 > "$ART/h1_traceroute_h2.txt" || true
echo "steady state artifacts in $ART"
