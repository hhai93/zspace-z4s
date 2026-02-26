#!/bin/bash
# ==============================================================================
# Zspace Z4S - Smart SATA Power & LED Control (Ubuntu/Generic Linux)
# Logic: Sequential power-up (5s delay) + Physical bay LED mapping
# ==============================================================================

# 1. Initialize EC Interface
# Enable write support for the Embedded Controller system
modprobe ec_sys write_support=1 2>/dev/null
EC_IO="/sys/kernel/debug/ec/ec0/io"

# Ensure debugfs is mounted to access the EC IO file
[ ! -d /sys/kernel/debug/ec ] && mount -t debugfs none /sys/kernel/debug 2>/dev/null

write_ec() {
    # Write raw hex byte to specific EC register offset
    printf "\\x$2" | dd of=$EC_IO bs=1 seek=$1 conv=notrunc status=none 2>/dev/null
}

echo "--- Z4S Hardware Initialization Started ---"

# 2. Grant Control & Power On System LED
write_ec 89 "0b" # Register 0x59: Grant EC write access
write_ec 80 "01" # Register 0x50: System Power LED Solid Blue

# 3. Staggered Spin-up (Sequentially power-up 4 bays to prevent voltage sag)
# Register 0x58 (88) controls SATA power bits
echo "Powering on Bay 1..."
write_ec 88 "c0"; sleep 5

echo "Powering on Bay 2..."
write_ec 88 "f0"; sleep 5

echo "Powering on Bay 3..."
write_ec 88 "fc"; sleep 5

echo "Powering on Bay 4..."
write_ec 88 "ff"; sleep 8 # Wait for the last motor to stabilize

# 4. Physical Bay LED Mapping via udevadm
# Resets all LEDs (81-84) before scanning
write_ec 81 "00"; write_ec 82 "00"; write_ec 83 "00"; write_ec 84 "00"

for disk in /dev/sd[a-z]; do
    [ ! -b "$disk" ] && continue
    
    # Retrieve the physical hardware path (ata-X) to identify the exact bay
    PORT=$(udevadm info --query=property --name="$disk" | grep "ID_PATH=" | grep -o "ata-[0-9]*" | cut -d'-' -f2)
    
    case "$PORT" in
        4) write_ec 81 "01" ;; # Physical Bay 1 -> Register 0x51
        3) write_ec 82 "01" ;; # Physical Bay 2 -> Register 0x52
        2) write_ec 83 "01" ;; # Physical Bay 3 -> Register 0x53
        1) write_ec 84 "01" ;; # Physical Bay 4 -> Register 0x54
    esac
done

echo "--- Initialization Complete ---"
