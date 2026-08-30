#!/bin/bash
# Bring up the firewall's control and monitoring plane:
#   1. load the nftables ruleset
#   2. ulogd bridges the nft NFLOG denies into syslog
#   3. rsyslog forwards syslog to the collector
#   4. softflowd exports NetFlow for traffic crossing the outside interface
set -e

nft -f /etc/nftables.conf

# rsyslog: read the local syslog socket (where ulogd writes the firewall
# denies) and forward everything to the collector over UDP 514.
cat > /etc/rsyslog.d/60-forward.conf <<'CONF'
module(load="imuxsock")
*.* action(type="omfwd" target="172.31.0.50" port="514" protocol="udp")
CONF
setsid rsyslogd
sleep 1

# ulogd: bridge NFLOG group 1 (the nft denies) into syslog. Delivered over
# netlink, so it does not depend on kernel ring buffer access in a container.
# Backgrounded explicitly (ulogd runs in the foreground) and not allowed to
# abort the rest of the startup if it hiccups.
setsid ulogd -c /etc/ulogd.conf >/var/log/ulogd.stdout 2>&1 < /dev/null &

# softflowd: export NetFlow for traffic crossing the outside interface.
# v5 (fixed record format, no templates) is used deliberately: NetFlow v9
# only lets the collector decode data once it has received the periodic
# template FlowSet, so a short lab drill loses its first records to
# "unknown template". v5 decodes immediately, which is what a bounded drill
# needs. maxlife=5 forces long flows to expire and export quickly.
softflowd -i eth2 -n 172.31.0.50:9995 -v 5 -t maxlife=5

echo "firewall control plane up: nft loaded, ulogd bridging NFLOG, rsyslog forwarding, softflowd exporting"
