# apollo-key — put the tailnet installer key on the Apollo stick, from sops.
# Packaged by Modules/Shell/deploy-tools.nix (see the Apollo overview there).
cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

dest=$(findmnt -rn -o TARGET -S LABEL=Apollo || true)
if [[ -z "$dest" ]]; then
  echo "❌ Apollo is not mounted."
  [[ -e /dev/disk/by-label/Apollo ]] \
    && echo "   udisksctl mount -b /dev/disk/by-label/Apollo"
  exit 1
fi

# The key is a plain file on the stick, never baked into the ISO: an ISO's
# Nix store is world-readable and this repo is public. The stick is the
# secret. Rotating the (max 90-day) key is re-running this command.
echo -e "\033[1;33m==> This writes the tailnet installer key in cleartext to:\033[0m"
# keys/ is where the age backup already lives, so the tailnet key goes
# there too. The boot unit checks both keys/ts-authkey and the root.
keydir="$dest/keys"
mkdir -p "$keydir"
echo "    $keydir/ts-authkey"
read -r -p "Continue? [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "aborted"; exit 1; }

sops -d --extract '["tailscale-installer-key"]' Secrets/secrets.yaml \
  | tr -d '[:space:]' > "$keydir/ts-authkey"
[[ -s "$keydir/ts-authkey" ]] || { echo "❌ decrypt produced nothing"; exit 1; }
sync
echo -e "\033[1;32m==> Key written ($(wc -c < "$keydir/ts-authkey") bytes).\033[0m"
echo ":: note: exFAT has no permissions — physical possession of the stick is the control."
