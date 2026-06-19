local _, ns = ...
local addon = ns
local API = (ns.Utils and ns.Utils.API) or {}
local UIParent = (API.UIParent and API.UIParent()) or UIParent
local Utils = ns.Utils
local SV = (ns.Utils and ns.Utils.SV) or nil
local uiShared = addon._ui or {}
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local ensureDatabase = uiShared.EnsureDB
local clampValue = uiShared.Clamp
local GetRuntimeDB
local PersistRuntimeChange
local POSITION_LIMIT = tonumber(C.ACTION_TRACKER_POSITION_LIMIT) or 3000

local _cachedRawRef, _cachedDB, _cachedGeneral, _cachedDisplay, _cachedFonts, _cachedFlags
local _persistPending = false

local function EnsureTable(parent, key)
  local value = parent[key]
  if type(value) ~= "table" then
    value = {}
    parent[key] = value
  end
  return value
end

local function TouchLegacyArgs(...)
  return select("#", ...)
end

local function GetRootDefaults()
  if SV and SV.GetRootDefaults then
    local defaults = SV:GetRootDefaults()
    if type(defaults) == "table" then
      return defaults
    end
  end
  if uiShared.GetRootDefaults then
    local defaults = uiShared.GetRootDefaults()
    if type(defaults) == "table" then
      return defaults
    end
  end
  return {}
end

local function GetDisplayDefaults()
  return EnsureTable(GetRootDefaults(), "display")
end

local function GetGeneralDefaults()
  return EnsureTable(GetRootDefaults(), "general")
end

local function GetFontDefaults(fontKey)
  local fonts = EnsureTable(GetRootDefaults(), "fonts")
  return EnsureTable(fonts, fontKey)
end

local function GetPressedIndicatorDefaults()
  local display = GetDisplayDefaults()
  return EnsureTable(display, "pressedIndicator")
end

local function GetActionTrackerBorderColorDefaults()
  local display = GetDisplayDefaults()
  local color = EnsureTable(display, "borderColor")
  if color.r == nil then color.r = 0.20 end
  if color.g == nil then color.g = 0.60 end
  if color.b == nil then color.b = 1.00 end
  return color
end

local function EnsureActionTrackerBorderColorTable()
  local _, _, display = GetRuntimeDB()
  local color = EnsureTable(display, "borderColor")
  local fallback = GetActionTrackerBorderColorDefaults()
  color.r = clampValue(tonumber(color.r) or tonumber(fallback.r) or 0.20, 0, 1)
  color.g = clampValue(tonumber(color.g) or tonumber(fallback.g) or 0.60, 0, 1)
  color.b = clampValue(tonumber(color.b) or tonumber(fallback.b) or 1.00, 0, 1)
  return color
end

local function GetCombatMarkerDefaults()
  return EnsureTable(GetRootDefaults(), "combatMarker")
end

local function GetMinimapDefaults()
  return EnsureTable(GetRootDefaults(), "minimap")
end

GetRuntimeDB = function()
  -- Key the cache on the ACTIVE store via a READ-ONLY lookup. Calling SV:GetDB()
  -- here (which self-assigns _G globals) on every call re-taints those globals;
  -- because this runs inside Settings dropdown generators (shared Menu system),
  -- that taint reaches the GameMenu and blocks Logout/action-bar grid. Read only.
  local rawRef = (SV and SV.GetActiveDBRaw and SV:GetActiveDBRaw()) or _G.GSETrackerDB
  if rawRef ~= nil and rawRef == _cachedRawRef then
    return _cachedDB, _cachedGeneral, _cachedDisplay, _cachedFonts, _cachedFlags
  end

  if ensureDatabase then ensureDatabase() end
  local db
  if SV and SV.EnsureDB then
    db = SV:EnsureDB()
  else
    if _G.GSETrackerDB == nil then _G.GSETrackerDB = {} end
    db = _G.GSETrackerDB
  end

  local general = EnsureTable(db, "general")
  local display = EnsureTable(db, "display")
  local fonts = EnsureTable(db, "fonts")
  local flags = EnsureTable(db, "flags")
  EnsureTable(display, "pressedIndicator")
  EnsureTable(fonts, "sequence")
  EnsureTable(fonts, "modifiers")
  EnsureTable(fonts, "keybind")
  EnsureTable(db, "colors")
  EnsureTable(db, "minimap")
  local layout = EnsureTable(db, "layout")
  EnsureTable(layout, "elements")
  EnsureTable(db, "combatMarker")
  EnsureTable(db, "assistedHighlight")

  _cachedRawRef = (SV and SV.GetActiveDBRaw and SV:GetActiveDBRaw()) or db
  _cachedDB = db
  _cachedGeneral = general
  _cachedDisplay = display
  _cachedFonts = fonts
  _cachedFlags = flags

  return db, general, display, fonts, flags
end

PersistRuntimeChange = function(db)
  if type(db) ~= "table" then return end
  if not (SV and SV.FlushRuntimeToCanonical) then return end
  if _persistPending then return end
  _persistPending = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      _persistPending = false
      if SV and SV.FlushRuntimeToCanonical then
        SV:FlushRuntimeToCanonical()
      end
    end)
  else
    _persistPending = false
    SV:FlushRuntimeToCanonical()
  end
end

local function CopyPoint(point)
  local fallbackPoint = GetDisplayDefaults().point
  if type(point) ~= "table" or #point < 5 then
    point = fallbackPoint
  end
  if type(point) ~= "table" or #point < 5 then
    point = (C.CopyDefaultActionTrackerPoint and C:CopyDefaultActionTrackerPoint()) or { "CENTER", "UIParent", "CENTER", 0, 0 }
  end
  return { point[1], point[2], point[3], tonumber(point[4]) or 0, tonumber(point[5]) or 0 }
end

local function RoundNearest(v)
  v = tonumber(v) or 0
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return math.ceil(v - 0.5)
end

local function ClampActionTrackerOffset(value)
  return clampValue(RoundNearest(value), -POSITION_LIMIT, POSITION_LIMIT)
end

local function EnsurePointTable()
  local _, _, display = GetRuntimeDB()
  local point = CopyPoint(display.point)

  local fallbackPoint = CopyPoint(GetDisplayDefaults().point)
  point[1] = type(point[1]) == "string" and point[1] ~= "" and point[1] or fallbackPoint[1]
  point[2] = type(point[2]) == "string" and point[2] ~= "" and point[2] or fallbackPoint[2]
  point[3] = type(point[3]) == "string" and point[3] ~= "" and point[3] or fallbackPoint[3]
  point[4] = ClampActionTrackerOffset(tonumber(point[4]) or fallbackPoint[4])
  point[5] = ClampActionTrackerOffset(tonumber(point[5]) or fallbackPoint[5])

  display.point = point
  return point
end

function Utils:IsEnabled()
  local _, general = GetRuntimeDB()
  return general.enabled ~= false
end

function Utils:SetEnabled(enabled)
  local db, general = GetRuntimeDB()
  general.enabled = enabled ~= false
  PersistRuntimeChange(db)
end

function Utils:IsLocked()
  local _, general = GetRuntimeDB()
  return general.locked and true or false
end

function Utils:SetLocked(locked)
  local db, general = GetRuntimeDB()
  general.locked = not not locked
  PersistRuntimeChange(db)
end

function Utils:IsBorderEnabled()
  return (Utils:GetBorderThickness() or 0) > 0
end

function Utils:SetBorderEnabled(enabled)
  local db, _, display = GetRuntimeDB()
  local currentThickness = clampValue(tonumber(display.borderThickness) or (tonumber(GetDisplayDefaults().borderThickness) or 0), 0, 5)
  display.borderThickness = enabled and math.max(currentThickness, 1) or 0
  display.border = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetActionTrackerUseClassColor()
  local _, _, display = GetRuntimeDB()
  return display.borderUseClassColor ~= false
