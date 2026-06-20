-- GSE: Tracker -- Meters\MetersOptions.lua (self-contained meters options panel)

local _, ns = ...
local panel = CreateFrame("Frame", "MetersOptionsPanel", UIParent)
panel.name = "Meters"
panel:Hide()

local LSM = LibStub("LibSharedMedia-3.0")
MetersSavedVars = MetersSavedVars or {}

-- Retail-only readouts depend on C_DamageMeter (absent on Classic). Detected directly here
-- because the addon's ns.Caps isn't populated until ADDON_LOADED (after this file runs).
local METERS_CAPABLE = ((not _G.WOW_PROJECT_ID) or (_G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1)))
  and (_G.C_DamageMeter and _G.C_DamageMeter.GetAvailableCombatSessions) and true or false

if MetersSavedVars.showAHLight == nil and MetersSavedVars.showSBA ~= nil then
    MetersSavedVars.showAHLight = MetersSavedVars.showSBA
end

if MetersSavedVars.showAHLightUsage == nil and MetersSavedVars.showSBAUsage ~= nil then
    MetersSavedVars.showAHLightUsage = MetersSavedVars.showSBAUsage
end

-- ─── Defaults ─────────────────────────────────────────────
local defaults = {
    Marker         = "AHLight",
    showAHLight      = true,
    showDPS          = true,
    showHPS          = true,
    showGCD          = true,
    showAHLightUsage = true,
    showDetails      = true,
    hideDetailsInCombat = false,
    locked           = true,
    fontSize         = 18,
    fontStyle        = "Friz Quadrata TT",
    fontType         = "Friz Quadrata TT",
    opacity          = 100,
    showWhen         = "Always",
    refreshRate      = 0.10
}

for k, v in pairs(defaults) do
    if MetersSavedVars[k] == nil then
        MetersSavedVars[k] = v
    end
end

local function NormalizeMarker(value)
    if value == "SBA" then value = "AHLight" end
    if value ~= "AHLight" and value ~= "Class" and value ~= "Specialization"
    and value ~= "Bullseye" and value ~= "None" then
        value = "AHLight"
    end
    return value
end

-- Migrate old saved values
if MetersSavedVars.Marker == nil then
    if MetersSavedVars.centerIndicator ~= nil then
        MetersSavedVars.Marker = NormalizeMarker(MetersSavedVars.centerIndicator)
    elseif MetersSavedVars.showAHLight == false or MetersSavedVars.showSBA == false then
        MetersSavedVars.Marker = "Bullseye"
    else
        MetersSavedVars.Marker = "AHLight"
    end
else
    MetersSavedVars.Marker = NormalizeMarker(MetersSavedVars.Marker)
end

if not MetersSavedVars.fontStyle and MetersSavedVars.fontType then
    MetersSavedVars.fontStyle = MetersSavedVars.fontType
end
if not MetersSavedVars.fontType and MetersSavedVars.fontStyle then
    MetersSavedVars.fontType = MetersSavedVars.fontStyle
end
if MetersSavedVars.point    == nil then MetersSavedVars.point    = "CENTER" end
if MetersSavedVars.relPoint == nil then MetersSavedVars.relPoint = "CENTER" end
if MetersSavedVars.x        == nil then MetersSavedVars.x        = 0       end
if MetersSavedVars.y        == nil then MetersSavedVars.y        = -15     end

local function GetCurrentFontName()
    return MetersSavedVars.fontStyle or MetersSavedVars.fontType or "Friz Quadrata TT"
end

local function SetCurrentFontName(name)
    name = name or "Friz Quadrata TT"
    MetersSavedVars.fontStyle = name
    MetersSavedVars.fontType  = name
end

local function GetMarker()
    MetersSavedVars.Marker = NormalizeMarker(MetersSavedVars.Marker)
    return MetersSavedVars.Marker
end

local function SyncLegacyShowAHLight()
    MetersSavedVars.showAHLight = (GetMarker() == "AHLight")
end

local function ApplyMarkerMode(mode)
    mode = NormalizeMarker(mode or GetMarker())
    MetersSavedVars.Marker = mode
    SyncLegacyShowAHLight()
    if Marker_SetMode then
        Marker_SetMode(mode)
    elseif Meter_SetCenterIndicator then
        Meter_SetCenterIndicator(mode)
    end
    if mode ~= "AHLight" and Marker_Refresh then
        Marker_Refresh()
    end
end

local function ApplyMarkerPreview(enabled)
    if Marker_SetPreview then Marker_SetPreview(enabled) end
end

local function RefreshMarker()
    if Marker_Refresh then Marker_Refresh() end
end

SyncLegacyShowAHLight()

-- ─── Layout constants ─────────────────────────────────────
local LEFT_MARGIN = 16
local COLUMN_GAP  = 160
local ROW_GAP     = -10
local INLINE_DROPDOWN_WIDTH = 130
local MAIN_SLIDER_WIDTH = 500
local CONTROL_SECTION_X_OFFSET = 41

local positionXSlider, positionYSlider
local positionXBox,    positionYBox
local opacitySlider,   opacityBox
local refreshRateSlider
local resetBtn, lockCB
local MarkerDrop, detailsCB, detailsCombatCB, autoResetCB

local function IsCombatLockActive()
    return UnitAffectingCombat("player")
end

