{ self, ... }: {
  # SSH public keys, defined once and consumed by every host that grants
  # access. base.nix installs it for the primary user; Hosts/Apollo/system.nix
  # needs the same key without importing all of base, so it lives here.
  flake.lib.sshKeys = {
    jimmy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8xJxKA/gdesYlTECQmBqvqZ0XhgmA08pagXZI95cKl jimmy";
  };

  flake.nixosModules.base = {
    pkgs,
    lib,
    activeUser,
    pkgs-unstable,
    ...
  }: {
    # Every host imports this, Asgard (headless) included, so it carries only
    # what a server needs too. Anything for a machine with a screen — GUI apps,
    # fonts, printing, Bluetooth, dark mode, MIME defaults, the X server — is in
    # Modules/Desktop/desktop.nix.

    # Nix settings
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
    };

    # ── Store hygiene ────────────────────────────────────────────────────────
    # Weekly GC of anything older than two weeks. `--delete-older-than` trims
    # generations from EVERY profile under /nix/var/nix/profiles, not just the
    # default system one: that includes the named system-profiles/ (`sisyphus`,
    # written by `system-rebuild` with `-p`, and read by the GRUB "System
    # Select" menu in Modules/Boot/grub.nix) and the per-user Home Manager
    # profiles. That is fine — the CURRENT generation of a profile is never
    # deleted, so every System Select entry keeps booting; only rollback history
    # older than 14 days goes. The `nix-gc` helper (Modules/Shell/navi.nix) is
    # the manual, more aggressive version of the same thing.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    # Hard-links identical store files on a timer, rather than on every build
    # (nix.settings.auto-optimise-store), which would slow builds down.
    nix.optimise.automatic = true;

    # The journal otherwise grows to 10% of the filesystem (capped at 4 GiB).
    services.journald.extraConfig = "SystemMaxUse=2G";

    nixpkgs.config.allowUnfree = true;

    # Networking
    networking.networkmanager.enable = true;

    # Services
    programs.ssh.startAgent = true;
    programs.ssh.extraConfig = ''
      Host asgard
        HostName 100.126.205.100
        User rock
        SetEnv TERM=xterm-256color
    '';

    # User
    users.users.${activeUser} = {
      isNormalUser = true;
      # mkDefault so a host can give the account a real display name (the SDDM
      # greeter shows this) without needing mkForce.
      description = lib.mkDefault activeUser;
      extraGroups = ["networkmanager" "wheel" "video" "render" "input"];
      openssh.authorizedKeys.keys = [
        self.lib.sshKeys.jimmy
      ];
      shell = pkgs.zsh;
    };

    programs.zsh.enable = true;
    # Home Manager's zsh (Modules/Shell/zsh.nix, enableCompletion = true) already
    # runs compinit from ~/.zshrc. Left on, /etc/zshrc runs it a second time
    # first — pure startup cost, nothing gained.
    programs.zsh.enableGlobalCompInit = false;

    # Common packages
    environment.systemPackages = with pkgs; [
      git
      home-manager
      pkgs-unstable.claude-code
    ];

    # Performance
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
        curl
        icu
      ];
    };

    # `"fs.file-max" = 524288` used to sit here too. Don't bring it back:
    # systemd already raises fs.file-max to its maximum at boot, so pinning a
    # number only ever LOWERED the limit.
    boot.kernel.sysctl = {
      "vm.max_map_count" = 16777216;
    };

    # Do NOT add `kernel.split_lock_mitigate = 0` here expecting it to help the
    # `took a bus_lock trap` spam from Steam/Spotify. Checked against the 6.18
    # source (arch/x86/kernel/cpu/bus_lock.c): these AMD CPUs raise #DB and land
    # in handle_bus_lock(), which in sld_warn state only calls
    # pr_warn_ratelimited(). The sysctl is read exclusively by split_lock_warn()
    # — the #AC split-lock path — so it is a no-op here. Discriminate by the log
    # prefix: "#DB ... bus_lock trap" is unaffected, "#AC ... split_lock trap"
    # is not. Only `split_lock_detect=off` as a kernelParam silences #DB, and
    # the traps cost ~microseconds each, so that is log hygiene, not a fix.

    zramSwap = {
      enable = true;
      memoryMax = 32 * 1024 * 1024 * 1024;
    };
  };
}
