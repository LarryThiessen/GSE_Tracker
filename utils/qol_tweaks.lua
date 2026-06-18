-- ============================================================================
-- GSE: Tracker -- utils\qol_tweaks.lua
--
-- Small, self-contained Quality-of-Life game tweaks toggled from the QoL tab:
--   * Mute the spell-fizzle (cast-failure) sounds.
--   * Hide the red UIErrorsFrame error text.
--
-- Both use stock Blizzard APIs (MuteSoundFile / UnmuteSoundFile, and the error
-- frame's own event registration), so they are fully reversible and touch nothing
-- else. State is read from the saved DB (ui\db.lua) and applied on login.
-- ============================================================================

local _, ns = ...
local addon = ns
local API = (ns.Utils and ns.Utils.API) or {}

-- Spell-fizzle sound FileDataIDs, one per magic school (Holy / Fire / Nature /
-- Frost / Shadow). These are public WoW asset IDs; muting them silences only the
-- "fizzle" sound a failed cast plays.
local FIZZLE_SOUND_IDS = { 569772, 569773, 569774, 569775, 569776 }

-- ─── Mute fizzle sounds ──────────────────────────────────────────────────────
local fizzleMuted = false
function addon:ApplyMuteFizzles(enabled)
  enabled = enabled and true or false
  if enabled == fizzleMuted then return end
  -- MuteSoundFile/UnmuteSoundFile take a FileDataID and last for the session
  -- (cleared on reload/relog, which is why we re-apply on login below).
  local apply = enabled and _G.MuteSoundFile or _G.UnmuteSoundFile
  if not apply then return end
  for _, id in ipairs(FIZZLE_SOUND_IDS) do
    pcall(apply, id)
  end
  fizzleMuted = enabled
end

-- ─── Hide error messages ─────────────────────────────────────────────────────
-- Stop the red error frame from listening for the error event (re-register to
-- restore). Leaves yellow info/quest messages (UI_INFO_MESSAGE) alone.
function addon:ApplyHideErrors(enabled)
  local ef = _G.UIErrorsFrame
  if not (ef and ef.RegisterEvent and ef.UnregisterEvent) then return end
  if enabled then
    ef:UnregisterEvent("UI_ERROR_MESSAGE")
  else
    ef:RegisterEvent("UI_ERROR_MESSAGE")
  end
end

-- ─── Apply saved state on login ──────────────────────────────────────────────
local loader = (API.CreateFrame and API.CreateFrame("Frame")) or CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  if addon.GetMuteFizzles then addon:ApplyMuteFizzles(addon:GetMuteFizzles()) end
  if addon.GetHideErrors then addon:ApplyHideErrors(addon:GetHideErrors()) end
end)
