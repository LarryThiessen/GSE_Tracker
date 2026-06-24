local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local uiShared = addon._ui or {}
local ensureDatabase = uiShared.EnsureDB
local StartNameSlide -- forward decl (defined with the slide helpers below); slides
                     -- the sequence name UP into place when it first appears.

-- In VERTICAL layout the flanking labels read top-to-bottom -- one glyph per line
-- (e.g. "Shift" -> S/h/i/f/t). Returns the text unchanged in horizontal layout.
-- UTF-8 aware so localised names stack per character, not per byte.
function uiShared.FormatLabelForLayout(text)
  -- The Action Tracker text now reads HORIZONTALLY in BOTH layouts (vertical no longer stacks glyphs:
  -- the GSE/Spell names sit above the icon column and MODKEYS below). Returns the text unchanged so the
  -- same reliable name path works for both layouts.
  return text
end
local function FmtLabel(text) return uiShared.FormatLabelForLayout(text) end

local function SetModifierStyle(fs, active, r, g, b)
  if not fs then return end
  if active then
    fs:SetTextColor(r, g, b, 1)
  else
    fs:SetTextColor(1, 1, 1, 0.50)
  end
end

local function ElementEnabled(elementName)
  local cfg, defaults = addon:GetElementLayout(elementName)
  if type(cfg) == "table" and cfg.enabled ~= nil then
    return cfg.enabled and true or false
  end
  if defaults and defaults.enabled ~= nil then
    return defaults.enabled and true or false
  end
  return true
end

-- Example label(s) shown while unlocked/editing so the user can position + font them. They reflect
-- the two name toggles + swap: split (swap + both) -> the main slot shows the Spell example (the GSE
-- example goes to the top label, GetPreviewTopName); otherwise a combined example (GSE on top).
local function GetPreviewSequenceText()
  local showSeq = addon.GetActionTrackerShowSequenceName and addon:GetActionTrackerShowSequenceName()
  local showSpell = addon.GetActionTrackerShowSpellName and addon:GetActionTrackerShowSpellName()
  if showSeq and showSpell then return "Spell Name" end   -- both -> Spell is the inner/main name
  if showSpell then return "Spell Name" end
  if showSeq then return "GSE Sequence Name" end
  return ""  -- both name toggles OFF -> show NO name text (not even a placeholder)
end

-- The hoisted GSE example (only when BOTH names are on, i.e. the split layout); "" otherwise.
local function GetPreviewTopName()
  local showSeq = addon.GetActionTrackerShowSequenceName and addon:GetActionTrackerShowSequenceName()
  local showSpell = addon.GetActionTrackerShowSpellName and addon:GetActionTrackerShowSpellName()
  if showSeq and showSpell then return "GSE Sequence Name" end
  return ""
end

local function GetPreviewKeybindText()
  return "F1"
end

local function HasRuntimeSequenceText(ui)
  local txt = ui and ui._lastSeqText
  return type(txt) == "string" and txt ~= ""
end

local function GetRuntimeSequenceKey(ui)
  local seqKey = (ui and ui._lastSeqKey) or addon._activeSeqKey
  if type(seqKey) == "string" and seqKey ~= "" then
    return seqKey
  end
  return nil
end

local function GetRuntimeSequenceText(ui)
  if HasRuntimeSequenceText(ui) then
    return ui._lastSeqText
  end
  local seqKey = GetRuntimeSequenceKey(ui)
  if seqKey and addon.GetActiveSequenceDisplayText then
    local displayText = addon:GetActiveSequenceDisplayText(seqKey)
    if type(displayText) == "string" and displayText ~= "" then
      return displayText
    end
  end
  return ""
end

local function GetRuntimeKeybindText(ui)
  local seqKey = GetRuntimeSequenceKey(ui)
  if not seqKey and not HasRuntimeSequenceText(ui) then
    return ""
  end

  if addon.GetActiveSequenceBindingText then
    local bindingText = addon:GetActiveSequenceBindingText(seqKey)
    if type(bindingText) == "string" and bindingText ~= "" then
      return bindingText
    end
  end

  local txt = ui and ui._lastKeybindText
  if type(txt) == "string" and txt ~= "" then
    return txt
  end

  return ""
