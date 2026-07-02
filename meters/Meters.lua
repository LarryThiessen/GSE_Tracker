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

-- Retail-only: the meters READOUTS (DPS/HPS/GCD/SBAssist/Details) and the Assisted-Highlight
-- marker mode need C_DamageMeter / C_AssistedCombat, absent on Classic. The plain Center
-- Marker still works there. MetersOK() gates the readout paths; the marker path is left alone.
-- Per-readout capability (so each can light up independently across flavors):
--   GCD     -> Blizzard cooldown read; works everywhere.
--   DPS/HPS -> retail C_DamageMeter OR the Details! addon (live-checked).
--   SBA%    -> Assisted Highlight usage; retail-only (C_AssistedCombat).
local function GCDOK()
    return _G.GSETracker_GCDCapable and true or false
end
local function DPSHPSOK()
    return (_G.GSETracker_HasDPSSource and _G.GSETracker_HasDPSSource()) and true or false
end
local function AHUsageOK()
    return (ns.Caps and ns.Caps.assistedHighlight) and true or false
end
-- The cluster is "OK" (anchor/controllers run) when ANY readout is usable.
local function MetersOK()
    return GCDOK() or DPSHPSOK()
end

local function UsingAHLight()
    return AHUsageOK() and GetMarker() == "AHLight"
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
    if value < 0.02 then return 0.02 end
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
    sv.scale        = tonumber(sv.scale) or 1
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

-- The centre icon (Marker / AHLight) is itself arrangeable on the 3x3 grid, so it rides on its OWN movable
-- point -- markerCell -- rather than the fixed iconCenter. SetupFrames moves markerCell to the Marker
-- slot's cell each layout; the icon AND its GCD swipe anchor to markerCell, so they travel together.
-- Defaults to dead-centre (the "C" cell).
local markerCell = CreateFrame("Frame", nil, anchor)
markerCell:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
markerCell:SetSize(1, 1)

