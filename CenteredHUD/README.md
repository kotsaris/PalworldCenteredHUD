# CenteredHUD

A Palworld mod that moves all corner-anchored HUD elements toward the screen center on ultrawide and super-ultrawide displays.

## What It Does

Palworld renders its entire in-game HUD on a single full-screen canvas widget (`WBP_PalHUDLayout`). On ultrawide displays (21:9, 32:9, 48:9), corner-anchored HUD elements like the HP bar, hotbar, minimap, and quest tracker sit at the far screen edges.

CenteredHUD narrows the HUD widget's viewport anchor box to a centered rectangular region (default: 16:9 aspect, meaning the middle 2560 pixels of a 5120x1440 display) so all edge-anchored elements move inward. The mod does not scale, clip, or replace any game assets; uninstalling restores vanilla behavior exactly.

The mod only activates on displays wider than a configurable aspect threshold. On 16:9 or narrower screens, the mod does nothing.

## Requirements

- Palworld 1.0 (Steam) — last verified on build v1.0.0.100427, the version shown top-left in-game while mods are active
- RE-UE4SS, experimental-palworld build — get it either way:
  - **Via Vortex:** the ["UE4SS (RE-UE4SS Okaetsu Experimental-Palworld)"](https://www.nexusmods.com/palworld/mods/3035) package on Nexus Mods (shows up as "UE4SS Palworld" in the Vortex mod list)
  - **Manually:** `UE4SS-Palworld.zip` from the [official GitHub release](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld)
- Built and tested July 2026

## Installation

**Option A — Vortex** (verified working):

1. Install and enable the "UE4SS Palworld" package from Nexus (see Requirements).
2. In Vortex, click **Install From File**, pick the CenteredHUD release zip, enable it, and deploy.
3. Launch the game — no further setup.

**Option B — Manual:**

1. Install UE4SS by extracting `UE4SS-Palworld.zip` into `Pal\Binaries\Win64` (skip if already installed).

2. In Steam, right-click Palworld > Manage > Browse local files. Navigate to `Pal\Binaries\Win64\ue4ss\Mods`.

3. Copy the `CenteredHUD` folder into that directory. Verify this file exists:
   ```
   ...\Win64\ue4ss\Mods\CenteredHUD\Scripts\main.lua
   ```
   (with `enabled.txt` in the parent `CenteredHUD` folder)

4. Launch the game. No mods.txt edit needed—`enabled.txt` auto-enables the mod.

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

### Complete example config.lua

The shipped file, reproduced in full so you can recreate it after deleting it (or if your copy predates a setting). Uncommented lines are the defaults; commented blocks show the syntax for every advanced setting:

```lua
-- CenteredHUD user config.
-- Edit while the game runs, then press F9 in-game to apply -- no restart, no
-- hot reload needed. Delete this file to run on built-in defaults.
-- Widget class names for the offsets table come from the F8 dump (UE4SS.log).

return {
    -- Width of the centered HUD box, as a width/height aspect ratio.
    -- 16/9 puts the HUD in the middle 2560 px of a 5120x1440 screen.
    -- Larger = wider box = gentler pull (e.g. 2.37 for a 21:9-shaped box).
    hud_aspect = 16 / 9,

    -- Uncomment to override hud_aspect with a direct fraction of screen
    -- width. 0.5 on 32:9 equals the 16:9 box; 0.7 is a gentler pull.
    -- hud_width_fraction = 0.6,

    -- Vertical extent of the box. 1.0 = full height.
    hud_height_fraction = 1.0,

    -- The mod stays inactive below this screen aspect (16:9 = 1.7778).
    min_aspect = 1.9,

    -- Verbose diagnostics: logs every anchor write and per-class match
    -- counts to UE4SS.log. Leave off for normal play; turn on (with F9)
    -- when investigating a misplaced element.
    dev_mode = false,

    -- ADDITIONS to the built-in list of widget classes the mod re-anchors
    -- (the HUD layout itself is built in). Use this when an element stays
    -- at the far screen edge because it lives outside the main layout
    -- widget. Discover class names with the F8 dump. Entries merge with
    -- the core list; they can never remove core entries.
    -- target_widgets_extra = {
    --     "WBP_SomeStrayHudWidget_C",
    -- },

    -- ADDITIONS to the built-in keep-fullscreen list (screen-space effects
    -- like the cold/frost vignette, heat shimmer, damage flashes). The core
    -- entries ship inside the mod and cannot be removed here -- this only
    -- ADDS classes, e.g. if a game patch introduces a new overlay that
    -- shows up misplaced.
    -- keep_fullscreen_extra = {
    --     "WBP_SomeNewOverlay_C",
    -- },

    -- Class-name fragments the F8 dump searches for across all live widgets.
    -- Use this to discover the real class name of an element before adding
    -- it to offsets below.
    dump_match = { "Stamina", "Compass" },

    -- Per-widget pixel nudges applied on top of the centering.
    -- dx moves right (+) / left (-), dy moves down (+) / up (-),
    -- in UI units (roughly pixels at 1440p).
    offsets = {
        -- Compass bar (top center):
        -- ["WBP_Ingame_Compass_C"] = { dx = 0, dy = 0 },

        -- Weapon/equip selector (bottom right). Example values tuned on
        -- 5120x1440 (32:9); other aspects need different dx.
        -- ["WBP_Ingame_WeaponChange_C"]     = { dx = -970, dy = -200 },
        -- ["WBP_Ingame_WeaponChangeList_C"] = { dx = -470, dy = -30 },
    },

    -- Per-widget opacity multipliers (0 = invisible, 1 = vanilla). Applied
    -- as a widget-level multiplier, so game-driven fade animations still
    -- work underneath. Example: soften the cold-frost screen effect.
    opacity = {
        -- ["WBP_IngameThermometerEff_C"] = 0.5,
    },
}
```

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

- Only dependency: RE-UE4SS (experimental-palworld build). No other mods required.
- Registers **no function hooks** — it only polls and writes layout properties on a named set of widgets, so it cannot break other mods' hooks and survives game patches that break hook-based mods
- Works well with **PalworldUltrawideFix** (FOV fix; uses F5/F7 for its hotkeys, no conflicts)
- Compatible with Engine.ini `ApplicationScale` HUD-size tweaks and HUD-visibility toggles (`bShowHUD`)
- Pak-based HUD reskins that restructure the widget tree degrade gracefully: if the expected canvases aren't found, the mod does nothing rather than misplacing elements
- Incompatible by nature with any other mod that repositions the same HUD widgets (a second centering mod)
- Keybinds used: F6, F8, F9 — if another mod binds the same keys, both will fire
- Client-side only; safe on dedicated servers
- **Vortex:** fully supported — install the release zip with **Install From File** alongside the Nexus "UE4SS Palworld" package (see Installation, Option A). Only if you copied the folder in manually while Vortex manages UE4SS: a Vortex purge/redeploy can remove the manual copy, so keep the zip to reinstall.

## Uninstall

Delete the `CenteredHUD` folder from `Pal\Binaries\Win64\ue4ss\Mods\`.