end

local function ApplyRuntimeSequenceVisibility(self, show)
  local ui = self.ui
  if not ui then return end

  -- Placement preview: the example name/keybind placeholders appear on EXACTLY the same
  -- signal as the example icons -- IsEditModePreviewActive (Blizzard Edit Mode +
  -- out of combat). Lock is Edit-Mode-driven now, so there is no separate
  -- "unlocked" preview state; keying on the preview signal keeps name/keybind in lockstep
  -- with the icons and guarantees they clear the instant Edit Mode exits OR combat starts.
  -- (No live GSE sequence exists out of combat, so the example always wins while previewing.)
  local inPreview = (self.IsEditModePreviewActive and self:IsEditModePreviewActive()) or false

  -- A post-combat name fade-out is in progress (see ui/events.lua PLAYER_REGEN_ENABLED). Let
  -- SmoothFadeOut own the name/keybind alpha for the duration so a visibility refresh can't snap
  -- them back to full (Always) or zero (In Combat) mid-ramp. A fresh cast/combat clears the flag
  -- via RebuildNameDisplay before this runs again. EXCEPTION: in Edit Mode preview we must paint
  -- the example now (there's no live fade to protect, and entering Edit Mode within ~3s of leaving
  -- combat must still show the placeholders) -- so cancel any lingering fade and continue.
  if ui._namesFading then
    if not inPreview then return end
    ui._namesFading = false
    if uiShared and uiShared.CancelFade then
      uiShared.CancelFade(ui.nameText)
      uiShared.CancelFade(ui.nameText2)
      uiShared.CancelFade(ui.keybindText)
    end
  end

  local seqText = show and GetRuntimeSequenceText(ui) or ""
  local keyText = show and GetRuntimeKeybindText(ui) or ""

  local usingPreview = false
  if inPreview then
    seqText = GetPreviewSequenceText(); usingPreview = true
    keyText = GetPreviewKeybindText()
  end

  local seqVisible = seqText ~= "" and ElementEnabled("sequenceText")
  -- VERTICAL: the single inner Spell name is REPLACED by per-icon labels (UpdateIconNames); the GSE name
  -- is hoisted top-centre (_UpdateTopNameLabel, still called below). Hide the single name here.
  if (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) == "VERTICAL" then
    seqVisible = false
  end
  if ui.sequenceTextFrame then
    if seqVisible then
      -- Slide the name UP into place when it first appears (false -> true).
      if not ui._seqWasVisible and StartNameSlide then StartNameSlide(ui) end
      ui.sequenceTextFrame:Show()
    else
      ui.sequenceTextFrame:Hide()
    end
  end
  ui._seqWasVisible = seqVisible
  if ui.nameText then
    ui.nameText:SetText(seqVisible and FmtLabel(seqText) or "")
    if self._ApplyNameVOffset then self:_ApplyNameVOffset(seqVisible and seqText or "") end
    -- The placeholder example must be fully visible: a just-cleared sequence leaves
    -- ui._accentA = 0, which would otherwise render the example transparent. Use white at
    -- full alpha for the preview; live sequences keep their accent colour/alpha.
    local r, g, b, a
    if usingPreview then
      r, g, b, a = 1, 1, 1, (seqVisible and 1 or 0)
    else
      r, g, b = ui._accentR or 1, ui._accentG or 1, ui._accentB or 1
      a = seqVisible and (ui._accentA or 1) or 0
    end
    ui.nameText:SetTextColor(r, g, b, a)
    -- Hoisted GSE label (only shows in split mode); mirror this colour/alpha.
    if self._UpdateTopNameLabel then
      local topText = usingPreview and GetPreviewTopName() or self._gseSeqName
      local doSplit = usingPreview or (self._NameSplitActive and self:_NameSplitActive())
      self:_UpdateTopNameLabel(topText, doSplit, r, g, b, a)
    end
  end

  local keyVisible = keyText ~= "" and ElementEnabled("keybindText")
  if ui.keybindFrame then
    if keyVisible then ui.keybindFrame:Show() else ui.keybindFrame:Hide() end
  end
  if ui.keybindText then
    ui.keybindText:SetText(keyVisible and FmtLabel(keyText) or "")
    ui.keybindText:SetTextColor(1, 1, 1, keyVisible and 1 or 0)
  end
