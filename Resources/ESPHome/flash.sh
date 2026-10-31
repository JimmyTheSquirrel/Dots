#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# Build and OTA-flash the two bedside Athom RGBCW bulbs.
#
#   ./flash.sh compile              build only, report the binary size
#   ./flash.sh flash <ip|host>      build (cached) and OTA one bulb
#   ./flash.sh flash-all            both bulbs, one after the other
#
# Run it from anywhere; it locates its own directory. Needs the sops age key
# (so: rock on Sisyphus) and LAN reach to the bulbs — they are on the house
# network, NOT the tailnet, so this has to run somewhere that can see
# 192.168.0.0/24. Asgard can; Sisyphus can.
#
# ⚠ The compiled binary CONTAINS the Wi-Fi password. The build directory is a
# mktemp with mode 700 and is removed on exit, success or failure. The
# PlatformIO toolchain cache lives separately and holds no secrets, so it
# survives between runs — the first compile takes a few minutes, later ones
# seconds.
#
# Why this is a script and not a nix derivation: `esphome compile` downloads
# its ESP-IDF toolchain from PlatformIO at build time, so it cannot be
# hermetic. The declarative part — the config — is bedside-bulb.yaml, in the
# repo. See Claude/home-assistant.md → Reflashing the bedside bulbs.
# ══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SECRETS="$REPO/Secrets/secrets.yaml"
CONFIG="bedside-bulb.yaml"

# Both bulbs. Addresses are DHCP but have been stable; `flash.sh flash <ip>`
# takes an override if one moves. These are also in Modules/Server/_plugs.nix
# only as entity ids — HA knows the IPs via sensor.<slug>_ip_address.
BULBS=(
  "192.168.0.152  rhys-bedside-table"
  "192.168.0.246  caitlin-bedside-lamp"
)

PIO_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/esphome-bedside-bulb/platformio"

BUILD=""
cleanup() { [[ -n "$BUILD" && -d "$BUILD" ]] && rm -rf "$BUILD"; }
trap cleanup EXIT INT TERM

die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
say() { printf '\033[36m→ %s\033[0m\n' "$*"; }
ok()  { printf '\033[32m✓ %s\033[0m\n' "$*"; }

prepare() {
  [[ -f "$SECRETS" ]] || die "no $SECRETS"
  command -v sops >/dev/null || die "sops not on PATH"

  BUILD="$(mktemp -d)"
  chmod 700 "$BUILD"
  mkdir -p "$PIO_CACHE"
  cp "$HERE/$CONFIG" "$BUILD/$CONFIG"

  # ESPHome wants underscores; sops uses dashes.
  local ssid pass
  ssid="$(sops -d --extract '["wifi-ssid"]' "$SECRETS")"     || die "cannot read wifi-ssid"
  pass="$(sops -d --extract '["wifi-password"]' "$SECRETS")" || die "cannot read wifi-password"
  [[ -n "$ssid" && -n "$pass" ]] || die "wifi-ssid / wifi-password are empty in sops"

  umask 077
  { printf 'wifi_ssid: %s\n' "$ssid"
    printf 'wifi_password: %s\n' "$pass"
  } > "$BUILD/secrets.yaml"

  say "build dir $BUILD  (removed on exit)"
}

# esphome from our own nixpkgs — 2026.5.1, which satisfies the pinned config's
# min_version of 2026.5.0. Do NOT bump the pin past what this can build.
esph() {
  PLATFORMIO_CORE_DIR="$PIO_CACHE" \
  nix run "$REPO#nixosConfigurations.rock-Asgard.pkgs.esphome" -- "$@"
}

compile() {
  say "compiling (first run pulls the ESP32-C3 toolchain — minutes)"
  ( cd "$BUILD" && esph compile "$CONFIG" )
  local bin
  bin="$(find "$BUILD/.esphome/build" -name 'firmware.factory.bin' -o -name 'firmware.bin' | head -1)"
  [[ -n "$bin" ]] || die "compiled but produced no binary"
  ok "built $(du -h "$bin" | cut -f1)  $(basename "$bin")"
}

flash_one() {
  local target="$1"
  say "OTA → $target"
  ( cd "$BUILD" && esph upload "$CONFIG" --device "$target" )
  ok "$target flashed"
}

case "${1:-}" in
  compile)
    prepare; compile
    ;;
  flash)
    [[ $# -eq 2 ]] || die "usage: flash.sh flash <ip|host>"
    prepare; compile; flash_one "$2"
    ;;
  flash-all)
    prepare; compile
    for b in "${BULBS[@]}"; do
      read -r ip label <<<"$b"
      say "--- $label"
      flash_one "$ip"
      printf '\n'
    done
    ;;
  *)
    sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