end

function Utils:SetActionTrackerUseClassColor(enabled)
  local db, _, display = GetRuntimeDB()
  display.borderUseClassColor = not not enabled
  PersistRuntimeChange(db)
end

-- Name source for the tracker's title label: false (default) = the GSE sequence name
-- as before; true = the most recently cast spell's name (shown the same way).
function Utils:GetActionTrackerUseSpellName()
  local _, _, display = GetRuntimeDB()
  return display.useSpellName == true
end

function Utils:SetActionTrackerUseSpellName(enabled)
  local db, _, display = GetRuntimeDB()
  display.useSpellName = not not enabled
  PersistRuntimeChange(db)
end

-- Whether the modifier readout shows the side prefix (L/R) before each key. Default
-- true (e.g. "LShift+RCtrl"); false collapses to "Shift+Ctrl".
function Utils:GetActionTrackerModkeySide()
  local _, _, display = GetRuntimeDB()
  return display.modkeySide ~= false
end

function Utils:SetActionTrackerModkeySide(enabled)
  local db, _, display = GetRuntimeDB()
  display.modkeySide = not not enabled
  PersistRuntimeChange(db)
end

-- Corner/centre that the per-recent-icon keybind label anchors to (matches the
-- Assisted Highlight keybind Location). Default TOPRIGHT (Blizzard HotKey style).
local VALID_ACTIONBAR_KEYBIND_ANCHORS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true, CENTER = true }

function Utils:GetActionTrackerKeybindAnchor()
  local _, _, display = GetRuntimeDB()
  local v = tostring(display.keybindAnchor or "TOPRIGHT")
  if not VALID_ACTIONBAR_KEYBIND_ANCHORS[v] then v = "TOPRIGHT" end
  return v
end

function Utils:SetActionTrackerKeybindAnchor(value)
  local db, _, display = GetRuntimeDB()
  local v = tostring(value or "TOPRIGHT")
  if not VALID_ACTIONBAR_KEYBIND_ANCHORS[v] then v = "TOPRIGHT" end
  display.keybindAnchor = v
  PersistRuntimeChange(db)
end

function Utils:GetActionTrackerBorderColor()
  local color = EnsureActionTrackerBorderColorTable()
  return color.r, color.g, color.b
end

function Utils:SetActionTrackerBorderColor(r, g, b)
  local db, _, display = GetRuntimeDB()
  local color = EnsureTable(display, "borderColor")
  local fallback = GetActionTrackerBorderColorDefaults()
  color.r = clampValue(tonumber(r) or tonumber(fallback.r) or 0.20, 0, 1)
  color.g = clampValue(tonumber(g) or tonumber(fallback.g) or 0.60, 0, 1)
  color.b = clampValue(tonumber(b) or tonumber(fallback.b) or 1.00, 0, 1)
  PersistRuntimeChange(db)
end

function Utils:GetBorderThickness()
  local _, _, display = GetRuntimeDB()
  return clampValue(tonumber(display.borderThickness) or (tonumber(GetDisplayDefaults().borderThickness) or 0), 0, 5)
end

function Utils:SetBorderThickness(value)
  local db, _, display = GetRuntimeDB()
  local thickness = clampValue(tonumber(value) or (tonumber(GetDisplayDefaults().borderThickness) or 0), 0, 5)
  display.borderThickness = thickness
  display.border = thickness > 0
  PersistRuntimeChange(db)
end

function Utils:GetActionTrackerPoint()
  local point = EnsurePointTable()
  return point[1], point[2], point[3], point[4], point[5]
end

function Utils:GetActionTrackerAnchor()
  local point, relName, relPoint, x, y = self:GetActionTrackerPoint()
  return point, (_G[relName] or UIParent), relPoint, x, y
end

function Utils:SetActionTrackerPoint(point, relName, relPoint, x, y)
  local db, _, display = GetRuntimeDB()
  local p = EnsurePointTable()
  local fallbackPoint = CopyPoint(GetDisplayDefaults().point)
  p[1] = type(point) == "string" and point or fallbackPoint[1]
  p[2] = type(relName) == "string" and relName or fallbackPoint[2]
  p[3] = type(relPoint) == "string" and relPoint or fallbackPoint[3]
  p[4] = ClampActionTrackerOffset(x)
  p[5] = ClampActionTrackerOffset(y)
  display.point = p
  PersistRuntimeChange(db)
end

function Utils:GetMinimapAngle()
  local db = GetRuntimeDB()
  local minimap = EnsureTable(db, "minimap")
  local defaultAngle = tonumber(GetMinimapDefaults().angle) or 225
  local value = tonumber(minimap.angle)
  if value == nil then
    value = defaultAngle
  end
  return value % 360
end

function Utils:SetMinimapAngle(value)
  local db = GetRuntimeDB()
  local minimap = EnsureTable(db, "minimap")
  local defaultAngle = tonumber(GetMinimapDefaults().angle) or 225
  local angle = tonumber(value)
  if angle == nil then
    angle = defaultAngle
  end
  minimap.angle = angle % 360
  PersistRuntimeChange(db)
end

function Utils:GetMinimapHidden()
  local db = GetRuntimeDB()
  local minimap = EnsureTable(db, "minimap")
  return minimap.hidden == true
end

function Utils:SetMinimapHidden(value)
  local db = GetRuntimeDB()
  local minimap = EnsureTable(db, "minimap")
  minimap.hidden = value == true or nil
  PersistRuntimeChange(db)
end

function Utils:GetHideLoginMessage()
  local _, general = GetRuntimeDB()
  return general.hideLoginMessage and true or false
end

function Utils:SetHideLoginMessage(value)
  local db, general = GetRuntimeDB()
  general.hideLoginMessage = not not value
  PersistRuntimeChange(db)
end


local NormalizeAssistedHighlightPointName
local NormalizeAssistedHighlightAnchorTarget
local GetAssistedHighlightColorDefaults
local EnsureAssistedHighlightColorTable
local GetAssistedHighlightAnchorPointModel

local function GetAssistedHighlightDefaults()
  return EnsureTable(GetRootDefaults(), "assistedHighlight")
end

local function GetAssistedHighlightPointDefaults()
  local defaults = GetAssistedHighlightDefaults()
  local point = defaults.point
  if type(point) ~= "table" or #point < 5 then
    point = { C.ANCHOR_CENTER or "CENTER", C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", 0, -140 }
  end
  return {
    NormalizeAssistedHighlightPointName(point[1], C.ANCHOR_CENTER or "CENTER"),
    type(point[2]) == "string" and point[2] ~= "" and point[2] or (C.UI_PARENT_NAME or "UIParent"),
    NormalizeAssistedHighlightPointName(point[3], C.ANCHOR_CENTER or "CENTER"),
    ClampActionTrackerOffset(tonumber(point[4]) or 0),
    ClampActionTrackerOffset(tonumber(point[5]) or -140),
  }
end

local function EnsureAssistedHighlightPointTable()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local point = assisted.point
  local fallback = GetAssistedHighlightPointDefaults()
  if type(point) ~= "table" or #point < 5 then
    point = { fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] }
  end

  assisted.anchorTarget = NormalizeAssistedHighlightAnchorTarget(assisted.anchorTarget)
  local effectivePoint, effectiveRelName, effectiveRelPoint = GetAssistedHighlightAnchorPointModel(assisted.anchorTarget)
  point[1] = effectivePoint
  point[2] = effectiveRelName
  point[3] = effectiveRelPoint
  point[4] = ClampActionTrackerOffset(tonumber(point[4]) or fallback[4])
  point[5] = ClampActionTrackerOffset(tonumber(point[5]) or fallback[5])

  assisted.point = point
  return point
