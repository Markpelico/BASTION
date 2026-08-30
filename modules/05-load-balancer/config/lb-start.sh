#!/bin/bash
# Start HAProxy in the foreground under setsid so the containerlab exec returns.
set -e
setsid haproxy -f /etc/haproxy/haproxy.cfg >/var/log/haproxy.log 2>&1 < /dev/null &
sleep 1
echo "haproxy up: L7 VIP 10.20.0.10:80, L4 VIP :8404, stats :8405/stats"
