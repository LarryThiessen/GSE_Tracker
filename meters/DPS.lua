-- DPS.lua (Optimized)

DPSSavedVars    = DPSSavedVars    or {}
MetersSavedVars = MetersSavedVars or {}

local MIN_REFRESH_RATE     = 0.02
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

-- Abbreviate large meter values so the readout stays short: 12345 -> "12.34K",
-- 1234567 -> "1.23M", 2.0e9 -> "2.00B". Below 1000 shows the whole number.
-- KEY: live C_DamageMeter values are "secret" (taint-protected) in combat -- we cannot read or
-- COMPARE them in Lua (it throws). Blizzard's own AbbreviateNumbers() is secret-safe (it formats
-- engine-side), which is how lightweight meters abbreviate live combat numbers. Build the config
-- once; fall back to the plain full number (string.format is permitted on secret values) if the
-- API is missing (older Classic).
local abbrevSettings
do
    if CreateAbbreviateConfig and AbbreviateNumbers then
        local ok, cfg = pcall(CreateAbbreviateConfig, {
            { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000,       abbreviation = "K", significandDivisor = 10,       fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
        })
        if ok and cfg then abbrevSettings = { config = cfg } end
    end
end

local function FormatMeterValue(n)
    if n == nil then return "" end
    if abbrevSettings then
        local ok, s = pcall(AbbreviateNumbers, n, abbrevSettings)
        if ok and s then return s end
    end
    local ok, s = pcall(string.format, "%.0f", n)
    if ok then return s end
    return ""
end

-- Exposed so the Edit-Mode example placeholders (Meters.lua / MetersOptions.lua) format their
-- sample numbers with the EXACT same abbreviation as live readouts.
_G.GSETracker_FormatMeterValue = _G.GSETracker_FormatMeterValue or FormatMeterValue

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
    -- number stays current right through damage lulls. Its values are taint-"secret" but
    -- FormatMeterValue uses Blizzard's secret-safe AbbreviateNumbers, so they still abbreviate.
    -- Classic flavors have no functional C_DamageMeter, so read DPS from the Details! addon there.
    if not _G.GSETracker_MetersCapable then
        local dps = _G.GSETracker_DetailsPerSecond and _G.GSETracker_DetailsPerSecond(1)
        if dps then dpsText:SetText(FormatMeterValue(dps)) end
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
                dpsText:SetText(FormatMeterValue(dps))
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
        -- Cancel any post-combat fade-out still running and restore full opacity for this fight.
        if GSETracker_CancelFade then GSETracker_CancelFade(frame) end
        dpsText:SetText("")
        peakText:SetText("")
        frame:Show()
        StartTicker()

    elseif event == "PLAYER_REGEN_ENABLED" then
        StopTicker()
        if MetersSavedVars.locked then
            -- Locked: re-read the final value, then snap the readout out over 0.12s (matches the icon
            -- flow fade-out) and hide. GSETracker_CancelFade restores alpha if combat restarts first.
            C_Timer.After(0.3, function() RefreshFromMeterProtected(true) end)
            if GSETracker_SmoothFadeOut then
                GSETracker_SmoothFadeOut(frame, 0.12, function()
                    if MetersSavedVars.locked and not UnitAffectingCombat("player") then frame:Hide() end
                    -- The fade left the frame at ~0 alpha; restore it (while hidden) so the next
                    -- show -- combat OR the unlocked example preview -- isn't invisible.
                    frame:SetAlpha(1)
                end)
            else
                C_Timer.After(0.12, function()
                    if MetersSavedVars.locked and not UnitAffectingCombat("player") then frame:Hide() end
                end)
            end
        else
            -- Unlocked = placement preview: restore the example value instead of clearing/
            -- hiding (the Meters engine's ApplyUnlockedPreviewDisplay sets "12345" + shows it).
            if GSETracker_CancelFade then GSETracker_CancelFade(frame) end
            if Meter_UpdateVisibility then Meter_UpdateVisibility() end
        end

    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if not ticker then
            RefreshFromMeterProtected(false)
        end
    end
end