end

local VALID_ASSISTED_HIGHLIGHT_POINTS = {
  CENTER = true,
  LEFT = true,
  RIGHT = true,
  ["TOPRIGHT"] = true,
  ["TOP"] = true,
  ["TOPLEFT"] = true,
  ["BOTTOM"] = true,
  ["BOTTOMRIGHT"] = true,
  ["BOTTOMLEFT"] = true,
}

local VALID_ASSISTED_HIGHLIGHT_ANCHORS = {
  Screen = true,
  ["Mouse Cursor"] = true,
  ["Target Nameplate"] = true,
}

NormalizeAssistedHighlightPointName = function(value, fallback)
  value = tostring(value or fallback or C.ANCHOR_CENTER or "CENTER")
  local compact = value:gsub("%s+", ""):upper()
  if compact == "TOPCENTER" then compact = "TOP" end
  if compact == "BOTTOMCENTER" then compact = "BOTTOM" end
  if VALID_ASSISTED_HIGHLIGHT_POINTS[compact] then
    return compact
  end
  return fallback or (C.ANCHOR_CENTER or "CENTER")
end

NormalizeAssistedHighlightAnchorTarget = function(value)
  value = tostring(value or "Screen")
  if VALID_ASSISTED_HIGHLIGHT_ANCHORS[value] then
    return value
  end
  return "Screen"
end

GetAssistedHighlightAnchorPointModel = function(value)
  -- Screen always resolves through CENTER; non-screen anchor modes resolve their
  -- effective frame/icon points here rather than inheriting stale user-selected data.
  local target = NormalizeAssistedHighlightAnchorTarget(value)
  if target == "Mouse Cursor" then
    return C.ANCHOR_CENTER or "CENTER", "Mouse Cursor", C.ANCHOR_CENTER or "CENTER"
  elseif target == "Target Nameplate" then
    return C.ANCHOR_CENTER or "CENTER", "Target Nameplate", C.ANCHOR_CENTER or "CENTER"
  end
  return C.ANCHOR_CENTER or "CENTER", C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER"
end

GetAssistedHighlightColorDefaults = function()
  local defaults = GetAssistedHighlightDefaults()
  return EnsureTable(defaults, "color")
end

EnsureAssistedHighlightColorTable = function()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local color = EnsureTable(assisted, "color")
  local fallback = GetAssistedHighlightColorDefaults()
  color.r = clampValue(tonumber(color.r) or tonumber(fallback.r) or 0.20, 0, 1)
  color.g = clampValue(tonumber(color.g) or tonumber(fallback.g) or 0.60, 0, 1)
  color.b = clampValue(tonumber(color.b) or tonumber(fallback.b) or 1.00, 0, 1)
  return color
end

local function GetCombatMarkerColorDefaults()
  local combatDefaults = GetCombatMarkerDefaults()
  return EnsureTable(combatDefaults, "color")
end

local function EnsureCombatMarkerColorTable()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local color = EnsureTable(combatMarker, "color")
  local fallback = GetCombatMarkerColorDefaults()
  color.r = clampValue(tonumber(color.r) or tonumber(fallback.r) or 1, 0, 1)
  color.g = clampValue(tonumber(color.g) or tonumber(fallback.g) or 1, 0, 1)
  color.b = clampValue(tonumber(color.b) or tonumber(fallback.b) or 1, 0, 1)
  return color
end

function Utils:IsCombatMarkerEnabled()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return combatMarker.enabled and true or false
end

function Utils:SetCombatMarkerEnabled(enabled)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.enabled = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerPreviewEnabled()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return combatMarker.preview and true or false
end

function Utils:SetCombatMarkerPreviewEnabled(enabled)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.preview = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerSymbol()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return tostring(combatMarker.symbol or (GetCombatMarkerDefaults().symbol or (C.COMBAT_MARKER_DEFAULT_SYMBOL or "x")))
end

function Utils:SetCombatMarkerSymbol(value)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local symbol = tostring(value or (GetCombatMarkerDefaults().symbol or (C.COMBAT_MARKER_DEFAULT_SYMBOL or "x")))
  local isImage = C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[symbol]
  -- Dynamic (Bullseye/Class/Specialization), "None" (off) and "AHLight" (AH mirrors its
  -- icon at centre) are also valid now that ALL Center Marker options route through this
  -- single combat-marker symbol.
  local isDynamic = C.COMBAT_MARKER_DYNAMIC_VALID and C.COMBAT_MARKER_DYNAMIC_VALID[symbol]
  if not isImage and not isDynamic and symbol ~= "None" and symbol ~= "AHLight"
    and symbol ~= "plus" and symbol ~= "diamond" and symbol ~= "x" and symbol ~= "square" and symbol ~= "circle" then
    if symbol == "cross" then symbol = "plus" else symbol = (C.COMBAT_MARKER_DEFAULT_SYMBOL or "x") end
  end
  combatMarker.symbol = symbol
  PersistRuntimeChange(db)
end

-- "Press Detection": when on, the Center Marker monitors input and blinks like the Pressed
-- Indicator (always shown, pulses on each key/GSE press). Off by default; independent of the
-- standalone Pressed Indicator and of the chosen marker symbol.
function Utils:GetCombatMarkerPressDetection()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return combatMarker.pressDetection and true or false
end

function Utils:SetCombatMarkerPressDetection(enabled)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.pressDetection = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerSize()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return clampValue(tonumber(combatMarker.size) or (tonumber(GetCombatMarkerDefaults().size) or (C.COMBAT_MARKER_DEFAULT_SIZE or 40)), C.COMBAT_MARKER_MIN_SIZE or 16, C.COMBAT_MARKER_MAX_SIZE or 128)
end

function Utils:SetCombatMarkerSize(value)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.size = clampValue(tonumber(value) or (tonumber(GetCombatMarkerDefaults().size) or (C.COMBAT_MARKER_DEFAULT_SIZE or 40)), C.COMBAT_MARKER_MIN_SIZE or 16, C.COMBAT_MARKER_MAX_SIZE or 128)
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerAlpha()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return clampValue(tonumber(combatMarker.alpha) or (tonumber(GetCombatMarkerDefaults().alpha) or (C.COMBAT_MARKER_DEFAULT_ALPHA or 0.85)), 0.05, 1.00)
end

function Utils:SetCombatMarkerAlpha(value)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.alpha = clampValue(tonumber(value) or (tonumber(GetCombatMarkerDefaults().alpha) or (C.COMBAT_MARKER_DEFAULT_ALPHA or 0.85)), 0.05, 1.00)
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerUseClassColor()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return combatMarker.useClassColor ~= false
end

function Utils:SetCombatMarkerUseClassColor(enabled)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.useClassColor = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerColor()
  local color = EnsureCombatMarkerColorTable()
  return color.r, color.g, color.b
end

function Utils:SetCombatMarkerColor(r, g, b)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local color = EnsureTable(combatMarker, "color")
  local fallback = GetCombatMarkerColorDefaults()
  color.r = clampValue(tonumber(r) or tonumber(fallback.r) or 1, 0, 1)
  color.g = clampValue(tonumber(g) or tonumber(fallback.g) or 1, 0, 1)
  color.b = clampValue(tonumber(b) or tonumber(fallback.b) or 1, 0, 1)
  PersistRuntimeChange(db)
end

-- Combat marker colour mode, mirroring the Pressed Indicator: "none" (no tint -- image
-- shows its own colours), "class", or "custom". On first read it migrates from the legacy
-- useClassColor boolean so existing markers keep their look (class unless custom was set).
function Utils:GetCombatMarkerColorMode()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  if combatMarker.colorMode == nil then
    combatMarker.colorMode = (combatMarker.useClassColor == false) and "custom" or "class"
  end
  local m = tostring(combatMarker.colorMode)
  if m ~= "class" and m ~= "custom" then m = "none" end
  return m
