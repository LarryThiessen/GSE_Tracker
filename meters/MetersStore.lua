-- ============================================================================
-- GSE: Tracker -- MetersStore.lua
--
-- Makes the ported Meters engine save into GSE_Tracker's OWN store instead of a
-- separate MetersSavedVars global, so all settings live in the same saved file and
-- follow the same Account Wide / per-character choice as the rest of the tracker.
--
-- The engine reads/writes the global `MetersSavedVars` (and every module does
-- `MetersSavedVars = MetersSavedVars or {}`), so we point that global at the active
-- store's `Meters` sub-table BEFORE any engine file loads. Because SetAccountWide
-- migrates the whole store (including `Meters`) between the account and per-character
-- DBs, the meters data follows the toggle automatically; we just re-point the global
-- afterwards so the live engine sees the now-active table.
--
-- MUST load first in the Meters TOC block (before Details.lua et al.).
-- ============================================================================

local ADDON_NAME, ns = ...
local SV = ns and ns.Utils and ns.Utils.SV

-- One-time migration from the pre-rename names: the sub-table key `myMeters` -> `Meters`,
-- the field `.myMarker` -> `.Marker`, and the value "MyAHLight" -> "AHLight". Run on
-- BOTH the account and per-character stores so data survives regardless of the toggle.
local function MigrateLegacyMeters(store)
  if type(store) ~= "table" then return end
  local legacy = store.myMeters
  if type(legacy) == "table" and next(legacy) ~= nil then
    store.Meters = store.Meters or {}
    if next(store.Meters) == nil then
      for k, v in pairs(legacy) do store.Meters[k] = v end
    end
    store.myMeters = nil
  end
  local m = store.Meters
  if type(m) == "table" then
    if m.Marker == nil and m.myMarker ~= nil then m.Marker = m.myMarker end
    m.myMarker = nil
    if m.Marker == "MyAHLight" then m.Marker = "AHLight" end
  end
end

-- NOTE: at FILE SCOPE the addon's SavedVariables are NOT loaded yet, so the two
-- stores are still nil/empty here and these calls are no-ops. The real migration
-- happens in the ADDON_LOADED handler below, once the saved tables exist.
MigrateLegacyMeters(_G.GSETrackerDB)
MigrateLegacyMeters(_G.GSETrackerCharDB)

local function RepointMetersStore()
  local store = SV and SV.GetDB and SV:GetDB()
  if type(store) == "table" then
    if type(store.Meters) ~= "table" then store.Meters = {} end
    _G.MetersSavedVars = store.Meters
  else
    -- Fallback: SV not ready -- keep a plain table so the engine still loads.
    _G.MetersSavedVars = _G.MetersSavedVars or {}
  end
end

-- File-scope repoint: SavedVariables are not loaded yet, so this only aliases a
-- temporary placeholder table so the engine files (which do
-- `MetersSavedVars = MetersSavedVars or {}` at their own file scope) have a table to
-- start from. It is re-pointed at the REAL saved store in the ADDON_LOADED handler.
RepointMetersStore()

-- CRITICAL: WoW loads this addon's SavedVariables AFTER all its Lua files have run,
-- so the file-scope RepointMetersStore() above aliased MetersSavedVars to a throwaway
-- table. Once SavedVariables are loaded (ADDON_LOADED), GSETrackerDB/CharDB hold the
-- real data, so we migrate + re-point again here. Without this, MetersSavedVars stays
-- aliased to the discarded placeholder and meters settings (e.g. the Details window
-- position) never load and never save. The engine reads MetersSavedVars by name and
-- Details re-inits its cache on PLAYER_ENTERING_WORLD (fired after this), so simply
-- re-pointing the global is enough for the saved values to take effect.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedName)
  if loadedName ~= ADDON_NAME then return end
  self:UnregisterEvent("ADDON_LOADED")
  MigrateLegacyMeters(_G.GSETrackerDB)
  MigrateLegacyMeters(_G.GSETrackerCharDB)
  RepointMetersStore()

  -- One-time: the static center-marker modes (Bullseye/Class/Specialization) now render
  -- through the unified GSE combat-marker symbol (one display rule), NOT the Meters
  -- engine. Migrate any such saved mode onto the combat-marker symbol and clear it here
  -- so the meters engine stops drawing it (which caused a second, differently-positioned
  -- marker). AHLight stays on the meters engine. Idempotent.
  local sv = _G.MetersSavedVars
  if type(sv) == "table" then
    local m = sv.Marker
    if m == "Bullseye" or m == "Class" or m == "Specialization" or m == "AHLight" then
      -- Bullseye is now a media image; Class/Spec/AHLight keep their values.
      -- Bullseye.png was replaced by the crosshair set; map a legacy Bullseye to one.
      local mapped = (m == "Bullseye") and "Crosshairs001.png" or m
      if ns and ns.SetCombatMarkerSymbol then ns:SetCombatMarkerSymbol(mapped) end
      sv.Marker = "None"
    end
  end

  -- Recenter: markers used to default to 120px above centre, which read as "too low"
  -- vs the on-character centre. If still on that old default, move to dead-centre (0,0)
  -- so every marker sits on the character. Customised offsets are left untouched.
  if ns and ns.GetCombatMarkerOffset and ns.SetCombatMarkerOffset then
    local x, y = ns:GetCombatMarkerOffset()
    if (tonumber(x) or 0) == 0 and (tonumber(y) or 0) == 120 then
      ns:SetCombatMarkerOffset(0, 0)
    end
  end
end)

-- Re-point when the user flips Account Wide <-> per-character. SetAccountWide has
-- already copied `Meters` into the now-active store by the time this runs, so the
-- alias just needs to follow it -- no /reload required.
if SV and SV.SetAccountWide and not SV._MetersStoreWrapped then
  SV._MetersStoreWrapped = true
  local originalSetAccountWide = SV.SetAccountWide
  function SV:SetAccountWide(enabled)
    originalSetAccountWide(self, enabled)
    RepointMetersStore()
  end
end
