-- TimeSet for Palworld -- jump the world clock to a chosen hour on a keypress.
-- Built as a development aid for CenteredHUD (forcing night to test the
-- cold-frost overlay), but works as a standalone convenience mod.
--
-- Uses UPalTimeManager::SetGameTime_FixDay(NextHour), discovered via the
-- UE4SS CXX header dump of Palworld 1.0. No chat hooks, no obfuscation.
--
-- Keys: HOME = jump to NIGHT_HOUR, END = jump to MORNING_HOUR.

local NIGHT_HOUR = 23  -- deep night immediately; 22 still needs a minute of dusk
local MORNING_HOUR = 9

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[TimeSet] " .. (ok and s or tostring(fmt)) .. "\n")
end

local function valid(o)
    return o ~= nil and type(o) == "userdata" and o.IsValid ~= nil and o:IsValid()
end

local function timeManager()
    for _, n in ipairs({ "BP_PalTimeManager_C", "PalTimeManager" }) do
        local ok, o = pcall(FindFirstOf, n)
        if ok and valid(o) then return o end
    end
    return nil
end

local function setHour(hour)
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local tm = timeManager()
            if not tm then
                log("no time manager found (not in a world?)")
                return
            end
            local before = "?"
            pcall(function() before = tostring(tm:GetCurrentPalWorldTime_Hour()) end)
            tm:SetGameTime_FixDay(hour)
            local after = "?"
            pcall(function() after = tostring(tm:GetCurrentPalWorldTime_Hour()) end)
            log("hour %s -> %s (requested %d:00)", before, after, hour)
        end)
        if not ok then log("error: %s", tostring(err)) end
    end)
end

RegisterKeyBind(Key.HOME, function() setHour(NIGHT_HOUR) end)
RegisterKeyBind(Key.END, function() setHour(MORNING_HOUR) end)

log("loaded -- HOME = %d:00 (night), END = %d:00 (morning)", NIGHT_HOUR, MORNING_HOUR)