end

function Utils:SetCombatMarkerColorMode(mode)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  if mode ~= "class" and mode ~= "custom" then mode = "none" end
  combatMarker.colorMode = mode
  -- Keep the legacy boolean roughly in sync for any old code path that still reads it.
  combatMarker.useClassColor = (mode == "class")
  PersistRuntimeChange(db)
end

local VALID_COMBAT_MARKER_ANCHORS = C.COMBAT_MARKER_VALID_ANCHORS or {
  CENTER = true,
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
}

local function IsLegacyCombatMarkerDefaultPoint(point)
  return type(point) == "table"
    and tostring(point[1] or "") == "TOP"
    and tostring(point[2] or "") == (C.UI_PARENT_NAME or "UIParent")
    and tostring(point[3] or "") == (C.ANCHOR_CENTER or "CENTER")
    and (tonumber(point[4]) or 0) == 0
    and (tonumber(point[5]) or 120) == 120
end

local function GetCombatMarkerPointDefaults()
  local combatDefaults = GetCombatMarkerDefaults()
  local point = combatDefaults.point
  if type(point) ~= "table" or #point < 5 then
    point = C.COMBAT_MARKER_DEFAULT_POINT or { "CENTER", "UIParent", "CENTER", 0, 120 }
  end
  local fallbackPoint = VALID_COMBAT_MARKER_ANCHORS[point[1]] and point[1] or ((C.COMBAT_MARKER_DEFAULT_POINT and C.COMBAT_MARKER_DEFAULT_POINT[1]) or "CENTER")
  return {
    fallbackPoint,
    C.UI_PARENT_NAME or "UIParent",
    C.ANCHOR_CENTER or "CENTER",
    ClampActionTrackerOffset(tonumber(point[4]) or 0),
    ClampActionTrackerOffset(tonumber(point[5]) or ((C.COMBAT_MARKER_DEFAULT_POINT and C.COMBAT_MARKER_DEFAULT_POINT[5]) or 120)),
  }
end

local function EnsureCombatMarkerPointTable()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local point = combatMarker.point
  local fallback = GetCombatMarkerPointDefaults()
  if type(point) ~= "table" or #point < 5 then
    point = { fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] }
  elseif IsLegacyCombatMarkerDefaultPoint(point) then
    point = { fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] }
  end
  -- Always anchor the marker by its CENTRE so the Size slider scales it symmetrically.
  -- A legacy "TOP" anchor (the old default) kept the top edge fixed and made the
  -- marker grow downward only when resized. relativePoint is CENTER, so the stored
  -- offset now positions the marker's centre.
  point[1] = C.ANCHOR_CENTER or "CENTER"
  point[2] = C.UI_PARENT_NAME or "UIParent"
  point[3] = C.ANCHOR_CENTER or "CENTER"
  point[4] = ClampActionTrackerOffset(tonumber(point[4]) or fallback[4])
  point[5] = ClampActionTrackerOffset(tonumber(point[5]) or fallback[5])
  combatMarker.point = point
  return point
end

function Utils:GetCombatMarkerPoint()
  local point = EnsureCombatMarkerPointTable()
  return point[1], point[2], point[3], point[4], point[5]
end

function Utils:GetCombatMarkerAnchorPoint()
  local point = EnsureCombatMarkerPointTable()
  return point[1]
end

function Utils:SetCombatMarkerAnchorPoint(anchorPoint)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local point = EnsureCombatMarkerPointTable()
  point[1] = VALID_COMBAT_MARKER_ANCHORS[tostring(anchorPoint)] and tostring(anchorPoint) or point[1]
  point[2] = C.UI_PARENT_NAME or "UIParent"
  point[3] = C.ANCHOR_CENTER or "CENTER"
  combatMarker.point = point
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerOffset()
  local _, _, _, x, y = self:GetCombatMarkerPoint()
  return x, y
end

function Utils:SetCombatMarkerPoint(point, relName, relPoint, x, y)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  TouchLegacyArgs(relName, relPoint)
  local p = EnsureCombatMarkerPointTable()
  p[1] = VALID_COMBAT_MARKER_ANCHORS[tostring(point)] and tostring(point) or p[1]
  p[2] = C.UI_PARENT_NAME or "UIParent"
  p[3] = C.ANCHOR_CENTER or "CENTER"
  p[4] = ClampActionTrackerOffset(x)
  p[5] = ClampActionTrackerOffset(y)
  combatMarker.point = p
  PersistRuntimeChange(db)
end

function Utils:SetCombatMarkerOffset(x, y)
  local point, relName, relPoint = self:GetCombatMarkerPoint()
  self:SetCombatMarkerPoint(point, relName, relPoint, x, y)
end

function Utils:GetCombatMarkerLocked()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return combatMarker.locked and true or false
end

function Utils:SetCombatMarkerLocked(enabled)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.locked = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerShowWhen()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local default = C.COMBAT_MARKER_DEFAULT_SHOW_WHEN or (C.MODE_IN_COMBAT or "InCombat")
  local value = tostring(combatMarker.showWhen or (GetCombatMarkerDefaults().showWhen or default))
  if value ~= (C.MODE_ALWAYS or "Always") and value ~= (C.MODE_IN_COMBAT or "InCombat") and value ~= (C.MODE_HAS_TARGET or "HasTarget") and value ~= (C.MODE_NEVER or "Never") then
    value = default
  end
  return value
end

function Utils:SetCombatMarkerShowWhen(value)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  local default = C.COMBAT_MARKER_DEFAULT_SHOW_WHEN or (C.MODE_IN_COMBAT or "InCombat")
  local normalized = tostring(value or default)
  if normalized ~= (C.MODE_ALWAYS or "Always") and normalized ~= (C.MODE_IN_COMBAT or "InCombat") and normalized ~= (C.MODE_HAS_TARGET or "HasTarget") and normalized ~= (C.MODE_NEVER or "Never") then
    normalized = default
  end
  combatMarker.showWhen = normalized
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerThickness()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return clampValue(tonumber(combatMarker.thickness) or (tonumber(GetCombatMarkerDefaults().thickness) or (C.COMBAT_MARKER_DEFAULT_THICKNESS or 4)), C.COMBAT_MARKER_MIN_THICKNESS or 1, C.COMBAT_MARKER_MAX_THICKNESS or 12)
end

function Utils:SetCombatMarkerThickness(value)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.thickness = clampValue(tonumber(value) or (tonumber(GetCombatMarkerDefaults().thickness) or (C.COMBAT_MARKER_DEFAULT_THICKNESS or 4)), C.COMBAT_MARKER_MIN_THICKNESS or 1, C.COMBAT_MARKER_MAX_THICKNESS or 12)
  PersistRuntimeChange(db)
end

function Utils:GetCombatMarkerBorderSize()
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  return clampValue(tonumber(combatMarker.borderSize) or (tonumber(GetCombatMarkerDefaults().borderSize) or (C.COMBAT_MARKER_DEFAULT_BORDER_SIZE or 2)), C.COMBAT_MARKER_MIN_BORDER_SIZE or 0, C.COMBAT_MARKER_MAX_BORDER_SIZE or 8)
end

function Utils:SetCombatMarkerBorderSize(value)
  local db = GetRuntimeDB()
  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.borderSize = clampValue(tonumber(value) or (tonumber(GetCombatMarkerDefaults().borderSize) or (C.COMBAT_MARKER_DEFAULT_BORDER_SIZE or 2)), C.COMBAT_MARKER_MIN_BORDER_SIZE or 0, C.COMBAT_MARKER_MAX_BORDER_SIZE or 8)
  PersistRuntimeChange(db)
