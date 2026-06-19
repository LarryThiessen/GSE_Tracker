local _, ns = ...
local addon = ns
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local Options = ns.Options
local optionsModule = Options

local ensureDatabase = optionsModule.EnsureDB
local getElementXY = optionsModule.GetElementXY
local layoutSettingsWindow = optionsModule.LayoutSettingsWindow
local setSliderBoxValue = optionsModule.SetSliderBoxValue
local setDropdownValue = optionsModule.SetDD
local styleWindowBorder = optionsModule.StyleWindowBorder

local SHOW_TEXT = {
  Always = "Always",
  HasTarget = "Has Harm Target",
  InCombat = "In Combat",
  Never = "Never",
}

local SHAPE_TEXT = {
  square = "Square",
  circle = "Circle",
  dot = "Dot",
  cross = "Cross",
}

local function IsCenterMarkerEffect(effect)
  return effect == "centerMarker" or effect == "combatMarker"
end

local function RefreshCenterMarker()
  if addon.RefreshCenterMarker then
    addon:RefreshCenterMarker()
  elseif addon.RefreshCombatMarker then
    addon:RefreshCombatMarker()
  end
end

local function SyncSlider(slider, value)
  if not slider then return end
  slider:SetValue(value)
  setSliderBoxValue(slider, value)
end

local function GetNormalizedFont(dbKey, fallback)
  if dbKey == "seqFont" then return addon:GetSeqFontName() end
  if dbKey == "modFont" then return addon:GetModFontName() end
  if dbKey == "keybindFont" then return addon:GetKeybindFontName() end
  return fallback
end

local function RefreshRuntimeSequenceAndKeybind()
  local ui = addon and addon.ui
  if not ui then return end
  local seqKey = ui._lastSeqKey or addon._activeSeqKey
  local seqText = ui._lastSeqText

  if (type(seqText) ~= "string" or seqText == "") and seqKey and addon.GetActiveSequenceDisplayText then
    local liveSeqText = addon:GetActiveSequenceDisplayText(seqKey)
    if type(liveSeqText) == "string" and liveSeqText ~= "" then
      seqText = liveSeqText
    end
  end

  if seqText ~= nil and addon.SetSequenceText then
    addon:SetSequenceText(seqText, nil, nil, seqKey)
  end

  if addon.SetKeybindText then
    local keybindText = ui._lastKeybindText
    if addon.GetActiveSequenceBindingText and seqKey then
      local liveKeybindText = addon:GetActiveSequenceBindingText(seqKey)
      if type(liveKeybindText) == "string" then
        keybindText = liveKeybindText
      end
    end
    addon:SetKeybindText(keybindText)
  end
end