end

function UI:RefreshCombatOnlyElements(show, inCombat)
  local ui = self.ui
  if not ui then return end

  -- ONE unified render path for both live play and Edit Mode placement preview. The
  -- example name / keybind / modkey placeholders are gated on EXACTLY the same signal as
  -- the example icons -- IsEditModePreviewActive (Edit Mode + out of combat). So all
  -- of them switch ON together when Edit Mode opens out of combat and OFF
  -- together the instant Edit Mode closes OR combat begins. There is deliberately NO
  -- separate "editing" render path: the old one drifted out of sync with the icons (text
  -- examples lingered after exit because lock applied after the render, and stayed up in
  -- combat because it ignored combat; its modkey example was also dead -- it set the legacy
  -- modAlt/modShift/modCtrl widgets that UpdateModifiers immediately wiped).
  local inPreview = (self.IsEditModePreviewActive and self:IsEditModePreviewActive()) or false

  ApplyRuntimeSequenceVisibility(self, show)

  -- Modifiers show ONLY while a side-modifier is actually held (UpdateModifiers does the
  -- show/hide); in preview we feed it a fixed sample ("LShift+RCtrl") so it can be placed.
  -- Allow the readout even if `show` is false in preview (e.g. no target), matching the
  -- icons/name which also ignore `show` while previewing.
  local modsAllowed = (show or inPreview) and ElementEnabled("modifiersText") and true or false
  ui._modsAllowed = modsAllowed
  ui._modsPreview = (modsAllowed and inPreview) and "LShift+RCtrl" or nil
  self:UpdateModifiers(true)

  -- The pressed indicator is independent of the tracker's visibility (it can show
  -- even when the tracker is hidden, so a left-on spammer is visible). Let
  -- RefreshPressedIndicator own the show/hide based on recent INPUT + the element
  -- being enabled.
  if self.RefreshPressedIndicator then
    self:RefreshPressedIndicator(true)
  end
  if inPreview and self.RefreshVerticalEditModeNames then
    self:RefreshVerticalEditModeNames()
  elseif self.UpdateIconNames then
    self:UpdateIconNames()
  end
  if self.UpdateAHMatchReadout then
    self:UpdateAHMatchReadout()
  end

  -- Entering/leaving preview changes the content size (placeholders appear/disappear); keep
  -- the frame fitted and the elements anchored so the example sits where the live text will
  -- (this is the layout work the old editing path did, now folded into the single path).
  if inPreview then
    if self.ApplyFontFaces then self:ApplyFontFaces() end
    if self.ApplyAllElementPositions then self:ApplyAllElementPositions() end
    if self._ResizeToContent then self:_ResizeToContent() end
  end
end

function UI:ApplyVisibility()
  local ui = self.ui
  if not ui then return end
  ensureDatabase()

  if self.UpdateEventSubscriptions then
    self:UpdateEventSubscriptions(ui)
  end

  local mode = (addon.GetShowWhen and addon:GetShowWhen()) or (C.MODE_ALWAYS or "Always")
  local inCombat = (ui._combatState ~= nil and ui._combatState) or API.InCombatLockdown()
  local hasTarget = (API.HasHarmTarget and API.HasHarmTarget()) or false

  local show
  -- Edit Mode visibility is DELIBERATELY decoupled from the Show-When setting: while Blizzard Edit
  -- Mode is open the tracker frame is ALWAYS shown so its selection box + example placeholders are
  -- visible to position, even if Show-When is "Has Target"/"In Combat"/"Never". Source of truth is
  -- Blizzard's live EditModeManagerFrame:IsEditModeActive() (our _editingOptions flag is the fast
  -- path) -- so a missed/late EditMode.Enter callback can't leave the frame hidden behind Show-When.
  local editingOverride = addon._editingOptions and true or false
  if not editingOverride then
    local EMM = _G.EditModeManagerFrame
    if EMM and EMM.IsEditModeActive and EMM:IsEditModeActive() then editingOverride = true end
  end
  if not editingOverride and self.IsEditModePreviewActive and self:IsEditModePreviewActive() then
    editingOverride = true
  end
  local actionTrackerEnabled = not (self.IsEnabled and not self:IsEnabled())
  if not actionTrackerEnabled then
    -- Disabled in the options = hidden EVERYWHERE, including Edit Mode. editingOverride no longer
    -- force-shows a disabled Action Tracker, so a turned-off element shows no frame/example/box.
    show = false
  elseif self.EvaluateVisibilityMode then
    show = self:EvaluateVisibilityMode(mode, inCombat, hasTarget, editingOverride)
  else
    show = true
    if not editingOverride then
      if mode == "Never" then
        show = false
      elseif mode == "InCombat" then
        show = inCombat
      elseif mode == "HasTarget" then
        show = hasTarget
      end
    end
  end

  local visibilityChanged = (ui._lastVisible ~= show)
  if visibilityChanged then
    ui._lastVisible = show
    if show then ui:Show() else ui:Hide() end
  end

  if self._pendingFontApply and self.ApplyFontFaces then
    self:ApplyFontFaces()
  end

  if self.ApplyEditModeIconPreview then
    self:ApplyEditModeIconPreview(false)
  end

  self:RefreshCombatOnlyElements(show, inCombat)
