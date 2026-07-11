# CenteredHUD Technical Findings

## 1. Goal

Center the HUD of Palworld (UE 5.1.1) in a 16:9 box on a 5120x1440 (32:9) display, configurable.

## 2. Tooling & Environment

**UE4SS & Deployment:**
- UE4SS: Okaetsu RE-UE4SS experimental-palworld (mandatory for Palworld since patch 0.4.1.5; plain UE4SS crashes)
- Mods live in `ue4ss/Mods/<Name>/Scripts/main.lua` + `enabled.txt` (auto-enables without a mods.txt entry)
- Palworld's `Pal-Windows.pak` is unencrypted—`UnrealPak.exe <pak> -List` dumps all 185k asset paths

**Widget Discovery:**
- This is how widget blueprint names were found offline (e.g. `Pal/Content/Pal/Blueprint/UI/System/WBP_PalHUDLayout.uasset`)
- Examples: compass = `WBP_Ingame_Compass`, stamina = `WBP_Ingame_PlayerStamina_Circle`
- Runtime class names get a `_C` suffix

**Engine.ini Configuration:**
- Palworld only parses custom sections when the full `[Core.System]` Paths block is replicated
- This technique was seen in the ResizeHUD reference mod, which sets `[/script/engine.userinterfacesettings] ApplicationScale`

## 3. Palworld's Runtime UI Architecture

Discovered via custom F8 tree-dump keybind:

- Exactly ONE widget is added to the viewport: `WBP_PalOverallUILayout_C` (outer: `BP_PalGameInstance_C`)
- `WBP_PalHUDLayout_C` (the in-game HUD) lives inside `WBP_PalOverallUILayout_C`'s WidgetTree but reports `Slot=none, GetParent()=none`—it cannot be re-anchored from outside
- Its internal tree structure:
  - `SafeZone` root
  - `CanvasPanel` (in a SafeZoneSlot)
  - TWO full-stretch (0,0)-(1,1) `CanvasPanel`s (in CanvasPanelSlots)
  - Actual HUD element widgets: `WBP_PlayerUI_C` (HP/hotbar/minimap cluster), `WBP_CaptureReticle_C`, `WBP_EnemyMark_C`, `WBP_PalDamageCanvas_OneShotText_C`, multiple `WBP_Ingame_InteractDurability_C` (world-projected, point-anchored), `WBP_PalHUD_InGame_GeneralDispatchEventReciever_C` (full-stretch; hosts dispatched screen effects), `WBP_PalDebugInfo_C`
- The HUD actor (AHUD) is `BP_PalHUD_InGame_C` with a `bShowHUD` bool (known from the cxve Toggle HUD mod)—unrelated to layout

## 4. The Working Technique

Cannot re-anchor the HUD layout itself (no slot), so squeeze the anchors of the two full-stretch canvases using the remap formula:

```
x' = box_min + x * (box_max - box_min)
```

For example, 16:9 on 32:9 display yields anchors (0.25,0)-(0.75,1):
- Element sizes unchanged (pixel offsets untouched)
- Everything edge-anchored moves inward
- SOME world-projected children line up on their own (interact prompts appear geometry-aware). Others do NOT: the stamina arc and the enemy/Pal nameplates (`WBP_EnemyMark_C`) are positioned per frame in raw full-viewport pixels and must go in keep_fullscreen — see the raw-viewport-projection finding below. Floating damage numbers (`WBP_PalDamageCanvas_OneShotText_C`) are the remaining unverified candidate of this family
- Screen-effect overlays that must stay fullscreen get the INVERSE transform `(orig - box_min)/box_width`, allowing anchors outside 0..1 (which UMG permits)—the `keep_fullscreen` config list
- Per-widget cosmetic nudges use `SetRenderTranslation` (works regardless of slot type)—the `offsets` config table
- Enforcement: a 1s `LoopAsync` poll re-finds widgets (the game rebuilds the HUD on world load, new instance IDs each time) and re-applies
- Per-slot original anchors are cached (keyed by slot address) making every pass idempotent and F6 restore exact

## 5. UE4SS Lua Gotchas

- `RegisterKeyBind` fires on a non-game thread: wrap all object access in `ExecuteInGameThread` + pcall
- `LoopAsync(ms, fn)`: fn returning false continues the loop
- `FindAllOf("ClassName_C")` finds live instances only after the class is loaded; returns CDOs too—filter names containing `Default__`
- Property reads through unreflected struct types (e.g. `SafeZoneSlot.LayoutData`) silently return `TrivialObject` userdata that cascades through field accesses and formats as `TrivialObject: 0x...`—crashes `%d`/`%f` formats. `CanvasPanelSlot.LayoutData.Anchors.Minimum.X` reads fine as numbers. Defense: `num()` coercion + `%s` formatting in dumps
- `SetAnchors`/`SetAnchorsInViewport`/`SetRenderTranslation` accept plain Lua tables for FAnchors/FVector2D (`{Minimum={X=..,Y=..},Maximum={..}}`)—verified working
- Hot reload (CTRL+<HotReloadKey>, CTRL mandatory, needs `EnableHotReloadSystem=1`, read at launch) RESETS Lua state but widgets KEEP modified anchors → naive re-capture of "originals" compounds the squeeze (observed: 4 reloads crushed the HUD to a 3%-wide box). Fix: `snapResidue()`—symmetric inset/outset stretch boxes captured as originals are snapped back to (0,1); point anchors exempt. A world reload also self-heals (fresh widgets = true vanilla)
- The dump keybind prints via `print()`: UE4SS prepends `[Lua]` but NOT the mod name—prefix dump lines manually for log grep-ability
- `EnableAutoReloadingLuaMods` exists but is dangerous here (reload can fire while transforms are applied)

