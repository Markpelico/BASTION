SHELL := /bin/bash
MODULES := modules

.PHONY: gen-all check campus-deploy campus-test campus-drills campus-destroy

gen-all:
	python3 tools/generate.py --all

check:
	python3 tools/check_style.py

# ---------------- module 1: campus-core ----------------
CAMPUS := $(MODULES)/01-campus-core

campus-deploy:
	python3 tools/generate.py --module 01-campus-core
	ip link show br-campus >/dev/null 2>&1 || { ip link add br-campus type bridge && ip link set br-campus up; }
	containerlab deploy -t $(CAMPUS)/topology.clab.yml --reconfigure

campus-test:
	cd $(CAMPUS) && python3 -m pytest tests/ -v

campus-drill-vrrp:
	bash $(CAMPUS)/drills/drill1_vrrp_failover.sh

campus-drill-ospf:
	bash $(CAMPUS)/drills/drill2_ospf_reconvergence.sh

campus-drills: campus-drill-vrrp campus-drill-ospf

campus-drift:
	python3 tools/driftcheck.py --module 01-campus-core --lab clab-bastion-campus

campus-destroy:
	containerlab destroy -t $(CAMPUS)/topology.clab.yml --cleanup

# ---------------- module 2: wan-edge ----------------
WAN := $(MODULES)/02-wan-edge

wan-image:
	docker build -t bastion/frr-vpn:lab images/frr-vpn

wan-deploy: wan-image
	python3 tools/generate.py --module 02-wan-edge
	containerlab deploy -t $(WAN)/topology.clab.yml --reconfigure

wan-test:
	cd $(WAN) && python3 -m pytest tests/ -v

wan-drill-bgp:
	bash $(WAN)/drills/drill1_bgp_failover.sh

wan-drill-ipsec:
	bash $(WAN)/drills/drill2_encryption_onoff.sh

wan-drill-satellite:
	bash $(WAN)/drills/drill3_satellite.sh

wan-drills: wan-drill-bgp wan-drill-ipsec wan-drill-satellite

wan-drift:
	python3 tools/driftcheck.py --module 02-wan-edge --lab clab-bastion-wan

wan-destroy:
	containerlab destroy -t $(WAN)/topology.clab.yml --cleanup

# ---------------- module 3: dc-fabric ----------------
DC := $(MODULES)/03-dc-fabric

dc-deploy:
	python3 tools/generate.py --module 03-dc-fabric
	containerlab deploy -t $(DC)/topology.clab.yml --reconfigure

dc-test:
	cd $(DC) && python3 -m pytest tests/ -v

dc-drill-vxlan:
	bash $(DC)/drills/drill1_vxlan_proof.sh

dc-drill-spine:
	bash $(DC)/drills/drill2_spine_failure.sh

dc-drills: dc-drill-vxlan dc-drill-spine

dc-drift:
	python3 tools/driftcheck.py --module 03-dc-fabric --lab clab-bastion-dc

dc-destroy:
	containerlab destroy -t $(DC)/topology.clab.yml --cleanup
