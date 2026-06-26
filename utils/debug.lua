local _, ns = ...
local Utils = ns.Utils or {}
ns.Utils = Utils
local C = Utils.Constants or ns.Constants or {}

local PREFIX = C.ADDON_DISPLAY_NAME or "|cFFFFFFFFGS|r|cFF00FFFFE:|r|cFFFFFF00 Tracker|r"

-- Slash-command module. (The old debug-mode toggle was removed -- GSE provides its own
-- debug tooling, and this addon only ever emitted two trivial debug lines.)
local DebugModule = Utils.DebugModule or {}
Utils.DebugModule = DebugModule

local function PrintChat(message)
  -- NOTE: only a nil guard here. Do NOT compare message to "" -- a debug line can carry a
  -- "secret" (taint-protected) value, e.g. a meter readout's FontString:GetText() pulled in
  -- combat, and `secret == ""` THROWS, aborting the dump mid-way. The whole emit is pcall'd
  -- for the same reason (concatenating/printing a secret can also raise).
  if message == nil then return end
  local ok = pcall(function()
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
      DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. message)
    elseif print then
      print("GSE Tracker", message)
    end
  end)
  if not ok and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " <unprintable secret/tainted value>")
  end
end

function DebugModule:HandleSlashCommand(msg)
  msg = type(msg) == "string" and msg:lower():match("^%s*(.-)%s*$") or ""

  if msg == "minimap" then
    if ns.SetMinimapHidden then
      ns:SetMinimapHidden(false)
    end
    if ns.UI and ns.UI.RefreshMinimapButton then
      ns.UI:RefreshMinimapButton()
    end
    PrintChat("Minimap button shown.")
    return
  end

  if msg == "reset" or msg == "resetpressed" or msg == "reset pressed" then
    -- Recover the Pressed Indicator if it was dragged off-screen / lost: re-center it on
    -- the icon row, ensure it's enabled, then flash it (mark input) so it's visible now.
    if ns.SetElementOffset then ns:SetElementOffset("pressedIndicator", 0, 0) end
    if ns.SetElementEnabled then ns:SetElementEnabled("pressedIndicator", true) end
    ns._lastInputTime = (_G.GetTime and _G.GetTime()) or 0
    if ns.RefreshPressedIndicator then ns:RefreshPressedIndicator(true) end
    PrintChat("Pressed Indicator re-centered on the tracker and enabled. Press any key to see it blink.")
    return
  end

  if msg == "f1off" or msg == "f1 off" or msg == "ah off" or msg == "assist off" then
    -- Turn OFF the Assisted Highlight (the "F1" keybind highlight) and hide it now.
    if ns.SetAssistedHighlightMirrorEnabled then ns:SetAssistedHighlightMirrorEnabled(false) end
    if ns.RefreshAssistedHighlight then ns:RefreshAssistedHighlight(true) end
    PrintChat("Assisted Highlight (the F1 keybind highlight) turned OFF.")
    return
  end

  if msg == "emstate" or msg == "editmode" then
    -- Dump the REAL Edit Mode / example-preview state from the addon's own ns table (so it can't be
    -- confused by guessing the wrong global). Run it while Blizzard Edit Mode is open.
    local EMM = _G.EditModeManagerFrame
    local blizz = (EMM and EMM.IsEditModeActive and EMM:IsEditModeActive()) and true or false
    local UI = ns  -- finalized addon: has cross-module methods (GetActionTrackerLayout etc.); ns.UI alone does not
    local f = (UI and UI.ui) or _G.GSE_TrackerFrame
    PrintChat(string.format(
      "EditMode: blizz=%s editing=%s preview=%s enabled=%s combat=%s frameShown=%s boxShown=%s",
      tostring(blizz),
      tostring(ns._editingOptions),
      tostring(UI and UI.IsEditModePreviewActive and UI:IsEditModePreviewActive()),
      tostring(ns.IsEnabled and ns:IsEnabled()),
      tostring(_G.InCombatLockdown and _G.InCombatLockdown() or false),
      tostring(f and f.IsShown and f:IsShown()),
      tostring(f and f._gsetEditBox and f._gsetEditBox.IsShown and f._gsetEditBox:IsShown())))
    -- Second line: actual rendered widget state (ground truth for "nothing shows").
    local ui = (UI and UI.ui) or f
    local ic = ui and ui.icons and ui.icons[1]
    local nt = ui and ui.nameText
    local nt2 = ui and ui.nameText2
    local il = ic and ic.nameLabel
    local overlays = ui and ui._verticalPreviewTextFrames
    local ot = overlays and overlays.top
    local oi = overlays and overlays.icon1
    PrintChat(string.format(
      "Render: nIcons=%s i1Shown=%s i1Alpha=%s i1Tex=%s frameAlpha=%s nameShown=%s nameAlpha=%s name=%q",
      tostring(ui and ui.icons and #ui.icons),
      tostring(ic and ic.IsShown and ic:IsShown()),
      tostring(ic and ic.GetAlpha and ic:GetAlpha()),
      tostring(ic and ic.tex and ic.tex.GetTexture and ic.tex:GetTexture()),
      tostring(f and f.GetAlpha and f:GetAlpha()),
      tostring(nt and nt.IsShown and nt:IsShown()),
      tostring(nt and nt.GetAlpha and nt:GetAlpha()),
      tostring((nt and nt.GetText and nt:GetText()) or "")))
    PrintChat(string.format(
      "VerticalNames: layout=%s topShown=%s topAlpha=%s top=%q i1NameShown=%s i1NameAlpha=%s i1Name=%q overlayTop=%s/%q overlayI1=%s/%q",
      tostring(UI and UI.GetActionTrackerLayout and UI:GetActionTrackerLayout()),
      tostring(nt2 and nt2.IsShown and nt2:IsShown()),
      tostring(nt2 and nt2.GetAlpha and nt2:GetAlpha()),
      tostring((nt2 and nt2.GetText and nt2:GetText()) or ""),
      tostring(il and il.IsShown and il:IsShown()),
      tostring(il and il.GetAlpha and il:GetAlpha()),
      tostring((il and il.GetText and il:GetText()) or ""),
      tostring(ot and ot.IsShown and ot:IsShown()),
      tostring((ot and ot.text and ot.text.GetText and ot.text:GetText()) or ""),
      tostring(oi and oi.IsShown and oi:IsShown()),
      tostring((oi and oi.text and oi.text.GetText and oi.text:GetText()) or "")))
    -- Fourth line: overlay LAYER + edit-box stacking. IsVisible (not IsShown) reflects the parent
    -- chain, so a hidden/under-strata layer shows up here even when the text frames report Shown.
    local layer = ui and ui._verticalNameOverlayLayer
    local box = ui and ui._gsetEditBox
    PrintChat(string.format(
      "Stacking: layerShown=%s layerStrata=%s layerLvl=%s boxStrata=%s boxLvl=%s topVisible=%s topStrata=%s topLvl=%s i1Visible=%s",
      tostring(layer and layer.IsShown and layer:IsShown()),
      tostring(layer and layer.GetFrameStrata and layer:GetFrameStrata()),
      tostring(layer and layer.GetFrameLevel and layer:GetFrameLevel()),
      tostring(box and box.GetFrameStrata and box:GetFrameStrata()),
      tostring(box and box.GetFrameLevel and box:GetFrameLevel()),
      tostring(ot and ot.IsVisible and ot:IsVisible()),
      tostring(ot and ot.GetFrameStrata and ot:GetFrameStrata()),
      tostring(ot and ot.GetFrameLevel and ot:GetFrameLevel()),
      tostring(oi and oi.IsVisible and oi:IsVisible())))
    PrintChat(string.format(
      "GSEnameSlide: fires=%s offset=%s startSet=%s driver=%s",
      tostring(ns._gseSlideFires or 0),
      tostring(nt2 and nt2._verticalGSESlideOffset),
      tostring(nt2 and nt2._verticalGSESlideStart ~= nil),
      tostring(ui and ui._verticalGSENameSlideDriver and ui._verticalGSENameSlideDriver.GetScript and ui._verticalGSENameSlideDriver:GetScript("OnUpdate") ~= nil)))
    return
  end

  if msg == "meters" then
    -- DPS/HPS not showing? Dump the gates + frame state. Run while IN COMBAT.
    local sv = _G.MetersSavedVars or {}
    local slots = sv.slots or {}
    local dpsF, hpsF, anc = _G.DPSFrame, _G.HPSFrame, _G.MetersAnchor
    PrintChat(string.format(
      "Meters caps: capable=%s hasSource=%s combat=%s mode=%s locked=%s enabled=%s",
      tostring(_G.GSETracker_MetersCapable),
      tostring(_G.GSETracker_HasDPSSource and _G.GSETracker_HasDPSSource()),
      tostring(_G.InCombatLockdown and _G.InCombatLockdown() or false),
      tostring(sv.showWhen), tostring(sv.locked), tostring(sv.enabled)))
    PrintChat(string.format(
      "Meters SV: showDPS=%s showHPS=%s slotDPS=%s slotHPS=%s",
      tostring(sv.showDPS), tostring(sv.showHPS), tostring(slots.DPS), tostring(slots.HPS)))
    PrintChat(string.format(
      "DPSFrame: shown=%s alpha=%s parent=%s text=%q",
      tostring(dpsF and dpsF.IsShown and dpsF:IsShown()),
      tostring(dpsF and dpsF.GetAlpha and dpsF:GetAlpha()),
      tostring(dpsF and dpsF.GetParent and dpsF:GetParent() and (dpsF:GetParent():GetName() or "anon")),
      tostring(dpsF and dpsF.dpsText and dpsF.dpsText.GetText and (dpsF.dpsText:GetText() or ""))))
    PrintChat(string.format(
      "HPSFrame: shown=%s alpha=%s text=%q | Anchor: shown=%s alpha=%s",
      tostring(hpsF and hpsF.IsShown and hpsF:IsShown()),
      tostring(hpsF and hpsF.GetAlpha and hpsF:GetAlpha()),
      tostring(hpsF and hpsF.hpsText and hpsF.hpsText.GetText and (hpsF.hpsText:GetText() or "")),
      tostring(anc and anc.IsShown and anc:IsShown()),
      tostring(anc and anc.GetAlpha and anc:GetAlpha())))
    return
  end

  if ns.ToggleSettingsWindow then
    ns:ToggleSettingsWindow()
  end
end

function DebugModule:RegisterSlashCommands()
  if self._slashRegistered then
    return
  end

  SLASH_GSETRACKER1 = "/gsetracker"
  SlashCmdList.GSETRACKER = function(msg)
    self:HandleSlashCommand(msg)
  end

  -- Convenience reload alias (restored). Note: /reload and /reloadui are Blizzard built-ins;
  -- /rl is not, so addons provide it. Last addon to register /rl wins if several do.
  SLASH_GSETRACKERRELOAD1 = "/rl"
  SlashCmdList.GSETRACKERRELOAD = function()
    if _G.ReloadUI then _G.ReloadUI() end
  end

  self._slashRegistered = true
end

function DebugModule:Init()
  self:RegisterSlashCommands()
end
