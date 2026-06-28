-- AHLight.lua (Optimized)

local DEFAULT_REFRESH_RATE = 0.10
local MIN_REFRESH_RATE     = 0.02
local MAX_REFRESH_RATE     = 0.15
local GCD_SPELL_ID         = 61304
local PREVIEW_TEXTURE      = "Interface\\Icons\\ui_spellbook_onebutton"

MetersSavedVars = MetersSavedVars or {}

-- ─── Marker helpers (local, no global read on every tick) ─────────────────────
local VALID_MYMARKERS = {
    AHLight = true, Class = true, Specialization = true, Bullseye = true, None = true,
}

local function NormalizeMarker(value)
    if value == "SBA" then value = "AHLight" end
    return VALID_MYMARKERS[value] and value or "AHLight"
end

local function GetCurrentMarker()
    local sv = MetersSavedVars
    if not sv then return "AHLight" end

    if sv.Marker ~= nil then
        sv.Marker = NormalizeMarker(sv.Marker)
        return sv.Marker
    end
    if sv.centerIndicator ~= nil then
        return NormalizeMarker(sv.centerIndicator)
    end
    if sv.showAHLight == false or sv.showSBA == false then
        return "Bullseye"
    end
    return "AHLight"
end

-- OPTIMISATION: SyncLegacyShowAHLight was called on every Refresh() tick.
-- Now called only when the marker actually changes (events / explicit API).
local function SyncLegacyShowAHLight()
    if MetersSavedVars then
        MetersSavedVars.showAHLight = (GetCurrentMarker() == "AHLight")
    end
end

local function UsingAHLightIndicator()
    return GetCurrentMarker() == "AHLight"
end

-- ─── Refresh rate ─────────────────────────────────────────────────────────────
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
    return ClampRefreshRate(MetersSavedVars.refreshRate)
end

-- ─── Spell texture ────────────────────────────────────────────────────────────
local function GetSpellTextureSafe(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(spellID)
        if icon then return icon end
    end
    return GetSpellTexture(spellID)
end

-- ─── Frame ────────────────────────────────────────────────────────────────────
AHLightFrame = CreateFrame("Frame", "AHLightFrame", UIParent)
AHLightFrame:SetSize(28, 28)
AHLightFrame:SetFrameStrata("HIGH")
AHLightFrame:SetFrameLevel(11)
AHLightFrame:Hide()

AHLightFrame.icon = AHLightFrame:CreateTexture(nil, "OVERLAY")
AHLightFrame.icon:SetAllPoints()
AHLightFrame.icon:SetTexture(nil)
AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)

AHLightFrame.cooldown = CreateFrame("Cooldown", nil, AHLightFrame, "CooldownFrameTemplate")
AHLightFrame.cooldown:SetAllPoints(AHLightFrame)
AHLightFrame.cooldown:SetFrameLevel(AHLightFrame:GetFrameLevel() + 5)
AHLightFrame.cooldown:Hide()
if AHLightFrame.cooldown.SetDrawEdge         then AHLightFrame.cooldown:SetDrawEdge(false)          end
if AHLightFrame.cooldown.SetDrawBling        then AHLightFrame.cooldown:SetDrawBling(false)         end
if AHLightFrame.cooldown.SetHideCountdownNumbers then AHLightFrame.cooldown:SetHideCountdownNumbers(true) end
if AHLightFrame.cooldown.SetDrawSwipe        then AHLightFrame.cooldown:SetDrawSwipe(true)          end

-- ─── Module state ─────────────────────────────────────────────────────────────
local elapsedTotal        = 0
local lastSpellID         = nil
local isPreviewMode       = false
local currentRefreshRate  = DEFAULT_REFRESH_RATE
local lastAppliedIconSize = nil
local UpdateAHLightPolling
local PlayerIsMountedForAHLight

