{ ... }: {
  flake.homeModules.fastfetch = { pkgs, ... }: let
    rawConfig = ''
      {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": {
          "type": "small",
          "padding": {
            "top": 1,
            "right": 2
          }
        },
        "display": {
          "color": "cyan",
          "separator": ": "
        },
        "modules": [
          {
            "type": "custom",
            "format": "╭───────────────────── Hardware ─────────────────────╮"
          },
          { "type": "host",     "key": "│ 󰍛 Board",   "keyColor": "red",    "format": "{name}", "color": "white" },
          { "type": "cpu",      "key": "│ 󰻠 CPU",     "keyColor": "red",    "color": "white" },
          { "type": "memory",   "key": "│ 󰑭 RAM",     "keyColor": "red",    "color": "white" },
          { "type": "disk",     "key": "│ 󰋊 Disk",    "keyColor": "red",    "color": "white" },
          {
            "type": "custom",
            "format": "╰─────────────────────────────────────────────────────╯"
          },
          {
            "type": "custom",
            "format": "╭───────────────────── Graphics ─────────────────────╮"
          },
          { "type": "gpu",    "key": "│ 󰢮 GPU",     "keyColor": "green", "gpuType": "discrete", "format": "{name}", "color": "white" },
          { "type": "vulkan", "key": "│ 󱨢 Driver",  "keyColor": "green", "color": "white" },
          {
            "type": "display",
            "key": "│ 󰍹 Display",
            "keyColor": "green",
            "compactType": "multiline",
            "format": "{width}x{height} @ {refresh-rate}Hz",
            "color": "white"
          },
          {
            "type": "custom",
            "format": "╰─────────────────────────────────────────────────────╯"
          },
          {
            "type": "custom",
            "format": "╭───────────────────── Software ─────────────────────╮"
          },
          { "type": "os",       "key": "│ 󱄅 OS",       "keyColor": "yellow", "format": "{name} {version} {arch}", "color": "white" },
          { "type": "kernel",   "key": "│ 󰌽 Kernel",   "keyColor": "yellow", "color": "white" },
          { "type": "packages", "key": "│ 󰏖 Packages", "keyColor": "yellow", "separate": false, "color": "white" },
          { "type": "shell",    "key": "│ 󰞷 Shell",    "keyColor": "yellow", "color": "white" },
          {
            "type": "custom",
            "format": "╰─────────────────────────────────────────────────────╯"
          },
          {
            "type": "custom",
            "format": "╭────────────────────── Session ─────────────────────╮"
          },
          { "type": "wm",       "key": "│ 󱂬 WM",       "keyColor": "cyan", "color": "white" },
          { "type": "terminal", "key": "│ 󰆍 Terminal", "keyColor": "cyan", "color": "white" },
          { "type": "uptime",   "key": "│ 󰅐 Uptime",   "keyColor": "cyan", "color": "white" },
          {
            "type": "custom",
            "format": "╰─────────────────────────────────────────────────────╯"
          },
          {
            "type": "colors",
            "symbol": "circle",
            "paddingLeft": 0
          }
        ]
      }
    '';
  in {
    home.packages = [ pkgs.fastfetch ];
    xdg.configFile."fastfetch/config.jsonc".text = rawConfig;
  };
}
