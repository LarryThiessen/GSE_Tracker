-- Modules\Meters\GCD.lua

local addonName, ns = ...
local GCD_SPELL_ID = 61304

MetersSavedVars = MetersSavedVars or {}

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ─── Frame ────────────────────────────────────────────────
local frame = CreateFrame("Frame", "GCDFrame", UIParent)
frame:SetSize(140, 24)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 117) -- moved down 3 pixels
frame:SetFrameStrata("HIGH")
frame:SetFrameLevel(11)
frame:SetClampedToScreen(true)
frame:Hide()

frame.gcdText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.gcdText:SetPoint("CENTER", frame, "CENTER", 0, -5) -- move all GCD text down 5 pixels
frame.gcdText:SetJustifyH("CENTER")
frame.gcdText:SetText("")

-- Backwards compatibility for any older references
frame.text = frame.gcdText

frame.isPreviewMode = false
frame.elapsedSinceUpdate = 0
frame.updateInterval = 0.10
frame.lastSeenDuration = 0
local UpdateGCDPolling

-- ─── Helpers ──────────────────────────────────────────────
local function IsEnabled()
    return MetersSavedVars.showGCD ~= false
end

local function ClampRefreshRate(value)
    value = tonumber(value) or 0.10

    if value < 0.05 then
        value = 0.05
    elseif value > 0.15 then
        value = 0.15
    end

    return value
end

local function GetRefreshRate()
    if Meters_GetRefreshRate then
        return ClampRefreshRate(Meters_GetRefreshRate())
    end

    MetersSavedVars.refreshRate = ClampRefreshRate(MetersSavedVars.refreshRate or 0.10)
    return MetersSavedVars.refreshRate
end

local function GetSavedFontName()
    return MetersSavedVars.fontStyle
        or MetersSavedVars.fontType
        or "Friz Quadrata TT"
end

local function GetGCDFontSize(size)
    size = tonumber(size) or 18
    return math.max(size - 2, 8)
end

local function ResolveFont(fontName)
    -- Auto-adopt the action-bar font face when a UI skin is active (mirrors the
    -- tracker adoption); Force-Native falls through to the player's pick below.
    local us = ns and ns._ui
    if us and us.GetAdoptedFontStyle then
        local ap = us.GetAdoptedFontStyle()
        if ap then return ap end
    end
    if type(fontName) == "string" and fontName ~= "" then
        if LSM then
            local ok, fetched = pcall(function()
                return LSM:Fetch("font", fontName)
            end)

            if ok and fetched then
                return fetched
            end
        end

        if fontName:find("\\") or fontName:find("/") then
            return fontName
        end
    end

    return STANDARD_TEXT_FONT
end

local function FormatGCDText(remaining, duration)
    duration = tonumber(duration) or 0
    remaining = tonumber(remaining) or 0

    if duration <= 0 then
        return ""
    end

    return string.format("%.2fs", duration)
end

local function GetActiveGCD()
    local startTime, duration

    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
        if info then
            startTime = info.startTime or 0
            duration = info.duration or 0
        end
    else
        startTime, duration = GetSpellCooldown(GCD_SPELL_ID)
        startTime = startTime or 0
        duration = duration or 0
    end

    if not startTime or not duration or duration <= 0 then
        return 0, 0
    end

    local now = GetTime()
    local remaining = math.max((startTime + duration) - now, 0)

    if remaining <= 0 then
        return 0, 0
    end

    return remaining, duration
end

local function ClearAndHide()
    frame.gcdText:SetText("")
    frame:Hide()
    if UpdateGCDPolling then UpdateGCDPolling() end
end

-- ─── Public API ───────────────────────────────────────────
function GCD_ApplyFont(fontName, size, flags)
    if not frame or not frame.gcdText then
        return
    end

    local chosenFont = fontName or GetSavedFontName()
    local chosenSize = size or MetersSavedVars.fontSize or 18
    local chosenFlags = flags
    if chosenFlags == nil then
        chosenFlags = "OUTLINE"
    end

    local fontPath = ResolveFont(chosenFont)
    local gcdSize = GetGCDFontSize(chosenSize)

    frame.gcdText:SetFont(fontPath, gcdSize, chosenFlags)
    frame.gcdText:SetJustifyH("CENTER")
