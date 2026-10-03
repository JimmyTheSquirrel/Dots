# apollo-connect [ssh args...] — wait for the booted Apollo stick to appear on
# the tailnet, then SSH in. Packaged by Modules/Shell/deploy-tools.nix.
#
# APOLLO_NODE=<ip-or-name> skips the lookup. The lookup itself (why it is a
# prefix + Online match and not the name "apollo") is in apollo-resolve.
node="${APOLLO_NODE:-}"

if ! tailscale status >/dev/null 2>&1; then
  echo "❌ tailscaled isn't reachable here. Is tailscale up on this machine?"
  exit 1
fi
if [ -z "$node" ]; then
  node=$(apollo-resolve)
  if [ -z "$node" ]; then
    echo -n ":: waiting for the Apollo stick to join the tailnet "
    for _ in $(seq 1 60); do
      node=$(apollo-resolve)
      [ -n "$node" ] && { echo " found."; break; }
      echo -n "."
      sleep 2
    done
  fi
fi

if [ -z "$node" ]; then
  echo ""
  echo "❌ no online apollo* node after 2 minutes."
  echo "   On the stick: check 'systemctl status apollo-tailscale-up', and that"
  echo "   keys/ts-authkey is present on the Ventoy partition ('apollo-key' writes it)."
  exit 1
fi
echo ":: using node '$node'"

# The ISO is read-only, so it generates a FRESH ssh host key on every boot.
# Without these options every single use of the stick trips
# "REMOTE HOST IDENTIFICATION HAS CHANGED". A new identity each boot is the
# expected behaviour here, and the tailnet is already authenticating the node.
exec ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o GlobalKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  "rock@${node}" "$@"
