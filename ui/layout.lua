local _, ns = ...
local addon = ns
local UI = ns.UI
local uiShared = addon._ui or {}
local pixelSnap = uiShared.PixelSnap
local ELEMENT_DEFAULTS = uiShared.ELEMENT_DEFAULTS or {}
local SV = (ns.Utils and ns.Utils.SV) or nil

-- The ACTIVE saved store (account or per-character). Element layout lives here, so
-- it must follow the same store as every other setting.
local function ActiveDB()
  -- Read-only active store (no global self-assign writes); falls back to GetDB
  -- (which creates the store once) only if the read-only ref isn't ready yet.
  if SV and SV.GetActiveDBRaw then
    local db = SV:GetActiveDBRaw()
    if db then return db end
  end
  if SV and SV.GetDB then return SV:GetDB() end
  return _G.GSETrackerDB or {}
end

local CENTERED_OFFSET_MODEL_VERSION = 2
local ROW_RELATIVE_ANCHOR_MODEL_VERSION = 2
local _layoutMigrationsApplied = false
local TEXT_ROW_OFFSET_MAX_X = 40
local TEXT_ROW_OFFSET_MAX_Y = 24

local ROW_RELATIVE_BASELINES = {
  sequenceText = { x = 0, y = 17 },
  modifiersText = { x = 0, y = -15 },
  keybindText = { x = 0, y = 27 },
}

local LEGACY_ELEMENT_DEFAULTS = {
  sequenceText = { point = "TOP", relativePoint = "TOP", x = 0, y = -13 },
  modifiersText = { point = "TOP", relativePoint = "TOP", x = 0, y = -50 },
  keybindText = { point = "TOP", relativePoint = "TOP", x = 0, y = -3 },
  pressedIndicator = { point = "LEFT", relativePoint = "RIGHT", x = 8, y = 0 },
}

local function SetElementPointIfNeeded(frame, point, anchor, relativePoint, x, y)
  return uiShared.SetPointIfChanged(frame, point, anchor, relativePoint, x, y)
end


local function RoundNearest(v)
  v = tonumber(v) or 0
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return math.ceil(v - 0.5)
end

local function GetOffsetModelVersion(db)
  if type(db) ~= "table" then return 0 end
  local layout = db.layout
  if type(layout) ~= "table" then return 0 end
  return tonumber(layout.offsetModelVersion) or 0
end

local function HasLegacyExactOffset(cfg, legacyDefaults)
  if type(cfg) ~= "table" or type(legacyDefaults) ~= "table" then return false end
  return (tonumber(cfg.x) or 0) == (tonumber(legacyDefaults.x) or 0)
    and (tonumber(cfg.y) or 0) == (tonumber(legacyDefaults.y) or 0)
end

local function NeedsBrokenCenteredOffsetRepair(db)
  if type(db) ~= "table" then return false end
  local layout = db.layout
  if type(layout) ~= "table" then return false end
  if layout.centeredOffsetRepairApplied then return false end
  if GetOffsetModelVersion(db) < CENTERED_OFFSET_MODEL_VERSION then return true end

  local elements = layout.elements
  if type(elements) ~= "table" then return false end

  local sequenceLegacy = HasLegacyExactOffset(elements.sequenceText, LEGACY_ELEMENT_DEFAULTS.sequenceText)
  local modifiersLegacy = HasLegacyExactOffset(elements.modifiersText, LEGACY_ELEMENT_DEFAULTS.modifiersText)
  local keybindLegacy = HasLegacyExactOffset(elements.keybindText, LEGACY_ELEMENT_DEFAULTS.keybindText)
  local indicatorLegacy = HasLegacyExactOffset(elements.pressedIndicator, LEGACY_ELEMENT_DEFAULTS.pressedIndicator)

  if sequenceLegacy and modifiersLegacy and keybindLegacy then
    return true
  end

  local exactLegacyCount = 0
  if sequenceLegacy then exactLegacyCount = exactLegacyCount + 1 end
  if modifiersLegacy then exactLegacyCount = exactLegacyCount + 1 end
  if keybindLegacy then exactLegacyCount = exactLegacyCount + 1 end
  if indicatorLegacy then exactLegacyCount = exactLegacyCount + 1 end
  return exactLegacyCount >= 3
end

local function SetOffsetModelVersion(db, version)
  if type(db) ~= "table" then return end
  db.layout = db.layout or {}
  db.layout.offsetModelVersion = tonumber(version) or CENTERED_OFFSET_MODEL_VERSION
  if SV and SV.FlushRuntimeToCanonical then
    SV:FlushRuntimeToCanonical()
  end
end