end

-- Modifier press slide-in: when a modifier becomes active, its label slides DOWN
-- into its resting spot (starts ~12px up toward the icons, eases down over ~0.18s).
local MOD_SLIDE_DISTANCE = 12
local MOD_SLIDE_DURATION = 0.18
local function ModNow()
  return (API.GetTime and API.GetTime()) or (_G.GetTime and _G.GetTime()) or 0
end
local function ApplyModSlideY(ui, label, y)
  if not (label and ui and ui.modifiersFrame) then return end
  label:ClearAllPoints()
  -- Vertical keeps ModKeys below the icon column, so it uses the same top-to-bottom
  -- slide as the horizontal layout.
  label:SetPoint("CENTER", ui.modifiersFrame, "CENTER", label._modBaseX or 0, y)
end
local function ModSlideOnUpdate(driver)
  local ui = driver and driver._ui
  if not ui then if driver then driver:SetScript("OnUpdate", nil) end return end
  local now = ModNow()
  local anyActive = false
  local labels = driver._labels
  for i = 1, #labels do
    local label = labels[i]
    if label and label._modSlideStart then
      local t = (now - label._modSlideStart) / MOD_SLIDE_DURATION
      if t >= 1 then
        label._modSlideStart = nil
        ApplyModSlideY(ui, label, 0)
      else
        anyActive = true
        local inv = 1 - t
        ApplyModSlideY(ui, label, MOD_SLIDE_DISTANCE * inv * inv) -- ease-out, ends 0
      end
    end
  end
  if not anyActive then driver:SetScript("OnUpdate", nil) end
end
local function StartModSlide(ui, label)
  if not (ui and label) then return end
  label._modSlideStart = ModNow()
  local driver = ui._modSlideDriver
  if not driver then
    driver = (API.CreateFrame or _G.CreateFrame)("Frame")
    ui._modSlideDriver = driver
  end
  driver._ui = ui
  driver._labels = { ui.modAlt, ui.modShift, ui.modCtrl }
  driver:SetScript("OnUpdate", ModSlideOnUpdate)
end

-- Sequence name slide-UP: when the name first appears it slides up into its resting
-- spot (starts ~12px DOWN toward the icons, eases up over the same duration).
local NAME_SLIDE_DISTANCE = 12
local function ApplyNameSlideY(ui, y)
  local fs = ui and ui.nameText
  local frame = ui and ui.sequenceTextFrame
  if not (fs and frame) then return end
  fs:ClearAllPoints()
  fs:SetPoint("CENTER", frame, "CENTER", 0, y)
