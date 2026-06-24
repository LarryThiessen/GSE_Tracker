local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local uiShared = addon._ui or {}
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local WHITE8X8 = C.TEXTURE_WHITE8X8 or "Interface/Buttons/WHITE8x8"

function UI:GetPressedIndicatorShape()
  if ns.Utils and ns.Utils.GetPressedIndicatorShape then
    return ns.Utils:GetPressedIndicatorShape()
  end
  uiShared.EnsureDB()
  return tostring(C.DEFAULT_PRESSED_INDICATOR_SHAPE or "circle")
end

function UI:GetPressedIndicatorSize()
  if ns.Utils and ns.Utils.GetPressedIndicatorSize then
    return ns.Utils:GetPressedIndicatorSize()
  end
  uiShared.EnsureDB()
  return uiShared.Clamp(tonumber(C.DEFAULT_PRESSED_INDICATOR_SIZE) or 10, C.PRESSED_INDICATOR_MIN_SIZE or 4, C.PRESSED_INDICATOR_MAX_SIZE or 24)
end

function UI:GetPressedIndicatorShowWhen()
  if ns.Utils and ns.Utils.GetPressedIndicatorShowWhen then
    return ns.Utils:GetPressedIndicatorShowWhen()
  end
  return (C.MODE_ALWAYS or "Always")
end

function UI:GetPressedIndicatorColorMode()
  if ns.Utils and ns.Utils.GetPressedIndicatorColorMode then
    return ns.Utils:GetPressedIndicatorColorMode()
  end
  return "none"
end

function UI:GetPressedIndicatorCustomColor()
  if ns.Utils and ns.Utils.GetPressedIndicatorCustomColor then
    return ns.Utils:GetPressedIndicatorCustomColor()
  end
  return 1, 0.82, 0
end

function UI:GetPressedIndicatorUnlocked()
  if ns.Utils and ns.Utils.GetPressedIndicatorUnlocked then
    return ns.Utils:GetPressedIndicatorUnlocked()
  end
  return false
end

-- After a drag, store the indicator's new position as an offset from its anchor (the icon
-- row centre), so the element system re-applies it. Scale-compensated because the indicator
-- lives on UIParent while its anchor is inside the scaled tracker.
local function StorePressedIndicatorDragOffset(self)
  local ui = self.ui
  local frame = ui and ui.pressedIndicator
  local anchor = (self.GetElementAnchorTarget and self:GetElementAnchorTarget("pressedIndicator")) or (ui and ui.content) or ui
  if not (frame and anchor and frame.GetCenter and anchor.GetCenter) then return end
  local fx, fy = frame:GetCenter()
  local ax, ay = anchor:GetCenter()
  if not (fx and fy and ax and ay) then return end
  local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
  local as = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
  local ue = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  if not ue or ue == 0 then ue = 1 end
  -- Store the offset in UIParent units (scale-independent) so the indicator keeps the same screen
  -- position when the Overall scale later changes its own scale; ApplyElementPosition re-divides by
  -- the indicator's current scale. (At scale 1, fs == ue, so this matches the previous behaviour.)
  local offX = (fx * fs - ax * as) / ue
  local offY = (fy * fs - ay * as) / ue
  if self.SetElementOffset then self:SetElementOffset("pressedIndicator", offX, offY) end
end

-- The pressed indicator is positioned through its Edit Mode "Click to Edit" box (which calls
-- StartMoving on this frame during a box drag, see ui/editmode.lua) -- the standard element lock
-- behaviour. So the frame itself is always LOCKED for direct mouse: never draggable in normal play,
-- and the box (a higher-level child) handles all dragging while editing.
function UI:UpdatePressedIndicatorDragState()
  local ui = self.ui
  local frame = ui and ui.pressedIndicator
  if not frame then return end
  local unlocked = false

  if not frame._gsetPiDragScripts then
    frame._gsetPiDragScripts = true
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(selfFrame)
      if not (addon.GetPressedIndicatorUnlocked and addon:GetPressedIndicatorUnlocked()) then return end
      if selfFrame.SetMovable then selfFrame:SetMovable(true) end
      selfFrame:StartMoving()
      selfFrame._gsetPiMoving = true
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
      if not selfFrame._gsetPiMoving then return end
      selfFrame._gsetPiMoving = false
      selfFrame:StopMovingOrSizing()
      if addon.StorePressedIndicatorDragOffset_Internal then addon:StorePressedIndicatorDragOffset_Internal() end
      if addon.ApplyElementPosition then addon:ApplyElementPosition("pressedIndicator") end
    end)
  end

  frame:SetMovable(unlocked)
  frame:EnableMouse(unlocked)
  -- Strata stays HIGH (set at creation); while the options panel is open the indicator is
  -- HIDDEN by RefreshPressedIndicator rather than lowered, so it never goes behind its icons.