end

function Utils:IsCenterMarkerEnabled()
  return self:IsCombatMarkerEnabled()
end

function Utils:SetCenterMarkerEnabled(enabled)
  self:SetCombatMarkerEnabled(enabled)
end

function Utils:GetCenterMarkerPreviewEnabled()
  return self:GetCombatMarkerPreviewEnabled()
end

function Utils:SetCenterMarkerPreviewEnabled(enabled)
  self:SetCombatMarkerPreviewEnabled(enabled)
end

function Utils:GetCenterMarkerSymbol()
  return self:GetCombatMarkerSymbol()
end

function Utils:SetCenterMarkerSymbol(value)
  self:SetCombatMarkerSymbol(value)
end

function Utils:GetCenterMarkerSize()
  return self:GetCombatMarkerSize()
end

function Utils:SetCenterMarkerSize(value)
  self:SetCombatMarkerSize(value)
end

function Utils:GetCenterMarkerAlpha()
  return self:GetCombatMarkerAlpha()
end

function Utils:SetCenterMarkerAlpha(value)
  self:SetCombatMarkerAlpha(value)
end

function Utils:GetCenterMarkerUseClassColor()
  return self:GetCombatMarkerUseClassColor()
end

function Utils:SetCenterMarkerUseClassColor(enabled)
  self:SetCombatMarkerUseClassColor(enabled)
end

function Utils:GetCenterMarkerColor()
  return self:GetCombatMarkerColor()
end

function Utils:SetCenterMarkerColor(r, g, b)
  self:SetCombatMarkerColor(r, g, b)
end

function Utils:GetCenterMarkerPoint()
  return self:GetCombatMarkerPoint()
end

function Utils:SetCenterMarkerPoint(point, relName, relPoint, x, y)
  self:SetCombatMarkerPoint(point, relName, relPoint, x, y)
end

function Utils:GetCenterMarkerAnchorPoint()
  return self:GetCombatMarkerAnchorPoint()
end

function Utils:SetCenterMarkerAnchorPoint(anchorPoint)
  self:SetCombatMarkerAnchorPoint(anchorPoint)
end

function Utils:GetCenterMarkerOffset()
  return self:GetCombatMarkerOffset()
end

function Utils:SetCenterMarkerOffset(x, y)
  self:SetCombatMarkerOffset(x, y)
end

function Utils:GetCenterMarkerLocked()
  return self:GetCombatMarkerLocked()
end

function Utils:SetCenterMarkerLocked(enabled)
  self:SetCombatMarkerLocked(enabled)
end

function Utils:GetCenterMarkerShowWhen()
  return self:GetCombatMarkerShowWhen()
end

function Utils:SetCenterMarkerShowWhen(value)
  self:SetCombatMarkerShowWhen(value)
end

function Utils:GetCenterMarkerThickness()
  return self:GetCombatMarkerThickness()
end

function Utils:SetCenterMarkerThickness(value)
  self:SetCombatMarkerThickness(value)
end

function Utils:GetCenterMarkerBorderSize()
  return self:GetCombatMarkerBorderSize()
end

function Utils:SetCenterMarkerBorderSize(value)
  self:SetCombatMarkerBorderSize(value)
end

function Utils:GetShowWhen()
  local _, general = GetRuntimeDB()
  return tostring(general.showWhen or GetGeneralDefaults().showWhen or (C.MODE_ALWAYS or "Always"))
end

function Utils:SetShowWhen(value)
  local db, general = GetRuntimeDB()
  general.showWhen = tostring(value or GetGeneralDefaults().showWhen or (C.MODE_ALWAYS or "Always"))
  PersistRuntimeChange(db)
end

local VALID_SKIN = { AUTO = true, MODERN = true, NATIVE = true }

function Utils:GetSkin()
  local db = GetRuntimeDB()
  local appearance = EnsureTable(db, "appearance")
  local value = tostring(appearance.skin or "AUTO")
  if not VALID_SKIN[value] then value = "AUTO" end
  return value
end

function Utils:SetSkin(value)
  local db = GetRuntimeDB()
  local appearance = EnsureTable(db, "appearance")
  local normalized = tostring(value or "AUTO")
  if not VALID_SKIN[normalized] then normalized = "AUTO" end
  appearance.skin = normalized
  PersistRuntimeChange(db)
end


function Utils:GetScale()
  local _, _, display = GetRuntimeDB()
  return clampValue(tonumber(display.scale) or (tonumber(GetDisplayDefaults().scale) or 1), 0.70, 1.80)
end

function Utils:SetScaleValue(value)
  local db, _, display = GetRuntimeDB()
  display.scale = clampValue(tonumber(value) or (tonumber(GetDisplayDefaults().scale) or 1), 0.70, 1.80)
  PersistRuntimeChange(db)
end


function Utils:GetElementLayoutConfig(elementName)
  local db = GetRuntimeDB()
  local layout = EnsureTable(db, "layout")
  local elements = EnsureTable(layout, "elements")
  local defaults = (uiShared.ELEMENT_DEFAULTS and uiShared.ELEMENT_DEFAULTS[elementName]) or nil
  if not defaults then return nil end

  local cfg = elements[elementName]
  if type(cfg) ~= "table" then
    cfg = {}
    elements[elementName] = cfg
  end

  if cfg.enabled == nil then cfg.enabled = defaults.enabled and true or false end
  if type(cfg.x) ~= "number" then cfg.x = tonumber(defaults.x) or 0 end
  if type(cfg.y) ~= "number" then cfg.y = tonumber(defaults.y) or 0 end

  return cfg, defaults
end

function Utils:SetElementLayoutEnabled(elementName, enabled)
  local db = GetRuntimeDB()
  local cfg = self:GetElementLayoutConfig(elementName)
  if not cfg then return false end
  cfg.enabled = not not enabled
  PersistRuntimeChange(db)
  return true
end

function Utils:SetElementLayoutOffset(elementName, x, y)
  local db = GetRuntimeDB()
  local cfg = self:GetElementLayoutConfig(elementName)
  if not cfg then return false end
  if type(x) == "number" then cfg.x = x end
  if type(y) == "number" then cfg.y = y end
  PersistRuntimeChange(db)
  return true
end

function Utils:ResetElementLayout(elementName)
  local db = GetRuntimeDB()
  local cfg, defaults = self:GetElementLayoutConfig(elementName)
  if not (cfg and defaults) then return false end
  cfg.x = tonumber(defaults.x) or 0
  cfg.y = tonumber(defaults.y) or 0
  cfg.enabled = defaults.enabled and true or false
  PersistRuntimeChange(db)
  return true
end

function Utils:GetIconCount()
  local _, _, display = GetRuntimeDB()
  return clampValue(tonumber(display.iconCount) or (tonumber(GetDisplayDefaults().iconCount) or 4), C.MIN_ICON_COUNT or 4, C.MAX_ICON_COUNT or 8)
end

function Utils:SetIconCount(value)
  local db, _, display = GetRuntimeDB()
  display.iconCount = clampValue(tonumber(value) or (tonumber(GetDisplayDefaults().iconCount) or 4), C.MIN_ICON_COUNT or 4, C.MAX_ICON_COUNT or 8)
  PersistRuntimeChange(db)
end

function Utils:GetIconGap()
  local _, _, display = GetRuntimeDB()
  return clampValue(tonumber(display.iconGap) or (tonumber(GetDisplayDefaults().iconGap) or 3), 0, 5)
end

function Utils:SetIconGap(value)
  local db, _, display = GetRuntimeDB()
  display.iconGap = clampValue(tonumber(value) or (tonumber(GetDisplayDefaults().iconGap) or 3), 0, 5)
  PersistRuntimeChange(db)
