# Rain Effect Overlay

**Module:** `Modules/rain-effect.nix` (Sisyphus only)

GLSL rain-on-glass overlay rendered on the Wayland `bottom` layer — above the wallpaper, below all windows.

## How It Works

- C program using `wlr-layer-shell` (`ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM`) + EGL + OpenGL ES 2
- Empty input region — all mouse/keyboard events pass through
- `exclusive_zone = -1` — doesn't push other surfaces
- Creates one layer surface per monitor (handles dual-monitor setup)
- Shader: BigWings "Heartfelt" drop simulation (CC BY-NC-SA 3.0) + refractive wallpaper sampling
- Binary compiled at Nix build time via `stdenv.mkDerivation` with `wayland-scanner`
- Uses `stb_image` (`pkgs.stb`) to load the wallpaper texture at runtime
- Wallpaper path stored in `$XDG_RUNTIME_DIR/rain-overlay.wallpaper`; SIGUSR1 triggers hot-reload
- Shine texture at `Resources/Rain-Effect/drop-shine.png`

## Usage

```bash
rain-toggle                           # toggle on/off
rain-toggle on / off                  # explicit
rain-toggle wallpaper /path/to/image  # hot-swap wallpaper while running
```

Keybind: `Mod+Shift+R` in Niri

**How wallpaper is found at startup:** `rain-toggle` finds the path via: stored WALLFILE → `jq` from skwd-wall config → most recent file in wallpaper dir. The `~` in jq result is expanded manually (`${walldir/#\~/$HOME}`).

## Shader Architecture (single-pass refractive)

The fragment shader does everything in one pass (no FBO):
1. Compute drop alpha + trail alpha via `Drops()` → single `DropLayer2` layer (rotated slightly)
2. Compute surface normals via forward finite differences on the drop field
3. Offset wallpaper UV by normals (refraction)
4. Apply `wallUV()` for cover/fill aspect ratio correction
5. Composite: refracted wallpaper + subtle cool tint + specular highlight from shine texture

## Rendering Model — Why Parameters Matter

The overlay is alpha-blended over the compositor's wallpaper. Our texture is a separate load of the same wallpaper file — may not perfectly match compositor rendering (gamma, color management):
- High drop alpha + large refraction offset → samples dark wallpaper regions → dark grey blobs (**bad**)
- Correct approach: moderate alpha (~35%), near-zero tint, specular highlight as primary visual cue → glass look (**good**)
- **Never use large refraction offsets** — keep combined `normal_scale * refract_strength ≤ 0.03` (3% screen max)

## Current Shader Parameters (glass-like drops)

- `rain = 0.48` — drop density
- `a = vec2(3., 3.)` in `DropLayer2` — 6×6 grid (changed from original 6×2 to reduce horizontal banding)
- `alpha = dropAlpha * 0.35 + trailAlpha * 0.02` — transparent drops, 65% compositor shows through
- `normal = vec2(nx,ny) * 5.0` — moderate normal scale
- `refractUV = screenUV + normal * 0.006` — tiny lens distortion (max ~1.8% screen offset)
- `water = mix(wall.rgb, vec3(0.92,0.95,1.0), 0.04)` — nearly no tint
- `spec = shine.r * dropAlpha * 0.85` — strong specular, main visual indicator of each drop

## Shader Tuning Knobs

- `rain` (0.0–1.0) — drop density
- `u_time*0.2` — animation speed (lower = slower)
- `a=vec2(X.,Y.)` in `DropLayer2` — grid density
- `rot2(0.07)` in `Drops()` — slight rotation breaks grid alignment
- `normal * N` — normal scale
- `screenUV + normal * M` — refraction strength; keep `N*M < 0.05`
- `dropAlpha * A` — drop opacity
- `mix(wall.rgb, vec3(...), T)` — water tint; keep `T < 0.10` for glass look
- `shine.r * dropAlpha * S` — specular intensity
- `wallUV()` — cover/fill aspect ratio correction

## Known Bugs Fixed

- **Blurry blob bug** — `droplets=S(.3,0.,length(st-vec2(x,y)))` was overwriting sin-based micro-drop computation with a large ~54px blurry circle. Fix: removed those two lines, keeping `sin(y*(1-y)*120)` only.
- **Dark blob bug** — `normal * 14.0 * 0.022 = 0.308` = 30% screen shift sampling dark regions. Fix: reduced to `normal * 5.0 * 0.006 = 0.03`.
- **Frosted glass attempt** — niri does NOT support `blur {}` inside `layer-rule` (only `window-rule`). Gives `unexpected node 'blur'` build error. Shader-based blur (9-tap Gaussian on our texture) blurs the drops not the background — doesn't work either.

## Current State (WIP)

- Drops animated (sliding via `Saw(.85,ti)`) with trails
- Look like transparent glass with specular highlights
- Grid pattern partially addressed — some regularity still visible
- Frosted glass background deferred — not achievable without compositor blur support on layer surfaces
- **Future:** auto-trigger based on weather API (Noctalia has Sydney weather enabled)
