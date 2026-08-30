#!/usr/bin/env bash
# Probe: does the VRRP backup forward frames addressed to the virtual MAC
# while it is still in Backup state?
#
# Method: capture on r2 eth1, take r1's LAN leg down, ping the VIP path from
# h1 immediately (inside the master down interval), and read r2's VRRP role
# 1.6s after the failure. If r2 reports Backup while the capture shows echo
# requests to 00:00:5e:00:01:0a being answered, the backup's data plane is
# carrying VMAC traffic before the VRRP state machine promotes it.
set -euo pipefail
LAB=clab-bastion-campus
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill1-vrrp-failover"
mkdir -p "$ART"

ip netns exec $LAB-r2 tcpdump -i eth1 -U -c 40 -w "$ART/probe_r2_backup_forwarding.pcap" icmp 2>/dev/null &
TPID=$!
sleep 1
docker exec $LAB-r1 ip link set eth1 down
docker exec $LAB-h1 ping -c 8 -i 0.3 -W 1 10.40.0.100 > "$ART/probe_ping.txt" &
PINGPID=$!
sleep 1.6
docker exec $LAB-r2 vtysh -c 'show vrrp' | grep 'Status (v4)' \
    | tee "$ART/probe_r2_role_at_1600ms.txt"
wait $PINGPID || true
docker exec $LAB-r1 ip link set eth1 up
sleep 8
kill $TPID 2>/dev/null || true
wait 2>/dev/null || true
tail -3 "$ART/probe_ping.txt"
echo "probe artifacts in $ART"