-- ─── Preview Display ──────────────────────────────────────
local function ApplyTestDisplay()
    local selectedMarker = GetMarker()
    local showAHLight = (selectedMarker == "AHLight")
    ApplyMarkerMode(selectedMarker)

    -- In combat ALWAYS show live (never the examples), even when unlocked -- otherwise the
    -- example values ("6789" etc.) linger during combat when there's no live value to
    -- overwrite them. The example branch below is for the unlocked, OUT-of-combat case only.
    if MetersSavedVars.locked or IsCombatLockActive() then
        ApplyMarkerPreview(false)
        if AHLight_SetPreview      then AHLight_SetPreview(false)      end
        if AHLightUsage_SetPreview then AHLightUsage_SetPreview(false) end
        if GCD_SetPreview          then GCD_SetPreview(false)
        elseif GCD_SetPreviewMode  then GCD_SetPreviewMode(false)      end

        if UnitAffectingCombat("player") then
            if Meter_SetDisplay then
                Meter_SetDisplay(showAHLight,
                    MetersSavedVars.showDPS, MetersSavedVars.showHPS,
                    MetersSavedVars.showGCD, MetersSavedVars.showAHLightUsage)
            end
            if Meter_UpdateVisibility then Meter_UpdateVisibility() end
            return
        end

        if DPSFrame and DPSFrame.dpsText then DPSFrame.dpsText:SetText(""); DPSFrame:Hide() end
        if HPSFrame and HPSFrame.hpsText then HPSFrame.hpsText:SetText(""); HPSFrame:Hide() end
        if GCDFrame and GCDFrame.gcdText then GCDFrame.gcdText:SetText(""); GCDFrame:Hide() end
        if AHLight_Clear  then AHLight_Clear()  end
        if AHLightFrame   then AHLightFrame:Hide() end
        if AHLightUsage_Clear then
            AHLightUsage_Clear()
        elseif AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:SetText("")
        end
        if AHLightUsageFrame then AHLightUsageFrame:Hide() end
        if selectedMarker ~= "AHLight" then RefreshMarker() end
        if GCD_UpdateNow          then GCD_UpdateNow()          end
        if Meter_UpdateVisibility then Meter_UpdateVisibility() end
        return
    end

    local showDPS          = MetersSavedVars.showDPS
    local showHPS          = MetersSavedVars.showHPS
    local showGCD          = MetersSavedVars.showGCD
    local showAHLightUsage = MetersSavedVars.showAHLightUsage

    if showAHLight then
        ApplyMarkerPreview(false)
        if AHLight_SetPreview then AHLight_SetPreview(true) end
        if AHLightFrame       then AHLightFrame:Show()       end
    else
        if AHLight_SetPreview then AHLight_SetPreview(false) end
        if AHLight_Clear      then AHLight_Clear()           end
        if AHLightFrame       then AHLightFrame:Hide()       end
        ApplyMarkerPreview(true)
        RefreshMarker()
    end

    if DPSFrame and DPSFrame.dpsText then
        if showDPS then DPSFrame.dpsText:SetText("12345"); DPSFrame:Show()
        else            DPSFrame.dpsText:SetText("");      DPSFrame:Hide() end
    end

    if HPSFrame and HPSFrame.hpsText then
        if showHPS then HPSFrame.hpsText:SetText("6789"); HPSFrame:Show()
        else            HPSFrame.hpsText:SetText("");     HPSFrame:Hide() end
    end

    if GCDFrame and GCDFrame.gcdText then
        if showGCD then GCDFrame.gcdText:SetText("1.50s"); GCDFrame:Show()
        else            GCDFrame.gcdText:SetText("");      GCDFrame:Hide() end
    end

    if showAHLightUsage then
        if AHLightUsage_SetPreview then
            AHLightUsage_SetPreview(true)
        elseif AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:SetText("24% (11/47)")
        end
        if AHLightUsageFrame then AHLightUsageFrame:Show() end
    else
        if AHLightUsage_SetPreview then AHLightUsage_SetPreview(false) end
        if AHLightUsage_Clear then
            AHLightUsage_Clear()
        elseif AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText then
            AHLightUsageFrame.ahLightUsageText:SetText("")
        end
        if AHLightUsageFrame then AHLightUsageFrame:Hide() end
    end

    if Meter_UpdateVisibility then Meter_UpdateVisibility() end
end

-- ─── Position Helpers ─────────────────────────────────────
local function GetPositionBounds()
    local screenWidth  = math.floor((GetScreenWidth  and GetScreenWidth())  or UIParent:GetWidth()  or 0)
    local screenHeight = math.floor((GetScreenHeight and GetScreenHeight()) or UIParent:GetHeight() or 0)
    local maxX = math.floor(screenWidth  / 2)
    local maxY = math.floor(screenHeight / 2)
    if MetersAnchor then
        local aw = math.floor(MetersAnchor:GetWidth()  or 0)
        local ah = math.floor(MetersAnchor:GetHeight() or 0)
        maxX = math.max(0, maxX - math.floor(aw / 2))
        maxY = math.max(0, maxY - math.floor(ah / 2))
    end
    return -maxX, maxX, -maxY, maxY
end

local function ClampPositionValue(axis, value)
    value = math.floor(tonumber(value) or 0)
    local minX, maxX, minY, maxY = GetPositionBounds()
    if axis == "x" then
        if value < minX then value = minX end
        if value > maxX then value = maxX end
    elseif axis == "y" then
        if value < minY then value = minY end
        if value > maxY then value = maxY end
    end
    return value
end

local function ClampOpacityValue(value)
    value = math.floor(tonumber(value) or 25)
    if value < 25  then value = 25  end
    if value > 100 then value = 100 end
    return value
end

local function ClampRefreshRateValue(value)
    value = tonumber(value) or 0.10
    value = math.floor((value * 100) + 0.5) / 100
    if value < 0.05 then value = 0.05 end
    if value > 0.15 then value = 0.15 end
    return value
end

