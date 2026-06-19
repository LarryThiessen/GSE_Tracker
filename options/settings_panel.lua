local _, ns = ...
local addon = ns
local Options = ns.Options or {}
ns.Options = Options
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}

-- =========================================================================
-- GSE: Tracker -- options panel: a Blizzard Settings "canvas" category with a
-- top tab bar [General][Action Tracker][Center Marker][Assisted Highlight].
-- Controls are native Blizzard widgets that work on a canvas: CheckButton,
-- OptionsSlider, the modern WowStyle1 dropdown (caret style, taint-free) and
-- ColorPicker. Bound to the addon's db getters/setters.
-- =========================================================================

local categoryID
local panel
local RefreshTabStates -- forward decl (defined with the panel; called by enable toggles)
local CATEGORY_NAME = "|cFFFFFFFFGS|r|cFF00FFFFE|r|cFFFFFF00: Tracker|r"

-- Control-state refreshers for the currently-built panel: callbacks that re-evaluate
-- a control's enabled/greyed state (e.g. disable the AH Scale slider while Target
-- Portrait auto-sizes). Reset whenever the panel is (re)populated; run after any
-- setter fires so toggling one control updates dependents live.
local activeRefreshers = {}
local function RunRefreshers()
  for _, fn in ipairs(activeRefreshers) do
    local ok = pcall(fn)
    if not ok then end -- a stale control (pane rebuilt) just no-ops
  end
end

local refreshPending = false
local function ScheduleRefresh()
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0, function()
    refreshPending = false
    if addon.ApplyDB then addon:ApplyDB() end
    RunRefreshers()
  end)
end

local function CallGet(method, ...)
  local fn = addon[method]
  if type(fn) == "function" then return fn(addon, ...) end
end
local function CallSet(method, ...)
  local fn = addon[method]
  if type(fn) == "function" then fn(addon, ...) end
  ScheduleRefresh()
end
local function ResolveGet(g)
  if type(g) == "function" then return g end
  return function() return CallGet(g) end
end
local function ResolveSet(s)
  if type(s) == "function" then return function(...) s(...); ScheduleRefresh() end end
  return function(...) CallSet(s, ...) end
end

-- ── Branding + social-link elements ────────────────────────────────────────
GSETrackerBrandMixin = GSETrackerBrandMixin or {}
function GSETrackerBrandMixin:Init(initializer) end
GSETrackerSocialMixin = GSETrackerSocialMixin or {}
function GSETrackerSocialMixin:Init(initializer) end

-- Register our copy-link popup by ADDING a key to the existing Blizzard table.
-- Do NOT write `StaticPopupDialogs = StaticPopupDialogs or {}` -- reassigning this
-- Blizzard-owned global from insecure (addon) code TAINTS the global. That taint
-- spreads to every system that reads StaticPopupDialogs (PlayerSpells, micro-menu)
-- and ultimately blocks the GameMenu callback (ADDON_ACTION_FORBIDDEN, "can't log
-- out"). Proven via taintLog 2 on 2026-06-15. StaticPopupDialogs always exists in
-- retail; just add our key.
if StaticPopupDialogs then
StaticPopupDialogs["GSE_TRACKER_LINK"] = {
  text = "%s link \226\128\148 press Ctrl+C to copy:",
  button1 = OKAY or "Okay",
  hasEditBox = true, editBoxWidth = 280, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self, data)
    local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
    if eb then eb:SetText((data and data.url) or ""); eb:HighlightText(); eb:SetFocus() end
  end,
  EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p then p:Hide() end end,
  EditBoxOnEscapePressed = function(self) local p = self:GetParent(); if p then p:Hide() end end,
}
end
function GSETracker_OpenLink(url, label)
  if not url then return end
  StaticPopup_Show("GSE_TRACKER_LINK", label or "Link", nil, { url = url })
end

-- ── Option lists ───────────────────────────────────────────────────────────
local SHOW_OPTIONS = {
  { value = "Always", text = "Always" }, { value = "HasTarget", text = "Has Harm Target" },
  { value = "InCombat", text = "In Combat" }, { value = "Never", text = "Never" },
}
-- Meters uses its own showWhen value strings (compared in Meter_UpdateVisibility).
local METERS_SHOW_OPTIONS = {
  { value = "Always", text = "Always" }, { value = "Has Target", text = "Has Harm Target" },
  { value = "Combat", text = "In Combat" }, { value = "Never", text = "Never" },
}
-- Special center-marker modes: Class/Specialization resolve a per-player icon;
-- "Assisted Highlight" (value kept as "AHLight") mirrors the AH icon at centre.
-- Bullseye is now a media image (see the manifest); None is appended LAST below.
local MYMARKER_OPTIONS = {
  { value = "Class", text = "Class" }, { value = "Specialization", text = "Specialization" },
  { value = "AHLight", text = "Assisted Highlight" },
}
-- The media image symbols from the manifest (auto-discovered crosshair art). New entries
-- in C.COMBAT_MARKER_IMAGE_SYMBOLS appear here automatically.
-- (The procedural vector shapes X/Plus/Diamond/Square/Circle were removed from both the
-- Center Marker and Pressed Indicator dropdowns per request.)
local IMAGE_OPTIONS = {}
local PRESSED_SHAPE_OPTIONS = {}