end

-- Legacy pressed-indicator shapes mapped onto the shared marker symbol set so old
-- saved values keep working after the indicator adopted the marker symbols.
local PRESSED_SHAPE_LEGACY = {
  dot = "circle",
  cross = "plus",
  eye = "GSE_Tracker_Round.png",
}

function Utils:GetPressedIndicatorShape()
  local _, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  local shape = tostring(pressed.shape or (tostring(GetPressedIndicatorDefaults().shape or "circle")))
  return PRESSED_SHAPE_LEGACY[shape] or shape
end

function Utils:SetPressedIndicatorShape(value)
  local db, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  pressed.shape = tostring(value or (tostring(GetPressedIndicatorDefaults().shape or "dot")))
  PersistRuntimeChange(db)
end

function Utils:GetPressedIndicatorSize()
  local _, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  return clampValue(tonumber(pressed.size) or (tonumber(GetPressedIndicatorDefaults().size) or 10), C.PRESSED_INDICATOR_MIN_SIZE or 4, C.PRESSED_INDICATOR_MAX_SIZE or 24)
end

function Utils:SetPressedIndicatorSize(value)
  local db, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  pressed.size = clampValue(tonumber(value) or (tonumber(GetPressedIndicatorDefaults().size) or 10), C.PRESSED_INDICATOR_MIN_SIZE or 4, C.PRESSED_INDICATOR_MAX_SIZE or 24)
  PersistRuntimeChange(db)
end

-- Pressed Indicator colour mode: "none" (DEFAULT -- the image shows in its own colours,
-- no tint), "class" (tinted with the player's class colour), or "custom" (tinted with the
-- stored RGB). "none" is what shows when neither Class nor Custom is selected.
function Utils:GetPressedIndicatorColorMode()
  local _, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  local m = tostring(pressed.colorMode or "none")
  if m ~= "class" and m ~= "custom" then m = "none" end
  return m
end

function Utils:SetPressedIndicatorColorMode(mode)
  local db, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  if mode ~= "class" and mode ~= "custom" then mode = "none" end
  pressed.colorMode = mode
  PersistRuntimeChange(db)
end

function Utils:GetPressedIndicatorCustomColor()
  local _, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  local c = EnsureTable(pressed, "color")
  return tonumber(c.r) or 1, tonumber(c.g) or 0.82, tonumber(c.b) or 0
end

function Utils:SetPressedIndicatorCustomColor(r, g, b)
  local db, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  local c = EnsureTable(pressed, "color")
  c.r, c.g, c.b = tonumber(r) or 1, tonumber(g) or 0.82, tonumber(b) or 0
  PersistRuntimeChange(db)
end

-- Pressed Indicator lock: locked (default) shows only on key press at its saved spot;
-- unlocked makes it draggable + always visible so it can be repositioned. The saved
-- position (element offset) is untouched, so unlocking keeps it at its current location.
function Utils:GetPressedIndicatorUnlocked()
  local _, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  return pressed.unlocked and true or false
end

function Utils:SetPressedIndicatorUnlocked(enabled)
  local db, _, display = GetRuntimeDB()
  local pressed = EnsureTable(display, "pressedIndicator")
  pressed.unlocked = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetSeqFontName()
  local _, _, _, fonts = GetRuntimeDB()
  local seq = EnsureTable(fonts, "sequence")
  local fallback = addon.DEFAULT_SEQ_FONT or GetFontDefaults("sequence").face or C.FONT_FRIZ or "Friz Quadrata TT"
  local value = seq.face or fallback
  return addon.NormalizeFontName and addon:NormalizeFontName(value, fallback) or value
end

function Utils:SetSeqFontName(value)
  local db, _, _, fonts = GetRuntimeDB()
  local seq = EnsureTable(fonts, "sequence")
  seq.face = value or (addon.DEFAULT_SEQ_FONT or GetFontDefaults("sequence").face or C.FONT_FRIZ or "Friz Quadrata TT")
  PersistRuntimeChange(db)
end

function Utils:GetModFontName()
  local _, _, _, fonts = GetRuntimeDB()
  local mods = EnsureTable(fonts, "modifiers")
  local fallback = addon.DEFAULT_MOD_FONT or GetFontDefaults("modifiers").face or C.FONT_FRIZ or "Friz Quadrata TT"
  local value = mods.face or fallback
  return addon.NormalizeFontName and addon:NormalizeFontName(value, fallback) or value
end

function Utils:SetModFontName(value)
  local db, _, _, fonts = GetRuntimeDB()
  local mods = EnsureTable(fonts, "modifiers")
  mods.face = value or (addon.DEFAULT_MOD_FONT or GetFontDefaults("modifiers").face or C.FONT_FRIZ or "Friz Quadrata TT")
  PersistRuntimeChange(db)
end

function Utils:GetKeybindFontName()
  local _, _, _, fonts = GetRuntimeDB()
  local keybind = EnsureTable(fonts, "keybind")
  local fallback = self:GetModFontName()
  local value = keybind.face or fallback
  return addon.NormalizeFontName and addon:NormalizeFontName(value, fallback) or value
end

function Utils:SetKeybindFontName(value)
  local db, _, _, fonts = GetRuntimeDB()
  local keybind = EnsureTable(fonts, "keybind")
  keybind.face = value or self:GetModFontName()
  PersistRuntimeChange(db)
end

function Utils:GetSeqFontSize()
  local _, _, _, fonts = GetRuntimeDB()
  local seq = EnsureTable(fonts, "sequence")
  return clampValue(tonumber(seq.size) or (tonumber(GetFontDefaults("sequence").size) or 12), 6, 24)
end

function Utils:SetSeqFontSize(value)
  local db, _, _, fonts = GetRuntimeDB()
  local seq = EnsureTable(fonts, "sequence")
  seq.size = clampValue(tonumber(value) or (tonumber(GetFontDefaults("sequence").size) or 12), 6, 24)
  PersistRuntimeChange(db)
end

function Utils:GetModFontSize()
  local _, _, _, fonts = GetRuntimeDB()
  local mods = EnsureTable(fonts, "modifiers")
  return clampValue(tonumber(mods.size) or (tonumber(GetFontDefaults("modifiers").size) or 8), 6, 24)
end

-- Action Tracker font outline, shared by the sequence name / modifiers / keybind labels:
-- "NONE", "OUTLINE" (default), or "THICKOUTLINE".
local VALID_FONT_OUTLINES = { NONE = true, OUTLINE = true, THICKOUTLINE = true }
function Utils:GetActionTrackerFontOutline()
  local _, _, _, fonts = GetRuntimeDB()
  local o = tostring((fonts and fonts.outline) or "OUTLINE")
  if not VALID_FONT_OUTLINES[o] then o = "OUTLINE" end
  return o
end

function Utils:SetActionTrackerFontOutline(value)
  local db, _, _, fonts = GetRuntimeDB()
  value = tostring(value or "OUTLINE")
  if not VALID_FONT_OUTLINES[value] then value = "OUTLINE" end
  fonts.outline = value
  PersistRuntimeChange(db)
end

function Utils:SetModFontSize(value)
  local db, _, _, fonts = GetRuntimeDB()
  local mods = EnsureTable(fonts, "modifiers")
  mods.size = clampValue(tonumber(value) or (tonumber(GetFontDefaults("modifiers").size) or 8), 6, 24)
  PersistRuntimeChange(db)
end

function Utils:GetKeybindFontSize()
  local _, _, _, fonts = GetRuntimeDB()
  local keybind = EnsureTable(fonts, "keybind")
  return clampValue(tonumber(keybind.size) or self:GetModFontSize(), 6, 20)
end