-- ─── Spell recommendation ─────────────────────────────────────────────────────
local function GetRecommendedSpell()
    if C_AssistedCombat then
        if type(C_AssistedCombat.GetNextCastSpell) == "function" then
            local id = C_AssistedCombat.GetNextCastSpell()
            if id and id ~= 0 then return id end
        end
        if type(C_AssistedCombat.GetActionSpell) == "function" then
            local id = C_AssistedCombat.GetActionSpell()
            if id and id ~= 0 then return id end
        end
    end
    return nil
end

local function InMountTransitionSuppress()
    -- Standalone: no external mount-transition hook. Mount handling is covered by the
    -- local PlayerIsMounted checks; nothing else to suppress.
    return false
end

-- ─── GCD swipe ────────────────────────────────────────────────────────────────
local function GetSpellCooldownInfo(spellID)
    if not spellID then return 0, 0, 0, 1 end
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            return info.startTime or 0, info.duration or 0, info.isEnabled or 0, info.modRate or 1
        end
    end
    local s, d, e, m = GetSpellCooldown(spellID)
    return s or 0, d or 0, e or 0, m or 1
end

local function ClearGCDSwipe()
    if not AHLightFrame or not AHLightFrame.cooldown then return end
    AHLightFrame.cooldown:SetCooldown(0, 0, 1)
    AHLightFrame.cooldown:Hide()
end

function AHLight_UpdateGCDSwipe()
    if not AHLightFrame or not AHLightFrame.cooldown or not AHLightFrame:IsShown() then return end
    if isPreviewMode then ClearGCDSwipe(); return end
    local startTime, duration, isEnabled, modRate = GetSpellCooldownInfo(GCD_SPELL_ID)
    if isEnabled == 0 or startTime <= 0 or duration <= 0 then
        ClearGCDSwipe(); return
    end
    AHLightFrame.cooldown:SetCooldown(startTime, duration, modRate or 1)
    AHLightFrame.cooldown:Show()
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function AHLight_ClearIcon()
    if not AHLightFrame then return end
    AHLightFrame.icon:SetTexture(nil)
    AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
    ClearGCDSwipe()
    AHLightFrame:Hide()
    lastSpellID = nil
    if UpdateAHLightPolling then UpdateAHLightPolling() end
end

AHLight_Clear = AHLight_ClearIcon   -- alias

function AHLight_ShouldShow()
    if not UsingAHLightIndicator() then return false end
    if isPreviewMode then return true end
    return AHLightFrame
        and AHLightFrame.icon
        and AHLightFrame.icon:GetTexture() ~= nil
end

function AHLight_SetPreview(enabled)
    isPreviewMode = enabled and true or false
    SyncLegacyShowAHLight()
    if not UsingAHLightIndicator() then
        AHLight_ClearIcon()
        if SetupFrames then SetupFrames() end
        return
    end
    if PlayerIsMountedForAHLight and PlayerIsMountedForAHLight() and not isPreviewMode then
        AHLight_ClearIcon()
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end
    if isPreviewMode then
        AHLightFrame.icon:SetTexture(PREVIEW_TEXTURE)
        AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
        ClearGCDSwipe()
        AHLightFrame:Show()
    else
        lastSpellID = nil
        AHLight_UpdateIcon()
    end
    if SetupFrames then SetupFrames() end
    if UpdateAHLightPolling then UpdateAHLightPolling() end
end

function AHLight_UpdateIcon(forceSpellID)
    if not AHLightFrame or not AHLightFrame.icon then return end

    if not UsingAHLightIndicator() then
        AHLight_ClearIcon(); return
    end

    if PlayerIsMountedForAHLight and PlayerIsMountedForAHLight() and not isPreviewMode then
        AHLight_ClearIcon()
        return
    end

    if isPreviewMode then
        AHLightFrame.icon:SetTexture(PREVIEW_TEXTURE)
        AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
        ClearGCDSwipe()
        AHLightFrame:Show()
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end

    local spellID = forceSpellID or GetRecommendedSpell()
    if not spellID then
        AHLightFrame.icon:SetTexture(nil)
        AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
        ClearGCDSwipe()
        AHLightFrame:Hide()
        lastSpellID = nil
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end

    local texture = GetSpellTextureSafe(spellID)
    if texture then
        AHLightFrame.icon:SetTexture(texture)
        AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
        AHLightFrame:Show()
        AHLight_UpdateGCDSwipe()
        lastSpellID = spellID
    else
        AHLightFrame.icon:SetTexture(nil)
        AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
        ClearGCDSwipe()
        AHLightFrame:Hide()
        lastSpellID = nil
    end
    if UpdateAHLightPolling then UpdateAHLightPolling() end
