# sysctl

Kernel parameters dropped into `/etc/sysctl.d/`.

## Files

| File | Deployed by | Purpose |
|------|-------------|---------|
| `99-swappiness.conf` | `install.sh`                       | `vm.swappiness=10` (favor RAM over swap) |
| `99-hardening.conf`  | `optional-scripts/system-hardening.sh` | Security defaults |

## 99-hardening.conf contents

- `kernel.kptr_restrict=2` — hide kernel pointers from userspace
- `kernel.yama.ptrace_scope=1` — restrict ptrace to parent processes
- `net.ipv4.conf.all.rp_filter=1` — reverse-path filter (anti-spoof)
- `net.ipv4.conf.all.accept_redirects=0` — drop ICMP redirects
- `net.ipv4.conf.all.send_redirects=0` — don't send ICMP redirects

## Activating without reboot

```sh
sudo sysctl --system
```

Both scripts already call this after deploying.
