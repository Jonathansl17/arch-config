# nvidia/

Optional, idempotent NVIDIA driver installer for this machine (ASUS hybrid laptop: AMD Radeon 660M iGPU + NVIDIA RTX 3050 Mobile dGPU).

**Not run by `install.sh`.** Run manually when you need it.

## What it installs

- `linux-headers`, `dkms`, `linux-firmware-nvidia` (prereqs)
- `nvidia-open-dkms` + `nvidia-utils`
- `/etc/modprobe.d/blacklist-nouveau.conf` to keep the nouveau kernel module from loading
- Regenerates initramfs via `mkinitcpio -P`

It does **not** install `nvidia-prime` or `lib32-nvidia-utils` (not needed: no gaming, no PRIME render offload on this setup — NVIDIA only wakes up for CUDA and NVENC).

## When to use

- The driver broke after an update and you want to restore the known-good setup.
- New machine install, reproducing the same NVIDIA config.
- Verifying that nothing has drifted (`--check`).

## Idempotency

If the system is already in the desired state, the script does **nothing**. It will tell you so and exit 0. The desired state is:

- prereq + nvidia packages installed
- nouveau userspace packages (`xf86-video-nouveau`, `vulkan-nouveau`) removed
- `blacklist-nouveau.conf` present with the expected content
- DKMS module installed for the running kernel
- nouveau NOT loaded, `nvidia`/`nvidia_modeset`/`nvidia_uvm`/`nvidia_drm` loaded
- `nvidia-smi` responds

If any of those is missing or wrong, only the missing phases run.

## Safety checks (preflight, exits before changing anything if any fail)

- Not running as root
- sudo works
- Root filesystem is writable (not emergency read-only)
- `/boot` ≥ 200 MB free, `/` ≥ 2 GB free
- NVIDIA GPU present in `lspci`
- Network reachable
- Pacman DB for nvidia-related packages not corrupt (auto-repaired if it is)
- Warns on Secure Boot enabled

## Usage

```bash
./nvidia/install-nvidia.sh            # idempotent install/repair
./nvidia/install-nvidia.sh --check    # preflight + state probe, no changes
./nvidia/install-nvidia.sh --force    # skip early-exit, re-run every phase check
./nvidia/install-nvidia.sh --nuke     # wipe everything NVIDIA and reinstall from scratch
```

Logs go to `nvidia/logs/install-<timestamp>.log`.

## `--nuke` — start from a clean slate

Use this when you don't trust the current state (partial install, driver
updates that left garbage, weird `nvidia-smi` errors that none of the other
phases fix). It will:

1. Ask you to type `nuke` to confirm.
2. `pacman -Rns nvidia-open-dkms nvidia-utils`
3. Remove `/etc/modprobe.d/blacklist-nouveau.conf`
4. Wipe `/var/lib/dkms/nvidia` and any stale `.ko` files under
   `/lib/modules/*/updates/dkms/`
5. Regenerate initramfs (`mkinitcpio -P`)
6. Then proceed through the normal install phases (2 through 8) to put
   everything back.
7. Require a **manual reboot** at the end.

Safe to run while Xorg is up: package removal doesn't unload the nvidia
kernel modules from memory, so your desktop keeps working on the AMD iGPU
throughout. The reboot at the end is what actually clears the old modules.

## If something goes wrong

See the `Rollback` section of `~/.claude/projects/-home-jony/memory/project_nvidia_baseline.md` — notably:

- Boot into Ubuntu (systemd-boot entry `ubuntu`) to repair Arch from another system.
- Or Arch live USB → chroot → `rm /etc/modprobe.d/blacklist-nouveau.conf` → `mkinitcpio -P` → reboot.