end
local function NameSlideOnUpdate(driver)
  local ui = driver and driver._ui
  local fs = ui and ui.nameText
  if not (fs and fs._slideStart) then
    if driver then driver:SetScript("OnUpdate", nil) end
    return
  end
  local t = (ModNow() - fs._slideStart) / MOD_SLIDE_DURATION
  if t >= 1 then
    fs._slideStart = nil
    ApplyNameSlideY(ui, 0)
    driver:SetScript("OnUpdate", nil)
  else
    local inv = 1 - t
    ApplyNameSlideY(ui, -NAME_SLIDE_DISTANCE * inv * inv) -- starts down, eases UP to 0
  end
end
StartNameSlide = function(ui) -- assigns the forward-declared upvalue
  if not (ui and ui.nameText) then return end
  ui.nameText._slideStart = ModNow()
  ApplyNameSlideY(ui, -NAME_SLIDE_DISTANCE) -- set the start (down) position immediately
  local driver = ui._nameSlideDriver
  if not driver then
    driver = (API.CreateFrame or _G.CreateFrame)("Frame")
    ui._nameSlideDriver = driver
  end
  driver._ui = ui
  driver:SetScript("OnUpdate", NameSlideOnUpdate)
end

-- Public hook so the live SetSequenceText path (icons.lua) can trigger the slide.
function UI:SlideSequenceNameIn()
  StartNameSlide(self.ui)
end

