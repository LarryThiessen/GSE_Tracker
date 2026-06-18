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
  if not fs or fs == 0 then fs = 1 end
  local offX = (fx * fs - ax * as) / fs
  local offY = (fy * fs - ay * as) / fs
  if self.SetElementOffset then self:SetElementOffset("pressedIndicator", offX, offY) end
end

-- Enable/disable dragging of the pressed indicator to match the unlock option.
function UI:UpdatePressedIndicatorDragState()
  local ui = self.ui
  local frame = ui and ui.pressedIndicator
  if not frame then return end
  local unlocked = self:GetPressedIndicatorUnlocked()

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
    local UnitClass = _G.UnitClass
    local _, classFile = (UnitClass and UnitClass("player"))
    local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then return c.r, c.g, c.b end
  end
  return 1, 1, 1
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

  local isImage = C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[shape]
  local r, g, b, a
  if isImage then
    -- Image symbols: tint by the chosen colour mode (Class / Custom / None=no tint), at
    -- full opacity. They don't take the procedural green/red flash.
    r, g, b = ResolvePressedIndicatorRGB(self)
    a = 1
  else
    -- Procedural shapes use the current flash/dim colour.
    r = target._piColorR or (C.COLOR_RED_R or 1)
    g = target._piColorG or (C.COLOR_RED_G or 0.20)
    b = target._piColorB or (C.COLOR_RED_B or 0.20)
    a = target._piColorA or (C.ALPHA_DEFAULT or 0.90)
  end
  if self.DrawSymbolOnFrame then
    self:DrawSymbolOnFrame(target, shape, baseSize, thickness, 0, r, g, b, a)
  end
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
  -- The indicator is now parented to UIParent (independent of the tracker frame's
  -- visibility) so a left-on spammer shows even when the tracker is hidden. But it
  -- must still respect the addon being turned off entirely.
  if enabled and self.IsEnabled and not self:IsEnabled() then
    enabled = false
  end

  local inCombat = (API.InCombatLockdown and API.InCombatLockdown()) and true or false
  local editing = addon._editingOptions or (self.IsEditModePreviewActive and self:IsEditModePreviewActive()) or false
  local active = false        -- brief "just pressed" flash (green tint for shapes)
  local recentlyUsed = false  -- stays visible while there's recent input
  -- Use the most recent of ANY key input or a GSE macro fire.
  local lastInput = math.max(tonumber(self._lastInputTime) or 0, tonumber(self._lastGSEPressTime) or 0)
  if lastInput > 0 then
    local dt = API.GetTime() - lastInput
    active = dt <= (C.PRESSED_INDICATOR_ACTIVE_WINDOW or 0.20)
    recentlyUsed = dt <= (C.PRESSED_INDICATOR_HOLD_WINDOW or 1.5)
  end
  -- Show whenever there's recent input -- in OR out of combat, tracker shown or
  -- hidden -- so a left-on spammer is always visible. Always show in editing/preview, and
  -- while UNLOCKED, so it can be positioned by dragging.
  local _ = inCombat -- (combat no longer gates the indicator)
  local unlocked = self.GetPressedIndicatorUnlocked and self:GetPressedIndicatorUnlocked() or false
  local shouldShow = enabled and (editing or recentlyUsed or unlocked)

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
  -- Held solid while editing or unlocked so it can be dragged into place. Set on the frame
  -- BEFORE the image early-return below, so IMAGE shapes (e.g. Crosshair) pulse too.
  do
    local pulse = 1
    if not (editing or unlocked) then
      local blinkDur = C.PRESSED_INDICATOR_BLINK_DURATION or 0.16
      local sinceInput = (lastInput > 0) and (API.GetTime() - lastInput) or blinkDur
      local minAlpha = C.PRESSED_INDICATOR_BLINK_MIN_ALPHA or 0.40
      local t = sinceInput / blinkDur
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      pulse = minAlpha + (1 - minAlpha) * (1 - t)
    end
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

  -- Image symbols keep their own colours (no green/red tint); procedural shapes flash
  -- green on press then sit dim-red while still held.
  if C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[shape] then return end

  if not force and ui._pressedIndicatorActive == active then return end
  ui._pressedIndicatorActive = active
  if active then
    self:SetPressedIndicatorColor(ui.pressedIndicator, C.COLOR_GREEN_R or 0.20, C.COLOR_GREEN_G or 1, C.COLOR_GREEN_B or 0.20, C.ALPHA_STRONG or 0.95)
  else
    self:SetPressedIndicatorColor(ui.pressedIndicator, C.COLOR_RED_R or 1, C.COLOR_RED_G or 0.20, C.COLOR_RED_B or 0.20, C.ALPHA_DIM or 0.60)
  end
end
