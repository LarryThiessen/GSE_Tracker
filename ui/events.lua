local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local uiShared = addon._ui or {}

local NAME_FADE = 3       -- seconds for the name/keybind fade-out ramp
local NAME_IDLE_HOLD = 3  -- seconds of no casting (OUT of combat) before the names fade

-- Smoothly fade the top-row names + keybind out, then clear. Shared by the post-combat fade AND the
-- out-of-combat idle fade. Token-guarded: a fresh cast (NoteNameActivity) bumps _nameActivityToken, so a
-- pending clear from an older fade is skipped and the re-shown name isn't wiped mid-cast.
function UI:FadeNamesOut()
  local ui = addon.ui
  if not ui then return end
  local token = ui._nameActivityToken or 0
  ui._namesFading = true
  uiShared.SmoothFadeOut(ui.nameText, NAME_FADE)
  uiShared.SmoothFadeOut(ui.nameText2, NAME_FADE)
  uiShared.SmoothFadeOut(ui.keybindText, NAME_FADE)
  if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(NAME_FADE + 0.1, function()
      if (ui._nameActivityToken or 0) ~= token then return end  -- a newer cast superseded this fade
      ui._namesFading = false
      uiShared.CancelFade(ui.nameText); uiShared.CancelFade(ui.nameText2); uiShared.CancelFade(ui.keybindText)
      if not (API.InCombatLockdown and API.InCombatLockdown()) then addon._gseSeqName = nil end
      addon:SetSequenceText("")
      addon:ApplyVisibility()
    end)
  else
    ui._namesFading = false
    addon._gseSeqName = nil
    addon:SetSequenceText("")
  end
end

-- Called on every cast that shows a name. Bumps the activity token (cancels any pending fade-clear) and,
-- OUT of combat, (re)arms the idle timer so the names fade once casting stops. In combat the post-combat
-- PLAYER_REGEN_ENABLED fade owns it, so we don't arm there.
function UI:NoteNameActivity()
  local ui = addon.ui
  if not ui then return end
  ui._nameActivityToken = (ui._nameActivityToken or 0) + 1
  local token = ui._nameActivityToken
  if API.InCombatLockdown and API.InCombatLockdown() then return end
  if not (_G.C_Timer and _G.C_Timer.After) then return end
  _G.C_Timer.After(NAME_IDLE_HOLD, function()
    if (ui._nameActivityToken or 0) ~= token then return end          -- a newer cast rearmed
    if API.InCombatLockdown and API.InCombatLockdown() then return end -- combat owns the fade
    if addon.IsEditModePreviewActive and addon:IsEditModePreviewActive() then return end  -- examples don't fade
    addon:FadeNamesOut()
  end)
end

local function HandleModifierStateChanged(_, _, key, state)
  local ui = addon and addon.ui
  if not ui then return end

  local changed = uiShared.ApplyModifierEvent and uiShared.ApplyModifierEvent(ui, key, state)
  -- Always refresh the combo readout: a side-specific change (e.g. pressing RShift
  -- while LShift is already held) doesn't change the combined state but DOES change
  -- what's displayed. UpdateModifiers itself no-ops when the string is unchanged.
  addon:UpdateModifiers()
  if changed and addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
end

