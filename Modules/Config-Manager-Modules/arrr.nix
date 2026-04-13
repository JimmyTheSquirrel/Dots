{pkgs, ...}: {
  # Use Docker (original setup that worked)
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  environment.systemPackages = with pkgs; [
    libva-utils
    radeontop
  ];

  users.groups.arrr = {
    gid = 995;
  };
  users.users."rock".extraGroups = ["arrr" "docker"];

  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    libva-vdpau-driver
    libvdpau-va-gl
    mesa.drivers
  ];

  hardware.enableAllFirmware = true;

  systemd.tmpfiles.rules = [
    "d /config/jellyfin 0775 - arrr - -"
    "d /config/plex 0775 - arrr - -"
    "d /config/plexTranscode 0775 - arrr - -"
    "d /config/jellyseerr 0775 - arrr - -"
    "d /config/prowlarr 0775 - arrr - -"
    "d /config/sonarr 0775 - arrr - -"
    "d /config/radarr 0775 - arrr - -"
    "d /config/qbitvpn 0775 - arrr - -"
    "d /config/sabnzb 0775 - arrr - -"
    "d /config/bazarr 0775 - arrr - -"
    "d /config/homepage 0775 1000 995 - -"

    "d /data/torrents/movies 0775 - arrr - -"
    "d /data/torrents/tv 0775 - arrr - -"
    "d /data/media/movies 0775 - arrr - -"
    "d /data/media/tv 0775 - arrr - -"
  ];

  # Homepage Dashboard Configuration Files
  system.activationScripts.homepageConfig = ''
        mkdir -p /config/homepage

        cat > /config/homepage/services.yaml << 'EOFSERVICES'
    ---
    - Media:
        - Jellyfin:
            icon: jellyfin.png
            href: http://localhost:8096
            description: Media Server
            widget:
              type: jellyfin
              url: http://localhost:8096
              key: YOUR_JELLYFIN_API_KEY_HERE

        - Jellyseerr:
            icon: jellyseerr.png
            href: http://localhost:5055
            description: Request Movies & TV
            widget:
              type: jellyseerr
              url: http://localhost:5055
              key: YOUR_JELLYSEERR_API_KEY_HERE

    - Download Clients:
        - SABnzbd:
            icon: sabnzbd.png
            href: http://localhost:8080
            description: Usenet Downloader
            widget:
              type: sabnzbd
              url: http://localhost:8080
              key: YOUR_SABNZBD_API_KEY_HERE

    - Media Management:
        - Sonarr:
            icon: sonarr.png
            href: http://localhost:8989
            description: TV Shows
            widget:
              type: sonarr
              url: http://localhost:8989
              key: YOUR_SONARR_API_KEY_HERE

        - Radarr:
            icon: radarr.png
            href: http://localhost:7878
            description: Movies
            widget:
              type: radarr
              url: http://localhost:7878
              key: YOUR_RADARR_API_KEY_HERE

        - Prowlarr:
            icon: prowlarr.png
            href: http://localhost:9696
            description: Indexer Manager
            widget:
              type: prowlarr
              url: http://localhost:9696
              key: YOUR_PROWLARR_API_KEY_HERE

        - Bazarr:
            icon: bazarr.png
            href: http://localhost:6767
            description: Subtitles
            widget:
              type: bazarr
              url: http://localhost:6767
              key: YOUR_BAZARR_API_KEY_HERE

    - Tools:
        - FlareSolverr:
            icon: flaresolverr.png
            href: http://localhost:8191
            description: Cloudflare Bypass

        - Portainer:
            icon: portainer.png
            href: http://localhost:9000
            description: Container Management
    EOFSERVICES

        cat > /config/homepage/settings.yaml << 'EOFSETTINGS'
    ---
    title: Media Server Dashboard
    favicon: https://jellyfin.org/images/favicon.ico

    background:
      image: https://images.unsplash.com/photo-1574375927938-d5a98e8ffe85
      blur: sm
      saturate: 50
      brightness: 50
      opacity: 50

    theme: dark
    color: slate

    layout:
      Media:
        style: row
        columns: 2
      Download Clients:
        style: row
        columns: 1
      Media Management:
        style: row
        columns: 4
      Tools:
        style: row
        columns: 2

    headerStyle: boxed
    statusStyle: dot
    hideVersion: true
    EOFSETTINGS

        cat > /config/homepage/widgets.yaml << 'EOFWIDGETS'
    ---
    - logo:
        icon: https://jellyfin.org/images/logo.svg

    - search:
        provider: google
        target: _blank

    - datetime:
        text_size: xl
        format:
          dateStyle: long
          timeStyle: short
          hourCycle: h23

    - resources:
        cpu: true
        memory: true
        disk: /
        cputemp: true
        uptime: true
        units: metric
        refresh: 3000

    - openmeteo:
        label: Sydney
        latitude: -33.87
        longitude: 151.21
        units: metric
        cache: 5
    EOFWIDGETS

        cat > /config/homepage/docker.yaml << 'EOFDOCKER'
    ---
    my-docker:
      socket: /var/run/docker.sock
    EOFDOCKER

        cat > /config/homepage/bookmarks.yaml << 'EOFBOOKMARKS'
    ---
    - Developer:
        - Github:
            - icon: github-light.png
              href: https://github.com/
        - Reddit:
            - icon: reddit.png
              href: https://reddit.com/r/jellyfin

    - Entertainment:
        - YouTube:
            - icon: youtube.png
              href: https://youtube.com
        - Trakt:
            - icon: trakt.png
              href: https://trakt.tv
    EOFBOOKMARKS

        chown -R 1000:995 /config/homepage
        chmod -R 775 /config/homepage
  '';

  virtualisation.oci-containers.containers = {
    jellyfin = {
      image = "jellyfin/jellyfin";
      extraOptions = [
        "--device=/dev/dri:/dev/dri"
        "--group-add=video"
      ];
      ports = [
        "8096:8096"
      ];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
      };
      volumes = [
        "/config/jellyfin:/config"
        "/data/media:/media"
        "/mnt/media:/mnt/media"
      ];
      autoStart = true;
    };

    jellyseerr = {
      image = "ghcr.io/fallenbagel/jellyseerr:latest";
      extraOptions = [
      ];
      ports = [
        "5055:5055"
      ];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
      };
      volumes = [
        "/config/jellyseerr:/app/config"
      ];
      autoStart = true;
    };

    sabVPN = {
      image = "docker.io/binhex/arch-sabnzbdvpn:latest";
      extraOptions = [
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
        "--privileged"
      ];
      ports = [
        "8080:8080"
      ];
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
      extraOptions = [
      ];
      ports = [
        "9696:9696"
      ];
      environment = {
        PUID = "1000";
        PGID = "995";
        UMASK = "002";
        RUN_OPTS = "--ProxyConnection=10.11.12.201:8118";
      };
      volumes = [
        "/config/prowlarr:/config"
      ];
      autoStart = true;
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      extraOptions = [
      ];
      ports = [
        "8191:8191"
      ];
      environment = {
      };
      volumes = [
      ];
      autoStart = true;
    };

    radarr = {
      image = "ghcr.io/hotio/radarr";
      extraOptions = [
      ];
      ports = [
        "7878:7878"
      ];
      environment = {
        PUID = "1000";
        PGID = "995";
        RUN_OPTS = "--ProxyConnection=10.11.12.201:8118";
      };
      volumes = [
        "/config/radarr:/config"
        "/data:/data"
        "/mnt/media:/mnt/media"
      ];
      autoStart = true;
    };

    sonarr = {
      image = "ghcr.io/hotio/sonarr";
      extraOptions = [
      ];
      ports = [
        "8989:8989"
      ];
      environment = {
        PUID = "1000";
        PGID = "995";
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
      extraOptions = [
      ];
      ports = [
        "6767:6767"
      ];
      environment = {
        PUID = "1000";
        PGID = "995";
      };
      volumes = [
        "/config/bazarr:/config"
        "/data:/data"
      ];
      autoStart = true;
    };

    portainer = {
      image = "portainer/portainer-ce:latest";
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

    homepage = {
      image = "ghcr.io/gethomepage/homepage:latest";
      ports = [
        "3000:3000"
      ];
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
  };

  networking.firewall.allowedTCPPorts = [3000 5055 6767 7878 8080 8096 8191 8989 9000 9443 9696];
  networking.firewall.allowedUDPPorts = [9696 8191 8989];
}
