# apollo-iso — build the Apollo ISO and copy it onto the Ventoy stick.
# Packaged by Modules/Shell/deploy-tools.nix (see the Apollo overview there).
cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

echo -e "\033[1;34m==> Building .#apollo-iso ...\033[0m"
out=$(nix build .#apollo-iso --no-link --print-out-paths)
iso="$out/iso/apollo-deployer.iso"
[[ -f "$iso" ]] || { echo "❌ no ISO at $iso"; ls -l "$out/iso" || true; exit 1; }
echo ":: $iso ($(du -h "$iso" | cut -f1))"

dest=$(findmnt -rn -o TARGET -S LABEL=Apollo || true)
if [[ -z "$dest" ]]; then
  if [[ -e /dev/disk/by-label/Apollo ]]; then
    echo -e "\033[1;33m==> Apollo is plugged in but not mounted. Mount it with:\033[0m"
    echo "    udisksctl mount -b /dev/disk/by-label/Apollo"
  else
    echo -e "\033[1;33m==> Apollo not found. Plug the Ventoy stick in, then re-run.\033[0m"
  fi
  echo ":: ISO is built and ready at:"
  echo "   $iso"
  exit 0
fi

# The stick already keeps images in ISOs/ (Ventoy scans subdirectories),
# so follow that rather than dropping it in the root.
sub="$dest"
[[ -d "$dest/ISOs" ]] && sub="$dest/ISOs"

echo -e "\033[1;34m==> Copying to $sub ...\033[0m"
cp --no-preserve=mode,ownership "$iso" "$sub/apollo-deployer.iso"
sync
echo -e "\033[1;32m==> Done. Boot it from Ventoy on the target machine.\033[0m"
echo -e "\033[1;33m   Secure Boot must be off, or Ventoy's shim MOK-enrolled.\033[0m"