function optionsModule.ApplyTargetedRefresh(effect, elementName, changeKind)
  if not addon then return end

  if effect == "visibility" then
    if addon.ApplyVisibility then addon:ApplyVisibility() end
  elseif effect == "indicator" then
    if addon.RefreshPressedIndicator then
      addon:RefreshPressedIndicator(true)
    elseif addon.ApplyPressedIndicatorStyle and addon.ui and addon.ui.pressedIndicator then
      addon:ApplyPressedIndicatorStyle(addon.ui.pressedIndicator)
    end
  elseif effect == "border" then
    if addon.ApplyBorderThickness then addon:ApplyBorderThickness() end
    if addon._editingOptions and addon.RefreshEditingPreviewState then addon:RefreshEditingPreviewState() end
  elseif effect == "iconLayout" then
    if addon.RebuildIcons then addon:RebuildIcons(true) end
    if addon._editingOptions and addon.RefreshEditingPreviewState then addon:RefreshEditingPreviewState() end
  elseif effect == "scale" then
    if addon.ApplyScale then addon:ApplyScale() end
    if addon.ApplyActionTrackerPosition then addon:ApplyActionTrackerPosition() end
    if addon._editingOptions and addon.RefreshEditingPreviewState then addon:RefreshEditingPreviewState() end
  elseif effect == "font" then
    if addon.ApplyFontFaces then addon:ApplyFontFaces() end
    if addon.ApplyAssistedHighlightFont then addon:ApplyAssistedHighlightFont() end
    if addon.ApplyAssistedHighlightKeybindPosition then addon:ApplyAssistedHighlightKeybindPosition() end
    if addon._editingOptions and addon.RefreshEditingPreviewState then addon:RefreshEditingPreviewState() end
  elseif effect == "actionTrackerPosition" then
    if addon.ApplyActionTrackerPosition then addon:ApplyActionTrackerPosition() end
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.UpdateActionTrackerMoveMarker then addon:UpdateActionTrackerMoveMarker() end
  elseif effect == "lock" then
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.UpdateActionTrackerMoveMarker then addon:UpdateActionTrackerMoveMarker() end
    RefreshCenterMarker()
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
  elseif effect == "performanceMode" then
    if addon.ui and addon.SetIconRow then
      addon:SetIconRow(addon._recentIcons or {})
    elseif addon.RebuildIcons then
      addon:RebuildIcons(true)
    end
    if addon._editingOptions and addon.RefreshEditingPreviewState then addon:RefreshEditingPreviewState() end
  elseif IsCenterMarkerEffect(effect) then
    if addon.UpdateEventSubscriptions then addon:UpdateEventSubscriptions() end
    RefreshCenterMarker()
  elseif effect == "assistedHighlight" then
    if changeKind == "layout" then
      if addon.ApplyAssistedHighlightLayout then
        addon:ApplyAssistedHighlightLayout()
      else
        if addon.ApplyAssistedHighlightPosition then addon:ApplyAssistedHighlightPosition() end
        if addon.ApplyAssistedHighlightKeybindPosition then addon:ApplyAssistedHighlightKeybindPosition() end
      end
    elseif changeKind == "font" then
      if addon.ApplyAssistedHighlightFont then addon:ApplyAssistedHighlightFont() end
      if addon.ApplyAssistedHighlightKeybindPosition then addon:ApplyAssistedHighlightKeybindPosition() end
    elseif changeKind == "size" then
      if addon.ApplyAssistedHighlightSize then addon:ApplyAssistedHighlightSize() end
    elseif changeKind == "alpha" then
      if addon.ApplyAssistedHighlightAlpha then addon:ApplyAssistedHighlightAlpha() end
    elseif changeKind == "border" then
      if addon.ApplyAssistedHighlightBorder then addon:ApplyAssistedHighlightBorder() end
    else
      if addon.ApplyAssistedHighlightSize then addon:ApplyAssistedHighlightSize() end
      -- The ShowWhen mode may have just changed to/from "Has Harm Target"; re-evaluate
      -- whether PLAYER_TARGET_CHANGED needs to be (un)registered so the highlight tracks
      -- target changes live even when no other area uses that mode (mirrors the
      -- player-tracker effect path above).
      if addon.UpdateEventSubscriptions then addon:UpdateEventSubscriptions() end
      if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
    end
  elseif effect == "element" then
    local layoutOnly = (changeKind == "layout")

    if changeKind == "font" and addon.ApplyFontFaces then
      addon:ApplyFontFaces()
      if elementName == "keybindText" then
        if addon.ApplyAssistedHighlightFont then addon:ApplyAssistedHighlightFont() end
        if addon.ApplyAssistedHighlightKeybindPosition then addon:ApplyAssistedHighlightKeybindPosition() end
      end
    end

    if elementName and addon.ApplyElementPosition then
      addon:ApplyElementPosition(elementName)
    elseif addon.ApplyAllElementPositions then
      addon:ApplyAllElementPositions()
    end

    if (not layoutOnly) and addon._editingOptions and addon.RefreshEditingPreviewState and elementName ~= "pressedIndicator" then
      addon:RefreshEditingPreviewState()
    end

    if not layoutOnly then
      if addon.ApplyVisibility then addon:ApplyVisibility() end
      if addon.RevealPendingSequenceText then addon:RevealPendingSequenceText() end
      RefreshRuntimeSequenceAndKeybind()
      if addon.RefreshPressedIndicator then addon:RefreshPressedIndicator(true) end
    elseif elementName == "pressedIndicator" and addon.RefreshPressedIndicator then
      addon:RefreshPressedIndicator(true)
    end
  elseif effect == "full" then
    if addon.ApplyFontFaces then addon:ApplyFontFaces() end
    if addon.ApplyScale then addon:ApplyScale() end
    if addon.ApplyActionTrackerPosition then addon:ApplyActionTrackerPosition() end
    if addon.ApplyAllElementPositions then addon:ApplyAllElementPositions() end
    if addon.ApplyVisibility then addon:ApplyVisibility() end
    if addon.RevealPendingSequenceText then addon:RevealPendingSequenceText() end
    RefreshRuntimeSequenceAndKeybind()
    if addon.RefreshPressedIndicator then addon:RefreshPressedIndicator(true) end
    RefreshCenterMarker()
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
  end

  optionsModule.RefreshLiveActionTrackerForOptions(effect, elementName, changeKind)
