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
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      radarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."radarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      lidarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."lidarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      prowlarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."prowlarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
          indexers = [
            {
              name = "Miatrix";
              apiKey._secret = config.sops.secrets."indexer-api-keys/Miatrix".path;
            }
            {
              name = "NZBgeek";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBGeek".path;
            }
            {
              name = "NzbPlanet";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBPlanet".path;
            }
          ];
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
        settings = {
          misc = {
            api_key._secret  = config.sops.secrets."sabnzbd-api-key".path;
            nzb_key._secret  = config.sops.secrets."sabnzbd-nzb-key".path;
            username._secret = config.sops.secrets."sabnzbd-username".path;
            password._secret = config.sops.secrets."sabnzbd-password".path;
            port = 8080;
            par2_multicore = 1;
          };
          servers = [
            {
              name = "FrugalUsenet";
              host = "aunews.frugalusenet.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/frugalusenet/username".path;
              password._secret = config.sops.secrets."usenet/frugalusenet/password".path;
              connections = 200;
              ssl = true;
              priority = 0;
            }
          ];
        };
      };
    };


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
# BOOKS — Audiobookshelf (server) + Shelfarr (request portal)
# Audiobookshelf: port 13378 — serves ebooks + audiobooks (Jellyfin-style UI)
# Shelfarr:       port 5056  — Jellyseerr-style request portal for books
#   Connects to Prowlarr (search) + SABnzbd (download) → delivers to ABS
#
# Post-boot (one-time): open Shelfarr at localhost:5056 → Admin → Settings:
#   Prowlarr: http://localhost:9696 + prowlarr-api-key (from sops)
#   SABnzbd:  http://localhost:8080 + sabnzbd-api-key (from sops)
#   ABS:      http://localhost:13378 + key from ABS Settings → API Keys
# ══════════════════════════════════════════════════════════════════════════════

    # Audiobookshelf — ebook + audiobook server
    virtualisation.oci-containers.containers.audiobookshelf = {
      image = "ghcr.io/advplyr/audiobookshelf:latest";
      ports = [ "13378:80" ];
      volumes = [
        "/var/lib/audiobookshelf/config:/config"
        "/var/lib/audiobookshelf/metadata:/metadata"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
      ];
      environment = {
        TZ = "Australia/Sydney";
      };
      autoStart = true;
    };

    # Shelfarr — Jellyseerr-style book request portal
    # RAILS_MASTER_KEY is auto-generated on first run and stored in /var/lib/shelfarr.
    # As long as the volume persists, the key is preserved across rebuilds.
    virtualisation.oci-containers.containers.shelfarr = {
      image = "ghcr.io/pedro-revez-silva/shelfarr:latest";
      ports = [ "5056:4000" ];
      volumes = [
        "/var/lib/shelfarr:/rails/storage"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
        "/data/downloads:/downloads"
      ];
      environment = {
        PUID                = "1000";
        PGID                = "1001";
        SOLID_QUEUE_IN_PUMA = "1";
        HTTP_PORT           = "4000";  # Go proxy port — must differ from Rails/Puma (3000)
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
          printf 'HOMEPAGE_VAR_TAILSCALE_API_KEY=%s\n' "$(cat ${config.sops.secrets."tailscale-api-key".path})"
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
      settings.allowedHosts = "sisyphus,sisyphus:3000,localhost,localhost:3000";

      settings = {
        title = "Asgard";
        theme = "dark";
        color = "neutral";
        headerStyle = "clean";
        layout = {
          "Services"   = { style = "row"; columns = 2; };  # arr (left) + media (right), 2-col grid
          "Downloads"  = { style = "row"; columns = 2; };
          "Utilities"  = { style = "column"; };
          "Network"    = { style = "row"; columns = 4; };
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
          # columns = 2 → items fill left-to-right, so odd positions = left col (arr),
          # even positions = right col (media). Interleave to achieve the desired layout:
          #   Sonarr    | Jellyfin
          #   Radarr    | Jellyseerr
          #   Lidarr    | Readarr
          "Services" = [
            {
              "Sonarr" = {
                href = "http://sisyphus:8989";
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
              "Jellyfin" = {
                href = "http://sisyphus:8096";
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
              "Radarr" = {
                href = "http://sisyphus:7878";
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
              "Jellyseerr" = {
                href = "http://sisyphus:5055";
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
              "Readarr" = {
                href = "http://sisyphus:8787";
                description = "Books";
                icon = "readarr.png";
                widget = {
                  type = "readarr";
                  url = "http://localhost:8787";
                  key = "{{HOMEPAGE_VAR_READARR_API_KEY}}";
                };
              };
            }
            {
              "Lidarr" = {
                href = "http://sisyphus:8686";
                description = "Music";
                icon = "lidarr.png";
                widget = {
                  type = "lidarr";
                  url = "http://localhost:8686";
                  key = "{{HOMEPAGE_VAR_LIDARR_API_KEY}}";
                };
              };
            }
          ];
        }
        {
          "Downloads" = [
            {
              "SABnzbd" = {
                href = "http://sisyphus:8080";
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
                href = "http://sisyphus:9696";
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
          "Utilities" = [
            {
              "Immich" = {
                href = "http://sisyphus:2283";
                description = "Photo Server";
                icon = "immich.png";
              };
            }
            {
              "Audiobookshelf" = {
                href = "http://sisyphus:13378";
                description = "Books & Audiobooks";
                icon = "audiobookshelf.png";
              };
            }
            {
              "Shelfarr" = {
                href = "http://sisyphus:5056";
                description = "Book Requests";
                icon = "shelfarr.png";
              };
            }
            {
              "Dozzle" = {
                href = "http://sisyphus:8888";
                description = "Container Logs";
                icon = "dozzle.png";
              };
            }
            {
              "File Browser" = {
                href = "http://sisyphus:8081";
                description = "File Manager";
                icon = "filebrowser.png";
              };
            }
          ];
        }
        {
          "Network" = [
            {
              "Sisyphus" = {
                icon = "tailscale.png";
                description = "Linux Desktop";
                widget = {
                  type = "tailscale";
                  deviceid = "8021612644818291";
                  key = "{{HOMEPAGE_VAR_TAILSCALE_API_KEY}}";
                  fields = [ "last_seen" "os" "authorized" ];
                };
              };
            }
            {
              "Eclipse Pi" = {
                icon = "tailscale.png";
                description = "Raspberry Pi";
                widget = {
                  type = "tailscale";
                  deviceid = "3166629277500775";
                  key = "{{HOMEPAGE_VAR_TAILSCALE_API_KEY}}";
                  fields = [ "last_seen" "os" "authorized" ];
                };
              };
            }
            {
              "Caitlin's S25" = {
                icon = "tailscale.png";
                description = "Android";
                widget = {
                  type = "tailscale";
                  deviceid = "6502532657979703";
                  key = "{{HOMEPAGE_VAR_TAILSCALE_API_KEY}}";
                  fields = [ "last_seen" "os" "authorized" ];
                };
              };
            }
            {
              "Rhys's S25" = {
                icon = "tailscale.png";
                description = "Android";
                widget = {
                  type = "tailscale";
                  deviceid = "5131325073312736";
                  key = "{{HOMEPAGE_VAR_TAILSCALE_API_KEY}}";
                  fields = [ "last_seen" "os" "authorized" ];
                };
              };
            }
          ];
        }
      ];

      bookmarks = [
        {
          "Quick Links" = [
            { "Nixpkgs Search"   = [{ abbr = "NX"; href = "https://search.nixos.org/packages"; }]; }
            { "NixOS Options"    = [{ abbr = "NO"; href = "https://search.nixos.org/options"; }]; }
            { "Tailscale Admin"  = [{ abbr = "TS"; href = "https://login.tailscale.com/admin/machines"; }]; }
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

# ══════════════════════════════════════════════════════════════════════════════
# QUALITY — Recyclarr (TRaSH Guides quality profile sync)
# Syncs quality profiles + custom formats to Sonarr + Radarr on boot + daily.
#   Sonarr: WEB-1080p + WEB-2160p (TV is web-sourced)
#   Radarr: Remux-1080p + Remux-2160p (Remux → Bluray → WEB, best first)
# This fixes grab issues like "only getting Redux" — proper CF scoring applied.
# ══════════════════════════════════════════════════════════════════════════════

    systemd.services.recyclarr-config = {
      description = "Generate Recyclarr config from sops secrets";
      before   = [ "recyclarr-sync.service" ];
      wantedBy = [ "recyclarr-sync.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/recyclarr
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        cat > /var/lib/recyclarr/recyclarr.yml << EOF
sonarr:
  main:
    base_url: http://localhost:8989
    api_key: $SONARR_KEY
    include:
      - template: sonarr-quality-definition-series
      - template: sonarr-v4-quality-profile-web-1080p
      - template: sonarr-v4-custom-formats-web-1080p
      - template: sonarr-v4-quality-profile-web-2160p
      - template: sonarr-v4-custom-formats-web-2160p
radarr:
  main:
    base_url: http://localhost:7878
    api_key: $RADARR_KEY
    include:
      - template: radarr-quality-definition-movie
      - template: radarr-quality-profile-remux-1080p
      - template: radarr-custom-formats-remux-1080p
      - template: radarr-quality-profile-remux-2160p
      - template: radarr-custom-formats-remux-2160p
EOF
        chmod 600 /var/lib/recyclarr/recyclarr.yml
      '';
    };

    systemd.services.recyclarr-sync = {
      description = "Sync TRaSH Guides quality profiles via Recyclarr";
      after  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      wants  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config /var/lib/recyclarr/recyclarr.yml";
        Environment = "RECYCLARR_APP_DATA=/var/lib/recyclarr";
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Daily Recyclarr sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";
      };
    };


    systemd.services.decluttarr-config = {
      description = "Generate Decluttarr YAML config from sops secrets";
      wantedBy = [ "podman-decluttarr.service" ];
      before   = [ "podman-decluttarr.service" ];
      partOf   = [ "podman-decluttarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/decluttarr/config
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        LIDARR_KEY=$(cat ${config.sops.secrets."lidarr-api-key".path})
        SABNZBD_KEY=$(cat ${config.sops.secrets."sabnzbd-api-key".path})
        cat > /var/lib/decluttarr/config/config.yaml << EOF
instances:
  sonarr:
    - base_url: http://host.containers.internal:8989
      api_key: $SONARR_KEY
  radarr:
    - base_url: http://host.containers.internal:7878
      api_key: $RADARR_KEY
  lidarr:
    - base_url: http://host.containers.internal:8686
      api_key: $LIDARR_KEY
download_clients:
  sabnzbd:
    - name: SABnzbd
      base_url: http://host.containers.internal:8080
      api_key: $SABNZBD_KEY
jobs:
  remove_stalled: true
  remove_failed_imports: true
  remove_failed_downloads: true
  remove_metadata_missing: true
  remove_orphans: true
EOF
        chmod 600 /var/lib/decluttarr/config/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.decluttarr = {
      image = "ghcr.io/manimatter/decluttarr:latest";
      volumes = [ "/var/lib/decluttarr/config:/app/config" ];
      autoStart = true;
    };


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
# Port 8081: FileBrowser — full filesystem browser (downloads, media, photos)
#   Credentials managed via sops: filebrowser-username / filebrowser-password
#   filebrowser-credentials.service syncs them on every boot.
# Both are Tailscale-only, not exposed via Cloudflare tunnel.
# ══════════════════════════════════════════════════════════════════════════════

    virtualisation.oci-containers.containers.dozzle = {
      image = "amir20/dozzle:latest";
      ports = [ "8888:8080" ];
      volumes = [ "/run/podman/podman.sock:/var/run/docker.sock:ro" ];
      autoStart = true;
    };

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
        "/data/downloads:/downloads"
        "/data/media:/media"
        "/data/photos:/photos"
        "/var/lib/filebrowser:/home/filebrowser/data"
      ];
      user = "root";
      autoStart = true;
    };

    # Syncs admin credentials from sops on every boot.
    # Tries the sops password first (handles already-changed installs),
    # then falls back to "admin" (handles first run with default password).
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

        # Wait up to 60s for FileBrowser to accept connections
        for i in $(seq 1 30); do
          if curl -s "$BASE" > /dev/null 2>&1; then break; fi
          echo "Waiting for FileBrowser... ($i/30)"
          sleep 2
        done

        # Authenticate — try sops password first, fall back to default "admin"
        # || true on every jq call prevents set -e from exiting on parse errors
        TOKEN=""
        for CURRENT_PASS in "$PASSWORD" "admin"; do
          RESP=$(curl -s -X POST "$BASE/api/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"admin\",\"password\":\"$CURRENT_PASS\"}" 2>/dev/null) || true
          TOKEN=$(printf '%s' "$RESP" | jq -r '.token // empty' 2>/dev/null) || true
          [ -n "$TOKEN" ] && break
        done

        if [ -z "$TOKEN" ]; then
          echo "FileBrowser: could not authenticate — skipping credential sync" >&2
          exit 0
        fi

        # Fetch current user object, patch username + password, write back
        USER_DATA=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/users/1" 2>/dev/null) || true
        UPDATED=$(printf '%s' "$USER_DATA" | jq \
          --arg u "$USERNAME" --arg p "$PASSWORD" \
          '.username = $u | .password = $p' 2>/dev/null) || true

        if [ -z "$UPDATED" ]; then
          echo "FileBrowser: could not build update payload — skipping" >&2
          exit 0
        fi

        curl -s -X PUT "$BASE/api/users/1" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" > /dev/null

        echo "FileBrowser credentials synced (user: $USERNAME)."
      '';
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

    # Seeds the Immich admin account from sops on first boot.
    # /api/auth/admin-signup is only available before any admin exists — idempotent.
    systemd.services.immich-admin-seed = {
      description = "Create Immich admin account from sops";
      after    = [ "immich-server.service" "network.target" ];
      wants    = [ "immich-server.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:2283"

        # Wait up to 2 minutes for Immich
        for i in $(seq 1 24); do
          if curl -sf "$BASE/api/server/ping" > /dev/null 2>&1; then break; fi
          echo "Waiting for Immich... ($i/24)"
          sleep 5
        done

        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$BASE/api/auth/admin-signup" \
          -H "Content-Type: application/json" \
          -d "{\"email\":\"$USERNAME@asgard.local\",\"password\":\"$PASSWORD\",\"name\":\"$USERNAME\"}" 2>/dev/null) || true

        if [ "$CODE" = "201" ]; then
          echo "Immich admin created."
        elif [ "$CODE" = "400" ]; then
          echo "Immich admin already exists — skipping."
        else
          echo "Immich admin-signup returned HTTP $CODE" >&2
        fi
      '';
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
    # tailscale0 trusted so all services are reachable from any tailnet device by hostname
    networking.firewall.trustedInterfaces = [ "podman0" "cni-podman0" "tailscale0" ];

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
      "d /data/media/books          0777 root  media -"
      "d /data/downloads            0775 root  media -"
      "d /data/downloads/usenet     0775 root  media -"
      "d /data/photos               0775 root  media -"
      "d /data/.state/services      0775 root  media -"
      "d /data/media/audiobooks               0777 root  media -"
      # Container state dirs
      "d /var/lib/audiobookshelf             0775 root  media -"
      "d /var/lib/audiobookshelf/config      0775 root  media -"
      "d /var/lib/audiobookshelf/metadata    0775 root  media -"
      "d /var/lib/shelfarr                   0755 root  root  -"
      "d /var/lib/homepage                   0755 root  root  -"
      "d /var/lib/filebrowser       0775 root  media -"
      "d /var/lib/decluttarr        0755 root  root  -"
      "d /var/lib/decluttarr/config 0755 root  root  -"
      "d /var/lib/recyclarr         0700 root  root  -"
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
    sops.secrets."jellyseerr-api-key"       = {};
    # audiobookshelf-api-key: declare here + add to homepage-env once you have the key from ABS Settings → API Keys
    sops.secrets."sabnzbd-api-key"              = {};
    sops.secrets."sabnzbd-nzb-key"              = {};
    sops.secrets."sabnzbd-username"             = {};
    sops.secrets."sabnzbd-password"             = {};
    sops.secrets."usenet/frugalusenet/username"    = {};
    sops.secrets."usenet/frugalusenet/password"    = {};
    sops.secrets."indexer-api-keys/Miatrix"        = {};
    sops.secrets."indexer-api-keys/NZBGeek"        = {};
    sops.secrets."indexer-api-keys/NZBPlanet"      = {};
    sops.secrets."jellyfin-api-key"         = {};
    sops.secrets."jellyfin-admin-password"  = {};
    sops.secrets."cloudflare-tunnel"        = {};
    sops.secrets."tailscale-api-key"        = {};
    sops.secrets."admin-username"           = {};
    sops.secrets."admin-password"           = {};

    # Kernel UDP buffer tuning for smooth streaming over Tailscale
    boot.kernel.sysctl = {
      "net.core.rmem_max"           = lib.mkDefault 26214400;
      "net.core.wmem_max"           = lib.mkDefault 26214400;
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
    };

  };
}
