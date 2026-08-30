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

campus-destroy:
	containerlab destroy -t $(CAMPUS)/topology.clab.yml --cleanup
