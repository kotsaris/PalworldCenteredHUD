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

    -- Widget classes that must keep covering the WHOLE screen instead of
    -- being centered with the rest of the HUD -- screen-space effects like
    -- the cold/frost vignette, heat shimmer, damage flashes. The default
    -- entry hosts Palworld's dispatched screen effects.
    -- NOTE: widgets the game repositions every frame in raw viewport pixels
    -- (like the stamina arc) also belong here, NOT in offsets -- they need
    -- their full-screen coordinate space back, not a nudge.
    keep_fullscreen = {
        "WBP_PalHUD_InGame_GeneralDispatchEventReciever_C",
        "WBP_IngameDamageVinette_C",
        "WBP_Ingame_PlayerStamina_Circle_C",
        "WBP_EnemyMark_C",
        "WBP_PalDamageCanvas_OneShotText_C",
        "WBP_PalNPCHPGaugeCanvas_C",
    },

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
    },
}
