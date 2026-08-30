# FRR plus strongSwan: the site edge router image for module 2.
# GRE over IPsec needs the routing suite and the IKE daemon in one
# network namespace, which is exactly how a real crypto capable edge
# router is built.
FROM quay.io/frrouting/frr:10.7.1
RUN apk add --no-cache strongswan
COPY start-vpn.sh /usr/local/bin/start-vpn.sh
RUN chmod +x /usr/local/bin/start-vpn.sh
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/start-vpn.sh"]
