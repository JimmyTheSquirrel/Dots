{pkgs, ...}: let
  serverIP = "192.168.5.14";

  homepageServices = pkgs.writeText "services.yaml" ''
    ---
    - Media:
        - Jellyfin:
            icon: jellyfin.png
            href: http://${serverIP}:8096
            description: Media Server
            widget:
              type: jellyfin
              url: http://jellyfin:8096
              key: {{HOMEPAGE_VAR_JELLYFIN_API_KEY}}

        - Jellyseerr:
            icon: jellyseerr.png
            href: http://${serverIP}:5055
            description: Request Media
            widget:
              type: jellyseerr
              url: http://jellyseerr:5055
              key: {{HOMEPAGE_VAR_JELLYSEERR_API_KEY}}

    - Downloads:
        - SABnzbd:
            icon: sabnzbd.png
            href: http://${serverIP}:8080
            description: Usenet Downloader
            widget:
              type: sabnzbd
              url: http://sabVPN:8080
              key: {{HOMEPAGE_VAR_SABNZBD_API_KEY}}

        - qBittorrent:
            icon: qbittorrent.png
            href: http://${serverIP}:8082
            description: Torrent Client
            widget:
              type: qbittorrent
              url: http://qbittorrent:8082
              username: {{HOMEPAGE_VAR_QBITTORRENT_USERNAME}}
              password: {{HOMEPAGE_VAR_QBITTORRENT_PASSWORD}}

    - Automation:
        - Sonarr:
            icon: sonarr.png
            href: http://${serverIP}:8989
            description: TV Shows
            widget:
              type: sonarr
              url: http://sonarr:8989
              key: {{HOMEPAGE_VAR_SONARR_API_KEY}}

        - Radarr:
            icon: radarr.png
            href: http://${serverIP}:7878
            description: Movies
            widget:
              type: radarr
              url: http://radarr:7878
              key: {{HOMEPAGE_VAR_RADARR_API_KEY}}

        - Bazarr:
            icon: bazarr.png
            href: http://${serverIP}:6767
            description: Subtitles
            widget:
              type: bazarr
              url: http://bazarr:6767
              key: {{HOMEPAGE_VAR_BAZARR_API_KEY}}

        - Prowlarr:
            icon: prowlarr.png
            href: http://${serverIP}:9696
            description: Indexer Manager
            widget:
              type: prowlarr
              url: http://prowlarr:9696
              key: {{HOMEPAGE_VAR_PROWLARR_API_KEY}}

    - Management:
        - Portainer:
            icon: portainer.png
            href: http://${serverIP}:9000
            description: Docker Management

        - FlareSolverr:
            icon: flaresolverr.png
            href: http://${serverIP}:8191
            description: Cloudflare Bypass
  '';

  homepageSettings = pkgs.writeText "settings.yaml" ''
    ---
    title: Media Server
    favicon: https://raw.githubusercontent.com/gethomepage/homepage/main/public/android-chrome-192x192.png
    theme: dark
    color: slate
    layout:
      Media:
        style: row
        columns: 2
      Downloads:
        style: row
        columns: 2
      Automation:
        style: row
        columns: 4
      Management:
        style: row
        columns: 2
  '';

  homepageWidgets = pkgs.writeText "widgets.yaml" ''
    ---
    - resources:
        cpu: true
        memory: true
        disk: /

    - search:
        provider: google
        target: _blank
  '';

  homepageBookmarks = pkgs.writeText "bookmarks.yaml" ''
    ---
    - Useful Links:
        - Reddit r/selfhosted:
            - icon: reddit.png
              href: https://reddit.com/r/selfhosted
        - TRaSH Guides:
            - icon: si-trakt
              href: https://trash-guides.info/
  '';
