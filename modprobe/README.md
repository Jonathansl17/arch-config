# modprobe

Kernel module options copied into `/etc/modprobe.d/` by `install.sh`.

## Files

| File | Purpose |
|------|---------|
| `rtw89.conf` | Keeps the Realtek RTL8852BE WiFi card (`rtw89` driver) from hanging |

## rtw89.conf

Symptom without it: WiFi drops and the interface disappears until a full power
off (a reboot is not enough). The kernel log shows the firmware failing to wake up:

```
rtw89_8852be: firmware failed to ack for leaving ps mode
rtw89_8852be: rtw89: failed to leave lps state
pcieport ...: AER: Uncorrectable (Non-Fatal) error
rtw89_8852be: mac preinit fail, ret: -110
```

Every option turns off a power-saving feature, so the card never goes through the
sleep/wake transition that fails:

- `rtw89_core disable_ps_mode=y` — no LPS (firmware/radio sleep between beacons)
- `rtw89_pci disable_aspm_l1=y` — PCIe link never enters ASPM L1
- `rtw89_pci disable_aspm_l1ss=y` — no deeper L1.1/L1.2 substates
- `rtw89_pci disable_clkreq=y` — PCIe reference clock is never gated

Cost: slightly higher power draw. On machines without an `rtw89` card the file is
harmless (options for modules that never load are ignored).

References: [kernel bug 217978](https://bugzilla.kernel.org/show_bug.cgi?id=217978),
[lwfinger/rtw89#226](https://github.com/lwfinger/rtw89/issues/226).

## Activating

Options apply when the module loads. Power off completely and boot again, then check:

```sh
cat /sys/module/rtw89_core/parameters/disable_ps_mode /sys/module/rtw89_pci/parameters/disable_aspm_l1
```

Both should print `Y`.
