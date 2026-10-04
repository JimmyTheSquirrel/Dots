# Asgard — the headless media server. Intel, systemd-boot, disko-managed disks.
# Hardware: ./_hardware.nix   Disks: ./_disko.nix   Services: Modules/Server/
{ self, ... }: {
  flake.nixosConfigurations.rock-Asgard = self.lib.mkHost {
    activeUser = "rock";
    hostName = "Asgard";
    stateVersion = "25.05";

    modules = [
      ./_hardware.nix
      ./_disko.nix

      # Shared base modules (shell, git, fonts, nix settings, user setup)
      self.nixosModules.base
      self.nixosModules.locale
      self.nixosModules.sops
      self.nixosModules.zsh
      self.nixosModules.git
      self.nixosModules.starship
      self.nixosModules.fastfetch
      self.nixosModules.btop

      # The full media server stack
      self.nixosModules.server

      # Home automation (smart plugs) — web UI on :8123
      self.nixosModules.home-assistant

      # MarsBar — partner-facing dashboard on its own tailnet node (marsbar:1111)
      self.nixosModules.marsbar

      ({ config, activeUser, ... }: {
        # LAN advertises IPv6 (router RA) but has no working v6 upstream.
        # .NET apps (Jellyfin/arrs) try AAAA first and hang 100s per request —
        # broke TMDb metadata/poster fetching. Everything here is IPv4/Tailscale.
        networking.enableIPv6 = false;
        # enp3s0 gets SLAAC addresses from the router before the 'all' sysctl fires,
        # so the interface-specific sysctl stays 0 and the dead IPv6 address persists.
        # Set it explicitly here too. (asgard.lanInterface is declared by the
        # server module — Modules/Server/default.nix.)
        boot.kernel.sysctl."net.ipv6.conf.${config.asgard.lanInterface}.disable_ipv6" = true;
        # Belt-and-suspenders: tell glibc to prefer IPv4 over IPv6.
        # Default table has ::ffff:0:0/96 (IPv4-mapped) at precedence 10, below ::/0 at 40.
        # Raising it to 100 makes getaddrinfo() return IPv4 first — .NET uses this and
        # would otherwise AAAA-first → hang 100s waiting for the dead-routed v6 address.
        networking.getaddrinfo.precedence = {
          "::1/128" = 50;   # loopback — unchanged
          "::/0" = 40;      # native IPv6 — unchanged
          "2002::/16" = 30; # 6to4 — unchanged
          "::/96" = 20;     # IPv4-compat — unchanged
          "::ffff:0:0/96" = 100; # IPv4-mapped — raised above IPv6 to prefer IPv4
        };

        # Boot — systemd-boot (no GRUB on server, single system)
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # Allow remote deploys from Sisyphus (nix-copy-closure needs trusted-users)
        nix.settings.trusted-users = [ activeUser ];

        # SSH for remote management
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = false;
        };

        # Passwordless sudo for server management
        security.sudo.wheelNeedsPassword = false;

        # No initialPassword here any more: rock's password comes from the sops
        # `user-password-hash` secret (Modules/Core/sops.nix) on every host that
        # imports sops. /downloads' tmpfiles rules live with the rest of the data
        # directories in Modules/Server/storage.nix — they were declared twice.
      })
    ];
  };
}