function Meters_GetRefreshRate()
    MetersSavedVars.refreshRate = ClampRefreshRateValue(MetersSavedVars.refreshRate or defaults.refreshRate or 0.10)
    return MetersSavedVars.refreshRate
end

function Meters_GetUpdateInterval()
    return Meters_GetRefreshRate()
end

MetersSavedVars.refreshRate = Meters_GetRefreshRate()

local function UpdatePositionSliderTexts()
    if positionXSlider then positionXSlider.Text:SetText("Position X: " .. math.floor(positionXSlider:GetValue() or 0)) end
    if positionYSlider then positionYSlider.Text:SetText("Position Y: " .. math.floor(positionYSlider:GetValue() or 0)) end
end

local function UpdatePositionBoxes()
    if positionXBox and not positionXBox:HasFocus() then positionXBox:SetText(tostring(math.floor(MetersSavedVars.x or 0)))   end
    if positionYBox and not positionYBox:HasFocus() then positionYBox:SetText(tostring(math.floor(MetersSavedVars.y or -15))) end
end

local function RefreshPositionSliderRanges()
    if not positionXSlider or not positionYSlider then return end
    local minX, maxX, minY, maxY = GetPositionBounds()
    positionXSlider:SetMinMaxValues(minX, maxX)
    positionYSlider:SetMinMaxValues(minY, maxY)
    positionXSlider.Low:SetText(tostring(minX)); positionXSlider.High:SetText(tostring(maxX))
    positionYSlider.Low:SetText(tostring(minY)); positionYSlider.High:SetText(tostring(maxY))
    MetersSavedVars.x = ClampPositionValue("x", MetersSavedVars.x or 0)
    MetersSavedVars.y = ClampPositionValue("y", MetersSavedVars.y or -15)
end

local function ApplyPosition(x, y)
    if MetersSavedVars.locked or IsCombatLockActive() then return end
    x = ClampPositionValue("x", x); y = ClampPositionValue("y", y)
    MetersSavedVars.point = "CENTER"; MetersSavedVars.relPoint = "CENTER"
    MetersSavedVars.x = x; MetersSavedVars.y = y
    if Meter_SetPosition then
        Meter_SetPosition(x, y)
    elseif MetersAnchor then
        MetersAnchor:ClearAllPoints()
        MetersAnchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    if positionXSlider and math.floor(positionXSlider:GetValue() or 0) ~= x then positionXSlider:SetValue(x) end
    if positionYSlider and math.floor(positionYSlider:GetValue() or 0) ~= y then positionYSlider:SetValue(y) end
    UpdatePositionSliderTexts(); UpdatePositionBoxes()
end

local function SyncPositionControlsFromSaved()
    RefreshPositionSliderRanges()
    local x = ClampPositionValue("x", MetersSavedVars.x or 0)
    local y = ClampPositionValue("y", MetersSavedVars.y or -15)
    MetersSavedVars.x = x; MetersSavedVars.y = y
    if positionXSlider then positionXSlider:SetValue(x) end
    if positionYSlider then positionYSlider:SetValue(y) end
    UpdatePositionSliderTexts(); UpdatePositionBoxes()
end

local function UpdatePositionControlState()
    local enabled = (not MetersSavedVars.locked) and (not IsCombatLockActive())
    for _, ctrl in ipairs({ positionXSlider, positionYSlider }) do
        if ctrl then
            if enabled then ctrl:Enable() else ctrl:Disable() end
            ctrl:SetAlpha(enabled and 1 or 0.5); ctrl:EnableMouse(enabled)
        end
    end
    for _, box in ipairs({ positionXBox, positionYBox }) do
        if box then
            if not enabled then box:ClearFocus() end
            box:EnableMouse(enabled); box:SetAlpha(enabled and 1 or 0.5)
        end
    end
end

function Meter_SyncPositionControls()
    SyncPositionControlsFromSaved(); UpdatePositionControlState()
end

-- ─── Font Helpers ─────────────────────────────────────────
local function RefreshFontStringNow(fontString, fontPath)
    if not fontString or not fontPath then return end
    local _, currentSize, currentFlags = fontString:GetFont()
    fontString:SetFont(fontPath, currentSize or (MetersSavedVars.fontSize or 18), currentFlags or "OUTLINE")
end

local function ForceImmediateFontRefresh()
    -- Adopt the action-bar font face when a UI skin is active (mirrors the meters'
    -- own ResolveFontPath); Force-Native falls back to the player's LSM pick.
    local us = ns and ns._ui
    local fontPath = (us and us.GetAdoptedFontStyle and us.GetAdoptedFontStyle())
        or (LSM and LSM:Fetch("font", GetCurrentFontName()))
    if not fontPath then return end
    RefreshFontStringNow(DPSFrame and DPSFrame.dpsText, fontPath)
    RefreshFontStringNow(HPSFrame and HPSFrame.hpsText, fontPath)
    RefreshFontStringNow(GCDFrame and GCDFrame.gcdText, fontPath)
    RefreshFontStringNow(AHLightUsageFrame and AHLightUsageFrame.ahLightUsageText, fontPath)
end

