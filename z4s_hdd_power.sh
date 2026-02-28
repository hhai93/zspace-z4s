#!/bin/bash
# ==============================================================================
# Zspace Z4S - SATA Power & LED Control (Ubuntu/Generic Linux)
# ==============================================================================

wait_ec() {
    # Wait until Input Buffer Full (IBF) bit is cleared (bit 1 = 0)
    while (( $(dd if=/dev/port bs=1 skip=102 count=1 status=none | od -An -tu1) & 2 )) 2>/dev/null; do :; done
}

write_ec() {
    # I/O Sequence: Write Command (0x81) -> Register Address -> Hex Data
    wait_ec; printf "\x81" | dd of=/dev/port bs=1 seek=102 conv=notrunc status=none
    wait_ec; printf "\\x$(printf "%02x" "$1")" | dd of=/dev/port bs=1 seek=98 conv=notrunc status=none
    wait_ec; printf "\x$2" | dd of=/dev/port bs=1 seek=98 conv=notrunc status=none
}

# Grant EC write access & set system LED
write_ec 89 "0b"
write_ec 80 "01"

# Staggered spin-up: 5s delay per drive is MANDATORY to prevent peak current overload
for v in c0 f0 fc ff; do
    write_ec 88 "$v"
    sleep 5
done
sleep 3 # Wait for the last motor to stabilize

# Reset all physical bay LEDs (Registers 81-84)
for i in {81..84}; do write_ec "$i" "00"; done

# Map physical bay LEDs via kernel sysfs (Xpenology / BusyBox safe)
# Logic: Port 4->Reg 81, Port 3->Reg 82, Port 2->Reg 83, Port 1->Reg 84
for disk in /sys/block/sd*; do
    [ -d "$disk" ] || continue
    
    # Read absolute hardware path and extract 'ataX' number reliably
    PORT=$(readlink "$disk" | awk -F'/ata' '{print $2}' | awk -F'/' '{print $1}')
    
    [[ "$PORT" =~ ^[1-4]$ ]] && write_ec $((85 - PORT)) "01"
done
