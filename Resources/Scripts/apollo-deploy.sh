# apollo-deploy [--vm-test|--dry-run] <flake-attr> [ssh-target] — install a host
# onto the machine booted from the Apollo stick (WIPES ITS DISKS).
# Packaged by Modules/Shell/deploy-tools.nix (see the Apollo overview there).
cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

vm_test=0
dry_run=0
while true; do
  case "${1:-}" in
    --vm-test) vm_test=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    *) break ;;
  esac
done

attr="${1:-}"
if [[ -z "$attr" ]]; then
  echo "Usage: apollo-deploy [--vm-test|--dry-run] <flake-attr> [ssh-target]"
  echo "   e.g. apollo-deploy kitkat-Elektra"
  echo "        apollo-deploy --dry-run kitkat-Elektra   # print the disko script"
  echo "        apollo-deploy --vm-test kitkat-Elektra   # apply it in a VM (see caveat)"
  echo ""
  echo "Env: APOLLO_EXTRA_FILES=<dir>  override; default ~/.local/share/apollo/<Host>"
  exit 2
fi

# Attr is <user>-<Host>; the facter report lives with the host it describes.
host="${attr#*-}"
facter="./Hosts/${host}/facter.json"
[[ -d "./Hosts/${host}" ]] || { echo "❌ no Hosts/${host}/ in this repo"; exit 1; }

if [[ "$dry_run" == 1 ]]; then
  # The disko script itself, printed rather than run. Works for any layout
  # whatever its size, and shows the exact sgdisk/mkfs/mount commands that
  # would be issued against the host's disk.
  echo -e "\033[1;34m==> disko script for .#${attr} (nothing is executed):\033[0m\n"
  script=$(nix build ".#nixosConfigurations.${attr}.config.system.build.diskoScript" \
             --no-link --print-out-paths)
  cat "$script"
  echo -e "\n\033[1;32m==> That script builds. Check the device names above before installing.\033[0m"
  exit 0
fi

if [[ "$vm_test" == 1 ]]; then
  echo -e "\033[1;34m==> VM-testing .#${attr} (no target touched) ...\033[0m"
  echo -e "\033[1;33m:: caveat: disko's test harness hardcodes a 4 GiB disk"
  echo -e "   (emptyDiskImages = 4096, lib/tests.nix — not settable from our config),"
  echo -e "   so a layout with more than ~4 GiB of fixed-size partitions can never"
  echo -e "   pass here. Elektra's 16 G swap puts it over; use --dry-run for those.\033[0m"
  echo ""

  # ⚠ `nixos-anywhere --vm-test` EXITS 0 EVEN WHEN THE TEST FAILS. A failed
  # disko run inside the VM surfaces only as text — "RequestedAssertionFailed"
  # / "failed (exit code N)" — while the wrapper still returns success. So the
  # output decides the outcome. A non-zero exit counts as a failure too — and
  # is captured rather than left to errexit/pipefail, which would kill the
  # script before the diagnosis below could print.
  log=$(mktemp)
  status=0
  nixos-anywhere --flake ".#${attr}" --vm-test 2>&1 | tee "$log" || status=$?
  if [[ "$status" -ne 0 ]] \
     || grep -qE "RequestedAssertionFailed|failed \(exit code|error: build of" "$log"; then
    echo -e "\n\033[1;31m==> VM test FAILED (exit $status — see above).\033[0m"
    if grep -q "not saving changes" "$log"; then
      echo "sgdisk could not write the table, which is almost certainly the 4 GiB"
      echo "harness disk rather than your partitioning. Use --dry-run, or shrink the"
      echo "swap partition in Hosts/${host}/_disko.nix temporarily to smoke-test it."
    fi
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
  echo -e "\n\033[1;32m==> VM test passed: the layout applies cleanly.\033[0m"
  exit 0
fi

# Only a REAL install needs the stick. This used to be resolved before the
# --dry-run / --vm-test branches above, so both of those refused to run unless
# the stick was booted and online, though neither touches it.
#
# Default target is the LIVE apollo* node (apollo-resolve explains why that is
# not simply the name "apollo").
if [ -n "${2:-}" ]; then
  target="$2"
else
  n=$(apollo-resolve)
  [ -z "$n" ] && { echo "❌ no online apollo* node — is the stick booted?"; exit 1; }
  target="rock@$n"
  echo ":: target resolved to $target"
fi

