#!/bin/bash
# Collector plane: syslog reception (rsyslog) and NetFlow capture (nfcapd).
set -e
mkdir -p /var/log/lab /var/cache/nfdump

# rsyslog with the per host template bound at /etc/rsyslog.d/50-lab.conf
setsid rsyslogd

# nfcapd listens for softflowd's NetFlow v9 export and rotates files into
# /var/cache/nfdump every 10s (-t 10) so records land on disk during a short
# drill rather than on the default 5 minute boundary; nfdump reads them later.
nfcapd -t 10 -D -l /var/cache/nfdump -p 9995

echo "collector up: rsyslog on 514, nfcapd on 9995"
