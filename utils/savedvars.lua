local _, ns = ...
local addon = ns
local Utils = ns.Utils or {}
ns.Utils = Utils

local SV = Utils.SV or {}
Utils.SV = SV
local C = Utils.Constants or addon.Constants or {}

SV.SCHEMA_VERSION = C.SCHEMA_VERSION or 3
SV.DB_NAME = C.DB_NAME or "GSETrackerDB"            -- account-wide store (holds the accountWide flag)
SV.CHAR_DB_NAME = C.CHAR_DB_NAME or "GSETrackerCharDB" -- per-character store
SV.ADDON_VERSION = C.ADDON_VERSION or "1.1.4"
local ACTION_TRACKER_POSITION_LIMIT = tonumber(C.ACTION_TRACKER_POSITION_LIMIT) or 3000

-- The highest migration version actually implemented in this file.
-- RunMigrations checks this at runtime to catch SCHEMA_VERSION bumps that
-- were made without a corresponding MigrateToVersion<N> function.
local MAX_IMPLEMENTED_MIGRATION = 3

local Clamp
local RoundNearest

local function CopyDefaultActionTrackerPoint()
  return (C.CopyDefaultActionTrackerPoint and C:CopyDefaultActionTrackerPoint()) or { "CENTER", "UIParent", "CENTER", 0, 0 }
end

local ROOT_DEFAULTS = {
  _meta = {
    schemaVersion = SV.SCHEMA_VERSION,
    lastAddonVersion = SV.ADDON_VERSION,
    migratedFrom = 0,
  },
  general = {
    enabled = true,
    locked = true,
    showWhen = C.MODE_ALWAYS or "Always",
    strata = C.DEFAULT_COMBAT_TRACKER_STRATA or (C.STRATA_MEDIUM or "MEDIUM"),
  },
  display = {
    scale = C.DEFAULT_SCALE or 1.00,
    iconCount = 6,
    iconGap = 0,
    layout = "HORIZONTAL",       -- HORIZONTAL | VERTICAL
    scrollDirection = "RIGHT",   -- LEFT | RIGHT (horizontal) | UP | DOWN (vertical); getter normalizes to the layout axis
    border = true,
    borderThickness = 1,
    borderUseClassColor = false,
    borderColor = {
      r = 0,
      g = 0,
      b = 0,
    },
    point = CopyDefaultActionTrackerPoint(),
    pressedIndicator = {
      shape = "X.png",
      size = 24,
    },
  },
  fonts = {
    outline = "OUTLINE",
    sequence = {
      face = C.FONT_FRIZ or "Friz Quadrata TT",
      size = 18,
    },
    modifiers = {
      face = C.FONT_FRIZ or "Friz Quadrata TT",
      size = 16,
    },
    keybind = {
      face = C.FONT_FRIZ or "Friz Quadrata TT",
      size = 13,
    },
  },
  flags = {
    performanceMode = false,
  },
  combatMarker = {
    enabled = true,
    preview = false,
    showWhen = C.MODE_ALWAYS or "Always",
    symbol = "X.png",
    size = 18,
    thickness = 1,
    borderSize = 0,
    alpha = 1.00,
    useClassColor = false,
    point = C.COMBAT_MARKER_DEFAULT_POINT or { "CENTER", "UIParent", "CENTER", 0, 0 },
    color = {
      r = 1.00,
      g = 0,
      b = 0.086,
    },
  },
  assistedHighlight = {
    enabled = false,
    preview = false,
    locked = false,
    showWhen = C.MODE_ALWAYS or "Always",
    size = 60,
    alpha = 1.00,
    borderSize = 1,
    point = { "CENTER", "UIParent", "CENTER", 0, -140 },
    anchorTarget = "Screen",
    showKeybind = true,
    showGCD = true,
    rangeChecker = true,
    useClassColor = false,
    color = {
      r = 0,
      g = 0,
      b = 0,
    },
    keybindXOffset = 16,
    keybindYOffset = 13,
    keybindAnchor = "TOPRIGHT",
    fontFace = "Friz Quadrata TT",
    fontSize = 15,
  },
  minimap = {
    angle = 225,
  },
  appearance = {
    skin = "AUTO",
  },
  layout = {
    offsetModelVersion = 2,
    rowRelativeAnchorModelVersion = 2,
    elements = {},
  },
  colors = {},
}

local VALID_SHOW = { [C.MODE_ALWAYS or "Always"] = true, [C.MODE_IN_COMBAT or "InCombat"] = true, [C.MODE_HAS_TARGET or "HasTarget"] = true, [C.MODE_NEVER or "Never"] = true }
local VALID_SKIN = { AUTO = true, MODERN = true, NATIVE = true }
local VALID_SHAPES = { square = true, circle = true, dot = true, cross = true, eye = true }
-- Valid Pressed Indicator shapes: the procedural shapes above, plus "None" (off) and
-- any media image symbol from the manifest (e.g. "GSE_Tracker_Round"). Without this
-- the image/None choices would be reset to the default on normalize and never persist.
local function IsValidPressedShape(shape)
  shape = tostring(shape or "")
  return VALID_SHAPES[shape]
    or shape == "None"
    or (C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[shape])
    or false