local function ConvertLegacyOffsetToCentered(elementName, x, y, ui, element)
  x = tonumber(x) or 0
  y = tonumber(y) or 0
  if not (ui and ui.content) then return x, y end

  local contentH = tonumber(ui.content:GetHeight()) or 0
  if contentH <= 0 then return x, y end

  local elementH = tonumber(element and element.GetHeight and element:GetHeight()) or 0
  local elementW = tonumber(element and element.GetWidth and element:GetWidth()) or 0

  if elementName == "pressedIndicator" then
    local iconHolder = ui.iconHolder
    local iconW = tonumber(iconHolder and iconHolder.GetWidth and iconHolder:GetWidth()) or 0
    local centerX = (iconW * 0.5) + x + (elementW * 0.5)
    local centerY = y
    return RoundNearest(centerX), RoundNearest(centerY)
  end

  local centerX = x
  local centerY = (contentH * 0.5) + y - (elementH * 0.5)
  return RoundNearest(centerX), RoundNearest(centerY)
end

function UI:EnsureCenteredElementOffsetModel()
  local ui = self.ui
  local db = ActiveDB()
  if type(db) ~= "table" then return false end
  if not NeedsBrokenCenteredOffsetRepair(db) then return false end
  if not (ui and ui.content and ui.elements) then return false end

  local contentH = tonumber(ui.content:GetHeight()) or 0
  if contentH <= 0 then return false end

  db.layout = db.layout or {}
  db.layout.elements = db.layout.elements or {}

  for elementName, legacyDefaults in pairs(LEGACY_ELEMENT_DEFAULTS) do
    local cfg = db.layout.elements[elementName]
    if type(cfg) ~= "table" then
      cfg = {}
      db.layout.elements[elementName] = cfg
    end

    local oldX = tonumber(cfg.x)
    if oldX == nil then oldX = tonumber(legacyDefaults.x) or 0 end
    local oldY = tonumber(cfg.y)
    if oldY == nil then oldY = tonumber(legacyDefaults.y) or 0 end

    local element = ui.elements[elementName]
    local newX, newY = ConvertLegacyOffsetToCentered(elementName, oldX, oldY, ui, element)
    cfg.x = newX
    cfg.y = newY
    if cfg.enabled == nil then
      local defaults = ELEMENT_DEFAULTS[elementName]
      cfg.enabled = defaults and defaults.enabled and true or false
    end
  end

  db.layout.centeredOffsetRepairApplied = true
  SetOffsetModelVersion(db, CENTERED_OFFSET_MODEL_VERSION)
  return true
end

local function GetRowRelativeAnchorModelVersion(db)
  if type(db) ~= "table" then return 0 end
  local layout = db.layout
  if type(layout) ~= "table" then return 0 end
  return tonumber(layout.rowRelativeAnchorModelVersion) or 0
end

local function SetRowRelativeAnchorModelVersion(db, version)
  if type(db) ~= "table" then return end
  db.layout = db.layout or {}
  db.layout.rowRelativeAnchorModelVersion = tonumber(version) or ROW_RELATIVE_ANCHOR_MODEL_VERSION
  if SV and SV.FlushRuntimeToCanonical then
    SV:FlushRuntimeToCanonical()
  end
end

local function NeedsRowRelativeAnchorMigration(db)
  if type(db) ~= "table" then return false end
  return GetRowRelativeAnchorModelVersion(db) < ROW_RELATIVE_ANCHOR_MODEL_VERSION
end

