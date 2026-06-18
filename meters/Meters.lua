-- Meters.lua (Optimized)

local _, ns = ...

MetersSavedVars = MetersSavedVars or {}

-- ─── Legacy Migration (run ONCE at load, not per-module) ──────────────────────
-- Centralised here; UI\MetersOptions.lua and per-module files no longer need to repeat it.
do
    local sv = MetersSavedVars
    if sv.showAHLight == nil and sv.showSBA ~= nil then
        sv.showAHLight = sv.showSBA
    end
    if sv.showAHLightUsage == nil and sv.showSBAUsage ~= nil then
        sv.showAHLightUsage = sv.showSBAUsage
    end
end

local VALID_MARKERS = {
    AHLight    = true,
    Class        = true,
    Specialization = true,
    Bullseye     = true,
    None         = true,
}

local function NormalizeMarker(value)
    if value == "SBA" then value = "AHLight" end
    return VALID_MARKERS[value] and value or "AHLight"
end

local function GetMarker()
    return NormalizeMarker(MetersSavedVars.Marker)
end

local function UsingAHLight()
    return GetMarker() == "AHLight"
end

local function SyncLegacyShowAHLight()
    MetersSavedVars.showAHLight = UsingAHLight()
end

local function SetMarker(value)
    MetersSavedVars.Marker = NormalizeMarker(value)
    SyncLegacyShowAHLight()
end

-- ─── Refresh Rate ─────────────────────────────────────────────────────────────
-- OPTIMISATION: clamp is inlined; no rounding needed beyond min/max clamp.
local function ClampRefreshRateValue(value)
    value = tonumber(value) or 0.10
    if value < 0.05 then return 0.05 end
    if value > 0.15 then return 0.15 end
    return value
end

function Meters_GetRefreshRate()
    local r = ClampRefreshRateValue(MetersSavedVars.refreshRate or 0.10)
    MetersSavedVars.refreshRate = r
    return r
end

Meters_GetUpdateInterval = Meters_GetRefreshRate   -- alias

-- ─── Defaults ─────────────────────────────────────────────────────────────────
local function EnsureDefaults()
    local sv = MetersSavedVars
    -- Boolean flags default true
    for _, k in ipairs({"locked","showDPS","showHPS","showGCD","showAHLightUsage"}) do
        if sv[k] == nil then sv[k] = true end
    end
    sv.opacity      = sv.opacity     or 100
    sv.fontSize     = sv.fontSize    or 18
    -- Keep fontStyle / fontType in sync
    local fname = sv.fontStyle or sv.fontType or "Friz Quadrata TT"
    sv.fontStyle    = fname
    sv.fontType     = fname
    sv.showWhen     = sv.showWhen    or "Always"
    sv.point        = "CENTER"
    sv.relPoint     = "CENTER"
    sv.x            = sv.x          or 0
    sv.y            = sv.y          or -15
    sv.refreshRate  = ClampRefreshRateValue(sv.refreshRate or 0.10)

    -- Migrate old centerIndicator → Marker
    if sv.Marker == nil then
        if sv.centerIndicator ~= nil then
            sv.Marker = NormalizeMarker(sv.centerIndicator)
        elseif sv.showAHLight == false or sv.showSBA == false then
            sv.Marker = "Bullseye"
        else
            sv.Marker = "AHLight"
        end
    else
        sv.Marker = NormalizeMarker(sv.Marker)
    end

    SyncLegacyShowAHLight()
end

EnsureDefaults()

-- ─── Font helpers ─────────────────────────────────────────────────────────────
local function GetCurrentFontName()
    return MetersSavedVars.fontStyle or MetersSavedVars.fontType or "Friz Quadrata TT"
end

local function SetCurrentFontName(name)
    name = name or "Friz Quadrata TT"
    MetersSavedVars.fontStyle = name
    MetersSavedVars.fontType  = name
end