## 6. Debug Workflow

UE4SS.log is the only channel (GUI console off). Monitor externally with:

```
tail -f UE4SS.log | grep --line-buffered "\[CenteredHUD\]"
```

The F8 dump evolved:
- v1.1: flat viewport list
- v1.3: tree walk (found the SafeZone)
- v1.5: depth-first nested tree (unambiguous parent/child)

Capture originals lazily, log the first N applications, cap noisy logs with a counter.

## 7. Version History

- **v1.0**: viewport re-anchor attempt (no-op: widget has no slot)
- **v1.2**: canvas child remap one level deep (no-op: root is SafeZone, single child in SafeZoneSlot)
- **v1.3**: SafeZone descent via BFS canvas search + TrivialObject crash fix (SUCCESS: "re-anchored 2 HUD child slot(s)")
- **v1.4**: external config.lua + per-widget offsets + F9 reload
- **v1.5**: keep_fullscreen inverse expansion + snapResidue anti-compounding + DFS dump
- **v1.5.1 finding (support gotcha)**: a user's config.lua OVERRIDES built-in defaults key-by-key. Shipping improved defaults (e.g. new keep_fullscreen entries) does nothing for users whose config already defines that key — they must update their config or delete it.
- **v1.6**: forensic logging — every anchor write logs old -> new values with the slot address
- **v1.8**: offset diagnostics — per-class "matched N live instance(s)" log lines (0 = wrong class name in config), SetRenderTranslation failures surfaced, and a `dump_match` fragment search added to F8 that lists every live widget whose class name contains a configured fragment (with slot/parent info). This is the tool for mapping a visible element to its class name.
- **v1.9**: cold/frost host identified. The frost, damage, and low-health screen vignettes are all drawn by `WBP_IngameDamageVinette_C` (found offline via the pak index: `UI/UserInterface/InGame/DamageEffect/WBP_IngameDamageVinette.uasset` — note Pocketpair's "Vinette" spelling). Added to keep_fullscreen; visually confirmed fullscreen for the low-health vignette.
- **v2.0 — the raw-viewport-projection finding**: the stamina arc (`WBP_Ingame_PlayerStamina_Circle_C`) is repositioned EVERY FRAME by game code that computes the character's screen position in FULL-VIEWPORT pixels and writes it into the widget's canvas slot. Inside a canvas squeezed to the middle 50%, a position computed for screen center (2560 px of 5120) renders at 1280+2560 = 75% of the screen — the arc appeared pinned to the centered box's right edge instead of beside the character. RenderTranslation offsets showed no visible effect on it. The correct fix is keep_fullscreen: the inverse anchor transform restores the widget's full-screen coordinate space, and the game's per-frame pixel positions land exactly where they were computed for. Rule of thumb: statically anchored elements -> centered automatically; per-frame pixel-positioned elements -> `keep_fullscreen`; cosmetic nudges of static elements -> `offsets`.
- **v2.1-v2.3 — the raw-pixel family, mapped by trial**: enemy/Pal nameplates turned out NOT to be hosted by `WBP_EnemyMark_C` (expanding it had no visible effect on them) — they are drawn by `WBP_PalNPCHPGaugeCanvas_C` (pak path `UI/NPCHPGauge/WBP_PalNPCHPGaugeCanvas`, per-enemy children `WBP_PalNPCHPGauge`). Floating damage numbers (`WBP_PalDamageCanvas_OneShotText_C`) confirmed same-family and fixed by keep_fullscreen. Final default keep_fullscreen list: dispatch receiver, damage vignette, stamina arc, enemy mark, damage-number canvas, NPC HP gauge canvas.
- **v2.2 — point-anchor compounding bug (fx path)**: keep-fullscreen expansion of POINT anchors (min == max) compounds across reloads because the symmetric-box residue snap deliberately exempts zero-width anchors. Observed doubling walk: 0 -> -0.5 -> -1.5 -> ... -> -31.5 (stamina arc ~80k px off-screen). Fix: snapResidue now takes the current box and iteratively inverts the expansion mapping (o = t*w + min) until the point value returns to the vanilla [0,1] range — exact recovery for any number of stacked applications.
- **v2.4 — core lists moved out of config**: the keep-fullscreen classes are correctness requirements, and letting config.lua REPLACE the list caused real breakage (a user config froze the list at one entry and silently blocked two later fixes). Core lists now live in main.lua only; config keys (`keep_fullscreen_extra` / `target_widgets_extra`, with the legacy names accepted too) MERGE additions and can never remove core entries. Working lists are rebuilt from the pristine core on every config load.
- **v2.5-v2.7 — frost host found offline; F8 crash lesson**: the cold-frost overlay is NOT `WBP_IngameDamageVinette_C` (that widget handles damage/low-health and was confirmed fullscreen) — it is `WBP_IngameThermometerEff_C` under `InGame/PlayerGauge/`, correlated offline via the `M_UI_ThermometerColdEff` material in the pak index; its sibling `WBP_IngameFlyEff_C` (gliding screen effect) was added alongside. Both live inside `WBP_PlayerUI_C`, which is why no fragment search matched "Cold". Also learned the hard way: a deep widget-tree walk that (a) resolves `LayoutData` on non-CanvasPanelSlot slot types or (b) probes `.WidgetTree` on primitive widgets can crash the game with a native access violation that pcall CANNOT catch — the F8 walk now reads anchors only from CanvasPanelSlots and descends only into `WBP_`/`BP_`-class widgets. The mod also skips blueprint archetypes (full names containing ` /Game/`) in all write paths; the earlier code was writing anchors on templates as well as live instances.
- **v2.8 — per-widget opacity**: config `opacity` table maps widget class -> 0..1, applied via `UWidget::SetRenderOpacity` in the enforcement poll (reset to 1 on restore). Verified on the frost effect at 0.5: the widget-level multiplier composes with the game's own fade animation.
- **TimeSet (sibling dev mod)**: forcing night to test the frost required time control. Third-party admin/chat-command mods are dead on Palworld 1.0 (their chat `RegisterHook` targets no longer exist; the popular Admin Commands mod registers its commands and then fatally errors). Instead, the UE4SS CXX header generator (CTRL+H, writes ~16 MB of headers to `Win64/ue4ss/CXXHeaderDump/`) exposed the real API: `UPalTimeManager::SetGameTime_FixDay(int32 NextHour)` (a UPalWorldSubsystem; live instance class `BP_PalTimeManager_C`), plus `GetCurrentPalWorldTime_Hour()` for read-back. TimeSet binds HOME (night) / END (morning) to it — 50 lines, no hooks. The header dump is the definitive discovery tool when pak names and widget dumps are not enough.
- **v2.9 — the 1 Hz hitch**: user-reported choppiness during play. Cause: the enforcement poll called `FindAllOf` for ~11 widget classes every second, and with `bUseUObjectArrayCache = false` (mandatory for Palworld stability) each call is a full scan of the global object array — the cost grew silently as every keep_fullscreen fix added another scan. Fix: a live-instance cache — scan a class once, keep the pre-filtered references (archetypes/CDOs excluded at cache time, which also removed per-tick GetFullName string builds), and invalidate when any cached instance dies or on a 15-second refresh; empty results are never cached so late-spawning classes are still found. The stray-repair walk was also throttled to every 5th tick (always on restore). Additionally `dev_mode` (config flag, default off) now gates the per-write forensic logs and match-count logs — errors always log. Steady-state tick cost dropped from ~11 full object scans to a handful of validity checks; user confirmed the choppiness gone.
- **v1.7**: construction-race fix. Discovery: when the game rebuilds the HUD (death, fast travel), it briefly parents content widgets (capture reticle, player UI) DIRECTLY to the SafeZone canvas before inserting the two wrapper canvases above them. A poll firing in that window squeezed the content widgets themselves; once the wrappers appeared (and got squeezed too), those widgets were stranded one level down, double-squeezed, and unreachable by F6 restore — seen in-game as a "super centered" HUD, with the disabled state masquerading as the correct centered look. Two-part fix: (1) only direct children of class `CanvasPanel` are ever squeezed; (2) every pass runs a stray-repair walk over descendants, restoring any canvas slot still carrying our squeeze (matched via the originals map, or via exact squeeze signature after a reload wiped the map). keep_fullscreen originals moved to a separate `fxOriginals` map so the repair pass cannot undo the effect-overlay expansion. First v1.7 pass in the field repaired five stranded slots.

## 8. Resolved / Open Items

Resolved (2026-07-11 evening, all user-verified in-game):
- Frost/cold/low-health/damage overlay host: `WBP_IngameDamageVinette_C` (not the dispatch event receiver, which stays in keep_fullscreen as the host of other dispatched effects).
- Stamina arc position: fixed via keep_fullscreen, not offsets (see v2.0 finding).
- Floating damage numbers: `WBP_PalDamageCanvas_OneShotText_C` via keep_fullscreen.
- Enemy/Pal nameplates and HP bars: `WBP_PalNPCHPGaugeCanvas_C` via keep_fullscreen (v2.3, confirmed on live targets).
- Point-anchor compounding across hot reloads: v2.2 unwind fix.
- Slot-address staleness: mitigated by the v1.7 stray-repair pass.

Open:
- Compass offset example in config.lua remains available but unused; no misplaced elements remain after extended play.
