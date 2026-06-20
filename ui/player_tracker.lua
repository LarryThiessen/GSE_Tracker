local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local uiShared = addon._ui or {}
local UIParent = (API.UIParent and API.UIParent()) or UIParent

local pi = math.pi
local TEXTURE_WHITE = C.TEXTURE_WHITE8X8 or "Interface\\Buttons\\WHITE8x8"
local MAX_BARS = 16
local COMBAT_MARKER_LEVEL_OFFSET = 20

local function Clamp(value, lo, hi)
  if uiShared.Clamp then
    return uiShared.Clamp(value, lo, hi)
  end
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function PixelSnap(value, frame)
  if uiShared.PixelSnap then
    return uiShared.PixelSnap(value, frame)
  end
  return tonumber(value) or 0
end

local function GetClassColorRGB()
  if uiShared.GetPlayerClassColorRGB then
    return uiShared.GetPlayerClassColorRGB(C.CLASS_FALLBACK_R or 0.20, C.CLASS_FALLBACK_G or 0.60, C.CLASS_FALLBACK_B or 1.00)
  end
  return C.CLASS_FALLBACK_R or 0.20, C.CLASS_FALLBACK_G or 0.60, C.CLASS_FALLBACK_B or 1.00
end

local function GetResolvedMarkerColor()
  -- Tri-state colour mode (mirrors the Pressed Indicator): "class" / "custom" / "none".
  -- "none" = fall back to RED so a white/greyscale shape or crosshair stays visible instead of
  -- washing out. Full-colour art and Class/Spec icons ignore the tint and keep their own colours
  -- (see DrawSymbolOnFrame), so this only affects tintable (white) symbols.
  local mode = (addon.GetCombatMarkerColorMode and addon:GetCombatMarkerColorMode()) or "none"
  if mode == "class" then
    return GetClassColorRGB()
  elseif mode == "custom" then
    if addon.GetCombatMarkerColor then
      return addon:GetCombatMarkerColor()
    end
    return 1.00, 0.82, 0.20
  end
  return C.COLOR_RED_R or 1, C.COLOR_RED_G or 0.20, C.COLOR_RED_B or 0.20
end

-- Master opacity from the Meters slider (MetersSavedVars.opacity, 0-100). The Center Marker is
-- parented to UIParent (so it can ignore the Meters scale), which means it does NOT inherit the
-- Meters anchor's alpha -- so fold the Meters opacity into the marker's own alpha here.
local function GetMetersOpacity()
  local sv = _G.MetersSavedVars
  local o = sv and tonumber(sv.opacity)
  if not o then return 1 end
  o = o / 100
  if o < 0 then return 0 elseif o > 1 then return 1 end
  return o
end

-- Lets the Meters engine nudge the Center Marker when the shared Opacity changes (the marker is
-- not a child of the Meters anchor, so it needs an explicit refresh to re-apply the alpha).
function _G.GSETracker_RefreshCenterMarker()
  if addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
end

local function ParentUnitsFromCanonical(value, parent)
  if uiShared.CanonicalPixelsToParentUnits then
    return uiShared.CanonicalPixelsToParentUnits(value, parent)
  end
  return PixelSnap(value, parent)
end

local function ParentUnitsToCanonical(value, parent)
  if uiShared.ParentUnitsToCanonicalPixels then
    return uiShared.ParentUnitsToCanonicalPixels(value, parent)
  end
  return tonumber(value) or 0
end

local function GetCursorPositionInParentSpace(parent)
  parent = parent or UIParent
  local scale = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
  if not scale or scale == 0 then
    scale = 1
  end

  local cursorX, cursorY = API.GetCursorPosition()
  return (tonumber(cursorX) or 0) / scale, (tonumber(cursorY) or 0) / scale
end

local function ClampCanonicalOffsets(frame, parent, x, y)
  if uiShared.ClampCenteredOffsetsToScreen then
    return uiShared.ClampCenteredOffsetsToScreen(frame, parent, x, y)
  end
  local limit = tonumber(C.COMBAT_MARKER_POSITION_LIMIT) or tonumber(C.ACTION_TRACKER_POSITION_LIMIT) or 3000
  return Clamp(x, -limit, limit), Clamp(y, -limit, limit)
end

local function HideTexture(tex)
  if tex then tex:Hide() end
end

