local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local uiShared = addon._ui or {}

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
    if addon.RefreshPlayerTracker then addon:RefreshPlayerTracker()
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
    if addon.RefreshPlayerTracker then addon:RefreshPlayerTracker()
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
    addon:SetSequenceText("")
    -- Clear active sequence state so ApplyVisibility does not
    -- re-resolve stale text from the GSE bridge.
    addon._activeSeqKey = nil
    addon._activeButtonName = nil
    addon._gseActive = false
    addon:ApplyVisibility()
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.RefreshPlayerTracker then addon:RefreshPlayerTracker()
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
    if addon.RefreshPlayerTracker then addon:RefreshPlayerTracker()
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
