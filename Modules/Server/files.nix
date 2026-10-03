{ ... }: {
  # Asgard — FileBrowser (Quantum), with its admin credentials synced from sops.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    inherit (import ./_lib.nix { inherit pkgs; }) waitForHttp;
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# UTILITIES — File Browser
# Port 8081: FileBrowser — full filesystem browser (downloads, media, photos)
#   Credentials managed via sops: admin-username / admin-password
#   filebrowser-credentials.service syncs them on every boot.
# Tailscale-only, not exposed via Cloudflare tunnel.
# ══════════════════════════════════════════════════════════════════════════════

    # Always writes config.yaml on every rebuild — port and sources are
    # infrastructure, not user settings. User prefs live in the database.
    systemd.services.filebrowser-init = {
      description = "Write FileBrowser Quantum config";
      before   = [ "podman-filebrowser.service" ];
      wantedBy = [ "podman-filebrowser.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/filebrowser
        printf 'server:\n  port: 8080\n  sources:\n    - path: /downloads\n      name: downloads\n    - path: /media\n      name: media\n    - path: /photos\n      name: photos\n' \
          > /var/lib/filebrowser/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.filebrowser = {
      image = "ghcr.io/gtsteffaniak/filebrowser:latest";
      ports = [ "8081:8080" ];
      volumes = [
        "/downloads:/downloads"
        "/data/media:/media"
        "/data/photos:/photos"
        "/var/lib/filebrowser:/home/filebrowser/data"
      ];
      user = "root";
      autoStart = true;
    };

    # Syncs admin credentials from sops on every boot. Tries, in order:
    #   1. $USERNAME / sops password — the steady state. The PUT at the end
    #      RENAMES user 1 to $USERNAME, so once a sync has landed there is no
    #      "admin" left to log in as. This used to try only "admin", so every
    #      boot after the first one failed to authenticate and quietly skipped.
    #   2. admin / sops password — password synced but not the name yet (or
    #      $USERNAME simply is "admin").
    #   3. admin / admin — a fresh install's default.
    systemd.services.filebrowser-credentials = {
      description = "Seed FileBrowser admin credentials from sops";
      after    = [ "podman-filebrowser.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:8081"

        ${waitForHttp { name = "FileBrowser"; url = "$BASE"; tries = 30; interval = 2; }}

        # Request bodies are built by jq from the ENVIRONMENT and piped to curl:
        # splicing "$PASSWORD" into a JSON string broke on a quote, and on any
        # command line it was readable by every user via /proc/<pid>/cmdline.
        # || true on every substitution keeps set -e from exiting on a parse
        # error — a failed attempt just falls through to the next one.
        export USERNAME PASSWORD
        login() { # $1 = user, $2 = password; prints the token or nothing
          LU="$1" LP="$2" jq -n '{username: $ENV.LU, password: $ENV.LP}' \
            | curl -s -X POST "$BASE/api/login" \
                -H "Content-Type: application/json" --data-binary @- 2>/dev/null \
            | jq -r '.token // empty' 2>/dev/null
        }
        TOKEN=$(login "$USERNAME" "$PASSWORD") || true
        [ -n "$TOKEN" ] || TOKEN=$(login admin "$PASSWORD") || true
        [ -n "$TOKEN" ] || TOKEN=$(login admin admin) || true

        if [ -z "$TOKEN" ]; then
          echo "FileBrowser: could not authenticate — skipping credential sync" >&2
          exit 0
        fi

        # Fetch current user object, patch username + password, write back
        USER_DATA=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/users/1" 2>/dev/null) || true
        UPDATED=$(printf '%s' "$USER_DATA" \
          | jq '.username = $ENV.USERNAME | .password = $ENV.PASSWORD' 2>/dev/null) || true

        if [ -z "$UPDATED" ]; then
          echo "FileBrowser: could not build update payload — skipping" >&2
          exit 0
        fi

        printf '%s' "$UPDATED" | curl -s -X PUT "$BASE/api/users/1" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          --data-binary @- > /dev/null

        echo "FileBrowser credentials synced (user: $USERNAME)."
      '';
    };

  };
}