end
local VALID_LAYOUT = { HORIZONTAL = true, VERTICAL = true }
local VALID_SCROLL_DIR = { LEFT = true, RIGHT = true, UP = true, DOWN = true }
local VALID_COMBAT_MARKER_SYMBOLS = { x = true, plus = true, diamond = true, square = true, circle = true }
local VALID_FRAME_STRATA = C.VALID_FRAME_STRATA or { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }


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

local function NormalizeCombatMarkerSymbol(symbol)
  symbol = tostring(symbol or ROOT_DEFAULTS.combatMarker.symbol)
  if VALID_COMBAT_MARKER_SYMBOLS[symbol] then
    return symbol
  end
  -- Media image symbols (e.g. "GSE_Tracker.png") are also valid; see the manifest
  -- in constants.lua (C.COMBAT_MARKER_IMAGE_VALID).
  if C.COMBAT_MARKER_IMAGE_VALID and C.COMBAT_MARKER_IMAGE_VALID[symbol] then
    return symbol
  end
  -- Dynamic ported-Meters symbols (Bullseye/Class/Specialization), "None" (off) and
  -- "AHLight" (the AH engine mirrors its icon at centre) are valid now that every
  -- Center Marker option routes through this one symbol.
  if (C.COMBAT_MARKER_DYNAMIC_VALID and C.COMBAT_MARKER_DYNAMIC_VALID[symbol])
    or symbol == "None" or symbol == "AHLight" then
    return symbol
  end
  if symbol == "cross" then return "plus" end
  return ROOT_DEFAULTS.combatMarker.symbol
end

local VALID_AH_KEYBIND_ANCHORS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true, CENTER = true }
local function NormalizeAHKeybindAnchor(value)
  value = tostring(value or (ROOT_DEFAULTS.assistedHighlight.keybindAnchor or "TOPRIGHT"))
  if VALID_AH_KEYBIND_ANCHORS[value] then return value end
  return ROOT_DEFAULTS.assistedHighlight.keybindAnchor or "TOPRIGHT"
end

local function IsLegacyCombatMarkerDefaultPoint(point)
  return type(point) == "table"
    and tostring(point[1] or "") == "TOP"
    and tostring(point[2] or "") == (C.UI_PARENT_NAME or "UIParent")
    and tostring(point[3] or "") == (C.ANCHOR_CENTER or "CENTER")
    and (tonumber(point[4]) or 0) == 0
    and (tonumber(point[5]) or 120) == 120
end

local function SanitizeCombatMarkerPoint(point)
  local fallback = ROOT_DEFAULTS.combatMarker.point or C.COMBAT_MARKER_DEFAULT_POINT or { "CENTER", "UIParent", "CENTER", 0, 120 }
  if type(point) ~= "table" then
    point = { fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] }
  elseif IsLegacyCombatMarkerDefaultPoint(point) then
    point = { fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] }
  end
  point[1] = VALID_COMBAT_MARKER_ANCHORS[point[1]] and point[1] or fallback[1]
  point[2] = C.UI_PARENT_NAME or "UIParent"
  point[3] = C.ANCHOR_CENTER or "CENTER"
  point[4] = Clamp(RoundNearest(tonumber(point[4]) or fallback[4]), -ACTION_TRACKER_POSITION_LIMIT, ACTION_TRACKER_POSITION_LIMIT)
  point[5] = Clamp(RoundNearest(tonumber(point[5]) or fallback[5]), -ACTION_TRACKER_POSITION_LIMIT, ACTION_TRACKER_POSITION_LIMIT)
  return point
end

local LEGACY_IMPORT_KEYS = {
  "enabled", "locked", "showWhen",
  "scale", "iconCount", "iconGap", "layout", "scrollDirection", "border", "borderThickness", "point",
  "pressedIndicatorShape", "pressedIndicatorSize",
  "seqFont", "seqFontSize", "modFont", "modFontSize", "keybindFont", "keybindFontSize",
  "performanceMode",
}

local function HasLegacyImportData(db)
  if type(db) ~= "table" then return false end
  for _, key in ipairs(LEGACY_IMPORT_KEYS) do
    if db[key] ~= nil then
      return true
    end
  end
  return false
end

local function HasCanonicalData(db)
  if type(db) ~= "table" then return false end
  return type(db._meta) == "table"
    or type(db.general) == "table"
    or type(db.display) == "table"
    or type(db.fonts) == "table"
    or type(db.flags) == "table"
    or type(db.layout) == "table"
end