-- Build the SIDE-specific held-modifier string, e.g. "RShift+LCtrl". Order:
-- Shift, Ctrl, Alt; each side listed if held. Empty when nothing is held.
-- Reads the EVENT-tracked ui._sideMod (set from MODIFIER_STATE_CHANGED) rather than
-- live IsXKeyDown(), because the just-pressed key's IsXKeyDown isn't true yet at its
-- own event -- which made single presses show nothing while doubles worked.
local function GetHeldModifierString(ui)
  local s = ui and ui._sideMod
  if not s then return "" end
  local p = {}
  if s.LSHIFT then p[#p + 1] = "LShift" end
  if s.RSHIFT then p[#p + 1] = "RShift" end
  if s.LCTRL  then p[#p + 1] = "LCtrl"  end
  if s.RCTRL  then p[#p + 1] = "RCtrl"  end
  if s.LALT   then p[#p + 1] = "LAlt"   end
  if s.RALT   then p[#p + 1] = "RAlt"   end
  return table.concat(p, "+")
end

-- Public accessor: the side-aware held-modifier string (e.g. "RShift+LCtrl"), or ""
-- when nothing is held. Used by the ModKey stack to group casts by combo.
function UI:GetHeldModifierString()
  return GetHeldModifierString(self.ui)
end

-- The modifier readout is now a SINGLE combined label (ui.modShift, centred) that
-- shows exactly which side+modifier(s) are held, and is HIDDEN when none are. It
-- slides in on the first press. ui.modAlt/ui.modCtrl are no longer used.
-- Drop the side prefix (L/R) from each token of a modifier string and de-duplicate,
-- e.g. "LShift+RCtrl" -> "Shift+Ctrl", "LShift+RShift" -> "Shift". Used when the
-- "Modkey Side" option is off.
local function StripModifierSides(str)
  if not str or str == "" then return str end
  local seen, out = {}, {}
  for token in string.gmatch(str, "[^+]+") do
    local bare = token:gsub("^[LR]", "")
    if not seen[bare] then
      seen[bare] = true
      out[#out + 1] = bare
    end
  end
  return table.concat(out, "+")
end

function UI:UpdateModifiers(force)
  local ui = self.ui
  if not ui then return end

  -- Preview (placement) shows a sample so it can be positioned; live uses the
  -- actual held keys, but only when the tracker allows the modifiers element.
  local str = ui._modsPreview or (ui._modsAllowed and GetHeldModifierString(ui)) or ""
  if str ~= "" and addon.GetActionTrackerModkeySide and not addon:GetActionTrackerModkeySide() then
    str = StripModifierSides(str)
  end

  if not force and ui._modComboStr == str then return end
  local prev = ui._modComboStr
  ui._modComboStr = str

  if ui.modAlt then ui.modAlt:SetText(""); ui.modAlt:Hide() end
  if ui.modCtrl then ui.modCtrl:SetText(""); ui.modCtrl:Hide() end

  local has = str ~= ""
  if ui.modifiersFrame then
    if has then ui.modifiersFrame:Show() else ui.modifiersFrame:Hide() end
  end
  if ui.modShift then
    if has then
      -- MODKEYS reads HORIZONTALLY now (it sits centred below the icon column in vertical layout), so
      -- skip the per-glyph vertical stacking there; horizontal layout keeps its normal text.
      local layoutVertical = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) == "VERTICAL"
      ui.modShift:SetText(layoutVertical and str or FmtLabel(str))
      SetModifierStyle(ui.modShift, true, 1, 1, 1)
      ui.modShift:Show()
      if not prev or prev == "" then StartModSlide(ui, ui.modShift) end -- slide in on press
    else
      ui.modShift:SetText("")
      ui.modShift:Hide()
    end
  end
end

function uiShared.SyncModifiers(ui)
  local alt = API.IsAltKeyDown() or false
  local shift = API.IsShiftKeyDown() or false
  local ctrl = API.IsControlKeyDown() or false
  local changed = (ui._modAlt ~= alt) or (ui._modShift ~= shift) or (ui._modCtrl ~= ctrl)
  ui._modAlt = alt
  ui._modShift = shift
  ui._modCtrl = ctrl
  -- Do NOT seed the SIDE-specific state from live IsXKeyDown() here. Right after /reload
  -- (this runs on PLAYER_ENTERING_WORLD) the client can still report a modifier as "down"
  -- because the key-up was never seen -- which made the readout show e.g. "LCtrl" for no
  -- reason until the user pressed+released that key. Start CLEARED; MODIFIER_STATE_CHANGED
  -- (ApplyModifierEvent) populates the real side state the moment a modifier is pressed.
  local s = ui._sideMod or {}
  s.LSHIFT, s.RSHIFT, s.LCTRL, s.RCTRL, s.LALT, s.RALT = false, false, false, false, false, false
  ui._sideMod = s
  return changed
end

-- Set the side-specific modifier state from LIVE key queries. Safe to call OUTSIDE a press
-- event (where IsXKeyDown is accurate); clears a side left stuck by a missed key-up (e.g. a
-- key released during the loading screen, which left our tracking "down" while the client
-- itself reports it up). `exceptKey` skips the just-pressed key, whose live state lags at its
-- own event -- the caller sets that one from the event instead.
function uiShared.ReconcileModifiersFromLive(ui, exceptKey)
  if not ui then return end
  local g = _G
  local s = ui._sideMod or {}
  local function set(k, fn)
    if k == exceptKey then return end
    s[k] = (fn and fn()) and true or false
  end
  set("LSHIFT", g.IsLeftShiftKeyDown)
  set("RSHIFT", g.IsRightShiftKeyDown)
  set("LCTRL",  g.IsLeftControlKeyDown)
  set("RCTRL",  g.IsRightControlKeyDown)
  set("LALT",   g.IsLeftAltKeyDown)
  set("RALT",   g.IsRightAltKeyDown)
  ui._sideMod = s
end

function uiShared.ApplyModifierEvent(ui, key, state)
  local down = (state == 1)
  -- Track the exact side+key from the EVENT (authoritative; live IsXKeyDown lags
  -- for the just-pressed key). The combo readout reads ui._sideMod.
  if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
    or key == "LALT" or key == "RALT" then
    ui._sideMod = ui._sideMod or {}
    ui._sideMod[key] = down
    -- Reconcile the OTHER sides from live so a stuck side (missed key-up) self-corrects on the
    -- next modifier press. The just-pressed key keeps its event value (live lags for it).
    uiShared.ReconcileModifiersFromLive(ui, key)
  end
  if key == "LALT" or key == "RALT" then
    if ui._modAlt == down then return false end
    ui._modAlt = down
    return true
  elseif key == "LSHIFT" or key == "RSHIFT" then
    if ui._modShift == down then return false end
    ui._modShift = down
    return true
  elseif key == "LCTRL" or key == "RCTRL" then
    if ui._modCtrl == down then return false end
    ui._modCtrl = down
    return true
  end
  return uiShared.SyncModifiers(ui)
end

function uiShared.VisibilityDependsOnTarget()
  return addon.VisibilityDependsOnTarget and addon:VisibilityDependsOnTarget() or false
end
