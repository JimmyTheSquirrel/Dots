{ ... }: {
  flake.homeModules.fastfetch = { pkgs, ... }: let
    rawConfig = ''
      {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": {
          "type": "kitty",
          "source": "/path/to/your/image.png",
          "height": 18
        },
        "display": {
          "color": "cyan",
          "separator": ": "
        },
        "modules": [
          {
            "type": "custom",
            "format": "\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Hardware \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e"
          },
          { "type": "host",     "key": "\uf878 Motherboard", "keyColor": "red",    "format": "{name}", "color": "white" },
          { "type": "cpu",      "key": "\uf4bc CPU",         "keyColor": "red",    "color": "white" },
          { "type": "memory",   "key": "\uf538 Memory",      "keyColor": "red",    "color": "white" },
          { "type": "disk",     "key": "\uf0a0 Disk",        "keyColor": "red",    "color": "white" },
          {
            "type": "custom",
            "format": "\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f"
          },
          { "type": "custom", "format": "" },
          {
            "type": "custom",
            "format": "\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Graphics \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e"
          },
          { "type": "gpu",    "key": "\uf200 GPU",     "keyColor": "green", "gpuType": "discrete", "format": "{name}", "color": "white" },
          { "type": "vulkan", "key": "\uf0e7 Driver",  "keyColor": "green", "color": "white" },
          {
            "type": "display",
            "key": "\uf878 Display",
            "keyColor": "green",
            "compactType": "multiline",
            "format": "{width}x{height} @ {refresh-rate}Hz",
            "color": "white"
          },
          {
            "type": "custom",
            "format": "\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f"
          },
          { "type": "custom", "format": "" },
          {
            "type": "custom",
            "format": "\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Software \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e"
          },
          { "type": "os",       "key": "\uf17c OS",       "keyColor": "yellow", "format": "{name} {version} {arch}", "color": "white" },
          { "type": "kernel",   "key": "\uebc6 Kernel",   "keyColor": "yellow", "color": "white" },
          { "type": "packages", "key": "\uf487 Packages", "keyColor": "yellow", "separate": false, "color": "white" },
          { "type": "shell",    "key": "\uf120 Shell",    "keyColor": "yellow", "color": "white" },
          {
            "type": "custom",
            "format": "\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f"
          },
          { "type": "custom", "format": "" },
          {
            "type": "custom",
            "format": "\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Session \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e"
          },
          { "type": "wm",       "key": "\uf5fc WM",       "keyColor": "cyan", "color": "white" },
          { "type": "terminal", "key": "\uf489 Terminal", "keyColor": "cyan", "color": "white" },
          { "type": "uptime",   "key": "\uf017 Uptime",   "keyColor": "cyan", "color": "white" },
          {
            "type": "custom",
            "format": "\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f"
          },
          { "type": "custom", "format": "" },
          {
            "type": "colors",
            "symbol": "circle",
            "paddingLeft": 2,
            "colors": ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
          },
          "break"
        ]
      }
    '';
  in {
    home.packages = [ pkgs.fastfetch ];
    xdg.configFile."fastfetch/config.jsonc".text = rawConfig;
  };
}
