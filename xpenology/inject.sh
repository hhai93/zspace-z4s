#!/bin/bash
# inject.sh
# Injects z4s_ec_init.sh into Arc loader's own initrd (p3/initrd-arc).
# The script runs inside Arc Linux environment BEFORE kexec hands off to DSM,
# ensuring SATA drives are powered on before the DSM kernel scans for them.
#
# Usage: sudo bash inject.sh /dev/sdX

set -e

DEV="${1:?Usage: $0 /dev/sdX}"
# mmcblk/nvme devices use "p" separator (e.g. mmcblk0p3, nvme0n1p3)
# standard block devices do not (e.g. sda3)
if echo "$DEV" | grep -qE "mmcblk|nvme"; then
    P3_DEV="${DEV}p3"
else
    P3_DEV="${DEV}3"
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"   # resolved before any cd
WORK=$(mktemp -d)
P3="$WORK/p3"
INITRD_WORK="$WORK/initrd"
TMP_INITRD="/tmp/initrd-arc.new"              # repack target in RAM, avoids needing 2x space on partition

cleanup() {
    umount "$P3" 2>/dev/null || true
    rm -rf "$WORK"
    rm -f "$TMP_INITRD"
}
trap cleanup EXIT

# ── Auto-resize p3 if needed ──────────────────────────────────────────────
# Arc ships with p3 sized just enough to hold its files.
# After injecting, the repacked initrd will be slightly larger,
# so we expand p3 to fill all remaining unallocated space first.
echo "[*] Checking partition size..."

# Get total disk size and p3 end position (in sectors)
DISK_SECTORS=$(blockdev --getsz "$DEV")
P3_END=$(parted -sm "$DEV" unit s print 2>/dev/null | awk -F: '/^3:/{gsub("s","",$3); print $3}')
DISK_END=$(( DISK_SECTORS - 1 ))

if [ -z "$P3_END" ]; then
    echo "[WARN] Could not determine p3 end — skipping auto-resize"
elif [ "$P3_END" -lt $(( DISK_END - 2048 )) ]; then
    # More than 1MB of unallocated space exists after p3 — worth expanding
    echo "[*] Unallocated space found after p3 — expanding..."
    umount "$P3_DEV" 2>/dev/null || true

    # Resize partition table entry (parted)
    parted -s "$DEV" resizepart 3 100%

    # Resize ext4 filesystem to fill new partition size
    e2fsck -f -y "$P3_DEV" >/dev/null 2>&1 || true
    resize2fs "$P3_DEV"

    echo "[*] p3 expanded: $(lsblk -dno SIZE "$P3_DEV")"
else
    echo "[*] p3 already uses full available space — no resize needed"
fi

# ── Mount p3 ──────────────────────────────────────────────────────────────
echo ""
echo "[*] Mounting ${P3_DEV}..."
mkdir -p "$P3"
mount -t ext4 "$P3_DEV" "$P3"

echo "[*] p3 contents:"
ls -lh "$P3"
echo ""

INITRD_FILE="$P3/initrd-arc"
if [ ! -f "$INITRD_FILE" ]; then
    echo "[ERR] initrd-arc not found in p3"
    find "$P3" -maxdepth 2 | sort
    exit 1
fi
echo "[*] Found: $INITRD_FILE ($(wc -c < "$INITRD_FILE") bytes)"

# ── Unpack initrd ─────────────────────────────────────────────────────────
mkdir -p "$INITRD_WORK"
cd "$INITRD_WORK"

echo "[*] Detecting compression format..."
FILE_TYPE=$(file "$INITRD_FILE")
echo "    $FILE_TYPE"

if echo "$FILE_TYPE" | grep -qi "Zstandard\|zstd"; then
    zstd -d "$INITRD_FILE" -o "$INITRD_FILE.cpio" -f
    cpio -idm < "$INITRD_FILE.cpio" 2>/dev/null
    rm -f "$INITRD_FILE.cpio"
    COMPRESS="zstd"
elif echo "$FILE_TYPE" | grep -qi "XZ\|lzma"; then
    xzcat "$INITRD_FILE" | cpio -idm 2>/dev/null
    COMPRESS="lzma"
elif echo "$FILE_TYPE" | grep -qi "gzip"; then
    zcat "$INITRD_FILE" | cpio -idm 2>/dev/null
    COMPRESS="gz"
else
    echo "[ERR] Unknown initrd format: $FILE_TYPE"
    exit 1
fi

echo "[*] Extracted OK. Arc scripts:"
find "$INITRD_WORK/opt" -name "*.sh" 2>/dev/null | sort || echo "  (no /opt found)"