function Utils:SetKeybindFontSize(value)
  local db, _, _, fonts = GetRuntimeDB()
  local keybind = EnsureTable(fonts, "keybind")
  keybind.size = clampValue(tonumber(value) or self:GetModFontSize(), 6, 20)
  PersistRuntimeChange(db)
end

function Utils:GetSequenceColorRGB(seqKey, fallbackR, fallbackG, fallbackB)
  local db = GetRuntimeDB()
  local colors = EnsureTable(db, "colors")
  local fallbackRResolved = tonumber(fallbackR) or 1
  local fallbackGResolved = tonumber(fallbackG) or 1
  local fallbackBResolved = tonumber(fallbackB) or 1

  if type(seqKey) == "string" and seqKey ~= "" then
    local color = colors[seqKey]
    if type(color) == "table" then
      return tonumber(color[1]) or fallbackRResolved, tonumber(color[2]) or fallbackGResolved, tonumber(color[3]) or fallbackBResolved
    end
  end

  return fallbackRResolved, fallbackGResolved, fallbackBResolved
end


function Utils:GetPerformanceModeEnabled()
  local _, _, _, _, flags = GetRuntimeDB()
  return flags.performanceMode and true or false
end

function Utils:SetPerformanceModeEnabledCanonical(enabled)
  local db, _, _, _, flags = GetRuntimeDB()
  flags.performanceMode = not not enabled
  PersistRuntimeChange(db)
end


function Utils:IsAssistedHighlightMirrorEnabled()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return assisted.enabled and true or false
end

function Utils:SetAssistedHighlightMirrorEnabled(enabled)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.enabled = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightSize()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return clampValue(tonumber(assisted.size) or (tonumber(GetAssistedHighlightDefaults().size) or 52), 28, 96)
end

