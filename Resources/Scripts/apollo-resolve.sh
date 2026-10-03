# apollo-resolve — print the tailnet IP of the LIVE Apollo stick, or nothing.
# Packaged by Modules/Shell/deploy-tools.nix as a runtime input of
# apollo-connect and apollo-deploy, which both used to carry their own copy of
# this jq filter.
#
# Resolve the LIVE apollo node, not the name "apollo".
#
# Ephemeral nodes linger in the device list for a while after going
# offline, and Tailscale will not reuse a name that is still taken — so the
# second boot of the stick registers as `apollo-1`, the third as `apollo-2`.
# Hardcoding `apollo` then points at a DEAD node: ssh hangs, deploys fail,
# and the live machine is sitting right there. Pick by prefix + Online.
#
# Never fails: an unreachable tailscaled and "no such node" both print
# nothing, and the callers treat empty output as "not found yet".
tailscale status --json 2>/dev/null \
  | jq -r '[.Peer[]? | select(.HostName | startswith("apollo")) | select(.Online) | .TailscaleIPs[0]] | first // empty' \
  || true