-- Discrete font sizes for the Meters font dropdown (mirrors the old Meters panel list).
local METERS_FONT_SIZE_OPTIONS = {}
for _, s in ipairs({ 12, 14, 16, 18, 20, 24, 28, 32 }) do
  METERS_FONT_SIZE_OPTIONS[#METERS_FONT_SIZE_OPTIONS + 1] = { value = s, text = s .. " pt" }
end

-- Getters/setters bridging the addon-style Meters font dropdowns (rendered at the top
-- of the Meters tab) to the Meters engine's saved vars + apply path. Defined here so
-- the Meters tab `rows` below can reference them.
local function MetersFontFaceGet()
  local sv = _G.MetersSavedVars
  return (sv and (sv.fontStyle or sv.fontType)) or "Friz Quadrata TT"
end
local function ApplyMetersFont(face)
  local sv = _G.MetersSavedVars
  -- Font-ONLY: must NOT trigger the Meters marker preview (the Bullseye "eye"),
  -- which the full ApplyFontSettings would force on and leave lingering on screen.
  if _G.Meters_ApplyFontOnly then
    _G.Meters_ApplyFontOnly()
  elseif _G.Meter_ApplyFont then
    _G.Meter_ApplyFont(face or MetersFontFaceGet(), sv and sv.fontSize)
  end
end
local function MetersFontFaceSet(v)
  local sv = _G.MetersSavedVars
  if sv then sv.fontStyle = v; sv.fontType = v end
  ApplyMetersFont(v)
end
local function MetersFontSizeGet()
  local sv = _G.MetersSavedVars
  return (sv and tonumber(sv.fontSize)) or 18
end
local function MetersFontSizeSet(v)
  local sv = _G.MetersSavedVars
  if sv then sv.fontSize = tonumber(v) or 18 end
  ApplyMetersFont()
end
local function MetersFontOutlineGet()
  local sv = _G.MetersSavedVars
  return (sv and sv.fontOutline) or "OUTLINE"
end
local function MetersFontOutlineSet(v)
  local sv = _G.MetersSavedVars
  if sv then sv.fontOutline = v end
  ApplyMetersFont()  -- Meter_ApplyFont reads MetersSavedVars.fontOutline
end
-- One merged Center Marker dropdown: the special modes (Class/Spec/Assisted Highlight)
-- first, then the media-image symbols (crosshair art), and "None" LAST. The procedural
-- vector shapes (X/Plus/Diamond/Square/Circle) are intentionally omitted here.
local CENTER_MARKER_OPTIONS = {}

-- (Re)build the three marker-image-backed option lists IN PLACE from the live discovery.
-- Run again at panel-build time (post-login) because the file-load scan in constants.lua
-- can miss files that weren't yet resolvable, which is why the Pressed Indicator / Center
-- Marker dropdowns could omit some crosshairs. Repopulating the SAME tables keeps the
-- references already captured by the tab row descs valid.
local function RebuildMarkerOptionLists()
  if C.DiscoverCombatMarkerImages then C.DiscoverCombatMarkerImages() end
  local clear = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
  clear(IMAGE_OPTIONS)
  for _, e in ipairs(C.COMBAT_MARKER_IMAGE_SYMBOLS or {}) do
    IMAGE_OPTIONS[#IMAGE_OPTIONS + 1] = { value = e.value, text = e.text }
  end
  -- Pressed Indicator: image symbols, then "None" LAST (turns the indicator off).
  clear(PRESSED_SHAPE_OPTIONS)
  for _, o in ipairs(IMAGE_OPTIONS) do PRESSED_SHAPE_OPTIONS[#PRESSED_SHAPE_OPTIONS + 1] = o end
  PRESSED_SHAPE_OPTIONS[#PRESSED_SHAPE_OPTIONS + 1] = { value = "None", text = "None" }
  -- Center Marker: special modes + image symbols + None. The "Assisted Highlight" mode
  -- (value "AHLight") mirrors the AH suggestion, which is retail-only -- drop it on Classic.
  clear(CENTER_MARKER_OPTIONS)
  local ahOK = ns.Caps and ns.Caps.assistedHighlight
  for _, o in ipairs(MYMARKER_OPTIONS) do
    if not (o.value == "AHLight" and not ahOK) then
      CENTER_MARKER_OPTIONS[#CENTER_MARKER_OPTIONS + 1] = o
    end
  end
  for _, o in ipairs(IMAGE_OPTIONS)    do CENTER_MARKER_OPTIONS[#CENTER_MARKER_OPTIONS + 1] = o end
  CENTER_MARKER_OPTIONS[#CENTER_MARKER_OPTIONS + 1] = { value = "None", text = "None" }
end
RebuildMarkerOptionLists()  -- initial best-effort fill; BuildPanel re-runs it post-login
local KEYBIND_ANCHOR_OPTIONS = {
  { value = "TOPLEFT", text = "Top Left" }, { value = "TOPRIGHT", text = "Top Right" },
  { value = "BOTTOMLEFT", text = "Bottom Left" }, { value = "BOTTOMRIGHT", text = "Bottom Right" },
  { value = "CENTER", text = "Center" },
}
local ANCHOR_OPTIONS = {
  { value = "Screen", text = "Screen" }, { value = "Mouse Cursor", text = "Mouse Cursor" },
  -- Value kept as "Target Nameplate" for saved-data compatibility; the option now
  -- anchors the highlight over the target's (round) portrait, hence the label.
  { value = "Target Nameplate", text = "Target Portrait" },
}
local SKIN_OPTIONS = { { value = "NATIVE", text = "Native" }, { value = "MODERN", text = "Modern" } }
local LAYOUT_OPTIONS = { { value = "HORIZONTAL", text = "Horizontal" }, { value = "VERTICAL", text = "Vertical" } }
local OUTLINE_OPTIONS = {
  { value = "NONE", text = "None" },
  { value = "OUTLINE", text = "Outline" },
  { value = "THICKOUTLINE", text = "Thick Outline" },
}
local SCROLL_H_OPTIONS = { { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" } }
local SCROLL_V_OPTIONS = { { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" } }
-- Scroll Direction options depend on the current Layout: horizontal shows Left/
-- Right, vertical shows Down/Up. Evaluated each time the dropdown opens.
local function SCROLL_OPTIONS()
  local layout = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) or "HORIZONTAL"
  if layout == "VERTICAL" then return SCROLL_V_OPTIONS end
  return SCROLL_H_OPTIONS
end
-- True when GSE (the macro compiler) is present, so labels can say "GSE Sequence
-- Name" vs the generic "Macro Name" when it isn't. Checked at row-build time (the
-- settings panel is built lazily, by which point GSE has loaded if installed).
local function IsGSEAvailable()
  if _G.GSE ~= nil then return true end
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "GSE")
    if ok and loaded then return true end
  end
  return false
end

-- The primary name source is GSE's sequence name when GSE is installed, otherwise the
-- plain macro name. These helpers keep the namesource checkbox and the font row label
-- in sync with that.
local function PrimaryNameLabel()
  return IsGSEAvailable() and "GSE Sequence Name" or "Macro Name"
end
local function PrimaryNameFontLabel()
  return PrimaryNameLabel() .. "/Spell Name"
end

local function FontOptions()
  local fonts = (addon.GetFontDropdownList and addon:GetFontDropdownList()) or {
    C.FONT_FRIZ or "Friz Quadrata TT", "Arial Narrow", "Morpheus", "Skurri",
  }
  local list = {}
  for _, f in ipairs(fonts) do list[#list + 1] = { value = f, text = f } end
  if #list == 0 then list[1] = { value = "Friz Quadrata TT", text = "Friz Quadrata TT" } end
  return list
end

-- Short (<1s) built-in Blizzard sounds, referenced by SOUNDKIT name so missing keys
-- are skipped. Stored as "kit:<id>" and played with PlaySound (not PlaySoundFile).
local BLIZZ_SHORT_SOUNDS = {
  { text = "Whisper",        key = "TELL_MESSAGE" },
  { text = "Map Ping",       key = "MAP_PING" },
  { text = "Quest Chime",    key = "IG_QUEST_LIST_COMPLETE" },
  { text = "Checkbox Click", key = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
  { text = "BNet Toast",     key = "UI_BNET_TOAST" },
  { text = "Player Invite",  key = "IG_PLAYER_INVITE" },
  { text = "Auto Quest",     key = "UI_AUTO_QUEST_COMPLETE" },
  { text = "PvP Queue Pop",  key = "PVP_THROUGH_QUEUE" },
  { text = "Auction Open",   key = "AUCTION_WINDOW_OPEN" },
  { text = "Chat Scroll",    key = "U_CHAT_SCROLL_BUTTON" },
  { text = "Ready Check",    key = "READY_CHECK" },
}

-- Built-in short Blizzard sounds first, then everything LibSharedMedia provides.
local function SoundOptions()
  local list = {}
  local SK = _G.SOUNDKIT
  if SK then
    for _, e in ipairs(BLIZZ_SHORT_SOUNDS) do
      local id = SK[e.key]
      if id then list[#list + 1] = { value = "kit:" .. id, text = e.text } end
    end
  end
  local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
  if LSM then
    local names = LSM:List("sound")
    if names then
      -- Skip LSM's own "None" entry -- we add a single "None" at the bottom below.
      for _, n in ipairs(names) do
        if n ~= "None" then list[#list + 1] = { value = n, text = n } end
      end
    end
  end
  -- One "None" LAST (the default -- disables the audible match), after the sounds.
  list[#list + 1] = { value = "None", text = "None" }
  return list
end

-- ── Native widget builders (return height consumed) ────────────────────────
local uid = 0
local function UName(p) uid = uid + 1; return "GSETrackerCanvas" .. p .. uid end

-- Native Blizzard caret dropdown (WowStyle1, modern menu = taint-free).
local function CreateWowDropdown(parent, width, opts, get, set)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetWidth(width)
  dd:SetupMenu(function(dropdown, rootDescription)
    -- opts may be a function so the list can change at open time (e.g. Scroll
    -- Direction options depend on the current Layout).
    local list = (type(opts) == "function") and opts() or opts
    for _, o in ipairs(list or {}) do
      rootDescription:CreateRadio(o.text,
        function() return get() == o.value end,
        function() set(o.value); return MenuResponse and MenuResponse.Close end)
    end
  end)
  return dd
end

-- Shift a row's pane-anchored frames so the row is centered horizontally in the pane.
-- Labels anchored LEFT->RIGHT to those frames follow automatically. rightX is measured
-- after text is set (GetStringWidth), so it accounts for the real label widths. Declared
-- before the renderers so each can see this local.
local function CenterPaneRow(pane, frames, leftX, rightX)
  local paneW = (pane.GetWidth and pane:GetWidth()) or 560
  if not paneW or paneW <= 1 then paneW = 560 end
  local shift = math.floor(((paneW - (rightX - leftX)) * 0.5) - leftX + 0.5)
  if shift == 0 then return end
  for _, f in ipairs(frames) do
    local p, rel, relP, x, fy = f:GetPoint(1)
    if p then
      f:ClearAllPoints()
      f:SetPoint(p, rel, relP, (x or 0) + shift, fy or 0)
    end
  end
end

-- Single colour hook for every checkbox/radio label (the [] toggles). WHITE -- matching
-- the dropdown/slider labels. Change the colour here to restyle all checkable labels at once.
local CHECK_LABEL_COLOR = HIGHLIGHT_FONT_COLOR or { r = 1.0, g = 1.0, b = 1.0 }
local function StyleCheckLabel(fs)
  if fs then fs:SetTextColor(CHECK_LABEL_COLOR.r or 1.0, CHECK_LABEL_COLOR.g or 1.0, CHECK_LABEL_COLOR.b or 1.0) end
  return fs
end

-- Show a GameTooltip on hover: `title` (bold gold) + optional wrapped `body`. Hooked via
-- HookScript so it never clobbers a widget's own OnEnter/OnLeave behaviour. No-op when the
-- frame can't take scripts or there's nothing to show.
local function AttachTooltip(frame, title, body)
  if not (frame and frame.HookScript) then return end
  if (not title or title == "") and (not body or body == "") then return end
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- GameTooltip:SetText(text, r, g, b) -- the 5th arg is ALPHA (a number), NOT wrap, so we
    -- pass only r,g,b here. AddLine's 5th arg IS wrap, so the body wraps correctly.
    if title and title ~= "" then GameTooltip:SetText(title, 1, 0.82, 0) end
    if body and body ~= "" then GameTooltip:AddLine(body, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeHeader(pane, y, desc)
  -- Consistent breathing room ABOVE every section header so gold titles aren't crammed
  -- against the row above (checkbox rows leave no trailing space). Skipped for the very
  -- first row (the tab title, y == -12) so the top of the pane isn't pushed down.
  local topPad = (y < -12) and 10 or 0
  local fs = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, y - topPad)
  fs:SetText(desc.text)
  return 30 + topPad
end

-- Pure vertical gap. Checkbox rows leave almost no trailing space (unlike sliders),
-- so a header placed right after them looks cramped; drop a spacer in to restore
-- the normal gap above the header. desc.h overrides the default height.
local function MakeSpacer(_, _, desc)
  return desc.h or 16
end

local function MakeCheck(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y)
  cb:SetChecked(get() and true or false)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  lbl:SetText(desc.label)
  StyleCheckLabel(lbl)
  AttachTooltip(cb, desc.label, desc.tooltip)
  if desc.center then CenterPaneRow(pane, { cb }, 16, 16 + 26 + 4 + (lbl:GetStringWidth() or 0)) end
  if desc.unavailable and desc.unavailable() then
    cb:Disable(); cb:SetAlpha(0.5)
    if lbl.SetTextColor then lbl:SetTextColor(0.5, 0.5, 0.5) end
    AttachTooltip(cb, desc.label, "Not available on this WoW version.")
  end
  return 28
end

-- Two or three checkboxes side by side on one row (the third is rendered only when
-- desc.get3 is supplied). Even horizontal spacing: each checkbox sits a fixed gap after the
-- PREVIOUS label, so the groups are spaced consistently regardless of label width. Row
-- starts shifted right 20.
local function MakeDualCheck(pane, y, desc)
  local ROW_X, COL_GAP = 36, 24
  local lastLbl = nil
  local function one(getName, setName, label, tip, disableName)
    local get, set = ResolveGet(getName), ResolveSet(setName)
    local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    if lastLbl then
      cb:SetPoint("LEFT", lastLbl, "RIGHT", COL_GAP, 0)
    else
      cb:SetPoint("TOPLEFT", pane, "TOPLEFT", ROW_X, y)
    end
    cb:SetChecked(get() and true or false)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    StyleCheckLabel(lbl)
    AttachTooltip(cb, label, tip)
    lastLbl = lbl
    -- Optional: grey this checkbox out (disabled + dimmed) when another setting makes it
    -- have no effect. Re-evaluated on every panel refresh, so it tracks the dependency live.
    if disableName then
      local disableGet = ResolveGet(disableName)
      activeRefreshers[#activeRefreshers + 1] = function()
        if disableGet() and true or false then
          cb:Disable(); cb:SetAlpha(0.4); lbl:SetAlpha(0.4)
        else
          cb:Enable(); cb:SetAlpha(1); lbl:SetAlpha(1)
        end
      end
    end
  end
  one(desc.get, desc.set, desc.label, desc.tooltip, desc.disable)
  one(desc.get2, desc.set2, desc.label2, desc.tooltip2, desc.disable2)
  if desc.get3 then one(desc.get3, desc.set3, desc.label3, desc.tooltip3, desc.disable3) end
  return 28
end

-- Two checkboxes + a dropdown, all on one row (the Match %, Match Audible, sound).
local function MakeMatchRow(pane, y, desc)
  local frames = {}
  local labels = {}
  local function check(getName, setName, label, x, tip)
    local get, set = ResolveGet(getName), ResolveSet(setName)
    local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", pane, "TOPLEFT", x, y)
    cb:SetChecked(get() and true or false)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    StyleCheckLabel(lbl)
    AttachTooltip(cb, label, tip)
    frames[#frames + 1] = cb
    labels[#labels + 1] = lbl
  end
  check(desc.get, desc.set, desc.label, 36, desc.tooltip)  -- Match % checkbox
  local ddget, ddset = ResolveGet(desc.ddget), ResolveSet(desc.ddset)
  local opts = desc.ddoptions
  local dd = CreateWowDropdown(pane, 220, opts, ddget, ddset)
  dd:SetPoint("TOPLEFT", pane, "TOPLEFT", 290, y - 2)  -- Match Audible group
  AttachTooltip(dd, desc.label2, desc.tooltip2)
  frames[#frames + 1] = dd
  -- "Match Audible" label just before the dropdown; the dropdown's "None" entry disables
  -- the audible match.
  local albl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  albl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
  albl:SetText(desc.label2 or "")
  labels[#labels + 1] = albl
  if desc.center then CenterPaneRow(pane, frames, 26, 310 + 220) end
  if desc.unavailable and desc.unavailable() then
    for i = 1, #frames do
      local fr = frames[i]
      if fr.SetEnabled then fr:SetEnabled(false) elseif fr.Disable then fr:Disable() end
      if fr.SetAlpha then fr:SetAlpha(0.5) end
    end
    for i = 1, #labels do
      if labels[i].SetTextColor then labels[i]:SetTextColor(0.5, 0.5, 0.5) end
    end
    AttachTooltip(dd, desc.label2, "Not available on this WoW version.")
  end
  return 30
end

local function MakeSlider(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  local name = UName("Slider")
  local sliderW = desc.width or 280  -- single-row sliders are wide (their own line)
  local s = CreateFrame("Slider", name, pane, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", pane, "TOPLEFT", 20, y - 16)
  s:SetWidth(sliderW)
  s:SetMinMaxValues(desc.min, desc.max)
  s:SetValueStep(desc.step)
  s:SetObeyStepOnDrag(true)
  local low, high, title = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
  if low then low:SetText("") end
  if high then high:SetText("") end
  if title then title:SetText(desc.label) end
  local val = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  val:SetPoint("LEFT", s, "RIGHT", 10, 0)
  local function fmt(v)
    if desc.float then return string.format("%.2f", v or 0) end
    return tostring(math.floor((v or 0) + 0.5))
  end
  local cur = tonumber(get()) or desc.min
  s:SetValue(cur)
  val:SetText(fmt(cur))
  s:SetScript("OnValueChanged", function(self, v, userInput)
    if not desc.float then v = math.floor(v + 0.5) end
    val:SetText(fmt(v))
    if userInput then set(v) end
  end)
  AttachTooltip(s, desc.label, desc.tooltip)
  if desc.center then
    CenterPaneRow(pane, { s }, 20, 20 + sliderW + 10 + (val:GetStringWidth() or 0))
  end
  return 50
end

local function MakeDropdown(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  local opts = desc.options
  if type(opts) == "function" then opts = opts() end
  local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl:SetPoint("TOPLEFT", pane, "TOPLEFT", 18, y)
  lbl:SetText(desc.label)
  local dd = CreateWowDropdown(pane, 220, opts, get, set)
  dd:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y - 18)
  AttachTooltip(dd, desc.label, desc.tooltip)
  if desc.center then CenterPaneRow(pane, { dd, lbl }, 16, 16 + 220) end
  if desc.unavailable and desc.unavailable() then
    if dd.SetEnabled then dd:SetEnabled(false) end
    if lbl.SetTextColor then lbl:SetTextColor(0.5, 0.5, 0.5) end
    AttachTooltip(dd, desc.label, "Not available on this WoW version.")
  end
  return 46
end

-- A dropdown with a checkbox after it on the SAME row (e.g. Center Marker + Show GCD).
local function MakeDropdownCheck(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  local opts = desc.options
  if type(opts) == "function" then opts = opts() end
  local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl:SetPoint("TOPLEFT", pane, "TOPLEFT", 18, y)
  lbl:SetText(desc.label)
  local dd = CreateWowDropdown(pane, 220, opts, get, set)
  dd:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y - 18)
  AttachTooltip(dd, desc.label, desc.tooltip)

  local cget, cset = ResolveGet(desc.checkGet), ResolveSet(desc.checkSet)
  local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb:SetPoint("LEFT", dd, "RIGHT", 12, 0)
  cb:SetChecked(cget() and true or false)
  cb:SetScript("OnClick", function(self) cset(self:GetChecked() and true or false) end)
  local clbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  clbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  clbl:SetText(desc.checkLabel or "")
  StyleCheckLabel(clbl)
  AttachTooltip(cb, desc.checkLabel, desc.tooltip2)
  return 46
end

-- Two dropdowns side by side on one row (e.g. Layout + Scroll Direction). The
-- second dropdown's options may be a function (dynamic), and changing the first
-- refreshes the second (so Scroll Direction tracks Layout live).
local function MakeDualDropdown(pane, y, desc)
  local dd2
  local get1, set1raw = ResolveGet(desc.get), ResolveSet(desc.set)
  local set1 = function(v)
    set1raw(v)
    if dd2 and dd2.GenerateMenu then dd2:GenerateMenu() end -- refresh dependent dropdown
  end
  local lbl1 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl1:SetPoint("TOPLEFT", pane, "TOPLEFT", 18, y)
  lbl1:SetText(desc.label)
  local dd1 = CreateWowDropdown(pane, 220, desc.options, get1, set1)
  dd1:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y - 18)
  AttachTooltip(dd1, desc.label, desc.tooltip)

  local get2, set2 = ResolveGet(desc.get2), ResolveSet(desc.set2)
  local lbl2 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl2:SetPoint("TOPLEFT", pane, "TOPLEFT", 290, y)
  lbl2:SetText(desc.label2)
  -- Pass options2 through as-is (may be a function) so it re-evaluates on open.
  dd2 = CreateWowDropdown(pane, 220, desc.options2, get2, set2)
  dd2:SetPoint("TOPLEFT", pane, "TOPLEFT", 288, y - 18)
  AttachTooltip(dd2, desc.label2, desc.tooltip2)
  if desc.center then CenterPaneRow(pane, { dd1, dd2, lbl1, lbl2 }, 16, 288 + 200) end
  return 46
end

local function MakeDropdownSlider(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  -- Pass options through as-is (may be a function) so the dropdown RE-EVALUATES it
  -- each time it opens -- e.g. Scroll Direction's Left/Right vs Up/Down depends on the
  -- current Layout, which can change after this row is built. (Pre-evaluating here
  -- locked the choices to the Layout at build time -> Vertical still showed Left/Right.)
  local opts = desc.options
  local dlbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  dlbl:SetPoint("TOPLEFT", pane, "TOPLEFT", 18, y)
  dlbl:SetText(desc.label)
  -- 220 to match the plain dropdown width (MakeDropdown) so e.g. the Keybind "Font"
  -- and "Location" dropdowns line up. The Size slider sits at x=290, well clear.
  local dd = CreateWowDropdown(pane, 220, opts, get, set)
  dd:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y - 18)
  AttachTooltip(dd, desc.label, desc.tooltip)

  local sget, sset = ResolveGet(desc.sliderGet), ResolveSet(desc.sliderSet)
  local name = UName("Slider")
  local s = CreateFrame("Slider", name, pane, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", pane, "TOPLEFT", 290, y - 16)
  s:SetWidth(150)
  s:SetMinMaxValues(desc.smin, desc.smax)
  s:SetValueStep(desc.sstep)
  s:SetObeyStepOnDrag(true)
  local low, high, title = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
  if low then low:SetText("") end
  if high then high:SetText("") end
  if title then title:SetText(desc.sliderLabel or "Size") end
  local val = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  val:SetPoint("LEFT", s, "RIGHT", 8, 0)
  local function fmt(v)
    if desc.sfloat then return string.format("%.2f", v or 0) end
    return tostring(math.floor((v or 0) + 0.5))
  end
  local cur = tonumber(sget()) or desc.smin
  s:SetValue(cur)
  val:SetText(fmt(cur))
  s:SetScript("OnValueChanged", function(self, v, userInput)
    if not desc.sfloat then v = math.floor(v + 0.5) end
    val:SetText(fmt(v))
    if userInput then sset(v) end
  end)
  AttachTooltip(s, desc.sliderLabel or "Size", desc.tooltip2 or desc.tooltip)
  -- Keep this dropdown's options/text live when another control changes it (e.g. Scroll
  -- Direction's choices depend on Layout): regenerate the menu on every refresh.
  if desc.refreshDropdown then
    activeRefreshers[#activeRefreshers + 1] = function()
      if dd and dd.GenerateMenu then dd:GenerateMenu() end
    end
  end
  if desc.center then CenterPaneRow(pane, { dd, dlbl, s }, 16, 290 + 150 + 8 + (val:GetStringWidth() or 0)) end
  if desc.unavailable and desc.unavailable() then
    if dd.SetEnabled then dd:SetEnabled(false) end
    if s.SetEnabled then s:SetEnabled(false) elseif s.Disable then s:Disable() end
    if dlbl.SetTextColor then dlbl:SetTextColor(0.5, 0.5, 0.5) end
    if title and title.SetTextColor then title:SetTextColor(0.5, 0.5, 0.5) end
    if val.SetTextColor then val:SetTextColor(0.5, 0.5, 0.5) end
    AttachTooltip(dd, desc.label, "Not available on this WoW version.")
  end
  return 50
end

local function MakeEnableShow(pane, y, desc)
  local eget, eset = ResolveGet(desc.get), ResolveSet(desc.set)
  local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y)
  cb:SetChecked(eget() and true or false)
  cb:SetScript("OnClick", function(self)
    eset(self:GetChecked() and true or false)
    -- Update the tab grey-out immediately (a tracker tab greys when disabled).
    if RefreshTabStates then RefreshTabStates() end
  end)
  local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  lbl:SetText(desc.label)
  StyleCheckLabel(lbl)
  AttachTooltip(cb, desc.label, desc.tooltip)

  local sget, sset = ResolveGet(desc.showGet), ResolveSet(desc.showSet)
  local dd = CreateWowDropdown(pane, 220, desc.showOptions, sget, sset)
  dd:SetPoint("LEFT", cb, "RIGHT", 180, 0)
  AttachTooltip(dd, "Show When", desc.tooltip2 or "When this element is visible: Always, only In Combat, only when you have a Harm Target, or Never.")
  -- Optional column header drawn above this dropdown (set on the top row to label the
  -- whole show-when column).
  if desc.showHeader then
    local sh = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sh:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 2, 5)
    sh:SetText(desc.showHeader)
    sh:SetTextColor(1, 1, 1)
  end
  -- Grey out + lock the row when the feature isn't available on this WoW version.
  if desc.unavailable and desc.unavailable() then
    if cb.SetEnabled then cb:SetEnabled(false) else cb:Disable() end
    if dd.SetEnabled then dd:SetEnabled(false) end
    if lbl.SetTextColor then lbl:SetTextColor(0.5, 0.5, 0.5) end
    local why = "Not available on this WoW version."
    AttachTooltip(cb, desc.label, why)
    AttachTooltip(dd, desc.label, why)
  end
  return 40
end

local function MakeColor(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  local btn = CreateFrame("Button", nil, pane)
  btn:SetSize(20, 20)
  btn:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y)
  local border = btn:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0, 0, 0, 1)
  local sw = btn:CreateTexture(nil, "ARTWORK")
  sw:SetAllPoints(btn)
  local function paint() local r, g, b = get(); sw:SetColorTexture(r or 1, g or 1, b or 1) end
  paint()
  local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lbl:SetPoint("LEFT", btn, "RIGHT", 6, 0)
  lbl:SetText(desc.label)
  btn:SetScript("OnClick", function()
    local r, g, b = get()
    r, g, b = r or 1, g or 1, b or 1
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); set(nr, ng, nb); paint() end,
        cancelFunc = function() set(r, g, b); paint() end,
        hasOpacity = false, r = r, g = g, b = b,
      })
    end
  end)
  AttachTooltip(btn, desc.label, desc.tooltip)
  return 28
end

-- Tri-state colour-source row: two mutually-exclusive checkboxes (Class Color / Custom
-- Color) that can BOTH be off (= no colour / no tint), plus a colour swatch for the custom
-- colour. desc.get/set read+write a MODE string ("none"/"class"/"custom"); colorGet/colorSet
-- the custom RGB. Clicking the active box turns it off (back to "none"). The swatch is
-- interactive only while Custom is selected.
local function MakeTriColor(pane, y, desc)
  local modeGet, modeSet = ResolveGet(desc.get), ResolveSet(desc.set)
  local colorGet, colorSet = ResolveGet(desc.colorGet), ResolveSet(desc.colorSet)
  local cbClass, cbCustom, btn, sw

  local function refresh()
    local mode = modeGet()
    cbClass:SetChecked(mode == "class")
    cbCustom:SetChecked(mode == "custom")
    if btn then
      if mode == "custom" then
        btn:Enable(); sw:SetDesaturated(false); btn:SetAlpha(1)
      else
        btn:Disable(); sw:SetDesaturated(true); btn:SetAlpha(0.4)
      end
    end
  end

  -- Even horizontal spacing: each control sits a fixed gap after the PREVIOUS label, so the
  -- groups are spaced consistently regardless of label width. Row starts shifted right 20.
  local ROW_X, COL_GAP = 36, 24
  local prevLabel = nil

  -- Optional leading checkbox (e.g. "Lock") before the Class/Custom choice.
  if desc.leadLabel then
    local lget, lset = ResolveGet(desc.leadGet), ResolveSet(desc.leadSet)
    local lcb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    lcb:SetSize(26, 26)
    lcb:SetPoint("TOPLEFT", pane, "TOPLEFT", ROW_X, y)
    lcb:SetChecked(lget() and true or false)
    lcb:SetScript("OnClick", function(self) lset(self:GetChecked() and true or false) end)
    local llbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    llbl:SetPoint("LEFT", lcb, "RIGHT", 4, 0)
    llbl:SetText(desc.leadLabel)
    StyleCheckLabel(llbl)
    AttachTooltip(lcb, desc.leadLabel, desc.tooltipLead)
    prevLabel = llbl
  end

  cbClass = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbClass:SetSize(26, 26)
  if prevLabel then
    cbClass:SetPoint("LEFT", prevLabel, "RIGHT", COL_GAP, 0)
  else
    cbClass:SetPoint("TOPLEFT", pane, "TOPLEFT", ROW_X, y)
  end
  local lblClass = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lblClass:SetPoint("LEFT", cbClass, "RIGHT", 4, 0)
  lblClass:SetText(desc.label or "Class Color")
  StyleCheckLabel(lblClass)
  AttachTooltip(cbClass, desc.label or "Class Color", desc.tooltip)
  cbClass:SetScript("OnClick", function() modeSet(modeGet() == "class" and "none" or "class"); refresh() end)

  cbCustom = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbCustom:SetSize(26, 26)
  cbCustom:SetPoint("LEFT", lblClass, "RIGHT", COL_GAP, 0)
  cbCustom:SetScript("OnClick", function() modeSet(modeGet() == "custom" and "none" or "custom"); refresh() end)
  AttachTooltip(cbCustom, desc.label2 or "Custom Color", desc.tooltip2)

  -- Swatch sits BETWEEN the checkbox and its label:  [ ] [swatch] Custom Color
  btn = CreateFrame("Button", nil, pane)
  btn:SetSize(20, 20)
  btn:SetPoint("LEFT", cbCustom, "RIGHT", 6, 0)
  local border = btn:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0, 0, 0, 1)
  sw = btn:CreateTexture(nil, "ARTWORK")
  sw:SetAllPoints(btn)
  local function paint() local r, g, b = colorGet(); sw:SetColorTexture(r or 1, g or 1, b or 1) end
  paint()
  btn:SetScript("OnClick", function()
    local r, g, b = colorGet()
    r, g, b = r or 1, g or 1, b or 1
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); colorSet(nr, ng, nb); paint() end,
        cancelFunc = function() colorSet(r, g, b); paint() end,
        hasOpacity = false, r = r, g = g, b = b,
      })
    end
  end)
  AttachTooltip(btn, desc.label2 or "Custom Color", desc.tooltip2)

  local lblCustom = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  -- Same 6px gap swatch->label as checkbox->swatch above, so the spacing is even.
  lblCustom:SetPoint("LEFT", btn, "RIGHT", 6, 0)
  lblCustom:SetText(desc.label2 or "Custom")
  StyleCheckLabel(lblCustom)

  refresh()
  return 30
end

-- A mutually-exclusive colour-source choice on one row: two checkboxes that act
-- as radio buttons (Class Color OR Custom Color, never both) plus a colour swatch
-- for the custom colour, e.g.
--   "[ ] Symbol: Class Color   [x] Symbol: Custom Color   [swatch]".
-- Both checkboxes are views of a single boolean (desc.get/set = "use class
-- color"): "Class" checked == true, "Custom" checked == false. The swatch is
-- greyed (non-interactive) while Class Color is active, since it has no effect then.
local function MakeCheckColor(pane, y, desc)
  local useGet, useSet = ResolveGet(desc.get), ResolveSet(desc.set)
  local get, set = ResolveGet(desc.colorGet), ResolveSet(desc.colorSet)
  local cbClass, cbCustom, btn, sw

  local function refresh()
    local useClass = useGet() and true or false
    cbClass:SetChecked(useClass)
    cbCustom:SetChecked(not useClass)
    if btn then
      if useClass then
        btn:Disable(); sw:SetDesaturated(true); btn:SetAlpha(0.4)
      else
        btn:Enable(); sw:SetDesaturated(false); btn:SetAlpha(1)
      end
    end
  end

  -- Optional leading checkbox (e.g. "Show GCD") rendered before the Class/Custom choice;
  -- when present the colour controls shift right to make room.
  local classX, customX, swatchX = 16, 190, 360
  if desc.leadLabel then
    classX, customX, swatchX = 150, 300, 450
    local lget, lset = ResolveGet(desc.leadGet), ResolveSet(desc.leadSet)
    local lcb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    lcb:SetSize(26, 26)
    lcb:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y)
    lcb:SetChecked(lget() and true or false)
    lcb:SetScript("OnClick", function(self) lset(self:GetChecked() and true or false) end)
    local llbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    llbl:SetPoint("LEFT", lcb, "RIGHT", 4, 0)
    llbl:SetText(desc.leadLabel)
    StyleCheckLabel(llbl)
    AttachTooltip(lcb, desc.leadLabel, desc.tooltipLead)
  end

  cbClass = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbClass:SetSize(26, 26)
  cbClass:SetPoint("TOPLEFT", pane, "TOPLEFT", classX, y)
  local lblClass = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lblClass:SetPoint("LEFT", cbClass, "RIGHT", 4, 0)
  lblClass:SetText(desc.label)
  StyleCheckLabel(lblClass)
  AttachTooltip(cbClass, desc.label, desc.tooltip)
  cbClass:SetScript("OnClick", function() useSet(true); refresh() end)

  cbCustom = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbCustom:SetSize(26, 26)
  cbCustom:SetPoint("TOPLEFT", pane, "TOPLEFT", customX, y)
  local lblCustom = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lblCustom:SetPoint("LEFT", cbCustom, "RIGHT", 4, 0)
  lblCustom:SetText(desc.label2 or "Custom Color")
  StyleCheckLabel(lblCustom)
  AttachTooltip(cbCustom, desc.label2 or "Custom Color", desc.tooltip2)
  cbCustom:SetScript("OnClick", function() useSet(false); refresh() end)

  btn = CreateFrame("Button", nil, pane)
  btn:SetSize(20, 20)
  btn:SetPoint("TOPLEFT", pane, "TOPLEFT", swatchX, y - 3)
  local border = btn:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0, 0, 0, 1)
  sw = btn:CreateTexture(nil, "ARTWORK")
  sw:SetAllPoints(btn)
  local function paint() local r, g, b = get(); sw:SetColorTexture(r or 1, g or 1, b or 1) end
  paint()
  btn:SetScript("OnClick", function()
    local r, g, b = get()
    r, g, b = r or 1, g or 1, b or 1
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); set(nr, ng, nb); paint() end,
        cancelFunc = function() set(r, g, b); paint() end,
        hasOpacity = false, r = r, g = g, b = b,
      })
    end
  end)
  AttachTooltip(btn, desc.label2 or "Custom Color", desc.tooltip2)

  if desc.center then
    CenterPaneRow(pane, { cbClass, cbCustom, btn }, 16, 360 + 20)
  end
  refresh()
  return 30
end

-- Two mutually-exclusive checkboxes (radio: get/set is a boolean -- unchecked-first /
-- checked-second view) plus an optional independent third checkbox, all on one row.
-- Used for the name source (GSE Sequence Name | Spell Name) + the Modkey Side toggle.
local function MakeNameSourceRow(pane, y, desc)
  local useGet, useSet = ResolveGet(desc.get), ResolveSet(desc.set)
  -- Optional "shown at all" dimension: when enabledGet/Set are supplied the two boxes
  -- become tri-state -- pick a source (mutually exclusive) OR uncheck the active one to
  -- turn the name OFF entirely (neither box checked). Without them it's a plain radio.
  local enGet = desc.enabledGet and ResolveGet(desc.enabledGet) or nil
  local enSet = desc.enabledSet and ResolveSet(desc.enabledSet) or nil
  local function isShown() return (not enGet) or (enGet() and true or false) end
  local cbA, cbB
  local function refresh()
    local b = useGet() and true or false
    local on = isShown()
    cbA:SetChecked(on and not b)
    cbB:SetChecked(on and b)
  end
  -- Clicking a box: if it's already the active choice, uncheck it (hide the name); else
  -- make it the active source and ensure the name is shown.
  local function pick(useSpell)
    if enSet then
      if isShown() and ((useGet() and true or false) == useSpell) then
        enSet(false)            -- toggling the active source off -> name hidden
        refresh()
        return
      end
      enSet(true)
    end
    useSet(useSpell)
    refresh()
  end

  -- Even horizontal spacing: each checkbox sits a fixed gap after the PREVIOUS label, so
  -- the groups are spaced consistently regardless of label width. Row shifted right 20.
  local ROW_X, COL_GAP = 36, 24

  cbA = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbA:SetSize(26, 26)
  cbA:SetPoint("TOPLEFT", pane, "TOPLEFT", ROW_X, y)
  local lA = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lA:SetPoint("LEFT", cbA, "RIGHT", 4, 0)
  lA:SetText(desc.label)
  StyleCheckLabel(lA)
  AttachTooltip(cbA, desc.label, desc.tooltip)
  cbA:SetScript("OnClick", function() pick(false) end)

  cbB = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbB:SetSize(26, 26)
  cbB:SetPoint("LEFT", lA, "RIGHT", COL_GAP, 0)
  local lB = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lB:SetPoint("LEFT", cbB, "RIGHT", 4, 0)
  lB:SetText(desc.label2 or "")
  StyleCheckLabel(lB)
  AttachTooltip(cbB, desc.label2, desc.tooltip2)
  cbB:SetScript("OnClick", function() pick(true) end)
  refresh()

  local frames, lastX, lastLbl = { cbA, cbB }, 190, lB
  if desc.get3 then
    local g3, s3 = ResolveGet(desc.get3), ResolveSet(desc.set3)
    local cb3 = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    cb3:SetSize(26, 26)
    cb3:SetPoint("LEFT", lB, "RIGHT", COL_GAP, 0)
    cb3:SetChecked(g3() and true or false)
    cb3:SetScript("OnClick", function(self) s3(self:GetChecked() and true or false) end)
    local l3 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    l3:SetPoint("LEFT", cb3, "RIGHT", 4, 0)
    l3:SetText(desc.label3 or "")
    StyleCheckLabel(l3)
    AttachTooltip(cb3, desc.label3, desc.tooltip3)
    frames[#frames + 1] = cb3; lastX = 340; lastLbl = l3
  end
  if desc.center then
    CenterPaneRow(pane, frames, 16, lastX + 26 + 4 + ((lastLbl and lastLbl:GetStringWidth()) or 0))
  end
  return 28
end

local function MakeSocial(pane, y)
  local f = CreateFrame("Frame", nil, pane, "GSETrackerSocialTemplate")
  f:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
  f:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
  return 56
end

-- Create a labelled slider at an explicit x (used for side-by-side rows).
local function CreateSliderAt(pane, x, y, width, labelText, get, set, minV, maxV, step, float)
  local name = UName("Slider")
  local s = CreateFrame("Slider", name, pane, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", pane, "TOPLEFT", x, y - 16)
  s:SetWidth(width)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  local low, high, title = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
  if low then low:SetText("") end
  if high then high:SetText("") end
  if title then title:SetText(labelText) end
  local val = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  val:SetPoint("LEFT", s, "RIGHT", 8, 0)
  local function fmt(v)
    if float then return string.format("%.2f", v or 0) end
    return tostring(math.floor((v or 0) + 0.5))
  end
  local cur = tonumber(get()) or minV
  s:SetValue(cur)
  val:SetText(fmt(cur))
  s:SetScript("OnValueChanged", function(self, v, userInput)
    if not float then v = math.floor(v + 0.5) end
    val:SetText(fmt(v))
    if userInput then set(v) end
  end)
  return s, val, title
end

-- Grey out / re-enable a slider built by CreateSliderAt (slider + value + title text).
local function SetSliderEnabled(s, val, title, enabled)
  if not s then return end
  if enabled then
    if s.Enable then s:Enable() end
    s:SetAlpha(1)
    if val then val:SetAlpha(1) end
    if title then title:SetAlpha(1) end
  else
    if s.Disable then s:Disable() end
    s:SetAlpha(0.4)
    if val then val:SetAlpha(0.4) end
    if title then title:SetAlpha(0.4) end
  end
end

-- Two sliders side by side on one row. An optional desc.disableGet (method name or
-- function returning true) greys out the FIRST slider when its value is controlled
-- automatically (e.g. AH Scale while Target Portrait auto-sizes to the portrait).
local function MakeDualSlider(pane, y, desc)
  local s1, v1, t1 = CreateSliderAt(pane, 20, y, 150, desc.label, ResolveGet(desc.get), ResolveSet(desc.set), desc.min, desc.max, desc.step, desc.float)
  local s2, v2 = CreateSliderAt(pane, 300, y, 150, desc.label2, ResolveGet(desc.get2), ResolveSet(desc.set2), desc.min2, desc.max2, desc.step2, desc.float2)
  AttachTooltip(s1, desc.label, desc.tooltip)
  AttachTooltip(s2, desc.label2, desc.tooltip2)
  if desc.disableGet then
    local disableGet = ResolveGet(desc.disableGet)
    activeRefreshers[#activeRefreshers + 1] = function()
      SetSliderEnabled(s1, v1, t1, not (disableGet() and true or false))
    end
  end
  if desc.center then CenterPaneRow(pane, { s1, s2 }, 20, 300 + 150 + 8 + ((v2 and v2:GetStringWidth()) or 0)) end
  return 50
end

-- Border row: [check] Border  [check] Class Color  [swatch] Border Color.
local function MakeBorderRow(pane, y, desc)
  local g1, s1 = ResolveGet(desc.get), ResolveSet(desc.set)
  local cb1 = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cb1:SetSize(26, 26)
  cb1:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y)
  cb1:SetChecked(g1() and true or false)
  cb1:SetScript("OnClick", function(self) s1(self:GetChecked() and true or false) end)
  local l1 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  l1:SetPoint("LEFT", cb1, "RIGHT", 4, 0)
  l1:SetText(desc.label)
  StyleCheckLabel(l1)

  local g2, s2 = ResolveGet(desc.classGet), ResolveSet(desc.classSet)
  local cb2 = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cb2:SetSize(26, 26)
  cb2:SetPoint("TOPLEFT", pane, "TOPLEFT", 150, y)
  cb2:SetChecked(g2() and true or false)
  cb2:SetScript("OnClick", function(self) s2(self:GetChecked() and true or false) end)
  local l2 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  l2:SetPoint("LEFT", cb2, "RIGHT", 4, 0)
  l2:SetText(desc.classLabel or "Class Color")
  StyleCheckLabel(l2)

  local g3, s3 = ResolveGet(desc.colorGet), ResolveSet(desc.colorSet)
  local btn = CreateFrame("Button", nil, pane)
  btn:SetSize(20, 20)
  btn:SetPoint("TOPLEFT", pane, "TOPLEFT", 320, y - 3)
  local bd = btn:CreateTexture(nil, "BACKGROUND")
  bd:SetPoint("TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", 1, -1); bd:SetColorTexture(0, 0, 0, 1)
  local sw = btn:CreateTexture(nil, "ARTWORK")
  sw:SetAllPoints(btn)
  local function paint() local r, g, b = g3(); sw:SetColorTexture(r or 1, g or 1, b or 1) end
  paint()
  local l3 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  l3:SetPoint("LEFT", btn, "RIGHT", 6, 0)
  l3:SetText(desc.colorLabel or "Border Color")
  btn:SetScript("OnClick", function()
    local r, g, b = g3()
    r, g, b = r or 1, g or 1, b or 1
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); s3(nr, ng, nb); paint() end,
        cancelFunc = function() s3(r, g, b); paint() end,
        hasOpacity = false, r = r, g = g, b = b,
      })
    end
  end)
  return 30
end

local RENDERERS = {
  header = MakeHeader, check = MakeCheck, slider = MakeSlider, dropdown = MakeDropdown,
  color = MakeColor, enableshow = MakeEnableShow, dropdownslider = MakeDropdownSlider,
  dualslider = MakeDualSlider, borderrow = MakeBorderRow, dualdropdown = MakeDualDropdown,
  dualcheck = MakeDualCheck, matchrow = MakeMatchRow, checkcolor = MakeCheckColor,
  spacer = MakeSpacer, namesource = MakeNameSourceRow, dropdowncheck = MakeDropdownCheck,
  tricolor = MakeTriColor,
}

-- When a tab requests centered content, ONLY slider rows are centered; everything else
-- (dropdowns, checkboxes, color, headers, ...) stays left-aligned as normal.
local CENTER_TYPES = { slider = true, dualslider = true }

local function Populate(pane, rows, center)
  -- NOTE: do NOT wipe activeRefreshers here -- every tab's pane is populated once during
  -- BuildPanel, so wiping per-pane would discard earlier tabs' refreshers (e.g. the AH
  -- Scale grey-out). The list is wiped once in BuildPanel; refreshers accumulate across
  -- all tabs and persist for the panel's lifetime.
  local y = -12
  for _, r in ipairs(rows) do
    -- Tab-level centering: ONLY slider rows center; everything else stays left.
    if center and CENTER_TYPES[r.type] then r.center = true end
    local consumed
    if r.type == "social" then
      consumed = MakeSocial(pane, y)
    else
      local fn = RENDERERS[r.type]
      consumed = fn and fn(pane, y, r) or 0
    end
    y = y - (consumed or 0)
  end
  pane:SetHeight(math.max(-y + 12, 1))
  RunRefreshers() -- set initial enabled/greyed states
end

-- Build-time grey-out of an ENTIRE tab pane when its feature is unavailable on this client
-- (e.g. Assisted Highlight on Classic -- no C_AssistedCombat). Disables every interactive
-- child and dims label text. Runs during BuildPanel (before the canvas is registered), so it
-- never mutates a live Settings canvas (no taint).
local function GreyOutPane(pane)
  if not pane then return end
  local function walk(fr)
    local kids = { fr:GetChildren() }
    for i = 1, #kids do
      local c = kids[i]
      if c.SetEnabled then c:SetEnabled(false) elseif c.Disable then pcall(c.Disable, c) end
      if c.EnableMouse then c:EnableMouse(false) end
      walk(c)
    end
    local regions = { fr:GetRegions() }
    for i = 1, #regions do
      local r = regions[i]
      if r.SetTextColor then r:SetTextColor(0.5, 0.5, 0.5) end
    end
  end
  walk(pane)
end

-- ── Tab content ─────────────────────────────────────────────────────────────
local function GeneralRows()
  return {
    { type = "header", text = "General" },
    { type = "check", label = "Lock All",
      get = function()
        return CallGet("IsLocked") and CallGet("GetCombatMarkerLocked") and CallGet("GetAssistedHighlightLocked") and true or false
      end,
      set = function(v)
        if addon.SetLocked then addon:SetLocked(v) end
        if addon.SetCombatMarkerLocked then addon:SetCombatMarkerLocked(v) end
        if addon.SetAssistedHighlightLocked then addon:SetAssistedHighlightLocked(v) end
        -- The Meters frame follows the same lock (its own Locked Frame box is removed).
        if _G.MetersSavedVars then _G.MetersSavedVars.locked = v and true or false end
        if _G.Meter_SetLocked then _G.Meter_SetLocked(v and true or false) end
      end,
      tooltip = "Lock or unlock every GSE: Tracker frame at once (Meters, Player Marker, Assisted Highlight, Action Tracker). Unlock to drag them into place." },
    { type = "check", label = "Performance Mode", get = "GetPerformanceModeEnabled", set = "SetPerformanceModeEnabledCanonical",
      tooltip = "Reduce how often the tracker updates to lower CPU use. Slightly less responsive; helps on low-end systems or in big group content." },
    { type = "check", label = "Show Minimap Button",
      get = function() return not (addon.GetMinimapHidden and addon:GetMinimapHidden()) end,
      set = function(v) if addon.SetMinimapHidden then addon:SetMinimapHidden(not v) end end,
      tooltip = "Show or hide the GSE: Tracker minimap button." },
    { type = "check", label = "Hide Login Message",
      get = "GetHideLoginMessage", set = "SetHideLoginMessage",
      tooltip = "Stop showing the GSE: Tracker welcome window each time you log in." },
    { type = "header", text = "Enable" },
    { type = "enableshow", label = "Meters", showHeader = "Visibility", tooltip = "Enable the Meters cluster. On Classic only the Center Marker is available (DPS/HPS/GCD/Details need retail APIs).",
      get = function() return _G.MetersSavedVars and _G.MetersSavedVars.enabled ~= false end,
      set = function(v)
        if _G.MetersSavedVars then _G.MetersSavedVars.enabled = v and true or false end
        if _G.Meter_UpdateVisibility then _G.Meter_UpdateVisibility() end
      end,
      showGet = function() return (_G.MetersSavedVars and _G.MetersSavedVars.showWhen) or "Always" end,
      showSet = function(v)
        if _G.MetersSavedVars then _G.MetersSavedVars.showWhen = v end
        if _G.Meter_UpdateVisibility then _G.Meter_UpdateVisibility() end
      end,
      showOptions = METERS_SHOW_OPTIONS },
    -- Player Marker has no separate Enable/Show row: it is pinned to the Meters centre and
    -- follows the Meters frame's visibility (see UI:ShouldShowCombatMarker).
    { type = "enableshow", label = "Assisted Highlight", get = "IsAssistedHighlightMirrorEnabled", set = "SetAssistedHighlightMirrorEnabled",
      unavailable = function() return not (ns.Caps and ns.Caps.assistedHighlight) end,
      tooltip = "Enable the Assisted Highlight icon that shows the next suggested ability.",
      showGet = "GetAssistedHighlightShowWhen", showSet = "SetAssistedHighlightShowWhen", showOptions = SHOW_OPTIONS },
    { type = "enableshow", label = "Action Tracker", get = "IsEnabled", set = "SetEnabled",
      tooltip = "Enable the Action Tracker — the row of upcoming/recent ability icons.",
      showGet = "GetShowWhen", showSet = "SetShowWhen", showOptions = SHOW_OPTIONS },
    { type = "header", text = "Skin" },
    -- Checked = force Blizzard Native over any skinner. Unchecked = adopt the
    -- skinner (ElvUI/EllesmereUI...) if installed, else Native automatically.
    { type = "check", label = "Force Blizzard Native Skin",
      get = function() return addon.GetSkin and addon:GetSkin() == "NATIVE" end,
      set = function(v)
        if addon.SetSkin then addon:SetSkin(v and "NATIVE" or "AUTO") end
        -- Re-skin the tracker live so the border switches immediately (no /reload): rebuild
        -- the Action Tracker icons + re-apply the border art, and re-render the Assisted
        -- Highlight (both read uiShared.GetActionButtonBorder, which resolves Native vs the
        -- adopted skinner). The options-window widget palette still finishes on /reload.
        if addon.RebuildIcons then addon:RebuildIcons(true) end
        if addon.ApplyBorderThickness then addon:ApplyBorderThickness() end
        if addon.ApplyFontFaces then addon:ApplyFontFaces() end
        if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
        -- Meters (Details / DPS / HPS / GCD) auto-adopt the same font face; restyle
        -- them live too so the switch is immediate (no /reload).
        if _G.Meter_ApplyFont then _G.Meter_ApplyFont() end
        if _G.RefreshDetails then _G.RefreshDetails() end
      end,
      tooltip = "Force Blizzard's native button art (border, icon crop and FONT style). Unchecked: automatically adopt your skin addon (ElvUI, EllesmereUI, ...) if one is installed." },
    -- (Social icons are no longer an in-flow row -- they live in a persistent footer
    -- pinned to the bottom of the whole settings frame; see BuildPanel.)
  }
end

local function ActionTrackerRows()
  return {
    { type = "header", text = "Action Tracker" },
    { type = "header", text = "Display" },
    -- 2x2 grid: dropdown (left) + slider (right) per row.
    { type = "dropdownslider",
      label = "Layout", get = "GetActionTrackerLayout", set = "SetActionTrackerLayout", options = LAYOUT_OPTIONS,
      tooltip = "Lay the ability icons out horizontally or vertically.",
      sliderLabel = "Icon Count", sliderGet = "GetIconCount", sliderSet = "SetIconCount",
      tooltip2 = "How many ability icons the tracker shows.",
      smin = C.MIN_ICON_COUNT or 4, smax = C.MAX_ICON_COUNT or 8, sstep = 1 },
    { type = "dropdownslider",
      label = "Scroll Direction", get = "GetActionTrackerScroll", set = "SetActionTrackerScroll", options = SCROLL_OPTIONS, refreshDropdown = true,
      tooltip = "Which direction new icons scroll in as the rotation advances.",
      sliderLabel = "Icon Spacing", sliderGet = "GetIconGap", sliderSet = "SetIconGap",
      tooltip2 = "Gap between icons, in pixels.",
      smin = 0, smax = 5, sstep = 1 },
    -- Border options removed: the icon border now always adopts the player's
    -- action-bar frame art (Blizzard default or skinner), like the rest of the UI.
    { type = "namesource",
      label = PrimaryNameLabel(), get = "GetActionTrackerUseSpellName", set = "SetActionTrackerUseSpellName",
      tooltip = "Use the GSE sequence's name as the tracker title. Click again to hide the name entirely.",
      label2 = "Spell Name",
      tooltip2 = "Use the most recently cast spell's name as the tracker title. Click again to hide the name entirely.",
      tooltip3 = "Show the L/R side prefix on modifier keys (e.g. 'LShift+RCtrl' vs 'Shift+Ctrl').",
      -- Both boxes can be unchecked -> the name element is disabled (no name text shown).
      enabledGet = function()
        if not addon.GetElementLayout then return true end
        local cfg = addon:GetElementLayout("sequenceText")
        if not cfg or cfg.enabled == nil then return true end
        return cfg.enabled and true or false
      end,
      enabledSet = function(v)
        if addon.SetElementEnabled then addon:SetElementEnabled("sequenceText", v and true or false) end
        if addon.ApplyVisibility then addon:ApplyVisibility() end
      end,
      label3 = "Modkey Side", get3 = "GetActionTrackerModkeySide", set3 = "SetActionTrackerModkeySide" },
    { type = "spacer", h = 12 },  -- top padding above the Scale slider
    { type = "slider", label = "Scale", get = "GetScale", set = "SetScaleValue", min = 0.70, max = 1.80, step = 0.01, float = true, center = true,
      tooltip = "Overall size of the Action Tracker." },
    { type = "dropdownslider", label = "GSE Sequence / Macro / Spell", get = "GetSeqFontName", set = "SetSeqFontName", options = FontOptions,
      tooltip = "Font for the sequence/spell name shown above the icons.",
      sliderLabel = "Size", sliderGet = "GetSeqFontSize", sliderSet = "SetSeqFontSize", smin = 6, smax = 24, sstep = 1, tooltip2 = "Name text size." },
    { type = "dropdownslider", label = "Modifiers", get = "GetModFontName", set = "SetModFontName", options = FontOptions,
      tooltip = "Font for the modifier-key readout (Shift/Ctrl/Alt).",
      sliderLabel = "Size", sliderGet = "GetModFontSize", sliderSet = "SetModFontSize", smin = 6, smax = 24, sstep = 1, tooltip2 = "Modifier text size." },
    { type = "dropdown", label = "Outline", options = OUTLINE_OPTIONS,
      tooltip = "Outline style for the Action Tracker fonts (name, modifiers, keybinds).",
      get = "GetActionTrackerFontOutline",
      set = function(v)
        if addon.SetActionTrackerFontOutline then addon:SetActionTrackerFontOutline(v) end
        if addon.ApplyFontFaces then addon:ApplyFontFaces() end
      end },
  }
end

-- Player Mark (Center Marker) controls on the Center Marker tab.
local function CenterMarkerRows()
  return {
    -- Center Marker dropdown + Scale on ONE row (dropdown left, Scale slider right).
    { type = "dropdownslider", label = "Center Marker", options = CENTER_MARKER_OPTIONS,
      tooltip = "What to show at the centre of the Meters readout: your Class or Spec icon, a crosshair image, the Assisted Highlight icon, or None.",
      -- ONE display rule, ONE marker: every option is a single GSE combat-marker symbol
      -- (centered + scale-aware). "AHLight" is a sentinel: the combat-marker frame draws
      -- nothing and instead the Assisted Highlight engine mirrors its icon there.
      get = function() return (addon.GetCombatMarkerSymbol and addon:GetCombatMarkerSymbol()) or "x" end,
      set = function(v)
        if addon.SetCombatMarkerSymbol then addon:SetCombatMarkerSymbol(v) end
        if _G.Meters_SetCenterMarker then _G.Meters_SetCenterMarker("None") end
        if addon.RefreshCenterMarker then addon:RefreshCenterMarker(false)
        elseif addon.RefreshCombatMarker then addon:RefreshCombatMarker(false) end
        if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
      end,
      -- Scale shares the row; refreshes the marker live AND the AH centre mirror (which IS
      -- the marker when "Assisted Highlight" is chosen, and is sized from this Scale).
      sliderLabel = "Scale", sliderGet = "GetCombatMarkerSize",
      sliderSet = function(v)
        if addon.SetCombatMarkerSize then addon:SetCombatMarkerSize(v) end
        if addon.RefreshCombatMarker then addon:RefreshCombatMarker(false) end
        if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
      end,
      smin = C.COMBAT_MARKER_MIN_SIZE or 16, smax = C.COMBAT_MARKER_MAX_SIZE or 128, sstep = 1,
      tooltip2 = "Size of the Center Marker (works for all marker types, including Assisted Highlight)." },
    -- Row under the dropdown: Class / Custom colour + swatch, tri-state like the Pressed
    -- Indicator -- unchecking both = no colour (the image shows its own colours).
    { type = "tricolor", label = "Class Color", label2 = "Custom",
      -- Leading toggle: Press Detection makes the chosen Center Marker monitor input and blink
      -- like the Pressed Indicator (always shown, pulses on each key/macro press).
      leadLabel = "Press Detection",
      leadGet = function() return addon.GetCombatMarkerPressDetection and addon:GetCombatMarkerPressDetection() end,
      leadSet = function(v)
        if addon.SetCombatMarkerPressDetection then addon:SetCombatMarkerPressDetection(v) end
        if addon.RefreshCombatMarker then addon:RefreshCombatMarker(false) end
      end,
      tooltipLead = "Make the Center Marker monitor your input and blink like the Pressed Indicator: always shown, pulsing on each key/macro press (procedural shapes flash green then dim red; image/class icons keep their colour and just pulse). The separate Pressed Indicator is unaffected.",
      get = "GetCombatMarkerColorMode",
      set = function(m)
        if addon.SetCombatMarkerColorMode then addon:SetCombatMarkerColorMode(m) end
        if addon.RefreshCombatMarker then addon:RefreshCombatMarker(false) end
        if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
      end,
      colorGet = "GetCombatMarkerColor",
      colorSet = function(r, g, b)
        if addon.SetCombatMarkerColor then addon:SetCombatMarkerColor(r, g, b) end
        if addon.RefreshCombatMarker then addon:RefreshCombatMarker(false) end
        if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
      end,
      tooltip = "Tint the Center Marker with your class colour.",
      tooltip2 = "Tint the Center Marker with a custom colour (click the swatch). With neither Class nor Custom selected, white/greyscale shapes fall back to red; full-colour art shows its own colours." },
    -- (Scale now shares the Center Marker row above. Thickness / Border Size were removed --
    -- they only affected the old procedural vector shapes, no longer offered as markers.)
  }
end

local function AssistedHighlightRows()
  return {
    { type = "header", text = "Assisted Highlight" },
    { type = "dropdown", label = "Anchor", get = "GetAssistedHighlightAnchorTarget", set = "SetAssistedHighlightAnchorTarget", options = ANCHOR_OPTIONS,
      tooltip = "Where the highlight sits: fixed on screen, following the mouse cursor, or over the target's portrait (only shown with an attackable target)." },
    { type = "spacer", h = 12 },  -- top padding above the Scale/Alpha row
    { type = "dualslider",
      label = "Scale", get = "GetAssistedHighlightSize", set = "SetAssistedHighlightSize", min = 28, max = 96, step = 1,
      tooltip = "Size of the Assisted Highlight icon. (Auto-sized to fit when anchored to the Target Portrait.)",
      tooltip2 = "Transparency of the highlight icon.",
      -- Target Portrait mode auto-sizes the highlight to the portrait, so Scale is
      -- driven by the addon -- grey it out to show it has no effect there.
      disableGet = function()
        return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
      end,
      label2 = "Alpha", get2 = "GetAssistedHighlightAlpha", set2 = "SetAssistedHighlightAlpha", min2 = 0.05, max2 = 1.00, step2 = 0.05, float2 = true },
    { type = "header", text = "Display" },
    { type = "dualcheck",
      label = "Range Check", get = "GetAssistedHighlightRangeCheckerEnabled", set = "SetAssistedHighlightRangeCheckerEnabled",
      tooltip = "Red-tint the highlight when the suggested ability is out of range of your target.",
      label2 = "Show Keybind/Stacks", get2 = "GetAssistedHighlightShowKeybind", set2 = "SetAssistedHighlightShowKeybind",
      tooltip2 = "Show the suggested ability's keybind text AND its stack/charge count on the highlight.",
      -- Keybind + stacks are hidden in Target Portrait mode (no room on the round emblem),
      -- so this toggle has no effect there -- grey it out.
      disable2 = function()
        return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
      end,
      label3 = "Show GCD Swipe", get3 = "GetAssistedHighlightShowGCD", set3 = "SetAssistedHighlightShowGCD",
      tooltip3 = "Sweep a cooldown 'swipe' across the highlight for the global cooldown." },
    -- Border options removed: the icon border now always adopts the player's
    -- action-bar frame art (Blizzard default or skinner), like the rest of the UI.
    { type = "spacer" },
    { type = "header", text = "Keybind" },
    { type = "dropdownslider", label = "Font", get = "GetAssistedHighlightFontName", set = "SetAssistedHighlightFontName", options = FontOptions,
      tooltip = "Font for the keybind text shown on the highlight.",
      sliderLabel = "Size", sliderGet = "GetAssistedHighlightFontSize", sliderSet = "SetAssistedHighlightFontSize", smin = 6, smax = 24, sstep = 1, tooltip2 = "Keybind text size." },
    { type = "dropdown", label = "Location", get = "GetAssistedHighlightKeybindAnchor", set = "SetAssistedHighlightKeybindAnchor", options = KEYBIND_ANCHOR_OPTIONS,
      tooltip = "Which corner of the highlight the keybind text sits in." },
  }
end

local function QoLRows()
  return {
    { type = "header", text = "Quality of Life" },
    { type = "header", text = "Game" },
    { type = "check", label = "Mute Fizzle Sounds", get = "GetMuteFizzles", set = "SetMuteFizzles",
      tooltip = "Mute the 'fizzle' sound a spell makes when it fails to cast (out of range, not enough resource, etc.)." },
    { type = "check", label = "Hide Error Messages", get = "GetHideErrors", set = "SetHideErrors",
      tooltip = "Hide the red Blizzard error text at the top of the screen (e.g. 'Not enough rage', 'Out of range')." },
    { type = "header", text = "Saved Settings" },
    { type = "check", label = "Account Wide", get = "GetAccountWide", set = "SetAccountWide",
      tooltip = "Share these settings across all your characters. Unchecked: settings are saved per-character." },
    { type = "header", text = "Assisted Highlight" },
    { type = "check", label = "Assisted Highlight Rotation Matching System", get = "GetProcGlowEnabled", set = "SetProcGlowEnabled",
      unavailable = function() return not (ns.Caps and ns.Caps.assistedHighlight) end,
      tooltip = "Track how often your casts match the Assisted Highlight suggestion (drives the AH Match % readout)." },
    { type = "matchrow",
      unavailable = function() return not (ns.Caps and ns.Caps.assistedHighlight) end,
      label = "Match %", get = "GetAHMatchPercentEnabled", set = "SetAHMatchPercentEnabled",
      tooltip = "Show the AH Match percentage readout under the Action Tracker.",
      tooltip2 = "Play a sound each time your cast matches the suggestion. 'None' disables the audible match.",
      label2 = "Match Audible",
      -- The dropdown now drives the audible match: "None" disables it, any sound enables
      -- it and selects that sound.
      ddget = function()
        if addon.GetAHMatchAudibleEnabled and not addon:GetAHMatchAudibleEnabled() then return "None" end
        return (addon.GetAHMatchSound and addon:GetAHMatchSound()) or "None"
      end,
      ddset = function(v)
        if v == "None" then
          if addon.SetAHMatchAudibleEnabled then addon:SetAHMatchAudibleEnabled(false) end
          return
        end
        if addon.SetAHMatchAudibleEnabled then addon:SetAHMatchAudibleEnabled(true) end
        if addon.SetAHMatchSound then addon:SetAHMatchSound(v) end
        if addon.PlayAHMatchSound then addon:PlayAHMatchSound(true) end -- preview the pick
      end,
      ddoptions = SoundOptions },
    { type = "header", text = "Pressed Indicator" },
    { type = "dropdownslider", label = "Shape", get = "GetPressedIndicatorShape", set = "SetPressedIndicatorShape", options = PRESSED_SHAPE_OPTIONS,
      tooltip = "Image flashed on screen when you press your macro key. 'None' turns it off.",
      sliderLabel = "Scale", sliderGet = "GetPressedIndicatorSize", sliderSet = "SetPressedIndicatorSize", smin = C.PRESSED_INDICATOR_MIN_SIZE or 4, smax = C.PRESSED_INDICATOR_MAX_SIZE or 24, sstep = 1, tooltip2 = "Size of the pressed indicator." },
    -- Colour source row, led by the Lock toggle: [] Lock  [] Class Color  [] Custom Color [swatch].
    -- Lock checked = locked (flashes on key press at its saved spot); unchecked = unlocked +
    -- draggable. Class/Custom mutually exclusive; neither = the image's own colours.
    { type = "tricolor", label = "Class Color", label2 = "Custom",
      leadLabel = "Lock",
      leadGet = function() return not (addon.GetPressedIndicatorUnlocked and addon:GetPressedIndicatorUnlocked()) end,
      leadSet = function(v)
        if addon.SetPressedIndicatorUnlocked then addon:SetPressedIndicatorUnlocked(not v) end
        if addon.UpdatePressedIndicatorDragState then addon:UpdatePressedIndicatorDragState() end
        if addon.RefreshPressedIndicator then addon:RefreshPressedIndicator(true) end
      end,
      tooltipLead = "Locked: the indicator only flashes on key press, at its saved spot. Uncheck to unlock it -- then it stays visible and you can drag it to a new location.",
      get = "GetPressedIndicatorColorMode",
      set = function(m)
        if addon.SetPressedIndicatorColorMode then addon:SetPressedIndicatorColorMode(m) end
        if addon.ApplyPressedIndicatorStyle then addon:ApplyPressedIndicatorStyle() end
      end,
      colorGet = "GetPressedIndicatorCustomColor",
      colorSet = function(r, g, b)
        if addon.SetPressedIndicatorCustomColor then addon:SetPressedIndicatorCustomColor(r, g, b) end
        if addon.ApplyPressedIndicatorStyle then addon:ApplyPressedIndicatorStyle() end
      end,
      tooltip = "Tint the pressed indicator with your class colour.",
      tooltip2 = "Tint the pressed indicator with a custom colour (click the swatch). With neither Class nor Custom selected, the image shows in its own colours." },
  }
end

local TABS = {
  { key = "General", text = "General", rows = GeneralRows },
  { key = "Meters", text = "Meters", embed = "MetersOptionsPanel", centerContent = true,
    -- Size the embedded Meters panel to its visible content (Show GCD/DPS row + Details
    -- rows + Refresh/Opacity) so the Player Marker rows sit a NORMAL row-gap below it -- not
    -- a big empty gap. Trimmed to ~the content's bottom so the spacing matches other rows.
    embedHeight = 144,
    rows = function()
      return {
        { type = "header", text = "Meters" },
        -- Font controls pulled up to the top as addon-style controls; the Meters panel's
        -- own font dropdowns are hidden in MetersOptions. Font (dropdown) + Font Size (slider).
        { type = "dropdownslider",
          label = "Font", get = MetersFontFaceGet, set = MetersFontFaceSet, options = FontOptions,
          tooltip = "Font for the Meters readout text (DPS/HPS/GCD/%).",
          sliderLabel = "Font Size", sliderGet = MetersFontSizeGet, sliderSet = MetersFontSizeSet, smin = 6, smax = 24, sstep = 1,
          tooltip2 = "Meters text size.",
          unavailable = function() return not (ns.Caps and ns.Caps.meters) end },
        { type = "dropdown", label = "Outline", get = MetersFontOutlineGet, set = MetersFontOutlineSet, options = OUTLINE_OPTIONS,
          tooltip = "Outline style for the Meters readout text.",
          unavailable = function() return not (ns.Caps and ns.Caps.meters) end },
      }
    end,
    -- Player Marker controls pinned to the BOTTOM of the Meters tab (moved from its own tab).
    bottomRows = CenterMarkerRows },
  { key = "AssistedHighlight", text = "Assisted Highlight", rows = AssistedHighlightRows, enableGet = "IsAssistedHighlightMirrorEnabled", centerContent = true, cap = "assistedHighlight" },
  { key = "ActionTracker", text = "Action Tracker", rows = ActionTrackerRows, enableGet = "IsEnabled", centerContent = true },
  { key = "QoL", text = "Quality of Life", rows = QoLRows, centerContent = true },
}

-- ── Panel construction ──────────────────────────────────────────────────────
local function CreateTabButton(name, parent, text)
  local button
  local ok = pcall(function() button = CreateFrame("Button", name, parent, "PanelTopTabButtonTemplate") end)
  if not ok or not button then
    pcall(function() button = CreateFrame("Button", name, parent, "PanelTabButtonTemplate") end)
  end
  if not button then
    button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(120, 24)
  end
  button:SetText(text or "")
  return button
end

-- NOTE: the tab grey-out (dim a tracker's tab when disabled) was removed. Any
-- insecure script or per-frame change on a Settings CANVAS taints the shared
-- Settings/GameMenu path and breaks Logout/Exit (and can propagate to action-bar
-- drag). Keeping this a no-op so the call sites stay harmless.
RefreshTabStates = function() end

local function ShowTab(index)
  if not panel then return end
  for i, entry in ipairs(panel.tabEntries) do
    if i == index then
      if PanelTemplates_SelectTab then PanelTemplates_SelectTab(entry.tab) end
      entry.scroll:Show()
    else
      if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(entry.tab) end
      entry.scroll:Hide()
    end
  end
  RefreshTabStates()
end

-- Embed a globally-named options panel (e.g. the ported Meters panel) into a tab
-- page by reparenting it to fill the page. Show/hide follows the page (so the tab
-- bar controls it) -- no per-show scripts on the canvas. Falls back to a message if
-- the panel isn't loaded.
local function EmbedGlobalPanel(page, globalName, topOffset, bottomOffset, embedHeight)
  local mp = _G[globalName]
  if not (mp and mp.SetParent and mp.SetPoint) then
    if page.embedFallback then page.embedFallback:Show() end
    return nil
  end
  if page.embedFallback then page.embedFallback:Hide() end
  mp:SetParent(page)
  mp:ClearAllPoints()
  mp:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(topOffset or 0))
  if embedHeight and embedHeight > 0 then
    -- Fixed height = the panel's visible content, so rows that follow sit RIGHT below it
    -- instead of the panel filling the whole page (which left a big empty gap).
    mp:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(topOffset or 0))
    mp:SetHeight(embedHeight)
  else
    -- Fill the page down to any bottom-pinned rows (bottomOffset).
    mp:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, (bottomOffset or 0))
  end
  mp:Show()
  return mp
end

-- Height reserved at the bottom of the frame for the persistent social footer (template
-- is 52 tall) plus a small gap, so tab content/scroll never overlaps the icons.
local FOOTER_RESERVE = 60

local function BuildPanel()
  if panel then return panel end
  -- Re-scan the marker-images folder now that the UI is up (the file-load scan can miss
  -- files), so the Center Marker / Pressed Indicator dropdowns list every crosshair PNG.
  RebuildMarkerOptionLists()
  wipe(activeRefreshers) -- fresh build: each tab's Populate accumulates its refreshers
  panel = CreateFrame("Frame", "GSETrackerCanvasPanel", UIParent)
  panel:SetSize(640, 600)
  panel.tabEntries = {}

  local titleFrame = CreateFrame("Frame", nil, panel, "GSETrackerBrandTemplate")
  titleFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
  titleFrame:SetSize(320, 36)
  panel.titleFrame = titleFrame

  local firstTab, prev
  for i, t in ipairs(TABS) do
    local tab = CreateTabButton("$parentTab" .. i, panel, t.text)
    tab:SetID(i)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 8) end
    if i == 1 then
      tab:SetPoint("TOPLEFT", titleFrame, "BOTTOMLEFT", 4, -6)
      firstTab = tab
    else
      tab:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    end
    tab:SetScript("OnClick", function(self) ShowTab(self:GetID()) end)
    prev = tab

    if t.embed then
      -- A whole-frame tab (e.g. the embedded Meters panel), optionally with GSE option
      -- rows pinned across the TOP of the page (the panel fills the space below them).
      local page = CreateFrame("Frame", "GSETrackerCanvasEmbed" .. i, panel)
      page:SetPoint("TOPLEFT", firstTab, "BOTTOMLEFT", 4, -6)
      page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, FOOTER_RESERVE)

      local topOffset = 0
      if t.rows then
        local rowPane = CreateFrame("Frame", nil, page)
        rowPane:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        rowPane:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, 0)
        rowPane:SetHeight(10)
        Populate(rowPane, t.rows(), t.centerContent)
        topOffset = (rowPane.GetHeight and rowPane:GetHeight()) or 0
        page.rowPane = rowPane
      end

      -- Optional GSE rows below the embed. Populated first to measure their height.
      local bPane, bPaneH
      if t.bottomRows then
        bPane = CreateFrame("Frame", nil, page)
        bPane:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        bPane:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, 0)
        bPane:SetHeight(10)
        Populate(bPane, t.bottomRows(), t.centerContent)
        bPaneH = (bPane.GetHeight and bPane:GetHeight()) or 0
        page.bottomRowPane = bPane
      end

      local fb = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      fb:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -(topOffset + 20))
      fb:SetText("Meters is not loaded.")
      fb:Hide()
      page.embedFallback = fb

      -- With embedHeight the panel is sized to its content and the bottom rows flow right
      -- below it (no gap); otherwise the panel fills the page and the rows pin to the bottom.
      local bottomOffset = (bPane and not t.embedHeight) and (bPaneH + 12) or 0
      local mp = EmbedGlobalPanel(page, t.embed, topOffset, bottomOffset, t.embedHeight)
      if bPane then
        bPane:ClearAllPoints()
        if t.embedHeight and mp then
          bPane:SetPoint("TOPLEFT", mp, "BOTTOMLEFT", 0, -12)
          bPane:SetPoint("TOPRIGHT", mp, "BOTTOMRIGHT", 0, -12)
        else
          bPane:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 8)
          bPane:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 8)
        end
        bPane:SetHeight(bPaneH or 10)
      end
      panel.tabEntries[i] = { tab = tab, scroll = page, pane = page }
    else
      local scroll = CreateFrame("ScrollFrame", "GSETrackerCanvasScroll" .. i, panel, "UIPanelScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", firstTab, "BOTTOMLEFT", 4, -6)
      scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, FOOTER_RESERVE)

      local pane = CreateFrame("Frame", nil, scroll)
      pane:SetSize(560, 10)
      scroll:SetScrollChild(pane)

      Populate(pane, t.rows(), t.centerContent)
      -- Whole-tab grey-out when the feature isn't available on this client (e.g. AH on Classic).
      if t.cap and not (ns.Caps and ns.Caps[t.cap]) then GreyOutPane(pane) end
      panel.tabEntries[i] = { tab = tab, scroll = scroll, pane = pane, enableGet = t.enableGet and ResolveGet(t.enableGet) or nil }
    end
  end

  -- Persistent social footer pinned to the bottom of the whole frame (shows on every
  -- tab). The template (150x52) centres its icons, so anchoring left+right centres them
  -- horizontally across the frame.
  local footer = CreateFrame("Frame", nil, panel, "GSETrackerSocialTemplate")
  footer:ClearAllPoints()
  -- Icons are CENTER-anchored within the footer; shifting the whole footer left 40 moves
  -- the centred icon group left 40.
  footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12 - 40, 8)
  footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12 - 40, 8)
  panel.socialFooter = footer

  -- (No OnShow/OnUpdate scripts on the canvas -- they taint the Settings/GameMenu
  -- path and break Logout/Exit.)
  ShowTab(1)
  return panel
