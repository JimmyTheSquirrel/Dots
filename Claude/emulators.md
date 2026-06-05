# Emulators — RPCS3 & Ryubing

**Module:** `Modules/rpcs3.nix` (all three systems)

## Installed Emulators

- **`rpcs3`** — PS3 emulator (SSX 2012 and other PS3 games)
- **`ryubing`** — Nintendo Switch emulator (community Ryujinx fork; official Ryujinx was shut down Oct 2024)

## RPCS3 Config

Seeded on first activation via home-manager activation script at `~/.config/rpcs3/config.yml`.
Key settings: Vulkan renderer, LLVM recompilers, Cubeb audio.
File is only written if it doesn't exist — RPCS3 UI changes survive rebuilds.

## Preparing a PS3 Game (Encrypted ISO + .dkey)

```bash
nix-shell -p ps3iso-utils --run "bash"
extractps3iso /path/to/game.iso /path/to/output/
```

`extractps3iso` can read encrypted ISOs without needing the `.dkey` in most cases. The `.dkey` is for `patchps3iso` which uses a different (CFW) key format. After extraction: **File → Add Games** in RPCS3.

**Firmware:** PS3 firmware is bundled in the game ISO at `PS3_UPDATE/PS3UPDAT.PUP`. Install via **File → Install Firmware** in RPCS3 before launching any game.

## DualSense with RPCS3

- Config → Pads → Handler: `DualSense`, Device: `DualSense Pad #1`
- Connect via Bluetooth before opening the Pads dialog, hit Refresh if needed
- The controller daemon (`controller.nix`) skips real Bluetooth devices so it won't conflict with RPCS3

## Resolution (SSX 2012)

SSX natively runs at 720p on PS3. Use **Resolution Scale** (Config → GPU) at 150–200% to upscale internal rendering — much sharper than native PS3 output. The `Resolution` setting (output res) is ignored by games that don't support it.

## Bluetooth Auto-Connect

Configured in `niri.nix`:
- `hardware.bluetooth.powerOnBoot = true`
- `hardware.bluetooth.settings.Policy.AutoEnable = "true"`
- `services.blueman.enable = true`
- After pairing, run `bluetoothctl trust <MAC>` once — controller reconnects automatically on PS button press
