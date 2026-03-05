#!/bin/bash
# ==============================================================================
# Zspace Z4S - SATA Power (Ubuntu/Generic Linux)
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

# Grant EC write access
write_ec 89 "0b"

# Staggered spin-up: 5s delay per drive is MANDATORY to prevent peak current overload
for v in c0 f0 fc ff; do
    write_ec 88 "$v"
    sleep 5
done
sleep 3 # Wait for the last motor to stabilize