# ── Inject EC init script ─────────────────────────────────────────────────
mkdir -p "$INITRD_WORK/usr/local/bin"
cp "$SCRIPT_DIR/z4s_ec_init.sh" "$INITRD_WORK/usr/local/bin/z4s_ec_init.sh"
chmod +x "$INITRD_WORK/usr/local/bin/z4s_ec_init.sh"
echo ""
echo "[*] Copied z4s_ec_init.sh → initrd:/usr/local/bin/"

# ── Patch boot.sh ─────────────────────────────────────────────────────────
# Arc's boot.sh runs inside Arc Linux and calls kexec to hand off to DSM.
# We hook just before the disk-presence check so drives are guaranteed
# to be powered and scanned before Arc (and later DSM) looks for them.
# Injection point:
#   if readConfigMap "addons" ... | grep -q nvmesystem   ← disk check starts here
#     ls /dev/sd* ...
BOOT_SH="$INITRD_WORK/opt/arc/boot.sh"

if [ ! -f "$BOOT_SH" ]; then
    echo "[ERR] boot.sh not found at $BOOT_SH"
    exit 1
fi

if grep -q "z4s_ec_init" "$BOOT_SH"; then
    echo "[*] boot.sh already patched — skipping"
else
    MARKER='if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem'

    if grep -qF "$MARKER" "$BOOT_SH"; then
        # Use Python for the insert to avoid shell escaping issues with sed
        python3 - "$BOOT_SH" << 'PYEOF'
import sys
path = sys.argv[1]
marker = 'if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem'
inject = (
    "# === z4s-ec: power on SATA drives before disk scan ===\n"
    "[ -x /usr/local/bin/z4s_ec_init.sh ] && /usr/local/bin/z4s_ec_init.sh\n"
    "# === end z4s-ec ===\n"
)
with open(path, 'r') as f:
    content = f.read()
content = content.replace(marker, inject + marker, 1)
with open(path, 'w') as f:
    f.write(content)
print("  patched OK")
PYEOF
        echo "[*] boot.sh patched — EC init will run before disk check"
    else
        echo "[ERR] Injection marker not found in boot.sh"
        echo "      Arc may have updated — check boot.sh manually: $BOOT_SH"
        exit 1
    fi
fi

# ── Repack initrd ─────────────────────────────────────────────────────────
# Repack to RAM (/tmp) first, then replace the file on p3.
# This avoids needing double the space on the partition simultaneously.
echo ""
echo "[*] Repacking initrd-arc to RAM..."
cd "$INITRD_WORK"

if [ "$COMPRESS" = "zstd" ]; then
    # -3 is fast and produces similar size to the original; -T0 uses all CPU cores
    find . | cpio -o -H newc -R root:root 2>/dev/null | zstd -3 -T0 -o "$TMP_INITRD" -f
elif [ "$COMPRESS" = "lzma" ]; then
    find . | cpio -o -H newc -R root:root 2>/dev/null | xz -9 --check=crc32 > "$TMP_INITRD"
else
    find . | cpio -o -H newc -R root:root 2>/dev/null | gzip -9 > "$TMP_INITRD"
fi

NEW_SIZE=$(wc -c < "$TMP_INITRD")
OLD_SIZE=$(wc -c < "$INITRD_FILE")
AVAIL_KB=$(df -k "$(dirname "$INITRD_FILE")" | awk 'NR==2 {print $4}')
AVAIL_BYTES=$(( AVAIL_KB * 1024 ))
# After removing old file, effective free space = current free + old file size
EFFECTIVE_FREE=$(( AVAIL_BYTES + OLD_SIZE ))

echo "[*] Old: $((OLD_SIZE/1024/1024))MB | New: $((NEW_SIZE/1024/1024))MB | Free after delete: $((EFFECTIVE_FREE/1024/1024))MB"

if [ "$EFFECTIVE_FREE" -lt "$NEW_SIZE" ]; then
    echo "[ERR] Not enough space on p3 even after removing old initrd"
    echo "      Need: $((NEW_SIZE/1024))KB  Available: $((EFFECTIVE_FREE/1024))KB"
    exit 1
fi

echo "[*] Writing new initrd-arc to p3..."
rm -f "$INITRD_FILE"
cp "$TMP_INITRD" "$INITRD_FILE"
sync

echo ""
echo "[OK] Done!"
echo "     EC init will run inside Arc Linux, before kexec → DSM kernel."
echo "     If something goes wrong: reflash Arc image to USB to restore."