end

function optionsModule.BuildSettingsRefresh(ctx)
  local frame = ctx.frame
  local sectionsByTab = ctx.sectionsByTab or {}
  local controls = ctx.controls or {}
  local SetActionTrackerSliderEnabled = ctx.SetActionTrackerSliderEnabled
  local SetRefreshing = ctx.SetRefreshing

  return function()
    ensureDatabase()
    SetRefreshing(true)

    local selectedTab = frame.GetSelectedTopTab and frame:GetSelectedTopTab() or "ActionTracker"
    local layoutSig = table.concat({
      tostring(math.floor((frame.GetWidth and frame:GetWidth()) or 0)),
      tostring(math.floor((frame.GetHeight and frame:GetHeight()) or 0)),
      tostring(selectedTab),
    }, "|")
    if frame._gsetrackerSettingsLayoutSig ~= layoutSig then
      frame._gsetrackerSettingsLayoutSig = layoutSig
      local sections = sectionsByTab[selectedTab] or sectionsByTab.ActionTracker or {}
      local content = (frame.tabCanvases and frame.tabCanvases[selectedTab]) or (frame.tabContents and frame.tabContents[selectedTab])
      if content then
        layoutSettingsWindow(frame, content, sections, selectedTab)
      end
    end

    local seqX, seqY, seqEnabled = getElementXY("sequenceText")
    local modX, modY, modEnabled = getElementXY("modifiersText")
    local keyX, keyY, keyEnabled = getElementXY("keybindText")
    local pressX, pressY, pressEnabled = getElementXY("pressedIndicator")

    if controls.cbEnable then
      controls.cbEnable:SetChecked(addon:IsEnabled())
    end
    if controls.cbLock then
      controls.cbLock:SetChecked(addon:IsLocked())
    end
    if controls.cbCombatMarkerLock then
      controls.cbCombatMarkerLock:SetChecked(addon.GetCombatMarkerLocked and addon:GetCombatMarkerLocked() or false)
    end
    controls.cbBorder:SetChecked(addon:IsBorderEnabled())
    if controls.cbActionTrackerUseClassColor then
      controls.cbActionTrackerUseClassColor:SetChecked(addon:GetActionTrackerUseClassColor())
    end
    if controls.cbPerformance then
      controls.cbPerformance:SetChecked(addon:IsPerformanceModeEnabled())
    end

    local actionTrackerX, actionTrackerY = addon:GetActionTrackerOffset()
    SyncSlider(controls.sActionTrackerX, actionTrackerX)
    SyncSlider(controls.sActionTrackerY, actionTrackerY)
    SetActionTrackerSliderEnabled(not (addon:IsLocked()))

    local scale = addon:GetDesiredScale()
    controls.sScale:SetValue(scale)
    if controls.sScale.inputBox and not controls.sScale.inputBox:HasFocus() then
      controls.sScale.inputBox:SetText(string.format("%.2f", scale))
    end

    setDropdownValue(controls.ddShowWhen, addon:GetShowWhen(), SHOW_TEXT[addon:GetShowWhen() or (C.MODE_ALWAYS or "Always")] or tostring(addon:GetShowWhen() or (C.MODE_ALWAYS or "Always")))
    setDropdownValue(controls.ddIndicatorShape, addon:GetPressedIndicatorShape(), SHAPE_TEXT[addon:GetPressedIndicatorShape()] or "Dot")

    SyncSlider(controls.sIconCount, addon:GetIconCount())
    SyncSlider(controls.sIconGap, addon:GetIconGap())
    SyncSlider(controls.sBorderThickness, addon:GetBorderThickness())
    if controls.btnActionTrackerBorderColor and frame.UpdateActionTrackerBorderColorButton then
      local hr, hg, hb = addon:GetActionTrackerBorderColor()
      frame:UpdateActionTrackerBorderColorButton(hr, hg, hb)
      local enabled = addon:IsEnabled() and (not addon:GetActionTrackerUseClassColor())
      controls.btnActionTrackerBorderColor:SetEnabled(enabled)
      controls.btnActionTrackerBorderColor:SetAlpha(enabled and 1 or 0.5)
    end

    local seqFont = GetNormalizedFont("seqFont", addon.DEFAULT_SEQ_FONT)
    local modFont = GetNormalizedFont("modFont", addon.DEFAULT_MOD_FONT)
    local keybindFont = GetNormalizedFont("keybindFont", addon:GetModFontName())
    setDropdownValue(controls.ddSeqFont, seqFont, seqFont)
    setDropdownValue(controls.ddModsFont, modFont, modFont)
    setDropdownValue(controls.ddKeybindFont, keybindFont, keybindFont)

    controls.cbSeqEnabled:SetChecked(seqEnabled ~= false)
    controls.cbModsEnabled:SetChecked(modEnabled ~= false)
    controls.cbKeybindEnabled:SetChecked(keyEnabled and true or false)
    controls.cbPressedEnabled:SetChecked(pressEnabled and true or false)

    SyncSlider(controls.sSeqX, seqX)
    SyncSlider(controls.sSeqY, seqY)
    SyncSlider(controls.sModsX, modX)
    SyncSlider(controls.sModsY, modY)
    SyncSlider(controls.sKeybindX, keyX)
    SyncSlider(controls.sKeybindY, keyY)
    SyncSlider(controls.sPressedX, pressX)
    SyncSlider(controls.sPressedY, pressY)
    SyncSlider(controls.sPressedSize, addon:GetPressedIndicatorSize())

    SyncSlider(controls.sSeqSize, addon:GetSeqFontSize())
    SyncSlider(controls.sModsSize, addon:GetModFontSize())
    SyncSlider(controls.sKeybindSize, addon:GetKeybindFontSize())

    if controls.cbCombatMarkerEnabled then
      controls.cbCombatMarkerEnabled:SetChecked(addon:IsCombatMarkerEnabled())
    end
    if controls.cbCombatMarkerBorder then
      controls.cbCombatMarkerBorder:SetChecked(addon:GetCombatMarkerBorderSize() > 0)
    end
    if controls.ddCombatMarkerShowWhen then
      local showWhen = addon:GetCombatMarkerShowWhen()
      local showWhenText = SHOW_TEXT[showWhen] or showWhen
      setDropdownValue(controls.ddCombatMarkerShowWhen, showWhen, showWhenText)
    end
    if controls.ddCombatMarkerSymbol then
      local symbol = addon:GetCombatMarkerSymbol()
      local symbolText = ({ x = "X", plus = "Plus", diamond = "Diamond", square = "Square", circle = "Circle" })[symbol] or symbol
      setDropdownValue(controls.ddCombatMarkerSymbol, symbol, symbolText)
    end
    if controls.sCombatMarkerX or controls.sCombatMarkerY then
      local mx, my = addon:GetCombatMarkerOffset()
      SyncSlider(controls.sCombatMarkerX, mx)
      SyncSlider(controls.sCombatMarkerY, my)
    end
    if controls.sCombatMarkerSize then
      SyncSlider(controls.sCombatMarkerSize, addon:GetCombatMarkerSize())
    end
    if controls.sCombatMarkerThickness then
      SyncSlider(controls.sCombatMarkerThickness, addon:GetCombatMarkerThickness())
    end
    if controls.sCombatMarkerBorderSize then
      SyncSlider(controls.sCombatMarkerBorderSize, addon:GetCombatMarkerBorderSize())
    end
    if controls.sCombatMarkerAlpha then
      local alpha = addon:GetCombatMarkerAlpha()
      controls.sCombatMarkerAlpha:SetValue(alpha)
      if controls.sCombatMarkerAlpha.inputBox and not controls.sCombatMarkerAlpha.inputBox:HasFocus() then
        controls.sCombatMarkerAlpha.inputBox:SetText(string.format("%.2f", alpha))
      end
    end
    if controls.cbCombatMarkerUseClassColor then
      controls.cbCombatMarkerUseClassColor:SetChecked(addon:GetCombatMarkerUseClassColor())
    end
    if controls.btnCombatMarkerColor and frame.UpdateCombatMarkerColorButton then
      local r, g, b = addon:GetCombatMarkerColor()
      frame:UpdateCombatMarkerColorButton(r, g, b)
    end
    if frame.SetCombatMarkerControlsEnabled then
      frame:SetCombatMarkerControlsEnabled(addon:IsCombatMarkerEnabled())
    end

    if controls.cbAssistedHighlightEnabled then
      controls.cbAssistedHighlightEnabled:SetChecked(addon:IsAssistedHighlightMirrorEnabled())
    end
    if controls.cbAssistedHighlightBorder then
      controls.cbAssistedHighlightBorder:SetChecked(addon:GetAssistedHighlightBorderSize() > 0)
    end
    if controls.cbAssistedHighlightKeybind then
      controls.cbAssistedHighlightKeybind:SetChecked(addon:GetAssistedHighlightShowKeybind())
    end
    if controls.cbAssistedHighlightRangeChecker then
      controls.cbAssistedHighlightRangeChecker:SetChecked(addon:GetAssistedHighlightRangeCheckerEnabled())
    end
    if controls.cbAssistedHighlightLock then
      controls.cbAssistedHighlightLock:SetChecked(addon:GetAssistedHighlightLocked())
    end
    if controls.cbAssistedHighlightUseClassColor then
      controls.cbAssistedHighlightUseClassColor:SetChecked(addon:GetAssistedHighlightUseClassColor())
    end
    if controls.ddAssistedHighlightShowWhen then
      local showWhen = addon:GetAssistedHighlightShowWhen()
      local showWhenText = SHOW_TEXT[showWhen] or showWhen
      setDropdownValue(controls.ddAssistedHighlightShowWhen, showWhen, showWhenText)
    end
    if controls.sAssistedHighlightSize then
      SyncSlider(controls.sAssistedHighlightSize, addon:GetAssistedHighlightSize())
    end
    if controls.sAssistedHighlightBorder then
      SyncSlider(controls.sAssistedHighlightBorder, addon:GetAssistedHighlightBorderSize())
    end
    if controls.sAssistedHighlightAlpha then
      SyncSlider(controls.sAssistedHighlightAlpha, addon:GetAssistedHighlightAlpha())
    end
    if controls.sAssistedHighlightX or controls.sAssistedHighlightY then
      local ax, ay = addon:GetAssistedHighlightOffset()
      SyncSlider(controls.sAssistedHighlightX, ax)
      SyncSlider(controls.sAssistedHighlightY, ay)
    end
    if controls.sAssistedHighlightKeybindX or controls.sAssistedHighlightKeybindY then
      local kx, ky = addon:GetAssistedHighlightKeybindOffset()
      SyncSlider(controls.sAssistedHighlightKeybindX, kx)
      SyncSlider(controls.sAssistedHighlightKeybindY, ky)
    end
    if controls.sAssistedHighlightFontSize then
      SyncSlider(controls.sAssistedHighlightFontSize, addon:GetAssistedHighlightFontSize())
    end
    if controls.ddAssistedHighlightFont then
      local fontName = addon:GetAssistedHighlightFontName()
      setDropdownValue(controls.ddAssistedHighlightFont, fontName, fontName)
    end
    if controls.ddAssistedHighlightAnchorTarget then
      local anchorTarget = addon:GetAssistedHighlightAnchorTarget()
      setDropdownValue(controls.ddAssistedHighlightAnchorTarget, anchorTarget, anchorTarget)
    end
    if controls.btnAssistedHighlightColor and frame.UpdateAssistedHighlightColorButton then
      local r, g, b = addon:GetAssistedHighlightColor()
      frame:UpdateAssistedHighlightColorButton(r, g, b)
    end
    if frame.SetAssistedHighlightControlsEnabled then
      frame:SetAssistedHighlightControlsEnabled(addon:IsAssistedHighlightMirrorEnabled())
    end

    if frame._gsetrackerBorderStyled ~= true then
      styleWindowBorder(frame)
      frame._gsetrackerBorderStyled = true
    end
    SetRefreshing(false)
  end
end
