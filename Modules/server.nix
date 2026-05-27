{ self, inputs, ... }: {

  flake.nixosModules.server = { config, pkgs, lib, activeUser, ... }: {

    imports = [ inputs.nixflix.nixosModules.default ];

# ══════════════════════════════════════════════════════════════════════════════
# NIXFLIX — Arr Stack + Jellyfin + SABnzbd
# Auto-wires: Prowlarr ↔ Sonarr/Radarr/Lidarr, Seerr ↔ Jellyfin/Sonarr/Radarr
# All API keys pre-generated and stored in sops — fully reproducible on deploy.
#
# Port reference (Tailscale-only unless noted):
#   Sonarr     8989  |  Radarr    7878  |  Lidarr   8686
#   Prowlarr   9696  |  Readarr   8787  |  SABnzbd  8080
#   Jellyfin   8096  (+ Cloudflare tunnel at jellyfin.bifrost-vault.com)
#   Jellyseerr 5055  (+ Cloudflare tunnel at requests.bifrost-vault.com)
# ══════════════════════════════════════════════════════════════════════════════

    nixflix = {
      enable = true;
      mediaDir    = "/data/media";
      downloadsDir = "/data/downloads";
      stateDir    = "/data/.state/services";

      sonarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."sonarr-api-key".path;
          hostConfig.authenticationRequired = "disabled";
        };
      };

      radarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."radarr-api-key".path;
          hostConfig.authenticationRequired = "disabled";
        };
      };

      lidarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."lidarr-api-key".path;
          hostConfig.authenticationRequired = "disabled";
        };
      };

      prowlarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."prowlarr-api-key".path;
          hostConfig.authenticationRequired = "disabled";
        };
      };

      jellyfin = {
        enable = true;
        apiKey._secret = config.sops.secrets."jellyfin-api-key".path;
        users.admin = {
          password._secret = config.sops.secrets."jellyfin-admin-password".path;
          policy.isAdministrator = true;
        };
      };

      # Jellyseerr — media request portal (exposed via Cloudflare tunnel)
      seerr = {
        enable = true;
        package = pkgs.jellyseerr;
        apiKey._secret = config.sops.secrets."jellyseerr-api-key".path;
      };

      # SABnzbd usenet download client
      usenetClients.sabnzbd = {
        enable = true;
        settings.misc = {
          api_key._secret = config.sops.secrets."sabnzbd-api-key".path;
          nzb_key._secret = config.sops.secrets."sabnzbd-nzb-key".path;
          port = 8080;
        };
      };
    };

    # Readarr (book grabber) — not yet in Nixflix, use native NixOS service
    services.readarr = {
      enable = true;
      openFirewall = false;
    };
    users.users.readarr.extraGroups = [ "media" ];

    # Completes the Jellyseerr setup wizard declaratively:
    # logs in via Jellyfin creds, syncs + enables all libraries, marks initialized.
    # Uses session cookie auth (same as nixflix's seerr-setup) — idempotent.
    systemd.services.seerr-library-setup = {
      description = "Activate all Jellyfin libraries in Jellyseerr";
      after    = [ "seerr.service" "seerr-setup.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        COOKIE="/tmp/seerr-library-setup-cookie"

        # Wait up to 2 minutes for Jellyseerr
        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Skip if already initialized
        if curl -s "$SEERR/api/v1/settings/public" | jq -e '.initialized == true' > /dev/null; then
          echo "Jellyseerr already initialized — nothing to do."
          exit 0
        fi

        # Log in with credentials only (no server config — Jellyfin is already wired by nixflix)
        echo "Logging in..."
        ADMIN_PASS=$(cat ${config.sops.secrets."jellyfin-admin-password".path})
        LOGIN_CODE=$(curl -s -c "$COOKIE" -X POST \
          -H "Content-Type: application/json" \
          -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" \
          -w "%{http_code}" -o /dev/null \
          "$SEERR/api/v1/auth/jellyfin")

        if [ "$LOGIN_CODE" != "200" ] && [ "$LOGIN_CODE" != "201" ]; then
          echo "Login failed (HTTP $LOGIN_CODE)" >&2; exit 1
        fi
        echo "Logged in."

        # Sync libraries from Jellyfin and enable all of them
        echo "Syncing libraries..."
        LIBS=$(curl -s -b "$COOKIE" "$SEERR/api/v1/settings/jellyfin/library?sync=true")
        echo "Found: $(echo "$LIBS" | jq -r '.[].name' | tr '\n' ' ')"
        LIBRARY_IDS=$(echo "$LIBS" | jq -r '.[].id' | paste -sd,)

        if [ -n "$LIBRARY_IDS" ]; then
          curl -sf -b "$COOKIE" \
            "$SEERR/api/v1/settings/jellyfin/library?enable=$LIBRARY_IDS" > /dev/null
          echo "Libraries enabled: $LIBRARY_IDS"
        else
          echo "Warning: no libraries found"
        fi

        # Mark setup as complete (dismisses wizard permanently)
        curl -sf -b "$COOKIE" -X POST "$SEERR/api/v1/settings/initialize" > /dev/null

        rm -f "$COOKIE"
        echo "Jellyseerr setup complete."
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# BOOKS — Kavita book server
# Android: install Kavita app → connect to http://<tailscale-ip>:5000
# Post-boot: add Readarr to Prowlarr in the Prowlarr UI (Settings → Apps)
# Port: 5000 (Tailscale only)
# ══════════════════════════════════════════════════════════════════════════════

    virtualisation.oci-containers.containers.kavita = {
      image = "lscr.io/linuxserver/kavita:latest";
      ports = [ "5000:5000" ];
      volumes = [
        "/var/lib/kavita:/config"
        "/data/media/books:/books"
      ];
      environment = {
        PUID = "1000"; # rock user
        PGID = "1001"; # media group
        TZ   = "Australia/Sydney";
      };
      autoStart = true;
    };


# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD — Homepage (declarative homelab dashboard)
# Runs as a native NixOS service (not a container) so localhost works for all
# arr/jellyfin widgets and /data is accessible for the disk widget.
# API keys are injected from sops via an env file on every boot.
# Readarr, Kavita, Immich are links only (API keys not in sops yet).
# Port: 3000 (Tailscale only)
# ══════════════════════════════════════════════════════════════════════════════

    # Writes sops API keys to an env file for {{HOMEPAGE_VAR_*}} substitution
    systemd.services.homepage-env = {
      description = "Generate Homepage env file from sops secrets";
      wantedBy = [ "homepage-dashboard.service" ];
      before   = [ "homepage-dashboard.service" ];
      partOf   = [ "homepage-dashboard.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/homepage
        {
          printf 'HOMEPAGE_VAR_SONARR_API_KEY=%s\n'     "$(cat ${config.sops.secrets."sonarr-api-key".path})"
          printf 'HOMEPAGE_VAR_RADARR_API_KEY=%s\n'     "$(cat ${config.sops.secrets."radarr-api-key".path})"
          printf 'HOMEPAGE_VAR_LIDARR_API_KEY=%s\n'     "$(cat ${config.sops.secrets."lidarr-api-key".path})"
          printf 'HOMEPAGE_VAR_PROWLARR_API_KEY=%s\n'   "$(cat ${config.sops.secrets."prowlarr-api-key".path})"
          printf 'HOMEPAGE_VAR_SABNZBD_API_KEY=%s\n'    "$(cat ${config.sops.secrets."sabnzbd-api-key".path})"
          printf 'HOMEPAGE_VAR_JELLYFIN_API_KEY=%s\n'   "$(cat ${config.sops.secrets."jellyfin-api-key".path})"
          printf 'HOMEPAGE_VAR_JELLYSEERR_API_KEY=%s\n' "$(cat ${config.sops.secrets."jellyseerr-api-key".path})"
        } > /var/lib/homepage/homepage.env
        chmod 600 /var/lib/homepage/homepage.env
      '';
    };

    # Pass env file to the homepage-dashboard systemd service
    systemd.services.homepage-dashboard.serviceConfig.EnvironmentFile =
      lib.mkForce "/var/lib/homepage/homepage.env";

    services.homepage-dashboard = {
      enable = true;
      listenPort = 3000;

      settings = {
        title = "Asgard";
        theme = "dark";
        color = "slate";
        headerStyle = "clean";
        layout = {
          "Media"             = { style = "row"; columns = 3; };
          "Downloads"         = { style = "row"; columns = 2; };
          "Arr Stack"         = { style = "row"; columns = 4; };
          "Books & Utilities" = { style = "row"; columns = 3; };
        };
      };

      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/data";
            cacheInterval = 5;
          };
        }
        {
          datetime = {
            text_size = "xl";
            format = {
              timeStyle = "short";
              dateStyle = "long";
              hour12 = false;
            };
          };
        }
      ];

      services = [
        {
          "Media" = [
            {
              "Jellyfin" = {
                href = "http://localhost:8096";
                description = "Media Server";
                icon = "jellyfin.png";
                widget = {
                  type = "jellyfin";
                  url = "http://localhost:8096";
                  key = "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}";
                  enableBlocks = true;
                };
              };
            }
            {
              "Jellyseerr" = {
                href = "http://localhost:5055";
                description = "Media Requests";
                icon = "jellyseerr.png";
                widget = {
                  type = "overseerr";
                  url = "http://localhost:5055";
                  key = "{{HOMEPAGE_VAR_JELLYSEERR_API_KEY}}";
                };
              };
            }
            {
              "Immich" = {
                href = "http://localhost:2283";
                description = "Photo Server";
                icon = "immich.png";
              };
            }
          ];
        }
        {
          "Downloads" = [
            {
              "SABnzbd" = {
                href = "http://localhost:8080";
                description = "Usenet Downloader";
                icon = "sabnzbd.png";
                widget = {
                  type = "sabnzbd";
                  url = "http://localhost:8080";
                  key = "{{HOMEPAGE_VAR_SABNZBD_API_KEY}}";
                };
              };
            }
            {
              "Prowlarr" = {
                href = "http://localhost:9696";
                description = "Indexer Manager";
                icon = "prowlarr.png";
                widget = {
                  type = "prowlarr";
                  url = "http://localhost:9696";
                  key = "{{HOMEPAGE_VAR_PROWLARR_API_KEY}}";
                };
              };
            }
          ];
        }
        {
          "Arr Stack" = [
            {
              "Sonarr" = {
                href = "http://localhost:8989";
                description = "TV Shows";
                icon = "sonarr.png";
                widget = {
                  type = "sonarr";
                  url = "http://localhost:8989";
                  key = "{{HOMEPAGE_VAR_SONARR_API_KEY}}";
                };
              };
            }
            {
              "Radarr" = {
                href = "http://localhost:7878";
                description = "Movies";
                icon = "radarr.png";
                widget = {
                  type = "radarr";
                  url = "http://localhost:7878";
                  key = "{{HOMEPAGE_VAR_RADARR_API_KEY}}";
                };
              };
            }
            {
              "Lidarr" = {
                href = "http://localhost:8686";
                description = "Music";
                icon = "lidarr.png";
                widget = {
                  type = "lidarr";
                  url = "http://localhost:8686";
                  key = "{{HOMEPAGE_VAR_LIDARR_API_KEY}}";
                };
              };
            }
            {
              "Readarr" = {
                href = "http://localhost:8787";
                description = "Books";
                icon = "readarr.png";
              };
            }
          ];
        }
        {
          "Books & Utilities" = [
            {
              "Kavita" = {
                href = "http://localhost:5000";
                description = "Book Server";
                icon = "kavita.png";
              };
            }
            {
              "Dozzle" = {
                href = "http://localhost:8888";
                description = "Container Logs";
                icon = "dozzle.png";
              };
            }
            {
              "File Browser" = {
                href = "http://localhost:8081";
                description = "File Manager";
                icon = "filebrowser.png";
              };
            }
          ];
        }
      ];

      bookmarks = [
        {
          "Quick Links" = [
            { "Nixpkgs Search" = [{ abbr = "NX"; href = "https://search.nixos.org/packages"; }]; }
            { "NixOS Options"  = [{ abbr = "NO"; href = "https://search.nixos.org/options"; }]; }
          ];
        }
      ];
    };


# ══════════════════════════════════════════════════════════════════════════════
# AUTOMATION — Decluttarr queue cleaner
# Polls arr service APIs to remove stalled/failed downloads automatically.
# DEFERRED until first boot (needs arr API keys generated by services).
# After first boot:
#   1. Retrieve API keys from each service (Settings → General → API Key)
#   2. Add to sops: sops ~/Dots/Secrets/secrets.yaml
#        decluttarr-env: |
#          SONARR_URL=http://localhost:8989
#          SONARR_KEY=<key>
#          RADARR_URL=http://localhost:7878
#          RADARR_KEY=<key>
#          LIDARR_URL=http://localhost:8686
#          LIDARR_KEY=<key>
#          READARR_URL=http://localhost:8787
#          READARR_KEY=<key>
#          SABNZBD_URL=http://localhost:8080
#          SABNZBD_KEY=<key>
#          REMOVE_STALLED=True
#          REMOVE_FAILED_IMPORTS=True
#          REMOVE_FAILED=True
#          REMOVE_METADATA_MISSING=True
#          REMOVE_ORPHANS=True
#   3. Un-comment container and add `sops.secrets."decluttarr-env" = {};` below
#   4. Rebuild Asgard
# ══════════════════════════════════════════════════════════════════════════════

    # virtualisation.oci-containers.containers.decluttarr = {
    #   image = "ghcr.io/manimatter/decluttarr:latest";
    #   environmentFiles = [ config.sops.secrets."decluttarr-env".path ];
    #   autoStart = true;
    # };


# ══════════════════════════════════════════════════════════════════════════════
# NETWORKING — Tailscale VPN + Cloudflare Tunnel
# Native NixOS services (not containers).
#
# Tailscale: run `sudo tailscale up` after first boot to authenticate.
#
# Cloudflare tunnel setup (one-time before first build):
#   1. dash.cloudflare.com → Zero Trust → Networks → Tunnels → Create tunnel
#   2. Name it "asgard", copy the Tunnel UUID shown on the detail page
#   3. Download/copy the credentials JSON shown during creation
#   4. sops ~/Dots/Secrets/secrets.yaml
#        cloudflare-tunnel: '<full credentials JSON>'
#   5. Replace TUNNEL-UUID-HERE below with the actual UUID
#
# Public URLs (bifrost-vault.com):
#   jellyfin.bifrost-vault.com  → localhost:8096
#   requests.bifrost-vault.com  → localhost:5055
#   photos.bifrost-vault.com    → localhost:2283
# ══════════════════════════════════════════════════════════════════════════════

    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    services.cloudflared = {
      enable = true;
      tunnels = {
        "804d54a8-e7ad-4f34-812d-3052cf862c47" = {
          credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
          default = "http_status:404";
          ingress = {
            "jellyfin.bifrost-vault.com"  = "http://localhost:8096";
            "requests.bifrost-vault.com"  = "http://localhost:5055";
            "photos.bifrost-vault.com"    = "http://localhost:2283";
          };
        };
      };
    };


# ══════════════════════════════════════════════════════════════════════════════
# UTILITIES — Dozzle (container log viewer) + File Browser
# Port 8888: Dozzle      — live container logs, no auth needed (Tailscale-only)
# Port 8081: FileBrowser — full filesystem browser, set password on first login
#   Default login: admin / admin — change immediately after first boot
# Both are Tailscale-only, not exposed via Cloudflare tunnel.
# ══════════════════════════════════════════════════════════════════════════════

    virtualisation.oci-containers.containers.dozzle = {
      image = "amir20/dozzle:latest";
      ports = [ "8888:8080" ];
      volumes = [ "/run/podman/podman.sock:/var/run/docker.sock:ro" ];
      autoStart = true;
    };

    virtualisation.oci-containers.containers.filebrowser = {
      image = "ghcr.io/gtsteffaniak/filebrowser:latest";
      ports = [ "8081:8080" ];
      volumes = [
        "/:/srv"
        "/var/lib/filebrowser:/config"
      ];
      autoStart = true;
    };


# ══════════════════════════════════════════════════════════════════════════════
# PHOTOS — Immich photo server
# Native NixOS module — manages its own PostgreSQL and Redis automatically.
# Public URL: photos.bifrost-vault.com (via Cloudflare tunnel)
# Port: 2283
# Post-boot: create admin account at http://localhost:2283 on first visit.
# ══════════════════════════════════════════════════════════════════════════════

    services.immich = {
      enable = true;
      mediaLocation = "/data/photos";
      openFirewall = false;
    };


# ══════════════════════════════════════════════════════════════════════════════
# INFRASTRUCTURE — Podman, media group, data directories, sops secrets
# ══════════════════════════════════════════════════════════════════════════════

    # --- Podman (OCI backend for Kavita, Dozzle, FileBrowser) ---
    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman = {
      enable = true;
      dockerSocket.enable = true; # compat socket for Dozzle
    };
    # Allow containers to reach host-bound services (arr, immich, etc.)
    networking.firewall.trustedInterfaces = [ "podman0" "cni-podman0" ];

    # --- Shared media group (GID 1001) ---
    # All service users and containers use this group for /data/media access.
    users.groups.media = { gid = 1001; };
    users.users.${activeUser}.extraGroups = [ "media" ];
    users.users.jellyfin.extraGroups = [ "media" ];

    # --- Data directories ---
    systemd.tmpfiles.rules = [
      "d /data                      0755 root  root  -"
      "d /data/media                0775 root  media -"
      "d /data/media/tv             0775 root  media -"
      "d /data/media/movies         0775 root  media -"
      "d /data/media/music          0775 root  media -"
      "d /data/media/books          0775 root  media -"
      "d /data/downloads            0775 root  media -"
      "d /data/downloads/usenet     0775 root  media -"
      "d /data/photos               0775 root  media -"
      "d /data/.state/services      0775 root  media -"
      # Container state dirs
      "d /var/lib/kavita            0775 root  media -"
      "d /var/lib/homepage          0755 root  root  -"
      "d /var/lib/filebrowser       0775 root  media -"
    ];

    # --- Sops secrets ---
    # All secrets live in Secrets/secrets.yaml.
    # Before first build, populate them with:
    #
    #   sops ~/Dots/Secrets/secrets.yaml
    #
    # Add each key as a plain string (generate with: od -An -tx1 -N16 /dev/urandom | tr -d ' \n'):
    #   sonarr-api-key: "<32 hex chars>"
    #   radarr-api-key: "<32 hex chars>"
    #   lidarr-api-key: "<32 hex chars>"
    #   prowlarr-api-key: "<32 hex chars>"
    #   jellyseerr-api-key: "<32 hex chars>"
    #   sabnzbd-api-key: "<32 hex chars>"
    #   sabnzbd-nzb-key: "<32 hex chars>"
    #   jellyfin-api-key: "<32 hex chars>"
    #   jellyfin-admin-password: "<your chosen password>"
    #   cloudflare-tunnel: "<full credentials JSON from Cloudflare dashboard>"
    sops.secrets."sonarr-api-key"           = {};
    sops.secrets."radarr-api-key"           = {};
    sops.secrets."lidarr-api-key"           = {};
    sops.secrets."prowlarr-api-key"         = {};
    sops.secrets."jellyseerr-api-key"        = {};
    sops.secrets."sabnzbd-api-key"          = {};
    sops.secrets."sabnzbd-nzb-key"          = {};
    sops.secrets."jellyfin-api-key"         = {};
    sops.secrets."jellyfin-admin-password"  = {};
    sops.secrets."cloudflare-tunnel"        = {};

    # Kernel UDP buffer tuning for smooth streaming over Tailscale
    boot.kernel.sysctl = {
      "net.core.rmem_max"           = lib.mkDefault 26214400;
      "net.core.wmem_max"           = lib.mkDefault 26214400;
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
    };

  };
}