args=(
  --flake ".#${attr}"
  --target-host "$target"
  --generate-hardware-config nixos-facter "$facter"
  --build-on local
  --ssh-option StrictHostKeyChecking=no
  --ssh-option UserKnownHostsFile=/dev/null
)
# Files planted onto the new system during the install — chiefly the
# PRE-GENERATED ssh host key whose age identity is already a recipient of
# that host's sops file. Without it the machine generates its own host key
# at first boot, sops has never heard of that identity, and the very first
# activation cannot decrypt anything — which for Elektra means no login
# password. The only fix at that point is to reinstall or hand-copy a key.
#
# Default location is OUTSIDE the repo on purpose: this repo is public and
# these are private keys. Generate a host's set with:
#   mkdir -p ~/.local/share/apollo/<Host>/etc/ssh
#   ssh-keygen -t ed25519 -N "" -C root@<Host> \
#     -f ~/.local/share/apollo/<Host>/etc/ssh/ssh_host_ed25519_key
#   nix run nixpkgs#ssh-to-age -- -i <that>.pub     # -> the age recipient
# then add that recipient to .sops.yaml and `sops updatekeys` the host's file.
extra="${APOLLO_EXTRA_FILES:-$HOME/.local/share/apollo/${host}}"
if [[ -d "$extra" ]]; then
  args+=(--extra-files "$extra")
  echo -e "\033[1;32m:: planting these onto the new system:\033[0m"
  find "$extra" -type f -printf '     /%P\n' 2>/dev/null
  echo ""
else
  echo -e "\033[1;31m:: NO extra files found at $extra\033[0m"
  echo "   The new system will generate its own ssh host key, so any sops secret"
  echo "   keyed to that host key will NOT decrypt on first boot — for a desktop"
  echo "   that usually means no login password."
  echo ""
  read -r -p "   Continue anyway? [y/N] " ok
  [[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "aborted"; exit 1; }
fi

# Show the MACHINE, not just the config name. Typing "Elektra" proves you
# know which config you are installing; it proves nothing about which
# physical box is on the other end of the tailnet. If a different machine
# were booted from an Apollo stick, the old prompt would happily wipe it.
echo -e "\033[1;34m:: asking $target what it is...\033[0m"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=15 -o BatchMode=yes "$target" '
  printf "  machine   : %s %s\n" "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" "$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
  printf "  ram       : %s\n" "$(awk "/MemTotal/ {printf \"%.1f GB\", \$2/1048576}" /proc/meminfo)"
  echo   "  disks     :"
  lsblk -dno NAME,SIZE,MODEL 2>/dev/null | sed "s/^/              /"
' || { echo "❌ could not reach $target to identify it"; exit 1; }
echo ""

echo -e "\033[1;31m╭────────────────────────────────────────────────────────────╮\033[0m"
echo -e "\033[1;31m│  This ERASES every disk named in ${host}'s disko config.   │\033[0m"
echo -e "\033[1;31m╰────────────────────────────────────────────────────────────╯\033[0m"
echo "  flake attr : .#${attr}"
echo "  target     : $target"
# Read the disks from the evaluated disko config itself, not by grepping
# source — the layout lives in Hosts/<Host>/_disko.nix and may name more
# than one disk. `|| wipe=""`: without it a failed eval killed the script
# here under errexit, silently (stderr is discarded), instead of reaching the
# "could not evaluate" fallback on the next line.
wipe=$(nix eval --raw ".#nixosConfigurations.${attr}.config.disko.devices.disk" \
         --apply 'ds: builtins.concatStringsSep " " (map (d: d.device) (builtins.attrValues ds))' 2>/dev/null) \
  || wipe=""
echo "  WILL WIPE  : ${wipe:-(could not evaluate the disko config)}"
echo "  facter out : $facter  (overwritten)"
echo ""
echo -e "\033[1;33m  Check the disk above appears in that machine's disk list.\033[0m"
echo ""
read -r -p "Type the host name ('${host}') to proceed: " confirm
[[ "$confirm" == "${host}" ]] || { echo "aborted"; exit 1; }

# nixos-anywhere detects VARIANT_ID=installer on the Apollo ISO and skips
# kexec, so this SSH session (and the tailnet link under it) survives the
# whole install.
nixos-anywhere "${args[@]}"

echo -e "\n\033[1;32m==> Installed. Review and commit the generated $facter.\033[0m"
