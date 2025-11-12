#!/usr/bin/env bash
set -euo pipefail

# wipe-drive.sh — Interactive secure wipe for HDDs and SSDs
# - Detects SSD vs HDD using /sys/block/*/queue/rotational
# - HDD: uses shred with selectable passes (1/3/7/35)
# - SSD: offers blkdiscard (safe), NVMe secure erase, or SATA hdparm secure erase
#
# Usage: sudo ./wipe-drive.sh
# Requirements (depending on choices): coreutils, util-linux, nvme-cli (NVMe), hdparm (SATA)

# ---------- helpers ----------
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
pause(){ read -rp "Press Enter to continue..."; }

list_disks() {
  echo "Detected block devices (non-removable disks):"
  echo "-----------------------------------------------------------"
  # NAME, SIZE, TYPE, ROTA, MODEL, TRAN, PATH
  lsblk -dno NAME,SIZE,TYPE,ROTA,MODEL,TRAN | awk '{printf "  %-10s %-8s %-6s ROTA=%s  %-20s %-6s\n",$1,$2,$3,$4,$5,$6}'
  echo "-----------------------------------------------------------"
  echo "Tip: NVMe disks usually appear as nvme0n1; SATA/SAS as sda, sdb, etc."
}

get_rotational_flag() {
  local dev="$1"
  local base; base="$(basename "$dev")"
  local sys="/sys/block/$base/queue/rotational"
  [[ -e "$sys" ]] || { # handle nvme namespaces like nvme0n1
    base="${base%%p*}"
    sys="/sys/block/$base/queue/rotational"
  }
  [[ -r "$sys" ]] || die "Cannot read $sys"
  cat "$sys"
}

ensure_not_mounted() {
  local dev="$1"
  if lsblk -nr "$dev" | awk '{print $7}' | grep -q '/'; then
    die "Device or its partitions appear mounted. Unmount them first."
  fi
}

confirm_destruction() {
  local dev="$1"
  local size; size="$(blockdev --getsize64 "$dev" 2>/dev/null || echo "?")"
  echo
  echo "FINAL WARNING: This will IRREVERSIBLY WIPE $dev (size: $size bytes)."
  read -rp "Type EXACTLY 'YES I UNDERSTAND' to proceed: " ack
  [[ "$ack" == "YES I UNDERSTAND" ]] || die "Confirmation failed."
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Run as root (sudo)."
}

# ---------- wipe actions ----------
hdd_shred() {
  local dev="$1" passes="$2"
  need shred
  echo "Running: shred -vzn $passes $dev"
  shred -vzn "$passes" "$dev"
  sync
  echo "HDD wipe complete (shred passes: $passes)."
}

ssd_blkdiscard() {
  local dev="$1"
  need blkdiscard
  echo "Running: blkdiscard $dev"
  blkdiscard "$dev"
  sync
  echo "SSD discard complete."
}

ssd_nvme_secure_erase() {
  local dev="$1"
  need nvme
  # Verify it's an NVMe device
  [[ "$(basename "$dev")" == nvme* ]] || die "Selected device is not NVMe."
  echo "Querying NVMe info for $dev ..."
  nvme id-ctrl "$dev" >/dev/null || die "nvme id-ctrl failed on $dev"
  echo
  echo "About to run: nvme format $dev --ses=1"
  echo "This issues a controller-managed secure erase (may take time)."
  read -rp "Proceed? (type 'nvme-ERASE' to continue): " ack
  [[ "$ack" == "nvme-ERASE" ]] || die "Aborted."
  nvme format "$dev" --ses=1
  sync
  echo "NVMe secure erase requested."
}

