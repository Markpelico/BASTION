#!/usr/bin/env bash
# Drill: kill one backend mid stream and show HAProxy health checks removing it
# from rotation, then restoring it. The client polls the VIP continuously; the
# response body names which backend served each request.
set -euo pipefail
LAB=clab-bastion-lb
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART="$DIR/artifacts/drill1-backend-failure"
rm -rf "$ART"; mkdir -p "$ART"
: > "$ART/timeline.txt"
ts() { date +%H:%M:%S.%3N; }
log() { echo "[$(ts)] $*" | tee -a "$ART/timeline.txt"; }

log "pre state: which backends are up"
docker exec $LAB-lb sh -c "echo 'show stat' | socat stdio /var/run/haproxy.sock 2>/dev/null" \
    > "$ART/pre_haproxy_stat.csv" 2>/dev/null || \
    docker exec $LAB-lb sh -c 'curl -s http://10.20.0.10:8405/stats' > "$ART/pre_stats.html" || true

log "polling the VIP 60 times at 0.25s; killing web1 partway"
: > "$ART/responses.txt"
for i in $(seq 1 60); do
  r=$(docker exec $LAB-client curl -s --max-time 2 http://10.20.0.10/id 2>/dev/null || echo "FAILED")
  echo "$i $(ts) $r" >> "$ART/responses.txt"
  if [ "$i" = "15" ]; then
    log "FAILURE: stopping web1 http server"
    docker exec $LAB-web1 sh -c 'pkill -f http.server' 2>/dev/null || true
  fi
  if [ "$i" = "40" ]; then
    log "RECOVERY: restarting web1 http server"
    docker exec $LAB-web1 sh -c 'setsid python3 -m http.server 8080 --directory /tmp >/tmp/http.log 2>&1 < /dev/null &' || true
  fi
  sleep 0.25
done

log "analysis"
{
  echo "== response distribution across the whole run:"
  awk '{print $NF}' "$ART/responses.txt" | sort | uniq -c
  echo
  echo "== during outage (requests 18 to 38, after health checks react):"
  awk 'NR>=18 && NR<=38 {print $NF}' "$ART/responses.txt" | sort | uniq -c
  echo
  echo "== any failed requests (client saw an error):"
  grep -c FAILED "$ART/responses.txt" || echo 0
} > "$ART/analysis.txt"
cat "$ART/analysis.txt" | tee -a "$ART/timeline.txt"
log "done: artifacts in $ART"
