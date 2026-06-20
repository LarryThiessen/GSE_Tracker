-- Modules/Meters/AHLightUsage.lua

local FADE_DELAY = 3   -- seconds the SBAssist % lingers after combat (matches DPS/HPS' 3s hold)
local AHLIGHT_MATCH_WINDOW = 0.35
local DEFAULT_REFRESH_RATE = 0.10
local MIN_REFRESH_RATE = 0.05
local MAX_REFRESH_RATE = 0.15

MetersSavedVars = MetersSavedVars or {}

if MetersSavedVars.showAHLightUsage == nil and MetersSavedVars.showSBAUsage ~= nil then
    MetersSavedVars.showAHLightUsage = MetersSavedVars.showSBAUsage
end


local function ClampRefreshRate(value)
    value = tonumber(value) or DEFAULT_REFRESH_RATE

    if value < MIN_REFRESH_RATE then
        value = MIN_REFRESH_RATE
    elseif value > MAX_REFRESH_RATE then
        value = MAX_REFRESH_RATE
    end

    return value
end

local function GetRefreshRate()
    if Meters_GetRefreshRate then
        return Meters_GetRefreshRate()
    end

    MetersSavedVars.refreshRate = ClampRefreshRate(MetersSavedVars.refreshRate)
    return MetersSavedVars.refreshRate
end

-- ─── Frame ────────────────────────────────────────────────
local frame = CreateFrame("Frame", "AHLightUsageFrame", UIParent)
frame:SetSize(220, 28)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:Hide()

frame.ahLightUsageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.ahLightUsageText:SetAllPoints()
frame.ahLightUsageText:SetJustifyH("CENTER")
frame.ahLightUsageText:SetJustifyV("MIDDLE")
frame.ahLightUsageText:SetText("")

frame.isPreviewMode = false
frame.elapsedSinceUpdate = 0
frame.updateInterval = GetRefreshRate()

-- ─── State ────────────────────────────────────────────────
local inCombat = false
local totalCastsThisCombat = 0
local ahLightCastsThisCombat = 0
local lastCombatPercent = 0
local lastCombatAHLight = 0
local lastCombatTotal = 0
local fadeDeadline = nil

local seenCastGUIDs = {}
local lastAHLightEventTime = 0
local UpdateAHLightUsagePolling

-- ─── Helpers ──────────────────────────────────────────────
local function WipeTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function IsEnabled()
    return MetersSavedVars.showAHLightUsage ~= false
end

local function CancelFade()
    fadeDeadline = nil
    -- Pull the frame out of the alpha-fade manager before restoring full opacity, or a
    -- still-running UIFrameFadeOut would keep ramping it back down past our SetAlpha(1).
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
    frame:SetAlpha(1)
    if UpdateAHLightUsagePolling then UpdateAHLightUsagePolling() end
end

local function StartFadeTimer()
    fadeDeadline = GetTime() + FADE_DELAY
    -- Smoothly ramp the SBAssist % out over the linger window instead of holding full then
    -- snapping off; the OnUpdate hides it once the deadline (= end of the ramp) is reached.
    frame:SetAlpha(1)
    if UIFrameFadeOut then UIFrameFadeOut(frame, FADE_DELAY, 1, 0) end
    if UpdateAHLightUsagePolling then UpdateAHLightUsagePolling() end
end

local function ResetCombatCounters()
    totalCastsThisCombat = 0
    ahLightCastsThisCombat = 0
    lastAHLightEventTime = 0
    WipeTable(seenCastGUIDs)
end

local function GetCurrentPercent()
    if totalCastsThisCombat <= 0 or ahLightCastsThisCombat <= 0 then
        return 0
    end

    return (ahLightCastsThisCombat / totalCastsThisCombat) * 100
end

local function FormatDisplay(percent, ahLightCount, totalCount)
    return string.format("%.1f%% (%d/%d)", percent, ahLightCount, totalCount)
end

local function ClearText()
    frame.ahLightUsageText:SetText("")
end

local function GetLiveText()
    if inCombat and totalCastsThisCombat > 0 then
        return FormatDisplay(GetCurrentPercent(), ahLightCastsThisCombat, totalCastsThisCombat)
    end

    if (not inCombat) and lastCombatTotal > 0 then
        return FormatDisplay(lastCombatPercent, lastCombatAHLight, lastCombatTotal)
    end

    return ""
end

local function RefreshTextOnly()
    if frame.isPreviewMode then
        if IsEnabled() then
            frame.ahLightUsageText:SetText("24% (11/47)")
        else
            ClearText()
        end
        return
    end

    if not IsEnabled() then
        ClearText()
        return
    end

    frame.ahLightUsageText:SetText(GetLiveText())
end

local function HandleAHLightCastEvent()
    if not inCombat or frame.isPreviewMode or not IsEnabled() then
        return
    end

    lastAHLightEventTime = GetTimePreciseSec()
end

local function HandleUnitSpellcastSucceeded(unitTarget, castGUID)
    if not inCombat or frame.isPreviewMode or not IsEnabled() then
        return
    end

    if unitTarget ~= "player" then
        return
    end

    if castGUID and seenCastGUIDs[castGUID] then
        return
    end

    if castGUID then
        seenCastGUIDs[castGUID] = true
    end

    totalCastsThisCombat = totalCastsThisCombat + 1

    local now = GetTimePreciseSec()
    if lastAHLightEventTime > 0 and (now - lastAHLightEventTime) <= AHLIGHT_MATCH_WINDOW then
        ahLightCastsThisCombat = ahLightCastsThisCombat + 1
        lastAHLightEventTime = 0
    end

    RefreshTextOnly()
end

-- ─── Public API ───────────────────────────────────────────
function AHLightUsage_Clear()
    CancelFade()
    ClearText()
end

function AHLightUsage_SetPreview(enabled)
    local wasPreview = frame.isPreviewMode
    frame.isPreviewMode = enabled and true or false
    frame.elapsedSinceUpdate = 0

    if frame.isPreviewMode then
        CancelFade()
        RefreshTextOnly()
        if IsEnabled() then
            frame:Show()
            frame:SetAlpha(1)
        else
            frame:Hide()
        end
    else
        if wasPreview then
            CancelFade()
        end
        RefreshTextOnly()
        if not IsEnabled() then
            frame:Hide()
        end
    end
    if UpdateAHLightUsagePolling then UpdateAHLightUsagePolling() end
end

function AHLightUsage_ApplyFont(font, size, flags)
    if frame and frame.ahLightUsageText then
        frame.ahLightUsageText:SetFont(font, size, flags or "OUTLINE")
    end
end

function AHLightUsage_ApplyRefreshRate(value)
    local rate = ClampRefreshRate(value)
    MetersSavedVars.refreshRate = rate
    frame.updateInterval = rate
    frame.elapsedSinceUpdate = 0
    if UpdateAHLightUsagePolling then UpdateAHLightUsagePolling() end
end

function AHLightUsage_Refresh()
    RefreshTextOnly()
end

function AHLightUsage_ShouldShow()
    if not IsEnabled() then
        return false
    end

    if frame.isPreviewMode then
        return true
    end

    if inCombat then
        return totalCastsThisCombat > 0
    end

    if lastCombatTotal > 0 then
        if fadeDeadline and GetTime() < fadeDeadline then
            return true
        end
    end

    return false
end

-- ─── Events ───────────────────────────────────────────────
local function ShouldPollAHLightUsage()
    if not frame or frame.isPreviewMode or not IsEnabled() then
        return false
    end
    return inCombat or fadeDeadline ~= nil
end

local function AHLightUsage_OnUpdate(_, elapsed)
    frame.elapsedSinceUpdate = (frame.elapsedSinceUpdate or 0) + (elapsed or 0)

    if frame.elapsedSinceUpdate < (frame.updateInterval or GetRefreshRate()) then
        return
    end

    frame.elapsedSinceUpdate = 0

    if inCombat then
        RefreshTextOnly()
    elseif fadeDeadline and GetTime() >= fadeDeadline then
        fadeDeadline = nil
        RefreshTextOnly()

        if frame:IsShown() and AHLightUsage_ShouldShow and not AHLightUsage_ShouldShow() then
            frame:Hide()
        end
        -- The fade left the frame at ~0 alpha; restore it (while hidden) so the next show
        -- isn't invisible.
        if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
        frame:SetAlpha(1)
        if UpdateAHLightUsagePolling then UpdateAHLightUsagePolling() end
    end
end

UpdateAHLightUsagePolling = function()
    if not frame then
        return
    end

    if ShouldPollAHLightUsage() then
        if frame:GetScript("OnUpdate") ~= AHLightUsage_OnUpdate then
            frame.elapsedSinceUpdate = 0
            frame:SetScript("OnUpdate", AHLightUsage_OnUpdate)
        end
    elseif frame:GetScript("OnUpdate") then
        frame.elapsedSinceUpdate = 0
        frame:SetScript("OnUpdate", nil)
    end
end

function AHLightUsage_ControllerEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        frame.updateInterval = GetRefreshRate()
        frame.elapsedSinceUpdate = 0
        inCombat = UnitAffectingCombat("player") and true or false
        ResetCombatCounters()
        lastCombatPercent = 0
        lastCombatAHLight = 0
        lastCombatTotal = 0
        CancelFade()
        RefreshTextOnly()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        ResetCombatCounters()
        lastCombatPercent = 0
        lastCombatAHLight = 0
        lastCombatTotal = 0
        CancelFade()
        RefreshTextOnly()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if inCombat then
            lastCombatPercent = GetCurrentPercent()
            lastCombatAHLight = ahLightCastsThisCombat
            lastCombatTotal = totalCastsThisCombat
        end

        inCombat = false
        ResetCombatCounters()
        if MetersSavedVars.locked then
            RefreshTextOnly()
            if lastCombatTotal > 0 then
                StartFadeTimer()
            end
        else
            -- Unlocked = placement preview: show the example "24% (11/47)" via the Meters
            -- engine instead of fading out the live readout.
            if Meter_UpdateVisibility then Meter_UpdateVisibility() end
        end

    elseif event == "ASSISTED_COMBAT_ACTION_SPELL_CAST" then
        HandleAHLightCastEvent()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        HandleUnitSpellcastSucceeded(...)
    end
    if UpdateAHLightUsagePolling then UpdateAHLightUsagePolling() end
end

UpdateAHLightUsagePolling()
