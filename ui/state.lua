local _, ns = ...
local addon = ns
local UI = ns.UI
local uiShared = addon._ui or {}
local ensureDatabase = uiShared.EnsureDB
local clampValue = uiShared.Clamp
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}

local function GetRootDefaults()
  return (uiShared.GetRootDefaults and uiShared.GetRootDefaults()) or {}
end


function UI:GetIconGap()
  if ns.Utils and ns.Utils.GetIconGap then
    return ns.Utils:GetIconGap()
  end
  ensureDatabase()
  local display = GetRootDefaults().display or {}
  return clampValue(tonumber(display.iconGap) or 3, 0, 5)
end

function UI:GetIconCount()
  if ns.Utils and ns.Utils.GetIconCount then
    return ns.Utils:GetIconCount()
  end
  ensureDatabase()
  local display = GetRootDefaults().display or {}
  return clampValue(tonumber(display.iconCount) or 4, C.MIN_ICON_COUNT or 4, C.MAX_ICON_COUNT or 8)
end

function UI:GetShowWhen()
  if ns.Utils and ns.Utils.GetShowWhen then
    return ns.Utils:GetShowWhen()
  end
  ensureDatabase()
  local general = GetRootDefaults().general or {}
  return tostring(general.showWhen or (C.MODE_ALWAYS or "Always"))
end

function UI:GetStrata()
  -- Use the ACTIVE store (account or per-character), not the raw account global.
  local db = (ensureDatabase and ensureDatabase()) or _G.GSETrackerDB or {}
  local general = type(db.general) == "table" and db.general or {}
  local strata = tostring(general.strata or (GetRootDefaults().general or {}).strata or (C.DEFAULT_COMBAT_TRACKER_STRATA or C.STRATA_MEDIUM or "MEDIUM"))
  local valid = C.VALID_FRAME_STRATA or { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

  if valid[strata] then
    return strata
  end

  return C.DEFAULT_COMBAT_TRACKER_STRATA or C.STRATA_MEDIUM or "MEDIUM"
end

function UI:GetDesiredScale()
  if ns.Utils and ns.Utils.GetScale then
    return ns.Utils:GetScale()
  end
  ensureDatabase()
  local display = GetRootDefaults().display or {}
  return clampValue(tonumber(display.scale) or 1, 0.70, 1.80)
end

function UI:InitUI()
  ensureDatabase()
  if self.EnsureMinimapButton then
    self:EnsureMinimapButton()
  end
  if self.ui then return end
  if self.BuildMainFrame then
    self:BuildMainFrame()
  end
  if self.EnsureCenterMarker then
    self:EnsureCenterMarker()
    self:RefreshCenterMarker()
  elseif self.EnsureCombatMarker then
    self:EnsureCombatMarker()
    self:RefreshCombatMarker()
  end
  if self.EnsureAssistedHighlight then
    self:EnsureAssistedHighlight()
    self:RefreshAssistedHighlight(true)
  end
end
