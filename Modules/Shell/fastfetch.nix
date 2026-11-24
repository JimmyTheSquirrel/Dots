# Fastfetch — the system-info panel printed on every new interactive kitty
# shell and again on every `clear` (see Modules/Shell/zsh.nix).
#
# ── This file is UNIVERSAL ────────────────────────────────────────────────
# It defines the panel every host gets by default. Nothing machine-specific
# belongs here. A host that wants a different panel builds its own from the
# pieces exported below as `self.lib.fastfetch`, in its own file — Elektra's
# is Hosts/Elektra/elektra-fastfetch.nix.
#
# `xdg.configFile` is set with lib.mkDefault, so a host module can simply
# assign its own text without needing mkForce.
{ lib, ... }:
let
  ff = rec {
    # Each section is a function of its two colours, so a host can recolour one
    # without restating its rows. `mkConfig`'s `order` picks which ones appear.
    ffSection = {
      hardware = c: b: [
        ''{ "type": "custom", "format": "╭─────────────── {#${c}}▌{#${b}}Hardware{#} ───────────────╮" }''
        ''{ "type": "host",   "key": " 󰍛 Board",   "keyColor": "${c}",   "format": "{name}", "color": "white" }''
        ''{ "type": "cpu",    "key": " 󰻠 CPU",     "keyColor": "${c}",   "color": "white" }''
        ''{ "type": "memory", "key": " 󰑭 RAM",     "keyColor": "${b}",   "color": "white" }''
        ''{ "type": "disk",   "key": " 󰋊 Disk",    "keyColor": "${b}",   "color": "white" }''
        ''{ "type": "custom", "format": "╰─────────────────────────────────────────╯" }''
      ];
      graphics = c: b: [
        ''{ "type": "custom", "format": "╭─────────────── {#${c}}▌{#${b}}Graphics{#} ───────────────╮" }''
        ''{ "type": "gpu",     "key": " 󰢮 GPU",     "keyColor": "${c}", "gpuType": "discrete", "format": "{name}", "color": "white" }''
        ''{ "type": "vulkan",  "key": " 󱨢 Driver",  "keyColor": "${c}", "color": "white" }''
        ''{ "type": "display", "key": " 󰍹 Display", "keyColor": "${b}", "compactType": "multiline", "format": "{width}x{height} @ {refresh-rate}Hz", "color": "white" }''
        ''{ "type": "custom", "format": "╰─────────────────────────────────────────╯" }''
      ];
      software = c: b: [
        ''{ "type": "custom", "format": "╭─────────────── {#${c}}▌{#${b}}Software{#} ───────────────╮" }''
        ''{ "type": "os",       "key": " 󱄅 OS",       "keyColor": "${c}", "format": "{name} {version} {arch}", "color": "white" }''
        ''{ "type": "kernel",   "key": " 󰌽 Kernel",   "keyColor": "${c}", "color": "white" }''
        ''{ "type": "shell",    "key": " 󰞷 Shell",    "keyColor": "${b}", "color": "white" }''
        ''{ "type": "custom", "format": "╰─────────────────────────────────────────╯" }''
      ];
      session = c: b: [
        ''{ "type": "custom", "format": "╭─────────────── {#${c}}▌{#${b}}Session{#} ────────────────╮" }''
        ''{ "type": "wm",       "key": " 󱂬 WM",       "keyColor": "${c}", "color": "white" }''
        ''{ "type": "terminal", "key": " 󰆍 Terminal", "keyColor": "${c}", "color": "white" }''
        ''{ "type": "uptime",   "key": " 󰅐 Uptime",   "keyColor": "${b}", "color": "white" }''
        ''{ "type": "custom", "format": "╰─────────────────────────────────────────╯" }''
      ];
    };

    # The stock palette: each section's normal and bright colour.
    defaultColors = {
      hardware = { c = "red";    b = "bright_red"; };
      graphics = { c = "yellow"; b = "bright_yellow"; };
      software = { c = "green";  b = "bright_green"; };
      session  = { c = "cyan";   b = "bright_cyan"; };
    };

    defaultOrder = [ "hardware" "graphics" "software" "session" ];

    # Build a complete config.jsonc.
    #
    #   logo        path to the image (MUST be git-tracked — a flake's source
    #               is only what git knows about — and have no spaces in the
    #               filename, since a Nix path literal cannot contain one)
    #   logoHeight  height in TERMINAL CELLS, not pixels
    #   logoWidth   width in cells, or null to omit the key
    #   order       which sections appear, in order
    #   colors      per-section { c, b } overrides, merged over defaultColors
    #
    # ⚠ `kitty-direct` hands the file to kitty without fastfetch ever decoding
    # it, so fastfetch CANNOT infer the aspect ratio. With only a height set, a
    # source shaped differently from the stock portrait logo renders at roughly
    # its native pixel size — a 1536x1024 photo came out nearly full-screen on
    # Elektra that way. Set both for any photo. A cell is ~2x taller than wide,
    # so the undistorted width is `2 * (w/h) * height`.
    mkConfig =
      { logo
      , logoHeight ? 14
      , logoWidth ? null
      , order ? defaultOrder
      , colors ? { }
      }:
      let
        col = lib.recursiveUpdate defaultColors colors;
        rows = (lib.concatMap (n: ffSection.${n} col.${n}.c col.${n}.b) order)
          ++ [ ''{ "type": "custom", "format": "" }'' ];
        widthLine = lib.optionalString (logoWidth != null)
          "\n    \"width\": ${toString logoWidth},";
      in ''
        {
          "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
          "logo": {
            "type": "kitty-direct",
            "source": "${logo}",${widthLine}
            "height": ${toString logoHeight},
            "padding": {
              "top": 0,
              "right": 2
            }
          },
          "display": {
            "color": "cyan",
            "separator": ": "
          },
          "modules": [
            ${lib.concatStringsSep ",\n    " rows}
          ]
        }
      '';
  };
in {
  flake.lib.fastfetch = ff;

  flake.nixosModules.fastfetch = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = {
      home.packages = [ pkgs.fastfetch ];
      xdg.configFile."fastfetch/config.jsonc".text = lib.mkDefault (ff.mkConfig {
        logo = ../../Resources/Terminal-Images/terminal-logo-small.png;
      });
    };
  };
}
