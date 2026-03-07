#!/bin/sh
# z4s_ec_init.sh
# Powers on SATA drives on ZSpace Z4S by initializing the Embedded Controller (EC).
# Runs inside Arc Linux (before kexec), so DSM kernel sees drives on first scan.
#
# Must be placed at: /usr/local/bin/z4s_ec_init.sh (inside Arc initrd)
# Called by: /opt/arc/boot.sh (injected by inject.sh)

LOGPFX="[z4s-ec]"

# Log to kernel ring buffer (visible via dmesg), fall back to stdout
log() { echo "$LOGPFX $*" > /dev/kmsg 2>/dev/null || echo "$LOGPFX $*"; }

# ── /dev/port check ───────────────────────────────────────────────────────
# All EC communication goes through legacy I/O port 0x62/0x66 via /dev/port.
# If the kernel was built without CONFIG_DEVPORT=y this file won't exist.
if [ ! -c /dev/port ]; then
    log "ERROR: /dev/port not available (CONFIG_DEVPORT=y required) — aborting"
    exit 1
fi

# ── EC I/O helpers ────────────────────────────────────────────────────────

# wait_ec: poll EC status register (port 0x66, byte offset 102) until bit 1 clears.
# Bit 1 = IBF (Input Buffer Full) — EC is busy processing previous command.
wait_ec() {
    local val retries=200
    while [ $retries -gt 0 ]; do
        retries=$(( retries - 1 ))
        val=$(dd if=/dev/port bs=1 skip=102 count=1 status=none 2>/dev/null \
              | od -An -tu1 2>/dev/null)
        val=$(echo $val)           # strip leading/trailing whitespace (busybox safe)
        val=$(( ${val:-0} & 2 ))   # isolate IBF bit; default 0 if od fails
        [ "$val" -eq 0 ] && return 0
        usleep 5000 2>/dev/null || true   # 5ms delay; no-op if usleep unavailable
    done
    log "WARN: EC wait timeout — proceeding anyway"
    return 0
}

# write_ec REG VAL: send a register write to the EC.
# Protocol: write command 0x81 to port 0x66, then REG and VAL to port 0x62.
# Offsets: 0x66 = 102 decimal, 0x62 = 98 decimal.
write_ec() {
    wait_ec
    printf "\x81"  | dd of=/dev/port bs=1 seek=102 conv=notrunc status=none  # command
    wait_ec
    printf "\\x$1" | dd of=/dev/port bs=1 seek=98  conv=notrunc status=none  # register
    wait_ec
    printf "\\x$2" | dd of=/dev/port bs=1 seek=98  conv=notrunc status=none  # value
}

# ── Power-on sequence ─────────────────────────────────────────────────────
log "Starting EC power-on sequence..."

write_ec "59" "0b"   # reg 0x59: enable power control mode
write_ec "50" "01"   # reg 0x50: assert power enable

# Staggered spin-up via bitmask: power on one drive group at a time.
# 5s per step prevents simultaneous inrush current from tripping PSU protection.
# c0=drives 1-2, f0=drives 1-3, fc=drives 1-4(partial), ff=all drives
log "Staggered spin-up (c0 -> f0 -> fc -> ff, 5s each)..."
for v in c0 f0 fc ff; do
    write_ec "58" "$v"
    log "  mask=0x$v, waiting 5s..."
    sleep 5
done

sleep 3   # extra settling time before LED init
log "EC power-on complete."

# Clear all bay LEDs (registers 0x51-0x54) to a known off state.
# z4s_daemon monitor service will take control of LEDs after DSM boots.
for reg in 51 52 53 54; do
    write_ec "$reg" "00"
done

# ── SCSI rescan ───────────────────────────────────────────────────────────
# The AHCI driver scanned for drives at kernel boot, before EC powered them on.
# Force a rescan so the kernel discovers the now-spinning drives.
log "Triggering SCSI host rescan..."
sleep 2   # let drives finish spin-up before rescan

for host in /sys/class/scsi_host/host*; do
    [ -f "$host/scan" ] || continue
    echo "- - -" > "$host/scan" 2>/dev/null
    log "  rescanned $(basename "$host")"
done

sleep 3   # wait for kernel to enumerate and create /dev/sdX nodes
log "Done — drives should now be visible to the system."