local function SetTextureBar(tex, parent, width, height, rotation, x, y, r, g, b, a, drawLayer, subLevel)
  if not tex then return end
  tex:ClearAllPoints()
  subLevel = Clamp(tonumber(subLevel) or 0, -8, 7)
  tex:SetDrawLayer(drawLayer or "OVERLAY", subLevel)
  tex:SetPoint("CENTER", parent, "CENTER", PixelSnap(x or 0, parent), PixelSnap(y or 0, parent))
  tex:SetTexture(TEXTURE_WHITE)
  tex:SetSize(PixelSnap(width, parent), PixelSnap(height, parent))
  tex:SetRotation(rotation or 0)
  tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
  tex:Show()
end

local function GetCenteredAnchorConfig()
  -- The Center Marker is locked to the Meters readout's centre: it is NOT independently
  -- positionable -- it rides the Meters anchor and moves only when the Meters text moves.
  -- So always centre it (0,0) on its parent; the stored drag offset is intentionally ignored.
  return "CENTER", 0, 0
end

-- The Center Marker is locked to the Meters readout: anchor it to MetersAnchor's centre
-- (not UIParent) so it stays dead-centre on the meters area and follows it when the user
-- moves the Meters Position X/Y. Falls back to UIParent before the meters engine exists.
local function GetMarkerParent()
  return _G.MetersAnchor or UIParent
end

local function BuildCircleBars(size, thickness)
  local bars = {}
  local segments = 12
  local radius = math.max((size * 0.5) - (thickness * 0.85), thickness * 1.2)
  local length = math.max(thickness * 1.25, size * 0.20)
  for i = 1, segments do
    local angle = ((i - 1) / segments) * (2 * pi)
    bars[#bars + 1] = {
      length = length,
      thick = thickness,
      rotation = angle + (pi * 0.5),
      x = math.cos(angle) * radius,
      y = math.sin(angle) * radius,
    }
  end
  return bars
end

local function GetLayoutBars(symbol, size, thickness)
  local half = size * 0.5
  local diagLength = math.max(thickness, size * 0.90)
  local diamondLength = math.max(thickness, size * 0.34)
  local squareOffset = math.max(0, half - (thickness * 0.5))

  if symbol == "plus" then
    return {
      { length = size, thick = thickness, rotation = 0, x = 0, y = 0 },
      { length = size, thick = thickness, rotation = pi * 0.5, x = 0, y = 0 },
    }
  elseif symbol == "diamond" then
    local edgeInset = math.max(thickness * 0.9, size * 0.16)
    return {
      { length = diamondLength, thick = thickness, rotation = pi * 0.25, x = 0, y = half - edgeInset },
      { length = diamondLength, thick = thickness, rotation = -pi * 0.25, x = half - edgeInset, y = 0 },
      { length = diamondLength, thick = thickness, rotation = pi * 0.25, x = 0, y = -(half - edgeInset) },
      { length = diamondLength, thick = thickness, rotation = -pi * 0.25, x = -(half - edgeInset), y = 0 },
    }
  elseif symbol == "square" then
    return {
      { length = size, thick = thickness, rotation = 0, x = 0, y = squareOffset },
      { length = size, thick = thickness, rotation = 0, x = 0, y = -squareOffset },
      { length = size, thick = thickness, rotation = pi * 0.5, x = -squareOffset, y = 0 },
      { length = size, thick = thickness, rotation = pi * 0.5, x = squareOffset, y = 0 },
    }
  elseif symbol == "circle" then
    return BuildCircleBars(size, thickness)
  end

  return {
    { length = diagLength, thick = thickness, rotation = pi * 0.25, x = 0, y = 0 },
    { length = diagLength, thick = thickness, rotation = -pi * 0.25, x = 0, y = 0 },
  }
end

-- Lazily create the single texture used for image (media) symbols. Centred on the
-- marker frame; sized/shown by ApplyMarkerStyleToFrame when an image symbol is active.
local function EnsureMarkerImage(frame)
  if not frame.imageSymbol then
    frame.imageSymbol = frame:CreateTexture(nil, "ARTWORK")
    frame.imageSymbol:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.imageSymbol:Hide()
  end
  return frame.imageSymbol
end

local function EnsureMarkerBars(frame)
  frame.borderBars = frame.borderBars or {}
  frame.fillBars = frame.fillBars or {}
  for i = 1, MAX_BARS do
    if not frame.borderBars[i] then
      frame.borderBars[i] = frame:CreateTexture(nil, "BACKGROUND")
      frame.borderBars[i]:Hide()
    end
    if not frame.fillBars[i] then
      frame.fillBars[i] = frame:CreateTexture(nil, "OVERLAY")
      frame.fillBars[i]:Hide()
    end
  end