end

-- Thin wrapper so the OnDragStop closure (which only has the addon table) can reach the
-- file-local StorePressedIndicatorDragOffset.
function UI:StorePressedIndicatorDragOffset_Internal()
  StorePressedIndicatorDragOffset(self)
end

-- The base tint for an image pressed-indicator: class colour, the custom colour, or -- when
-- neither Class nor Custom is selected -- NO tint (1,1,1), so the image shows as-is.
local function ResolvePressedIndicatorRGB(self)
  local mode = self:GetPressedIndicatorColorMode()
  if mode == "custom" then
    return self:GetPressedIndicatorCustomColor()
  elseif mode == "class" then
    -- Use the shared resolver (correctly reads the 2nd return of UnitClass and handles the
    -- Classic SHAMAN colour quirk). Falls back to no-tint (1,1,1) if the colour can't resolve.
    if uiShared.GetPlayerClassColorRGB then
      return uiShared.GetPlayerClassColorRGB(1, 1, 1)
    end
    if _G.UnitClass then
      local _, classFile = _G.UnitClass("player")  -- NOTE: capture the 2nd return, don't truncate
      local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
      local c = classFile and colors and colors[classFile]
      if c then return c.r, c.g, c.b end
    end
  end
  return 1, 1, 1
end

-- Resolve the draw colour for a Pressed Indicator shape given the press state. TINTABLE (white)
-- symbols -- procedural shapes and white/greyscale image art -- follow the chosen colour mode;
-- with NO colour chosen they flash GREEN while active (pressed) and RED while idle. Full-colour
-- art keeps its own colours (the renderer ignores the tint for those). Returns r, g, b, a.
local function ResolvePressedIndicatorShapeColor(self, shape, active)
  local isImage = C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[shape]
  local isTintable = (not isImage)  -- procedural vector shapes are always tintable
    or (C.COMBAT_MARKER_IMAGE_TINT and C.COMBAT_MARKER_IMAGE_TINT[shape])  -- white/greyscale art
  if not isTintable then
    return 1, 1, 1, 1  -- full-colour art: render as-is (no recolour)
  end
  local mode = self:GetPressedIndicatorColorMode()
  if mode == "class" or mode == "custom" then
    local r, g, b = ResolvePressedIndicatorRGB(self)
    return r, g, b, 1
  end
  if active then
    return C.COLOR_GREEN_R or 0.20, C.COLOR_GREEN_G or 1, C.COLOR_GREEN_B or 0.20, C.ALPHA_STRONG or 0.95
  end
  return C.COLOR_RED_R or 1, C.COLOR_RED_G or 0.20, C.COLOR_RED_B or 0.20, C.ALPHA_DIM or 0.60
end

function UI:SetPressedIndicatorColor(frame, r, g, b, a)
  local target = frame or (self.ui and self.ui.pressedIndicator)
  if not target then return end
  local cr, cg, cb, ca = r or (C.COLOR_RED_R or 1), g or (C.COLOR_RED_G or 0.20), b or (C.COLOR_RED_B or 0.20), a or (C.ALPHA_DEFAULT or 0.90)
  target._piColorR, target._piColorG, target._piColorB, target._piColorA = cr, cg, cb, ca
  -- Redraw the symbol in the new colour via the shared renderer. Procedural shapes
  -- tint; image symbols keep their own colours (the renderer ignores the tint for
  -- images). Skipped until ApplyPressedIndicatorStyle has recorded the geometry.
  if self.DrawSymbolOnFrame and target._piShape then
    self:DrawSymbolOnFrame(target, target._piShape, target._piDrawSize or (target.GetWidth and target:GetWidth()) or 10, target._piThickness or 2, 0, cr, cg, cb, ca)
  end
end