function UI:EnsureRowRelativeAnchorOffsetModel()
  local ui = self.ui
  local db = ActiveDB()
  if type(db) ~= "table" then return false end
  if not NeedsRowRelativeAnchorMigration(db) then return false end
  if not (ui and ui.content and ui.iconHolder and ui.elements) then return false end
  local rowRelativeVersion = GetRowRelativeAnchorModelVersion(db)
  local changed = false

  db.layout = db.layout or {}
  db.layout.elements = db.layout.elements or {}

  if rowRelativeVersion < 1 then
    for elementName, baseline in pairs(ROW_RELATIVE_BASELINES) do
      local cfg = db.layout.elements[elementName]
      if type(cfg) ~= "table" then
        cfg = {}
        db.layout.elements[elementName] = cfg
      end
      cfg.x = RoundNearest((tonumber(cfg.x) or 0) - (tonumber(baseline.x) or 0))
      cfg.y = RoundNearest((tonumber(cfg.y) or 0) - (tonumber(baseline.y) or 0))
      if cfg.enabled == nil then
        local defaults = ELEMENT_DEFAULTS[elementName]
        cfg.enabled = defaults and defaults.enabled and true or false
      end
    end

    do
      local elementName = "pressedIndicator"
      local cfg = db.layout.elements[elementName]
      if type(cfg) ~= "table" then
        cfg = {}
        db.layout.elements[elementName] = cfg
      end
      local element = ui.elements[elementName]
      local elementW = tonumber(element and element.GetWidth and element:GetWidth()) or 0
      local baselineX = (elementW * 0.5) + 8
      cfg.x = RoundNearest((tonumber(cfg.x) or 0) - baselineX)
      cfg.y = RoundNearest(tonumber(cfg.y) or 0)
      if cfg.enabled == nil then
        local defaults = ELEMENT_DEFAULTS[elementName]
        cfg.enabled = defaults and defaults.enabled and true or false
      end
    end
    changed = true
  end

  if rowRelativeVersion < 2 then
    for elementName in pairs(ROW_RELATIVE_BASELINES) do
      local cfg = db.layout.elements[elementName]
      if type(cfg) ~= "table" then
        cfg = {}
        db.layout.elements[elementName] = cfg
      end
      local x = RoundNearest(tonumber(cfg.x) or 0)
      local y = RoundNearest(tonumber(cfg.y) or 0)
      if math.abs(x) > TEXT_ROW_OFFSET_MAX_X or math.abs(y) > TEXT_ROW_OFFSET_MAX_Y then
        local defaults = ELEMENT_DEFAULTS[elementName]
        cfg.x = tonumber(defaults and defaults.x) or 0
        cfg.y = tonumber(defaults and defaults.y) or 0
        changed = true
      end
      if cfg.enabled == nil then
        local defaults = ELEMENT_DEFAULTS[elementName]
        cfg.enabled = defaults and defaults.enabled and true or false
      end
    end
  end

  if changed or rowRelativeVersion < ROW_RELATIVE_ANCHOR_MODEL_VERSION then
    SetRowRelativeAnchorModelVersion(db, ROW_RELATIVE_ANCHOR_MODEL_VERSION)
    return true
  end
  return false
end

function UI:EnsureLayoutDB(db)
  db = db or ActiveDB()
  if type(db) ~= "table" then return end
  db.layout = db.layout or {}
  db.layout.elements = db.layout.elements or {}
  for name, defaults in pairs(ELEMENT_DEFAULTS) do
    local cfg = db.layout.elements[name]
    if type(cfg) ~= "table" then
      cfg = {}
      db.layout.elements[name] = cfg
    end
    if cfg.enabled == nil then cfg.enabled = defaults.enabled and true or false end
    if type(cfg.x) ~= "number" then cfg.x = defaults.x or 0 end
    if type(cfg.y) ~= "number" then cfg.y = defaults.y or 0 end
  end
end

function UI:GetElementLayoutDefaults(elementName)
  return ELEMENT_DEFAULTS[elementName]
end

function UI:GetElementLayout(elementName)
  local defaults = ELEMENT_DEFAULTS[elementName]
  if not defaults then return nil end

  if addon.GetElementLayoutConfig then
    local cfg = addon:GetElementLayoutConfig(elementName)
    if cfg then
      return cfg, defaults
    end
  end

  self:EnsureLayoutDB(ActiveDB())
  local db = ActiveDB() and ActiveDB().layout and ActiveDB().layout.elements
  local cfg = db and db[elementName]
  if type(cfg) ~= "table" then return defaults end
  return cfg, defaults
end

function UI:GetElementAnchorTarget(elementName)
  local ui = self.ui
  if not ui then return nil end
  if ui.elementAnchors and ui.elementAnchors[elementName] then
    return ui.elementAnchors[elementName]
  end
  return ui.content or ui
end

