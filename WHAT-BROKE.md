# What broke, and how it was diagnosed

Honest notes from the build. Only things that actually happened.

## 1. The WSL distro was silently WSL 1, and containerlab needs WSL 2

**Symptom:** `wsl -l -v` showed `Ubuntu-24.04 ... VERSION 1` and `wsl --status`
reported `Default Version: 1`, even though the machine also runs a WSL 2 based
Docker Desktop backend. containerlab requires a real Linux kernel with network
namespaces, which WSL 1 does not provide (it is a syscall translation layer, not
a VM).

**Diagnosis:** the registry entry under `HKCU\...\Lxss` showed `Version: 2`,
which looks contradictory until you know that field is the distro storage format
version, not the WSL version. The authoritative source is `wsl -l -v`. The
on-disk layout confirmed it: a `rootfs` directory (WSL 1 stores files directly
on NTFS) instead of an `ext4.vhdx` (WSL 2 stores a real ext4 filesystem in a
virtual disk).

**Fix:** in-place conversion with `wsl --set-version Ubuntu-24.04 2`, which
repacks the root filesystem into a VHDX. The only errors were bsdtar warnings
about stale VS Code IPC sockets in `/tmp` (sockets cannot be archived, and do
not need to be). Afterward, `wsl --set-default-version 2` so future distros do
not repeat this.

**Lesson:** verify the platform layer before trusting it. The machine "had WSL
and Docker" but neither was actually in a usable state for network labs.

## 2. The VRRP loss window refused to exist

**Symptom:** drill 1 was designed to "kill the VRRP master mid ping and measure
the loss window." First attempt (docker pause r1): 197 of 197 pings survived.
Redesigned attempt (r1 LAN interface down, so the data path dies too): still
197 of 197. The textbook says 3 to 4 seconds of blackout; the lab kept saying
zero.

**Diagnosis:** stopped guessing and read the captures. The h1 side pcap showed
echo replies switching from r1's real MAC to r2's real MAC 204ms after the
failure (OSPF healed the return path with an immediate LSA), while requests to
the virtual MAC kept being answered the entire time. That left only one
possible forwarder, so a targeted probe captured on r2's interface while
reading its VRRP role 1.6s after the failure: `Status (v4) Backup` while
forwarding virtual MAC frames. The bridge had flushed the dead port and flooded
unknown unicast at r2, whose FRR macvlan keeps the virtual MAC programmed even
in Backup (protodown notwithstanding).

**Fix:** none needed; the behavior is correct and the drill now documents both
scenarios plus the probe, with the mechanism proven per packet.

**Lesson:** when a measurement contradicts theory, the measurement is the
starting point, not the enemy. Also: FHRP failover behavior depends on how the
virtual MAC is programmed, which is an implementation property, not a protocol
property.

## 3. FRR said "No changes found to be committed!" while changing everything

**Symptom:** drill 2 shuts r1's uplink with vtysh (`interface eth2`,
`shutdown`). FRR 10.7 answered `% Configuration applied with notes: No changes
found to be committed!`, which reads exactly like the command was a no op.

**Diagnosis:** checked the kernel instead of the message: `ip link show eth2`
inside the container reported `state DOWN`, the capture shows r1 originating a
new router LSA 100ms later, and the routing table flipped to the backup path.
The message is noise from the new mgmtd transactional backend commenting on its
own config store.

**Lesson:** command output is a claim, not a fact. Verify state changes at the
layer that owns them (kernel link state, LSDB, routing table).