end

function GCD_RefreshFont()
    GCD_ApplyFont(
        GetSavedFontName(),
        MetersSavedVars.fontSize or 18,
        "OUTLINE"
    )
end

function GCD_SetPreview(enabled)
    frame.isPreviewMode = enabled and true or false
    if UpdateGCDPolling then UpdateGCDPolling() end
end

function GCD_ApplyRefreshRate(value)
    frame.updateInterval = ClampRefreshRate(value or MetersSavedVars.refreshRate or 0.10)
    MetersSavedVars.refreshRate = frame.updateInterval
    frame.elapsedSinceUpdate = 0
    GCD_UpdateNow()
    if UpdateGCDPolling then UpdateGCDPolling() end
end

-- Backwards compatible alias
GCD_SetPreviewMode = GCD_SetPreview

function GCD_UpdateNow()
    -- GCD is a Blizzard cooldown read (spell 61304) -- available on every flavor, not just retail.
    if not _G.GSETracker_GCDCapable then
        if frame then frame:Hide() end
        return
    end
    if not frame or not frame.gcdText then
        return
    end

    if not IsEnabled() then
        frame.lastSeenDuration = 0
        ClearAndHide()
        return
    end

    -- When unlocked and out of combat, let preview logic own the text
    if not MetersSavedVars.locked and not UnitAffectingCombat("player") then
        return
    end

    if frame.isPreviewMode then
        return
    end

    local inCombat = UnitAffectingCombat("player")
    local remaining, duration = GetActiveGCD()

    if duration > 0 and remaining > 0 then
        frame.lastSeenDuration = duration
        frame.gcdText:SetText(FormatGCDText(remaining, duration))
        frame:Show()
        if UpdateGCDPolling then UpdateGCDPolling() end
        return
    end

    if inCombat and frame.lastSeenDuration and frame.lastSeenDuration > 0 then
        frame.gcdText:SetText(string.format("%.2fs", frame.lastSeenDuration))
        frame:Show()
        if UpdateGCDPolling then UpdateGCDPolling() end
        return
    end

    frame.lastSeenDuration = 0
    ClearAndHide()
end

-- ─── Live Updates ─────────────────────────────────────────
local function ShouldPollGCD()
    return frame
        and frame:IsShown()
        and IsEnabled()
        and not frame.isPreviewMode
end

local function GCD_OnUpdate(self, elapsed)
    if not _G.GSETracker_GCDCapable then return end
    self.elapsedSinceUpdate = (self.elapsedSinceUpdate or 0) + (elapsed or 0)

    if self.elapsedSinceUpdate < (self.updateInterval or GetRefreshRate()) then
        return
    end

    self.elapsedSinceUpdate = 0
    GCD_UpdateNow()
end

UpdateGCDPolling = function()
    if not frame then
        return
    end

    if ShouldPollGCD() then
        if frame:GetScript("OnUpdate") ~= GCD_OnUpdate then
            frame.elapsedSinceUpdate = 0
            frame:SetScript("OnUpdate", GCD_OnUpdate)
        end
    elseif frame:GetScript("OnUpdate") then
        frame.elapsedSinceUpdate = 0
        frame:SetScript("OnUpdate", nil)
    end
end

frame:HookScript("OnShow", function()
    if UpdateGCDPolling then UpdateGCDPolling() end
end)
frame:HookScript("OnHide", function()
    if UpdateGCDPolling then UpdateGCDPolling() end
end)

-- ─── Initial State ────────────────────────────────────────
MetersSavedVars.refreshRate = ClampRefreshRate(MetersSavedVars.refreshRate or 0.10)
GCD_RefreshFont()
GCD_ApplyRefreshRate(MetersSavedVars.refreshRate)