-- ─── Apply Functions ──────────────────────────────────────
local function ApplyFontSettings()
    local selectedFont = GetCurrentFontName()
    SetCurrentFontName(selectedFont)
    if Meter_ApplyFont then Meter_ApplyFont(selectedFont, MetersSavedVars.fontSize) end
    ForceImmediateFontRefresh()
    ApplyMarkerMode(GetMarker())
    if MetersSavedVars.locked then
        ApplyMarkerPreview(false)
        if Meter_SetDisplay then
            Meter_SetDisplay((GetMarker() == "AHLight"),
                MetersSavedVars.showDPS, MetersSavedVars.showHPS,
                MetersSavedVars.showGCD, MetersSavedVars.showAHLightUsage)
        end
        if GCD_UpdateNow          then GCD_UpdateNow()          end
        if Meter_UpdateVisibility then Meter_UpdateVisibility() end
    else
        ApplyTestDisplay()
    end
    C_Timer.After(0, function()
        if Meter_ApplyFont then Meter_ApplyFont(selectedFont, MetersSavedVars.fontSize) end
        ForceImmediateFontRefresh(); ApplyMarkerMode(GetMarker())
        if MetersSavedVars.locked then
            ApplyMarkerPreview(false)
            if Meter_SetDisplay then
                Meter_SetDisplay((GetMarker() == "AHLight"),
                    MetersSavedVars.showDPS, MetersSavedVars.showHPS,
                    MetersSavedVars.showGCD, MetersSavedVars.showAHLightUsage)
            end
            if GCD_UpdateNow          then GCD_UpdateNow()          end
            if Meter_UpdateVisibility then Meter_UpdateVisibility() end
        else
            ApplyTestDisplay()
        end
    end)
end

-- Exposed so the addon's settings panel (which renders the Meters Font Style/Size
-- dropdowns at the top of the Meters tab in the modern WowStyle1 look) can trigger the
-- exact same full refresh as the old in-panel dropdowns did.
_G.Meters_ApplyFontSettings = ApplyFontSettings

-- Font-ONLY apply for the addon-side Meters font dropdowns. The full ApplyFontSettings
-- also runs ApplyMarkerMode + ApplyTestDisplay, which force the center-marker preview
-- (e.g. the Bullseye "eye") on -- it then lingers on screen. A font change must not
-- touch the marker, so this applies just the font + refreshes the meter font strings.
function _G.Meters_ApplyFontOnly()
    local selectedFont = GetCurrentFontName()
    SetCurrentFontName(selectedFont)
    if Meter_ApplyFont then Meter_ApplyFont(selectedFont, MetersSavedVars.fontSize) end
    ForceImmediateFontRefresh()
end

local function ApplyOpacity()
    if Meter_SetOpacity then Meter_SetOpacity(MetersSavedVars.opacity) end
end

local function ApplyRefreshRate()
    local r = Meters_GetRefreshRate()
    if Meter_ApplyRefreshRate      then Meter_ApplyRefreshRate(r)      end
    if Marker_ApplyRefreshRate     then Marker_ApplyRefreshRate(r)     end
    if AHLight_ApplyRefreshRate    then AHLight_ApplyRefreshRate(r)    end
    if AHLightUsage_ApplyRefreshRate then AHLightUsage_ApplyRefreshRate(r) end
    if DPS_ApplyRefreshRate        then DPS_ApplyRefreshRate(r)        end
    if HPS_ApplyRefreshRate        then HPS_ApplyRefreshRate(r)        end
    if GCD_ApplyRefreshRate        then GCD_ApplyRefreshRate(r)        end
    if GCD_UpdateNow               then GCD_UpdateNow()                end
end

local function UpdateRefreshRateText(val)
    if refreshRateSlider then refreshRateSlider.Text:SetText(string.format("Refresh Rate: %.2f", val)) end
end

local function UpdateOpacityText(val)
    if opacitySlider then opacitySlider.Text:SetText("Opacity: " .. val .. "%") end
end

local function UpdateOpacityBox()
    if opacityBox and not opacityBox:HasFocus() then
        opacityBox:SetText(tostring(math.floor(MetersSavedVars.opacity or 100)))
    end
end

local function ApplyDisplayToggles()
    SyncLegacyShowAHLight(); ApplyMarkerMode(GetMarker())
    if Meter_SetDisplay then
        Meter_SetDisplay(MetersSavedVars.showAHLight,
            MetersSavedVars.showDPS, MetersSavedVars.showHPS,
            MetersSavedVars.showGCD, MetersSavedVars.showAHLightUsage)
    end
    ApplyTestDisplay()
end

-- ─── Details Toggle ───────────────────────────────────────
local function ApplyDetailsToggle(openWhenEnabled)
    local show = MetersSavedVars.showDetails ~= false
    MetersSavedVars.Details = MetersSavedVars.Details or {}
    MetersSavedVars.Details.enabled = show
    MetersSavedVars.Details.hideInCombat = MetersSavedVars.hideDetailsInCombat == true
    if show then
        if openWhenEnabled or MetersSavedVars.Details.wasShown then
            if Details_Show then Details_Show() end
        end
    else
        if Details_Hide then Details_Hide() end
        MetersSavedVars.Details.wasShown = false
    end
end

local function ApplyDetailsCombatToggle()
    MetersSavedVars.hideDetailsInCombat = MetersSavedVars.hideDetailsInCombat == true
    MetersSavedVars.Details = MetersSavedVars.Details or {}
    MetersSavedVars.Details.hideInCombat = MetersSavedVars.hideDetailsInCombat
    if detailsCombatCB then detailsCombatCB:SetChecked(MetersSavedVars.hideDetailsInCombat) end
    if Details_ApplyCombatVisibility then Details_ApplyCombatVisibility() end
end

function Meters_SetDetailsOptionChecked(checked)
    local show = checked == true
    MetersSavedVars.showDetails = show
    MetersSavedVars.Details = MetersSavedVars.Details or {}
    MetersSavedVars.Details.enabled = show
    MetersSavedVars.Details.hideInCombat = MetersSavedVars.hideDetailsInCombat == true
    if not show then MetersSavedVars.Details.wasShown = false end
    if detailsCB then detailsCB:SetChecked(show) end
end

