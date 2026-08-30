#!/bin/sh
# Start strongSwan's starter/charon in the background, then hand the
# container over to FRR's normal init (which supervises the routing daemons).
ipsec start 2>/dev/null || true
exec /usr/lib/frr/docker-start