end

-- ── Registration + entry points ─────────────────────────────────────────────
local registered = false
local function RegisterSettings()
  if registered then return end
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  registered = true

  local p = BuildPanel()
  local category = Settings.RegisterCanvasLayoutCategory(p, CATEGORY_NAME)
  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
end

-- After the Settings panel opens/closes, re-evaluate the overlay frames' strata: the Center
-- Marker and Pressed Indicator drop below the open panel (so they don't draw over it or grab
-- its controls) and rise back to HIGH when it closes. Deferred a frame so SettingsPanel:IsShown()
-- reflects the new state.
local function RefreshOverlayStrata()
  if not (C_Timer and C_Timer.After) then return end
  C_Timer.After(0, function()
    if _G.Meter_UpdateVisibility then _G.Meter_UpdateVisibility() end  -- marker drops below the panel while open
  end)
end

-- WoW has no event for the Settings panel showing/hiding, so a tiny watcher polls its
-- IsShown() on a slow tick and refreshes overlay strata only when it CHANGES. This keeps the
-- Center Marker / Pressed Indicator below the panel while it's open and snaps them back to
-- HIGH promptly when it closes (any close path: ESC, the X, or our toggle). Own frame -- no
-- scripts on the Settings canvas (those taint the Settings/GameMenu path).
do
  local watcher = CreateFrame("Frame")
  local lastShown
  watcher._t = 0
  watcher:SetScript("OnUpdate", function(self, elapsed)
    self._t = self._t + (elapsed or 0)
    if self._t < 0.2 then return end
    self._t = 0
    local shown = (_G.SettingsPanel and _G.SettingsPanel.IsShown and _G.SettingsPanel:IsShown()) and true or false
    if shown ~= lastShown then
      lastShown = shown
      RefreshOverlayStrata()
    end
  end)