local function UpdateLockState()
    -- The meters frame follows GSE: Tracker's "Lock All"; combat no longer force-locks it
    -- (InCombatLock() disables dragging during combat without persisting a lock that would
    -- otherwise stick true and stop the examples returning afterwards).
    if Meter_SetLocked then Meter_SetLocked(MetersSavedVars.locked) end
    ApplyMarkerMode(GetMarker())
    if MetersSavedVars.locked then ApplyMarkerPreview(false) end
    UpdatePositionControlState(); ApplyTestDisplay()
end

local function UpdateVisibility()
    if Meter_UpdateVisibility then Meter_UpdateVisibility() end
end

-- ─── UI ───────────────────────────────────────────────────
-- Header
local TITLE_IMAGE_TARGET_SIZE = 48

-- Header logo + "Meters" title removed (the panel is embedded as the GSE: Tracker
-- "Meters" tab, which has its own tab label). Kept as hidden frames so the few
-- downstream anchor/setText references stay valid.
local titleImage = panel:CreateTexture(nil, "ARTWORK")
titleImage:SetSize(TITLE_IMAGE_TARGET_SIZE, TITLE_IMAGE_TARGET_SIZE)
titleImage:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_MARGIN, -16)
titleImage:Hide()

local titleText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
titleText:SetPoint("LEFT", titleImage, "RIGHT", 12, 0)
titleText:Hide()

-- ROW 1: Lock -- removed; the meters frame now follows GSE: Tracker's General > Lock.
-- Kept created (hidden) so its label/checked-state references stay valid.
lockCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
lockCB:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_MARGIN, -16)
lockCB:Hide()

local function UpdateLockLabel()
    if IsCombatLockActive() then
        lockCB.Text:SetText("Locked Frame (Combat)")
    else
        lockCB.Text:SetText(MetersSavedVars.locked and "Locked Frame" or "Unlocked Frame [Auto-Locks when Closed/Combat]")
    end
end

-- NOTE: formerly "force lock". The meters frame now follows GSE: Tracker's "Lock All", so
-- this NO LONGER forces MetersSavedVars.locked = true (that made it lock on combat/login/
-- panel-close and never unlock, so examples never returned). It just re-applies the CURRENT
-- lock state + display; combat is handled by InCombatLock() without persisting a lock.
local function ForceLockUI()
    if lockCB then lockCB:SetChecked(MetersSavedVars.locked) end
    UpdateLockLabel()
    if Meter_SetLocked then Meter_SetLocked(MetersSavedVars.locked) end
    SyncLegacyShowAHLight(); ApplyMarkerMode(GetMarker())
    if MetersSavedVars.locked then ApplyMarkerPreview(false) end
    if Meter_SetDisplay then
        Meter_SetDisplay(MetersSavedVars.showAHLight,
            MetersSavedVars.showDPS, MetersSavedVars.showHPS,
            MetersSavedVars.showGCD, MetersSavedVars.showAHLightUsage)
    end
    ApplyTestDisplay(); UpdatePositionControlState(); UpdateVisibility()
end

-- Show When
local showLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
showLabel:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 2 + CONTROL_SECTION_X_OFFSET, ROW_GAP - 8)
showLabel:SetText("Show When:")

local showDrop = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
showDrop:SetPoint("TOPLEFT", showLabel, "TOPLEFT", 65, 8)
UIDropDownMenu_SetWidth(showDrop, INLINE_DROPDOWN_WIDTH)

UIDropDownMenu_Initialize(showDrop, function()
    for _, opt in ipairs({ "Always", "Has Target", "Combat", "Never" }) do
        local info = UIDropDownMenu_CreateInfo()
        info.text    = opt
        info.checked = (MetersSavedVars.showWhen == opt)
        info.func    = function()
            MetersSavedVars.showWhen = opt
            UIDropDownMenu_SetText(showDrop, opt)
            UpdateVisibility()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

-- "Show When" is now exposed on the GSE: Tracker General tab (Meters enable row),
-- styled like the other trackers; hide the panel's own copy. Kept created (hidden) so
-- the refresh code that calls UIDropDownMenu_SetText(showDrop, ...) stays valid.
showLabel:Hide()
showDrop:Hide()

-- Center Marker (moves up into the row the Show When dropdown used to occupy)
local MarkerLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
MarkerLabel:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 2 + CONTROL_SECTION_X_OFFSET, ROW_GAP - 8)
MarkerLabel:SetText("Center Marker:")

MarkerDrop = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
MarkerDrop:SetPoint("TOPLEFT", MarkerLabel, "TOPLEFT", 80, 8)
UIDropDownMenu_SetWidth(MarkerDrop, INLINE_DROPDOWN_WIDTH)

UIDropDownMenu_Initialize(MarkerDrop, function()
    for _, opt in ipairs({ "Class", "Specialization", "AHLight", "Bullseye", "None" }) do
        local info = UIDropDownMenu_CreateInfo()
        info.text    = opt
        info.checked = (GetMarker() == opt)
        info.func    = function()
            MetersSavedVars.Marker = NormalizeMarker(opt)
            SyncLegacyShowAHLight()
            UIDropDownMenu_SetText(MarkerDrop, MetersSavedVars.Marker)
            ApplyMarkerMode(MetersSavedVars.Marker)
            ApplyTestDisplay(); UpdateVisibility()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

-- Expose the center-marker mode globally so the GSE: Tracker Meters tab can drive it
-- from the merged "Center Marker" section at the top of that tab; then hide this copy.
function Meters_GetCenterMarker()
    return GetMarker()
end
function Meters_SetCenterMarker(opt)
    MetersSavedVars.Marker = NormalizeMarker(opt)
    SyncLegacyShowAHLight()
    if MarkerDrop then UIDropDownMenu_SetText(MarkerDrop, MetersSavedVars.Marker) end
    ApplyMarkerMode(MetersSavedVars.Marker)
    ApplyTestDisplay(); UpdateVisibility()
end
MarkerLabel:Hide()
MarkerDrop:Hide()

-- ROW 2: Show GCD | Show DPS | Show HPS | Show SBAssist %  ("Show GCD" leads the row, in
-- front of Show DPS -- it is the single source for showGCD, so the addon's Player Marker
-- colour row no longer carries a duplicate Show GCD checkbox.)
local gcdCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
-- Row 2: the Details row is now ABOVE this one (rows swapped); -54 keeps the original row spacing.
gcdCB:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_MARGIN, -54)
gcdCB.Text:SetText("Show GCD")

local dpsCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
-- Sits right after Show GCD; Show HPS / SBAssist chain off it at the same 130px spacing.
dpsCB:SetPoint("TOPLEFT", gcdCB, "TOPLEFT", 130, 0)
dpsCB.Text:SetText("Show DPS")

local hpsCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
hpsCB:SetPoint("TOPLEFT", dpsCB, "TOPLEFT", 130, 0)
hpsCB.Text:SetText("Show HPS")

local ahLightUsageCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
ahLightUsageCB:SetPoint("TOPLEFT", hpsCB, "TOPLEFT", 130, 0)
ahLightUsageCB.Text:SetText("Show SBAssist %")

-- Details row (ROW 1, on top, centred horizontally): Show Details | Auto Reset Details | Hide
-- Details in Combat. Positioned at the left for now; re-centred once all three labels exist.
detailsCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
detailsCB:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_MARGIN, -16)
detailsCB.Text:SetText("Show Details")

autoResetCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
autoResetCB:SetPoint("LEFT", detailsCB.Text, "RIGHT", 24, 0)
autoResetCB.Text:SetText("Auto Reset Details")

detailsCombatCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
detailsCombatCB:SetPoint("LEFT", autoResetCB.Text, "RIGHT", 24, 0)
detailsCombatCB.Text:SetText("Hide Details in Combat")

-- Centre the Details row horizontally over the content (the sliders span LEFT_MARGIN .. +MAIN_SLIDER_WIDTH).
-- Width = the 3 (checkbox + label) groups + the 2x 24px gaps between them (~132 of fixed chrome).
do
    local rowW = 132 + (detailsCB.Text:GetStringWidth() or 0)
                     + (autoResetCB.Text:GetStringWidth() or 0)
                     + (detailsCombatCB.Text:GetStringWidth() or 0)
    local cx = math.floor((LEFT_MARGIN + MAIN_SLIDER_WIDTH * 0.5) - rowW * 0.5 + 0.5)
    if cx < LEFT_MARGIN then cx = LEFT_MARGIN end
    detailsCB:ClearAllPoints()
    detailsCB:SetPoint("TOPLEFT", panel, "TOPLEFT", cx, -16)
end

-- Hover tooltips. Read-only OnEnter/OnLeave -> taint-safe on the embedded Settings canvas. The
-- Classic DPS/HPS/Details paths run off the Details! Damage Meter addon, so call that out.
local function AddMeterTooltip(cb, title, body)
  if not cb then return end
  cb:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then GameTooltip:AddLine(body, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
  end)
  cb:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
AddMeterTooltip(gcdCB, "Show GCD", "Your global cooldown timer. Works on every game version (read directly from Blizzard).")
AddMeterTooltip(dpsCB, "Show DPS", "Your damage per second. Retail: Blizzard's real-time damage meter. Classic: the |cff33ff99Details! Damage Meter|r addon (if installed).")
AddMeterTooltip(hpsCB, "Show HPS", "Your healing per second. Retail: Blizzard's real-time damage meter. Classic: the |cff33ff99Details! Damage Meter|r addon (if installed).")
AddMeterTooltip(ahLightUsageCB, "Show SBAssist %", "How often your casts match the Assisted Highlight suggestion. Retail only.")
AddMeterTooltip(detailsCB, "Show Details", "Show the damage-meter window. |cff33ff99Details!|r: re-opens its window even if you'd closed it. Blizzard's built-in (Retail, no Details!): shows it -- but the meter must be enabled in Settings > Gameplay Enhancements first (there's no API to switch it on).")
AddMeterTooltip(autoResetCB, "Auto Reset Details", "Automatically reset the damage meter at the start of each combat, so it shows only the current fight. Enables auto-reset even if it was switched off in the meter's settings.")
AddMeterTooltip(detailsCombatCB, "Hide Details in Combat", "Hide the Details window during combat, then show it again afterwards.")

-- Refresh Rate. Anchored to gcdCB -- the GCD row is now the LOWER of the two checkbox rows (rows
-- were swapped, Details on top), so the sliders sit just below it at the left margin.
refreshRateSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
refreshRateSlider:SetPoint("TOPLEFT", gcdCB, "BOTTOMLEFT", 0, -28)
refreshRateSlider:SetMinMaxValues(0.05, 0.15)
refreshRateSlider:SetValueStep(0.01)
refreshRateSlider:SetObeyStepOnDrag(true)
refreshRateSlider:SetWidth((MAIN_SLIDER_WIDTH - 40) / 2)  -- half width: shares the row with Opacity
refreshRateSlider.Low:SetText("0.05")
refreshRateSlider.High:SetText("0.15")
refreshRateSlider:SetScript("OnValueChanged", function(_, value)
    value = ClampRefreshRateValue(value)
    MetersSavedVars.refreshRate = value
    UpdateRefreshRateText(value); ApplyRefreshRate()
end)