function UI:ApplyElementPosition(elementName)
  if not _layoutMigrationsApplied then
    _layoutMigrationsApplied = true
    self:EnsureCenteredElementOffsetModel()
    self:EnsureRowRelativeAnchorOffsetModel()
  end
  local ui = self.ui
  if not (ui and ui.elements) then return end
  local element = ui.elements[elementName]
  if not element then return end

  local cfg, defaults = self:GetElementLayout(elementName)
  defaults = defaults or ELEMENT_DEFAULTS[elementName]
  if not defaults then return end

  if self.UpdateActionTrackerRowRelativeAnchors then
    self:UpdateActionTrackerRowRelativeAnchors()
  end
  local anchor = self:GetElementAnchorTarget(elementName) or ui.content or ui
  local point = defaults.point or "CENTER"
  local relativePoint = defaults.relativePoint or point
  local x = (cfg and cfg.x) or defaults.x or 0
  local y = (cfg and cfg.y) or defaults.y or 0
  -- Swap Name <-> ModKeys: each of the pair adopts the OTHER's anchor + offset, so they trade places.
  -- HORIZONTAL only: in VERTICAL the single name is hidden (per-icon names instead), the GSE name is
  -- top-centre and MODKEYS is fixed bottom-centre, and the swap just flips which SIDE the per-icon names
  -- sit (SetIconNameLabel) -- so swapping these anchors here would wrongly move MODKEYS above the column.
  local verticalSwapLayout = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) == "VERTICAL"
  if (elementName == "sequenceText" or elementName == "modifiersText")
    and not verticalSwapLayout
    and addon.GetActionTrackerSwapNameModkeys and addon:GetActionTrackerSwapNameModkeys() then
    local other = (elementName == "sequenceText") and "modifiersText" or "sequenceText"
    local ocfg, odef = self:GetElementLayout(other)
    odef = odef or ELEMENT_DEFAULTS[other]
    if odef then
      point = odef.point or point
      relativePoint = odef.relativePoint or relativePoint
      x = (ocfg and ocfg.x) or odef.x or 0
      y = (ocfg and ocfg.y) or odef.y or 0
    end
    -- Position = baseline anchor (set per element relative to the icon row) + offset, so also adopt
    -- the OTHER element's baseline anchor; otherwise the two wouldn't actually trade rows.
    anchor = self:GetElementAnchorTarget(other) or anchor
  end
  local visible = (cfg and cfg.enabled)
  if visible == nil then visible = defaults.enabled and true or false end

  -- While the pressed indicator is being dragged (unlocked), don't re-anchor it -- that
  -- would yank it out from under the cursor. The drag's OnDragStop stores the new offset.
  if elementName == "pressedIndicator" and element._gsetPiMoving then
    return
  end
  local function PS(v) return pixelSnap(v, ui) end
  local ox, oy = x, y
  if elementName == "pressedIndicator" then
    -- The pressed indicator carries the Overall (master) addon scale on itself. Its anchor offset
    -- is stored in UIParent units but SetPoint interprets the offset in the indicator's OWN scaled
    -- space, so divide by that scale: the saved screen position stays fixed and the indicator grows
    -- about its centre instead of drifting as the Overall scale changes.
    local sc = (element.GetScale and element:GetScale()) or 1
    if not sc or sc == 0 then sc = 1 end
    ox, oy = x / sc, y / sc
  end
  SetElementPointIfNeeded(element, point, anchor, relativePoint, PS(ox), PS(oy))
  -- The pressed indicator lives on UIParent (independent of the tracker frame) and
  -- its show/hide is owned entirely by RefreshPressedIndicator (input-gated). Don't
  -- let the layout pass force it visible just because the element is "enabled".
  if elementName == "pressedIndicator" then
    if self.RefreshPressedIndicator then self:RefreshPressedIndicator(true) end
    return
  end
  if element._gsetrackerVisible ~= visible then
    element._gsetrackerVisible = visible
    if visible then element:Show() else element:Hide() end
  end
end

function UI:ApplyAllElementPositions()
  if not (self.ui and self.ui.elements) then return end
  for name in pairs(self.ui.elements) do
    self:ApplyElementPosition(name)
  end
end

function UI:ResetElementPosition(elementName)
  local defaults = ELEMENT_DEFAULTS[elementName]
  if not defaults then return end

  if addon.ResetElementLayout then
    addon:ResetElementLayout(elementName)
  else
    self:EnsureLayoutDB(ActiveDB())
    local cfg = ActiveDB().layout.elements[elementName]
    cfg.x = defaults.x or 0
    cfg.y = defaults.y or 0
    cfg.enabled = defaults.enabled and true or false
  end

  self:ApplyElementPosition(elementName)
end

function UI:ResetAllElementPositions()
  self:EnsureLayoutDB(ActiveDB())
  for name in pairs(ELEMENT_DEFAULTS) do
    self:ResetElementPosition(name)
  end
end

function UI:SetElementEnabled(elementName, enabled)
  if addon.SetElementLayoutEnabled then
    if not addon:SetElementLayoutEnabled(elementName, enabled) then return end
  else
    self:EnsureLayoutDB(ActiveDB())
    local cfg = ActiveDB().layout.elements[elementName]
    if not cfg then return end
    cfg.enabled = not not enabled
  end
  self:ApplyElementPosition(elementName)
end

function UI:SetElementOffset(elementName, x, y)
  if addon.SetElementLayoutOffset then
    if not addon:SetElementLayoutOffset(elementName, x, y) then return end
  else
    self:EnsureLayoutDB(ActiveDB())
    local cfg = ActiveDB().layout.elements[elementName]
    if not cfg then return end
    if type(x) == "number" then cfg.x = x end
    if type(y) == "number" then cfg.y = y end
  end
  self:ApplyElementPosition(elementName)
end
