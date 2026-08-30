# Monitoring and traffic tooling for module 4, on the netshoot base
# (which already carries nft, iptables, tcpdump, nmap, iperf3).
#   softflowd  NetFlow v9 exporter
#   nfdump     NetFlow collector (nfcapd) and analyzer (nfdump)
#   rsyslog    syslog collector and forwarder
#   ulogd      bridges netfilter NFLOG (netlink) events into syslog, the
#              container friendly way to get nft denies off the box
#   hping3     crafted packet generator for firewall drills
#   haproxy    load balancer for the load-balancer stretch module
#   socat      unix socket client for the HAProxy runtime API
FROM nicolaka/netshoot:v0.16
RUN apk add --no-cache softflowd nfdump rsyslog ulogd hping3 haproxy socat
