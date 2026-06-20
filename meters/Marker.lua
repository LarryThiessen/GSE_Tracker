-- Modules\Meters\Marker.lua

MetersSavedVars = MetersSavedVars or {}

if MetersSavedVars.showAHLight == nil and MetersSavedVars.showSBA ~= nil then
    MetersSavedVars.showAHLight = MetersSavedVars.showSBA
end


local DEFAULT_MODE = "AHLight"
local DEFAULT_SIZE = 28

local BULLSEYE_TEXTURE = "Interface\\AddOns\\GSE_Tracker\\media\\marker-images\\Crosshairs001.png"
local CLASS_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

local VALID_MODES = {
    AHLight = true,
    Class = true,
    Specialization = true,
    Bullseye = true,
    None = true,
}

-- ─── Frame ────────────────────────────────────────────────
local frame = CreateFrame("Frame", "MarkerFrame", UIParent)
frame:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
frame:SetFrameStrata("HIGH")
frame:SetFrameLevel(10)
frame:SetClampedToScreen(true)
frame:Hide()

frame.mode = DEFAULT_MODE
frame.isPreviewMode = false

frame.icon = frame:CreateTexture(nil, "ARTWORK")
frame.icon:SetAllPoints()
frame.icon:SetTexture(nil)
frame.icon:SetTexCoord(0, 1, 0, 1)

-- ─── Helpers ──────────────────────────────────────────────
local function NormalizeMode(mode)
    if VALID_MODES[mode] then
        return mode
    end

    return DEFAULT_MODE
end

local function PlayerIsMounted()
    if UnitOnTaxi and UnitOnTaxi("player") then
        return true
    end

    if IsMounted and IsMounted() then
        return true
    end

    return false
end

local function GetSavedMode()
    local mode = MetersSavedVars.Marker

    -- Backwards compatibility with older saved var name
    if mode == nil then
        mode = MetersSavedVars.centerIndicator
    end

    if mode == "SBA" then
        mode = "AHLight"
    end

    mode = NormalizeMode(mode)
    MetersSavedVars.Marker = mode

    return mode
end

local function SyncLegacyShowAHLight()
    MetersSavedVars.showAHLight = (GetSavedMode() == "AHLight")
end

local function GetParentFrame()
    return MetersAnchor or UIParent
end

local function AttachToAnchor()
    local parent = GetParentFrame()

    if frame:GetParent() ~= parent then
        frame:SetParent(parent)
    end
end

local function GetReferenceSize()
    local fallback = math.max(24, math.floor(((MetersSavedVars.fontSize or 18) * 1.6) + 0.5))

    if AHLightFrame then
        local w = tonumber(AHLightFrame:GetWidth()) or 0
        local h = tonumber(AHLightFrame:GetHeight()) or 0

        if w > 0 and h > 0 then
            return w, h
        end
    end

    return fallback, fallback
end

local function ApplySize()
    local w, h = GetReferenceSize()
    frame:SetSize(w, h)
end

local function ApplyOpacity()
    -- Let MetersAnchor control final alpha.
    frame:SetAlpha(1)
end

local function GetSpecializationTexture()
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, _, _, icon = GetSpecializationInfo(specIndex)
            if icon then
                return icon
            end
        end
    end

    return FALLBACK_TEXTURE
end

local function GetClassTextureAndCoords()
    local _, classFile = UnitClass("player")

    if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
        local coords = CLASS_ICON_TCOORDS[classFile]
        return CLASS_TEXTURE, coords[1], coords[2], coords[3], coords[4]
    end

    return FALLBACK_TEXTURE, 0, 1, 0, 1
end

local function SetMarkerTexture(mode)
    mode = NormalizeMode(mode)

    if mode == "Bullseye" then
        frame.icon:SetTexture(BULLSEYE_TEXTURE)
        frame.icon:SetTexCoord(0, 1, 0, 1)

    elseif mode == "Class" then
        local texture, left, right, top, bottom = GetClassTextureAndCoords()
        frame.icon:SetTexture(texture)
        frame.icon:SetTexCoord(left, right, top, bottom)

    elseif mode == "Specialization" then
        frame.icon:SetTexture(GetSpecializationTexture())
        frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    elseif mode == "None" then
        frame.icon:SetTexture(nil)
        frame.icon:SetTexCoord(0, 1, 0, 1)

    else
        frame.icon:SetTexture(nil)
        frame.icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function HideAHLight()
    if AHLight_SetPreview then
        AHLight_SetPreview(false)
    end

    if AHLight_Clear then
        AHLight_Clear()
    end

    if AHLightFrame then
        AHLightFrame:Hide()
    end
end

local function ShouldShowMarker()
    local mode = GetSavedMode()

    if PlayerIsMounted() and not frame.isPreviewMode then
        return false
    end

    if mode == "AHLight" or mode == "None" then
        return false
    end

    return true
end

local function ApplyModeVisuals()
    frame.mode = GetSavedMode()

    AttachToAnchor()
    ApplySize()
    ApplyOpacity()

    -- VERY IMPORTANT:
    -- Whenever the selected mode is not AHLight, force-hide the AHLight icon first
    if frame.mode ~= "AHLight" then
        HideAHLight()
    end

    if not ShouldShowMarker() then
        frame.icon:SetTexture(nil)
        frame:Hide()
        return
    end

    SetMarkerTexture(frame.mode)
    frame:Show()
end

-- ─── Public API ───────────────────────────────────────────
function Marker_SetMode(mode)
    mode = NormalizeMode(mode)

    MetersSavedVars.Marker = mode
    frame.mode = mode

    SyncLegacyShowAHLight()

    if mode == "AHLight" then
        frame.icon:SetTexture(nil)
        frame:Hide()
        return
    end

    HideAHLight()
    ApplyModeVisuals()
end

function Marker_SetPreview(enabled)
    frame.isPreviewMode = not not enabled

    local mode = GetSavedMode()

    if mode == "AHLight" then
        if AHLight_SetPreview then
            AHLight_SetPreview(frame.isPreviewMode)
        end

        frame:Hide()
        return
    end

    HideAHLight()
    ApplyModeVisuals()

    if frame.isPreviewMode and ShouldShowMarker() then
        frame:Show()
    end
end

function Marker_Refresh()
    local mode = GetSavedMode()
    frame.mode = mode

    if mode == "AHLight" then
        frame.icon:SetTexture(nil)
        frame:Hide()
        return
    end

    if PlayerIsMounted() and not frame.isPreviewMode then
        frame.icon:SetTexture(nil)
        frame:Hide()
        return
    end

    -- Force-hide AHLight here too, not just in SetMode
    HideAHLight()
    ApplyModeVisuals()
end

function Marker_Clear()
    frame.icon:SetTexture(nil)
    frame:Hide()
end

-- ─── Backwards Compatibility ──────────────────────────────
if Meter_SetCenterIndicator == nil then
    function Meter_SetCenterIndicator(mode)
        Marker_SetMode(mode)
    end
end

