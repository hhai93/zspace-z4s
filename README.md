# ZSpace Z4S — Linux HDD Power & LED Monitor

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Last Commit](https://img.shields.io/github/last-commit/hhai93/zspace-z4s)

Userspace daemon for ZSpace Z4S NAS — enables SATA power and drives bay LED indicators on generic Linux (Ubuntu, Debian, etc.).

---

## Background

Stock ZSpace firmware controls SATA power and LEDs via proprietary kernel modules (`sata_ahci_power.ko`, `leds_ec.ko`). These are unavailable on standard Linux kernels. This project reimplements the required EC (Embedded Controller) initialization sequence entirely in userspace — no kernel recompilation needed.

---

## Features

- Staggered HDD spin-up (prevents current overload)
- Bay LED indicators: power, I/O activity, fault, degraded, rebuilding
- Disk health monitoring via SMART, ZFS (`zpool`), and Linux RAID (`mdstat`)
- Runs as a systemd daemon

---

## Repository Structure

```
.
├── z4s_daemon          # Main daemon script
├── z4s_daemon.service  # systemd service unit
└── README.md
```

---

## Requirements

- ZSpace Z4S NAS
- Linux with root privileges
- `smartmontools` (optional, for SMART health checks)
- `zfsutils-linux` (optional, for ZFS pool status)

### Tested On

- Ubuntu 22.04

---

## Installation

```bash
# 1. Copy script
sudo cp z4s_daemon /usr/local/bin/z4s_daemon
sudo chmod +x /usr/local/bin/z4s_daemon

# 2. Install service
sudo cp z4s_daemon.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now z4s_daemon.service
```

---

## Usage

```bash
z4s_daemon boot           # Power on drives
z4s_daemon monitor        # Start LED monitor loop
z4s_daemon boot-monitor   # Boot + monitor (used by service)
z4s_daemon status         # Show all bay status
```

---

## LED Reference

| State       | Color              |
|-------------|--------------------|
| Power on    | Green              |
| I/O active  | Green blink        |
| Degraded    | Yellow             |
| Rebuilding  | Yellow blink       |
| Fault       | Red                |
| Empty bay   | Off                |

---

## Troubleshooting

```bash
systemctl status z4s_daemon.service
journalctl -u z4s_daemon.service -f
```

---

## Disclaimer

Unofficial project, not affiliated with ZSpace. Use at your own risk. Always back up data before testing.

---

## License

MIT
