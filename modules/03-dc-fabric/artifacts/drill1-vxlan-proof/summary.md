# Drill 1 summary: multi tenancy on the wire

One destination address, 172.16.1.102, pinged from two tenants while both l1
spine uplinks are captured. Everything below is read from the two pcaps and
the control plane dumps in this directory.

## The decisive capture

From vxlan_decode.txt (outer VTEP addresses, VNI, inner ICMP):

```
tenant B: 10.255.255.1 -> 10.255.255.3   VNI 10020   inner 172.16.1.101 -> 172.16.1.102
tenant A: 10.255.255.1 -> 10.255.255.2   VNI 10010   inner 172.16.1.101 -> 172.16.1.102
```

Identical inner source and destination addresses leave the same leaf toward
two different physical destinations, separated only by the VNI in the VXLAN
header. That is the entire multi tenant overlay argument in two lines: the
fabric routes on outer headers (VTEP loopbacks), tenants keep private and
even conflicting address plans, and the VNI is the isolation boundary.

A bonus visible in the same capture: the two tenants hashed onto different
uplinks (tenant A via eth2, tenant B via eth1), which is underlay ECMP doing
its job on the outer header five tuple.

## Control plane evidence

- l1_evpn_routes.txt: type 2 routes (MAC and MAC/IP) for the hosts, type 3
  IMET routes from every VTEP per VNI.
- l1_evpn_macs.txt: remote MACs installed against remote VTEPs, local MACs
  against access ports.
- l1_bridge_fdb_tenantA.txt: the kernel view: hA2's MAC pinned to the vxlan
  device with dst 10.255.255.2, installed by FRR (the bridge has learning
  off; nothing here was flood learned).

The validation suite asserts the same facts mechanically, including that the
two tenants resolve 172.16.1.102 to different physical hosts
(test_overlapping_ip_resolves_to_different_hosts_per_tenant).