function UI:ApplyPressedIndicatorStyle(frame)
  local ui = self.ui
  local target = frame or (ui and ui.pressedIndicator)
  if not target then return end

  local shape = self:GetPressedIndicatorShape()
  local configuredSize = self:GetPressedIndicatorSize()
  local baseSize = uiShared.PixelSnap(configuredSize, ui or target)
  -- Bar thickness scales with size so procedural shapes stay legible at small sizes.
  local thickness = math.max(2, math.floor((configuredSize * 0.22) + 0.5))

  target:SetSize(baseSize, baseSize)
  if self.UpdateActionTrackerRowRelativeAnchors then
    self:UpdateActionTrackerRowRelativeAnchors()
  end

  -- Hide the legacy single-texture shape art (tex/cross/mask). The shared symbol
  -- renderer now draws into its own bar/image textures on the frame, so the pressed
  -- indicator offers the same symbol set as the player-tracker marker.
  if target.tex then target.tex:Hide() end
  if target.crossH then target.crossH:Hide() end
  if target.crossV then target.crossV:Hide() end
  if target.mask then target.mask:Hide() end

  -- Record geometry so colour flashes (SetPressedIndicatorColor) can redraw cheaply.
  target._piShape = shape
  target._piDrawSize = baseSize
  target._piThickness = thickness

  -- Tintable shapes (procedural + white image art) follow the colour mode, or flash green/red
  -- when no colour is chosen; full-colour art keeps its own colours. Use the current press state.
  local active = (ui and ui._pressedIndicatorActive) or false
  local r, g, b, a = ResolvePressedIndicatorShapeColor(self, shape, active)
  if self.DrawSymbolOnFrame then
    self:DrawSymbolOnFrame(target, shape, baseSize, thickness, 0, r, g, b, a)
  end
end

-- Shared press state, used by BOTH the Pressed Indicator (below) and the Center Marker's Press
-- Detection mode (ui/player_tracker.lua), so the two Monitor / Show / Blink with the SAME code.
-- Reads the most recent of ANY key/wheel input (addon._lastInputTime) or a GSE macro fire
-- (addon._lastGSEPressTime). Returns:
--   active       -- within the brief just-pressed flash window (green tint for procedural shapes)
--   recentlyUsed -- within the hold window -> stay shown (hidden / faded out otherwise)
--   pulse        -- blink alpha 0..1 (full-bright on press, easing to the dim floor between)
function UI:ComputePressState()
  local now = API.GetTime()
  local lastInput = math.max(tonumber(addon._lastInputTime) or 0, tonumber(addon._lastGSEPressTime) or 0)
  local active, recentlyUsed, pulse = false, false, 1
  if lastInput > 0 and now and now > 0 then
    local dt = now - lastInput
    active = dt <= (C.PRESSED_INDICATOR_ACTIVE_WINDOW or 0.20)
    recentlyUsed = dt <= (C.PRESSED_INDICATOR_HOLD_WINDOW or 1.5)
    local blinkDur = C.PRESSED_INDICATOR_BLINK_DURATION or 0.16
    local minAlpha = C.PRESSED_INDICATOR_BLINK_MIN_ALPHA or 0.40
    local t = dt / blinkDur
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    pulse = minAlpha + (1 - minAlpha) * (1 - t)
  end
  return active, recentlyUsed, pulse
end

local function PressedIndicatorOnUpdate(driverFrame, elapsed)
  driverFrame._tick = (driverFrame._tick or 0) + (elapsed or 0)
  if driverFrame._tick < 0.05 then return end
  driverFrame._tick = 0

  if not (addon and addon.RefreshPressedIndicator) then
    driverFrame._driverActive = false
    driverFrame:SetScript("OnUpdate", nil)
    return
  end

  addon:RefreshPressedIndicator()
  if not driverFrame:IsShown() or not driverFrame._indicatorDriverNeeded then
    driverFrame._driverActive = false
    driverFrame:SetScript("OnUpdate", nil)
  end
end

function UI:StopPressedIndicatorDriver(frame)
  local target = frame or (self.ui and self.ui.pressedIndicator)
  if not target then return end
  target._tick = 0
  target._driverActive = false
  target:SetScript("OnUpdate", nil)
end

function UI:StartPressedIndicatorDriver(frame)
  local target = frame or (self.ui and self.ui.pressedIndicator)
  if not target then return end
  if target._driverActive then return end
  target._driverActive = true
  target._tick = 0
  target:SetScript("OnUpdate", PressedIndicatorOnUpdate)
