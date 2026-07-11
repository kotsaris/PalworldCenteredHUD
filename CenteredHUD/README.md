# CenteredHUD

A Palworld mod that moves all corner-anchored HUD elements toward the screen center on ultrawide and super-ultrawide displays.

## What It Does

Palworld renders its entire in-game HUD on a single full-screen canvas widget (`WBP_PalHUDLayout`). On ultrawide displays (21:9, 32:9, 48:9), corner-anchored HUD elements like the HP bar, hotbar, minimap, and quest tracker sit at the far screen edges.

CenteredHUD narrows the HUD widget's viewport anchor box to a centered rectangular region (default: 16:9 aspect, meaning the middle 2560 pixels of a 5120x1440 display) so all edge-anchored elements move inward. The mod does not scale, clip, or replace any game assets; uninstalling restores vanilla behavior exactly.

The mod only activates on displays wider than a configurable aspect threshold. On 16:9 or narrower screens, the mod does nothing.

## Requirements

- Palworld 1.0 (Steam)
- RE-UE4SS experimental-palworld build (the "UE4SS-Palworld" package)
- Built and tested July 2026

## Installation

1. In Steam, right-click Palworld > Manage > Browse local files. Navigate to `Pal\Binaries\Win64\ue4ss\Mods`.

2. Copy the `CenteredHUD` folder into that directory. Verify this file exists:
   ```
   ...\Win64\ue4ss\Mods\CenteredHUD\Scripts\main.lua
   ```
   (with `enabled.txt` in the parent `CenteredHUD` folder)

3. Launch the game. No mods.txt edit needed—`enabled.txt` auto-enables the mod.

## Hotkeys

| Key | Action |
|-----|--------|
| F6  | Toggle centered / vanilla HUD live in-game |
| F8  | Write the HUD widget tree to UE4SS.log (source of widget class names for `target_widgets`, `keep_fullscreen`, and `offsets` in config.lua) |
| F9  | Re-read config.lua without reloading (config-only changes) |
| CTRL+INS | Hot-reload all Lua mods (requires EnableHotReloadSystem=1 in UE4SS-settings.ini) |

## Configuration

Settings live in `config.lua` in the mod folder. Edit it while the game runs, then press F9 in-game to apply—no restart or hot reload needed. Delete this file to run on built-in defaults.

**Core Settings:**

| Setting | Default | Description |
|---------|---------|-------------|
| `hud_aspect` | `16 / 9` | Aspect ratio of the centered HUD box; larger values create a wider box and a gentler pull toward center (e.g., `2.37` for a 21:9-shaped box) |
| `hud_width_fraction` | `nil` | When set (0–1), overrides `hud_aspect`; specifies box width as a fraction of screen width (e.g., 0.5 on 32:9 equals the 16:9 box, 0.7 is gentler) |
| `hud_height_fraction` | `1.0` | Vertical extent of the box; lower values also pull top/bottom elements inward |
| `min_aspect` | `1.9` | Mod stays inactive below this screen aspect ratio (keeps vanilla 16:9 behavior) |
| `dev_mode` | `false` | Verbose diagnostics: logs every anchor write and per-class match counts to UE4SS.log. Leave off for normal play; flip on (then F9) when investigating a misplaced element |

**Advanced Settings:**

| Setting | Default | Description |
|---------|---------|-------------|
| `target_widgets_extra` | `{}` | ADDITIONS to the mod's built-in list of widget classes to re-anchor (the HUD layout itself is built in); discover class names via the F8 dump |
| `keep_fullscreen_extra` | `{}` | ADDITIONS to the mod's built-in keep-fullscreen list. The core entries — stamina arc, enemy bars, damage numbers, damage/low-health/frost vignettes, dispatch receiver — ship inside the mod and cannot be removed via config. Add a class here if a game patch introduces a new overlay that shows up misplaced |
| `offsets` | `{}` | Per-widget pixel nudges for statically anchored elements only. Table format: `["WidgetClass_C"] = { dx = ..., dy = ... }`. Positive dx moves right, positive dy moves down (UI units, roughly pixels at 1440p). Class names come from the F8 dump. Example: `["WBP_Ingame_Compass_C"] = { dx = 0, dy = 0 }`. Do not use offsets for elements the game moves every frame — put those in `keep_fullscreen` |
| `opacity` | `{}` | Per-widget opacity multipliers, `["WidgetClass_C"] = 0..1` (1 = vanilla). Applied at the widget level, so game-driven fade animations keep working underneath. Example: `["WBP_IngameThermometerEff_C"] = 0.5` softens the cold-frost screen effect |
| `dump_match` | `{ "Stamina", "Compass", ... }` | Class-name fragments the F8 dump searches across all live widgets, for discovering an element's real class name |

## Verify It Works

1. Set your resolution to 5120x1440 in Palworld's settings.
2. Load into a world. The HP bar, hotbar, minimap, and other elements should sit noticeably closer to the center, framing a centered 16:9 region.
3. Press F6 twice to see the HUD jump between vanilla edges and the centered box.
4. Check the log at `Pal\Binaries\Win64\ue4ss\UE4SS.log` for lines prefixed `[CenteredHUD]`. You should see:
   - A startup line: `v1.5 (fx keep-fullscreen) loaded -- hud_aspect=1.7778 (or width_frac=nil), min_aspect=1.9000, poll=1000ms (F6 toggle, F8 dump, F9 config reload)`
   - A config line: `config: config.lua applied, 0 offset entries` (or the count of custom offsets)
   - After loading into the world: `re-anchored 2 HUD child slot(s) under WBP_PalHUDLayout_C`

## Troubleshooting

**No `[CenteredHUD]` lines in UE4SS.log at all**
- The mod folder is in the wrong location, or UE4SS did not load. Verify the folder path matches the Installation section.

**Startup line present, but nothing anchored after loading a world**
- The HUD widget class may have changed in a game patch. Press F8 in-game, open UE4SS.log, and search for a full-screen widget with `HUD` in its name. Add its class name to `TARGET_WIDGETS`.

**`[CenteredHUD] ... SetAnchorsInViewport` error line**
- This indicates an engine call that differs between UE4SS builds. Report the error; it is the one call most likely to vary.

**Some HUD element still at the far edge**
- It lives outside the main layout widget. Discover it via the F8 dump in UE4SS.log, then add its class name to `TARGET_WIDGETS`.

## Compatibility

- Works well with **PalworldUltrawideFix** (FOV fix; uses F5/F7 for its hotkeys, no conflicts)
- Compatible with Engine.ini `ApplicationScale` HUD-size tweaks
- Client-side only; safe on dedicated servers
- **Note for Vortex users:** This mod is installed manually into the game folder. Re-deploying or purging UE4SS from Vortex may remove it. Keep the zip file to reinstall if needed.

## Uninstall

Delete the `CenteredHUD` folder from `Pal\Binaries\Win64\ue4ss\Mods\`.
