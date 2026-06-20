-- DPS.lua (Optimized)

DPSSavedVars    = DPSSavedVars    or {}
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
    local r = ClampRefreshRate(MetersSavedVars.refreshRate or DEFAULT_REFRESH_RATE)
    MetersSavedVars.refreshRate = r
    return r
end

-- ─── Frame ────────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "DPSFrame", UIParent)
frame:SetSize(180, 64)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:Hide()

local dpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dpsText:SetPoint("CENTER", frame, "CENTER", 0, 3)
dpsText:SetText("")
dpsText:SetTextColor(1, 0.82, 0, 1)
frame.dpsText = dpsText   -- exposed for Meters.lua

local peakText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
peakText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
peakText:SetText("")
peakText:SetTextColor(0.5, 0.5, 0.5, 1)

-- ─── Core read ────────────────────────────────────────────────────────────────
local function RefreshFromMeter()
    if not UnitAffectingCombat("player") then
        dpsText:SetText("")
        return
    end
    -- Retail: Blizzard's real-time C_DamageMeter -- a live session tied to GAME combat, so the
    -- number stays current right through damage lulls. Classic flavors have no functional
    -- C_DamageMeter (the table can be a non-functional stub), so read DPS from the Details! addon
    -- there instead. Gate on the capability flag, not bare existence.
    if not _G.GSETracker_MetersCapable then
        local dps = _G.GSETracker_DetailsPerSecond and _G.GSETracker_DetailsPerSecond(1)
        if dps then dpsText:SetText(string.format("%.0f", dps)) end
        return
    end
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    if not sessions or #sessions == 0 then return end
    local sid = sessions[#sessions].sessionID
    if not sid then return end
    local ok, info = pcall(C_DamageMeter.GetCombatSessionFromID, sid, 0)
    if not ok or not info or not info.combatSources then return end
    for _, src in ipairs(info.combatSources) do
        if src.isLocalPlayer then
            local dps = tonumber(src.amountPerSecond)
            if dps then
                dpsText:SetText(string.format("%.0f", dps))
            end
            return
        end
    end
end

-- ─── Ticker ───────────────────────────────────────────────────────────────────
local ticker
local currentRefreshRate = GetRefreshRate()
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

function DPS_ApplyRefreshRate(value)
    local newRate = ClampRefreshRate(value)
    MetersSavedVars.refreshRate = newRate
    currentRefreshRate = newRate
    if ticker then StopTicker(); StartTicker() end
end

-- ─── Events ───────────────────────────────────────────────────────────────────
function DPS_ControllerEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        currentRefreshRate = GetRefreshRate()
        lastMeterRefresh = 0

    elseif event == "PLAYER_REGEN_DISABLED" then
        dpsText:SetText("")
        peakText:SetText("")
        frame:Show()
        StartTicker()

    elseif event == "PLAYER_REGEN_ENABLED" then
        StopTicker()
        if MetersSavedVars.locked then
            -- Locked: clear the live value and hide shortly after combat (idle UI).
            C_Timer.After(0.3, function() RefreshFromMeterProtected(true) end)
            dpsText:SetText("")
            C_Timer.After(3.0, function()
                if MetersSavedVars.locked and not UnitAffectingCombat("player") then frame:Hide() end
            end)
        else
            -- Unlocked = placement preview: restore the example value instead of clearing/
            -- hiding (the Meters engine's ApplyUnlockedPreviewDisplay sets "12345" + shows it).
            if Meter_UpdateVisibility then Meter_UpdateVisibility() end
        end

    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if not ticker then
            RefreshFromMeterProtected(false)
        end
    end
end