end

function UI:SetupPressedIndicator(ui)
  if not ui then return end
  local pressedSize = self:GetPressedIndicatorSize()
  -- Parented to UIParent (NOT ui.content) so it can show even when the tracker is
  -- hidden out of combat -- so a left-on spammer is visible on a clean UI. It stays
  -- positioned at the tracker (anchored to the icon row via the element system) and
  -- sits at HIGH strata so it draws above the icons when the tracker IS shown.
  ui.pressedIndicator = API.CreateFrame("Frame", nil, _G.UIParent)
  ui.pressedIndicator:SetSize(uiShared.PixelSnap(pressedSize, ui), uiShared.PixelSnap(pressedSize, ui))
  ui.pressedIndicator:SetFrameStrata("HIGH")
  ui.elements.pressedIndicator = ui.pressedIndicator
  ui.pressedIndicator.tex = ui.pressedIndicator:CreateTexture(nil, "OVERLAY")
  ui.pressedIndicator.tex:SetAllPoints()
  ui.pressedIndicator.tex:SetTexture(WHITE8X8)
  -- Full opacity so it reads clearly over the icons (was 0.90).
  self:SetPressedIndicatorColor(ui.pressedIndicator, C.COLOR_RED_R or 1, C.COLOR_RED_G or 0.20, C.COLOR_RED_B or 0.20, 1)
  ui.pressedIndicator.mask = ui.pressedIndicator:CreateMaskTexture(nil, "OVERLAY")
  ui.pressedIndicator.mask:SetAllPoints(ui.pressedIndicator.tex)
  ui.pressedIndicator:Hide()
  ui.pressedIndicator._driverActive = false
  ui.pressedIndicator._indicatorDriverNeeded = false
  ui.pressedIndicator._styleSig = nil
  self:ApplyPressedIndicatorStyle(ui.pressedIndicator)

  -- Global input monitor: ANY key press (or mouse wheel) marks recent input so the
  -- Pressed Indicator lights up -- e.g. an F1 spammer -- not only when the GSE macro
  -- actually fires. SetPropagateKeyboardInput(true) passes keys straight through so
  -- bindings / movement / chat keep working. Enabled out of combat (that call is
  -- combat-sensitive); login/reload-OOC covers the normal case.
  if not addon._inputMonitor then
    local mon = API.CreateFrame("Frame")
    local function mark()
      addon._lastInputTime = API.GetTime()
      if addon.RefreshPressedIndicator then addon:RefreshPressedIndicator() end
      -- If the Center Marker has Press Detection on, wake it on the same input so it
      -- monitors/blinks in lockstep with the standalone indicator.
      if addon.RefreshCombatMarker and addon.GetCombatMarkerPressDetection
        and addon:GetCombatMarkerPressDetection() then
        addon:RefreshCombatMarker()
      end
    end
    mon:SetScript("OnKeyDown", mark)
    mon:SetScript("OnMouseWheel", mark)
    addon._inputMonitor = mon
  end
  if not (API.InCombatLockdown and API.InCombatLockdown()) then
    local mon = addon._inputMonitor
    mon:EnableKeyboard(true)
    if mon.SetPropagateKeyboardInput then mon:SetPropagateKeyboardInput(true) end
    if mon.EnableMouseWheel then mon:EnableMouseWheel(true) end
  end
end

