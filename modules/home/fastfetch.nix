{ ... }: {
  flake.homeModules.fastfetch = { pkgs, ... }: let
    rawConfig = ''
      {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": {
          "type": "kitty-direct",
          "source": "/home/rock/Dots/assets/terminal-logo-small.png",
          "height": 14,
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
          { "type": "custom", "format": "╭─────────────── {#red}▌{#bright_red}Hardware{#} ───────────────╮" },
          { "type": "host",   "key": " 󰍛 Board",   "keyColor": "red",   "format": "{name}", "color": "white" },
          { "type": "cpu",    "key": " 󰻠 CPU",     "keyColor": "red",   "color": "white" },
          { "type": "memory", "key": " 󰑭 RAM",     "keyColor": "bright_red",   "color": "white" },
          { "type": "disk",   "key": " 󰋊 Disk",    "keyColor": "bright_red",   "color": "white" },
          { "type": "custom", "format": "╰─────────────────────────────────────────╯" },
          { "type": "custom", "format": "╭─────────────── {#yellow}▌{#bright_yellow}Graphics{#} ───────────────╮" },
          { "type": "gpu",     "key": " 󰢮 GPU",     "keyColor": "yellow", "gpuType": "discrete", "format": "{name}", "color": "white" },
          { "type": "vulkan",  "key": " 󱨢 Driver",  "keyColor": "yellow", "color": "white" },
          { "type": "display", "key": " 󰍹 Display", "keyColor": "bright_yellow", "compactType": "multiline", "format": "{width}x{height} @ {refresh-rate}Hz", "color": "white" },
          { "type": "custom", "format": "╰─────────────────────────────────────────╯" },
          { "type": "custom", "format": "╭─────────────── {#green}▌{#bright_green}Software{#} ───────────────╮" },
          { "type": "os",       "key": " 󱄅 OS",       "keyColor": "green", "format": "{name} {version} {arch}", "color": "white" },
          { "type": "kernel",   "key": " 󰌽 Kernel",   "keyColor": "green", "color": "white" },
          { "type": "shell",    "key": " 󰞷 Shell",    "keyColor": "bright_green", "color": "white" },
          { "type": "custom", "format": "╰─────────────────────────────────────────╯" },
          { "type": "custom", "format": "╭─────────────── {#cyan}▌{#bright_cyan}Session{#} ────────────────╮" },
          { "type": "wm",       "key": " 󱂬 WM",       "keyColor": "cyan", "color": "white" },
          { "type": "terminal", "key": " 󰆍 Terminal", "keyColor": "cyan", "color": "white" },
          { "type": "uptime",   "key": " 󰅐 Uptime",   "keyColor": "bright_cyan", "color": "white" },
          { "type": "custom", "format": "╰─────────────────────────────────────────╯" },
          { "type": "custom", "format": "" }
        ]
      }
    '';
  in {
    home.packages = [ pkgs.fastfetch ];
    xdg.configFile."fastfetch/config.jsonc".text = rawConfig;
  };
}