function Utils:SetAssistedHighlightSize(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.size = clampValue(tonumber(value) or (tonumber(GetAssistedHighlightDefaults().size) or 52), 28, 96)
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightAlpha()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return clampValue(tonumber(assisted.alpha) or (tonumber(GetAssistedHighlightDefaults().alpha) or (C.ASSISTED_HIGHLIGHT_DEFAULT_ALPHA or 0.85)), 0.05, 1.00)
end

function Utils:SetAssistedHighlightAlpha(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.alpha = clampValue(tonumber(value) or (tonumber(GetAssistedHighlightDefaults().alpha) or (C.ASSISTED_HIGHLIGHT_DEFAULT_ALPHA or 0.85)), 0.05, 1.00)
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightPoint()
  local point = EnsureAssistedHighlightPointTable()
  return point[1], point[2], point[3], point[4], point[5]
end

function Utils:GetAssistedHighlightOffset()
  local _, _, _, x, y = self:GetAssistedHighlightPoint()
  return x, y
end

function Utils:SetAssistedHighlightPoint(point, relName, relPoint, x, y)
  -- Keep the legacy signature for compatibility, but fold point selection into the
  -- current anchor target so old saved point values cannot override anchor-driven placement.
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  TouchLegacyArgs(point, relName, relPoint)
  assisted.anchorTarget = NormalizeAssistedHighlightAnchorTarget(assisted.anchorTarget)
  local p = EnsureAssistedHighlightPointTable()
  local effectivePoint, effectiveRelName, effectiveRelPoint = GetAssistedHighlightAnchorPointModel(assisted.anchorTarget)
  p[1] = effectivePoint
  p[2] = effectiveRelName
  p[3] = effectiveRelPoint
  p[4] = ClampActionTrackerOffset(x)
  p[5] = ClampActionTrackerOffset(y)
  assisted.point = p
  PersistRuntimeChange(db)
end

function Utils:SetAssistedHighlightOffset(x, y)
  local point, relName, relPoint = self:GetAssistedHighlightPoint()
  self:SetAssistedHighlightPoint(point, relName, relPoint, x, y)
end


function Utils:GetAssistedHighlightShowWhen()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local default = GetAssistedHighlightDefaults().showWhen or (C.MODE_ALWAYS or "Always")
  local value = tostring(assisted.showWhen or default)
  if value ~= (C.MODE_ALWAYS or "Always") and value ~= (C.MODE_IN_COMBAT or "InCombat") and value ~= (C.MODE_HAS_TARGET or "HasTarget") and value ~= (C.MODE_NEVER or "Never") then
    value = default
  end
  return value
end

function Utils:SetAssistedHighlightShowWhen(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local default = GetAssistedHighlightDefaults().showWhen or (C.MODE_ALWAYS or "Always")
  local normalized = tostring(value or default)
  if normalized ~= (C.MODE_ALWAYS or "Always") and normalized ~= (C.MODE_IN_COMBAT or "InCombat") and normalized ~= (C.MODE_HAS_TARGET or "HasTarget") and normalized ~= (C.MODE_NEVER or "Never") then
    normalized = default
  end
  assisted.showWhen = normalized
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightLocked()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return assisted.locked and true or false
end

function Utils:SetAssistedHighlightLocked(enabled)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.locked = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightAnchorTarget()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.anchorTarget = NormalizeAssistedHighlightAnchorTarget(assisted.anchorTarget)
  return assisted.anchorTarget
end

function Utils:SetAssistedHighlightAnchorTarget(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.anchorTarget = NormalizeAssistedHighlightAnchorTarget(value)
  EnsureAssistedHighlightPointTable()
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightUseClassColor()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return assisted.useClassColor ~= false
end

function Utils:SetAssistedHighlightUseClassColor(enabled)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.useClassColor = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightColor()
  local color = EnsureAssistedHighlightColorTable()
  return color.r, color.g, color.b
end

function Utils:SetAssistedHighlightColor(r, g, b)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local color = EnsureTable(assisted, "color")
  local fallback = GetAssistedHighlightColorDefaults()
  color.r = clampValue(tonumber(r) or tonumber(fallback.r) or 0.20, 0, 1)
  color.g = clampValue(tonumber(g) or tonumber(fallback.g) or 0.60, 0, 1)
  color.b = clampValue(tonumber(b) or tonumber(fallback.b) or 1.00, 0, 1)
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightShowKeybind()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  if assisted.showKeybind == nil then
    return GetAssistedHighlightDefaults().showKeybind ~= false
  end
  return assisted.showKeybind and true or false
end

function Utils:SetAssistedHighlightShowKeybind(enabled)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.showKeybind = not not enabled
  PersistRuntimeChange(db)
end

-- The AH "Show GCD Swipe" and the Meters "Show GCD" are unified onto a SINGLE flag
-- (MetersSavedVars.showGCD) so the AH icon -- shown in the AH position AND mirrored at
-- the centre marker -- follows ONE toggle instead of two conflicting ones. The AH db
-- copy is kept in sync as a mirror / pre-Meters fallback.
function Utils:GetAssistedHighlightShowGCD()
  local sv = _G.MetersSavedVars
  if type(sv) == "table" then
    return sv.showGCD ~= false
  end
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  if assisted.showGCD == nil then
    return GetAssistedHighlightDefaults().showGCD ~= false
  end
  return assisted.showGCD and true or false
end

function Utils:SetAssistedHighlightShowGCD(enabled)
  enabled = not not enabled
  local sv = _G.MetersSavedVars
  if type(sv) == "table" then sv.showGCD = enabled end
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.showGCD = enabled
  PersistRuntimeChange(db)
end

-- ModKey burst stack (centered z-stack of modifier-fired abilities). Default ON.
function Utils:GetModkeyStackEnabled()
  local db = GetRuntimeDB()
  if db.modkeyStackEnabled == nil then return true end
  return db.modkeyStackEnabled and true or false
end

function Utils:SetModkeyStackEnabled(enabled)
  local db = GetRuntimeDB()
  db.modkeyStackEnabled = not not enabled
  PersistRuntimeChange(db)
end

-- Proc glow: flash the main-row icon when a cast matches the AH suggestion. Default ON.
function Utils:GetProcGlowEnabled()
  local db = GetRuntimeDB()
  if db.procGlowEnabled == nil then return true end
  return db.procGlowEnabled and true or false
end

function Utils:SetProcGlowEnabled(enabled)
  local db = GetRuntimeDB()
  db.procGlowEnabled = not not enabled
  PersistRuntimeChange(db)
end

-- QoL: mute the spell-fizzle (cast-failure) sounds. Default OFF.
function Utils:GetMuteFizzles()
  local db = GetRuntimeDB()
  return db.muteFizzles and true or false
end

function Utils:SetMuteFizzles(enabled)
  local db = GetRuntimeDB()
  db.muteFizzles = not not enabled
  PersistRuntimeChange(db)
  if addon.ApplyMuteFizzles then addon:ApplyMuteFizzles(db.muteFizzles) end
end

-- QoL: hide the red UIErrorsFrame error text. Default OFF.
function Utils:GetHideErrors()
  local db = GetRuntimeDB()
  return db.hideErrors and true or false
end

function Utils:SetHideErrors(enabled)
  local db = GetRuntimeDB()
  db.hideErrors = not not enabled
  PersistRuntimeChange(db)
  if addon.ApplyHideErrors then addon:ApplyHideErrors(db.hideErrors) end
end

-- AH match % readout (matches / casts over the session's combat time). Default OFF.
function Utils:GetAHMatchPercentEnabled()
  local db = GetRuntimeDB()
  return db.ahMatchPercentEnabled and true or false
end

function Utils:SetAHMatchPercentEnabled(enabled)
  local db = GetRuntimeDB()
  db.ahMatchPercentEnabled = not not enabled
  PersistRuntimeChange(db)
end

-- AH match audible alert + chosen LibSharedMedia sound name. Default OFF.
function Utils:GetAHMatchAudibleEnabled()
  local db = GetRuntimeDB()
  return db.ahMatchAudibleEnabled and true or false
end

function Utils:SetAHMatchAudibleEnabled(enabled)
  local db = GetRuntimeDB()
  db.ahMatchAudibleEnabled = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetAHMatchSound()
  local db = GetRuntimeDB()
  return (type(db.ahMatchSound) == "string" and db.ahMatchSound ~= "") and db.ahMatchSound or nil
end

function Utils:SetAHMatchSound(name)
  local db = GetRuntimeDB()
  db.ahMatchSound = (type(name) == "string" and name ~= "") and name or nil
  PersistRuntimeChange(db)
end


function Utils:GetAssistedHighlightPreviewEnabled()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return assisted.preview and true or false
end

function Utils:SetAssistedHighlightPreviewEnabled(enabled)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.preview = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightRangeCheckerEnabled()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  if assisted.rangeChecker == nil then
    return GetAssistedHighlightDefaults().rangeChecker ~= false
  end
  return assisted.rangeChecker and true or false
end

function Utils:SetAssistedHighlightRangeCheckerEnabled(enabled)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.rangeChecker = not not enabled
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightBorderSize()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return clampValue(tonumber(assisted.borderSize) or (tonumber(GetAssistedHighlightDefaults().borderSize) or 2), 0, 12)
end

function Utils:SetAssistedHighlightBorderSize(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.borderSize = clampValue(tonumber(value) or (tonumber(GetAssistedHighlightDefaults().borderSize) or 2), 0, 12)
  PersistRuntimeChange(db)
end

function Utils:GetAccountWide()
  return (SV and SV.GetAccountWide and SV:GetAccountWide()) or false
end

function Utils:SetAccountWide(enabled)
  if SV and SV.SetAccountWide then SV:SetAccountWide(enabled) end
  -- The active store changed: invalidate the runtime cache and persist.
  _cachedRawRef = nil
  local db = GetRuntimeDB()
  PersistRuntimeChange(db)
end

local VALID_LAYOUT = { HORIZONTAL = true, VERTICAL = true }
local VALID_SCROLL_DIR = { LEFT = true, RIGHT = true, UP = true, DOWN = true }

function Utils:GetActionTrackerLayout()
  local _, _, display = GetRuntimeDB()
  local v = tostring(display.layout or "")
  if VALID_LAYOUT[v] then return v end
  return "HORIZONTAL"
end

function Utils:SetActionTrackerLayout(value)
  local db, _, display = GetRuntimeDB()
  value = tostring(value or "")
  display.layout = VALID_LAYOUT[value] and value or "HORIZONTAL"
  PersistRuntimeChange(db)
end

function Utils:GetActionTrackerScroll()
  local _, _, display = GetRuntimeDB()
  local v = tostring(display.scrollDirection or "")
  -- Constrain to the layout's axis: vertical uses UP/DOWN (default DOWN),
  -- horizontal uses LEFT/RIGHT (default RIGHT). A stored value for the other axis
  -- (or no selection) falls back to the axis default.
  if self:GetActionTrackerLayout() == "VERTICAL" then
    if v == "UP" or v == "DOWN" then return v end
    return "DOWN"
  end
  if v == "LEFT" or v == "RIGHT" then return v end
  return "RIGHT"
end

function Utils:SetActionTrackerScroll(value)
  local db, _, display = GetRuntimeDB()
  value = tostring(value or "")
  display.scrollDirection = VALID_SCROLL_DIR[value] and value or "LEFT"
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightKeybindOffset()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local defaults = GetAssistedHighlightDefaults()
  local x = clampValue(tonumber(assisted.keybindXOffset) or (tonumber(defaults.keybindXOffset) or -3), -64, 64)
  local y = clampValue(tonumber(assisted.keybindYOffset) or (tonumber(defaults.keybindYOffset) or -3), -64, 64)
  return x, y
end

function Utils:SetAssistedHighlightKeybindOffset(x, y)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.keybindXOffset = clampValue(tonumber(x) or (tonumber(GetAssistedHighlightDefaults().keybindXOffset) or -3), -64, 64)
  assisted.keybindYOffset = clampValue(tonumber(y) or (tonumber(GetAssistedHighlightDefaults().keybindYOffset) or -3), -64, 64)
  PersistRuntimeChange(db)
end

local VALID_AH_KEYBIND_ANCHORS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true, CENTER = true }

function Utils:GetAssistedHighlightKeybindAnchor()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local default = GetAssistedHighlightDefaults().keybindAnchor or "TOPRIGHT"
  local value = tostring(assisted.keybindAnchor or default)
  if not VALID_AH_KEYBIND_ANCHORS[value] then value = default end
  return value
end

function Utils:SetAssistedHighlightKeybindAnchor(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local default = GetAssistedHighlightDefaults().keybindAnchor or "TOPRIGHT"
  local normalized = tostring(value or default)
  if not VALID_AH_KEYBIND_ANCHORS[normalized] then normalized = default end
  assisted.keybindAnchor = normalized
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightFontName()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  local fallback = self:GetKeybindFontName()
  local value = assisted.fontFace or fallback
  return addon.NormalizeFontName and addon:NormalizeFontName(value, fallback) or value
end

function Utils:SetAssistedHighlightFontName(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.fontFace = value or self:GetKeybindFontName()
  PersistRuntimeChange(db)
end

function Utils:GetAssistedHighlightFontSize()
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  return clampValue(tonumber(assisted.fontSize) or self:GetKeybindFontSize(), 6, 40)
end

function Utils:SetAssistedHighlightFontSize(value)
  local db = GetRuntimeDB()
  local assisted = EnsureTable(db, "assistedHighlight")
  assisted.fontSize = clampValue(tonumber(value) or self:GetKeybindFontSize(), 6, 40)
  PersistRuntimeChange(db)
end