end

local function EnsureMarkerFrame(frame, parent, strata, level)
  if frame then
    EnsureMarkerBars(frame)
    return frame
  end

  frame = API.CreateFrame("Frame", nil, parent or UIParent)
  frame:SetSize(C.COMBAT_MARKER_DEFAULT_SIZE or 40, C.COMBAT_MARKER_DEFAULT_SIZE or 40)
  frame:SetFrameStrata(strata or (C.STRATA_TOOLTIP or "TOOLTIP"))
  frame:SetFrameLevel(level or ((C.ACTION_TRACKER_MARKER_FRAME_LEVEL or 50) + COMBAT_MARKER_LEVEL_OFFSET))
  frame:SetIgnoreParentScale(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(false)
  frame:Hide()
  EnsureMarkerBars(frame)
  return frame
end

local function CombatMarkerDragOnUpdate(selfFrame)
  if selfFrame and selfFrame._isDragging and addon.SyncActiveCombatMarkerDragPosition then
    addon:SyncActiveCombatMarkerDragPosition()
  end
end

-- Shared symbol renderer used by BOTH the combat marker and the pressed indicator so
-- they offer the same symbol/shape set. Draws either a media image symbol (full colour,
-- no tint) or a procedural shape (coloured bars tinted r,g,b,a) onto `frame`, sized to
-- `size`. The caller owns frame:SetSize and positioning.
-- Resolve the texture (+ texcoords) for a ported Meters "dynamic" marker symbol.
-- Bullseye is a fixed image; Class/Specialization resolve per-player at draw time.
-- Returns texture, left, right, top, bottom (or nil for an unknown symbol).
local function ResolveDynamicMarkerTexture(symbol)
  if symbol == "Class" then
    local _, classFile = UnitClass("player")
    local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if coords then
      return C.MARKER_CLASS_TEXTURE, coords[1], coords[2], coords[3], coords[4]
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark", 0, 1, 0, 1
  elseif symbol == "Specialization" then
    local icon
    -- Retail / modern clients: GetSpecialization() index -> GetSpecializationInfo (icon = 4th).
    if GetSpecialization and GetSpecializationInfo then
      local idx = GetSpecialization()
      if idx then local _, _, _, i = GetSpecializationInfo(idx); icon = i end
    end
    -- MoP Classic: the modern spec API returns nil there; it uses the older talent-tree API
    -- (GetPrimaryTalentTree() -> GetTalentTabInfo, icon = 4th return).
    if not icon and GetPrimaryTalentTree and GetTalentTabInfo then
      local tree = GetPrimaryTalentTree()
      if tree then local _, _, _, i = GetTalentTabInfo(tree); icon = i end
    end
    if icon then return icon, 0.07, 0.93, 0.07, 0.93 end
    return "Interface\\Icons\\INV_Misc_QuestionMark", 0, 1, 0, 1
  end
  return nil
end

function UI:DrawSymbolOnFrame(frame, symbol, size, thickness, borderSize, r, g, b, a)
  if not frame then return end
  EnsureMarkerBars(frame)

  -- "None" (off) or "AHLight" (the AH engine mirrors its own icon here -- the combat
  -- marker frame is just a positioned anchor): draw nothing.
  if symbol == nil or symbol == "None" or symbol == "none" or symbol == "AHLight" then
    for i = 1, MAX_BARS do
      HideTexture(frame.fillBars[i])
      HideTexture(frame.borderBars[i])
    end
    if frame.imageSymbol then frame.imageSymbol:Hide() end
    return
  end

  size = math.max(2, tonumber(size) or 2)
  thickness = math.max(1, tonumber(thickness) or 2)
  borderSize = math.max(0, tonumber(borderSize) or 0)
  a = tonumber(a) or 1
  r, g, b = r or 1, g or 1, b or 1

  -- Media image symbols (manifest) OR the ported Meters "dynamic" symbols
  -- (Bullseye / Class / Specialization) render as a single texture in this frame --
  -- so they follow the same centre/scale/show-when rule as every other marker.
  local imagePath = C.COMBAT_MARKER_IMAGE_PATHS and C.COMBAT_MARKER_IMAGE_PATHS[symbol]
  local tex, cl, cr, ct, cb
  if imagePath then
    tex, cl, cr, ct, cb = imagePath, 0, 1, 0, 1
  elseif C.COMBAT_MARKER_DYNAMIC_VALID and C.COMBAT_MARKER_DYNAMIC_VALID[symbol] then
    tex, cl, cr, ct, cb = ResolveDynamicMarkerTexture(symbol)
  end
  if tex then
    for i = 1, MAX_BARS do
      HideTexture(frame.fillBars[i])
      HideTexture(frame.borderBars[i])
    end
    local img = EnsureMarkerImage(frame)
    img:SetTexture(tex)
    img:SetTexCoord(cl or 0, cr or 1, ct or 0, cb or 1)
    -- Tintable images (white/greyscale, e.g. the crosshairs) follow the marker color;
    -- full-colour art and dynamic Class/Spec icons render as-is.
    if imagePath and C.COMBAT_MARKER_IMAGE_TINT and C.COMBAT_MARKER_IMAGE_TINT[symbol] then
      img:SetVertexColor(r, g, b, a)
    else
      img:SetVertexColor(1, 1, 1, a)
    end
    img:SetSize(PixelSnap(size, frame), PixelSnap(size, frame))
    img:Show()
    return
  end
  if frame.imageSymbol then frame.imageSymbol:Hide() end

  local bars = GetLayoutBars(symbol, size, thickness)
  for i = 1, MAX_BARS do
    local fill = frame.fillBars[i]
    local border = frame.borderBars[i]
    local bar = bars[i]
    if bar then
      local borderThick = math.max(bar.thick, bar.thick + (borderSize * 2))
      local borderLength = bar.length + (borderSize * 2)
      if borderSize > 0 then
        SetTextureBar(border, frame, borderLength, borderThick, bar.rotation, bar.x, bar.y, 0, 0, 0, math.min(1, a * 0.95), "BACKGROUND", i)
      else
        HideTexture(border)
      end
      SetTextureBar(fill, frame, bar.length, bar.thick, bar.rotation, bar.x, bar.y, r, g, b, a, "OVERLAY", i)
    else
      HideTexture(fill)
      HideTexture(border)
    end
  end
end

-- Forward declaration: ApplyMarkerStyleToFrame (below) references this, but its full definition
-- lives further down. Declared local here so the reference binds to the upvalue, not a nil global.
local IsEditingCenterMarkerTab

-- "Press Detection" Center Marker behaviour --------------------------------------------------
-- When Press Detection is ON the chosen Center Marker (whatever symbol it is) MONITORS input and
-- BLINKS like the standalone Pressed Indicator: it is always shown, pulses at the input rate, and
-- (for procedural shapes) flashes green-on-press then dim-red while held -- image / Class / Spec
-- markers keep their resolved colour and just pulse. The standalone Pressed Indicator is
-- unaffected. Both read the same input clock (addon._lastInputTime / _lastGSEPressTime).
local function IsPressDetectionOn()
  return (addon.GetCombatMarkerPressDetection and addon:GetCombatMarkerPressDetection()) and true or false
end

-- Delegates to the Pressed Indicator's shared press-state (ui/indicator.lua: UI:ComputePressState),
-- so the Center Marker's Press Detection Monitors / Shows / Blinks with the SAME code as the PI.
-- Returns: active (just-pressed flash), recentlyUsed (stay shown), pulse (blink alpha 0..1).
local function GetMarkerPressedState()
  if UI.ComputePressState then return UI:ComputePressState() end
  return false, false, 1
end

local function ApplyMarkerStyleToFrame(frame)
  if not frame then return end

  local size = addon.GetCombatMarkerSize and addon:GetCombatMarkerSize() or (C.COMBAT_MARKER_DEFAULT_SIZE or 40)
  local thickness = addon.GetCombatMarkerThickness and addon:GetCombatMarkerThickness() or (C.COMBAT_MARKER_DEFAULT_THICKNESS or 4)
  local borderSize = addon.GetCombatMarkerBorderSize and addon:GetCombatMarkerBorderSize() or (C.COMBAT_MARKER_DEFAULT_BORDER_SIZE or 2)
  local alpha = addon.GetCombatMarkerAlpha and addon:GetCombatMarkerAlpha() or (C.COMBAT_MARKER_DEFAULT_ALPHA or 0.85)
  local symbol = addon.GetCombatMarkerSymbol and addon:GetCombatMarkerSymbol() or (C.COMBAT_MARKER_DEFAULT_SYMBOL or "x")
  local r, g, b = GetResolvedMarkerColor()

  -- "Press Detection": keep the user's chosen symbol but override its colour/draw-alpha with the
  -- press flash (procedural shapes only); image / Class / Spec keep their resolved colour. The
  -- blink (whole-frame alpha) is applied AFTER the style cache so it animates without an
  -- expensive symbol redraw every tick.
  local piMode = IsPressDetectionOn()
  local pulse = 1
  if piMode then
    local active, _, blinkPulse = GetMarkerPressedState()
    pulse = blinkPulse
    -- Hold solid (no blink) while the options/preview is open or it's being dragged, so it can
    -- be seen and positioned.
    if IsEditingCenterMarkerTab() or frame._isDragging then pulse = 1 end
    -- Which symbols are tintable (white) vs keep-their-own-colours:
    local isImage = C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[symbol]
    local isDynamic = C.COMBAT_MARKER_DYNAMIC_VALID and C.COMBAT_MARKER_DYNAMIC_VALID[symbol]
    local isTintable = (not isImage and not isDynamic)  -- procedural vector shapes
      or (isImage and C.COMBAT_MARKER_IMAGE_TINT and C.COMBAT_MARKER_IMAGE_TINT[symbol])  -- white art
    local mode = (addon.GetCombatMarkerColorMode and addon:GetCombatMarkerColorMode()) or "none"
    local hasColorChoice = (mode == "class" or mode == "custom")
    if isTintable and not hasColorChoice then
      -- No colour chosen: flash GREEN while active (pressed), RED while idle.
      if active then
        r, g, b, alpha = C.COLOR_GREEN_R or 0.20, C.COLOR_GREEN_G or 1, C.COLOR_GREEN_B or 0.20, C.ALPHA_STRONG or 0.95
      else
        r, g, b, alpha = C.COLOR_RED_R or 1, C.COLOR_RED_G or 0.20, C.COLOR_RED_B or 0.20, C.ALPHA_DIM or 0.60
      end
    end
    -- Otherwise: tintable + Class/Custom keeps its resolved colour (r,g,b from GetResolvedMarkerColor);
    -- full-colour art / Class / Spec keep their own colours (DrawSymbolOnFrame ignores the tint).
  end

  size = Clamp(tonumber(size) or 40, C.COMBAT_MARKER_MIN_SIZE or 16, C.COMBAT_MARKER_MAX_SIZE or 128)
  -- Fold the Overall (master) addon scale into the RENDERED size so the marker grows about its
  -- centre together with the rest of the UI. The marker uses SetIgnoreParentScale (its drag math
  -- assumes effective scale 1), so scaling the SIZE -- not SetScale -- keeps dragging correct and
  -- avoids drift. The Center Marker Scale slider still shows the raw (unmultiplied) value.
  local gScale = (_G.GSETracker_GetGlobalScale and _G.GSETracker_GetGlobalScale()) or 1
  gScale = tonumber(gScale) or 1
  if gScale ~= 1 then size = size * gScale end
  if size < 1 then size = 1 end  -- SetSize(0)/DrawSymbol with 0 is invalid; floor near-invisible
  thickness = Clamp(tonumber(thickness) or 4, C.COMBAT_MARKER_MIN_THICKNESS or 1, C.COMBAT_MARKER_MAX_THICKNESS or 12)
  borderSize = Clamp(tonumber(borderSize) or 2, C.COMBAT_MARKER_MIN_BORDER_SIZE or 0, C.COMBAT_MARKER_MAX_BORDER_SIZE or 8)
  alpha = Clamp(tonumber(alpha) or 0.85, 0.05, 1.00)

  -- Dynamic symbols (Class/Specialization) resolve their texture per-player, so fold
  -- that into the cache key -- otherwise a spec change wouldn't redraw (same symbol).
  local dynToken = ""
  if C.COMBAT_MARKER_DYNAMIC_VALID and C.COMBAT_MARKER_DYNAMIC_VALID[symbol] then
    dynToken = tostring((ResolveDynamicMarkerTexture(symbol)))
  end
  local styleSig = table.concat({
    tostring(symbol), tostring(size), tostring(thickness), tostring(borderSize),
    string.format("%.3f", alpha),
    string.format("%.3f", r or 1), string.format("%.3f", g or 1), string.format("%.3f", b or 1),
    dynToken, piMode and "pi" or "",
  }, "|")
  if frame._combatMarkerStyleSig ~= styleSig then
    frame._combatMarkerStyleSig = styleSig
    frame:SetSize(PixelSnap(size, frame), PixelSnap(size, frame))
    UI:DrawSymbolOnFrame(frame, symbol, size, thickness, borderSize, r, g, b, alpha)
  end

  -- Blink: cheap whole-frame alpha applied every call. Non-PI mode stays solid at 1. Both are
  -- scaled by the shared Meters opacity so the Center Marker fades with the rest of the cluster.
  frame:SetAlpha((piMode and pulse or 1) * GetMetersOpacity())
end

local function ApplyMarkerPointToFrame(frame, parent, point, x, y)
  if not frame then return end
  parent = parent or UIParent
  x, y = ClampCanonicalOffsets(frame, parent, x, y)
  -- The marker uses SetIgnoreParentScale(true), so its effective scale is 1 and a
  -- SetPoint offset in parent units lands at the wrong screen distance -- the marker
  -- then drifts off the cursor as you drag (moves cursorDelta / UIScale instead of
  -- cursorDelta). Multiply by the parent's effective scale so on-screen movement
  -- tracks the cursor 1:1 (mirrors the frame-scale compensation the action tracker
  -- does in ApplyCenteredOffsets; the assisted highlight instead does not ignore
  -- parent scale).
  local s = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
  if not s or s <= 0 then s = 1 end
  local px = ParentUnitsFromCanonical(x, parent) * s
  local py = ParentUnitsFromCanonical(y, parent) * s

  if uiShared.SetPointIfChanged then
    uiShared.SetPointIfChanged(frame, point, parent, "CENTER", px, py)
  else
    frame:ClearAllPoints()
    frame:SetPoint(point, parent, "CENTER", px, py)
  end
end


function IsEditingCenterMarkerTab()
  if not addon._editingOptions then return false end
  local settingsWindow = addon.settingsWindow
  if not (settingsWindow and settingsWindow.GetSelectedTopTab) then return true end
  return settingsWindow:GetSelectedTopTab() == "CenterMarker"
end

local function GetLiveActionTrackerStrataAndLevel(self)
  local ui = self and self.ui
  if ui and ui.GetFrameStrata then
    local strata = ui:GetFrameStrata()
    if strata and strata ~= "" then
      return strata, math.max(0, (ui:GetFrameLevel() or 0) + COMBAT_MARKER_LEVEL_OFFSET)
    end
  end

  local strata = (self and self.GetStrata and self:GetStrata()) or (C.DEFAULT_COMBAT_TRACKER_STRATA or C.STRATA_MEDIUM or "MEDIUM")
  return strata, (C.ACTION_TRACKER_MARKER_FRAME_LEVEL or 50) + COMBAT_MARKER_LEVEL_OFFSET
end

function UI:ApplyCombatMarkerStrata(frame)
  frame = frame or addon.combatMarkerFrame
  if not frame then return end

  local strata, level = GetLiveActionTrackerStrataAndLevel(self)
  frame:SetFrameStrata(strata)
  frame:SetFrameLevel(level)
end

function UI:EnsureCombatMarker()
  local strata, level = GetLiveActionTrackerStrataAndLevel(self)
  addon.combatMarkerFrame = EnsureMarkerFrame(addon.combatMarkerFrame, UIParent, strata, level)
  addon.centerMarkerFrame = addon.combatMarkerFrame
  if addon.combatMarkerFrame and not addon.combatMarkerFrame._gseMarkerDragScripts then
    local frame = addon.combatMarkerFrame
    frame._gseMarkerDragScripts = true
    frame:SetScript("OnMouseDown", function(selfFrame, button)
      if button ~= "LeftButton" then return end
      if not (addon.CanDragCombatMarker and addon:CanDragCombatMarker()) then return end
      addon:BeginCombatMarkerDrag(selfFrame)
    end)
    frame:SetScript("OnMouseUp", function(selfFrame, button)
      if button ~= "LeftButton" then return end
      if selfFrame._isDragging and addon.EndCombatMarkerDrag then
        addon:EndCombatMarkerDrag(true)
      end
    end)
    frame:SetScript("OnHide", function(selfFrame)
      if selfFrame._isDragging and addon.EndCombatMarkerDrag then
        addon:EndCombatMarkerDrag(false)
      end
    end)
  end
  -- The marker follows the Meters frame's visibility (ShouldShowCombatMarker mirrors
  -- MetersAnchor:IsShown()). Hook the anchor's show/hide so the marker re-evaluates the
  -- instant the meters readout appears/disappears, not just on the next combat event.
  local mAnchor = _G.MetersAnchor
  if mAnchor and not mAnchor._gseMarkerVisibilityHook then
    mAnchor._gseMarkerVisibilityHook = true
    local function syncMarker()
      if addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    end
    mAnchor:HookScript("OnShow", syncMarker)
    mAnchor:HookScript("OnHide", syncMarker)
  end
  self:ApplyCombatMarkerStrata(addon.combatMarkerFrame)
  return addon.combatMarkerFrame