end

function AHLight_ApplySize(size)
    if not AHLightFrame then return end
    local iconSize = (size or 18) + 22
    if lastAppliedIconSize == iconSize then
        return
    end

    lastAppliedIconSize = iconSize
    AHLightFrame:SetSize(iconSize, iconSize)
    if AHLightFrame.cooldown then
        AHLightFrame.cooldown:SetAllPoints(AHLightFrame)
    end
    if Meter_InvalidateLayout then Meter_InvalidateLayout() end
    if SetupFrames then SetupFrames() end
end

-- OPTIMISATION: Refresh no longer calls SyncLegacyShowAHLight() every tick.
function AHLight_Refresh()
    if not UsingAHLightIndicator() then
        AHLight_ClearIcon(); return
    end
    if PlayerIsMountedForAHLight and PlayerIsMountedForAHLight() then
        AHLight_ClearIcon(); return
    end
    if isPreviewMode then
        if not AHLightFrame:IsShown() then
            AHLightFrame.icon:SetTexture(PREVIEW_TEXTURE)
            AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
            ClearGCDSwipe()
            AHLightFrame:Show()
        end
        return
    end

    local spellID = GetRecommendedSpell()
    if spellID ~= lastSpellID then
        if spellID then
            AHLight_UpdateIcon(spellID)
        else
            AHLight_ClearIcon()
        end
    elseif spellID then
        AHLight_UpdateGCDSwipe()  -- only update swipe, not the whole icon
    else
        ClearGCDSwipe()
    end
end

function AHLight_ControllerRefresh(forceIcon)
    SyncLegacyShowAHLight()
    currentRefreshRate = GetRefreshRate()
    MetersSavedVars.refreshRate = currentRefreshRate

    if InMountTransitionSuppress() then
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end

    if PlayerIsMountedForAHLight and PlayerIsMountedForAHLight() and not isPreviewMode then
        AHLight_ClearIcon()
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end

    if not UsingAHLightIndicator() then
        AHLight_ClearIcon()
        if SetupFrames then SetupFrames() end
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end

    if isPreviewMode then
        AHLightFrame.icon:SetTexture(PREVIEW_TEXTURE)
        AHLightFrame.icon:SetTexCoord(0, 1, 0, 1)
        ClearGCDSwipe()
        AHLightFrame:Show()
        if SetupFrames then SetupFrames() end
        if UpdateAHLightPolling then UpdateAHLightPolling() end
        return
    end

    if forceIcon then
        lastSpellID = nil
    end
    AHLight_Refresh()
    if UpdateAHLightPolling then UpdateAHLightPolling() end
end

function AHLight_ApplyRefreshRate(value)
    local rate = ClampRefreshRate(value)
    MetersSavedVars.refreshRate = rate
    currentRefreshRate = rate
    elapsedTotal = 0
    if UpdateAHLightPolling then UpdateAHLightPolling() end
end

-- ─── OnUpdate (throttled) ─────────────────────────────────────────────────────
PlayerIsMountedForAHLight = function()
    return (IsMounted and IsMounted())
        or (UnitOnTaxi and UnitOnTaxi("player"))
        or false
end

UpdateAHLightPolling = function()
    if not AHLightFrame then
        return
    end

    -- AHLight is event/meter-driven (not self-managed polling); ensure no stray
    -- OnUpdate handler is left installed.
    if AHLightFrame:GetScript("OnUpdate") then
        elapsedTotal = 0
        AHLightFrame:SetScript("OnUpdate", nil)
    end
end

