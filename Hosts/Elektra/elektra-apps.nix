# Elektra — her application choices. Hers only; see Hosts/Elektra/system.nix.
{ ... }: {
  flake.nixosModules.elektra-apps = { ... }: {
    # system-rebuild, git-sync and nix-gc, so a rebuild can be run sitting at
    # her machine (system-rebuild sees it is ON Elektra and rebuilds in place,
    # from ~/Dots or, without one, github:JimmyTheSquirrel/Dots). Not the
    # Apollo commands or rock's cheats: Modules/Shell/deploy-tools.nix.
    my.deploy-tools.admin = false;

    # Dark browser chrome AND dark pages, not just the frame.
    my.brave.forceDarkMode = true;

    # Her Brave profile was made while this machine was called Kit-Kat, and
    # its folder is named after the host (Brave-Browser-<name>). Keeping the
    # old name means the rename to Elektra leaves her bookmarks, logins and
    # extensions exactly where Brave looks for them — nothing moves.
    my.brave.profileName = "Kit-Kat";

    # Google, not Brave Search. This is an enterprise policy, which means the
    # Settings dropdown locks and shows the "managed" badge — change it here,
    # not in the browser. Verify with brave://policy.
    my.brave.defaultSearchEngine = "google";

    # Sleek + Coral, instead of rock's local Text theme and its matugen
    # wallpaper pipeline. Setting `theme` also strips the two spicetify skwd
    # integrations, the matugen-colors.js extension and spotify-apply-colors
    # — see the option description in Modules/Apps/spicetify.nix.
    my.spicetify = {
      theme = "sleek";
      colorScheme = "Coral";
    };

    # No Millennium — that is rock's Steam ricing. She gets plain upstream
    # Steam: no CSS/JS injector, no extra openssl ABIs, no libXtst relink on
    # every launch (which is what stopped Steam starting at all here).
    my.steam.millennium = false;
  };
}
