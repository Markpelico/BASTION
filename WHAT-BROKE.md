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