-- Opacity
opacitySlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
opacitySlider:SetPoint("TOPLEFT", refreshRateSlider, "TOPRIGHT", 40, 0)  -- same row, right of Refresh Rate
opacitySlider:SetMinMaxValues(25, 100)
opacitySlider:SetValueStep(1)
opacitySlider:SetObeyStepOnDrag(true)
opacitySlider:SetWidth((MAIN_SLIDER_WIDTH - 40) / 2)
opacitySlider.Low:SetText("25%")
opacitySlider.High:SetText("100%")
opacitySlider:SetScript("OnValueChanged", function(_, value)
    value = ClampOpacityValue(value)
    MetersSavedVars.opacity = value
    UpdateOpacityText(value); UpdateOpacityBox(); ApplyOpacity()
end)

-- Position X/Y sliders removed: the meters frame is positioned by DRAGGING it while
-- unlocked (out of combat), so the numeric sliders are gone. positionXSlider/positionYSlider
-- (and the never-created boxes) stay nil; the position-control helpers guard on them and
-- become harmless no-ops.

-- Font Style (hidden here -- the live font dropdowns live at the top of the Meters tab).
local typeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
typeLabel:SetPoint("TOPLEFT", refreshRateSlider, "BOTTOMLEFT", 0, -28)
typeLabel:SetText("Font Style:")

local typeDrop = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
typeDrop:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", -15, -2)
UIDropDownMenu_SetWidth(typeDrop, 160)

UIDropDownMenu_Initialize(typeDrop, function()
    local currentFont = GetCurrentFontName()
    for _, name in ipairs(LSM:List("font")) do
        local info = UIDropDownMenu_CreateInfo()
        info.text    = name
        info.checked = (currentFont == name)
        info.func    = function()
            SetCurrentFontName(name)
            UIDropDownMenu_SetText(typeDrop, name)
            ApplyFontSettings()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

-- Font Size
local sizeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sizeLabel:SetPoint("TOPLEFT", typeLabel, "TOPLEFT", COLUMN_GAP + 40, 0)
sizeLabel:SetText("Font Size:")

local sizeDrop = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
sizeDrop:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", -15, -2)
UIDropDownMenu_SetWidth(sizeDrop, 100)

UIDropDownMenu_Initialize(sizeDrop, function()
    for _, s in ipairs({12, 14, 16, 18, 20, 24, 28, 32}) do
        local info = UIDropDownMenu_CreateInfo()
        info.text    = s .. " pt"
        info.checked = ((MetersSavedVars.fontSize or 18) == s)
        info.func    = function()
            MetersSavedVars.fontSize = s
            UIDropDownMenu_SetText(sizeDrop, s .. " pt")
            ApplyFontSettings()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

-- The Font Style / Font Size controls are now rendered at the TOP of the Meters tab
-- by the addon's settings panel (modern WowStyle1 dropdowns), so hide these in-panel
-- ones. Kept created (hidden) so the refresh code that calls UIDropDownMenu_SetText on
-- them stays valid; nothing visible anchors to them, leaving no layout gap up top.
typeLabel:Hide(); typeDrop:Hide()
sizeLabel:Hide(); sizeDrop:Hide()

-- Reset
resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(160, 24)
resetBtn:SetPoint("TOPLEFT", typeDrop, "BOTTOMLEFT", -28, -10)
resetBtn:SetText("Reset to Defaults")
-- Removed from the embedded Meters tab. Kept created (hidden) so its OnClick handler
-- below stays valid; nothing anchors to it, so hiding leaves no layout gap.
resetBtn:Hide()

-- ─── Callbacks ────────────────────────────────────────────
lockCB:SetScript("OnClick", function(self)
    if IsCombatLockActive() then
        self:SetChecked(true); MetersSavedVars.locked = true
        UpdateLockState(); UpdateLockLabel(); return
    end
    MetersSavedVars.locked = self:GetChecked()
    UpdateLockState(); UpdateLockLabel()
end)

gcdCB:SetScript("OnClick", function(self)
    MetersSavedVars.showGCD = self:GetChecked(); ApplyDisplayToggles()
end)

dpsCB:SetScript("OnClick", function(self)
    MetersSavedVars.showDPS = self:GetChecked(); ApplyDisplayToggles()
end)

hpsCB:SetScript("OnClick", function(self)
    MetersSavedVars.showHPS = self:GetChecked(); ApplyDisplayToggles()
end)

ahLightUsageCB:SetScript("OnClick", function(self)
    MetersSavedVars.showAHLightUsage = self:GetChecked(); ApplyDisplayToggles()
end)

detailsCB:SetScript("OnClick", function(self)
    Meters_SetDetailsOptionChecked(self:GetChecked()); ApplyDetailsToggle(self:GetChecked())
end)

autoResetCB:SetScript("OnClick", function(self)
    MetersSavedVars.autoResetDetails = self:GetChecked() == true
end)

detailsCombatCB:SetScript("OnClick", function(self)
    MetersSavedVars.hideDetailsInCombat = self:GetChecked() == true
    ApplyDetailsCombatToggle()
end)

resetBtn:SetScript("OnClick", function()
    for k in pairs(MetersSavedVars) do MetersSavedVars[k] = nil end
    for k, v in pairs(defaults)       do MetersSavedVars[k] = v   end
    MetersSavedVars.centerIndicator = nil
    MetersSavedVars.Marker = NormalizeMarker(defaults.Marker)
    SetCurrentFontName(defaults.fontStyle); SyncLegacyShowAHLight()
    MetersSavedVars.point = "CENTER"; MetersSavedVars.relPoint = "CENTER"
    MetersSavedVars.x = 0; MetersSavedVars.y = -15

    lockCB:SetChecked(true); gcdCB:SetChecked(true); dpsCB:SetChecked(true)
    hpsCB:SetChecked(true); ahLightUsageCB:SetChecked(true); detailsCB:SetChecked(true)
    detailsCombatCB:SetChecked(false); autoResetCB:SetChecked(false)

    opacitySlider:SetValue(100); UpdateOpacityText(100); UpdateOpacityBox()

    MetersSavedVars.refreshRate = defaults.refreshRate
    if refreshRateSlider then refreshRateSlider:SetValue(MetersSavedVars.refreshRate) end
    UpdateRefreshRateText(MetersSavedVars.refreshRate)

    UIDropDownMenu_SetText(showDrop,     "Always")
    UIDropDownMenu_SetText(MarkerDrop, GetMarker())
    UIDropDownMenu_SetText(typeDrop,     GetCurrentFontName())
    UIDropDownMenu_SetText(sizeDrop,     (MetersSavedVars.fontSize or 18) .. " pt")

    ApplyMarkerMode(GetMarker()); ApplyMarkerPreview(false)

    if Meter_ResetPosition then
        Meter_ResetPosition()
    elseif MetersAnchor then
        MetersAnchor:ClearAllPoints()
        MetersAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, -15)
    end

    SyncPositionControlsFromSaved(); UpdatePositionControlState()
    ApplyFontSettings(); ApplyDisplayToggles(); ApplyDetailsToggle(); ApplyDetailsCombatToggle()
    UpdateLockState(); UpdateLockLabel(); ApplyOpacity(); ApplyRefreshRate(); UpdateVisibility()
end)

-- Per-feature greying of the readout controls:
--   GCD            -- Blizzard cooldown read; works on EVERY flavor -> never greyed.
--   Refresh/Opacity sliders -- drive/affect the readouts (incl. GCD) -> never greyed.
--   DPS/HPS        -- need C_DamageMeter (retail) OR the Details! addon -> greyed if neither.
--   SBA% + Details -- retail-only (C_AssistedCombat / C_DamageMeter) -> greyed off mainline.
-- Run ONCE at PLAYER_LOGIN, not at file load: Details! may load AFTER us (so HasDPSSource is
-- only reliable post-login) and not in OnShow (repeated mutation of the embedded Settings canvas
-- risks taint). A single OOC pass at login only DISABLES the unavailable controls.
local function ApplyReadoutAvailability()
    local function dim(w)
        if not w then return end
        if w.SetEnabled then w:SetEnabled(false) elseif w.Disable then w:Disable() end
        if w.Text and w.Text.SetTextColor then w.Text:SetTextColor(0.5, 0.5, 0.5) end
    end
    -- DPS/HPS + the Details window all need a damage-meter source (retail C_DamageMeter OR the
    -- Details! addon). SBA% is the only one that's strictly retail (C_AssistedCombat).
    if not (_G.GSETracker_HasDPSSource and _G.GSETracker_HasDPSSource()) then
        dim(dpsCB); dim(hpsCB); dim(detailsCB); dim(detailsCombatCB); dim(autoResetCB)
    end
    if not METERS_CAPABLE then
        dim(ahLightUsageCB)
    end
end
local capFrame = CreateFrame("Frame")
capFrame:RegisterEvent("PLAYER_LOGIN")
capFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ApplyReadoutAvailability()
end)