in {
  environment.systemPackages = with pkgs; [
    libva-utils
    radeontop
  ];

  users.groups.arrr = {
    gid = 995;
  };
  users.users."rock".extraGroups = ["arrr"];

  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    vaapiVdpau
    libvdpau-va-gl
    mesa.drivers
  ];

  hardware.enableAllFirmware = true;

  systemd.tmpfiles.rules = [
    "d /config/jellyfin 0775 - arrr - -"
    "d /config/jellyseerr 0775 - arrr - -"
    "d /config/prowlarr 0775 - arrr - -"
    "d /config/sonarr 0775 - arrr - -"
    "d /config/radarr 0775 - arrr - -"
    "d /config/qbitvpn 0775 - arrr - -"
    "d /config/sabnzb 0775 - arrr - -"
    "d /config/bazarr 0775 - arrr - -"
    "d /config/homepage 0775 - arrr - -"
    "d /config/portainer 0775 - arrr - -"
    "d /config/qbittorrent 0775 - arrr - -"

    # Data directories
    "d /data/torrents 0775 - arrr - -"

    # IMPORTANT: directories you were actually using in practice
    "d /data/torrents/complete 0775 - arrr - -"

    "d /data/media 0775 - arrr - -"
    "d /data/media/movies 0775 - arrr - -"
    "d /data/media/tv 0775 - arrr - -"
  ];

  systemd.services.setup-homepage-config = {
    description = "Setup Homepage configuration files";
    wantedBy = ["multi-user.target"];
    before = ["docker-homepage.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /config/homepage
      rm -f /config/homepage/services.yaml
      rm -f /config/homepage/settings.yaml
      rm -f /config/homepage/widgets.yaml
      rm -f /config/homepage/bookmarks.yaml
      cp ${homepageServices} /config/homepage/services.yaml
      cp ${homepageSettings} /config/homepage/settings.yaml
      cp ${homepageWidgets} /config/homepage/widgets.yaml
      cp ${homepageBookmarks} /config/homepage/bookmarks.yaml

      if [ -f /home/rock/Downloads/Docker/homepage.env ]; then
        cp /home/rock/Downloads/Docker/homepage.env /config/homepage/.env
        chown 1000:995 /config/homepage/.env
        chmod 600 /config/homepage/.env
      fi

      chown -R 1000:995 /config/homepage
      chmod -R 775 /config/homepage
    '';
  };

  systemd.services.init-arrr-network = {
    description = "Create the arrr Docker network";
    after = ["docker.service"];
    requires = ["docker.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.docker}/bin/docker network create arrr-network || true
    '';
  };

  virtualisation.oci-containers.containers = {
    jellyfin = {
      image = "jellyfin/jellyfin";
      extraOptions = [
        "--device=/dev/dri:/dev/dri"
        "--group-add=video"
        "--network=arrr-network"
      ];
      ports = ["8096:8096"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
      };
      volumes = [
        "/config/jellyfin:/config"
        "/data/media:/media"
      ];
      autoStart = true;
    };

    jellyseerr = {
      image = "ghcr.io/fallenbagel/jellyseerr:latest";
      extraOptions = ["--network=arrr-network"];
      ports = ["5055:5055"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
      };
      volumes = ["/config/jellyseerr:/config"];
      autoStart = true;
    };

    sabVPN = {
      image = "docker.io/binhex/arch-sabnzbdvpn:latest";
      extraOptions = [
        "--sysctl=\"net.ipv4.conf.all.src_valid_mark=1\""
        "--privileged=true"
        "--network=arrr-network"
      ];
      ports = ["8080:8080"];
      environment = {
        PUID = "1000";
        PGID = "995";
        VPN_ENABLED = "yes";
        VPN_PROV = "custom";
        VPN_CLIENT = "wireguard";
        STRICT_PORT_FORWARD = "yes";
        ENABLE_PRIVOXY = "no";
        ENABLE_SOCKS = "no";
        LAN_NETWORK = "10.11.12.0/24";
      };
      volumes = [
        "/config/sabnzb:/config"
        "/data/torrents:/data/torrents"
        "/etc/localtime:/etc/localtime:ro"
      ];
      autoStart = true;
    };

    prowlarr = {
      image = "ghcr.io/hotio/prowlarr";
      extraOptions = ["--network=arrr-network"];
      ports = ["9696:9696"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
        RUN_OPTS = "--ProxyConnection=10.11.12.201:8118";
      };
      volumes = ["/config/prowlarr:/config"];
      autoStart = true;
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      extraOptions = ["--network=arrr-network"];
      ports = ["8191:8191"];
      autoStart = true;
    };

    radarr = {
      image = "ghcr.io/hotio/radarr";
      extraOptions = ["--network=arrr-network"];
      ports = ["7878:7878"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
        RUN_OPTS = "--ProxyConnection=10.11.12.201:8118";
      };
      volumes = [
        "/config/radarr:/config"
        "/data:/data"
      ];
      autoStart = true;
    };

    sonarr = {
      image = "ghcr.io/hotio/sonarr";
      extraOptions = ["--network=arrr-network"];
      ports = ["8989:8989"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
        RUN_OPTS = "--ProxyConnection=10.11.12.201:8118";
      };
      volumes = [
        "/config/sonarr:/config"
        "/data:/data"
      ];
      autoStart = true;
    };

    bazarr = {
      image = "ghcr.io/hotio/bazarr";
      extraOptions = ["--network=arrr-network"];
      ports = ["6767:6767"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
      };
      volumes = [
        "/config/bazarr:/config"
        "/data:/data"
      ];
      autoStart = true;
    };

    qbittorrent = {
      image = "lscr.io/linuxserver/qbittorrent:latest";
      extraOptions = ["--network=arrr-network"];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
        TZ = "Etc/UTC";
        WEBUI_PORT = "8082";
        TORRENTING_PORT = "6881";
      };
      volumes = [
        "/config/qbittorrent:/config"
        # FIX: match internal paths with Radarr/Sonarr
        "/data:/data"
      ];
      ports = [
        "8082:8082"
        "6881:6881"
        "6881:6881/udp"
      ];
      autoStart = true;
    };

    homepage = {
      image = "ghcr.io/gethomepage/homepage:latest";
      extraOptions = ["--network=arrr-network"];
      ports = ["3000:3000"];
      environment = {
        PUID = "1000";
        PGID = "995";
      };
      volumes = [
        "/config/homepage:/app/config"
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
      autoStart = true;
    };

    portainer = {
      image = "portainer/portainer-ce:latest";
      extraOptions = ["--network=arrr-network"];
      ports = [
        "9000:9000"
        "9443:9443"
      ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/config/portainer:/data"
      ];
      autoStart = true;
    };
  };

  systemd.services.docker-homepage = {
    after = ["setup-homepage-config.service"];
    requires = ["setup-homepage-config.service"];
  };

  virtualisation = {
    docker.enable = true;
    oci-containers.backend = "docker";
    containers.enable = true;
  };

  networking.firewall.allowedTCPPorts = [
    9696
    8191
    8989
    7878
    6767
    8096
    5055
    8080
    8082
    3000
    9000
    9443
    32400
  ];
  networking.firewall.allowedUDPPorts = [9696 8191 8989 6881];
}