end

function Options:OpenSettingsWindow()
  -- Combat lock: the Blizzard Settings panel is a PROTECTED frame, so Settings.OpenToCategory
  -- (which ShowUIPanel's it) is blocked in combat and throws an ADDON_ACTION_BLOCKED error --
  -- even though it's Blizzard's own panel. Bail politely instead; the user can retry OOC.
  if _G.InCombatLockdown and _G.InCombatLockdown() then
    local cf = _G.DEFAULT_CHAT_FRAME
    if cf and cf.AddMessage then
      cf:AddMessage("|cFFFFFFFFGS|r|cFF00FFFFE|r|cFFFFFF00: Tracker|r |cffff5555Options can't be opened during combat.|r Try again after combat.")
    end
    return
  end
  RegisterSettings()
  -- Re-scan marker-images and repopulate the option tables IN PLACE so the dropdowns show
  -- the current files each time the window opens (the menus read these tables live on open).
  RebuildMarkerOptionLists()
  if categoryID and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(categoryID)
  end
  RefreshOverlayStrata()
end

-- A real toggle (the old `= OpenSettingsWindow` alias only ever opened): close the
-- Settings panel when it's already showing OUR category, switch to ours if it's open on
-- a different one, otherwise open it.
function Options:ToggleSettingsWindow()
  RegisterSettings()
  local sp = _G.SettingsPanel
  if sp and sp.IsShown and sp:IsShown() then
    local onOurs = true
    if categoryID and sp.GetCurrentCategory then
      local ok, cur = pcall(sp.GetCurrentCategory, sp)
      if ok and cur and cur.GetID then onOurs = (cur:GetID() == categoryID) end
    end
    if onOurs then
      if _G.HideUIPanel then _G.HideUIPanel(sp) else sp:Hide() end
      RefreshOverlayStrata()
      return
    end
  end
  self:OpenSettingsWindow()
end

function Options:CloseSettingsWindow()
  if SettingsPanel and SettingsPanel:IsShown() and SettingsPanel.Close then
    SettingsPanel:Close()
  end
  RefreshOverlayStrata()
end

-- ── Login / welcome window (5-page) ──────────────────────────────────────────
-- Shown once per login UNLESS "Hide Login Message" (General tab) is checked. A paged
-- walkthrough: each page shows an image (and optional caption). To drop in artwork
-- later, just set `image` on the matching LOGIN_PAGES entry (a texture path) and it
-- renders automatically; until then each page shows a grey placeholder.
local LOGIN_PAGES = {
  { image = "Interface\\AddOns\\GSE_Tracker\\media\\GTLogin\\GSETRK-LoginGeneral.png", w = 500, h = 500, caption = "" },
  { image = "Interface\\AddOns\\GSE_Tracker\\media\\GTLogin\\GSETRK-LoginMeters.png", w = 500, h = 500, caption = "" },
  { image = "Interface\\AddOns\\GSE_Tracker\\media\\GTLogin\\GSETRK-LoginAssistedHighlight.png", w = 500, h = 500, caption = "" },
  { image = "Interface\\AddOns\\GSE_Tracker\\media\\GTLogin\\GSETRK-LoginActionTracker.png", w = 500, h = 500, caption = "" },
  { image = "Interface\\AddOns\\GSE_Tracker\\media\\GTLogin\\GSETRK-LoginQoL.png", w = 500, h = 500, caption = "" },
}

local loginMessageFrame

local function UpdateLoginPage(f)
  local total = #LOGIN_PAGES
  local page = f._page or 1
  if page < 1 then page = 1 elseif page > total then page = total end
  f._page = page
  local data = LOGIN_PAGES[page] or {}

  local INSET_L, INSET_R, INSET_T, INSET_B = 11, 12, 12, 11
  if data.image then
    -- Frame wraps the image EXACTLY: dialog size = image size + backdrop insets.
    -- Prefer the image's NATIVE size (data.w/h) -- no downscaling. Fall back to an
    -- aspect-fit only for pages that don't declare explicit dimensions.
    local w, h = tonumber(data.w), tonumber(data.h)
    if not (w and h) then
      local MAX_IMG = 380
      local aspect = tonumber(data.aspect) or 1
      if aspect >= 1 then w, h = MAX_IMG, MAX_IMG / aspect else w, h = MAX_IMG * aspect, MAX_IMG end
    end
    f.image:SetTexture(data.image)
    f.image:ClearAllPoints()
    f.image:SetPoint("TOPLEFT", f, "TOPLEFT", INSET_L, -INSET_T)
    f.image:SetSize(w, h)
    f.image:Show()
    f.imgText:Hide()
    f:SetSize(w + INSET_L + INSET_R, h + INSET_T + INSET_B)
  else
    f.image:Hide()
    f.imgText:SetText("IMAGE WILL GO HERE LATER\n(Page " .. page .. " of " .. total .. ")")
    f.imgText:Show()
    f:SetSize(420, 300)
  end

  if f.prev then if page <= 1 then f.prev:Disable() else f.prev:Enable() end end
  if f.next then if page >= total then f.next:Disable() else f.next:Enable() end end
end

local function BuildLoginMessageFrame()
  if loginMessageFrame then return loginMessageFrame end

  local f = CreateFrame("Frame", "GSETrackerLoginMessageFrame", UIParent, "BackdropTemplate")
  f:SetSize(480, 400)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  -- ESC closes it (add a key to the Blizzard table -- never reassign the table).
  if UISpecialFrames then table.insert(UISpecialFrames, "GSETrackerLoginMessageFrame") end

  -- Corner close (X) -- no title bar / labels; the image is the whole content.
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  -- Page image (size/anchor set per-page in UpdateLoginPage).
  local image = f:CreateTexture(nil, "ARTWORK")
  image:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -12)
  image:Hide()
  f.image = image

  -- Placeholder text for pages that don't have an image yet.
  local imgText = f:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
  imgText:SetPoint("CENTER")
  imgText:SetJustifyH("CENTER")
  imgText:SetText("IMAGE WILL GO HERE LATER")
  f.imgText = imgText

  -- Small Prev / Next arrows, centred at the bottom (overlaid on the image edge).
  local prev = CreateFrame("Button", nil, f)
  prev:SetSize(32, 32)
  prev:SetPoint("BOTTOM", f, "BOTTOM", -22, 18)
  prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
  prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
  prev:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
  prev:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  prev:SetScript("OnClick", function() f._page = (f._page or 1) - 1; UpdateLoginPage(f) end)
  f.prev = prev

  local nextb = CreateFrame("Button", nil, f)
  nextb:SetSize(32, 32)
  nextb:SetPoint("BOTTOM", f, "BOTTOM", 22, 18)
  nextb:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
  nextb:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
  nextb:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
  nextb:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  nextb:SetScript("OnClick", function() f._page = (f._page or 1) + 1; UpdateLoginPage(f) end)
  f.next = nextb

  -- "Hide Login Message" checkbox -- no visible label (tooltip explains it), bottom-left.
  local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check:SetPoint("LEFT", f, "BOTTOMLEFT", 33, 34)  -- vertical centre aligned with the arrow row (arrows: bottom 18 + half of 32)
  check:SetScript("OnClick", function(self)
    if addon.SetHideLoginMessage then addon:SetHideLoginMessage(self:GetChecked() and true or false) end
  end)
  check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Hide Login Message", 1, 1, 1)
    GameTooltip:AddLine("Don't show this window on future logins.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local checkLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
  checkLabel:SetText("Hide Login Message")
  f.check = check

  loginMessageFrame = f
  return f
end

function Options:ShowLoginMessage()
  -- Respect the opt-out, and don't pop a movable frame during combat lockdown.
  if addon.GetHideLoginMessage and addon:GetHideLoginMessage() then return end
  if _G.InCombatLockdown and _G.InCombatLockdown() then return end
  local f = BuildLoginMessageFrame()
  if f.check and f.check.SetChecked then
    f.check:SetChecked(addon.GetHideLoginMessage and addon:GetHideLoginMessage() or false)
  end
  f._page = 1
  UpdateLoginPage(f)
  -- Showing during PLAYER_LOGIN gets swept away by the loading-screen / CloseSpecialWindows
  -- pass (UISpecialFrames are hidden as the world finishes loading). Defer the show to the
  -- first PLAYER_ENTERING_WORLD so the window lands AFTER the loading screen.
  if not f._pewWaiter then f._pewWaiter = CreateFrame("Frame") end
  f._pewWaiter:RegisterEvent("PLAYER_ENTERING_WORLD")
  f._pewWaiter:SetScript("OnEvent", function(waiter)
    waiter:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Re-check the opt-out in case it was toggled between login and world-load.
    if addon.GetHideLoginMessage and addon:GetHideLoginMessage() then return end
    f:Show()
  end)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  RegisterSettings()
  -- Unify the Meters engine's lock with the addon's master "Lock All" state. They default
  -- DIFFERENTLY (addon = unlocked, Meters engine = locked), so without this the Meters
  -- readout behaves locked while the rest of the UI is unlocked -- its examples never come
  -- back after combat. The addon lock is the source of truth; push it into the engine.
  if addon.IsLocked then
    local locked = addon:IsLocked() and true or false
    if _G.MetersSavedVars then _G.MetersSavedVars.locked = locked end
    if _G.Meter_SetLocked then _G.Meter_SetLocked(locked) end
  end
end)