-- ─── Misc helpers ─────────────────────────────────────────────────────────────
local function RoundToNearest(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function PlayerIsMounted()
    return (UnitOnTaxi and UnitOnTaxi("player"))
        or (IsMounted and IsMounted())
        or false
end

-- Authoritative combat state, driven by PLAYER_REGEN_DISABLED/ENABLED (in the event
-- handler) and re-synced on PLAYER_ENTERING_WORLD. UnitAffectingCombat("player") can still
-- report combat at the exact tick PLAYER_REGEN_ENABLED fires, which made the unlocked
-- placement preview fail to reappear after a fight (it only came back on a lock/unlock).
-- The regen events are the reliable "left combat" signal, so this flag is the source of
-- truth -- do NOT fall back to UnitAffectingCombat here or that lingering tick returns.
-- Initialised from UnitAffectingCombat for the load-time/mid-combat-reload case.
local playerInCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false

local function InCombatLock()
    return playerInCombat
end

local function InMountTransitionSuppress()
    -- Standalone: no external mount-transition hook. Mount handling is covered by the
    -- local PlayerIsMounted checks; nothing else to suppress.
    return false
end

local function IsFramePositionLocked()
    return MetersSavedVars.locked or InCombatLock()
end

local function ResolveFontPath(fontName)
    -- Auto-adopt the action-bar font face when a UI skin is active (mirrors the
    -- tracker adoption); Force-Native falls through to the player's pick below.
    local us = ns and ns._ui
    if us and us.GetAdoptedFontStyle then
        local ap = us.GetAdoptedFontStyle()
        if ap then return ap end
    end
    local name = fontName or GetCurrentFontName()
    if type(name) == "string" and name ~= "" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local ok, fetched = pcall(function() return LSM:Fetch("font", name) end)
            if ok and fetched then return fetched end
        end
        if name:find("\\") or name:find("/") then return name end
    end
    return STANDARD_TEXT_FONT
end

-- ─── Anchor ───────────────────────────────────────────────────────────────────
local anchor = CreateFrame("Frame", "MetersAnchor", UIParent)
anchor:SetSize(320, 120)
anchor:SetFrameStrata("HIGH")
anchor:SetFrameLevel(10)
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:Hide()

-- ─── Opacity helpers ──────────────────────────────────────────────────────────
local function GetConfiguredOpacity()
    local o = RoundToNearest(tonumber(MetersSavedVars.opacity) or 100)
    if o < 25 then return 25 end
    if o > 100 then return 100 end
    return o
end

local function ApplyEffectiveOpacity()
    if not anchor then return end
    -- The Opacity slider controls ALL meter parts: every readout frame (DPS/HPS/GCD/usage
    -- + marker) is reparented onto `anchor` in SetupFrames, so the anchor's alpha cascades
    -- to them. Apply the configured value directly -- locked or unlocked -- so the slider
    -- always takes effect. (It used to force full alpha whenever unlocked, which made the
    -- slider appear to do nothing while the options window was open.)
    anchor:SetAlpha(GetConfiguredOpacity() / 100)
end

-- ─── GCD / Marker helpers ─────────────────────────────────────────────────────
local function SetGCDPreviewState(enabled)
    if GCD_SetPreview then
        GCD_SetPreview(enabled)
    elseif GCD_SetPreviewMode then
        GCD_SetPreviewMode(enabled)
    end
end

local function ClearMarkerDisplay()
    if Marker_Clear then
        Marker_Clear()
    elseif MarkerFrame then
        MarkerFrame:Hide()
    end
end

-- ─── Center icon ──────────────────────────────────────────────────────────────
local iconCenter = CreateFrame("Frame", nil, anchor)
iconCenter:SetPoint("CENTER", anchor, "CENTER", 0, 0)
iconCenter:SetSize(1, 1)

local CENTER_GCD_SPELL_ID   = 61304
local BULLSEYE_SWIPE_TEXTURE = "Interface\\AddOns\\GSE_Tracker\\media\\marker-images\\Crosshairs001.png"
local GetCenterFrameSize    -- forward declaration

local centerGCDSwipe = CreateFrame("Cooldown", nil, anchor, "CooldownFrameTemplate")
centerGCDSwipe:SetDrawEdge(false)
centerGCDSwipe:SetDrawBling(false)
centerGCDSwipe:SetDrawSwipe(true)
centerGCDSwipe:SetHideCountdownNumbers(true)
centerGCDSwipe:SetReverse(false)
centerGCDSwipe:SetFrameStrata("HIGH")
centerGCDSwipe:SetFrameLevel(12)
centerGCDSwipe:Hide()
if centerGCDSwipe.SetSwipeColor then
    centerGCDSwipe:SetSwipeColor(0, 0, 0, 0.65)
end

local function ShouldShowCenterGCDSwipe()
    return (MetersSavedVars.showGCD ~= false)
        and (GetMarker() ~= "None")
        and (not PlayerIsMounted())
end

-- OPTIMISATION: candidate table is module-level; no allocation per call.
local _textureCandidates = {
    "icon","Icon","texture","Texture","tex",
    "iconTexture","IconTexture","markerTexture",
    "centerTexture","ahLightTexture","AHLightTexture",
}
local function GetTexturePathFromFrame(f)
    if not f then return nil end
    for _, key in ipairs(_textureCandidates) do
        local region = f[key]
        if region and region.GetObjectType
                  and region:GetObjectType() == "Texture"
                  and region.GetTexture then
            local tex = region:GetTexture()
            if tex then return tex end
        end
    end
    local regions = { f:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region.GetObjectType
                  and region:GetObjectType() == "Texture"
                  and region.GetTexture then
            local tex = region:GetTexture()
            if tex then return tex end
        end
    end
    return nil
end

local function ResolveCenterSwipeTexture()
    local mode = GetMarker()
    if mode == "None"     then return nil end
    if mode == "Bullseye" then return BULLSEYE_SWIPE_TEXTURE end
    if UsingAHLight()   then return GetTexturePathFromFrame(AHLightFrame) end
    return GetTexturePathFromFrame(MarkerFrame)
end

local function ClearCenterGCDSwipe()
    if centerGCDSwipe.Clear then
        centerGCDSwipe:Clear()
    else
        centerGCDSwipe:SetCooldown(0, 0)
    end
    centerGCDSwipe:Hide()
end

local function GetCenterGCDCooldownInfo()
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(CENTER_GCD_SPELL_ID)
        if info then
            return tonumber(info.startTime) or 0,
                   tonumber(info.duration)  or 0,
                   info.isEnabled ~= false,
                   tonumber(info.modRate)   or 1
        end
    end
    if GetSpellCooldown then
        local s, d, e, m = GetSpellCooldown(CENTER_GCD_SPELL_ID)
        return tonumber(s) or 0, tonumber(d) or 0, e ~= 0, tonumber(m) or 1
    end
    return 0, 0, false, 1
end

local function UpdateCenterGCDSwipe()
    if not centerGCDSwipe then return end
    if not ShouldShowCenterGCDSwipe() then
        ClearCenterGCDSwipe()
        return
    end
    local width, height = GetCenterFrameSize()
    width  = math.max(1, tonumber(width)  or 1)
    height = math.max(1, tonumber(height) or 1)
    local swipeTexture = ResolveCenterSwipeTexture()
    local layoutKey = tostring(width) .. ":" .. tostring(height) .. ":" .. tostring(swipeTexture or "")
    if centerGCDSwipe._layoutKey ~= layoutKey then
        if swipeTexture and centerGCDSwipe.SetSwipeTexture then
            centerGCDSwipe:SetSwipeTexture(swipeTexture)
        end
        centerGCDSwipe:SetParent(anchor)
        centerGCDSwipe:SetFrameLevel(12)
        centerGCDSwipe:SetSize(width, height)
        centerGCDSwipe:ClearAllPoints()
        centerGCDSwipe:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
        centerGCDSwipe._layoutKey = layoutKey
    end
    local startTime, duration, enabled, modRate = GetCenterGCDCooldownInfo()
    if enabled and startTime > 0 and duration and duration > 0 then
        centerGCDSwipe:SetCooldown(startTime, duration, modRate or 1)
        centerGCDSwipe:Show()
    else
        ClearCenterGCDSwipe()
    end
end

GetCenterFrameSize = function()
    local fallback = math.max(24, RoundToNearest((MetersSavedVars.fontSize or 18) * 1.6))
    local width, height = fallback, fallback
    if UsingAHLight() then
        if AHLightFrame then
            local w = tonumber(AHLightFrame:GetWidth())  or 0
            local h = tonumber(AHLightFrame:GetHeight()) or 0
            if w > 0 then width  = w end
            if h > 0 then height = h end
        end
    else
        if MarkerFrame then
            local w = tonumber(MarkerFrame:GetWidth())  or 0
            local h = tonumber(MarkerFrame:GetHeight()) or 0
            if w > 0 then width  = w end
            if h > 0 then height = h end
        end
    end
    return width, height
end

-- ─── Marker / AHLight helpers ─────────────────────────────────────────────────
local function UpdateMarkerFrame()
    if PlayerIsMounted() and IsFramePositionLocked() then ClearMarkerDisplay(); return end
    local mode = GetMarker()
    if mode == "AHLight" or mode == "None" then ClearMarkerDisplay(); return end
    if not MarkerFrame then return end
    MarkerFrame:SetParent(MetersAnchor or UIParent)
    MarkerFrame:SetFrameLevel(11)
    MarkerFrame:ClearAllPoints()
    MarkerFrame:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
    MarkerFrame:SetAlpha(1)
    MarkerFrame:Show()
end

local function SyncMarkerState()
    local mode = GetMarker()
    if mode == "AHLight" or mode == "None" then ClearMarkerDisplay(); return end
    if Marker_SetMode    then Marker_SetMode(mode) end
    if Marker_SetPreview then Marker_SetPreview(not IsFramePositionLocked()) end
    if Marker_Refresh    then Marker_Refresh() end
    UpdateMarkerFrame()
end

local function ClearAHLightDisplay()
    if AHLight_SetPreview then AHLight_SetPreview(false) end
    if AHLight_Clear      then AHLight_Clear() end
end

local function ShouldUseAHLightPreview()
    return UsingAHLight() and (not IsFramePositionLocked())
end

local function UpdateAHLightFrame(forceIcon)
    if not AHLightFrame then return end
    if not UsingAHLight() or (PlayerIsMounted() and not ShouldUseAHLightPreview()) then
        ClearAHLightDisplay()
        AHLightFrame:Hide()
        return
    end
    if AHLight_SetPreview then AHLight_SetPreview(ShouldUseAHLightPreview()) end
    if AHLight_ControllerRefresh then
        AHLight_ControllerRefresh(forceIcon)
    elseif AHLight_UpdateIcon then
        AHLight_UpdateIcon()
    end
    if not MetersSavedVars.locked and InCombatLock() then
        AHLightFrame:Show()
        return
    end
    if AHLight_ShouldShow then
        AHLightFrame:SetShown(AHLight_ShouldShow())
    else
        AHLightFrame:Show()
    end
end

local function ShouldUseAHLightUsagePreview()
    return not IsFramePositionLocked()
end

local function ClearAHLightUsageDisplay()
    if AHLightUsage_SetPreview then
        AHLightUsage_SetPreview(false)
    end
    if AHLightUsage_Clear then
        AHLightUsage_Clear()
    elseif AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText then
        AHLightUsageFrame.ahLightUsageText:SetText("")
    end
end

local function UpdateAHLightUsageFrame()
    if not AHLightUsageFrame then return end
    if (PlayerIsMounted() and not ShouldUseAHLightUsagePreview()) or MetersSavedVars.showAHLightUsage == false then
        ClearAHLightUsageDisplay()
        AHLightUsageFrame:Hide()
        return
    end
    if ShouldUseAHLightUsagePreview() then
        if AHLightUsage_SetPreview then
            AHLightUsage_SetPreview(true)
        elseif AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:SetText("24% (11/47)")
        end
        AHLightUsageFrame:Show()
        return
    end
    if AHLightUsage_SetPreview then AHLightUsage_SetPreview(false) end
    if AHLightUsage_Refresh    then AHLightUsage_Refresh() end
    if not MetersSavedVars.locked and InCombatLock() then
        AHLightUsageFrame:Show()
        return
    end
    if AHLightUsage_ShouldShow and AHLightUsage_ShouldShow() then
        AHLightUsageFrame:Show()
    else
        AHLightUsageFrame:Hide()
    end
end

-- ─── Anchor interactivity ─────────────────────────────────────────────────────
local UpdateAnchorInteractivity

local function ApplyUnlockedPreviewDisplay()
    if MetersSavedVars.locked or InCombatLock() then
        return false
    end

    ApplyEffectiveOpacity()
    anchor:Show()
    if UpdateAnchorInteractivity then UpdateAnchorInteractivity() end

    if UsingAHLight() then
        ClearMarkerDisplay()
        if AHLight_ApplySize then AHLight_ApplySize(MetersSavedVars.fontSize) end
        if AHLight_SetPreview then AHLight_SetPreview(true) end
        if AHLightFrame then AHLightFrame:Show() end
    else
        ClearAHLightDisplay()
        if AHLightFrame then AHLightFrame:Hide() end
        if Marker_SetMode then Marker_SetMode(GetMarker()) end
        if Marker_SetPreview then Marker_SetPreview(true) end
        if Marker_Refresh then Marker_Refresh() end
        if MarkerFrame and GetMarker() ~= "None" then MarkerFrame:Show() end
    end

    if DPSFrame and DPSFrame.dpsText then
        if MetersSavedVars.showDPS ~= false then
            DPSFrame.dpsText:SetText("12345")
            DPSFrame:Show()
        else
            DPSFrame.dpsText:SetText("")
            DPSFrame:Hide()
        end
    end

    if HPSFrame and HPSFrame.hpsText then
        if MetersSavedVars.showHPS ~= false then
            HPSFrame.hpsText:SetText("6789")
            HPSFrame:Show()
        else
            HPSFrame.hpsText:SetText("")
            HPSFrame:Hide()
        end
    end

    if GCDFrame and GCDFrame.gcdText then
        if MetersSavedVars.showGCD ~= false then
            SetGCDPreviewState(true)
            GCDFrame.gcdText:SetText("1.50s")
            GCDFrame:Show()
        else
            SetGCDPreviewState(false)
            GCDFrame.gcdText:SetText("")
            GCDFrame:Hide()
        end
    end

    if AHLightUsageFrame then
        if MetersSavedVars.showAHLightUsage ~= false then
            if AHLightUsage_SetPreview then
                AHLightUsage_SetPreview(true)
            elseif AHLightUsageFrame.ahLightUsageText then
                AHLightUsageFrame.ahLightUsageText:SetText("24% (11/47)")
            end
            AHLightUsageFrame:Show()
        else
            ClearAHLightUsageDisplay()
            AHLightUsageFrame:Hide()
        end
    end

    if Meter_InvalidateLayout then Meter_InvalidateLayout() end
    if SetupFrames then SetupFrames() end
    UpdateCenterGCDSwipe()
    return true
end

UpdateAnchorInteractivity = function()
    local locked = IsFramePositionLocked()
    if locked then
        anchor:StopMovingOrSizing()
        anchor:SetMovable(false)
        anchor:EnableMouse(false)
        if anchor.SetMouseClickEnabled  then anchor:SetMouseClickEnabled(false)  end
        if anchor.SetMouseMotionEnabled then anchor:SetMouseMotionEnabled(false) end
    else
        anchor:SetMovable(true)
        anchor:EnableMouse(true)
        if anchor.SetMouseClickEnabled  then anchor:SetMouseClickEnabled(true)  end
        if anchor.SetMouseMotionEnabled then anchor:SetMouseMotionEnabled(true) end
    end
    ApplyEffectiveOpacity()
end

Meters_ShowPreview = ApplyUnlockedPreviewDisplay

-- ─── Saved position ───────────────────────────────────────────────────────────
local function ApplySavedPosition()
    local x = RoundToNearest(MetersSavedVars.x or 0)
    local y = RoundToNearest(MetersSavedVars.y or -15)
    MetersSavedVars.x = x
    MetersSavedVars.y = y
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function SaveAnchorPosition()
    anchor:StopMovingOrSizing()
    local ax, ay = anchor:GetCenter()
    local px, py = UIParent:GetCenter()
    local x = MetersSavedVars.x or 0
    local y = MetersSavedVars.y or -15
    if ax and ay and px and py then
        x = RoundToNearest(ax - px)
        y = RoundToNearest(ay - py)
    end
    MetersSavedVars.x = x
    MetersSavedVars.y = y
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    if Meter_SyncPositionControls then Meter_SyncPositionControls() end
end

-- ─── Layout ───────────────────────────────────────────────────────────────────
local lastLayoutKey = nil

function Meter_InvalidateLayout()
    lastLayoutKey = nil
    if centerGCDSwipe then
        centerGCDSwipe._layoutKey = nil
    end
end

function SetupFrames()
    local gap = 3
    local iconWidth, iconHeight = 0, 0
    local usingAHLight = UsingAHLight()
    local markerMode = GetMarker()
    local needsAnchorLayout = false

    if AHLightFrame then
        needsAnchorLayout = needsAnchorLayout or (AHLightFrame._gnomesterLayoutAnchor ~= anchor)
        if usingAHLight then
            iconWidth  = AHLightFrame:GetWidth()  or 0
            iconHeight = AHLightFrame:GetHeight() or 0
        end
    end

    if not usingAHLight and MarkerFrame then
        needsAnchorLayout = needsAnchorLayout or (MarkerFrame._gnomesterLayoutAnchor ~= anchor)
        iconWidth  = MarkerFrame:GetWidth()  or 0
        iconHeight = MarkerFrame:GetHeight() or 0
    end

    if iconWidth <= 0 or iconHeight <= 0 then
        iconWidth, iconHeight = GetCenterFrameSize()
    end

    local offsetX = (iconWidth > 0) and ((iconWidth / 2) + gap) or 0

    -- GCD text height
    local gcdTextHeight = MetersSavedVars.fontSize or 18
    if GCDFrame and GCDFrame.gcdText then
        local h = tonumber(GCDFrame.gcdText:GetStringHeight()) or 0
        if h > 0 then
            gcdTextHeight = h
        else
            local _, fs = GCDFrame.gcdText:GetFont()
            gcdTextHeight = tonumber(fs) or gcdTextHeight
        end
    end

    local gcdOffsetY
    if iconHeight > 0 then
        gcdOffsetY = math.floor(((iconHeight / 2) + (gcdTextHeight / 2) + gap) + 0.5)
    else
        gcdOffsetY = math.floor(((gcdTextHeight / 2) + gap) + 0.5)
    end

    -- Usage text height
    local usageTextHeight = math.max(6, (MetersSavedVars.fontSize or 18) - 2)
    if AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText then
        local h = tonumber(AHLightUsageFrame.ahLightUsageText:GetStringHeight()) or 0
        if h > 0 then
            usageTextHeight = h
        else
            local _, fs = AHLightUsageFrame.ahLightUsageText:GetFont()
            usageTextHeight = tonumber(fs) or usageTextHeight
        end
    end

    local usageOffsetY
    if iconHeight > 0 then
        usageOffsetY = -math.floor(((iconHeight / 2) + (usageTextHeight / 2) + gap) + 0.5)
    else
        usageOffsetY = -math.floor(((usageTextHeight / 2) + gap) + 0.5)
    end

    local layoutKey = table.concat({
        tostring(markerMode),
        tostring(MetersSavedVars.fontSize or 18),
        tostring(iconWidth),
        tostring(iconHeight),
        tostring(gcdTextHeight),
        tostring(usageTextHeight),
        tostring(MetersSavedVars.showDPS ~= false),
        tostring(MetersSavedVars.showHPS ~= false),
        tostring(MetersSavedVars.showGCD ~= false),
        tostring(MetersSavedVars.showAHLightUsage ~= false),
    }, ":")

    if lastLayoutKey == layoutKey and not needsAnchorLayout then
        UpdateCenterGCDSwipe()
        return
    end
    lastLayoutKey = layoutKey

    if AHLightFrame then
        AHLightFrame:SetParent(anchor)
        AHLightFrame._gnomesterLayoutAnchor = anchor
        AHLightFrame:SetFrameLevel(11)
        AHLightFrame:ClearAllPoints()
        AHLightFrame:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
    end

    if not usingAHLight and MarkerFrame then
        MarkerFrame:SetParent(anchor)
        MarkerFrame._gnomesterLayoutAnchor = anchor
        MarkerFrame:SetFrameLevel(11)
        MarkerFrame:ClearAllPoints()
        MarkerFrame:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
        MarkerFrame:SetAlpha(1)
    end

    if DPSFrame then
        DPSFrame:SetParent(anchor)
        DPSFrame:SetFrameLevel(11)
        DPSFrame:ClearAllPoints()
        DPSFrame:SetPoint("RIGHT", iconCenter, "CENTER", -offsetX, 0)
        if DPSFrame.dpsText then
            DPSFrame.dpsText:ClearAllPoints()
            DPSFrame.dpsText:SetPoint("RIGHT", iconCenter, "CENTER", -offsetX, 0)
            DPSFrame.dpsText:SetJustifyH("RIGHT")
        end
    end

    if HPSFrame then
        HPSFrame:SetParent(anchor)
        HPSFrame:SetFrameLevel(11)
        HPSFrame:ClearAllPoints()
        HPSFrame:SetPoint("LEFT", iconCenter, "CENTER", offsetX, 0)
        if HPSFrame.hpsText then
            HPSFrame.hpsText:ClearAllPoints()
            HPSFrame.hpsText:SetPoint("LEFT", iconCenter, "CENTER", offsetX, 0)
            HPSFrame.hpsText:SetJustifyH("LEFT")
        end
    end

    if GCDFrame then
        GCDFrame:SetParent(anchor)
        GCDFrame:SetFrameLevel(11)
        GCDFrame:ClearAllPoints()
        if GCDFrame.gcdText then
            GCDFrame.gcdText:ClearAllPoints()
            GCDFrame.gcdText:SetPoint("CENTER", GCDFrame, "CENTER", 0, 0)
            GCDFrame.gcdText:SetJustifyH("CENTER")
        end
        GCDFrame:SetPoint("CENTER", iconCenter, "CENTER", 0, gcdOffsetY)
    end

    if AHLightUsageFrame then
        AHLightUsageFrame:SetParent(anchor)
        AHLightUsageFrame:SetFrameLevel(11)
        AHLightUsageFrame:ClearAllPoints()
        AHLightUsageFrame:SetPoint("CENTER", iconCenter, "CENTER", 0, usageOffsetY)
        if AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:ClearAllPoints()
            AHLightUsageFrame.ahLightUsageText:SetPoint("CENTER", AHLightUsageFrame, "CENTER", 0, 0)
            AHLightUsageFrame.ahLightUsageText:SetJustifyH("CENTER")
        end
    end

    UpdateCenterGCDSwipe()
end

-- ─── Visibility ───────────────────────────────────────────────────────────────
function Meter_UpdateVisibility()
    local mode = MetersSavedVars.showWhen or "Always"

    -- Master enable (the "Meters" entry in the GSE: Tracker General > Enable list).
    -- nil = enabled (default); only an explicit false hides everything.
    if MetersSavedVars.enabled == false then
        anchor:Hide()
        ClearCenterGCDSwipe()
        return
    end

    if ApplyUnlockedPreviewDisplay() then
        return
    end

    -- Not in placement-preview (locked, or in combat). When OUT of combat (locked + idle),
    -- clear any leftover EXAMPLE/live text + hide the readout parts so locking doesn't keep
    -- showing the examples ("12345"/"6789"/...). In combat the live modules own the text.
    if not InCombatLock() then
        if DPSFrame and DPSFrame.dpsText then DPSFrame.dpsText:SetText(""); DPSFrame:Hide() end
        if HPSFrame and HPSFrame.hpsText then HPSFrame.hpsText:SetText(""); HPSFrame:Hide() end
        if GCDFrame and GCDFrame.gcdText then GCDFrame.gcdText:SetText(""); GCDFrame:Hide() end
        if SetGCDPreviewState then SetGCDPreviewState(false) end
        if AHLightUsage_Clear then AHLightUsage_Clear()
        elseif AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:SetText(""); AHLightUsageFrame:Hide()
        end
    end

    if PlayerIsMounted() then
        anchor:Hide()
        ClearCenterGCDSwipe()
        return
    end

    if mode == "Always" then
        anchor:Show()
    elseif mode == "Combat" then
        anchor:SetShown(InCombatLock())
    elseif mode == "Has Target" then
        local hasTarget = UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
        anchor:SetShown(hasTarget or InCombatLock())
    elseif mode == "Never" then
        anchor:Hide()
    end

    if anchor:IsShown() then
        ApplyEffectiveOpacity()
        if UsingAHLight() then
            UpdateAHLightFrame()
            ClearMarkerDisplay()
        else
            if AHLightFrame then AHLightFrame:Hide() end
            SyncMarkerState()
        end
    end

    UpdateCenterGCDSwipe()
    UpdateAnchorInteractivity()
end

-- ─── Apply functions ──────────────────────────────────────────────────────────
function Meter_SetLocked(locked)
    MetersSavedVars.locked = not not locked
    UpdateAnchorInteractivity()
    local effectiveLocked = IsFramePositionLocked()
    if effectiveLocked then
        SetGCDPreviewState(false)
    else
        SetGCDPreviewState(MetersSavedVars.showGCD)
    end
    if AHLight_ApplySize then AHLight_ApplySize(MetersSavedVars.fontSize) end
    if AHLight_UpdateIcon then AHLight_UpdateIcon() end
    if not UsingAHLight() then SyncMarkerState() end
    Meter_InvalidateLayout()
    SetupFrames()
    Meter_SetDisplay(
        UsingAHLight(),
        MetersSavedVars.showDPS,
        MetersSavedVars.showHPS,
        MetersSavedVars.showGCD,
        MetersSavedVars.showAHLightUsage
    )
    Meter_UpdateVisibility()
    -- Re-enable/disable the Position X/Y sliders to match the new lock state (so they
    -- become active when unlocked from anywhere, e.g. the General tab's "Lock All").
    if Meter_SyncPositionControls then Meter_SyncPositionControls() end
end

function Meter_SetCenterIndicator(indicator)
    SetMarker(indicator)
    SyncMarkerState()
    Meter_InvalidateLayout()
    SetupFrames()
    Meter_SetDisplay(
        UsingAHLight(),
        MetersSavedVars.showDPS,
        MetersSavedVars.showHPS,
        MetersSavedVars.showGCD,
        MetersSavedVars.showAHLightUsage
    )
    Meter_UpdateVisibility()
end

function Meter_SetDisplay(showAHLight, showDPS, showHPS, showGCD, showAHLightUsage)
    -- Backward compatibility
    if showAHLight == true and not UsingAHLight() then
        SetMarker("AHLight")
        if Marker_SetMode then Marker_SetMode("AHLight") end
    elseif showAHLight == false and UsingAHLight() then
        SetMarker("Bullseye")
        SyncMarkerState()
    end

    showDPS          = showDPS          ~= nil and showDPS          or MetersSavedVars.showDPS
    showHPS          = showHPS          ~= nil and showHPS          or MetersSavedVars.showHPS
    showGCD          = showGCD          ~= nil and showGCD          or MetersSavedVars.showGCD
    showAHLightUsage = showAHLightUsage ~= nil and showAHLightUsage or MetersSavedVars.showAHLightUsage

    MetersSavedVars.showDPS          = showDPS
    MetersSavedVars.showHPS          = showHPS
    MetersSavedVars.showGCD          = showGCD
    MetersSavedVars.showAHLightUsage = showAHLightUsage
    SyncLegacyShowAHLight()

    if ApplyUnlockedPreviewDisplay() then
        return
    end

    if DPSFrame then DPSFrame:SetShown(showDPS) end
    if HPSFrame then HPSFrame:SetShown(showHPS) end

    if GCDFrame then
        local usePreview = (not IsFramePositionLocked()) and (not PlayerIsMounted())
        if usePreview then
            SetGCDPreviewState(showGCD)
            if showGCD then
                if GCDFrame.gcdText then GCDFrame.gcdText:SetText("1.50s") end
                GCDFrame:Show()
            else
                if GCDFrame.gcdText then GCDFrame.gcdText:SetText("") end
                GCDFrame:Hide()
            end
        else
            SetGCDPreviewState(false)
            if showGCD then
                if GCD_UpdateNow then GCD_UpdateNow() end
            else
                if GCDFrame.gcdText then GCDFrame.gcdText:SetText("") end
                GCDFrame:Hide()
            end
        end
    end

    if UsingAHLight() then
        UpdateAHLightFrame()
        ClearMarkerDisplay()
    else
        ClearAHLightDisplay()
        if AHLightFrame then AHLightFrame:Hide() end
        SyncMarkerState()
    end

    if AHLightUsageFrame then
        if showAHLightUsage then
            UpdateAHLightUsageFrame()
        else
            ClearAHLightUsageDisplay()
            AHLightUsageFrame:Hide()
        end
    end

    SetupFrames()
    UpdateCenterGCDSwipe()
end

function Meter_SetOpacity(opacity)
    MetersSavedVars.opacity = GetConfiguredOpacity()  -- validated inside
    ApplyEffectiveOpacity()
    if MarkerFrame then MarkerFrame:SetAlpha(1) end
end

function Meter_ApplyFont(fontName, size)
    local selectedFontName = fontName or GetCurrentFontName()
    local resolvedSize     = tonumber(size) or MetersSavedVars.fontSize or 18
    local fontPath         = ResolveFontPath(selectedFontName)
    -- Outline flag from the Meters "Outline" dropdown ("NONE" -> no outline). Default OUTLINE.
    local outline = tostring(MetersSavedVars.fontOutline or "OUTLINE")
    if outline ~= "OUTLINE" and outline ~= "THICKOUTLINE" then outline = (outline == "NONE") and "" or "OUTLINE" end
    SetCurrentFontName(selectedFontName)
    if DPSFrame and DPSFrame.dpsText then
        DPSFrame.dpsText:SetFont(fontPath, resolvedSize, outline)
    end
    if HPSFrame and HPSFrame.hpsText then
        HPSFrame.hpsText:SetFont(fontPath, resolvedSize, outline)
    end
    if GCD_ApplyFont then
        GCD_ApplyFont(selectedFontName, resolvedSize, outline)
    end
    if AHLightUsage_ApplyFont then
        AHLightUsage_ApplyFont(fontPath, math.max(6, resolvedSize - 2), outline)
    end
    if AHLight_ApplySize  then AHLight_ApplySize(resolvedSize) end
    if AHLight_UpdateIcon then AHLight_UpdateIcon() end
    if not UsingAHLight() then SyncMarkerState() end
    Meter_InvalidateLayout()
    SetupFrames()
    UpdateCenterGCDSwipe()
end

function Meter_ApplyRefreshRate(value)
    local rate = ClampRefreshRateValue(value or MetersSavedVars.refreshRate or 0.10)
    MetersSavedVars.refreshRate = rate
    if AHLight_ApplyRefreshRate then AHLight_ApplyRefreshRate(rate) end
    if GCD_ApplyRefreshRate then GCD_ApplyRefreshRate(rate) end
    if DPS_ApplyRefreshRate then DPS_ApplyRefreshRate(rate) end
    if HPS_ApplyRefreshRate then HPS_ApplyRefreshRate(rate) end
    if AHLightUsage_ApplyRefreshRate then AHLightUsage_ApplyRefreshRate(rate) end
end

function Meter_SetPosition(x, y)
    if InCombatLock() then return end
    x = RoundToNearest(x or 0)
    y = RoundToNearest(y or -15)
    MetersSavedVars.x = x
    MetersSavedVars.y = y
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    ApplyEffectiveOpacity()
    Meter_UpdateVisibility()
end

function Meter_ResetPosition()
    if InCombatLock() then return end
    MetersSavedVars.x = 0
    MetersSavedVars.y = -15
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -15)
    ApplyEffectiveOpacity()
    Meter_InvalidateLayout()
    SetupFrames()
    Meter_SetDisplay(
        UsingAHLight(),
        MetersSavedVars.showDPS,
        MetersSavedVars.showHPS,
        MetersSavedVars.showGCD,
        MetersSavedVars.showAHLightUsage
    )
    Meter_UpdateVisibility()
    if Meter_SyncPositionControls then Meter_SyncPositionControls() end
end

local function Meters_FullReset()
    local sv = MetersSavedVars
    sv.locked            = true
    sv.showDPS           = true
    sv.showHPS           = true
    sv.showGCD           = true
    sv.showAHLightUsage  = true
    sv.opacity           = 100
    sv.fontSize          = 18
    sv.refreshRate       = 0.10
    sv.showWhen          = "Always"
    SetCurrentFontName("Friz Quadrata TT")
    SetMarker("AHLight")
    if Marker_SetMode then Marker_SetMode("AHLight") end
    Meter_ResetPosition()
    Meter_ApplyFont(GetCurrentFontName(), sv.fontSize)
    Meter_ApplyRefreshRate(sv.refreshRate)
    Meter_SetDisplay(UsingAHLight(), sv.showDPS, sv.showHPS, sv.showGCD, sv.showAHLightUsage)
    Meter_SetLocked(sv.locked)
    Meter_SetOpacity(sv.opacity)
    Meter_UpdateVisibility()
    print("|cff00ccffMeters|r: Reset to defaults.")
end

-- ─── Drag ────────────────────────────────────────────────────────────────────
anchor:SetScript("OnDragStart", function(self)
    if IsFramePositionLocked() then return end
    self:StartMoving()
end)
anchor:SetScript("OnDragStop", SaveAnchorPosition)

-- ─── Events ──────────────────────────────────────────────────────────────────
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
eventFrame:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

-- Poll only as a safety net for mount/taxi state changes missed by events.
local elapsedTotal = 0
local actionElapsedTotal = 0
local lastMountedState = PlayerIsMounted()
local scheduledMountRefresh = nil
local scheduledActionRefresh = nil
local MOUNT_STATE_POLL_INTERVAL = 0.50
local LANDING_REFRESH_DELAY = 0.12
local ACTION_REFRESH_DELAY = 0.08

local function CancelScheduledMountRefresh()
    if scheduledMountRefresh and scheduledMountRefresh.Cancel then
        scheduledMountRefresh:Cancel()
    end
    scheduledMountRefresh = nil
end

local function CancelScheduledActionRefresh()
    if scheduledActionRefresh and scheduledActionRefresh.Cancel then
        scheduledActionRefresh:Cancel()
    end
    scheduledActionRefresh = nil
end

local function HideForMountedState()
    CancelScheduledActionRefresh()
    if ApplyUnlockedPreviewDisplay() then
        return
    end

    anchor:Hide()
    ClearCenterGCDSwipe()
    SetGCDPreviewState(false)

    if AHLightFrame then
        AHLightFrame:Hide()
    end
    if MarkerFrame then
        MarkerFrame:Hide()
    end
    if GCDFrame then
        if GCDFrame.gcdText then GCDFrame.gcdText:SetText("") end
        GCDFrame:Hide()
    end
    if AHLightUsageFrame then
        if AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:SetText("")
        end
        AHLightUsageFrame:Hide()
    end
end

local function RunUnmountedRefresh()
    scheduledMountRefresh = nil
    if PlayerIsMounted() then
        lastMountedState = true
        HideForMountedState()
        return
    end

    lastMountedState = false
    SetupFrames()
    Meter_UpdateVisibility()
    if UsingAHLight() then UpdateAHLightFrame(true) else SyncMarkerState() end
    if IsFramePositionLocked() and GCD_UpdateNow then GCD_UpdateNow() end
    UpdateCenterGCDSwipe()
    if MetersSavedVars.showAHLightUsage ~= false then UpdateAHLightUsageFrame() end
end

local function ScheduleUnmountedRefresh()
    CancelScheduledMountRefresh()
    if C_Timer and C_Timer.NewTimer then
        scheduledMountRefresh = C_Timer.NewTimer(LANDING_REFRESH_DELAY, RunUnmountedRefresh)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(LANDING_REFRESH_DELAY, RunUnmountedRefresh)
    else
        RunUnmountedRefresh()
    end
end

local function RunActionRefresh(forceIcon)
    scheduledActionRefresh = nil
    if InMountTransitionSuppress() then
        return
    end
    if PlayerIsMounted() and IsFramePositionLocked() then
        HideForMountedState()
        return
    end

    if ApplyUnlockedPreviewDisplay() then
        return
    end
    if not anchor:IsShown() then
        return
    end
    if UsingAHLight() then
        UpdateAHLightFrame(forceIcon)
    else
        SyncMarkerState()
    end
    if IsFramePositionLocked() and GCD_UpdateNow then
        GCD_UpdateNow()
    end
    UpdateCenterGCDSwipe()
    if MetersSavedVars.showAHLightUsage ~= false then
        UpdateAHLightUsageFrame()
    end
end

local function ScheduleActionRefresh(forceIcon)
    if InMountTransitionSuppress() or (PlayerIsMounted() and IsFramePositionLocked()) then
        CancelScheduledActionRefresh()
        return
    end
    CancelScheduledActionRefresh()
    if C_Timer and C_Timer.NewTimer then
        scheduledActionRefresh = C_Timer.NewTimer(ACTION_REFRESH_DELAY, function()
            RunActionRefresh(forceIcon)
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(ACTION_REFRESH_DELAY, function()
            RunActionRefresh(forceIcon)
        end)
    else
        RunActionRefresh(forceIcon)
    end
end

local function ShouldPollActionRefresh()
    if InMountTransitionSuppress() or (PlayerIsMounted() and IsFramePositionLocked()) then
        return false
    end
    if not UsingAHLight() or not AHLightFrame then
        return false
    end
    if not IsFramePositionLocked() then
        return false
    end
    return InCombatLock()
        or (AHLightFrame:IsShown() and AHLight_ShouldShow and AHLight_ShouldShow())
end

local function HandleMountStateChanged(mounted)
    mounted = mounted and true or false
    if mounted then
        if lastMountedState and not scheduledMountRefresh then
            return
        end
        lastMountedState = true
        CancelScheduledMountRefresh()
        HideForMountedState()
        return
    end

    if not lastMountedState or scheduledMountRefresh then
        return
    end

    ScheduleUnmountedRefresh()
end

-- Shared full-init helper – avoids duplicating the large block in login + C_Timer.
local function FullInit()
    lastMountedState = PlayerIsMounted()
    ApplySavedPosition()
    UpdateAnchorInteractivity()
    if AHLight_ApplySize  then AHLight_ApplySize(MetersSavedVars.fontSize) end
    if AHLight_UpdateIcon then AHLight_UpdateIcon() end
    SyncMarkerState()
    Meter_ApplyFont(GetCurrentFontName(), MetersSavedVars.fontSize or 18)
    Meter_ApplyRefreshRate(MetersSavedVars.refreshRate)
    SetupFrames()
    Meter_SetDisplay(
        UsingAHLight(),
        MetersSavedVars.showDPS,
        MetersSavedVars.showHPS,
        MetersSavedVars.showGCD,
        MetersSavedVars.showAHLightUsage
    )
    Meter_SetLocked(MetersSavedVars.locked)
    Meter_UpdateVisibility()
    if not lastMountedState then
        if UsingAHLight() then UpdateAHLightFrame(true) else UpdateMarkerFrame() end
        if IsFramePositionLocked() and GCD_UpdateNow then GCD_UpdateNow() end
    end
    Meters_GetRefreshRate()
end

local didInitialFullInit = false
local deferredFullInitTimer = nil

local function ScheduleDeferredFullInit()
    if deferredFullInitTimer and deferredFullInitTimer.Cancel then
        deferredFullInitTimer:Cancel()
    end
    deferredFullInitTimer = nil

    if C_Timer and C_Timer.NewTimer then
        deferredFullInitTimer = C_Timer.NewTimer(0.2, function()
            deferredFullInitTimer = nil
            FullInit()
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.2, FullInit)
    end
end

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal >= MOUNT_STATE_POLL_INTERVAL then
        elapsedTotal = 0

        local mounted = PlayerIsMounted()
        if mounted ~= lastMountedState then
            HandleMountStateChanged(mounted)
        end
    end

    if ShouldPollActionRefresh() then
        actionElapsedTotal = actionElapsedTotal + elapsed
        if actionElapsedTotal >= Meters_GetRefreshRate() then
            actionElapsedTotal = 0
            RunActionRefresh(false)
        end
    else
        actionElapsedTotal = 0
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local arg1 = ...
    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        if DPS_ControllerEvent then DPS_ControllerEvent(event) end
        if HPS_ControllerEvent then HPS_ControllerEvent(event) end
        if AHLightUsage_ControllerEvent then AHLightUsage_ControllerEvent(event, ...) end
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if DPS_ControllerEvent then DPS_ControllerEvent(event) end
        if HPS_ControllerEvent then HPS_ControllerEvent(event) end
    elseif event == "ASSISTED_COMBAT_ACTION_SPELL_CAST" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if AHLightUsage_ControllerEvent then AHLightUsage_ControllerEvent(event, ...) end
    end

    if event == "PLAYER_LOGIN" then
        FullInit()
        didInitialFullInit = true
        ScheduleDeferredFullInit()

    elseif event == "PLAYER_ENTERING_WORLD" then
        playerInCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
        if not didInitialFullInit then
            FullInit()
            didInitialFullInit = true
            ScheduleDeferredFullInit()
        else
            lastMountedState = PlayerIsMounted()
            if lastMountedState then
                HideForMountedState()
            else
                Meter_UpdateVisibility()
            end
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        Meter_UpdateVisibility()
        if UsingAHLight() then UpdateAHLightFrame(true) else UpdateMarkerFrame() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        playerInCombat = true
        SaveAnchorPosition()
        UpdateAnchorInteractivity()
        SetGCDPreviewState(false)
        Meter_UpdateVisibility()
        if UsingAHLight() then UpdateAHLightFrame(true) else SyncMarkerState() end
        if not PlayerIsMounted() and GCD_UpdateNow then GCD_UpdateNow() end
        UpdateCenterGCDSwipe()
        if MetersSavedVars.showAHLightUsage ~= false then UpdateAHLightUsageFrame() end
        Meters_GetRefreshRate()

    elseif event == "PLAYER_REGEN_ENABLED" then
        playerInCombat = false
        UpdateAnchorInteractivity()
        if not MetersSavedVars.locked then SetGCDPreviewState(MetersSavedVars.showGCD) end
        Meter_UpdateVisibility()
        if UsingAHLight() then UpdateAHLightFrame(true) else SyncMarkerState() end
        if not PlayerIsMounted() and MetersSavedVars.locked and GCD_UpdateNow then GCD_UpdateNow() end
        UpdateCenterGCDSwipe()
        if MetersSavedVars.showAHLightUsage ~= false then UpdateAHLightUsageFrame() end

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        ScheduleActionRefresh(false)

    elseif event == "SPELLS_CHANGED"
        or event == "ACTIONBAR_UPDATE_STATE"
        or event == "ACTIONBAR_SLOT_CHANGED" then
        ScheduleActionRefresh(true)

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        HandleMountStateChanged(PlayerIsMounted())

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 and arg1 ~= "player" then return end
        if not UsingAHLight() then SyncMarkerState(); SetupFrames() end
        UpdateCenterGCDSwipe()
        ScheduleActionRefresh(true)

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if not UsingAHLight() then SyncMarkerState(); SetupFrames() end
        UpdateCenterGCDSwipe()
        ScheduleActionRefresh(true)
    end
end)

