{ ... }:
let
  braveOptions = { lib, hostName, ... }: {
    options.my.brave.profileName = lib.mkOption {
      type = lib.types.str;
      default = hostName;
      defaultText = lib.literalExpression "hostName";
      example = "Kit-Kat";
      description = ''
        Names Brave's profile folder, ~/.config/BraveSoftware/Brave-Browser-<this>.

        It follows the host's name by default. A RENAMED machine sets its old
        name here, so Brave keeps opening the same profile — bookmarks, logins,
        extensions — instead of quietly starting an empty one (Elektra, which
        was Kit-Kat until 2026-10-09, does). A lock left under the old hostname
        is cleared by staleProfileLocks in Modules/Desktop/desktop.nix.
      '';
    };

    options.my.brave.forceDarkMode = lib.mkEnableOption ''
      Chromium's forced dark mode in Brave.

      This is the browser UI *and* a dark filter over sites that ship no dark
      theme of their own. Per-host because it is a taste call — rock leaves it
      to each site, Kit-Kat wants everything dark.
    '';

    options.my.brave.defaultSearchEngine = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "google" "duckduckgo" ]);
      default = null;
      example = "google";
      description = ''
        Replace Brave Search as the default search engine.

        `null` (the default) writes no policy at all and leaves Brave's own
        default in place.

        Implemented as a Chromium enterprise policy in
        `/etc/brave/policies/managed/` — Brave has its own policy directory and
        does *not* read `/etc/chromium/policies/`, which is where
        `Modules/Apps/helium.nix` writes. Verify it took with `brave://policy`.

        One consequence worth knowing before setting this: a policy-managed
        search provider is **locked**. The Settings → Search engine dropdown
        greys out and shows the "managed by your organisation" badge, so the
        only way to change it afterwards is to change this option. That is the
        trade for it being declarative.
      '';
    };
  };

  # {searchTerms} is Chromium's substitution token, not a Nix one — it has to
  # reach the JSON verbatim.
  searchProviders = {
    google = {
      name = "Google";
      keyword = "google.com";
      searchURL = "https://www.google.com/search?q={searchTerms}";
      # output=chrome is what makes the omnibox dropdown populate; without a
      # suggest URL the policy still works but typing feels dead by comparison.
      suggestURL = "https://www.google.com/complete/search?output=chrome&q={searchTerms}";
      iconURL = "https://www.google.com/favicon.ico";
    };
    duckduckgo = {
      name = "DuckDuckGo";
      keyword = "duckduckgo.com";
      searchURL = "https://duckduckgo.com/?q={searchTerms}";
      suggestURL = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";
      iconURL = "https://duckduckgo.com/favicon.ico";
    };
  };
in {
  flake.nixosModules.brave = { lib, config, activeUser, ... }:
  let
    provider =
      if config.my.brave.defaultSearchEngine == null then null
      else searchProviders.${config.my.brave.defaultSearchEngine};
  in {
    imports = [ braveOptions ];

    environment.etc = lib.mkIf (provider != null) {
      "brave/policies/managed/search.json".text = builtins.toJSON {
        DefaultSearchProviderEnabled = true;
        DefaultSearchProviderName = provider.name;
        DefaultSearchProviderKeyword = provider.keyword;
        DefaultSearchProviderSearchURL = provider.searchURL;
        DefaultSearchProviderSuggestURL = provider.suggestURL;
        DefaultSearchProviderIconURL = provider.iconURL;
      };
    };

    home-manager.users.${activeUser} = { config, osConfig, ... }:
    let
      profileDir = "${config.home.homeDirectory}/.config/BraveSoftware/Brave-Browser-${osConfig.my.brave.profileName}";
    in {
      # (A profile lock left under the OLD hostname is cleared by
      # staleProfileLocks in Modules/Desktop/desktop.nix, for every Chromium app.)
      programs.brave = {
        enable = true;

        # Chromium only honours the LAST --enable-features it is given, so every
        # feature has to travel in ONE comma-joined flag. Passing the flag twice
        # (as this did until 2026-10-03) silently dropped the first set.
        #
        # The same rule bites across the wrapper: these args are appended AFTER
        # the nixpkgs brave wrapper's own `--enable-features=AcceleratedVideo-
        # DecodeLinuxGL,AcceleratedVideoEncoder` (plus WaylandWindowDecorations
        # under NIXOS_OZONE_WL — pkgs/by-name/br/brave/make-brave.nix). So any
        # flag emitted here REPLACES that one, and the old always-on
        # `--enable-features=UseOzonePlatform[,…]` was quietly switching off
        # VA-API video decode/encode and Wayland decorations on every launch.
        # Hence: no flag at all unless there is a feature to add, and when there
        # is, the wrapper's set is repeated first. Re-check that list against
        # make-brave.nix when nixpkgs moves.
        #
        # UseOzonePlatform itself is gone: Ozone has been Chromium's only Linux
        # backend for years, so the feature does nothing — `--ozone-platform`
        # below is what selects Wayland.
        commandLineArgs =
          let
            wrapperFeatures = [
              "AcceleratedVideoDecodeLinuxGL"
              "AcceleratedVideoEncoder"
              "WaylandWindowDecorations"
            ];
            ourFeatures =
              # `--force-dark-mode` darkens the browser's own chrome; the
              # WebContentsForceDark feature is what darkens pages that have no
              # dark theme. Without the second, only the frame goes dark and
              # sites stay blinding, which reads as "it didn't work".
              lib.optional osConfig.my.brave.forceDarkMode "WebContentsForceDark";
          in
          [
            "--password-store=basic"
            "--ozone-platform=wayland"
            "--user-data-dir=${profileDir}"
          ]
          ++ lib.optional (ourFeatures != [ ])
            "--enable-features=${lib.concatStringsSep "," (wrapperFeatures ++ ourFeatures)}"
          ++ lib.optional osConfig.my.brave.forceDarkMode "--force-dark-mode";
      };

      # Normal priority on purpose. Modules/Apps/helium.nix sets the same three
      # keys with lib.mkDefault, so wherever both browsers are imported (Elektra)
      # Brave is the default — by priority, not by which module happens to be
      # listed first. (Both used to be normal priority; the lists concatenated
      # in import order, and Brave won only by sitting earlier in the host file.)
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = [ "brave-browser.desktop" ];
          "x-scheme-handler/http" = [ "brave-browser.desktop" ];
          "x-scheme-handler/https" = [ "brave-browser.desktop" ];
        };
      };
    };
  };
}
