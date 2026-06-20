-- HPS.lua (Optimized)

HPSSavedVars    = HPSSavedVars    or {}
MetersSavedVars = MetersSavedVars or {}

local MIN_REFRESH_RATE     = 0.05
local MAX_REFRESH_RATE     = 0.15
local DEFAULT_REFRESH_RATE = 0.10
local MIN_DAMAGE_METER_INTERVAL = 0.15

local function ClampRefreshRate(value)
    value = tonumber(value) or DEFAULT_REFRESH_RATE
    if value < MIN_REFRESH_RATE then return MIN_REFRESH_RATE end
    if value > MAX_REFRESH_RATE then return MAX_REFRESH_RATE end
    return value
end

local function GetRefreshRate()
    if Meters_GetRefreshRate then
        return ClampRefreshRate(Meters_GetRefreshRate())
    end
    if MetersSavedVars and MetersSavedVars.refreshRate ~= nil then
        return ClampRefreshRate(MetersSavedVars.refreshRate)
    end
    return DEFAULT_REFRESH_RATE
end

local function InitializeRefreshRate()
    local r = GetRefreshRate()
    if MetersSavedVars then MetersSavedVars.refreshRate = r end
    return r
end

-- ─── Frame ────────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "HPSFrame", UIParent)
frame:SetSize(180, 64)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:Hide()

local hpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
hpsText:SetPoint("CENTER", frame, "CENTER", 0, 3)
hpsText:SetText("")
hpsText:SetTextColor(0, 1, 0, 1)
frame.hpsText = hpsText   -- exposed for Meters.lua

local peakText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
peakText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
peakText:SetText("")
peakText:SetTextColor(0.5, 0.5, 0.5, 1)

-- ─── Core read ────────────────────────────────────────────────────────────────
local typeHealing = Enum.DamageMeterType and Enum.DamageMeterType.HealingDone or 2

local function RefreshFromMeter()
    if not UnitAffectingCombat("player") then
        hpsText:SetText("")
        return
    end
    -- Retail: Blizzard's real-time C_DamageMeter -- a live session tied to GAME combat, so the
    -- number stays current right through damage lulls. Classic flavors have no functional
    -- C_DamageMeter (the table can be a non-functional stub), so read HPS from the Details! addon
    -- there instead. Gate on the capability flag, not bare existence.
    if not _G.GSETracker_MetersCapable then
        local hps = _G.GSETracker_DetailsPerSecond and _G.GSETracker_DetailsPerSecond(2)
        if hps then hpsText:SetText(string.format("%.0f", hps)) end
        return
    end
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    if not sessions or #sessions == 0 then return end
    local sid = sessions[#sessions].sessionID
    if not sid then return end
    local ok, info = pcall(C_DamageMeter.GetCombatSessionFromID, sid, typeHealing)
    if not ok or not info or not info.combatSources then return end
    for _, src in ipairs(info.combatSources) do
        if src.isLocalPlayer then
            local hps = tonumber(src.amountPerSecond)
            if hps then
                hpsText:SetText(string.format("%.0f", hps))
            end
            return
        end
    end
end

-- ─── Ticker ───────────────────────────────────────────────────────────────────
local ticker
local currentRefreshRate = InitializeRefreshRate()
local currentTickerInterval = nil
local lastMeterRefresh = 0

local function GetDamageMeterInterval()
    return math.max(currentRefreshRate or GetRefreshRate(), MIN_DAMAGE_METER_INTERVAL)
end

local function RefreshFromMeterProtected(force)
    local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
    local interval = GetDamageMeterInterval()
    if not force and lastMeterRefresh > 0 and (now - lastMeterRefresh) < interval then
        return
    end

    lastMeterRefresh = now
    pcall(RefreshFromMeter)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
    currentTickerInterval = nil
end

local function StartTicker()
    -- Keep DamageMeter reads slower than icon/GCD updates.
    currentRefreshRate = GetRefreshRate()
    local desired = GetDamageMeterInterval()
    if ticker and currentTickerInterval == desired then return end
    StopTicker()
    currentTickerInterval = desired
    ticker = C_Timer.NewTicker(currentTickerInterval, function()
        RefreshFromMeterProtected(true)
    end)
end

function HPS_ApplyRefreshRate(value)
    local rate = ClampRefreshRate(value)
    if MetersSavedVars then MetersSavedVars.refreshRate = rate end
    currentRefreshRate = rate
    if ticker then StopTicker(); StartTicker() end
end

-- ─── Events ───────────────────────────────────────────────────────────────────
function HPS_ControllerEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        currentRefreshRate = InitializeRefreshRate()
        lastMeterRefresh = 0

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Cancel any post-combat fade-out still running and restore full opacity for this fight.
        if GSETracker_CancelFade then GSETracker_CancelFade(frame) end
        hpsText:SetText("")
        peakText:SetText("")
        frame:Show()
        StartTicker()

    elseif event == "PLAYER_REGEN_ENABLED" then
        StopTicker()
        if MetersSavedVars.locked then
            -- Locked: re-read the final value, then smoothly fade the readout out over 3s
            -- (it stays readable while it ramps) and hide. GSETracker_CancelFade restores
            -- alpha if combat restarts before the fade completes.
            C_Timer.After(0.3, function() RefreshFromMeterProtected(true) end)
            if GSETracker_SmoothFadeOut then
                GSETracker_SmoothFadeOut(frame, 3.0, function()
                    if MetersSavedVars.locked and not UnitAffectingCombat("player") then frame:Hide() end
                    -- The fade left the frame at ~0 alpha; restore it (while hidden) so the next
                    -- show -- combat OR the unlocked example preview -- isn't invisible.
                    frame:SetAlpha(1)
                end)
            else
                C_Timer.After(3.0, function()
                    if MetersSavedVars.locked and not UnitAffectingCombat("player") then frame:Hide() end
                end)
            end
        else
            -- Unlocked = placement preview: restore the example value instead of clearing/
            -- hiding (ApplyUnlockedPreviewDisplay sets "6789" + shows it).
            if GSETracker_CancelFade then GSETracker_CancelFade(frame) end
            if Meter_UpdateVisibility then Meter_UpdateVisibility() end
        end

    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if not ticker then
            RefreshFromMeterProtected(false)
        end
    end
end

InitializeRefreshRate()
