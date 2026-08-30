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

## 4. The satellite baseline measured 600ms RTT

**Symptom:** drill 3's "no impairment" baseline reported 12 Mbps and the
baseline ping showed 600ms RTT, on a veth path that should run at gigabits
with microsecond latency.

**Diagnosis:** the previous run of the drill had died halfway (a sysctl key
that does not exist inside network namespaces, net.core.rmem_max, tripped
set -e) and its cleanup never ran, leaving tc netem applied on the provider
router. The next run inherited a poisoned network and measured the impairment
as its baseline.

**Fix:** two changes to the drill: it now deletes any leftover qdiscs and
resets congestion control before measuring anything, and a trap removes the
impairment on every exit path. Rerun produced a sane baseline (5486 Mbps,
0.095ms).

**Lesson:** experiments that mutate shared state must be self cleaning at
start, not just at end: cleanup code after a failure never runs. And a
baseline that looks remotely plausible is not the same as a correct baseline;
the RTT line exposed this instantly.

## 5. The first IKE SA came up over the management network

**Symptom:** drill 2's teardown log showed the IKE SA between
172.20.20.13[4500] and 172.20.20.9[4500], the containerlab management
addresses, not the 192.0.2.x loopbacks the tunnel is designed around.

**Diagnosis:** strongSwan's auto=start initiates at boot, before BGP has
converged. At that moment the only route to the peer loopback is the
container's default route, which points out the management interface, and the
management bridge happily delivers it. The ESP protected GRE data always used
the real provider path (the drill's provider side capture shows the ESP), but
the IKE control channel had quietly taken an out of band shortcut.

**Fix:** none required for correctness, and the renegotiation during drill 2
established the SA between the loopbacks over the real path (visible in the
steady state ipsec statusall). Documented instead of hidden, because "the
control plane took a path you did not design" is exactly the kind of thing an
interviewer should hear you notice.

**Lesson:** out of band management networks are real paths. Anything that
races convergence at boot may use them, and only inspection of addresses and
captures reveals it.

## 6. CI failed on an adjacency that always worked locally

**Symptom:** first CI run: 8 of 10 module 1 tests pass in the GitHub runner,
but r1 and r2 each report one Full OSPF neighbor instead of two. The missing
adjacency is exactly the r1 to r2 pairing across the LAN bridge. VRRP on the
same segment had converged fine.

**Diagnosis:** OSPF's broadcast network state machine. On a multi access
segment, routers sit in Waiting state for a full dead interval (40s) before
electing DR and BDR, and only then proceed to database exchange. The CI
workflow slept 35 seconds: it tested inside the wait timer window. Locally the
lab always had more than a minute between deploy and the first check, which
hid the boundary. The point to point adjacencies formed in seconds because
point to point networks skip the election entirely.

**Fix:** replaced the blind sleep with a convergence poll that checks r1's
Full neighbor count every 10s (and logs how long convergence actually took).

**Lesson:** CI is a timing microscope: it runs the exact same commands at a
phase of the lab's life a human never observes. Convergence gates should poll
for the condition, not sleep for a guess, and the 40s broadcast wait timer is
a real number worth knowing cold.
