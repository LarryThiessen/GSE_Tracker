local _, ns = ...
local addon = ns
local Options = ns.Options
local optionsModule = Options

-- =========================================================================
-- GSE: Tracker -- options-window skin definitions.
--
-- Provides a palette-swap skin system for the settings window so it can be
-- painted in either the in-house dark "Modern" look or a stock-Blizzard
-- "Native" look, and resolves an "Auto" preference that follows GSE's own
-- skin choice when GSE is installed.
--
-- Design / values ported from GSE (Gnome Sequencer Enhanced / Advanced
-- Macros) by Timothy Minahan -- specifically the tri-state skin model in
-- GSE_Utils/Appearance.lua (GSE.GetEffectiveSkinMode -> NATIVE/MODERN/ADDON)
-- and the Modern accent palette in GSE_GUI/NativeUI.lua. No GSE source is
-- executed here; the resolved value is read at runtime via GSE's public
-- GSE.GetEffectiveSkinMode() when present. GSE is all-rights-reserved; this
-- reimplementation lives under GSE: Tracker (MIT). Keep this attribution.
-- =========================================================================

local SKIN_AUTO = "AUTO"
local SKIN_MODERN = "MODERN"
local SKIN_NATIVE = "NATIVE"

optionsModule.SKIN_AUTO = SKIN_AUTO
optionsModule.SKIN_MODERN = SKIN_MODERN
optionsModule.SKIN_NATIVE = SKIN_NATIVE

-- Each palette carries the full set of colour keys consumed by the widget
-- factories in helpers.lua (kept name-for-name with the locals there), plus
-- accent handling used by GetClassColor:
--   useClassAccent = true  -> accent follows the player's class colour
--                             (and GSE's Modern custom colour when present)
--   useClassAccent = false -> accent is the fixed `accent` colour below.
optionsModule.SkinPalettes = {
  -- The Modern values match GSE: Tracker's original hard-coded palette, so
  -- selecting Modern (or running with no GSE installed) keeps the look the
  -- addon has always shipped with.
  [SKIN_MODERN] = {
    BG_DARK = { 0.025, 0.03, 0.035 },
    BG_MEDIUM = { 0.035, 0.04, 0.045 },
    BG_LIGHT = { 0.05, 0.055, 0.06 },
    BG_INPUT = { 0.06, 0.065, 0.07 },
    BG_HOVER = { 0.08, 0.085, 0.09 },
    BORDER_DARK = { 0.06, 0.06, 0.06 },
    BORDER_DEFAULT = { 0.12, 0.12, 0.12 },
    BORDER_LIGHT = { 0.18, 0.18, 0.18 },
    BORDER_HOVER = { 0.25, 0.25, 0.25 },
    BORDER_INPUT = { 0.15, 0.15, 0.15 },
    TEXT_PRIMARY = { 1, 1, 1 },
    TEXT_SECONDARY = { 0.7, 0.7, 0.7 },
    TEXT_MUTED = { 0.5, 0.5, 0.5 },
    TEXT_DISABLED = { 0.35, 0.35, 0.35 },
    CONTROL_TRACK = { 0.15, 0.15, 0.15 },
    CONTROL_TRACK_OFF = { 0.2, 0.2, 0.2 },
    SCROLL_THUMB = { 0.45, 0.45, 0.45 },
    SCROLL_THUMB_HOVER = { 0.55, 0.55, 0.55 },
    FALLBACK_ACCENT = { 0.45, 0.85, 0.65 },
    useClassAccent = true,
    accent = { 0.45, 0.85, 0.65 },
  },
  -- The Native values approximate a stock Blizzard panel: lighter neutral
  -- greys, a warm tan/gold frame border, and a gold accent instead of class
  -- colour. (GSE Tracker's widgets are fully custom WHITE8x8 frames, so a
  -- neutral palette is the practical equivalent of GSE's no-op Native skin.)
  [SKIN_NATIVE] = {
    BG_DARK = { 0.10, 0.10, 0.11 },
    BG_MEDIUM = { 0.13, 0.13, 0.14 },
    BG_LIGHT = { 0.16, 0.16, 0.17 },
    BG_INPUT = { 0.18, 0.18, 0.19 },
    BG_HOVER = { 0.24, 0.24, 0.25 },
    BORDER_DARK = { 0.20, 0.20, 0.20 },
    BORDER_DEFAULT = { 0.30, 0.28, 0.24 },
    BORDER_LIGHT = { 0.45, 0.40, 0.30 },
    BORDER_HOVER = { 0.55, 0.50, 0.38 },
    BORDER_INPUT = { 0.30, 0.30, 0.30 },
    TEXT_PRIMARY = { 1, 1, 1 },
    TEXT_SECONDARY = { 0.78, 0.78, 0.78 },
    TEXT_MUTED = { 0.55, 0.55, 0.55 },
    TEXT_DISABLED = { 0.40, 0.40, 0.40 },
    CONTROL_TRACK = { 0.25, 0.25, 0.25 },
    CONTROL_TRACK_OFF = { 0.30, 0.30, 0.30 },
    SCROLL_THUMB = { 0.50, 0.50, 0.50 },
    SCROLL_THUMB_HOVER = { 0.62, 0.62, 0.62 },
    FALLBACK_ACCENT = { 1.00, 0.82, 0.00 },
    useClassAccent = false,
    accent = { 1.00, 0.82, 0.00 },
  },
}

-- ── Skinner detection: COPIED from the GSE addon ──────────────────────────────
-- Logic ported from GSE_Utils/Appearance.lua (GetInstalledSkinProviderName,
-- GetEffectiveSkinMode). GSE is all-rights-reserved; ported into GSE: Tracker
-- (MIT) per the owner's authorization. No GSE code runs at runtime and the GSE
-- addon is NOT referenced (the only GSE link is the bridge).

-- True when an external UI skin provider GSE recognises is installed (ElvUI or
-- EllesmereUI). Mirrors GSE.GetInstalledSkinProviderName -- detects the addons
-- directly, without calling into GSE.
function optionsModule.HasInstalledSkinProvider()
  if type(_G.ElvUI) == "table" and type(_G.ElvUI[1]) == "table" then
    return true
  end
  local IsAddOnLoaded = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
  if IsAddOnLoaded then
    for _, name in ipairs({ "EllesmereUIActionBars", "EllesmereUI" }) do
      local ok, loaded = pcall(IsAddOnLoaded, name)
      if ok and loaded then return true end
    end
  end
  return false
end

-- Resolve the stored preference (AUTO/MODERN/NATIVE) to a concrete skin
-- (MODERN/NATIVE), standalone. AUTO mirrors GSE's GetEffectiveSkinMode: adopt the
-- skinned UI when a provider is installed, else Blizzard-native.
function optionsModule.GetSkinMode()
  local pref = (addon.GetSkin and addon:GetSkin()) or SKIN_AUTO
  if pref == SKIN_MODERN or pref == SKIN_NATIVE then
    return pref
  end
  if optionsModule.HasInstalledSkinProvider() then
    return SKIN_MODERN
  end
  return SKIN_NATIVE
end

-- Returns the active palette table (never nil).
function optionsModule.GetActiveSkin()
  local mode = optionsModule.GetSkinMode()
  return optionsModule.SkinPalettes[mode] or optionsModule.SkinPalettes[SKIN_MODERN]
end

-- True when the resolved skin is Native. The widget factories use this to skip
-- their custom WHITE8x8 repaint and let genuine Blizzard templates render.
function optionsModule.IsNativeSkin()
  return optionsModule.GetSkinMode() == SKIN_NATIVE
end