panel:SetScript("OnShow", function()
    SyncLegacyShowAHLight()
    -- (Removed: combat no longer force-locks the meters frame -- it follows "Lock All".)

    lockCB:SetChecked(MetersSavedVars.locked)
    gcdCB:SetChecked(MetersSavedVars.showGCD)
    dpsCB:SetChecked(MetersSavedVars.showDPS)
    hpsCB:SetChecked(MetersSavedVars.showHPS)
    ahLightUsageCB:SetChecked(MetersSavedVars.showAHLightUsage)
    detailsCB:SetChecked(MetersSavedVars.showDetails ~= false)
    detailsCombatCB:SetChecked(MetersSavedVars.hideDetailsInCombat == true)
    autoResetCB:SetChecked(MetersSavedVars.autoResetDetails == true)
    UpdateLockLabel()

    opacitySlider:SetValue(MetersSavedVars.opacity or 100)
    UpdateOpacityText(MetersSavedVars.opacity or 100); UpdateOpacityBox()

    MetersSavedVars.refreshRate = Meters_GetRefreshRate()
    if refreshRateSlider then refreshRateSlider:SetValue(MetersSavedVars.refreshRate) end
    UpdateRefreshRateText(MetersSavedVars.refreshRate)

    UIDropDownMenu_SetText(showDrop,     MetersSavedVars.showWhen or "Always")
    UIDropDownMenu_SetText(MarkerDrop, GetMarker())
    UIDropDownMenu_SetText(typeDrop,     GetCurrentFontName())
    UIDropDownMenu_SetText(sizeDrop,     (MetersSavedVars.fontSize or 18) .. " pt")

    ApplyMarkerMode(GetMarker())
    if MetersSavedVars.locked then ApplyMarkerPreview(false) end

    SyncPositionControlsFromSaved(); UpdatePositionControlState()
    ApplyFontSettings(); ApplyDisplayToggles(); ApplyDetailsCombatToggle()
    UpdateLockState(); ApplyOpacity(); ApplyRefreshRate(); UpdateVisibility()
end)

panel:SetScript("OnHide", function()
    C_Timer.After(0, function() ForceLockUI() end)
end)

local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
startupFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
startupFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
startupFrame:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUI)
    if event == "PLAYER_ENTERING_WORLD" then
        if isInitialLogin or isReloadingUI then ForceLockUI() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ForceLockUI(); UpdateLockLabel(); UpdatePositionControlState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateLockLabel(); UpdatePositionControlState()
    end
end)