local function ShouldImportLegacyFlat(db)
  if not HasLegacyImportData(db) then return false end
  if not HasCanonicalData(db) then return true end

  local schemaVersion = tonumber(db._meta and db._meta.schemaVersion) or tonumber(db._schemaVersion) or 0
  return schemaVersion < (SV.SCHEMA_VERSION or 0)
end

Clamp = function(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

RoundNearest = function(v)
  v = tonumber(v) or 0
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return math.ceil(v - 0.5)
end

local function DeepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    out[k] = DeepCopy(v)
  end
  return out
end

function SV:CopyDefaults()
  return DeepCopy(ROOT_DEFAULTS)
end

function SV:GetRootDefaults()
  return ROOT_DEFAULTS
end


local function MergeMissing(dst, defaults)
  for k, v in pairs(defaults) do
    if dst[k] == nil then
      dst[k] = DeepCopy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" then
      MergeMissing(dst[k], v)
    end
  end
end

local function EnsureTable(parent, key)
  local value = parent[key]
  if type(value) ~= "table" then
    value = {}
    parent[key] = value
  end
  return value
end

local function EnsureAncillaryTables(db)
  if type(db.colors) ~= "table" then
    db.colors = {}
  end

  if addon and addon.EnsureLayoutDB then
    addon:EnsureLayoutDB(db)
  else
    local layout = EnsureTable(db, "layout")
    EnsureTable(layout, "elements")
  end
end


local function SanitizePoint(point, fallback)
  fallback = fallback or ROOT_DEFAULTS.display.point
  if type(point) ~= "table" then
    point = DeepCopy(fallback)
  end
  point[1] = type(point[1]) == "string" and point[1] ~= "" and point[1] or fallback[1]
  point[2] = type(point[2]) == "string" and point[2] ~= "" and point[2] or fallback[2]
  point[3] = type(point[3]) == "string" and point[3] ~= "" and point[3] or fallback[3]
  point[4] = Clamp(RoundNearest(tonumber(point[4]) or fallback[4]), -ACTION_TRACKER_POSITION_LIMIT, ACTION_TRACKER_POSITION_LIMIT)
  point[5] = Clamp(RoundNearest(tonumber(point[5]) or fallback[5]), -ACTION_TRACKER_POSITION_LIMIT, ACTION_TRACKER_POSITION_LIMIT)
  return point
end

local function NormalizeCanonical(db)
  MergeMissing(db, ROOT_DEFAULTS)

  local meta = EnsureTable(db, "_meta")
  meta.schemaVersion = tonumber(meta.schemaVersion) or 0
  meta.lastAddonVersion = tostring(meta.lastAddonVersion or SV.ADDON_VERSION)
  meta.migratedFrom = tonumber(meta.migratedFrom) or 0

  local general = EnsureTable(db, "general")
  general.enabled = general.enabled ~= false
  general.locked = not not general.locked
  general.showWhen = VALID_SHOW[tostring(general.showWhen)] and tostring(general.showWhen) or ROOT_DEFAULTS.general.showWhen
  general.strata = VALID_FRAME_STRATA[tostring(general.strata)] and tostring(general.strata) or ROOT_DEFAULTS.general.strata

  local appearance = EnsureTable(db, "appearance")
  appearance.skin = VALID_SKIN[tostring(appearance.skin)] and tostring(appearance.skin) or ROOT_DEFAULTS.appearance.skin

  local display = EnsureTable(db, "display")
  display.scale = Clamp(tonumber(display.scale) or ROOT_DEFAULTS.display.scale, 0.70, 1.80)
  display.iconCount = Clamp(tonumber(display.iconCount) or ROOT_DEFAULTS.display.iconCount, C.MIN_ICON_COUNT or 4, C.MAX_ICON_COUNT or 8)
  display.iconGap = Clamp(tonumber(display.iconGap) or ROOT_DEFAULTS.display.iconGap, 0, 5)
  display.layout = VALID_LAYOUT[tostring(display.layout)] and tostring(display.layout) or ROOT_DEFAULTS.display.layout
  display.scrollDirection = VALID_SCROLL_DIR[tostring(display.scrollDirection)] and tostring(display.scrollDirection) or ROOT_DEFAULTS.display.scrollDirection
  display.border = not not display.border
  display.borderThickness = Clamp(tonumber(display.borderThickness) or ROOT_DEFAULTS.display.borderThickness, 0, 5)
  display.borderUseClassColor = display.borderUseClassColor ~= false
  local actionTrackerBorderColor = EnsureTable(display, "borderColor")
  local actionTrackerBorderDefaults = ROOT_DEFAULTS.display.borderColor or { r = 0.20, g = 0.60, b = 1.00 }
  actionTrackerBorderColor.r = Clamp(tonumber(actionTrackerBorderColor.r) or actionTrackerBorderDefaults.r or 0.20, 0, 1)
  actionTrackerBorderColor.g = Clamp(tonumber(actionTrackerBorderColor.g) or actionTrackerBorderDefaults.g or 0.60, 0, 1)
  actionTrackerBorderColor.b = Clamp(tonumber(actionTrackerBorderColor.b) or actionTrackerBorderDefaults.b or 1.00, 0, 1)
  if display.border == false then
    display.borderThickness = 0
  end
  display.point = SanitizePoint(display.point, ROOT_DEFAULTS.display.point)

  local pressed = EnsureTable(display, "pressedIndicator")
  local shape = tostring(pressed.shape or ROOT_DEFAULTS.display.pressedIndicator.shape)
  pressed.shape = IsValidPressedShape(shape) and shape or ROOT_DEFAULTS.display.pressedIndicator.shape
  pressed.size = Clamp(tonumber(pressed.size) or ROOT_DEFAULTS.display.pressedIndicator.size, C.PRESSED_INDICATOR_MIN_SIZE or 4, C.PRESSED_INDICATOR_MAX_SIZE or 24)

  local fonts = EnsureTable(db, "fonts")
  local seq = EnsureTable(fonts, "sequence")
  local mods = EnsureTable(fonts, "modifiers")
  local keybind = EnsureTable(fonts, "keybind")

  seq.face = type(seq.face) == "string" and seq.face or (addon.DEFAULT_SEQ_FONT or ROOT_DEFAULTS.fonts.sequence.face)
  mods.face = type(mods.face) == "string" and mods.face or (addon.DEFAULT_MOD_FONT or ROOT_DEFAULTS.fonts.modifiers.face)
  keybind.face = type(keybind.face) == "string" and keybind.face or mods.face

  seq.size = Clamp(tonumber(seq.size) or ROOT_DEFAULTS.fonts.sequence.size, 8, 24)
  mods.size = Clamp(tonumber(mods.size) or ROOT_DEFAULTS.fonts.modifiers.size, 6, 20)
  keybind.size = Clamp(tonumber(keybind.size) or mods.size, 6, 20)

  local flags = EnsureTable(db, "flags")
  flags.performanceMode = not not flags.performanceMode

  local combatMarker = EnsureTable(db, "combatMarker")
  combatMarker.enabled = not not combatMarker.enabled
  combatMarker.preview = not not combatMarker.preview
  combatMarker.showWhen = VALID_SHOW[tostring(combatMarker.showWhen)] and tostring(combatMarker.showWhen) or ROOT_DEFAULTS.combatMarker.showWhen
  combatMarker.symbol = NormalizeCombatMarkerSymbol(combatMarker.symbol)
  combatMarker.size = Clamp(tonumber(combatMarker.size) or ROOT_DEFAULTS.combatMarker.size, C.COMBAT_MARKER_MIN_SIZE or 16, C.COMBAT_MARKER_MAX_SIZE or 128)
  combatMarker.thickness = Clamp(tonumber(combatMarker.thickness) or ROOT_DEFAULTS.combatMarker.thickness, C.COMBAT_MARKER_MIN_THICKNESS or 1, C.COMBAT_MARKER_MAX_THICKNESS or 12)
  combatMarker.borderSize = Clamp(tonumber(combatMarker.borderSize) or ROOT_DEFAULTS.combatMarker.borderSize, C.COMBAT_MARKER_MIN_BORDER_SIZE or 0, C.COMBAT_MARKER_MAX_BORDER_SIZE or 8)
  combatMarker.alpha = Clamp(tonumber(combatMarker.alpha) or ROOT_DEFAULTS.combatMarker.alpha, 0.05, 1.00)
  combatMarker.useClassColor = combatMarker.useClassColor ~= false
  local combatColor = EnsureTable(combatMarker, "color")
  combatColor.r = Clamp(tonumber(combatColor.r) or ROOT_DEFAULTS.combatMarker.color.r, 0, 1)
  combatColor.g = Clamp(tonumber(combatColor.g) or ROOT_DEFAULTS.combatMarker.color.g, 0, 1)
  combatColor.b = Clamp(tonumber(combatColor.b) or ROOT_DEFAULTS.combatMarker.color.b, 0, 1)
  combatMarker.point = SanitizeCombatMarkerPoint(combatMarker.point)

  local assistedHighlight = EnsureTable(db, "assistedHighlight")
  assistedHighlight.enabled = not not assistedHighlight.enabled
  assistedHighlight.preview = not not assistedHighlight.preview
  assistedHighlight.locked = not not assistedHighlight.locked
  assistedHighlight.showWhen = VALID_SHOW[tostring(assistedHighlight.showWhen)] and tostring(assistedHighlight.showWhen) or ROOT_DEFAULTS.assistedHighlight.showWhen
  assistedHighlight.size = Clamp(tonumber(assistedHighlight.size) or ROOT_DEFAULTS.assistedHighlight.size, 28, 96)
  assistedHighlight.alpha = Clamp(tonumber(assistedHighlight.alpha) or ROOT_DEFAULTS.assistedHighlight.alpha, 0.05, 1.00)
  assistedHighlight.borderSize = Clamp(tonumber(assistedHighlight.borderSize) or ROOT_DEFAULTS.assistedHighlight.borderSize or 2, 0, 12)
  assistedHighlight.point = SanitizePoint(assistedHighlight.point, ROOT_DEFAULTS.assistedHighlight.point)
  assistedHighlight.anchorTarget = tostring(assistedHighlight.anchorTarget or ROOT_DEFAULTS.assistedHighlight.anchorTarget or "Screen")
  assistedHighlight.showKeybind = assistedHighlight.showKeybind ~= false
  assistedHighlight.showGCD = assistedHighlight.showGCD ~= false
  assistedHighlight.rangeChecker = assistedHighlight.rangeChecker ~= false
  assistedHighlight.useClassColor = assistedHighlight.useClassColor ~= false
  local ahColor = EnsureTable(assistedHighlight, "color")
  local ahColorDefaults = ROOT_DEFAULTS.assistedHighlight.color or { r = 0.20, g = 0.60, b = 1.00 }
  ahColor.r = Clamp(tonumber(ahColor.r) or ahColorDefaults.r or 0.20, 0, 1)
  ahColor.g = Clamp(tonumber(ahColor.g) or ahColorDefaults.g or 0.60, 0, 1)
  ahColor.b = Clamp(tonumber(ahColor.b) or ahColorDefaults.b or 1.00, 0, 1)
  assistedHighlight.keybindXOffset = Clamp(RoundNearest(tonumber(assistedHighlight.keybindXOffset) or ROOT_DEFAULTS.assistedHighlight.keybindXOffset or -3), -64, 64)
  assistedHighlight.keybindYOffset = Clamp(RoundNearest(tonumber(assistedHighlight.keybindYOffset) or ROOT_DEFAULTS.assistedHighlight.keybindYOffset or -3), -64, 64)
  assistedHighlight.keybindAnchor = NormalizeAHKeybindAnchor(assistedHighlight.keybindAnchor)
  assistedHighlight.fontFace = type(assistedHighlight.fontFace) == "string" and assistedHighlight.fontFace or ROOT_DEFAULTS.assistedHighlight.fontFace
  assistedHighlight.fontSize = Clamp(tonumber(assistedHighlight.fontSize) or ROOT_DEFAULTS.assistedHighlight.fontSize or 8, 6, 40)
  assistedHighlight.showStacks = nil
  assistedHighlight.showCooldown = nil
  assistedHighlight.showUnusable = nil

  local minimap = EnsureTable(db, "minimap")
  local minimapDefaults = ROOT_DEFAULTS.minimap or { angle = 225 }
  local minimapAngle = tonumber(minimap.angle)
  if minimapAngle == nil then
    minimapAngle = tonumber(minimapDefaults.angle) or 225
  end
  minimap.angle = minimapAngle % 360

  EnsureAncillaryTables(db)

  if addon and addon.MaybeMigrateLegacyFontsInDB then
    addon:MaybeMigrateLegacyFontsInDB(db)
  end
end

-- The accountWide flag ALWAYS lives in the account store so it's a single global
-- preference, readable before we decide which store is active.
function SV:IsAccountWide()
  local acc = _G[self.DB_NAME]
  return (acc and acc.accountWide) and true or false
end

-- Seed a fresh per-character store from the account store once, so existing
-- (previously account-wide) setups carry over to the character on first use.
local function SeedCharFromAccount(self)
  local char = _G[self.CHAR_DB_NAME]
  if not char or char._gseSeeded then return end
  char._gseSeeded = true
  local account = _G[self.DB_NAME]
  if type(account) == "table" then
    for k, v in pairs(account) do
      if k ~= "accountWide" and char[k] == nil then
        char[k] = DeepCopy(v)
      end
    end
  end
end

-- READ-ONLY active store: NEVER writes globals, so it's safe to call on every
-- GetRuntimeDB (incl. inside dropdown generators that run in the shared Menu
-- system used by the GameMenu). `_G.X = _G.X or {}` self-assigns the global on
-- every call, which re-taints it and broke Logout/action-bar grid.
function SV:GetActiveDBRaw()
  if self:IsAccountWide() then return _G[self.DB_NAME] end
  return _G[self.CHAR_DB_NAME]
end

-- Returns the ACTIVE store, creating the backing globals ONLY when missing (no
-- per-call self-assign writes).
function SV:GetDB()
  if _G[self.DB_NAME] == nil then _G[self.DB_NAME] = {} end
  if _G[self.CHAR_DB_NAME] == nil then _G[self.CHAR_DB_NAME] = {} end
  if self:IsAccountWide() then
    return _G[self.DB_NAME]
  end
  SeedCharFromAccount(self)
  return _G[self.CHAR_DB_NAME]
end

function SV:GetAccountWide()
  return self:IsAccountWide()
end

-- Toggle account-wide saving, migrating (copying) the current active store's
-- settings into the new active store so the tracker looks identical afterwards.
function SV:SetAccountWide(enabled)
  enabled = enabled and true or false
  if _G[self.DB_NAME] == nil then _G[self.DB_NAME] = {} end
  if _G[self.CHAR_DB_NAME] == nil then _G[self.CHAR_DB_NAME] = {} end
  local account = _G[self.DB_NAME]
  local char = _G[self.CHAR_DB_NAME]
  if (account.accountWide and true or false) == enabled then return end

  if enabled then
    -- per-character -> account: copy this character's settings up.
    for k in pairs(account) do
      if k ~= "accountWide" then account[k] = nil end
    end
    for k, v in pairs(char) do
      if k ~= "accountWide" and k ~= "_gseSeeded" then account[k] = DeepCopy(v) end
    end
  else
    -- account -> per-character: copy account settings down.
    for k in pairs(char) do
      if k ~= "_gseSeeded" then char[k] = nil end
    end
    for k, v in pairs(account) do
      if k ~= "accountWide" then char[k] = DeepCopy(v) end
    end
    char._gseSeeded = true
  end
  account.accountWide = enabled
end

function SV:SyncLegacyMirrorToCanonical(db)
  if type(db) ~= "table" then return end

  local general = EnsureTable(db, "general")
  local assistedHighlight = EnsureTable(db, "assistedHighlight")
  assistedHighlight.enabled = not not assistedHighlight.enabled
  assistedHighlight.preview = not not assistedHighlight.preview
  assistedHighlight.locked = not not assistedHighlight.locked
  assistedHighlight.size = Clamp(tonumber(assistedHighlight.size) or ROOT_DEFAULTS.assistedHighlight.size, 28, 96)
  assistedHighlight.alpha = Clamp(tonumber(assistedHighlight.alpha) or ROOT_DEFAULTS.assistedHighlight.alpha, 0.05, 1.00)
  assistedHighlight.borderSize = Clamp(tonumber(assistedHighlight.borderSize) or ROOT_DEFAULTS.assistedHighlight.borderSize, 0, 12)
  assistedHighlight.point = SanitizePoint(assistedHighlight.point, ROOT_DEFAULTS.assistedHighlight.point)
  assistedHighlight.anchorTarget = tostring(assistedHighlight.anchorTarget or ROOT_DEFAULTS.assistedHighlight.anchorTarget or "Screen")
  assistedHighlight.showKeybind = assistedHighlight.showKeybind ~= false
  assistedHighlight.showGCD = assistedHighlight.showGCD ~= false
  assistedHighlight.rangeChecker = assistedHighlight.rangeChecker ~= false
  assistedHighlight.useClassColor = assistedHighlight.useClassColor ~= false
  local ahColor = EnsureTable(assistedHighlight, "color")
  local ahColorDefaults = ROOT_DEFAULTS.assistedHighlight.color or { r = 0.20, g = 0.60, b = 1.00 }
  ahColor.r = Clamp(tonumber(ahColor.r) or ahColorDefaults.r or 0.20, 0, 1)
  ahColor.g = Clamp(tonumber(ahColor.g) or ahColorDefaults.g or 0.60, 0, 1)
  ahColor.b = Clamp(tonumber(ahColor.b) or ahColorDefaults.b or 1.00, 0, 1)
  assistedHighlight.keybindXOffset = Clamp(RoundNearest(tonumber(assistedHighlight.keybindXOffset) or ROOT_DEFAULTS.assistedHighlight.keybindXOffset or -3), -64, 64)
  assistedHighlight.keybindYOffset = Clamp(RoundNearest(tonumber(assistedHighlight.keybindYOffset) or ROOT_DEFAULTS.assistedHighlight.keybindYOffset or -3), -64, 64)
  assistedHighlight.keybindAnchor = NormalizeAHKeybindAnchor(assistedHighlight.keybindAnchor)
  assistedHighlight.fontFace = assistedHighlight.fontFace or ROOT_DEFAULTS.assistedHighlight.fontFace
  assistedHighlight.fontSize = Clamp(tonumber(assistedHighlight.fontSize) or ROOT_DEFAULTS.assistedHighlight.fontSize or 8, 6, 40)

  local display = EnsureTable(db, "display")
  local fonts = EnsureTable(db, "fonts")
  local seq = EnsureTable(fonts, "sequence")
  local mods = EnsureTable(fonts, "modifiers")
  local keybind = EnsureTable(fonts, "keybind")
  local flags = EnsureTable(db, "flags")
  local pressed = EnsureTable(display, "pressedIndicator")

  if db.enabled ~= nil then general.enabled = db.enabled end
  if db.locked ~= nil then general.locked = db.locked end
  if db.showWhen ~= nil then general.showWhen = db.showWhen end

  if db.scale ~= nil then display.scale = db.scale end
  if db.iconCount ~= nil then display.iconCount = db.iconCount end
  if db.iconGap ~= nil then display.iconGap = db.iconGap end
  if db.layout ~= nil then display.layout = db.layout end
  if db.scrollDirection ~= nil then display.scrollDirection = db.scrollDirection end
  if db.border ~= nil then display.border = db.border end
  if db.borderThickness ~= nil then display.borderThickness = db.borderThickness end
  if db.borderUseClassColor ~= nil then display.borderUseClassColor = db.borderUseClassColor end
  if type(db.borderColor) == "table" then display.borderColor = db.borderColor end
  if db.point ~= nil then display.point = db.point end

  if db.pressedIndicatorShape ~= nil then pressed.shape = db.pressedIndicatorShape end
  if db.pressedIndicatorSize ~= nil then pressed.size = db.pressedIndicatorSize end

  if db.seqFont ~= nil then seq.face = db.seqFont end
  if db.seqFontSize ~= nil then seq.size = db.seqFontSize end
  if db.modFont ~= nil then mods.face = db.modFont end
  if db.modFontSize ~= nil then mods.size = db.modFontSize end
  if db.keybindFont ~= nil then keybind.face = db.keybindFont end
  if db.keybindFontSize ~= nil then keybind.size = db.keybindFontSize end

  if db.performanceMode ~= nil then flags.performanceMode = db.performanceMode end

  if type(db.colors) ~= "table" then
    db.colors = {}
  end
end

function SV:MigrateToVersion1(db)
  if type(db.point) ~= "table" or #db.point < 5 then
    db.point = (C.CopyDefaultActionTrackerPoint and C:CopyDefaultActionTrackerPoint()) or { "CENTER", "UIParent", "CENTER", 0, 0 }
  end
  if type(db.colors) ~= "table" then
    db.colors = {}
  end
  db._schemaVersion = 1
end

function SV:MigrateToVersion2(db)
  if type(db.point) ~= "table" or #db.point < 5 then
    db.point = CopyDefaultActionTrackerPoint()
  end
  db.point = SanitizePoint(db.point, ROOT_DEFAULTS.display.point)

  db.iconCount = Clamp(tonumber(db.iconCount) or ROOT_DEFAULTS.display.iconCount, C.MIN_ICON_COUNT or 4, C.MAX_ICON_COUNT or 8)
  db.scale = Clamp(tonumber(db.scale) or ROOT_DEFAULTS.display.scale, 0.70, 1.80)
  db.iconGap = Clamp(tonumber(db.iconGap) or ROOT_DEFAULTS.display.iconGap, 0, 5)
  db.layout = VALID_LAYOUT[tostring(db.layout)] and tostring(db.layout) or ROOT_DEFAULTS.display.layout
  db.scrollDirection = VALID_SCROLL_DIR[tostring(db.scrollDirection)] and tostring(db.scrollDirection) or ROOT_DEFAULTS.display.scrollDirection
  db.border = not not db.border
  db.borderThickness = Clamp(tonumber(db.borderThickness) or ROOT_DEFAULTS.display.borderThickness, 0, 5)
  if db.border == false then
    db.borderThickness = 0
  end

  db.showWhen = VALID_SHOW[tostring(db.showWhen)] and tostring(db.showWhen) or ROOT_DEFAULTS.general.showWhen

  db.seqFont = type(db.seqFont) == "string" and db.seqFont or (addon.DEFAULT_SEQ_FONT or ROOT_DEFAULTS.fonts.sequence.face)
  db.modFont = type(db.modFont) == "string" and db.modFont or (addon.DEFAULT_MOD_FONT or ROOT_DEFAULTS.fonts.modifiers.face)
  db.keybindFont = type(db.keybindFont) == "string" and db.keybindFont or db.modFont
  db.seqFontSize = Clamp(tonumber(db.seqFontSize) or ROOT_DEFAULTS.fonts.sequence.size, 8, 24)
  db.modFontSize = Clamp(tonumber(db.modFontSize) or ROOT_DEFAULTS.fonts.modifiers.size, 6, 20)
  db.keybindFontSize = Clamp(tonumber(db.keybindFontSize) or db.modFontSize, 6, 20)

  local shape = tostring(db.pressedIndicatorShape or ROOT_DEFAULTS.display.pressedIndicator.shape)
  db.pressedIndicatorShape = IsValidPressedShape(shape) and shape or ROOT_DEFAULTS.display.pressedIndicator.shape
  db.pressedIndicatorSize = Clamp(tonumber(db.pressedIndicatorSize) or ROOT_DEFAULTS.display.pressedIndicator.size, 4, 24)
  db.performanceMode = not not db.performanceMode
  EnsureAncillaryTables(db)

  if addon and addon.MaybeMigrateLegacyFontsInDB then
    addon:MaybeMigrateLegacyFontsInDB(db)
  end

  db._schemaVersion = 2
end

local function CleanupLegacyFlatKeys(db)
  if type(db) ~= "table" then return end
  for _, key in ipairs(LEGACY_IMPORT_KEYS) do
    db[key] = nil
  end
  db._schemaVersion = nil
end

function SV:MigrateToVersion3(db)
  local fromVersion = tonumber(db._schemaVersion) or tonumber(db._meta and db._meta.schemaVersion) or 0
  db._meta = db._meta or {}
  if not db._meta.migratedFrom or db._meta.migratedFrom == 0 then
    db._meta.migratedFrom = fromVersion
  end
  self:SyncLegacyMirrorToCanonical(db)
  CleanupLegacyFlatKeys(db)
  NormalizeCanonical(db)
  db._meta.schemaVersion = 3
  db._meta.lastAddonVersion = self.ADDON_VERSION
end

function SV:RunMigrations(db)
  if (self.SCHEMA_VERSION or 0) > MAX_IMPLEMENTED_MIGRATION then
    local msg = "GSE_Tracker: SCHEMA_VERSION=" .. tostring(self.SCHEMA_VERSION)
      .. " but the highest implemented migration is " .. MAX_IMPLEMENTED_MIGRATION
      .. ". Add the missing MigrateToVersion function before shipping."
    local chatFrame = rawget(_G, "DEFAULT_CHAT_FRAME")
    if chatFrame and chatFrame.AddMessage then
      chatFrame:AddMessage("|cFFFF4444" .. msg .. "|r")
    elseif print then
      print(msg)
    end
  end

  local current = tonumber(db._meta and db._meta.schemaVersion) or tonumber(db._schemaVersion) or 0
  if current < 1 then
    self:MigrateToVersion1(db)
    current = tonumber(db._schemaVersion) or 1
  end
  if current < 2 then
    self:MigrateToVersion2(db)
    current = tonumber(db._schemaVersion) or 2
  end
  if current < 3 then
    self:MigrateToVersion3(db)
  end
end

local function FinalizeDatabase(self, db, mergeDefaults, importLegacy)
  if mergeDefaults then
    MergeMissing(db, ROOT_DEFAULTS)
  end
  if importLegacy then
    self:SyncLegacyMirrorToCanonical(db)
  end
  -- Prune the legacy flat keys for EVERYONE (not only on import). Once the canonical
  -- sections exist these are dead mirrors; leaving them is a landmine -- a future
  -- SCHEMA_VERSION bump would flip ShouldImportLegacyFlat true again and re-apply the
  -- STALE flat values OVER the user's current settings (data loss). Runs AFTER the sync
  -- above so an old-schema import still captures them first. Safe on fresh/reset DBs
  -- (they carry no legacy flat keys, so this removes nothing).
  CleanupLegacyFlatKeys(db)
  NormalizeCanonical(db)
  db._meta.schemaVersion = self.SCHEMA_VERSION
  db._meta.lastAddonVersion = self.ADDON_VERSION

  -- One-time: the keybindText element ("F1" keybind readout) shipped enabled-by-default
  -- in older versions. It is now OFF by default, so flip any existing DB that still
  -- carries the old default to OFF. Sentinel-guarded: runs exactly once, so a user who
  -- later re-enables the keybind in settings keeps it. Fresh installs have no keybindText
  -- element table yet, so this is a no-op for them (they get the new false default).
  if not db._meta.keybindDefaultOffApplied then
    db._meta.keybindDefaultOffApplied = true
    local elements = db.layout and db.layout.elements
    if elements and type(elements.keybindText) == "table" then
      elements.keybindText.enabled = false
    end
  end

  return db
end

function SV:EnsureDB()
  local db = self:GetDB()
  self:RunMigrations(db)
  return FinalizeDatabase(self, db, true, ShouldImportLegacyFlat(db))
end

function SV:FlushRuntimeToCanonical()
  local db = self:GetDB()
  return FinalizeDatabase(self, db, false, false)
end

function SV:ResetToDefaults(preserve)
  -- Reset the ACTIVE store only (account or per-character), and keep the
  -- account-wide flag (it lives in the account store) so the mode is preserved.
  local activeName = self:IsAccountWide() and self.DB_NAME or self.CHAR_DB_NAME
  local old = _G[activeName] or {}
  local newDB = self:CopyDefaults()

  if preserve and preserve.colors and type(old.colors) == "table" then
    newDB.colors = DeepCopy(old.colors)
  end
  if activeName == self.DB_NAME then
    newDB.accountWide = old.accountWide
  else
    newDB._gseSeeded = true
  end

  _G[activeName] = FinalizeDatabase(self, newDB, false, false)
  return _G[activeName]
end

function SV:GetSchemaVersion()
  local db = self:GetDB() or {}
  return tonumber((db._meta and db._meta.schemaVersion) or db._schemaVersion) or 0
end
