{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.helium = {
    pkgs,
    activeUser,
    ...
  }: {
    home-manager.users.${activeUser} = {config, ...}: {
      # Widevine CDM for DRM video (Crunchyroll etc). Helium is ungoogled-chromium
      # based — it has no component updater to fetch the CDM itself, so provide it
      # in the profile using the component-updater layout Chromium scans on Linux,
      # plus the hint file telling it which version directory to load.
      # Note: works for Crunchyroll/YouTube; Netflix additionally requires browser
      # certification (VMP) and will still refuse to play.
      home.file = let
        widevineProfileDir = "${config.home.homeDirectory}/.config/net.imput.helium/WidevineCdm";
      in {
        ".config/net.imput.helium/WidevineCdm/${pkgs.widevine-cdm.version}".source = "${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm";
        # Helium rewrites this hint file at runtime (resolving the symlink to the
        # store path), which makes HM's backup step fail on every later rebuild.
        # force = true: overwrite it instead of backing it up.
        ".config/net.imput.helium/WidevineCdm/latest-component-updated-widevine-cdm" = {
          text = builtins.toJSON {
            Path = "${widevineProfileDir}/${pkgs.widevine-cdm.version}";
          };
          force = true;
        };
      };

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = [ "helium.desktop" ];
          "x-scheme-handler/http" = [ "helium.desktop" ];
          "x-scheme-handler/https" = [ "helium.desktop" ];
        };
      };

      home.packages = [
        (
          let
            helium-pkg = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;
            helium-dark-theme = pkgs.runCommand "helium-dark-theme" {} ''
              mkdir -p $out
              cat > $out/manifest.json <<'EOF'
{
  "manifest_version": 3,
  "name": "Helium Dark",
  "version": "1.0",
  "theme": {
    "colors": {
      "frame": [42, 42, 42],
      "frame_inactive": [36, 36, 36],
      "toolbar": [48, 48, 48],
      "omnibox_background": [38, 38, 38],
      "omnibox_text": [215, 215, 215],
      "tab_text": [230, 230, 230],
      "tab_background_text": [150, 150, 150],
      "bookmark_text": [175, 175, 175],
      "ntp_background": [12, 12, 12]
    }
  }
}
EOF
            '';
            bitwarden-zip = pkgs.fetchzip {
              url = "https://github.com/bitwarden/clients/releases/download/browser-v2026.5.1/dist-chrome-2026.5.1.zip";
              hash = "sha256-xmTQ9HMiGlHtVCkTkzfIVxYsJ3A+zj0VF5S+mTnSIr0=";
              stripRoot = false;
            };
            # Inject the RSA public key into manifest.json so --load-extension assigns the
            # correct extension ID (nngceckbapebfimnlniiiahkandclblb) instead of a random one.
            # Key extracted from the signed CRX and verified against the known extension ID.
            bitwarden-extension = pkgs.runCommand "bitwarden-extension" {nativeBuildInputs = [pkgs.jq];} ''
              cp -rT ${bitwarden-zip} $out
              chmod -R u+w $out
              # Strip source maps — debug files not needed at runtime (saves ~28MB)
              find $out -name "*.map" -delete
              jq '. + {"key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmqKbvreshyXRuN2gikeR1idqR6KL0Di89JZcMyD4bjJRZVmQO7aznSGSALIHzSAUGYocUYBNDOP5QAhImxXyQ1qG8+goXs93v9GzrNJETdVuCEhqBggC4/DFabryJZDiKvZ2Jl0DM7MsWdoybZPwrj70V3aJ/nVNOMkf868scNTMliwitCqqjT5baTANsG0DkZWQExD4lSXzSZHH9MEO8q0iZ7RRlNuGRBAkZgNV8FwZRsPKm/rwQ9dy3VpgLcmLp5GiMt+kAEncqKAkuRYnhVXXBsKqIyYTMjHSLkLnpfFySyOPLBdS617i/PGNiP/MT6Xy6z//v5NozUgaAZ4gJQIDAQAB"}' \
                $out/manifest.json > /tmp/manifest.json
              mv /tmp/manifest.json $out/manifest.json
            '';
          in
            pkgs.symlinkJoin {
              name = "helium";
              paths = [helium-pkg];
              buildInputs = [pkgs.makeWrapper];
              postBuild = ''
                wrapProgram $out/bin/helium \
                  --add-flags "--load-extension=${bitwarden-extension},${helium-dark-theme}" \
                  --add-flags "--disk-cache-size=104857600" \
                  --add-flags "--enable-gpu-rasterization" \
                  --add-flags "--enable-zero-copy" \
                  --add-flags "--no-default-browser-check"
              '';
            }
        )
      ];
    };

    # Chromium enterprise policies - Helium reads from /etc/chromium/policies/managed/
    environment.etc."chromium/policies/managed/helium.json".text = builtins.toJSON {
      # Pin Bitwarden to the toolbar (extension loaded via --load-extension)
      ExtensionSettings = {
        "nngceckbapebfimnlniiiahkandclblb" = {
          toolbar_pin = "force_pinned";
        };
      };
      # Blank new tab page (removes "Add shortcut" widget)
      NewTabPageLocation = "about:blank";
      # Managed bookmark folders (read-only, always present)
      ManagedBookmarks = [
        {toplevel_name = "Bookmarks";}
        {
          name = "Work";
          children = [
            {
              name = "Outlook";
              url = "https://outlook.live.com";
            }
          ];
        }
        {
          name = "Personal";
          children = [
            {
              name = "GitHub";
              url = "https://github.com";
            }
            {
              name = "Reddit";
              url = "https://reddit.com";
            }
            {
              name = "ProtonDB";
              url = "https://www.protondb.com";
            }
            {
              name = "Glance";
              url = "http://asgard:8888";
            }
          ];
        }
      ];
    };
  };
}