function UI:RefreshPressedIndicator(force)
  local ui = self.ui
  if not (ui and ui.pressedIndicator and ui.pressedIndicator.tex) then return end

  local cfg, defaults = self:GetElementLayout("pressedIndicator")
  local enabled = true
  if type(cfg) == "table" and cfg.enabled ~= nil then
    enabled = cfg.enabled and true or false
  elseif defaults and defaults.enabled ~= nil then
    enabled = defaults.enabled and true or false
  end
  -- The Pressed Indicator is its OWN element, SEPARATE from the Action Tracker. It is governed solely by
  -- its own enable (above) -- NOT by the Action Tracker's enable (IsEnabled). It's parented to UIParent,
  -- so it shows even when the tracker frame is hidden or the Action Tracker is disabled.

  local inCombat = (API.InCombatLockdown and API.InCombatLockdown()) and true or false
  local editing = addon._editingOptions or (self.IsEditModePreviewActive and self:IsEditModePreviewActive()) or false
  -- Shared press state (the SAME code the Center Marker's Press Detection uses). active = brief
  -- just-pressed flash; recentlyUsed = stay shown; blinkPulse = blink alpha for the pulse below.
  local active, recentlyUsed, blinkPulse = UI:ComputePressState()
  -- Show whenever there's recent input -- in OR out of combat, tracker shown or
  -- hidden -- so a left-on spammer is always visible. Always show in editing/preview, and
  -- while UNLOCKED, so it can be positioned by dragging.
  -- Visibility (Show-When) gate: applies ONLY to live play. Edit Mode always shows the indicator so it
  -- can be positioned (via its "Click to Edit" box, the standard element lock behaviour). "Always" =
  -- input-driven as before; "In Combat" / "Has Target" additionally require that state; "Never" hides
  -- it outside Edit Mode.
  local showWhenOK = true
  if not editing then
    local mode = self.GetPressedIndicatorShowWhen and self:GetPressedIndicatorShowWhen() or "Always"
    if mode == "Never" then
      showWhenOK = false
    elseif mode == "InCombat" then
      showWhenOK = inCombat
    elseif mode == "HasTarget" then
      showWhenOK = (API.HasHarmTarget and API.HasHarmTarget()) or false
    end
  end
  local shouldShow = enabled and showWhenOK and (editing or recentlyUsed)

  local shape = self.GetPressedIndicatorShape and self:GetPressedIndicatorShape() or (C.DEFAULT_PRESSED_INDICATOR_SHAPE or "dot")
  local size = self.GetPressedIndicatorSize and self:GetPressedIndicatorSize() or (C.DEFAULT_PRESSED_INDICATOR_SIZE or 10)
  local styleSig = tostring(shape) .. "|" .. tostring(size)

  if not shouldShow then
    ui._pressedIndicatorActive = false
    ui.pressedIndicator._indicatorDriverNeeded = false
    if self.StopPressedIndicatorDriver then self:StopPressedIndicatorDriver(ui.pressedIndicator) end
    ui.pressedIndicator:Hide()
    return
  end

  ui.pressedIndicator:Show()
  ui.pressedIndicator._indicatorDriverNeeded = recentlyUsed and true or false
  if self.UpdatePressedIndicatorDragState then self:UpdatePressedIndicatorDragState() end

  -- BLINK at the input rate: full-bright the instant a monitored key / GSE fire lands,
  -- then ease toward a DIM-BUT-VISIBLE floor between presses, so the image visibly pulses
  -- as fast as the input it's watching. It never fades to invisible (that read as "gone").
  -- Held solid while editing so it can be dragged into place. Set on the frame
  -- BEFORE the image early-return below, so IMAGE shapes (e.g. Crosshair) pulse too.
  do
    -- Held solid while editing (Edit Mode positioning); otherwise blink at the input rate.
    local pulse = editing and 1 or blinkPulse
    ui.pressedIndicator:SetAlpha(pulse)
  end

  if ui.pressedIndicator._styleSig ~= styleSig and self.ApplyPressedIndicatorStyle then
    ui.pressedIndicator._styleSig = styleSig
    self:ApplyPressedIndicatorStyle(ui.pressedIndicator)
    force = true
  end

  if recentlyUsed then
    if self.StartPressedIndicatorDriver then self:StartPressedIndicatorDriver(ui.pressedIndicator) end
  elseif self.StopPressedIndicatorDriver then
    self:StopPressedIndicatorDriver(ui.pressedIndicator)
  end

  -- Tintable shapes (procedural + white/greyscale image art) recolour on press; full-colour art
  -- keeps its own colours and never takes the green/red flash.
  local isImage = C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[shape]
  local isTintable = (not isImage) or (C.COMBAT_MARKER_IMAGE_TINT and C.COMBAT_MARKER_IMAGE_TINT[shape])
  if not isTintable then return end

  if not force and ui._pressedIndicatorActive == active then return end
  ui._pressedIndicatorActive = active
  -- Class/Custom -> that colour; no colour chosen -> GREEN while active, RED while idle.
  local r, g, b, a = ResolvePressedIndicatorShapeColor(self, shape, active)
  self:SetPressedIndicatorColor(ui.pressedIndicator, r, g, b, a)
end
