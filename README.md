# ZSpace Z4S — Linux HDD Power & LED Monitor

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Last Commit](https://img.shields.io/github/last-commit/hhai93/zspace-z4s)

Userspace daemon for ZSpace Z4S NAS — enables SATA power and drive bay LEDs on generic Linux and Xpenology (ARC loader). Reimplements the proprietary EC initialization sequence without kernel modules.

---

## Repository Structure

```
.
├── z4s_daemon              # Main daemon (runs inside DSM/Linux)
├── z4s_daemon.service      # systemd service unit
├── xpenology/
│   ├── z4s_ec_init.sh      # EC power-on script, injected into Arc initrd
│   └── inject.sh           # Injects z4s_ec_init.sh into Arc's initrd-arc
└── README.md
```

## Features

- Staggered HDD spin-up (prevents inrush current)
- Bay LEDs: power, I/O activity, fault, degraded, rebuilding
- Health monitoring via SMART, ZFS, Linux RAID
- Xpenology (ARC loader) support

---

## Generic Linux

```bash
sudo cp z4s_daemon /etc && sudo chmod +x /etc/z4s_daemon
sudo cp z4s_daemon.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now z4s_daemon.service
```

---

## Xpenology (ARC Loader)

On ZSpace Z4S, SATA drives have no power until the EC is initialized. This must happen **before** the DSM kernel boots, or DSM will find no drives.

```
Arc boot.sh → z4s_ec_init.sh (EC on, SCSI rescan) → kexec → DSM → z4s_daemon monitor
```

### Step 1 — Inject into Arc initrd

> ⚠️ Must be done on a **Full Linux environment ** — requires `zstd`, `python3`, `parted`, `e2fsck`, `resize2fs` which are not available in Arc's busybox environment. (You can use Live CD)

```bash
sudo apt install zstd python3 parted e2fsprogs
sudo bash inject.sh /dev/sdX
```

### Step 2 — Install LED monitor in DSM

SSH into DSM after installation, then install the daemon in monitor-only mode (drives are already powered by Arc):

```bash
sudo cp z4s_daemon /usr/local/bin
sudo chmod +x /usr/local/bin/z4s_daemon

sudo tee /usr/local/etc/rc.d/z4s_daemon.sh << 'RCDEOF'
#!/bin/sh
case "$1" in
    start) /usr/local/bin/z4s_daemon monitor & ;;
    stop)  kill $(cat /var/run/z4s_daemon.pid 2>/dev/null) 2>/dev/null || true ;;
    *)     echo "Usage: $0 {start|stop}" ;;
esac
RCDEOF
sudo chmod +x /usr/local/etc/rc.d/z4s_daemon.sh

# Start immediately without rebooting
sudo /usr/local/etc/rc.d/z4s_daemon.sh start
```

### ⚠️ After every Arc update

Arc overwrites `initrd-arc` on update — re-run inject:

```bash
sudo bash arc-loader/inject.sh /dev/sdX
```

---

## Usage

```bash
z4s_daemon boot-monitor   # boot + monitor (native Linux service)
z4s_daemon monitor        # LED monitor only (Xpenology service)
z4s_daemon status         # show bay status
```

## LED Reference

| State      | Color        |
|------------|--------------|
| Power on   | Green        |
| I/O active | Green blink  |
| Degraded   | Yellow       |
| Rebuilding | Yellow blink |
| Fault      | Red          |
| Empty bay  | Off          |

## Troubleshooting

```bash
journalctl -u z4s_daemon.service -f
dmesg | grep z4s-ec          # verify EC init ran (Xpenology)
```

---

## Disclaimer

Unofficial, not affiliated with ZSpace. Use at your own risk.

## License

MIT
