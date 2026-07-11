-- CenteredHUD for Palworld 1.0 -- Center HUD elements on ultrawide displays.
-- Palworld hosts its entire in-game HUD on one full-screen canvas widget (WBP_PalHUDLayout_C).
-- On a 32:9 monitor, corner-anchored elements sit at far edges. This mod narrows the widget's
-- viewport anchor box to a centered region (default 16:9) so every edge-anchored element moves
-- inward. No scaling, no clipping. The game rebuilds the HUD on world load, so the mod re-asserts
-- anchors on a slow poll (same pattern as UltrawideFix for FOV constraint).
-- Tested on Palworld 1.0 (Steam) with RE-UE4SS experimental-palworld.

--========================================================================
-- CONFIG
--========================================================================

local HUD_ASPECT = 16 / 9              -- 16:9 box; larger values pull elements in less
local HUD_WIDTH_FRACTION = nil          -- nil = use HUD_ASPECT; 0.5 on 32:9 = 16:9 box
local HUD_HEIGHT_FRACTION = 1.0         -- vertical extent of the box
local MIN_ASPECT = 1.9                  -- do nothing unless screen width/height >= this
-- Core widget lists. These are correctness requirements of the mod, not
-- preferences: config.lua can only ADD to them (via *_extra keys, e.g. after
-- a game patch introduces a new overlay), never replace them.
local CORE_TARGET_WIDGETS = { "WBP_PalHUDLayout_C" }  -- widget classes to re-anchor
local FALLBACK_W, FALLBACK_H = 5120, 1440       -- fallback resolution

-- Widget classes that must keep covering the WHOLE screen. They get
-- counter-expanded by the inverse of the squeeze. Two kinds live here:
-- screen-space effect overlays, and widgets the game positions per frame
-- in raw full-viewport pixels (which render misplaced inside a squeezed
-- canvas). All are required for correctness.
local CORE_KEEP_FULLSCREEN = {
    "WBP_PalHUD_InGame_GeneralDispatchEventReciever_C",
    "WBP_IngameDamageVinette_C",           -- damage / low-health / cold-frost vignettes
    "WBP_Ingame_PlayerStamina_Circle_C",   -- stamina arc: game positions it per frame
                                           -- in raw viewport pixels, so it needs the
                                           -- full-screen coordinate space back
    "WBP_EnemyMark_C",                     -- enemy/Pal nameplates: same raw-pixel projection
    "WBP_PalDamageCanvas_OneShotText_C",   -- floating damage numbers: same family
    "WBP_PalNPCHPGaugeCanvas_C",           -- NPC/Pal nameplates + HP bars container
    "WBP_IngameThermometerEff_C",          -- cold-frost / heat screen effect (thermometer)
    "WBP_IngameFlyEff_C",                  -- gliding/flying screen effect, same family
}

-- Working lists: core plus whatever config.lua adds. Rebuilt on every config
-- (re)load from the pristine core lists so removals in config take effect.
local TARGET_WIDGETS = CORE_TARGET_WIDGETS
local KEEP_FULLSCREEN = CORE_KEEP_FULLSCREEN