end

function UI:ApplyCombatMarkerStyle(frame)
  ApplyMarkerStyleToFrame(frame or self:EnsureCombatMarker())
end

function UI:ApplyCombatMarkerPosition(frame, parent, point, x, y)
  frame = frame or self:EnsureCombatMarker()
  if not frame then return end
  if point == nil then
    point, x, y = GetCenteredAnchorConfig()
  end
  ApplyMarkerPointToFrame(frame, parent or GetMarkerParent(), point, x, y)
end

function UI:BeginCombatMarkerDrag(frame)
  frame = frame or addon.combatMarkerFrame
  if not frame then return false end
  if frame._isDragging then return true end
  if not self:CanDragCombatMarker() then return false end

  local point = addon.GetCombatMarkerAnchorPoint and addon:GetCombatMarkerAnchorPoint() or ((C.COMBAT_MARKER_DEFAULT_POINT and C.COMBAT_MARKER_DEFAULT_POINT[1]) or "CENTER")
  local x, y = addon:GetCombatMarkerOffset()
  self._combatMarkerDragOrigin = { point, x, y }
  self._combatMarkerDragCursorOriginX, self._combatMarkerDragCursorOriginY = GetCursorPositionInParentSpace(UIParent)
  frame._isDragging = true
  frame:SetScript("OnUpdate", CombatMarkerDragOnUpdate)
  self:SyncActiveCombatMarkerDragPosition()
  return true