ssd_sata_secure_erase() {
  local dev="$1"
  need hdparm
  echo "Checking hdparm security state for $dev ..."
  hdparm -I "$dev" | sed -n '/Security:/,/^[^ ]/p'
  echo
  echo "Notes:"
  echo " - Drive must not be 'frozen'. If frozen, power-cycle (not just reboot) or use sleep trick."
  echo " - This sets a temporary password and performs SECURITY ERASE UNIT."
  echo " - Some drives support --security-erase-enhanced (faster or more thorough by vendor)."
  echo
  read -rp "Set temporary password 'NULL' and proceed with SECURITY ERASE? (type 'sata-ERASE'): " ack
  [[ "$ack" == "sata-ERASE" ]] || die "Aborted."
  # Set a temp password "NULL" for user
  hdparm --user-master u --security-set-pass NULL "$dev"
  # Try enhanced first; fallback to standard if not supported
  if hdparm -I "$dev" | grep -q "supported: enhanced erase"; then
    echo "Running enhanced erase..."
    hdparm --user-master u --security-erase-enhanced NULL "$dev"
  else
    echo "Running standard erase..."
    hdparm --user-master u --security-erase NULL "$dev"
  fi
  sync
  echo "SATA secure erase complete."
}

# ---------- menus ----------
choose_security_level_hdd() {
  echo
  echo "Choose HDD Security Level:"
  echo "  1) Personal wipe before reinstall    -> shred -vzn 1  (1 pass)"
  echo "  2) Business / resale                 -> shred -vzn 3  (3 passes)"
  echo "  3) Government-grade (DoD 5220.22-M)  -> shred -vzn 7  (7 passes)"
  echo "  4) Paranoid / forensic (Gutmann)     -> shred -vzn 35 (35 passes)"
  read -rp "Select [1-4]: " c
  case "$c" in
    1) echo 1 ;;
    2) echo 3 ;;
    3) echo 7 ;;
    4) echo 35 ;;
    *) die "Invalid selection." ;;
  esac
}

choose_security_level_ssd() {
  echo
  echo "Choose SSD Erase Method:"
  echo "  1) blkdiscard (fast TRIM whole device)   [Recommended, broadly safe]"
  echo "  2) NVMe secure erase (nvme format -s1)   [Expert; NVMe only]"
  echo "  3) SATA secure erase (hdparm)            [Expert; SATA only]"
  read -rp "Select [1-3]: " c
  case "$c" in
    1) echo "blkdiscard" ;;
    2) echo "nvme" ;;
    3) echo "sata" ;;
    *) die "Invalid selection." ;;
  esac
}

# ---------- main ----------
main() {
  require_root
  need lsblk
  need dd
  need blockdev

  echo
  echo "=== Secure Disk Wiper (HDD & SSD) ==="
  echo
  list_disks
  echo
  read -rp "Enter target device path (e.g., /dev/sda or /dev/nvme0n1): " DEV
  [[ -b "$DEV" ]] || die "Not a block device: $DEV"

  ensure_not_mounted "$DEV"

  # Detect HDD (rotational=1) vs SSD (rotational=0)
  ROTA="$(get_rotational_flag "$DEV" 2>/dev/null || echo 0)"
  TYPE_HINT="SSD"
  [[ "$ROTA" == "1" ]] && TYPE_HINT="HDD"

  echo
  echo "Detected: $DEV likely a $TYPE_HINT (rotational=$ROTA)."
  read -rp "Proceed treating this device as $TYPE_HINT? [y/N]: " yn
  [[ "${yn:-n}" =~ ^[Yy]$ ]] || die "Aborted."

  confirm_destruction "$DEV"
  echo

  if [[ "$TYPE_HINT" == "HDD" ]]; then
    PASSES="$(choose_security_level_hdd)"
    echo
    echo "Summary:"
    echo "  Device : $DEV"
    echo "  Type   : HDD"
    echo "  Passes : $PASSES (shred)"
    read -rp "Final confirm? [y/N]: " ok
    [[ "${ok:-n}" =~ ^[Yy]$ ]] || die "Aborted."
    hdd_shred "$DEV" "$PASSES"
  else
    METHOD="$(choose_security_level_ssd)"
    echo
    echo "Summary:"
    echo "  Device : $DEV"
    echo "  Type   : SSD"
    echo "  Method : $METHOD"
    read -rp "Final confirm? [y/N]: " ok
    [[ "${ok:-n}" =~ ^[Yy]$ ]] || die "Aborted."
    case "$METHOD" in
      blkdiscard) ssd_blkdiscard "$DEV" ;;
      nvme)       ssd_nvme_secure_erase "$DEV" ;;
      sata)       ssd_sata_secure_erase "$DEV" ;;
      *) die "Unknown method." ;;
    esac
  fi

  echo
  echo "All done."
}

main "$@"