-- 1x1 anchor parked at the "Personal Resource Bar" grid cell. The PRD lock (ui/personal_resource.lua)
-- reads this frame's screen centre to position Blizzard's protected PRD nameplate. Named so the lock
-- module can find it; SetupFrames re-parks it on every layout.
local prdCell = CreateFrame("Frame", "GSETracker_PRDCell", anchor)
prdCell:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
prdCell:SetSize(1, 1)
-- 1x1 anchors the native Cooldown Manager viewers (Essential/Utility) are pinned to (ui/cooldown_viewer.lua
-- reads these); SetupFrames re-parks them on every layout.
local essentialCDCell = CreateFrame("Frame", "GSETracker_EssentialCDCell", anchor)
essentialCDCell:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
essentialCDCell:SetSize(1, 1)
local utilityCDCell = CreateFrame("Frame", "GSETracker_UtilityCDCell", anchor)
utilityCDCell:SetPoint("CENTER", iconCenter, "CENTER", 0, 0)
utilityCDCell:SetSize(1, 1)

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
    if not GCDOK() then if ClearCenterGCDSwipe then ClearCenterGCDSwipe() end return end
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
        centerGCDSwipe:SetPoint("CENTER", markerCell, "CENTER", 0, 0)  -- follows the (movable) centre icon
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
    MarkerFrame:SetPoint("CENTER", markerCell, "CENTER", 0, 0)  -- markerCell follows the Marker grid slot
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
    if not AHUsageOK() then AHLightUsageFrame:Hide() return end
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
    -- Meters disabled in the options = no Edit Mode preview either (hide the whole cluster). Without this,
    -- the unlocked preview would re-show the example readouts even when Meters is turned off.
    if MetersSavedVars.enabled == false then
        anchor:Hide()
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
        if DPSHPSOK() and MetersSavedVars.showDPS ~= false then
            -- Stop any in-flight post-combat fade and restore full opacity, or the example
            -- preview would show at the fade's leftover (possibly zero) alpha.
            if GSETracker_CancelFade then GSETracker_CancelFade(DPSFrame) end
            DPSFrame.dpsText:SetText((_G.GSETracker_FormatMeterValue and _G.GSETracker_FormatMeterValue(12345)) or "12345")
            DPSFrame:Show()
        else
            DPSFrame.dpsText:SetText("")
            DPSFrame:Hide()
        end
    end

    if HPSFrame and HPSFrame.hpsText then
        if DPSHPSOK() and MetersSavedVars.showHPS ~= false then
            if GSETracker_CancelFade then GSETracker_CancelFade(HPSFrame) end
            HPSFrame.hpsText:SetText((_G.GSETracker_FormatMeterValue and _G.GSETracker_FormatMeterValue(6789)) or "6789")
            HPSFrame:Show()
        else
            HPSFrame.hpsText:SetText("")
            HPSFrame:Hide()
        end
    end

    if GCDFrame and GCDFrame.gcdText then
        if GCDOK() and MetersSavedVars.showGCD ~= false then
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
        if AHUsageOK() and MetersSavedVars.showAHLightUsage ~= false then
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
    if _G.GSETracker_EditModeActive then
        -- Edit Mode: the selection box (at MEDIUM, Blizzard's layer) is the interaction surface and drags
        -- the anchor via StartMoving -- so keep the anchor MOVABLE but give up the MOUSE, otherwise the
        -- HIGH mouse-enabled anchor would swallow the MEDIUM box's clicks.
        anchor:SetMovable(true)
        anchor:EnableMouse(false)
        if anchor.SetMouseClickEnabled  then anchor:SetMouseClickEnabled(false)  end
        if anchor.SetMouseMotionEnabled then anchor:SetMouseMotionEnabled(false) end
    elseif locked then
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
    -- While the options panel is open, sit BELOW it (LOW) so it neither grabs the mouse nor
    -- draws over the panel -- regardless of lock state. Prominent (HIGH) otherwise. (LOW, not
    -- MEDIUM: the Classic options panel sits at MEDIUM, so MEDIUM still drew over its bg.)
    local optionsOpen = _G.SettingsPanel and _G.SettingsPanel.IsShown and _G.SettingsPanel:IsShown()
    anchor:SetFrameStrata(optionsOpen and "LOW" or "HIGH")
    ApplyEffectiveOpacity()
end

-- Let ui/editmode.lua re-apply anchor interactivity when Edit Mode boxes show/hide (so the anchor yields
-- the mouse to its MEDIUM selection box while editing).
function _G.Meters_UpdateAnchorInteractivity() UpdateAnchorInteractivity() end

-- ─── Saved position ───────────────────────────────────────────────────────────
-- SetPoint offsets live in the anchor's OWN (scaled) coordinate space, so a scaled anchor would
-- MULTIPLY the offset and drift the whole cluster (e.g. the default y = -15 doubles at scale 2,
-- pushing it down). Store x/y in UIParent units (scale-independent) and divide by the anchor's
-- scale when applying, so the cluster keeps its screen position and grows about its own centre.
local function ApplySavedPosition()
    -- Player-Tracked HUD: anchor the whole cluster to the player's personal nameplate so it follows the
    -- character. Only works while that nameplate exists (needs nameplateShowSelf -- the toggle enables it);
    -- if it isn't there (no nameplate, vehicle, cinematic, ...) we fall through to the fixed screen spot.
    -- Anchoring our own (unprotected) frame to the nameplate is allowed even in combat.
    if MetersSavedVars.playerTracked then
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
        if np then
            anchor:ClearAllPoints()
            anchor:SetPoint("CENTER", np, "CENTER", 0, 0)
            return
        end
    end
    local x = RoundToNearest(MetersSavedVars.x or 0)
    local y = RoundToNearest(MetersSavedVars.y or -15)
    MetersSavedVars.x = x
    MetersSavedVars.y = y
    local s = (anchor.GetScale and anchor:GetScale()) or 1
    if not s or s == 0 then s = 1 end
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
end

-- Re-apply the anchor when the player nameplate appears/disappears, so Player-Tracked mode latches onto it
-- (ADDED) and falls back to the fixed spot when it's gone (REMOVED).
local npTrackFrame = CreateFrame("Frame")
npTrackFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
npTrackFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
npTrackFrame:SetScript("OnEvent", function(_, _, unit)
    if unit == "player" and MetersSavedVars.playerTracked then ApplySavedPosition() end
end)

-- Player-Tracked HUD toggle. Needs the personal nameplate present to follow, so enabling it also turns on
-- nameplateShowSelf (which also shows Blizzard's PRD bar -- they share the one CVar). Combat-protected CVar,
-- so only set out of combat (the options panel can't be changed in combat anyway).
function _G.Meters_GetPlayerTracked() return MetersSavedVars.playerTracked == true end
function _G.Meters_SetPlayerTracked(on)
    MetersSavedVars.playerTracked = on and true or nil
    if on and not InCombatLockdown() then pcall(SetCVar, "nameplateShowSelf", "1") end
    ApplySavedPosition()
end

local function SaveAnchorPosition()
    anchor:StopMovingOrSizing()
    local s = (anchor.GetScale and anchor:GetScale()) or 1
    if not s or s == 0 then s = 1 end
    local ax, ay = anchor:GetCenter()
    local px, py = UIParent:GetCenter()
    local x = MetersSavedVars.x or 0
    local y = MetersSavedVars.y or -15
    if ax and ay and px and py then
        -- anchor:GetCenter() is in the anchor's own (scaled) space; * its scale -> UIParent units.
        x = RoundToNearest(ax * s - px)
        y = RoundToNearest(ay * s - py)
    end
    MetersSavedVars.x = x
    MetersSavedVars.y = y
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
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

-- ─── Sub-element slots (user-arrangeable readouts) ─────────────────────────────
-- The four readouts (DPS/HPS/GCD/Usage) live in four fixed slots around the centre icon:
-- TOP / BOTTOM / LEFT / RIGHT. We persist only the SLOT NAME per readout (not pixel offsets), so the
-- arrangement is scale-free and survives icon-size / font changes -- SetupFrames recomputes each slot's
-- geometry from the live icon size every layout. In Edit Mode the user drags a readout; on drop it
-- snaps to the nearest cell, and if that cell is taken the two readouts SWAP. The arranger is a 3x3 grid
-- (9 cells); the CENTRE cell is allowed (a readout can sit over the icon). Defaults reproduce the original
-- look (DPS left, HPS right, GCD top). NOTE: AHLightUsage is NOT a meters readout -- it's an Assisted
-- Highlight element positioned at the cluster bottom (see its own block in SetupFrames), so it is NOT in
-- this slot system. The centre Marker icon, however, IS arrangeable -- it's slot id "Marker" (default "C").
--
-- 35 cells: 5 columns (LL/L/C/R/RR) x 7 rows (TTT/TT/T/M/B/XB/XXB). The inner 9 keep their ORIGINAL names
-- (TL/T/.../BR) so saved arrangements survive with no migration; the far columns (LL/RR), the extra
-- top/bottom rows (TT/XB) and now a 3rd top/bottom pair (TTT/XXB) are added. 7 rows = odd, so M is still
-- the TRUE centre row. Each cell decomposes into a column + a row, each with a position multiplier from centre.
local METER_SLOTS = {
    "TTTLL","TTTL","TTTC","TTTR","TTTRR",
    "TTLL", "TTL", "TTC", "TTR", "TTRR",
    "LLT",  "TL",  "T",   "TR",  "RRT",
    "LL",   "L",   "C",   "R",   "RR",
    "LLB",  "BL",  "B",   "BR",  "RRB",
    "XBLL", "XBL", "XBC", "XBR", "XBRR",
    "XXBLL","XXBL","XXBC","XXBR","XXBRR",
}
local METER_SLOT_SET = {}
for _, s in ipairs(METER_SLOTS) do METER_SLOT_SET[s] = true end
local SLOT_COL = {
    TTTLL="LL",TTTL="L",TTTC="C",TTTR="R",TTTRR="RR",
    TTLL= "LL", TTL= "L", TTC="C", TTR= "R", TTRR= "RR",
    LLT = "LL", TL = "L", T = "C", TR = "R", RRT = "RR",
    LL  = "LL", L  = "L", C = "C", R  = "R", RR  = "RR",
    LLB = "LL", BL = "L", B = "C", BR = "R", RRB = "RR",
    XBLL= "LL", XBL= "L", XBC="C", XBR= "R", XBRR= "RR",
    XXBLL="LL",XXBL="L",XXBC="C",XXBR="R",XXBRR="RR",
}
local SLOT_ROW = {
    TTTLL="TTT",TTTL="TTT",TTTC="TTT",TTTR="TTT",TTTRR="TTT",
    TTLL= "TT", TTL= "TT",TTC="TT",TTR= "TT",TTRR= "TT",
    LLT = "T",  TL = "T", T = "T", TR = "T", RRT = "T",
    LL  = "M",  L  = "M", C = "M", R  = "M", RR  = "M",
    LLB = "B",  BL = "B", B = "B", BR = "B", RRB = "B",
    XBLL= "XB", XBL= "XB",XBC="XB",XBR= "XB",XBRR= "XB",
    XXBLL="XXB",XXBL="XXB",XXBC="XXB",XXBR="XXB",XXBRR="XXB",
}
-- Position multipliers from centre (in "steps"). The HUD geometry below turns these into pixel offsets.
local COL_MULT = { LL = -2, L = -1, C = 0, R = 1, RR = 2 }
local ROW_MULT = { TTT = 3, TT = 2, T = 1, M = 0, B = -1, XB = -2, XXB = -3 }
-- Migrate the old 4-name scheme (pre-9-grid) so saved arrangements survive.
local LEGACY_SLOT_MAP = { TOP = "T", BOTTOM = "B", LEFT = "L", RIGHT = "R" }

-- Marker = the centre icon; it follows the same drag/swap rules as the readouts.
-- AHMatch (the "AH %" readout) is a fixed element that DEFAULTS OFF: it lives under the Action Tracker
-- until the user adds it to the grid (FixedElementOn special-cases it to off-by-default). Its default
-- cell (B) is only used once it's added. When ON the grid, the under-AT readout stands down (see
-- ui/modkey_stack.lua UpdateAHMatchReadout, gated on GSETracker_IsAHMatchSlotted).
-- PersonalResource is positional like Marker (no text frame): it locks Blizzard's protected PRD nameplate
-- to its cell at safe moments (see ui/personal_resource.lua). Default cell XBC (bottom row, centre).
-- TrackedBuffs is the "Cooldowns" bar (up to 5 chosen 30s+ spells, side by side); positional, no text frame.
local METER_SLOT_DEFAULTS = { DPS = "L", HPS = "R", GCD = "T", Marker = "C", AHMatch = "B", PlayerName = "TTC", PersonalResource = "XBC", TrackedBuffs = "XXBC", EssentialCDs = "XBC", UtilityCDs = "XXBC" }

-- id -> (global frame name created by its module, text fontstring field on that frame). The Marker is NOT
-- here -- it isn't a text readout placed by PlaceMeterElement; it has its own markerCell positioning.
local METER_ELEMENTS = {
    { id = "DPS", frame = "DPSFrame", text = "dpsText" },
    { id = "HPS", frame = "HPSFrame", text = "hpsText" },
    { id = "GCD", frame = "GCDFrame", text = "gcdText" },
    { id = "AHMatch", frame = "AHMatchFrame", text = "matchText" },
    { id = "PlayerName", frame = "PlayerNameFrame", text = "nameText" },
}

-- "Player Name" grid element -- a static, class-coloured readout of the player's name. Default OFF
-- (off the grid) like AHMatch; placed by the same machinery when added. UpdatePlayerNameText refreshes
-- the text/colour (name only changes on rename/transfer -> a /reload, so refreshing in SetupFrames is fine).
local PlayerNameFrame = CreateFrame("Frame", "PlayerNameFrame", UIParent)
PlayerNameFrame:SetSize(120, 20)
PlayerNameFrame:Hide()
PlayerNameFrame.nameText = PlayerNameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
PlayerNameFrame.nameText:SetPoint("CENTER", PlayerNameFrame, "CENTER", 0, 0)
local function UpdatePlayerNameText()
    PlayerNameFrame.nameText:SetText(UnitName("player") or "")
    local _, classFile = UnitClass("player")
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then PlayerNameFrame.nameText:SetTextColor(c.r, c.g, c.b) else PlayerNameFrame.nameText:SetTextColor(1, 1, 1) end
end

-- Offset (from iconCenter) where the centre ICON sits for a given grid cell: centred, COL_MULT/ROW_MULT
-- steps of one icon + gap out per direction (so it lines up with the readout columns/rows).
local function MarkerCellOffset(slot, iconWidth, iconHeight, gap)
    local cm = COL_MULT[SLOT_COL[slot] or "C"] or 0
    local rm = ROW_MULT[SLOT_ROW[slot] or "M"] or 0
    return cm * ((iconWidth or 0) + gap), rm * ((iconHeight or 0) + gap)
end

-- Centre offset (from iconCenter) for a non-text positional element (the PRD bar) that must line up with
-- the TEXT readouts. Mirrors PlaceMeterElement's row/column step (first step = half-icon + half-font + gap,
-- each further step = one base-font line) -- NOT MarkerCellOffset's icon step, which is ~twice as large and
-- makes the element over/undershoot the readouts the further it sits from centre.
local function MeterTextCellOffset(slot, iconWidth, iconHeight, gap)
    local cm = COL_MULT[SLOT_COL[slot] or "C"] or 0
    local rm = ROW_MULT[SLOT_ROW[slot] or "M"] or 0
    local fontSize = MetersSavedVars.fontSize or 18
    local x = 0
    if cm ~= 0 then
        local edgeX = (iconWidth > 0) and ((iconWidth / 2) + gap) or 0
        local COL_W = (fontSize * 4) + gap
        local mag = edgeX + (math.abs(cm) - 1) * COL_W
        x = (cm > 0) and mag or -mag
    end
    local y = 0
    if rm ~= 0 then
        local th = fontSize
        local mag = (iconHeight > 0) and ((iconHeight / 2) + (th / 2) + gap) or ((th / 2) + gap)
        mag = math.floor((mag + (math.abs(rm) - 1) * (th + gap)) + 0.5)
        y = (rm > 0) and mag or -mag
    end
    return x, y
end

-- Centre offset for ICON elements (cooldown items). Y matches the TEXT rows (MeterTextCellOffset) so items
-- sit at the cluster's row heights and don't shoot far above/below it; X is a symmetric step with a one-icon
-- MINIMUM so side-by-side items never overlap. (A pure icon-sized grid flew items way out; the tight text
-- columns let them overlap -- this hybrid keeps them aligned vertically and spread horizontally.)
local function MeterIconCellOffset(slot, iconWidth, iconHeight, gap)
    local cm = COL_MULT[SLOT_COL[slot] or "C"] or 0
    local rm = ROW_MULT[SLOT_ROW[slot] or "M"] or 0
    local fontSize = MetersSavedVars.fontSize or 18
    local y = 0
    if rm ~= 0 then
        local th = fontSize
        local mag = (iconHeight > 0) and ((iconHeight / 2) + (th / 2) + gap) or ((th / 2) + gap)
        mag = math.floor((mag + (math.abs(rm) - 1) * (th + gap)) + 0.5)
        y = (rm > 0) and mag or -mag
    end
    local stepX = math.max((fontSize * 2) + gap, (iconWidth or 0) + gap)
    return cm * stepX, y
end

-- Optional cooldown elements (Trinkets, Healthstone, ...) live in the slot map ONLY when placed, keyed by
-- their CooldownElements id. They're valid grid members but are NOT part of METER_SLOT_DEFAULTS.
local function OptionalElementValid(id)
    return (_G.GSETracker_CooldownElements_IsValid and _G.GSETracker_CooldownElements_IsValid(id)) or false
end

local function MeterSlots()
    local s = MetersSavedVars.slots
    if type(s) ~= "table" then s = {}; MetersSavedVars.slots = s end
    s.Usage = nil  -- legacy: Usage left the meters slot system (it's an Assisted Highlight element)
    for id, def in pairs(METER_SLOT_DEFAULTS) do
        local v = s[id]
        if LEGACY_SLOT_MAP[v] then v = LEGACY_SLOT_MAP[v]; s[id] = v end  -- old TOP/BOTTOM/LEFT/RIGHT -> T/B/L/R
        if not METER_SLOT_SET[v] then s[id] = def end
    end
    -- Drop any optional element whose id is no longer valid or whose cell is invalid (collect-then-delete
    -- so we never remove keys mid-pairs).
    local drop
    for id, v in pairs(s) do
        if not METER_SLOT_DEFAULTS[id] and not (OptionalElementValid(id) and METER_SLOT_SET[v]) then
            drop = drop or {}; drop[#drop + 1] = id
        end
    end
    if drop then for _, id in ipairs(drop) do s[id] = nil end end
    return s
end

local function MeterElementInSlot(slot)
    for id, sl in pairs(MeterSlots()) do
        if sl == slot then return id end
    end
end

-- Ids of currently-placed optional elements (stable, sorted order).
local function PlacedOptionalIds()
    local out = {}
    for id, cell in pairs(MeterSlots()) do
        if not METER_SLOT_DEFAULTS[id] and METER_SLOT_SET[cell] then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- Move `id` into `slot`. If another readout already holds it, that readout takes `id`'s old slot (swap).
local function MeterAssignSlot(id, slot)
    local s = MeterSlots()
    local from = s[id]
    if from == slot then return end
    local occupant = MeterElementInSlot(slot)
    if occupant and occupant ~= id then s[occupant] = from end
    s[id] = slot
end

function Meter_ResetSlots()
    local s = MeterSlots()
    for id, def in pairs(METER_SLOT_DEFAULTS) do s[id] = def end
    Meter_InvalidateLayout()
    if SetupFrames then SetupFrames() end
    if ApplyUnlockedPreviewDisplay then ApplyUnlockedPreviewDisplay() end
    if _G.GSETracker_RefitMetersBox then _G.GSETracker_RefitMetersBox() end  -- resize the Edit Mode box
end

-- Concatenate the assignments -- folded into the layout cache key so a swap forces a re-layout.
function Meter_SlotKey()
    local s = MeterSlots()
    return (s.DPS or "") .. (s.HPS or "") .. (s.GCD or "") .. (s.Marker or "") .. (s.AHMatch or "") .. (s.PlayerName or "")
end

local function MeterTextHeight(fs)
    local fallback = MetersSavedVars.fontSize or 18
    if not fs then return fallback end
    -- Derive height from the FONT size, NEVER GetStringHeight(): a readout whose text came from
    -- C_DamageMeter (DPS/HPS) has a "secret" string height that THROWS on comparison while our code is
    -- tainted (same guard as ui/editmode.lua FitMetersBox). The font size is a plain number set by us and
    -- is close enough for the vertical slot offset. pcall-wrapped in case the font isn't applied yet.
    local ok, _, size = pcall(fs.GetFont, fs)
    return (ok and tonumber(size)) or fallback
end

-- Place ONE readout, centred at the (x, y) centre of its grid cell. The content-aware grid (ComputeMeterGrid)
-- has already sized every column/row to its widest/tallest member, so cells never overlap and centring the
-- text is safe. (x, y) come from CellXY(grid, slot) in SetupFrames.
local function PlaceMeterElement(frame, textField, x, y)
    if not frame then return end
    frame:SetParent(anchor)
    frame:SetFrameLevel(11)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", iconCenter, "CENTER", x, y)
    local fs = frame[textField]
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
    end
end

-- ── Removable elements (fixed readouts/marker + optional cooldowns) ──────────
-- DPS/HPS/GCD/Marker can be removed from the grid (right-click) and re-added from the "+" list, like the
-- optional cooldown elements. "On the grid" maps onto each one's existing visibility: DPS/HPS/GCD follow
-- their show flag (so the Readouts dropdown stays in sync), the Marker follows markerHidden (gated in
-- ui/player_tracker.lua ShouldShowCombatMarker). They keep their saved cell while hidden, so re-adding
-- restores the spot.
local FIXED_SHOW_KEY = { DPS = "showDPS", HPS = "showHPS", GCD = "showGCD", AHMatch = "showAHMatch", PlayerName = "showPlayerName", PersonalResource = "showPRD", TrackedBuffs = "showTrackedBuffs", EssentialCDs = "showEssentialCDs", UtilityCDs = "showUtilityCDs" }
local FIXED_ORDER    = { "GCD", "DPS", "HPS", "AHMatch", "PlayerName", "PersonalResource", "EssentialCDs", "UtilityCDs", "TrackedBuffs", "Marker" }

-- Elements that need a capability the flavor may lack: AH % needs C_AssistedCombat; PRD pins only on Retail.
-- When the cap is absent the element is never "on" (below) and never offered (Meter_GetAvailableElements).
local FIXED_ELEMENT_CAP = { AHMatch = "assistedHighlight", PersonalResource = "prd", EssentialCDs = "cooldownManager", UtilityCDs = "cooldownManager" }

local function FixedElementOn(id)
    local reqCap = FIXED_ELEMENT_CAP[id]
    if reqCap and not (ns.Caps and ns.Caps[reqCap]) then return false end
    if id == "Marker" then return not MetersSavedVars.markerHidden end
    -- These fixed elements DEFAULT OFF (off the grid until the user adds them).
    if id == "AHMatch" then return MetersSavedVars.showAHMatch == true end
    if id == "PlayerName" then return MetersSavedVars.showPlayerName == true end
    if id == "PersonalResource" then return MetersSavedVars.showPRD == true end
    if id == "EssentialCDs" then return MetersSavedVars.showEssentialCDs == true end
    if id == "UtilityCDs" then return MetersSavedVars.showUtilityCDs == true end
    -- The custom Cooldowns bar is the Classic-only fallback; on Retail the native Cooldown Manager
    -- viewers (Essential/Utility) replace it, so it never renders there.
    if id == "TrackedBuffs" then
        if ns.Caps and ns.Caps.cooldownManager then return false end
        return MetersSavedVars.showTrackedBuffs == true
    end
    local k = FIXED_SHOW_KEY[id]
    if k then return MetersSavedVars[k] ~= false end
    return true
end

-- True when "AH %" has been placed on the Layout Control grid (so the under-AT readout stands down).
function _G.GSETracker_IsAHMatchSlotted()
    return MetersSavedVars.showAHMatch == true
end

-- The Player Name element duplicates Blizzard's "My Name" nameplate option (CVar UnitNameOwn) shown on the
-- personal nameplate. So while our Player Name is on the grid, turn UnitNameOwn OFF (no doubled name) and
-- restore the player's original setting when it's removed. We capture the original ONCE (persisted in the SV
-- so a reload doesn't capture our own "0"). The CVar is nameplate-protected -> only set out of combat (grid
-- edits happen in the options panel, which is out of combat).
local function ApplyPlayerNameCVar()
    if InCombatLockdown() then return end
    if MetersSavedVars.showPlayerName == true then
        if MetersSavedVars.nameOwnSaved == nil then
            MetersSavedVars.nameOwnSaved = GetCVar("UnitNameOwn") or "1"   -- the player's real setting, once
        end
        pcall(SetCVar, "UnitNameOwn", "0")
    elseif MetersSavedVars.nameOwnSaved ~= nil then
        pcall(SetCVar, "UnitNameOwn", MetersSavedVars.nameOwnSaved)
        MetersSavedVars.nameOwnSaved = nil
    end
end

local function SetFixedElementOn(id, on)
    if id == "Marker" then
        MetersSavedVars.markerHidden = (not on) or nil
    else
        local k = FIXED_SHOW_KEY[id]
        if k then MetersSavedVars[k] = on and true or false end
    end
end

-- Re-layout + re-apply readout visibility + refit the Edit Mode box after any grid change. (The combat
-- marker -- a separate system -- is refreshed by the caller, e.g. the arranger's RefreshCenterMarker.)
local function AfterGridChange()
    Meter_InvalidateLayout()
    if SetupFrames then SetupFrames() end
    if ApplyUnlockedPreviewDisplay then ApplyUnlockedPreviewDisplay() end
    if _G.Meters_ApplyDisplayToggles then _G.Meters_ApplyDisplayToggles() end
    if _G.GSETracker_RefitMetersBox then _G.GSETracker_RefitMetersBox() end
    -- AH %% toggles between its grid slot and the under-Action-Tracker spot -- refresh it on any grid change.
    if _G.GSETracker_UpdateAHMatchReadout then _G.GSETracker_UpdateAHMatchReadout() end
    -- Re-lock the protected PRD nameplate to its cell (no-op if not slotted / out of combat handled there).
    if _G.GSETracker_LockPersonalResource then _G.GSETracker_LockPersonalResource() end
end

-- True when "Personal Resource Bar" is on the Layout Control grid (the PRD lock module gates on this).
function _G.GSETracker_IsPRDSlotted()
    return MetersSavedVars.showPRD == true
end

-- True when the native Cooldown Manager viewers are slotted (the cooldown_viewer lock module gates on these).
function _G.GSETracker_IsEssentialCDsSlotted() return MetersSavedVars.showEssentialCDs == true end
function _G.GSETracker_IsUtilityCDsSlotted()   return MetersSavedVars.showUtilityCDs == true end

-- Which screen SIDE a native Cooldown viewer sits on, from its grid cell. The lock module centres the block on
-- the cell and rotates its icon fill/stack direction by side so the whole element turns like a clock as it
-- moves around the grid (never a 180 flip): left/right columns -> vertical, top/bottom -> horizontal.
-- Returns "LEFT" / "RIGHT" / "TOP" / "BOTTOM".
function _G.GSETracker_CDViewerGrowth(slotKey)
    local slot = MeterSlots()[slotKey]
    local col  = COL_MULT[SLOT_COL[slot or ""] or "C"] or 0
    local row  = ROW_MULT[SLOT_ROW[slot or ""] or "M"] or 0
    if col < 0 then return "LEFT"  end
    if col > 0 then return "RIGHT" end
    if row > 0 then return "TOP"   end
    return "BOTTOM"
end

-- Half-extents (halfW, halfH) of the VISIBLE readout cluster, centred on MetersAnchor -- so the cooldown lock
-- module can butt the native viewers against the cluster edge (anchorCentre +/- half). Mirrors the measurement
-- the Edit Mode box uses (union of the placed readout frames; DPS/HPS geometry is "secret" so each read is
-- pcall-guarded). Measured OUT OF COMBAT only and cached, so a secret/partial in-combat read can't jitter it.
local clusterHW, clusterHH = 90, 35   -- fallback (~180x70 cluster)
function _G.GSETracker_MetersClusterHalfExtents()
    local a = _G.MetersAnchor
    if a and a.GetLeft and not InCombatLockdown() then
        pcall(function()
            local aL, aR, aT, aB = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom()
            if not (aL and aR and aT and aB) then error("noanchor") end
            local minL, maxR, maxT, minB
            local function add(c)
                if not (c and c.IsShown and c:IsShown() and c.GetLeft) then return end
                pcall(function()
                    local w = c:GetWidth(); if not w or w <= 1 then return end
                    local l, r, t, b = c:GetLeft(), c:GetRight(), c:GetTop(), c:GetBottom()
                    if not (l and r and t and b) then return end
                    minL = minL and math.min(minL, l) or l; maxR = maxR and math.max(maxR, r) or r
                    maxT = maxT and math.max(maxT, t) or t; minB = minB and math.min(minB, b) or b
                end)
            end
            add(_G.GCDFrame and _G.GCDFrame.gcdText);   add(_G.DPSFrame and _G.DPSFrame.dpsText)
            add(_G.HPSFrame and _G.HPSFrame.hpsText);   add(_G.AHMatchFrame and _G.AHMatchFrame.matchText)
            add(_G.PlayerNameFrame and _G.PlayerNameFrame.nameText)
            add(_G.AHLightFrame); add(_G.MarkerFrame)
            if _G.GSETracker_CooldownElements_ForEachShown then _G.GSETracker_CooldownElements_ForEachShown(add) end
            if not minL then error("nokids") end
            local pad = 8
            local cx, cy = (aL + aR) / 2, (aT + aB) / 2
            clusterHW = math.max((maxR + pad) - cx, cx - (minL - pad))
            clusterHH = math.max((maxT + pad) - cy, cy - (minB - pad))
        end)
    end
    return clusterHW, clusterHH
end

-- Assign `id` to a 3x3 grid `slot` (TL/T/TR/L/C/R/BL/B/BR), swapping any occupant. Placing a fixed element
-- also turns it back ON. Works for fixed AND optional ids. Returns the slot map.
function Meter_SetElementSlot(id, slot)
    if not ((METER_SLOT_DEFAULTS[id] or OptionalElementValid(id)) and METER_SLOT_SET[slot]) then
        return MeterSlots()
    end
    if METER_SLOT_DEFAULTS[id] then SetFixedElementOn(id, true) end
    MeterAssignSlot(id, slot)
    if id == "PersonalResource" and _G.GSETracker_SetPRDEnabled then _G.GSETracker_SetPRDEnabled(true) end
    if id == "PlayerName" then ApplyPlayerNameCVar() end   -- hide Blizzard's "My Name" so it's not doubled
    AfterGridChange()
    return MeterSlots()
end

-- Remove an element from the grid: fixed -> turn its visibility off (keeps its cell for re-add); optional
-- -> drop it from the slot map + hide its widget. Returns the slot map.
function Meter_RemoveElement(id)
    if METER_SLOT_DEFAULTS[id] then
        SetFixedElementOn(id, false)
        if id == "PersonalResource" and _G.GSETracker_SetPRDEnabled then _G.GSETracker_SetPRDEnabled(false) end
        if id == "PlayerName" then ApplyPlayerNameCVar() end   -- restore the player's "My Name" setting
    elseif OptionalElementValid(id) then
        local s = MeterSlots()
        if s[id] == nil then return s end
        s[id] = nil
        if _G.GSETracker_CooldownElements_Hide then _G.GSETracker_CooldownElements_Hide(id) end
    else
        return MeterSlots()
    end
    AfterGridChange()
    return MeterSlots()
end

-- Elements NOT currently on the grid -- the "+" add list: removed fixed elements first (stable order),
-- then unplaced optional elements. {id,label}.
function Meter_GetAvailableElements()
    local out, s = {}, MeterSlots()
    for _, id in ipairs(FIXED_ORDER) do
        -- Don't offer an element whose capability the flavor lacks (AH % needs C_AssistedCombat; PRD pins
        -- only on Retail).
        local reqCap = FIXED_ELEMENT_CAP[id]
        if reqCap and not (ns.Caps and ns.Caps[reqCap]) then
            -- skip: flavor lacks the capability
        elseif id == "TrackedBuffs" and ns.Caps and ns.Caps.cooldownManager then
            -- skip: native Cooldown Manager replaces the custom Cooldowns bar on Retail
        elseif not FixedElementOn(id) then
            out[#out + 1] = { id = id, label = Meter_ElementLabel(id) }
        end
    end
    if _G.GSETracker_CooldownElements_List then
        for _, e in ipairs(_G.GSETracker_CooldownElements_List()) do
            -- Hide it if already on the grid OR already in the Cooldowns bar (no duplicate display).
            local inBar = _G.GSETracker_TrackedCooldowns_IsAssigned and _G.GSETracker_TrackedCooldowns_IsAssigned(e.id)
            if s[e.id] == nil and not inBar then out[#out + 1] = e end
        end
    end
    return out
end

function Meter_IsOptionalElement(id) return not METER_SLOT_DEFAULTS[id] end

-- True if an optional element id is currently placed as a standalone cell on the grid (used by the Cooldowns
-- bar picker to avoid offering an element that's already shown elsewhere).
function _G.Meter_IsOptionalPlaced(id)
    return (not METER_SLOT_DEFAULTS[id]) and MeterSlots()[id] ~= nil
end

-- Display label for any element id (readout labels are literal; optional elements come from the registry).
function Meter_ElementLabel(id)
    if id == "AHMatch" then return "AH %" end
    if id == "PlayerName" then return "Player Name" end
    if id == "PersonalResource" then return "PRD" end
    if id == "EssentialCDs" then return "Essential" end
    if id == "UtilityCDs" then return "Utility" end
    if id == "TrackedBuffs" then return "Cooldowns" end
    if METER_SLOT_DEFAULTS[id] then return id end
    return (_G.GSETracker_CooldownElements_Label and _G.GSETracker_CooldownElements_Label(id)) or id
end

-- Snapshot of the slot map (id -> slot) of elements currently ON the grid: shown fixed elements + placed
-- optional elements. (Removed fixed elements are excluded so they appear as "+" cells, not chips.)
function Meter_GetElementSlots()
    local s, out = MeterSlots(), {}
    for id in pairs(METER_SLOT_DEFAULTS) do
        if FixedElementOn(id) then out[id] = s[id] end
    end
    for _, id in ipairs(PlacedOptionalIds()) do out[id] = s[id] end
    return out
end

-- ── Layout padding (X/Y gap between grid cells) ──────────────────────────────
-- User-tunable horizontal/vertical gap added between grid cells (Meters HUD panel). Clamped 0..10; default 0
-- (no extra gap) -- the player bumps it up in the Meters panel if they want spacing, and the change saves to SV.
local function PaddingX()
    local v = tonumber(MetersSavedVars.paddingX); if not v then return 0 end
    return math.max(0, math.min(10, v))
end
local function PaddingY()
    local v = tonumber(MetersSavedVars.paddingY); if not v then return 0 end
    return math.max(0, math.min(10, v))
end
function _G.Meter_GetPaddingX() return PaddingX() end
function _G.Meter_GetPaddingY() return PaddingY() end
local function ApplyPaddingChange()
    Meter_InvalidateLayout()
    if SetupFrames then SetupFrames() end
    if _G.GSETracker_RefitMetersBox then _G.GSETracker_RefitMetersBox() end
    if addon and addon.RefreshCombatMarker then pcall(addon.RefreshCombatMarker, addon, false) end
end
function _G.Meter_SetPaddingX(v)
    MetersSavedVars.paddingX = math.max(0, math.min(10, tonumber(v) or 0)); ApplyPaddingChange()
end
function _G.Meter_SetPaddingY(v)
    MetersSavedVars.paddingY = math.max(0, math.min(10, tonumber(v) or 0)); ApplyPaddingChange()
end

-- ── Content-aware grid ──────────────────────────────────────────────────────
-- Each COLUMN's width = its widest member, each ROW's height = its tallest; cells are laid out cumulatively
-- out from the centre cell (C/M); every element is centred in its cell. So big items (icons) make their
-- row/column bigger and smaller items just sit centred inside -- no overlap, no flying out. Footprints are
-- font/icon estimates (never measured: DPS/HPS width+height are "secret" and throw on read while tainted).
-- gapX/gapY (PaddingX/PaddingY) are added between cells. Returns colX[cm] / rowY[rm] centre-offset tables.
local function ComputeMeterGrid(slots, iconSize, fontSize, gap)
    -- Every column/row starts at a MINIMUM size (not 0) so EMPTY cells still occupy their slot -- otherwise
    -- empty interior rows/columns collapse and the HUD drifts out of sync with the Layout Control schematic
    -- (which shows every cell). Content (icons/text) expands a cell beyond the minimum via note().
    local minColW = fontSize * 3
    local minRowH = fontSize
    local colW, rowH = {}, {}
    for c = -2, 2 do colW[c] = minColW end
    for r = -3, 3 do rowH[r] = minRowH end
    local function note(slot, w, h)
        local c = COL_MULT[SLOT_COL[slot] or "C"] or 0
        local r = ROW_MULT[SLOT_ROW[slot] or "M"] or 0
        if w > colW[c] then colW[c] = w end
        if h > rowH[r] then rowH[r] = h end
    end
    -- Footprints are FIXED font-based estimates (never the live text width -- DPS/HPS width is "secret", and
    -- a measured width would shuffle the grid as the numbers change in combat). DPS/HPS get extra headroom so
    -- the biggest abbreviated number (e.g. "999.9K") fits the fixed cell without overflowing into neighbours.
    local th = fontSize                                   -- text line height
    if FixedElementOn("DPS")              then note(slots.DPS,        fontSize * 4, th) end
    if FixedElementOn("HPS")              then note(slots.HPS,        fontSize * 4, th) end
    if FixedElementOn("GCD")              then note(slots.GCD,        fontSize * 3, th) end
    if FixedElementOn("AHMatch")          then note(slots.AHMatch,    fontSize * 4, th) end
    if FixedElementOn("PlayerName")       then note(slots.PlayerName, fontSize * 4, th) end
    if FixedElementOn("PersonalResource") then
        -- Use the PRD bar's REAL height (it's a thin bar, not a full icon) so its row isn't over-tall.
        -- The PRD is a PROTECTED nameplate frame: in combat its GetHeight() can return a "secret"
        -- (taint-protected) value, and comparing it (ph <= 1) then THROWS -- which aborted the whole
        -- SetupFrames layout mid-way, leaving Player Name (and everything placed after this) unplaced,
        -- and poisoning the layout cache so it never recovered. pcall the read+compare; fall back to the
        -- icon size when the height is unreadable.
        local ph = iconSize
        local prd = _G.PersonalResourceDisplayFrame
        if prd and prd.GetHeight then
            local ok, h = pcall(function()
                local v = prd:GetHeight()
                if type(v) == "number" and v > 1 then return v end
                return nil
            end)
            if ok and h then ph = h end
        end
        note(slots.PersonalResource, iconSize * 2, ph)
    end
    -- Essential/Utility CD viewers contribute NO footprint: they pin to their cell centre and overflow the
    -- grid freely in every direction, so placing one never resizes the surrounding rows/columns.
    -- TrackedBuffs (the Cooldowns bar). HORIZONTAL (off the centre row): contributes only ROW HEIGHT -- the
    -- bar spans the row centred on its cell and overflows horizontally by design (width 0 = no column impact).
    -- VERTICAL (centre row -- the DPS/Marker/HPS line): the bar stacks instead so it doesn't spill across the
    -- readouts, reserving COLUMN WIDTH and overflowing vertically (height 0) -- mirrors the horizontal case.
    if FixedElementOn("TrackedBuffs") then
        if SLOT_ROW[slots.TrackedBuffs] == "M" then
            note(slots.TrackedBuffs, iconSize, 0)
        else
            note(slots.TrackedBuffs, 0, iconSize)
        end
    end
    note(slots.Marker, iconSize, iconSize)               -- centre icon always occupies its cell
    for _, id in ipairs(PlacedOptionalIds()) do note(slots[id], iconSize, iconSize) end

    local gapX = PaddingX()
    local gapY = PaddingY()
    local colX, rowY = { [0] = 0 }, { [0] = 0 }
    for c = 1, 2       do colX[c] = colX[c - 1] + (colW[c - 1] + colW[c]) / 2 + gapX end
    for c = -1, -2, -1 do colX[c] = colX[c + 1] - (colW[c + 1] + colW[c]) / 2 - gapX end
    for r = 1, 3       do rowY[r] = rowY[r - 1] + (rowH[r - 1] + rowH[r]) / 2 + gapY end
    for r = -1, -3, -1 do rowY[r] = rowY[r + 1] - (rowH[r + 1] + rowH[r]) / 2 - gapY end
    return colX, rowY
end

local function CellXY(colX, rowY, slot)
    local c = COL_MULT[SLOT_COL[slot] or "C"] or 0
    local r = ROW_MULT[SLOT_ROW[slot] or "M"] or 0
    return colX[c] or 0, rowY[r] or 0
end

-- The (x, y) the centre marker should shift by for its assigned grid cell. The visible centre marker is
-- usually the COMBAT marker (ui/player_tracker.lua); ApplyCombatMarkerPosition adds this so the "Marker"
-- chip moves the real marker. Uses the same content grid as SetupFrames so it lands on the same spot.
function Meter_GetMarkerCellOffset()
    local w = GetCenterFrameSize()
    local isize = math.max(16, math.floor(((w and w > 0 and w) or 24) + 0.5))
    local colX, rowY = ComputeMeterGrid(MeterSlots(), isize, MetersSavedVars.fontSize or 18, 3)
    return CellXY(colX, rowY, MeterSlots().Marker)
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

    -- GCD / Usage text heights (for the layout cache key). Font-size based via MeterTextHeight -- NOT
    -- GetStringHeight(), whose value is "secret" (and throws on comparison) once a readout shows
    -- C_DamageMeter / C_AssistedCombat data while our code is tainted.
    local gcdTextHeight   = MeterTextHeight(GCDFrame and GCDFrame.gcdText)
    local usageTextHeight = MeterTextHeight(AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText)

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
        tostring(Meter_SlotKey()),
    }, ":")

    if lastLayoutKey == layoutKey and not needsAnchorLayout then
        UpdateCenterGCDSwipe()
        return
    end
    -- NOTE: lastLayoutKey is set at the END of this function, not here -- so if any read below throws
    -- (e.g. a "secret" protected-frame geometry value in combat), the cache is NOT marked done and the
    -- next call re-runs the full layout instead of skipping it forever ("poisoned" cache).

    local slots = MeterSlots()

    -- Build the content-aware grid once: columns/rows sized to their widest/tallest member; everything is
    -- placed at its cell centre via CellXY. iconSize = the centre icon footprint (also used for placed items).
    local isize = math.max(16, math.floor((iconWidth > 0 and iconWidth or GetCenterFrameSize()) + 0.5))
    local colX, rowY = ComputeMeterGrid(slots, isize, MetersSavedVars.fontSize or 18, gap)

    -- Move the centre-icon cell to the Marker's assigned grid cell. The icon (AHLight/Marker) and its GCD
    -- swipe all anchor to markerCell, so they follow it together.
    local mcx, mcy = CellXY(colX, rowY, slots.Marker)
    markerCell:ClearAllPoints()
    markerCell:SetPoint("CENTER", iconCenter, "CENTER", mcx, mcy)

    -- Park the PRD + Cooldown Manager lock anchors at their cells so the lock modules can read the screen pos.
    local pcx, pcy = CellXY(colX, rowY, slots.PersonalResource)
    prdCell:ClearAllPoints()
    prdCell:SetPoint("CENTER", iconCenter, "CENTER", pcx, pcy)
    local ecx, ecy = CellXY(colX, rowY, slots.EssentialCDs)
    essentialCDCell:ClearAllPoints()
    essentialCDCell:SetPoint("CENTER", iconCenter, "CENTER", ecx, ecy)
    local ucx, ucy = CellXY(colX, rowY, slots.UtilityCDs)
    utilityCDCell:ClearAllPoints()
    utilityCDCell:SetPoint("CENTER", iconCenter, "CENTER", ucx, ucy)
    if _G.GSETracker_LockCooldownViewers then _G.GSETracker_LockCooldownViewers() end

    if AHLightFrame then
        AHLightFrame:SetParent(anchor)
        AHLightFrame._gnomesterLayoutAnchor = anchor
        AHLightFrame:SetFrameLevel(11)
        AHLightFrame:ClearAllPoints()
        AHLightFrame:SetPoint("CENTER", markerCell, "CENTER", 0, 0)
    end

    if not usingAHLight and MarkerFrame then
        MarkerFrame:SetParent(anchor)
        MarkerFrame._gnomesterLayoutAnchor = anchor
        MarkerFrame:SetFrameLevel(11)
        MarkerFrame:ClearAllPoints()
        MarkerFrame:SetPoint("CENTER", markerCell, "CENTER", 0, 0)
        MarkerFrame:SetAlpha(1)
    end

    -- Place the readouts (DPS/HPS/GCD/AH%/Player Name) at their grid-cell centres.
    for _, e in ipairs(METER_ELEMENTS) do
        local ex, ey = CellXY(colX, rowY, slots[e.id])
        PlaceMeterElement(_G[e.frame], e.text, ex, ey)
    end

    -- Player Name is static: refresh its text/colour and show it only while it's on the grid. (AH% owns
    -- its own show/value via UpdateAHMatchReadout; DPS/HPS/GCD are shown by their modules + Meter_SetDisplay.)
    UpdatePlayerNameText()
    PlayerNameFrame:SetShown(FixedElementOn("PlayerName"))

    -- Place any optional cooldown elements (Trinkets, Healthstone, ...) at their grid-cell centres. Their
    -- icon footprint sized the row/column (in ComputeMeterGrid), so they sit centred without overlapping.
    if _G.GSETracker_CooldownElements_Ensure then
        for _, id in ipairs(PlacedOptionalIds()) do
            local f = _G.GSETracker_CooldownElements_Ensure(id, anchor)
            if f then
                f:SetParent(anchor)
                f:SetFrameLevel(12)
                f:SetSize(isize, isize)
                f:ClearAllPoints()
                local ox, oy = CellXY(colX, rowY, slots[id])
                f:SetPoint("CENTER", iconCenter, "CENTER", ox, oy)
                -- Adopt the action-bar skin (frame art + mask + crop) so items match the rest of the UI.
                if _G.GSETracker_SkinAdoptedIcon then _G.GSETracker_SkinAdoptedIcon(f) end
                f:Show()
                if _G.GSETracker_CooldownElements_Update then _G.GSETracker_CooldownElements_Update(id) end
            end
        end
    end

    -- Cooldowns bar (TrackedBuffs): render up to N chosen 30s+ spells, NO padding, centred at the cell.
    -- HORIZONTAL (off the centre row) = icons left->right; VERTICAL (centre row -- the DPS/Marker/HPS line)
    -- = icons top->bottom, so a wide bar doesn't spill across the readouts. The swipe + number are
    -- engine-drawn. Hidden (widgets parked) when not slotted.
    if _G.GSETracker_TrackedCooldowns_Ensure and FixedElementOn("TrackedBuffs") then
        local n  = (_G.GSETracker_TrackedCooldowns_Count and _G.GSETracker_TrackedCooldowns_Count()) or 5
        local bx, by = CellXY(colX, rowY, slots.TrackedBuffs)
        local vertical = (SLOT_ROW[slots.TrackedBuffs] == "M")
        local startX = bx - (n * isize) / 2 + isize / 2     -- centre of the FIRST icon (left, horizontal)
        local startY = by + (n * isize) / 2 - isize / 2     -- centre of the FIRST icon (top,  vertical)
        for i = 1, n do
            local f = _G.GSETracker_TrackedCooldowns_Ensure(i, anchor)
            if f then
                f:SetParent(anchor); f:SetFrameLevel(12); f:SetSize(isize, isize)
                f:ClearAllPoints()
                if vertical then
                    f:SetPoint("CENTER", iconCenter, "CENTER", bx, startY - (i - 1) * isize)  -- stacked, no gap
                else
                    f:SetPoint("CENTER", iconCenter, "CENTER", startX + (i - 1) * isize, by)  -- side by side, no gap
                end
                if _G.GSETracker_SkinAdoptedIcon then _G.GSETracker_SkinAdoptedIcon(f) end
                f:Show()
                _G.GSETracker_TrackedCooldowns_Update(i)
            end
        end
    elseif _G.GSETracker_TrackedCooldowns_HideAll then
        _G.GSETracker_TrackedCooldowns_HideAll()
    end

    -- AHLightUsage is NOT a meters readout (it's an Assisted Highlight element); it keeps its own fixed
    -- spot at the cluster bottom, independent of the DPS/HPS/GCD arranger.
    if AHLightUsageFrame then
        AHLightUsageFrame:SetParent(anchor)
        AHLightUsageFrame:SetFrameLevel(11)
        AHLightUsageFrame:ClearAllPoints()
        local uth = MeterTextHeight(AHLightUsageFrame.ahLightUsageText)
        local uy  = (iconHeight > 0)
            and -math.floor(((iconHeight / 2) + (uth / 2) + gap) + 0.5)
            or  -math.floor(((uth / 2) + gap) + 0.5)
        AHLightUsageFrame:SetPoint("CENTER", iconCenter, "CENTER", 0, uy)
        if AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:ClearAllPoints()
            AHLightUsageFrame.ahLightUsageText:SetPoint("CENTER", AHLightUsageFrame, "CENTER", 0, 0)
            AHLightUsageFrame.ahLightUsageText:SetJustifyH("CENTER")
        end
    end

    UpdateCenterGCDSwipe()
    lastLayoutKey = layoutKey   -- mark the cache done only AFTER a full, successful layout (see note above)
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

    -- Classic: the Center Marker is shown above; keep all readouts hidden (they need
    -- retail-only data APIs). The marker path (SyncMarkerState) already ran.
    if not MetersOK() then
        if DPSFrame then DPSFrame:Hide() end
        if HPSFrame then HPSFrame:Hide() end
        if GCDFrame then GCDFrame:Hide() end
        if AHLightUsageFrame then AHLightUsageFrame:Hide() end
    end
    UpdateCenterGCDSwipe()
    UpdateAnchorInteractivity()
    -- Cooldowns bar follows the HUD's visibility (showWhen): shown only when the anchor is shown AND the
    -- element is on the grid; hidden otherwise (matches the readouts instead of lingering on its own).
    if _G.GSETracker_TrackedCooldowns_SetShown then
        _G.GSETracker_TrackedCooldowns_SetShown(anchor:IsShown() and FixedElementOn("TrackedBuffs"))
    end
    -- If the PRD is slotted in the Meters HUD, mirror the HUD's visibility onto it (alpha lever -- works in
    -- combat too, unlike Hide on a protected nameplate frame).
    if _G.GSETracker_SyncPRDVisibility then _G.GSETracker_SyncPRDVisibility() end
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

    -- nil = "keep saved value"; an explicit false must survive (the `and/or` idiom would
    -- silently turn false back into the saved value).
    if showDPS          == nil then showDPS          = MetersSavedVars.showDPS end
    if showHPS          == nil then showHPS          = MetersSavedVars.showHPS end
    if showGCD          == nil then showGCD          = MetersSavedVars.showGCD end
    if showAHLightUsage == nil then showAHLightUsage = MetersSavedVars.showAHLightUsage end

    MetersSavedVars.showDPS          = showDPS
    MetersSavedVars.showHPS          = showHPS
    MetersSavedVars.showGCD          = showGCD
    MetersSavedVars.showAHLightUsage = showAHLightUsage
    SyncLegacyShowAHLight()

    if ApplyUnlockedPreviewDisplay() then
        return
    end

    -- nil = ON (default), matching every other showDPS/showHPS read (e.g. ApplyUnlockedPreviewDisplay,
    -- the layout cache key). Using the bare value treated an unset (nil) SavedVar as OFF, so DPS/HPS
    -- never showed on a fresh profile. Only an explicit false hides.
    if DPSFrame then DPSFrame:SetShown(DPSHPSOK() and showDPS ~= false) end
    if HPSFrame then HPSFrame:SetShown(DPSHPSOK() and showHPS ~= false) end

    if GCDFrame and not GCDOK() then
        SetGCDPreviewState(false)
        if GCDFrame.gcdText then GCDFrame.gcdText:SetText("") end
        GCDFrame:Hide()
    elseif GCDFrame then
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
    -- The Center Marker isn't a child of the Meters anchor, so it won't inherit the opacity --
    -- nudge it to re-apply (it folds the Meters opacity into its own alpha).
    if _G.GSETracker_RefreshCenterMarker then _G.GSETracker_RefreshCenterMarker() end
end

-- ─── Scale ──────────────────────────────────────────────────────────────────
-- The Meters Scale slider sizes the whole readout cluster (DPS/HPS/GCD/% text) by scaling the
-- anchor every readout frame is reparented onto. The master/overall addon scale multiplies on
-- top, so the on-screen size = MetersScale * OverallScale.
local function ClampMetersScale(v)
    -- 0..2.0 (= 0..200% in the UI; 1.0/100% is the normal default).
    local s = tonumber(v) or 1
    if s < 0 then s = 0 elseif s > 2.00 then s = 2.00 end
    return s
end

function Meter_GetScale()
    return ClampMetersScale(MetersSavedVars and MetersSavedVars.scale)
end

function Meter_ApplyScale()
    if not anchor then return end
    local g = (_G.GSETracker_GetGlobalScale and _G.GSETracker_GetGlobalScale()) or 1
    g = tonumber(g) or 1
    if g < 0 then g = 0 end
    local eff = Meter_GetScale() * g
    if eff < 0.05 then eff = 0.05 end  -- SetScale(0) is invalid; floor at a near-invisible value
    anchor:SetScale(eff)
    ApplySavedPosition()  -- re-place with the new scale so the cluster stays centred on its spot
end

function Meter_SetScale(v)
    if MetersSavedVars then MetersSavedVars.scale = ClampMetersScale(v) end
    Meter_ApplyScale()
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
    if AHMatchFrame and AHMatchFrame.matchText then
        -- AH %% in the Meters HUD renders 8pt smaller than the other readouts (floored at 8), like GCD's -2.
        AHMatchFrame.matchText:SetFont(fontPath, math.max(resolvedSize - 8, 8), outline)
    end
    if PlayerNameFrame and PlayerNameFrame.nameText then
        PlayerNameFrame.nameText:SetFont(fontPath, resolvedSize, outline)
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
    ApplySavedPosition()  -- scale-compensated placement
    ApplyEffectiveOpacity()
    Meter_UpdateVisibility()
end

function Meter_ResetPosition()
    if InCombatLock() then return end
    MetersSavedVars.x = 0
    MetersSavedVars.y = -15
    ApplySavedPosition()  -- scale-compensated placement
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
-- These events exist only on Retail (mount/spec/talent + the C_DamageMeter and
-- C_AssistedCombat backends). On Classic, RegisterEvent THROWS for an unknown event,
-- so pcall-guard them -- the addon still loads, and the meters cluster is gated off
-- there anyway (ns.Caps.meters).
local function SafeRegisterEvent(ev) pcall(eventFrame.RegisterEvent, eventFrame, ev) end
SafeRegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
SafeRegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
SafeRegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
SafeRegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
SafeRegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST")
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
    if not MetersOK() then return end
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
    Meter_ApplyScale()  -- MetersScale * OverallScale onto the anchor
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
    ApplyPlayerNameCVar()  -- on load: if Player Name is slotted, ensure Blizzard's "My Name" is OFF (no double)
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
    -- Classic: meters engine is unavailable -- hide the whole cluster once and bail.
    local arg1 = ...
    -- Readout controllers are retail-only (C_DamageMeter / C_AssistedCombat). On Classic
    -- skip them; the marker + lifecycle handling below still runs so the Center Marker works.
    if MetersOK() then
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