end

function UI:EndCombatMarkerDrag(commit)
  local frame = addon.combatMarkerFrame
  if not (frame and frame._isDragging) then return false end

  if commit then
    self:SyncActiveCombatMarkerDragPosition()
  else
    local origin = self._combatMarkerDragOrigin
    if origin then
      addon:SetCombatMarkerPoint(origin[1], C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", origin[2], origin[3])
      self:ApplyCombatMarkerPosition(frame, UIParent, origin[1], origin[2], origin[3])
    end
  end

  frame._isDragging = false
  frame:SetScript("OnUpdate", nil)
  self._combatMarkerDragOrigin = nil
  self._combatMarkerDragCursorOriginX = nil
  self._combatMarkerDragCursorOriginY = nil

  local settingsWindow = addon.settingsWindow
  if settingsWindow and settingsWindow.RefreshCombatMarkerControls then
    settingsWindow:RefreshCombatMarkerControls()
  end
  self:RefreshCombatMarkerDragMouseState()
  return true
end

function UI:CanDragCombatMarker()
  -- The Center Marker is no longer independently draggable: it is pinned to the Meters
  -- centre and moves only when the Meters text is dragged. Returning false here also keeps
  -- the marker mouse-disabled (RefreshCombatMarkerDragMouseState) so clicks fall through to
  -- the Meters anchor underneath -- letting the user grab the Meters text where the marker sits.
  return false
end

function UI:RefreshCombatMarkerDragMouseState()
  local frame = addon and addon.combatMarkerFrame
  if frame then
    local canDrag = self:CanDragCombatMarker()
    if (not canDrag) and frame._isDragging then
      self:EndCombatMarkerDrag(true)
      return
    end
    frame._canDragCombatMarker = canDrag
    frame:EnableMouse(canDrag)
  end
end

function UI:SyncActiveCombatMarkerDragPosition()
  local frame = addon and addon.combatMarkerFrame
  if not (frame and frame._isDragging) then return false end

  local origin = self._combatMarkerDragOrigin
  local startCursorX = self._combatMarkerDragCursorOriginX
  local startCursorY = self._combatMarkerDragCursorOriginY

  local point = addon.GetCombatMarkerAnchorPoint and addon:GetCombatMarkerAnchorPoint() or ((C.COMBAT_MARKER_DEFAULT_POINT and C.COMBAT_MARKER_DEFAULT_POINT[1]) or "CENTER")
  local x, y
  if origin and startCursorX ~= nil and startCursorY ~= nil then
    local cursorX, cursorY = GetCursorPositionInParentSpace(UIParent)
    x = (tonumber(origin[2]) or 0) + ParentUnitsToCanonical(cursorX - startCursorX, UIParent)
    y = (tonumber(origin[3]) or 0) + ParentUnitsToCanonical(cursorY - startCursorY, UIParent)
  else
    x, y = addon:GetCombatMarkerOffset()
  end

  x, y = ClampCanonicalOffsets(frame, UIParent, x, y)
  addon:SetCombatMarkerPoint(point, C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", x, y)
  self:ApplyCombatMarkerPosition(frame, GetMarkerParent(), point, x, y)

  local settingsWindow = addon.settingsWindow
  if settingsWindow and settingsWindow.RefreshCombatMarkerControls then
    settingsWindow:RefreshCombatMarkerControls()
  end
  return true
end

function UI:ShouldShowCombatMarker(forceOverride)
  -- The Center Marker is pinned to the Meters readout's centre and has NO independent
  -- enable/show of its own -- it simply follows the Meters frame's visibility: shown when
  -- the Meters readout is shown, hidden otherwise. (forceOverride / editing-tab preview
  -- still forces it visible so it can be seen while the options window is open.)
  if forceOverride == true or IsEditingCenterMarkerTab() then
    return true
  end
  -- Press Detection: behave exactly like the standalone Pressed Indicator -- ALWAYS AVAILABLE
  -- (independent of combat / the Meters readout), shown and pulsing while there's recent input,
  -- and faded ALL THE WAY out (hidden) when no input is detected. The blink/colour is handled in
  -- ApplyMarkerStyleToFrame.
  if IsPressDetectionOn() then
    local _, recentlyUsed = GetMarkerPressedState()
    return recentlyUsed and true or false
  end
  local anchor = _G.MetersAnchor
  if anchor and anchor.IsShown then
    return anchor:IsShown() and true or false
  end
  return false
end

-- Lightweight ~20Hz ticker that re-refreshes the Center Marker while it's in Pressed Indicator
-- mode and recently used, so it blinks and auto-hides after the hold window -- exactly like the
-- standalone indicator. Uses a DEDICATED frame, NOT the marker's own OnUpdate (which the drag
-- system owns), so the two never fight over the script.
local function CombatMarkerPiOnUpdate(driver, elapsed)
  driver._tick = (driver._tick or 0) + (elapsed or 0)
  if driver._tick < 0.05 then return end
  driver._tick = 0
  if not (addon and addon.RefreshCombatMarker) then
    driver._active = false
    driver:SetScript("OnUpdate", nil)
    return
  end
  addon:RefreshCombatMarker()
end

function UI:StartCombatMarkerPiDriver()
  local d = addon._combatMarkerPiDriver
  if not d then
    d = (API.CreateFrame and API.CreateFrame("Frame")) or _G.CreateFrame("Frame")
    addon._combatMarkerPiDriver = d
  end
  if d._active then return end
  d._active = true
  d._tick = 0
  d:SetScript("OnUpdate", CombatMarkerPiOnUpdate)
end

function UI:StopCombatMarkerPiDriver()
  local d = addon._combatMarkerPiDriver
  if not (d and d._active) then return end
  d._active = false
  d._tick = 0
  d:SetScript("OnUpdate", nil)
end

function UI:RefreshCombatMarker(force)
  local frame = self:EnsureCombatMarker()
  if not frame then return end

  self:ApplyCombatMarkerStyle(frame)
  self:ApplyCombatMarkerPosition(frame)

  local show = self:ShouldShowCombatMarker(force)
  if show then
    frame:Show()
  else
    frame:Hide()
  end

  -- With Press Detection on, keep the blink ticker running while it's shown and there's recent
  -- input; stop it otherwise (and always when off).
  if show and IsPressDetectionOn() then
    local _, recentlyUsed = GetMarkerPressedState()
    if recentlyUsed then
      self:StartCombatMarkerPiDriver()
    else
      self:StopCombatMarkerPiDriver()
    end
  else
    self:StopCombatMarkerPiDriver()
  end

  self:RefreshCombatMarkerDragMouseState()
end

function UI:EnsureCenterMarker()
  return self:EnsureCombatMarker()
end

function UI:RefreshCenterMarker(force)
  return self:RefreshCombatMarker(force)
end