local function mergedList(core, extraA, extraB)
    local out, seen = {}, {}
    for _, v in ipairs(core) do
        out[#out + 1] = v
        seen[v] = true
    end
    for _, extra in ipairs({ extraA or false, extraB or false }) do
        if type(extra) == "table" then
            for _, v in ipairs(extra) do
                if type(v) == "string" and not seen[v] then
                    out[#out + 1] = v
                    seen[v] = true
                end
            end
        end
    end
    return out
end

-- Class-name fragments the F8 dump searches for across ALL live widgets,
-- printing full name + hosting info. Used to find the real class name of an
-- element before adding it to offsets. Override via config.lua's dump_match.
local DUMP_MATCH = { "Stamina", "Compass", "Vinette", "Effect", "Cold", "Weapon" }
local POLL_MS = 1000                    -- enforcement poll interval in ms
local REASSERT_TICKS = 30               -- every N polls, re-apply (catches widget recycling)
local CACHE_REFRESH_TICKS = 15          -- every N polls, drop the widget cache and re-scan
local REPAIR_TICKS = 5                  -- run the stray-repair walk every N polls

-- Verbose diagnostics (per-write forensic logs, match-count logs). Off for
-- normal play; enable via config.lua's dev_mode = true when investigating.
local DEV_MODE = false
local KEY_TOGGLE = Key.F6               -- toggle centered/vanilla
local KEY_DUMP = Key.F8                 -- dump all in-viewport widgets to log
local KEY_RELOAD_CFG = Key.F9           -- re-read config.lua without a reload

-- Everything above can be overridden from CenteredHUD/config.lua (a Lua file
-- returning a table -- see README). The config file additionally supports
-- per-widget-class pixel nudges via its 'offsets' table.

--========================================================================

local enabled = true
local applied = {}
local tick = 0
local logCount = 0
local logLimit = 150
local fallbackLogged = false
local EPS = 1e-4

-- Original child-slot anchors, keyed by slot address, captured the first time
-- a slot is seen. Never cleared: needed both to keep the remap idempotent and
-- to restore vanilla on toggle. Rebuilt widgets get fresh slot addresses and
-- therefore fresh vanilla originals; a recycled address could briefly misplace
-- one element until the next world load, which we accept.
local originals = {}

-- Per-widget-class visual nudges from config.lua: class name -> {dx, dy}.
local OFFSETS = {}

-- Per-widget-class opacity multipliers from config.lua: class name -> 0..1.
local OPACITY = {}

-- Live-instance cache. FindAllOf is a full scan of the global object array
-- (UE4SS's object cache must stay disabled on Palworld), and the enforcement
-- poll needs instances of ~a dozen classes: scanning every second causes a
-- visible 1 Hz hitch. Widgets live as long as the world, so scan once per
-- class, keep the (pre-filtered) references, and drop a class's list when
-- any entry dies or on the periodic refresh. Empty results are never cached
-- so classes that spawn later are still discovered.
local instanceCache = {}

local function flushInstanceCache()
    instanceCache = {}
end

-- Originals for KEEP_FULLSCREEN slots, kept apart from the wrapper originals:
-- the stray-repair pass restores anything found in `originals`, and the
-- expanded effect overlays must not be caught by it.
local fxOriginals = {}

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[CenteredHUD] " .. (ok and s or tostring(fmt)) .. "\n")
end

local function valid(o)
    return o ~= nil and type(o) == "userdata" and o.IsValid ~= nil and o:IsValid()
end

local function near(a, b) return math.abs(a - b) < EPS end

-- Returns live, non-archetype instances of a class, from cache when every
-- cached entry is still alive, re-scanning otherwise.
local function cachedInstances(cls)
    local entry = instanceCache[cls]
    if entry then
        for i = 1, #entry do
            if not valid(entry[i]) then
                entry = nil
                break
            end
        end
        if entry then return entry end
    end
    local fresh = {}
    local ok, list = pcall(FindAllOf, cls)
    if ok and list then
        for i = 1, #list do
            local w = list[i]
            if valid(w) then
                local okN, fn = pcall(function() return w:GetFullName() end)
                if okN then
                    local nm = tostring(fn)
                    if not nm:find("Default__") and not nm:find(" /Game/", 1, true) then
                        fresh[#fresh + 1] = w
                    end
                end
            end
        end
    end
    if #fresh > 0 then instanceCache[cls] = fresh end
    return fresh
end

-- Squeeze an anchor coordinate into the target box: 0 -> box min, 1 -> box
-- max, 0.5 (screen center) stays put. Applied to a full-stretch child this
-- reproduces exactly what shrinking the parent would have done.
local function remap(x, lo, hi) return lo + x * (hi - lo) end

-- Struct field reads can come back as an opaque 'TrivialObject' userdata on
-- this UE4SS build instead of a Lua number; coerce via tostring.
local function num(v)
    if type(v) == "number" then return v end
    local ok, n = pcall(function() return tonumber(tostring(v)) end)
    if ok then return n end
    return nil
end

local anchorReadDebugged = false

local function readAnchors(slot)
    local ok, a = pcall(function()
        local d = slot.LayoutData.Anchors
        return { minX = num(d.Minimum.X), minY = num(d.Minimum.Y),
                 maxX = num(d.Maximum.X), maxY = num(d.Maximum.Y) }
    end)
    if ok and a and a.minX and a.minY and a.maxX and a.maxY then return a end
    if not anchorReadDebugged then
        anchorReadDebugged = true
        pcall(function()
            local raw = slot.LayoutData.Anchors.Minimum.X
            log("anchor read failed: type=%s tostring=%s", type(raw), tostring(raw))
        end)
    end
    return nil
end

-- The HUD layout's tree root is a SafeZone, not a canvas; the panel holding
-- the actual HUD elements sits below it. Breadth-first search for the first
-- CanvasPanel, descending through panels and nested user widgets alike.
local function findHudCanvas(w)
    local okT, root = pcall(function() return w.WidgetTree.RootWidget end)
    if not okT or not valid(root) then return nil end
    local queue = { root }
    local qi, scanned = 1, 0
    while qi <= #queue and scanned < 64 do
        local node = queue[qi]
        qi = qi + 1
        scanned = scanned + 1
        local cls = ""
        pcall(function() cls = tostring(node:GetClass():GetFName():ToString()) end)
        if cls == "CanvasPanel" then return node end
        local okC, n = pcall(function() return node:GetChildrenCount() end)
        if okC and n and n > 0 then
            for i = 0, n - 1 do
                local okG, ch = pcall(function() return node:GetChildAt(i) end)
                if okG and valid(ch) then queue[#queue + 1] = ch end
            end
        end
        if cls:find("^WBP_") or cls:find("^BP_") then
            pcall(function()
                local sub = node.WidgetTree
                if valid(sub) and valid(sub.RootWidget) then queue[#queue + 1] = sub.RootWidget end
            end)
        end
    end
    return nil
end

local function firstOf(names)
    for _, n in ipairs(names) do
        local ok, o = pcall(FindFirstOf, n)
        if ok and valid(o) then return o end
    end
    return nil
end

local function configFilePath()
    local src = debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*[\\/])") or ""
    return dir .. "../config.lua"
end

-- Parses config.lua and overrides the defaults above. Pure parse: no game
-- objects are touched, so it is safe to call from the main chunk at load.
local function loadUserConfig()
    TARGET_WIDGETS = mergedList(CORE_TARGET_WIDGETS)
    KEEP_FULLSCREEN = mergedList(CORE_KEEP_FULLSCREEN)
    local path = configFilePath()
    local f = io.open(path, "r")
    if not f then return false, "no config.lua, using built-in defaults" end
    f:close()
    local ok, cfg = pcall(dofile, path)
    if not ok then return false, "config.lua error: " .. tostring(cfg) end
    if type(cfg) ~= "table" then return false, "config.lua did not return a table" end
    if type(cfg.hud_aspect) == "number" and cfg.hud_aspect > 0 then HUD_ASPECT = cfg.hud_aspect end
    HUD_WIDTH_FRACTION = (type(cfg.hud_width_fraction) == "number") and cfg.hud_width_fraction or nil
    if type(cfg.hud_height_fraction) == "number" then HUD_HEIGHT_FRACTION = cfg.hud_height_fraction end
    if type(cfg.min_aspect) == "number" then MIN_ASPECT = cfg.min_aspect end
    -- Core lists are mod internals; config entries MERGE into them (both the
    -- legacy key names and the *_extra names are accepted as additions).
    TARGET_WIDGETS = mergedList(CORE_TARGET_WIDGETS, cfg.target_widgets, cfg.target_widgets_extra)
    KEEP_FULLSCREEN = mergedList(CORE_KEEP_FULLSCREEN, cfg.keep_fullscreen, cfg.keep_fullscreen_extra)
    if type(cfg.dump_match) == "table" then DUMP_MATCH = cfg.dump_match end
    OFFSETS = (type(cfg.offsets) == "table") and cfg.offsets or {}
    OPACITY = (type(cfg.opacity) == "table") and cfg.opacity or {}
    if type(cfg.dev_mode) == "boolean" then DEV_MODE = cfg.dev_mode end
    local n = 0
    for _ in pairs(OFFSETS) do n = n + 1 end
    return true, string.format("config.lua applied, %d offset entr%s", n, n == 1 and "y" or "ies")
end

local function screenRes()
    local gus = firstOf({ "PalGameLocalSettings", "GameUserSettings" })
    if not gus then
        if not fallbackLogged then
            log("could not read resolution; using fallback %dx%d", FALLBACK_W, FALLBACK_H)
            fallbackLogged = true
        end
        return FALLBACK_W, FALLBACK_H
    end
    local ok, w, h = pcall(function()
        return tonumber(gus.ResolutionSizeX), tonumber(gus.ResolutionSizeY)
    end)
    if not ok or not w or not h or w <= 0 or h <= 0 then
        if not fallbackLogged then
            log("invalid resolution read; using fallback %dx%d", FALLBACK_W, FALLBACK_H)
            fallbackLogged = true
        end
        return FALLBACK_W, FALLBACK_H
    end
    return w, h
end

local function anchorBox()
    local w, h = screenRes()
    local aspect = w / h
    if aspect < MIN_ASPECT then return nil end
    local frac = HUD_WIDTH_FRACTION or (HUD_ASPECT / aspect)
    if frac >= 1 then return nil end
    if frac < 0.1 then frac = 0.1 end
    local xmin = (1 - frac) / 2
    local ymin = math.max(0, (1 - HUD_HEIGHT_FRACTION) / 2)
    local xmax = 1 - xmin
    local ymax = 1 - ymin
    return { xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax }
end

local function applyAnchors(w, box)
    local ok, fname = pcall(function() return w:GetFullName() end)
    if not ok then return false end
    local fullName = tostring(fname)
    if string.find(fullName, "Default__") then return false end

    local ok1, inVp = pcall(function() return w:IsInViewport() end)
    if ok1 and inVp then
        local anchors = { Minimum = { X = box.xmin, Y = box.ymin }, Maximum = { X = box.xmax, Y = box.ymax } }
        local ok2, err = pcall(function() w:SetAnchorsInViewport(anchors) end)
        if not ok2 then
            if logCount < logLimit then
                log("SetAnchorsInViewport failed on %s: %s", fullName, tostring(err))
                logCount = logCount + 1
            end
            return false
        end
        return true
    end

    local okS, slot = pcall(function() return w.Slot end)
    if okS and valid(slot) then
        local ok3, slotClass = pcall(function() return slot:GetClass():GetFName():ToString() end)
        if ok3 and tostring(slotClass) == "CanvasPanelSlot" then
            local anchors = { Minimum = { X = box.xmin, Y = box.ymin }, Maximum = { X = box.xmax, Y = box.ymax } }
            local ok4, err4 = pcall(function() slot:SetAnchors(anchors) end)
            local ok5, err5 = pcall(function() slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
            if not ok4 or not ok5 then
                if logCount < logLimit then
                    if not ok4 then log("SetAnchors failed on %s: %s", fullName, tostring(err4)) end
                    if not ok5 then log("SetOffsets failed on %s: %s", fullName, tostring(err5)) end
                    logCount = logCount + 1
                end
                return false
            end
            return true
        end
    end
    return false
end

-- Anchors captured as "original" can be residue of our own transforms if a
-- hot reload wiped the originals map (Lua state resets, widgets keep their
-- modified anchors). Our residues are symmetric boxes: inset (squeeze) or
-- outset (keep-fullscreen expansion). Snap those back to full-stretch at
-- capture time so transforms never compound across reloads. Point anchors
-- (crosshair-style, zero width) are never touched.
local function snapResidue(o, box)
    local function sym(lo, hi) return math.abs(lo - (1 - hi)) < 0.02 end
    local r = { minX = o.minX, minY = o.minY, maxX = o.maxX, maxY = o.maxY }
    if ((r.minX > 0 and r.maxX < 1) or (r.minX < 0 and r.maxX > 1))
            and (r.maxX - r.minX) > 0.01 and sym(r.minX, r.maxX) then
        r.minX, r.maxX = 0, 1
    end
    if ((r.minY > 0 and r.maxY < 1) or (r.minY < 0 and r.maxY > 1))
            and (r.maxY - r.minY) > 0.01 and sym(r.minY, r.maxY) then
        r.minY, r.maxY = 0, 1
    end
    -- Point anchors (min == max, zero width) compound differently: each
    -- keep-fullscreen expansion maps o -> (o - min)/w, walking the value
    -- further outside 0..1 every reload (observed: 0 -> -0.5 -> ... -> -31.5).
    -- Vanilla point anchors always lie in [0,1], so unwind our own mapping
    -- until the value is back in range.
    if box then
        local bw = box.xmax - box.xmin
        if bw > 0 and bw < 1 then
            local guard = 0
            while near(r.minX, r.maxX) and (r.minX < -EPS or r.minX > 1 + EPS) and guard < 12 do
                local v = r.minX * bw + box.xmin
                r.minX, r.maxX = v, v
                guard = guard + 1
            end
        end
        local bh = box.ymax - box.ymin
        if bh > 0 and bh < 1 then
            local guard = 0
            while near(r.minY, r.maxY) and (r.minY < -EPS or r.minY > 1 + EPS) and guard < 12 do
                local v = r.minY * bh + box.ymin
                r.minY, r.maxY = v, v
                guard = guard + 1
            end
        end
    end
    return r
end

-- The HUD layout widget itself is hosted with no panel slot (it is effectively
-- the root of Palworld's UI tree), so it cannot be re-anchored from outside.
-- Instead, squeeze the anchors of every canvas child inside its own widget
-- tree. Originals are captured per slot so the operation is idempotent and
-- reversible. Returns how many children were (re)positioned this pass.
local function applyToCanvasChildren(w, box, restore)
    -- Callers pass instances from cachedInstances(), which already excludes
    -- class defaults and blueprint archetypes.
    local root = findHudCanvas(w)
    if not valid(root) then return 0 end
    local okC, n = pcall(function() return root:GetChildrenCount() end)
    if not okC or not n or n <= 0 then return 0 end
    local touched = 0
    local directKeys = {}
    for i = 0, n - 1 do
        local okG, child = pcall(function() return root:GetChildAt(i) end)
        if okG and valid(child) then
            -- Only plain CanvasPanel wrappers get squeezed. During HUD
            -- construction the game briefly parents content widgets (capture
            -- reticle, player UI) directly to this canvas; squeezing those
            -- strands them double-squeezed once the wrappers appear above
            -- them (observed in-game as a "super centered" HUD).
            local childCls = ""
            pcall(function() childCls = tostring(child:GetClass():GetFName():ToString()) end)
            local okS, slot = pcall(function() return child.Slot end)
            if childCls == "CanvasPanel" and okS and valid(slot) then
                local okK, sc = pcall(function() return slot:GetClass():GetFName():ToString() end)
                if okK and tostring(sc) == "CanvasPanelSlot" then
                    local okA, addr = pcall(function() return slot:GetAddress() end)
                    local key = okA and tostring(addr) or nil
                    local cur = readAnchors(slot)
                    if key and cur then
                        directKeys[key] = true
                        if not originals[key] then originals[key] = snapResidue(cur, box) end
                        local o = originals[key]
                        local t
                        if restore then
                            t = o
                        else
                            t = { minX = remap(o.minX, box.xmin, box.xmax),
                                  maxX = remap(o.maxX, box.xmin, box.xmax),
                                  minY = remap(o.minY, box.ymin, box.ymax),
                                  maxY = remap(o.maxY, box.ymin, box.ymax) }
                        end
                        if not (near(cur.minX, t.minX) and near(cur.maxX, t.maxX)
                                and near(cur.minY, t.minY) and near(cur.maxY, t.maxY)) then
                            local okW, errW = pcall(function()
                                slot:SetAnchors({ Minimum = { X = t.minX, Y = t.minY },
                                                  Maximum = { X = t.maxX, Y = t.maxY } })
                            end)
                            if okW then
                                touched = touched + 1
                                -- Forensic: every write logged with old -> new so
                                -- anomalous anchor math is visible in UE4SS.log.
                                if DEV_MODE and logCount < logLimit then
                                    log("write slot %s: (%.3f,%.3f)-(%.3f,%.3f) -> (%.3f,%.3f)-(%.3f,%.3f)%s",
                                        key, cur.minX, cur.minY, cur.maxX, cur.maxY,
                                        t.minX, t.minY, t.maxX, t.maxY, restore and " [restore]" or "")
                                    logCount = logCount + 1
                                end
                            elseif logCount < logLimit then
                                log("child SetAnchors failed: %s", tostring(errW))
                                logCount = logCount + 1
                            end
                        end
                    end
                end
            end
        end
    end
    -- Repair pass: walk the descendants and un-strand any canvas slot we once
    -- squeezed (its key is still in originals) or that carries our exact
    -- squeeze signature after a reload wiped the map, but which is not one of
    -- the current wrappers. Heals widgets caught by construction races.
    -- Throttled: the walk is the most expensive part of a pass, and strays
    -- are rare; restores always run it so F6 leaves nothing behind.
    if not restore and tick % REPAIR_TICKS ~= 0 then return touched end
    local queue, qi, scanned = { root }, 1, 0
    while qi <= #queue and scanned < 128 do
        local node = queue[qi]
        qi = qi + 1
        scanned = scanned + 1
        local okS2, slot2 = pcall(function() return node.Slot end)
        if okS2 and valid(slot2) then
            local okK2, sc2 = pcall(function() return slot2:GetClass():GetFName():ToString() end)
            if okK2 and tostring(sc2) == "CanvasPanelSlot" then
                local okA2, addr2 = pcall(function() return slot2:GetAddress() end)
                local key2 = okA2 and tostring(addr2) or nil
                if key2 and not directKeys[key2] then
                    local cur2 = readAnchors(slot2)
                    if cur2 then
                        local o2 = originals[key2]
                        local repair = false
                        if o2 then
                            if box then
                                -- Only repair if the slot really looks like our
                                -- squeeze of the stored original; an address
                                -- reused by an unrelated slot stays untouched.
                                local t2 = { minX = remap(o2.minX, box.xmin, box.xmax),
                                             maxX = remap(o2.maxX, box.xmin, box.xmax),
                                             minY = remap(o2.minY, box.ymin, box.ymax),
                                             maxY = remap(o2.maxY, box.ymin, box.ymax) }
                                repair = near(cur2.minX, t2.minX) and near(cur2.maxX, t2.maxX)
                                    and near(cur2.minY, t2.minY) and near(cur2.maxY, t2.maxY)
                            else
                                repair = true
                            end
                        elseif box and not (near(box.xmin, 0) and near(box.xmax, 1))
                                and near(cur2.minX, box.xmin) and near(cur2.maxX, box.xmax)
                                and near(cur2.minY, box.ymin) and near(cur2.maxY, box.ymax) then
                            -- Post-reload stray: exact squeeze signature, map lost.
                            o2 = { minX = 0, minY = 0, maxX = 1, maxY = 1 }
                            repair = true
                        end
                        if repair and o2 then
                            if not (near(cur2.minX, o2.minX) and near(cur2.maxX, o2.maxX)
                                    and near(cur2.minY, o2.minY) and near(cur2.maxY, o2.maxY)) then
                                local okW2 = pcall(function()
                                    slot2:SetAnchors({ Minimum = { X = o2.minX, Y = o2.minY },
                                                       Maximum = { X = o2.maxX, Y = o2.maxY } })
                                end)
                                if okW2 and logCount < logLimit then
                                    log("repaired stray slot %s: (%.3f,%.3f)-(%.3f,%.3f) -> (%.3f,%.3f)-(%.3f,%.3f)",
                                        key2, cur2.minX, cur2.minY, cur2.maxX, cur2.maxY,
                                        o2.minX, o2.minY, o2.maxX, o2.maxY)
                                    logCount = logCount + 1
                                end
                            end
                            originals[key2] = nil
                        end
                    end
                end
            end
        end
        local okC2, n2 = pcall(function() return node:GetChildrenCount() end)
        if okC2 and n2 and n2 > 0 then
            for i = 0, n2 - 1 do
                local okG2, ch2 = pcall(function() return node:GetChildAt(i) end)
                if okG2 and valid(ch2) then queue[#queue + 1] = ch2 end
            end
        end
    end
    return touched
end

-- Counter-expands KEEP_FULLSCREEN widgets by the inverse of the squeeze so
-- screen-space effect overlays keep covering the whole display. Works one
-- level deep in a chain of full-stretch parents, which is where these live.
local function applyKeepFullscreen(box, restore)
    local bw = box and (box.xmax - box.xmin) or 1
    local bh = box and (box.ymax - box.ymin) or 1
    if bw <= 0 or bh <= 0 then return end
    for _, clsName in ipairs(KEEP_FULLSCREEN) do
        local list = cachedInstances(clsName)
        if list then
            for i = 1, #list do
                local wd = list[i]
                if valid(wd) then
                    do
                        local okS, slot = pcall(function() return wd.Slot end)
                        if okS and valid(slot) then
                            local okK, sc = pcall(function() return slot:GetClass():GetFName():ToString() end)
                            if okK and tostring(sc) == "CanvasPanelSlot" then
                                local okA, addr = pcall(function() return slot:GetAddress() end)
                                local key = okA and tostring(addr) or nil
                                local cur = readAnchors(slot)
                                if key and cur then
                                    if not fxOriginals[key] then fxOriginals[key] = snapResidue(cur, box) end
                                    local o = fxOriginals[key]
                                    local t
                                    if restore then
                                        t = o
                                    else
                                        t = { minX = (o.minX - box.xmin) / bw, maxX = (o.maxX - box.xmin) / bw,
                                              minY = (o.minY - box.ymin) / bh, maxY = (o.maxY - box.ymin) / bh }
                                    end
                                    if not (near(cur.minX, t.minX) and near(cur.maxX, t.maxX)
                                            and near(cur.minY, t.minY) and near(cur.maxY, t.maxY)) then
                                        local okW = pcall(function()
                                            slot:SetAnchors({ Minimum = { X = t.minX, Y = t.minY },
                                                              Maximum = { X = t.maxX, Y = t.maxY } })
                                        end)
                                        if okW and DEV_MODE and logCount < logLimit then
                                            log("write fx %s (%s): (%.3f,%.3f)-(%.3f,%.3f) -> (%.3f,%.3f)-(%.3f,%.3f)%s",
                                                key, clsName, cur.minX, cur.minY, cur.maxX, cur.maxY,
                                                t.minX, t.minY, t.maxX, t.maxY, restore and " [restore]" or "")
                                            logCount = logCount + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Applies (or zeroes) the config file's per-class nudges as an absolute
-- render translation -- works on any widget regardless of how it is slotted,
-- and re-asserting the same value every pass is harmless.
local offsetMatchLogged = {}

local function applyOffsets(zero)
    for clsName, off in pairs(OFFSETS) do
        local dx = zero and 0 or (tonumber(off.dx) or 0)
        local dy = zero and 0 or (tonumber(off.dy) or 0)
        local matched = 0
        local list = cachedInstances(clsName)
        if list then
            for i = 1, #list do
                local w = list[i]
                if valid(w) then
                    do
                        local okT, errT = pcall(function() w:SetRenderTranslation({ X = dx, Y = dy }) end)
                        if okT then
                            matched = matched + 1
                        elseif logCount < logLimit then
                            log("offset %s: SetRenderTranslation failed: %s", clsName, tostring(errT))
                            logCount = logCount + 1
                        end
                    end
                end
            end
        end
        -- Logged on change; "matched 0 live instance(s)" means the class name
        -- in config.lua does not exist in the running game.
        if DEV_MODE and offsetMatchLogged[clsName] ~= matched and logCount < logLimit then
            log("offset %s: matched %d live instance(s)", clsName, matched)
            logCount = logCount + 1
            offsetMatchLogged[clsName] = matched
        end
    end
end

-- Applies (or resets) per-class opacity multipliers from the config file.
-- RenderOpacity is a widget-level multiplier, so game-driven fades on inner
-- images still work underneath it.
local opacityMatchLogged = {}

local function applyOpacity(reset)
    for clsName, val in pairs(OPACITY) do
        local a = reset and 1 or math.max(0, math.min(1, tonumber(val) or 1))
        local matched = 0
        local list = cachedInstances(clsName)
        if list then
            for i = 1, #list do
                local w = list[i]
                if valid(w) then
                    do
                        local okT = pcall(function() w:SetRenderOpacity(a) end)
                        if okT then matched = matched + 1 end
                    end
                end
            end
        end
        if DEV_MODE and opacityMatchLogged[clsName] ~= matched and logCount < logLimit then
            log("opacity %s: matched %d live instance(s)", clsName, matched)
            logCount = logCount + 1
            opacityMatchLogged[clsName] = matched
        end
    end
end

local function enforce()
    if not enabled then return end
    local box = anchorBox()
    if not box then return end
    tick = tick + 1
    if tick % REASSERT_TICKS == 0 then applied = {} end
    if tick % CACHE_REFRESH_TICKS == 0 then flushInstanceCache() end
    applyOffsets(false)
    applyOpacity(false)
    applyKeepFullscreen(box, false)
    for _, cls in ipairs(TARGET_WIDGETS) do
        local list = cachedInstances(cls)
        if list ~= nil then
            for i = 1, #list do
                local w = list[i]
                if valid(w) then
                    local key
                    local ok2, addr = pcall(function() return w:GetAddress() end)
                    if ok2 and addr then
                        key = tostring(addr)
                    else
                        local ok3, fname = pcall(function() return w:GetFullName() end)
                        if ok3 and fname then key = tostring(fname) end
                    end
                    if key and not applied[key] and applyAnchors(w, box) then
                        applied[key] = true
                        if DEV_MODE and logCount < logLimit then
                            log("anchored %s to (%.3f,%.3f)-(%.3f,%.3f)",
                                key, box.xmin, box.ymin, box.xmax, box.ymax)
                            logCount = logCount + 1
                        end
                    end
                    -- Runs every pass; self-limiting via the originals map.
                    local moved = applyToCanvasChildren(w, box, false)
                    if moved > 0 and logCount < logLimit then
                        log("re-anchored %d HUD child slot(s) under %s", moved, cls)
                        logCount = logCount + 1
                    end
                end
            end
        end
    end
end

local function restoreVanilla()
    local box = { xmin = 0, ymin = 0, xmax = 1, ymax = 1 }
    for _, cls in ipairs(TARGET_WIDGETS) do
        local list = cachedInstances(cls)
        if list ~= nil then
            for i = 1, #list do
                local w = list[i]
                if valid(w) then
                    applyAnchors(w, box)
                    applyToCanvasChildren(w, nil, true)
                end
            end
        end
    end
    applyOffsets(true)
    applyOpacity(true)
    applyKeepFullscreen(nil, true)
    applied = {}
    log("restored vanilla anchors")
end

LoopAsync(POLL_MS, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(enforce)
        if not ok then log("error: %s", tostring(err)) end
    end)
    return false
end)

RegisterKeyBind(KEY_TOGGLE, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            enabled = not enabled
            log("centered HUD %s", enabled and "ENABLED" or "DISABLED (vanilla)")
            if not enabled then
                restoreVanilla()
            else
                applied = {}
                enforce()
            end
        end)
        if not ok then log("toggle error: %s", tostring(err)) end
    end)
end)

-- Structure probe: lists every live widget whose class name contains HUD/Hud/
-- Layout, with its slot class and parent panel class. This is how we learn
-- where Palworld actually hosts the HUD so TARGET_WIDGETS and the anchor
-- path can be corrected without guessing.
RegisterKeyBind(KEY_DUMP, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local ok2, list = pcall(FindAllOf, "UserWidget")
            if not ok2 or list == nil then
                log("widget dump: FindAllOf failed")
                return
            end
            print("---- HUD widget structure dump ----\n")
            local count = 0
            for i = 1, #list do
                local w = list[i]
                if valid(w) then
                    local okN, fname = pcall(function() return w:GetFullName() end)
                    local fullName = okN and tostring(fname) or nil
                    if fullName and not string.find(fullName, "Default__") then
                        local cls = fullName:match("^(%S+)") or ""
                        if cls:find("HUD") or cls:find("Hud") or cls:find("Layout") then
                            local inVp = false
                            pcall(function() inVp = w:IsInViewport() end)
                            local slotCls = "none"
                            pcall(function()
                                local s = w.Slot
                                if valid(s) then slotCls = tostring(s:GetClass():GetFName():ToString()) end
                            end)
                            local parentCls = "none"
                            pcall(function()
                                local p = w:GetParent()
                                if valid(p) then parentCls = tostring(p:GetClass():GetFName():ToString()) end
                            end)
                            count = count + 1
                            print(string.format("%2d  %s | viewport=%s slot=%s parent=%s\n",
                                count, fullName, tostring(inVp), slotCls, parentCls))
                        end
                    end
                end
            end
            print("---- total: " .. tostring(count) .. " HUD/Layout widgets ----\n")
            -- Deep dump: breadth-first walk of each target widget's tree so we
            -- can see where the HUD canvas lives and what anchors its children
            -- have. Anchor values go through %s: struct field reads can come
            -- back as non-numeric userdata on this UE4SS build.
            -- Also walk WBP_PlayerUI_C: it hosts the vignettes and other
            -- overlays, and unidentified screen effects hide in its tree.
            local walkList = mergedList(TARGET_WIDGETS, { "WBP_PlayerUI_C" })
            for _, cls in ipairs(walkList) do
                local okF, insts = pcall(FindAllOf, cls)
                if okF and insts then
                    for j = 1, #insts do
                        local tw = insts[j]
                        if valid(tw) then
                            local okN2, fn2 = pcall(function() return tw:GetFullName() end)
                            local nm = okN2 and tostring(fn2) or "?"
                            if not nm:find("Default__") and not nm:find(" /Game/", 1, true) then
                                local okR, root = pcall(function() return tw.WidgetTree.RootWidget end)
                                if okR and valid(root) then
                                    print(string.format("[CenteredHUD] tree walk of %s:\n", cls))
                                    local stack = { { node = root, depth = 0 } }
                                    local scanned = 0
                                    while #stack > 0 and scanned < 150 do
                                        local e = table.remove(stack)
                                        scanned = scanned + 1
                                        local node = e.node
                                        local nc = "?"
                                        pcall(function() nc = tostring(node:GetClass():GetFName():ToString()) end)
                                        local scName = "none"
                                        local aTxt = ""
                                        pcall(function()
                                            local s = node.Slot
                                            if valid(s) then
                                                scName = tostring(s:GetClass():GetFName():ToString())
                                                -- LayoutData only exists on canvas slots; resolving
                                                -- it against other slot types can crash natively.
                                                if scName == "CanvasPanelSlot" then
                                                    local a = readAnchors(s)
                                                    if a then
                                                        aTxt = string.format(" anchors=(%s,%s)-(%s,%s)",
                                                            tostring(a.minX), tostring(a.minY),
                                                            tostring(a.maxX), tostring(a.maxY))
                                                    end
                                                end
                                            end
                                        end)
                                        print(string.format("[CenteredHUD] %s- %s slot=%s%s\n",
                                            string.rep("  ", e.depth), nc, scName, aTxt))
                                        -- Only blueprint user widgets have a WidgetTree; probing
                                        -- the property on primitive widgets risks a native crash.
                                        if nc:find("^WBP_") or nc:find("^BP_") then
                                            pcall(function()
                                                local sub = node.WidgetTree
                                                if valid(sub) and valid(sub.RootWidget) then
                                                    stack[#stack + 1] = { node = sub.RootWidget, depth = e.depth + 1 }
                                                end
                                            end)
                                        end
                                        -- Depth-first, children pushed in reverse: prints a
                                        -- properly nested tree so parent/child is unambiguous.
                                        local okC, n = pcall(function() return node:GetChildrenCount() end)
                                        if okC and n and n > 0 then
                                            for i = n - 1, 0, -1 do
                                                local okG, ch = pcall(function() return node:GetChildAt(i) end)
                                                if okG and valid(ch) then
                                                    stack[#stack + 1] = { node = ch, depth = e.depth + 1 }
                                                end
                                            end
                                        end
                                    end
                                else
                                    print(string.format("[CenteredHUD] tree %s: no widget tree root\n", cls))
                                end
                            end
                        end
                    end
                end
            end
            -- Name-fragment search across ALL live widgets: prints class,
            -- full path and hosting info for anything matching dump_match.
            -- This is how offset class names in config.lua get verified.
            local okU, allW = pcall(FindAllOf, "UserWidget")
            if okU and allW then
                for _, frag in ipairs(DUMP_MATCH) do
                    print(string.format("[CenteredHUD] widgets matching '%s':\n", frag))
                    local found = 0
                    for i = 1, #allW do
                        local w2 = allW[i]
                        if valid(w2) then
                            local okN3, fn3 = pcall(function() return w2:GetFullName() end)
                            local full = okN3 and tostring(fn3) or ""
                            local cls2 = full:match("^(%S+)") or ""
                            if cls2:find(frag, 1, true) and not full:find("Default__") then
                                local slotCls2, parentCls2 = "none", "none"
                                pcall(function()
                                    local s = w2.Slot
                                    if valid(s) then slotCls2 = tostring(s:GetClass():GetFName():ToString()) end
                                end)
                                pcall(function()
                                    local p = w2:GetParent()
                                    if valid(p) then parentCls2 = tostring(p:GetClass():GetFName():ToString()) end
                                end)
                                found = found + 1
                                print(string.format("[CenteredHUD]   %s | slot=%s parent=%s\n",
                                    full, slotCls2, parentCls2))
                            end
                        end
                    end
                    print(string.format("[CenteredHUD]   %d match(es)\n", found))
                end
            end
        end)
        if not ok then log("dump error: %s", tostring(err)) end
    end)
end)

RegisterKeyBind(KEY_RELOAD_CFG, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local before = OFFSETS
            local _, msg = loadUserConfig()
            flushInstanceCache()
            log("config reload: %s", tostring(msg))
            -- Zero nudges for classes removed from the config, or they stick.
            for cls in pairs(before) do
                if not OFFSETS[cls] then
                    local okF, list = pcall(FindAllOf, cls)
                    if okF and list then
                        for i = 1, #list do
                            local w = list[i]
                            if valid(w) then
                                pcall(function() w:SetRenderTranslation({ X = 0, Y = 0 }) end)
                            end
                        end
                    end
                end
            end
            if enabled then
                applied = {}
                enforce()
            end
        end)
        if not ok then log("config reload error: %s", tostring(err)) end
    end)
end)

local _, cfgMsg = loadUserConfig()
log("v2.9 loaded -- hud_aspect=%.4f (or width_frac=%s), min_aspect=%.4f, poll=%dms, dev_mode=%s (F6 toggle, F8 dump, F9 config reload)",
    HUD_ASPECT, HUD_WIDTH_FRACTION and tostring(HUD_WIDTH_FRACTION) or "nil", MIN_ASPECT, POLL_MS, tostring(DEV_MODE))
log("config: %s", tostring(cfgMsg))
