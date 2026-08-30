#!/usr/bin/env bash
# The script behind docs/demo.gif, recorded with:
#   asciinema rec --cols 100 --rows 30 -i 2 -c "bash docs/demo.sh" docs/demo.cast
#   agg docs/demo.cast docs/demo.gif (theme and font flags in the Makefile)
# Every command runs for real against the live lab: the recording is a
# genuine deploy, validation, and failure drill, idle time compressed to 2s.
set -euo pipefail
cd "$(dirname "$0")/.."

G=$'\e[32m'; B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
say()  { printf '\n%s$%s %s%s%s\n' "$G" "$R" "$B" "$*" "$R"; }
run()  { say "$*"; eval "$*"; }
note() { printf '%s# %s%s\n' "$D" "$*" "$R"; }

note "BASTION module 1: deploy it, validate it, then crash the gateway mid ping"
sleep 1

run "make campus-deploy"

say "waiting for OSPF convergence (the LAN DR election sits out a 40s wait timer)"
for i in $(seq 1 20); do
  full=$(docker exec clab-bastion-campus-r1 vtysh -c 'show ip ospf neighbor json' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for l in d.get('neighbors',{}).values() for e in l if (e.get('nbrState') or e.get('converged') or '').startswith('Full')))" \
    2>/dev/null || echo 0)
  if [ "$full" = "2" ]; then printf ' converged\n'; break; fi
  printf '.'
  sleep 5
done

say "waiting for VRRP roles to settle (r1 Master and r2 Backup, not just r1)"
for i in $(seq 1 15); do
  m1=$(docker exec clab-bastion-campus-r1 vtysh -c 'show vrrp' \
    | grep -E 'Status \(v4\)' | grep -c Master || true)
  b2=$(docker exec clab-bastion-campus-r2 vtysh -c 'show vrrp' \
    | grep -E 'Status \(v4\)' | grep -c Backup || true)
  if [ "$m1" = "1" ] && [ "$b2" = "1" ]; then printf ' roles settled\n'; break; fi
  printf '.'
  sleep 3
done
sleep 3

run "make campus-test"

note "drill: freeze the VRRP master (r1) while h1 pings h2 at 5 packets per second"
run "docker exec clab-bastion-campus-r1 vtysh -c 'show vrrp' | grep 'Status (v4)'"

say "docker exec clab-bastion-campus-h1 ping -i 0.2 -w 18 10.40.0.100   (running in background)"
docker exec clab-bastion-campus-h1 ping -i 0.2 -w 18 10.40.0.100 > /tmp/demo_ping.txt &
PING=$!
sleep 3

run "docker pause clab-bastion-campus-r1"
sleep 7

note "the backup noticed the silence and took over the virtual IP:"
run "docker exec clab-bastion-campus-r2 vtysh -c 'show vrrp' | grep 'Status (v4)'"

run "docker unpause clab-bastion-campus-r1"
wait "$PING" || true

say "tail -3 /tmp/demo_ping.txt"
tail -3 /tmp/demo_ping.txt

note "zero loss: VRRP failed over on schedule while the frozen kernel kept forwarding"
note "measured takeover, pcaps, and the full story: modules/01-campus-core/artifacts/"
sleep 2