local function HandleCombatEvent(_, event)
  local ui = addon and addon.ui
  if not ui then return end

  if event == "PLAYER_TARGET_CHANGED" then
    addon:ApplyVisibility()
    if addon.RefreshCenterMarker then addon:RefreshCenterMarker()
    elseif addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    -- Assisted highlight self-gates its OnUpdate while hidden (see the IsShown()
    -- early-out in assisted_highlight.lua) and relies on an event-driven refresh to
    -- wake back up when its Show mode (In Combat / Has Harm Target) flips. Without
    -- this call those modes never re-appear after combat/target changes.
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight() end
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    if ui._combatState == true then return end
    ui._combatState = true
    -- A post-combat name fade may still be running from the previous fight; cancel it so the
    -- names snap back to full opacity for the new combat.
    ui._namesFading = false
    uiShared.CancelFade(ui.nameText)
    uiShared.CancelFade(ui.nameText2)
    uiShared.CancelFade(ui.keybindText)
    -- Reset the AH match counters so the % reflects THIS combat (enter -> leave).
    addon._ahCastCount = 0
    addon._ahMatchCount = 0
    addon._ahSbaCastCount = 0
    addon._ahSbaMatchCount = 0
    addon._sbaEventActive = false
    addon._lastCastSbaCounted = false
    addon:RevealPendingSequenceText()
    addon:ApplyVisibility()
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.RefreshCenterMarker then addon:RefreshCenterMarker()
    elseif addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    -- Assisted highlight self-gates its OnUpdate while hidden (see the IsShown()
    -- early-out in assisted_highlight.lua) and relies on an event-driven refresh to
    -- wake back up when its Show mode (In Combat / Has Harm Target) flips. Without
    -- this call those modes never re-appear after combat/target changes.
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight() end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    if ui._combatState == false then return end
    ui._combatState = false
    addon:ClearSpellHistory()
    -- Clear any modifier left "held" by a key-up missed during the fight (heavy macro spam can drop a
    -- key-up), so the MODKEYS readout (e.g. "LCtrl") doesn't linger after combat. Live key queries are
    -- authoritative here (we're not mid key-event); a genuinely-held modifier stays shown.
    if uiShared.ReconcileModifiersFromLive then uiShared.ReconcileModifiersFromLive(ui) end
    if addon.UpdateModifiers then addon:UpdateModifiers(true) end
    -- Smoothly fade the top-row names + keybind out, then clear (shared with the out-of-combat idle fade).
    addon:FadeNamesOut()
    -- Clear active sequence state so ApplyVisibility does not
    -- re-resolve stale text from the GSE bridge.
    addon._activeSeqKey = nil
    addon._activeButtonName = nil
    addon._gseActive = false
    addon:ApplyVisibility()
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.RefreshCenterMarker then addon:RefreshCenterMarker()
    elseif addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    -- Assisted highlight self-gates its OnUpdate while hidden (see the IsShown()
    -- early-out in assisted_highlight.lua) and relies on an event-driven refresh to
    -- wake back up when its Show mode (In Combat / Has Harm Target) flips. Without
    -- this call those modes never re-appear after combat/target changes.
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight() end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    local newCombatState = API.InCombatLockdown() or false
    local combatChanged = (ui._combatState ~= newCombatState)
    local needsTargetVisibilityRefresh = addon.VisibilityDependsOnTarget and addon:VisibilityDependsOnTarget() or false
    ui._combatState = newCombatState
    if uiShared.SyncModifiers then
      local changed = uiShared.SyncModifiers(ui)
      addon:UpdateModifiers(changed)
    end
    -- Once the load settles, reconcile modifier state from live key queries to clear any side
    -- left stuck by a key-up missed during the loading screen (the "LCtrl shows for no reason
    -- on login" case). Live is reliable here -- this isn't a press-event moment.
    if C_Timer and C_Timer.After and uiShared.ReconcileModifiersFromLive then
      C_Timer.After(1.0, function()
        uiShared.ReconcileModifiersFromLive(ui)
        if addon.UpdateModifiers then addon:UpdateModifiers(true) end
      end)
    end
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if combatChanged or ui._lastVisible == nil or needsTargetVisibilityRefresh then
      addon:ApplyVisibility()
    end
    if addon.RefreshCenterMarker then addon:RefreshCenterMarker()
    elseif addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    -- Assisted highlight self-gates its OnUpdate while hidden (see the IsShown()
    -- early-out in assisted_highlight.lua) and relies on an event-driven refresh to
    -- wake back up when its Show mode (In Combat / Has Harm Target) flips. Without
    -- this call those modes never re-appear after combat/target changes.
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight() end
  end
end

function UI:RegisterModifierEvents(ui)
  if not ui then return end

  if not ui.modEvents then
    ui.modEvents = API.CreateFrame("Frame")
  else
    ui.modEvents:UnregisterAllEvents()
  end

  API.SafeRegisterEvent(ui.modEvents, "MODIFIER_STATE_CHANGED")
  ui.modEvents:SetScript("OnEvent", HandleModifierStateChanged)

  if uiShared.SyncModifiers then
    uiShared.SyncModifiers(ui)
  end
  if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
end

function UI:UpdateEventSubscriptions(ui)
  ui = ui or self.ui
  if not (ui and ui.combatEvents) then return end

  local needsTargetEvent = false
  if self.VisibilityDependsOnTarget then
    needsTargetEvent = self:VisibilityDependsOnTarget() and true or false
  end

  if ui._targetEventRegistered ~= needsTargetEvent then
    ui._targetEventRegistered = needsTargetEvent
    if needsTargetEvent then
      API.SafeRegisterEvent(ui.combatEvents, "PLAYER_TARGET_CHANGED")
    else
      ui.combatEvents:UnregisterEvent("PLAYER_TARGET_CHANGED")
    end
  end
end

function UI:RegisterCombatEvents(ui)
  if not ui then return end

  if not ui.combatEvents then
    ui.combatEvents = API.CreateFrame("Frame")
  else
    ui.combatEvents:UnregisterAllEvents()
  end

  API.SafeRegisterEvent(ui.combatEvents, "PLAYER_REGEN_DISABLED")
  API.SafeRegisterEvent(ui.combatEvents, "PLAYER_REGEN_ENABLED")
  API.SafeRegisterEvent(ui.combatEvents, "PLAYER_ENTERING_WORLD")
  self:UpdateEventSubscriptions(ui)

  ui.combatEvents:SetScript("OnEvent", HandleCombatEvent)
end
