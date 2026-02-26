# NAS ZSpace Z4S -- HDD Power Enable for Linux

![GitHub](https://img.shields.io/badge/license-MIT-blue.svg) ![GitHub last commit](https://img.shields.io/github/last-commit/hhai93/zspace-z4s)

Enable hard drive power on the ZSpace Z4S NAS when running non-stock Linux operating systems such as Ubuntu, Debian, or other Linux distributions.

------------------------------------------------------------------------

## Overview

When installing a generic Linux distribution on the ZSpace Z4S, the hard drives may remain powered off after boot. This occurs because the original firmware controls SATA power through proprietary kernel modules that are not included in standard Linux systems.

After analyzing and decompiling the original modules:

-   `sata_ahci_power.ko`
-   `leds_ec.ko`

the required initialization sequence was identified and implemented as a userspace script.

Running the script during system startup enables HDD power automatically.

------------------------------------------------------------------------

## Features

-   Enables HDD power on ZSpace Z4S
-   Works with standard Linux kernels
-   No kernel recompilation required
-   Simple installation
-   Compatible with most Debian/Ubuntu-based systems

------------------------------------------------------------------------

## Repository Structure

    .
    ├── z4s_hdd_power.sh   # HDD power initialization script
    └── README.md

------------------------------------------------------------------------

## Requirements

-   ZSpace Z4S NAS
-   Linux-based operating system
-   Root privileges
-   AHCI/SATA support enabled in kernel

### Tested On

-   Ubuntu 22.04

Other distributions may work but are not guaranteed.

------------------------------------------------------------------------

## Installation

### 1. Clone Repository

``` bash
git clone https://github.com/YOUR_USERNAME/z4s-hdd-power.git
cd z4s-hdd-power
```

### 2. Make Script Executable

``` bash
chmod +x z4s_hdd_power.sh
```

### 3. Manual Test (Recommended)

``` bash
sudo ./z4s_hdd_power.sh
```

Verify that drives appear:

``` bash
lsblk
```

or:

``` bash
dmesg | grep -i sata
```

------------------------------------------------------------------------

## Run Automatically at Boot

Create a systemd service:

``` bash
sudo nano /etc/systemd/system/z4s-hdd-power.service
```

Add:

``` ini
[Unit]
Description=Enable HDD Power on ZSpace Z4S
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/path/to/z4s_hdd_power.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable the service:

``` bash
sudo systemctl daemon-reload
sudo systemctl enable z4s-hdd-power.service
```

Reboot:

``` bash
sudo reboot
```

------------------------------------------------------------------------

## Troubleshooting

### Drives Not Detected

Check service status:

``` bash
systemctl status z4s-hdd-power.service
```

Check logs:

``` bash
journalctl -u z4s-hdd-power.service
```

------------------------------------------------------------------------

## Disclaimer

This project is unofficial and not affiliated with ZSpace.

Use at your own risk. Always back up important data before testing.

------------------------------------------------------------------------

## Contributing

Pull requests and improvements are welcome.

------------------------------------------------------------------------

## License

MIT License (or your preferred license).
