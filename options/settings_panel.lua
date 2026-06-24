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
  -- If Edit Mode is open, re-evaluate the selection boxes so toggling an element on/off in the options
  -- shows/hides its Edit Mode box live (not only on the next Edit Mode open).
  if _G.GSETracker_RefreshEditModeBoxes then pcall(_G.GSETracker_RefreshEditModeBoxes) end
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
  -- Keep the DamageMeter Skinner in step with font/skin changes (Retail, no Details!).
  if _G.GSETracker_MeterSkin_Refresh then _G.GSETracker_MeterSkin_Refresh() end
  if _G.GSETrackerDetails_ApplyBorder then _G.GSETrackerDetails_ApplyBorder() end
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
  -- Center Marker: special modes + image symbols + None. Drop the ones that can't work on this
  -- client: "AHLight" (mirrors the AH suggestion -- retail only) and "Specialization" (needs the
  -- spec system, Mists+ -- absent on Classic Era / TBC). "Class" + images + None work everywhere.
  clear(CENTER_MARKER_OPTIONS)
  local ahOK = ns.Caps and ns.Caps.assistedHighlight
  local specOK = _G.GetNumSpecializations and (_G.GetNumSpecializations() or 0) > 0
  for _, o in ipairs(MYMARKER_OPTIONS) do
    local drop = (o.value == "AHLight" and not ahOK)
              or (o.value == "Specialization" and not specOK)
    if not drop then
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
  -- Greyed out when the player's UI has no target-frame portrait to anchor to.
  { value = "Target Nameplate", text = "Target Portrait",
    disable = function() return not (addon.HasTargetPortrait and addon:HasTargetPortrait()) end },
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
-- True when GSE (the macro compiler) is present. When it isn't, there are no GSE sequence
-- names, so the "GSE Sequence Name" option is greyed out and the tracker falls back to Spell
-- Names. Checked at row-build time (the settings panel is built lazily, by which point GSE has
-- loaded if installed).
local function IsGSEAvailable()
  if _G.GSE ~= nil then return true end
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "GSE")
    if ok and loaded then return true end
  end
  return false
end

-- The primary name source is always GSE's sequence name (greyed + unused when GSE isn't
-- installed). These helpers keep the namesource checkbox and the font row label in sync.
local function PrimaryNameLabel()
  return "GSE Sequence Name"
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

-- Same list WITHOUT the "None" entry -- used where a separate checkbox controls enable/disable (the AH
-- Match Audible row), so the dropdown only picks WHICH sound.
local function SoundOptionsNoNone()
  local list = SoundOptions()
  for i = #list, 1, -1 do
    if list[i].value == "None" then table.remove(list, i) end
  end
  return list
end

-- Curated <=1 second sounds for the Match Audible cue (a per-cast tick wants to be SHORT). WoW has no API
-- to read a sound file's length, so this is a hand-picked kit-only subset of brief UI blips -- the longer
-- BLIZZ_SHORT_SOUNDS entries (Ready Check / BNet Toast / PvP Queue Pop / Auto Quest) and the
-- arbitrary-length LibSharedMedia sounds are intentionally excluded.
local SHORT_1S_SOUNDS = {
  { text = "Checkbox Click", key = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
  { text = "Chat Scroll",    key = "U_CHAT_SCROLL_BUTTON" },
  { text = "Map Ping",       key = "MAP_PING" },
  { text = "Whisper",        key = "TELL_MESSAGE" },
  { text = "Player Invite",  key = "IG_PLAYER_INVITE" },
  { text = "Auction Open",   key = "AUCTION_WINDOW_OPEN" },
  { text = "Quest Chime",    key = "IG_QUEST_LIST_COMPLETE" },
}
local function SoundOptionsShort()
  local list = {}
  local SK = _G.SOUNDKIT
  if SK then
    for _, e in ipairs(SHORT_1S_SOUNDS) do
      local id = SK[e.key]
      if id then list[#list + 1] = { value = "kit:" .. id, text = e.text } end
    end
  end
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
      local radio = rootDescription:CreateRadio(o.text,
        function() return get() == o.value end,
        function() set(o.value); return MenuResponse and MenuResponse.Close end)
      -- A per-option disable() (re-evaluated each time the menu opens) greys the entry out and
      -- blocks selection -- e.g. "Target Portrait" when the UI has no target-frame portrait.
      if radio and radio.SetEnabled and o.disable and o.disable() then
        radio:SetEnabled(false)
      end
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

-- Uniform vertical rhythm: every row leaves the SAME gap (ROW_PAD) below its content, so the
-- spacing reads evenly across all tabs regardless of control type. Each renderer returns its
-- content height + ROW_PAD. (Headers keep their own larger spacing as section dividers.)
local ROW_PAD   = 8    -- gap below every row
local RH_CHECK  = 26   -- checkbox / toggle / swatch+label row content
local RH_COLOR  = 20   -- bare colour-swatch row content
local RH_LINE   = 44   -- dropdown / dropdown+slider row (label above a dropdown control)
local RH_SLIDER = 32   -- standalone slider row (title + slider sits at y-16, ends ~y-32)

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

-- A simple action button row. desc.red tints the native UIPanelButton red (call-to-action). desc.onClick
-- fires on click; desc.tooltip/label drive the hover tip; desc.width sets the button width (default 150).
--
-- desc.secureMacro (string OR function->string|nil): when set, the button is built from
-- SecureActionButtonTemplate and fires that slash text as a macro. The point: a macro runs in the
-- SecureActionButton's *secure* context, so a PROTECTED action it reaches (e.g. TargetUnit() during
-- Blizzard Edit Mode setup) is ALLOWED -- our insecure code is never on that stack, so no
-- ADDON_ACTION_FORBIDDEN taint. When secure, desc.preClick/desc.onClick are wired as PreClick/PostClick
-- (NOT OnClick -- that would replace the secure handler). If the macro resolves to nil (slash not
-- available) or we're in combat (can't set secure attributes), we fall back to a plain insecure button.
local function MakeButton(pane, y, desc)
  local topPad = 2
  local macro = desc.secureMacro
  if type(macro) == "function" then macro = macro() end
  local useSecure = macro and not (_G.InCombatLockdown and _G.InCombatLockdown())
  local template = useSecure and "UIPanelButtonTemplate, SecureActionButtonTemplate" or "UIPanelButtonTemplate"
  local b = CreateFrame("Button", nil, pane, template)
  -- desc.spanRight: a tall (square-ish) button pinned to the pane's RIGHT, OVERLAYING the rows beside it
  -- (consumes no vertical space -- returns 0). Used for the Edit Mode button next to the enable/show rows.
  if desc.spanRight then
    b:SetSize(desc.width or 90, desc.height or 90)
    b:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -(desc.rightInset or 16), y - topPad)
  else
    b:SetSize(desc.width or 150, 24)
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, y - topPad)
  end
  b:SetText(desc.label or "")
  if desc.red then
    local function tint(tex) if tex then tex:SetVertexColor(0.80, 0.13, 0.13) end end
    tint(b:GetNormalTexture()); tint(b:GetPushedTexture()); tint(b:GetDisabledTexture())
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetVertexColor(1, 0.30, 0.30) end
    local fs = b.GetFontString and b:GetFontString()
    if fs then fs:SetTextColor(1, 0.92, 0.92) end
  end
  if useSecure then
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macro)
    if desc.preClick then b:SetScript("PreClick", function() desc.preClick() end) end
    if desc.onClick then b:SetScript("PostClick", function() desc.onClick() end) end
  else
    if desc.preClick or desc.onClick then
      b:SetScript("OnClick", function()
        if desc.preClick then desc.preClick() end
        if desc.onClick then desc.onClick() end
      end)
    end
  end
  AttachTooltip(b, desc.label, desc.tooltip)
  -- Optional white column header above the button (set on the TOP spanRight button to label the
  -- whole Edit Mode column, mirroring the "Visibility" header above the dropdowns).
  if desc.spanRight and desc.spanHeader then
    local hdr = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 5, 5)
    hdr:SetText(desc.spanHeader)
    hdr:SetTextColor(1, 1, 1)
  end
  -- Grey the button out (and block the click) when its element is disabled. A disabled button takes no
  -- clicks, so the secure macro can't fire either. Re-evaluated on every settings change (RunRefreshers).
  if desc.disableGet then
    local disableGet = ResolveGet(desc.disableGet)
    local function applyDisabled()
      if disableGet() then
        if b.Disable then b:Disable() end
        b:SetAlpha(0.4)
      else
        if b.Enable then b:Enable() end
        b:SetAlpha(1)
      end
    end
    applyDisabled()
    activeRefreshers[#activeRefreshers + 1] = applyDisabled
  end
  if desc.spanRight then return 0 end  -- overlays the rows beside it; takes no vertical space
  if desc.center then CenterPaneRow(pane, { b }, 16, desc.width or 150) end
  return 24 + topPad + ROW_PAD
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
  return RH_CHECK + ROW_PAD
end

-- Two or three checkboxes side by side on one row (the third is rendered only when
-- desc.get3 is supplied). Even horizontal spacing: each checkbox sits a fixed gap after the
-- PREVIOUS label, so the groups are spaced consistently regardless of label width. The first
-- checkbox starts at x=16 to line up with the single checks / enable-show rows above it.
local function MakeDualCheck(pane, y, desc)
  local ROW_X, COL_GAP = 16, 24
  local lastLbl = nil
  local firstCB, rowRight = nil, ROW_X  -- for optional centering of the whole row
  -- desc.cols = { x1, x2, ... } pins each checkbox at a FIXED pane x (a stacked grid that lines up
  -- across rows), instead of chaining each after the previous label.
  local idx = 0
  local function one(getName, setName, label, tip, disableName)
    idx = idx + 1
    local get, set = ResolveGet(getName), ResolveSet(setName)
    local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    if desc.cols and desc.cols[idx] then
      cb:SetPoint("TOPLEFT", pane, "TOPLEFT", desc.cols[idx], y)
      if not firstCB then firstCB = cb end
    elseif lastLbl then
      cb:SetPoint("LEFT", lastLbl, "RIGHT", COL_GAP, 0)
      rowRight = rowRight + COL_GAP
    else
      cb:SetPoint("TOPLEFT", pane, "TOPLEFT", ROW_X, y)
      firstCB = cb
    end
    cb:SetChecked(get() and true or false)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    local lbl = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    StyleCheckLabel(lbl)
    AttachTooltip(cb, label, tip)
    lastLbl = lbl
    rowRight = rowRight + 26 + 4 + (lbl:GetStringWidth() or 0)  -- checkbox + gap + label width
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
  -- Optionally centre the whole row in the pane. Only the first checkbox is pane-anchored (the rest
  -- chain off it), so shifting just that one slides the entire row.
  if desc.center and not desc.cols and firstCB then CenterPaneRow(pane, { firstCB }, ROW_X, rowRight) end
  return RH_CHECK + ROW_PAD
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
  return RH_CHECK + ROW_PAD
end

-- OptionsSliderTemplate's groove isn't applied on some clients (e.g. TBC "Anniversary"): the thumb
-- shows but the bar is missing, and that slider itself has no working SetBackdrop. So build a
-- dedicated backdrop frame BEHIND the slider with the STOCK Blizzard slider textures -- the groove
-- (UI-SliderBar-Background) AND the rounded end-caps (UI-SliderBar-Border). A "BackdropTemplate"
-- frame works on every flavor (the option panels already use it), giving the genuine native look.
local function AddSliderTrack(s)
  if not s or s._gseTrack then return end
  s._gseTrack = true
  local track = CreateFrame("Frame", nil, s:GetParent(), "BackdropTemplate")
  track:SetAllPoints(s)
  track:SetFrameLevel(math.max(0, (s:GetFrameLevel() or 1) - 1))  -- sits behind the thumb
  if track.SetBackdrop then
    track:SetBackdrop({
      bgFile   = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
      tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  else
    -- Fallback (no BackdropTemplate): groove texture only, no end-caps.
    local bar = track:CreateTexture(nil, "BACKGROUND")
    bar:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    if bar.SetHorizTile then bar:SetHorizTile(true) end
    bar:SetHeight(8)
    bar:SetPoint("LEFT", track, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", track, "RIGHT", 0, 0)
  end
  s._gseTrack = track
end

local function MakeSlider(pane, y, desc)
  local get, set = ResolveGet(desc.get), ResolveSet(desc.set)
  local name = UName("Slider")
  local sliderW = desc.width or 280  -- single-row sliders are wide (their own line)
  local s = CreateFrame("Slider", name, pane, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", pane, "TOPLEFT", 20, y - 16)
  s:SetWidth(sliderW)
  AddSliderTrack(s)
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
    if desc.percent then return tostring(math.floor((v or 0) + 0.5)) .. "%" end
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
  -- Optional: grey the slider out (disabled + dimmed) while another setting controls its value
  -- automatically (e.g. AH Scale while the Target Portrait auto-sizes the highlight). Re-evaluated
  -- on every panel refresh so it tracks the dependency live.
  if desc.disableGet then
    local disableGet = ResolveGet(desc.disableGet)
    activeRefreshers[#activeRefreshers + 1] = function()
      local off = disableGet() and true or false
      if off then
        if s.Disable then s:Disable() end
        s:SetAlpha(0.4); val:SetAlpha(0.4); if title then title:SetAlpha(0.4) end
      else
        if s.Enable then s:Enable() end
        s:SetAlpha(1); val:SetAlpha(1); if title then title:SetAlpha(1) end
      end
    end
  end
  if desc.center then
    CenterPaneRow(pane, { s }, 20, 20 + sliderW + 10 + (val:GetStringWidth() or 0))
  end
  return RH_SLIDER + ROW_PAD
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
  return RH_LINE + ROW_PAD
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
  return RH_LINE + ROW_PAD
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
  return RH_LINE + ROW_PAD
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
  AddSliderTrack(s)
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
  return RH_LINE + ROW_PAD
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
  return RH_CHECK + ROW_PAD
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
  return RH_COLOR + ROW_PAD
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
  return RH_CHECK + ROW_PAD
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
  return RH_CHECK + ROW_PAD
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

  -- desc.cols = { x1, x2 } pins each checkbox at a FIXED pane x (a stacked grid that lines up across
  -- rows), instead of chaining the 2nd after the 1st label.
  cbA = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbA:SetSize(26, 26)
  cbA:SetPoint("TOPLEFT", pane, "TOPLEFT", (desc.cols and desc.cols[1]) or ROW_X, y)
  local lA = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lA:SetPoint("LEFT", cbA, "RIGHT", 4, 0)
  lA:SetText(desc.label)
  StyleCheckLabel(lA)
  AttachTooltip(cbA, desc.label, desc.tooltip)
  cbA:SetScript("OnClick", function() pick(false) end)
  -- Optionally grey out the FIRST source (e.g. "GSE Sequence Name" when GSE isn't installed):
  -- disable the box and dim its label; the effective getter already falls back to the 2nd source.
  local naGet = desc.unavailableA and ResolveGet(desc.unavailableA) or nil
  if naGet and naGet() then
    if cbA.SetEnabled then cbA:SetEnabled(false) else cbA:Disable() end
    cbA:EnableMouse(false)
    lA:SetTextColor(0.5, 0.5, 0.5)
  end

  cbB = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
  cbB:SetSize(26, 26)
  if desc.cols and desc.cols[2] then
    cbB:SetPoint("TOPLEFT", pane, "TOPLEFT", desc.cols[2], y)
  else
    cbB:SetPoint("LEFT", lA, "RIGHT", COL_GAP, 0)
  end
  local lB = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lB:SetPoint("LEFT", cbB, "RIGHT", 4, 0)
  lB:SetText(desc.label2 or "")
  StyleCheckLabel(lB)
  AttachTooltip(cbB, desc.label2, desc.tooltip2)
  cbB:SetScript("OnClick", function() pick(true) end)
  refresh()

  -- Real row width for centering: ROW_X + each (checkbox + gap + label) + COL_GAP between groups.
  local rowRight = ROW_X + 26 + 4 + (lA:GetStringWidth() or 0)
                 + COL_GAP + 26 + 4 + (lB:GetStringWidth() or 0)
  if desc.get3 then
    local g3, s3 = ResolveGet(desc.get3), ResolveSet(desc.set3)
    local cb3 = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    cb3:SetSize(26, 26)
    if desc.cols and desc.cols[3] then
      cb3:SetPoint("TOPLEFT", pane, "TOPLEFT", desc.cols[3], y)
    else
      cb3:SetPoint("LEFT", lB, "RIGHT", COL_GAP, 0)
    end
    cb3:SetChecked(g3() and true or false)
    cb3:SetScript("OnClick", function(self) s3(self:GetChecked() and true or false) end)
    local l3 = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    l3:SetPoint("LEFT", cb3, "RIGHT", 4, 0)
    l3:SetText(desc.label3 or "")
    StyleCheckLabel(l3)
    AttachTooltip(cb3, desc.label3, desc.tooltip3)
    rowRight = rowRight + COL_GAP + 26 + 4 + (l3:GetStringWidth() or 0)
  end
  -- Only the lead checkbox is pane-anchored (the rest chain off it), so shifting just cbA slides
  -- the whole row.
  if desc.center and not desc.cols and cbA then CenterPaneRow(pane, { cbA }, ROW_X, rowRight) end
  return RH_CHECK + ROW_PAD
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
  AddSliderTrack(s)
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
  return RH_LINE + ROW_PAD
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
  return RH_CHECK + ROW_PAD
end

-- An inline drag-and-drop arranger for the Meters cluster: the readouts (DPS/HPS/GCD), the centre Marker,
-- and optional cooldowns -- all following the same rules. Rendered inline in the Meters edit panel as a
-- flush 5x5 grid of 25 cells (M is the true centre row/column). Drag a chip onto any cell to place it, drop
-- onto an occupied cell to swap; the "+" cells add optional elements. Writes through Meter_SetElementSlot so
-- the live HUD mirrors every change instantly, and reads Meter_GetElementSlots as the source of truth.
local function MakeMeterSlots(pane, y, desc)
  local topPad = 8
  local BOX_W, BOX_H = 440, 150
  local CHIP_W, CHIP_H = 82, 24
  local HGAP, VGAP = CHIP_W, CHIP_H     -- 0px gap (cells flush)
  local GRID_CY = -8                     -- grid sits just under the gold heading (tight vertical padding)

  local container = CreateFrame("Frame", nil, pane)
  container:SetSize(BOX_W, BOX_H)
  container:SetPoint("TOP", pane, "TOP", 0, y - topPad)

  -- Gold section heading above the grid.
  local heading = container:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  heading:SetPoint("TOP", container, "TOP", 0, -2)
  heading:SetText("Layout Control")
  heading:SetTextColor(1, 0.82, 0)  -- WoW gold

  -- 25 cells: 5 columns (LL/L/C/R/RR) x 5 rows (TT/T/M/B/XB) -- MUST match Meters.lua's slot model.
  -- 5 rows = odd, so M is the true centre row.
  local SLOTS = {
    "TTLL", "TTL", "TTC", "TTR", "TTRR",
    "LLT",  "TL",  "T",   "TR",  "RRT",
    "LL",   "L",   "C",   "R",   "RR",
    "LLB",  "BL",  "B",   "BR",  "RRB",
    "XBLL", "XBL", "XBC", "XBR", "XBRR",
  }
  local COLX = { LL = -2 * HGAP, L = -HGAP, C = 0, R = HGAP, RR = 2 * HGAP }
  local ROWY = { TT = 2 * VGAP, T = VGAP, M = 0, B = -VGAP, XB = -2 * VGAP }
  local COL  = {
    TTLL= "LL", TTL= "L", TTC="C", TTR= "R", TTRR= "RR",
    LLT = "LL", TL = "L", T = "C", TR = "R", RRT = "RR",
    LL  = "LL", L  = "L", C = "C", R  = "R", RR  = "RR",
    LLB = "LL", BL = "L", B = "C", BR = "R", RRB = "RR",
    XBLL= "LL", XBL= "L", XBC="C", XBR= "R", XBRR= "RR",
  }
  local ROW  = {
    TTLL= "TT", TTL= "TT",TTC="TT",TTR= "TT",TTRR= "TT",
    LLT = "T",  TL = "T", T = "T", TR = "T", RRT = "T",
    LL  = "M",  L  = "M", C = "M", R  = "M", RR  = "M",
    LLB = "B",  BL = "B", B = "B", BR = "B", RRB = "B",
    XBLL= "XB", XBL= "XB",XBC="XB",XBR= "XB",XBRR= "XB",
  }

  -- Build the 9 drop-zones (faint target; a thin border if BackdropTemplate is available).
  local zones = {}
  for _, slot in ipairs(SLOTS) do
    local ok, z = pcall(CreateFrame, "Frame", nil, container, "BackdropTemplate")
    if not ok or not z then z = CreateFrame("Frame", nil, container) end
    z:SetSize(CHIP_W, CHIP_H)
    z:SetPoint("CENTER", container, "CENTER", COLX[COL[slot]], GRID_CY + ROWY[ROW[slot]])
    local zbg = z:CreateTexture(nil, "BACKGROUND")
    zbg:SetAllPoints(z); zbg:SetColorTexture(1, 1, 1, 0.04)
    if z.SetBackdrop then
      z:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      z:SetBackdropBorderColor(1, 1, 1, 0.15)
    end
    zones[slot] = z
  end

  -- The visible centre marker is the COMBAT marker (anchored to UIParent centre + offset), not the meters
  -- MarkerFrame -- so after a Marker move we must re-apply its position (it adds Meter_GetMarkerCellOffset).
  -- Also refresh the Assisted Highlight, which mirrors its icon at the marker when "Assisted Highlight" is the
  -- chosen centre marker.
  local function RefreshCenterMarker()
    if addon.RefreshCombatMarker then addon:RefreshCombatMarker(false)
    elseif addon.RefreshCenterMarker then addon:RefreshCenterMarker(false) end
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
  end

  -- One chip + one "+" add-button per cell. Redraw() shows the chip (labelled with the cell's occupant) on
  -- filled cells and the "+" on empty cells (when there's something left to add). Chips drag to rearrange
  -- (swap on drop); right-clicking an OPTIONAL element's chip removes it. The "+" opens a menu of the
  -- not-yet-placed optional elements (Trinkets, Healthstone, ...).
  local cellChips, cellPlus = {}, {}
  local Redraw, OpenAddMenu
  local menuFrame  -- reused dropdown frame for the EasyMenu (Classic) fallback

  OpenAddMenu = function(anchorBtn, cell)
    local items = (_G.Meter_GetAvailableElements and _G.Meter_GetAvailableElements()) or {}
    if #items == 0 then return end
    local function pick(id)
      if _G.Meter_SetElementSlot then _G.Meter_SetElementSlot(id, cell) end
      RefreshCenterMarker(); Redraw()
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(anchorBtn, function(_, root)
        root:CreateTitle("Add element")
        for _, e in ipairs(items) do root:CreateButton(e.label, function() pick(e.id) end) end
      end)
    elseif EasyMenu then
      menuFrame = menuFrame or CreateFrame("Frame", "GSETrackerMeterAddMenu", UIParent, "UIDropDownMenuTemplate")
      local menu = {}
      for _, e in ipairs(items) do
        menu[#menu + 1] = { text = e.label, notCheckable = true, func = function() pick(e.id) end }
      end
      EasyMenu(menu, menuFrame, anchorBtn, 0, 0, "MENU")
    end
  end

  for _, slot in ipairs(SLOTS) do
    local zone = zones[slot]

    local chip = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    chip:SetSize(CHIP_W, CHIP_H)
    chip:SetPoint("CENTER", zone, "CENTER", 0, 0)
    chip:SetMovable(true)
    chip:RegisterForDrag("LeftButton")
    chip:RegisterForClicks("RightButtonUp")
    chip:SetScript("OnDragStart", function(self)
      self:SetFrameLevel((container:GetFrameLevel() or 1) + 20)  -- float above the zones + other chips
      self:StartMoving()
    end)
    chip:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local mx, my = self:GetCenter()  -- nearest cell zone (Euclidean to each zone centre)
      local best, bestd
      for s2, z2 in pairs(zones) do
        local zx, zy = z2:GetCenter()
        if mx and zx then
          local d = (mx - zx) ^ 2 + (my - zy) ^ 2
          if not bestd or d < bestd then bestd, best = d, s2 end
        end
      end
      if best and self.elementId and _G.Meter_SetElementSlot then _G.Meter_SetElementSlot(self.elementId, best) end
      RefreshCenterMarker(); Redraw()
    end)
    chip:SetScript("OnClick", function(self, button)
      if button == "RightButton" and self.elementId and _G.Meter_RemoveElement then
        _G.Meter_RemoveElement(self.elementId)  -- any element (DPS/HPS/GCD/Marker or a cooldown) -> the + list
        RefreshCenterMarker(); Redraw()
      end
    end)
    AttachTooltip(chip, "Element", "Drag to move (swaps on drop). Right-click to remove it (it returns to the + list).")
    cellChips[slot] = chip

    local plus = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    plus:SetSize(CHIP_W, CHIP_H)
    plus:SetPoint("CENTER", zone, "CENTER", 0, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function(self) OpenAddMenu(self, slot) end)
    AttachTooltip(plus, "Add", "Add a readout (DPS/HPS/GCD/Marker) or a Trinket / Healthstone / cooldown to this cell.")
    cellPlus[slot] = plus
  end

  Redraw = function()
    local map = (_G.Meter_GetElementSlots and _G.Meter_GetElementSlots()) or {}
    local occ = {}
    for id, cell in pairs(map) do occ[cell] = id end
    local avail = (_G.Meter_GetAvailableElements and _G.Meter_GetAvailableElements()) or {}
    local hasAvail = #avail > 0
    for _, slot in ipairs(SLOTS) do
      local id = occ[slot]
      local chip, plus = cellChips[slot], cellPlus[slot]
      chip:ClearAllPoints()
      chip:SetPoint("CENTER", zones[slot], "CENTER", 0, 0)
      chip:SetFrameLevel((zones[slot]:GetFrameLevel() or 1) + 4)
      if id then
        chip.elementId = id
        chip:SetText((_G.Meter_ElementLabel and _G.Meter_ElementLabel(id)) or id)
        chip:Show(); plus:Hide()
      else
        chip.elementId = nil
        chip:Hide()
        if hasAvail then plus:Show() else plus:Hide() end
      end
    end
  end

  Redraw()
  return topPad + BOX_H + ROW_PAD
end

local RENDERERS = {
  header = MakeHeader, check = MakeCheck, slider = MakeSlider, dropdown = MakeDropdown,
  color = MakeColor, enableshow = MakeEnableShow, dropdownslider = MakeDropdownSlider,
  dualslider = MakeDualSlider, borderrow = MakeBorderRow, dualdropdown = MakeDualDropdown,
  dualcheck = MakeDualCheck, matchrow = MakeMatchRow, checkcolor = MakeCheckColor,
  spacer = MakeSpacer, namesource = MakeNameSourceRow, dropdowncheck = MakeDropdownCheck,
  tricolor = MakeTriColor, button = MakeButton, meterslots = MakeMeterSlots,
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

-- ═════════════════════════════════════════════════════════════════════════════
-- Native Edit Mode row renderer
-- Rebuilds option descriptors into the EXACT layout of Blizzard's EditModeSystemSettingsDialog
-- (dumped via GSEBlizzardDefault -- see the native-editmode-dialog-spec memory): one setting per
-- row, label on the LEFT (GameFontHighlightMedium size 14, white), control on the RIGHT, each row
-- 32px tall on a 34px pitch, 20px side margins. Composite descriptors are EXPANDED into multiple
-- native rows (a dropdown+slider row becomes two rows; a dual-checkbox row becomes two checkbox
-- rows). Reuses the same get/set resolution and native widgets as the compact renderer so behaviour
-- is identical -- only the presentation matches Blizzard.
-- ═════════════════════════════════════════════════════════════════════════════
local NATIVE_MARGIN   = 20   -- container side margin (native: 20)
local NATIVE_ROW_H    = 32   -- row height (native: 32)
local NATIVE_PITCH    = 34   -- vertical distance between rows (native: 34)
local NATIVE_LABEL_W  = 150  -- label column width
local NATIVE_CTRL_X   = 160  -- control left edge (label.RIGHT + ~5, matching native spacing)
local NATIVE_CTRL_W   = 200  -- control column width (native control container: 200)

local function NRow(pane, y)
  local row = CreateFrame("Frame", nil, pane)
  row:SetHeight(NATIVE_ROW_H)
  row:SetPoint("TOPLEFT",  pane, "TOPLEFT",  NATIVE_MARGIN, y)
  row:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -NATIVE_MARGIN, y)
  return row
end

-- Left-hand setting label (native: GameFontHighlightMedium 14, white, left-justified).
local function NLabel(row, text)
  local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
  fs:SetPoint("LEFT", row, "LEFT", 0, 0)
  fs:SetWidth(NATIVE_LABEL_W); fs:SetJustifyH("LEFT")
  fs:SetText(text or ""); fs:SetTextColor(1, 1, 1)
  return fs
end

-- Dropdown in the right control column.
local function NDropdown(row, opts, get, set, tip, tipTitle)
  local dd = CreateWowDropdown(row, NATIVE_CTRL_W, opts, get, set)
  dd:SetPoint("LEFT", row, "LEFT", NATIVE_CTRL_X, 0)
  AttachTooltip(dd, tipTitle, tip)
  return dd
end

-- Slider in the right control column. Uses Blizzard's native MinimalSliderWithSteppersTemplate -- the
-- exact "< [====O====] >" stepper slider the HUD Edit Mode dialogs use, with the value (gold) shown on
-- the right. API confirmed from Baganator/LibEditMode: Init(value, min, max, numSteps, formatters) +
-- RegisterCallback(...Event.OnValueChanged).
local function NSlider(row, get, set, minV, maxV, step, percent, float, tip, tipTitle, fullWidth)
  minV, maxV, step = minV or 0, maxV or 1, step or 1
  local s = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
  s:SetPoint("LEFT",  row, "LEFT",  fullWidth and 0 or NATIVE_CTRL_X, 0)
  -- The value (gold) renders to the RIGHT of the slider frame, so inset the frame's right edge ~30px
  -- so the number lands with the same right padding as the dropdowns (which end at the row's right).
  s:SetPoint("RIGHT", row, "RIGHT", -30, 0)
  s:SetHeight(20)
  local function fmt(v)
    v = float and (v or 0) or math.floor((v or 0) + 0.5)
    if percent then return tostring(v) .. "%" end
    return float and string.format("%.2f", v) or tostring(v)
  end
  local steps = math.max(1, math.floor((maxV - minV) / step + 0.5))
  local formatters
  if MinimalSliderWithSteppersMixin and CreateMinimalSliderFormatter then
    formatters = {
      [MinimalSliderWithSteppersMixin.Label.Right] =
        CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmt(v) end),
    }
  end
  local cur = tonumber(get()) or minV
  s:Init(cur, minV, maxV, steps, formatters)
  -- Register AFTER Init so the initial value doesn't fire our setter.
  s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
    set(float and v or math.floor((v or 0) + 0.5))
  end)
  AttachTooltip(s, tipTitle, tip)
  return s
end

-- Checkbox row: native 28px UICheckButton on the left, label to its right.
local function NCheck(row, label, get, set, disableGet, tip)
  local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cb:SetSize(28, 28)
  -- -4 (not 0): the UICheckButtonTemplate insets its check texture inside the 28px button, so an x=0
  -- frame reads as indented vs plain left-justified labels and the tricolor cbClass box (also at -4).
  -- This lines every checkbox's VISIBLE box up with the labels and with each other.
  cb:SetPoint("LEFT", row, "LEFT", -4, 0)
  cb:SetChecked(get() and true or false)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  local l = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
  l:SetPoint("LEFT", cb, "RIGHT", 5, 0); l:SetText(label or ""); l:SetTextColor(1, 1, 1)
  if disableGet and disableGet() then
    if cb.SetEnabled then cb:SetEnabled(false) else cb:Disable() end
    cb:EnableMouse(false); l:SetTextColor(0.5, 0.5, 0.5)
  end
  AttachTooltip(cb, label, tip)
  return cb, l
end

-- Render a descriptor list as native one-per-row rows. Returns nothing; sizes the pane to content.
-- Live grey-out for native rows: disables the given controls + dims their labels whenever disableName()
-- is true. Registered as an activeRefresher so it re-evaluates on every settings change (e.g. greying the
-- keybind Font/Size/Location when the Assisted Highlight is anchored to the Target Portrait).
local function NDisable(disableName, controls, labels)
  if not disableName then return end
  local dg = ResolveGet(disableName)
  activeRefreshers[#activeRefreshers + 1] = function()
    local off = dg() and true or false
    for _, c in ipairs(controls) do
      if c then
        if c.SetEnabled then c:SetEnabled(not off)
        elseif off and c.Disable then c:Disable()
        elseif (not off) and c.Enable then c:Enable() end
      end
    end
    for _, l in ipairs(labels) do
      if l and l.SetTextColor then
        if off then l:SetTextColor(0.5, 0.5, 0.5) else l:SetTextColor(1, 1, 1) end
      end
    end
  end
end

local function PopulateNative(pane, rows)
  local y = -12
  local function adv(h) y = y - (h or NATIVE_PITCH) end
  for _, r in ipairs(rows) do
    local t = r.type
    if t == "header" then
      -- Skip section headers: the window title bar already names the element, and Blizzard's native
      -- Edit Mode dialogs have no gold section-header text. (No row, no vertical advance.)
    elseif t == "spacer" then
      adv(r.h or 12)
    elseif t == "dropdown" then
      local row = NRow(pane, y); local lbl = NLabel(row, r.label)
      local dd = NDropdown(row, r.options, ResolveGet(r.get), ResolveSet(r.set), r.tooltip, r.label)
      adv()
      if r.disableGet then NDisable(r.disableGet, { dd }, { lbl }) end
    elseif t == "slider" then
      local sFrame, sLabel
      if r.stacked then
        -- "Scale" sliders: label STACKED + CENTERED over a full-width slider.
        local rowL = NRow(pane, y)
        local lbl = rowL:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
        -- Centered over the slider track. The slider is inset 30px on the right (for its value), so its
        -- track centre sits 15px left of the row centre -- offset the label to match.
        lbl:SetPoint("CENTER", rowL, "CENTER", -15, 0)
        lbl:SetText(r.label or ""); lbl:SetTextColor(1, 1, 1)
        sLabel = lbl
        adv()
        local rowS = NRow(pane, y)
        sFrame = NSlider(rowS, ResolveGet(r.get), ResolveSet(r.set), r.min, r.max, r.step, r.percent, r.float, r.tooltip, r.label, true)
        adv()
      else
        -- Inline slider: label left, slider right (like the dropdown-slider rows).
        local row = NRow(pane, y); sLabel = NLabel(row, r.label)
        sFrame = NSlider(row, ResolveGet(r.get), ResolveSet(r.set), r.min, r.max, r.step, r.percent, r.float, r.tooltip, r.label)
        adv()
      end
      -- Live grey-out: e.g. the Assisted Highlight Scale is disabled in Target Portrait mode (auto-sized).
      -- A refresher re-evaluates on every settings change (ResolveSet -> ScheduleRefresh -> RunRefreshers).
      if r.disableGet then
        local dg = ResolveGet(r.disableGet)
        activeRefreshers[#activeRefreshers + 1] = function()
          local off = dg() and true or false
          if sFrame then
            if sFrame.SetEnabled then sFrame:SetEnabled(not off)
            elseif off and sFrame.Disable then sFrame:Disable() end
          end
          if sLabel and sLabel.SetTextColor then
            if off then sLabel:SetTextColor(0.5, 0.5, 0.5) else sLabel:SetTextColor(1, 1, 1) end
          end
        end
      end
    elseif t == "tricolor" then
      -- Lead toggle (e.g. "Press Detection") on its own row, then Class/Custom + colour swatch on the next.
      if r.leadLabel then
        local rowL = NRow(pane, y)
        NCheck(rowL, r.leadLabel, ResolveGet(r.leadGet), ResolveSet(r.leadSet), nil, r.tooltipLead)
        adv()
      end
      local row = NRow(pane, y)
      local modeGet, modeSet   = ResolveGet(r.get), ResolveSet(r.set)
      local colorGet, colorSet = ResolveGet(r.colorGet), ResolveSet(r.colorSet)
      local cbClass, cbCustom
      local function refresh()
        local m = modeGet()
        if cbClass  then cbClass:SetChecked(m == "class") end
        if cbCustom then cbCustom:SetChecked(m == "custom") end
      end
      cbClass = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      -- The check texture is inset inside the 28px button, so a x=0 frame reads as indented vs a plain
      -- left-justified label (e.g. the Scale label above). Pull it left so the visible box lines up.
      cbClass:SetSize(28, 28); cbClass:SetPoint("LEFT", row, "LEFT", -4, 0)
      cbClass:SetScript("OnClick", function() modeSet(modeGet() == "class" and "none" or "class"); refresh() end)
      local lC = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
      lC:SetPoint("LEFT", cbClass, "RIGHT", 5, 0); lC:SetText(r.label or "Class Color"); lC:SetTextColor(1, 1, 1)
      AttachTooltip(cbClass, r.label, r.tooltip)
      cbCustom = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      cbCustom:SetSize(28, 28); cbCustom:SetPoint("LEFT", lC, "RIGHT", 16, 0)
      cbCustom:SetScript("OnClick", function() modeSet(modeGet() == "custom" and "none" or "custom"); refresh() end)
      local lU = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
      lU:SetPoint("LEFT", cbCustom, "RIGHT", 5, 0); lU:SetText(r.label2 or "Custom"); lU:SetTextColor(1, 1, 1)
      AttachTooltip(cbCustom, r.label2, r.tooltip2)
      local btn = CreateFrame("Button", nil, row)
      btn:SetSize(20, 20); btn:SetPoint("LEFT", lU, "RIGHT", 6, 0)
      local bd = btn:CreateTexture(nil, "BACKGROUND"); bd:SetPoint("TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", 1, -1); bd:SetColorTexture(0, 0, 0, 1)
      local sw = btn:CreateTexture(nil, "ARTWORK"); sw:SetAllPoints(btn)
      local function paint() local cr, cg, cb = colorGet(); sw:SetColorTexture(cr or 1, cg or 1, cb or 1) end
      paint()
      btn:SetScript("OnClick", function()
        local cr, cg, cb = colorGet(); cr, cg, cb = cr or 1, cg or 1, cb or 1
        if ColorPickerFrame.SetupColorPickerAndShow then
          ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); colorSet(nr, ng, nb); paint() end,
            cancelFunc = function() colorSet(cr, cg, cb); paint() end,
            hasOpacity = false, r = cr, g = cg, b = cb,
          })
        end
      end)
      refresh()
      adv()
    elseif t == "dropdownslider" then
      local row = NRow(pane, y); local lbl = NLabel(row, r.label)
      local dd = NDropdown(row, r.options, ResolveGet(r.get), ResolveSet(r.set), r.tooltip, r.label)
      adv()
      local row2 = NRow(pane, y); local sLabel = NLabel(row2, r.sliderLabel)
      local sFrame = NSlider(row2, ResolveGet(r.sliderGet), ResolveSet(r.sliderSet), r.smin, r.smax, r.sstep, r.percent, r.sfloat, r.tooltip2, r.sliderLabel)
      adv()
      -- Grey the WHOLE row -- dropdown + slider + both labels (e.g. the AH keybind Font/Size when the
      -- keybind is hidden in Target Portrait mode).
      if r.disableGet then NDisable(r.disableGet, { dd, sFrame }, { lbl, sLabel }) end
      -- Live grey-out of the slider half only (e.g. AH Opacity is disabled in Target Portrait mode,
      -- which fades the highlight itself). Same refresher pattern as the standalone "slider" type.
      if r.sliderDisableGet then
        local dg = ResolveGet(r.sliderDisableGet)
        activeRefreshers[#activeRefreshers + 1] = function()
          local off = dg() and true or false
          if sFrame then
            if sFrame.SetEnabled then sFrame:SetEnabled(not off)
            elseif off and sFrame.Disable then sFrame:Disable() end
          end
          if sLabel and sLabel.SetTextColor then
            if off then sLabel:SetTextColor(0.5, 0.5, 0.5) else sLabel:SetTextColor(1, 1, 1) end
          end
        end
      end
    elseif t == "dropdowncheck" then
      local row = NRow(pane, y); NLabel(row, r.label)
      NDropdown(row, r.options, ResolveGet(r.get), ResolveSet(r.set), r.tooltip, r.label)
      adv()
      local row2 = NRow(pane, y)
      NCheck(row2, r.checkLabel, ResolveGet(r.checkGet), ResolveSet(r.checkSet), nil, r.tooltip2)
      adv()
    elseif t == "dualcheck" then
      if r.inline2 then
        -- Both checkboxes on ONE row: [check] label   [check] label2 (label2 sits in the control column).
        local row = NRow(pane, y)
        NCheck(row, r.label, ResolveGet(r.get), ResolveSet(r.set), r.disable and ResolveGet(r.disable) or nil, r.tooltip)
        local cb2 = NCheck(row, r.label2, ResolveGet(r.get2), ResolveSet(r.set2), r.disable2 and ResolveGet(r.disable2) or nil, r.tooltip2)
        if cb2 then cb2:ClearAllPoints(); cb2:SetPoint("LEFT", row, "LEFT", NATIVE_CTRL_X, 0) end
        adv()
      else
        local row = NRow(pane, y)
        NCheck(row, r.label, ResolveGet(r.get), ResolveSet(r.set), r.disable and ResolveGet(r.disable) or nil, r.tooltip)
        adv()
        local row2 = NRow(pane, y)
        NCheck(row2, r.label2, ResolveGet(r.get2), ResolveSet(r.set2), r.disable2 and ResolveGet(r.disable2) or nil, r.tooltip2)
        adv()
        if r.label3 and r.get3 then  -- optional third checkbox (e.g. AH "Show GCD Swipe")
          local row3 = NRow(pane, y)
          NCheck(row3, r.label3, ResolveGet(r.get3), ResolveSet(r.set3), r.disable3 and ResolveGet(r.disable3) or nil, r.tooltip3)
          adv()
        end
      end
    elseif t == "matchrow" then
      -- Row 1: [check] AH Match % (4/99). Row 2: [check] AH Match Audible + sound dropdown.
      -- Both rows are greyed out (live) when "Rotation Matching System" is OFF.
      local row1 = NRow(pane, y)
      local cb1, lbl1 = NCheck(row1, r.label, ResolveGet(r.get), ResolveSet(r.set), nil, r.tooltip)
      adv()
      local row2 = NRow(pane, y)
      local cb2, lbl2 = NCheck(row2, r.label2, ResolveGet(r.audGet), ResolveSet(r.audSet), nil, r.tooltip2)
      local dd = NDropdown(row2, r.ddoptions, ResolveGet(r.ddget), ResolveSet(r.ddset), r.tooltip2, r.label2)
      adv()
      -- Shift BOTH checkbox+label groups right 10px (move the checkboxes; their labels are anchored off
      -- them so they follow). The dropdown is anchored to the row, so it stays put.
      if cb1 then cb1:ClearAllPoints(); cb1:SetPoint("LEFT", row1, "LEFT", 10, 0) end
      if cb2 then cb2:ClearAllPoints(); cb2:SetPoint("LEFT", row2, "LEFT", 10, 0) end
      -- Live enable/disable based on Rotation Matching System (the master switch for match tracking).
      local function setOn(w, on, lbl)
        if not w then return end
        if w.SetEnabled then w:SetEnabled(on) end
        if w.EnableMouse then w:EnableMouse(on) end
        if lbl then local c = on and 1 or 0.5; lbl:SetTextColor(c, c, c) end
      end
      activeRefreshers[#activeRefreshers + 1] = function()
        local on = (addon.GetProcGlowEnabled and addon:GetProcGlowEnabled()) and true or false
        setOn(cb1, on, lbl1)
        setOn(cb2, on, lbl2)
        -- The sound dropdown also needs Match Audible itself enabled.
        local ddOn = on and (addon.GetAHMatchAudibleEnabled and addon:GetAHMatchAudibleEnabled()) and true or false
        setOn(dd, ddOn)
      end
    elseif t == "namesource" then
      -- Two mutually-exclusive sources rendered as two checkbox rows (kept simple in native layout).
      local row = NRow(pane, y)
      NCheck(row, r.label, ResolveGet(r.get), ResolveSet(r.set), r.unavailableA and ResolveGet(r.unavailableA) or nil, r.tooltip)
      adv()
      local row2 = NRow(pane, y)
      NCheck(row2, r.label2, function() return ResolveGet(r.get)() and true or false end, function(v) ResolveSet(r.set)(v) end, nil, r.tooltip2)
      adv()
    elseif t == "check" then
      local row = NRow(pane, y)
      NCheck(row, r.label, ResolveGet(r.get), ResolveSet(r.set), r.disable and ResolveGet(r.disable) or nil, r.tooltip)
      adv()
    elseif t == "enableshow" then
      local row = NRow(pane, y)
      NCheck(row, r.label, ResolveGet(r.get), ResolveSet(r.set), r.unavailable and ResolveGet(r.unavailable) or nil, r.tooltip)
      adv()
      if r.showOptions then
        local row2 = NRow(pane, y); NLabel(row2, r.showHeader or "Visibility")
        NDropdown(row2, r.showOptions, ResolveGet(r.showGet), ResolveSet(r.showSet))
        adv()
      end
    elseif t == "meterslots" then
      -- The drag-and-drop readout arranger (shared with the compact renderer). Returns its full height so
      -- the pane -- and therefore the auto-fitted window -- grows to include it.
      adv(MakeMeterSlots(pane, y, r))
    else
      -- Unknown/unsupported-in-native type: skip with a small gap (covered as the rollout expands).
      adv(8)
    end
  end
  pane:SetHeight(math.max(-y, 1))  -- end right at the last row (~2px); the window adds a uniform bottom pad
  RunRefreshers()
end

-- Per-tab "is this element DISABLED?" check -- greys out the row's Edit Mode button so you can't enter
-- Edit Mode for an element that won't show anything. (1=Meters, 2=Action Tracker, 3=Assisted Highlight,
-- 4=Pressed Indicator -- same enable sources as the Enable checkboxes + ui/editmode.lua box gating.)
local EDITMODE_DISABLE = {
  [1] = function() return _G.MetersSavedVars and _G.MetersSavedVars.enabled == false end,
  [2] = function() return addon.IsEnabled and not addon:IsEnabled() end,
  [3] = function() return addon.IsAssistedHighlightMirrorEnabled and not addon:IsAssistedHighlightMirrorEnabled() end,
  [4] = function()
    local cfg = addon.GetElementLayout and addon:GetElementLayout("pressedIndicator")
    return type(cfg) == "table" and cfg.enabled == false
  end,
}

-- A small "Edit Mode" button pinned to the RIGHT of an enable/show row (spanRight -> overlays the row,
-- takes no height). Enters Edit Mode via the secure /editmode macro, then opens that element's options
-- panel (tabIdx into EDITMODE_TABS: Meters=1, Action Tracker=2, Assisted Highlight=3). See ui/editmode.lua.
local function EditModeButtonDesc(tabIdx, headerText)
  return {
    type = "button", label = "Edit Mode", red = true, spanRight = true, width = 92, height = 24, rightInset = 16,
    spanHeader = headerText,  -- white column label drawn above this button (set only on the top row)
    disableGet = tabIdx and EDITMODE_DISABLE[tabIdx] or nil,  -- grey out when the element is disabled
    tooltip = "Enter Edit Mode and open this element's options. (Can't be entered during combat.)",
    secureMacro = function()
      if _G.SlashCmdList and _G.SlashCmdList.EDITMODE and _G.SLASH_EDITMODE1 then return _G.SLASH_EDITMODE1 end
      return nil
    end,
    preClick = function()
      if _G.InCombatLockdown and _G.InCombatLockdown() then
        local cf = _G.DEFAULT_CHAT_FRAME
        if cf and cf.AddMessage then
          cf:AddMessage("|cFFFFFFFFGS|r|cFF00FFFFE|r|cFFFFFF00: Tracker|r |cffff5555Edit Mode can't be entered during combat.|r Try again after combat.")
        end
        return
      end
      if _G.HideUIPanel and _G.SettingsPanel and _G.SettingsPanel.IsShown and _G.SettingsPanel:IsShown() then
        pcall(_G.HideUIPanel, _G.SettingsPanel)
      end
    end,
    onClick = function()
      if _G.InCombatLockdown and _G.InCombatLockdown() then return end
      local EMM = _G.EditModeManagerFrame
      if not (EMM and EMM.IsEditModeActive and EMM:IsEditModeActive()) then
        if _G.GSETracker_EnterEditMode then _G.GSETracker_EnterEditMode() end  -- overlay fallback (no /editmode)
      end
      if tabIdx and _G.GSETracker_EditModeShowTab then _G.GSETracker_EditModeShowTab(tabIdx) end
    end,
  }
end

-- ── Tab content ─────────────────────────────────────────────────────────────
local function GeneralRows()
  return {
    -- "Lock All" removed: lock state now follows Blizzard Edit Mode automatically (locked unless you're in
    -- Edit Mode -- see ui/editmode.lua). Performance Mode lives under the Quality of Life checks.
    { type = "header", text = "Enable" },
    -- One "Edit Mode" button per enable/show row, pinned to the right of each dropdown (overlays the row).
    EditModeButtonDesc(1, "Edit / Options"),  -- Meters (top row: also labels the Edit Mode column)
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
    EditModeButtonDesc(2),  -- Action Tracker
    { type = "enableshow", label = "Action Tracker", get = "IsEnabled", set = "SetEnabled",
      tooltip = "Enable the Action Tracker — the row of upcoming/recent ability icons.",
      showGet = "GetShowWhen", showSet = "SetShowWhen", showOptions = SHOW_OPTIONS },
    EditModeButtonDesc(3),  -- Assisted Highlight
    { type = "enableshow", label = "Assisted Highlight", get = "IsAssistedHighlightMirrorEnabled", set = "SetAssistedHighlightMirrorEnabled",
      unavailable = function() return not (ns.Caps and ns.Caps.assistedHighlight) end,
      tooltip = "Enable the Assisted Highlight icon that shows the next suggested ability.",
      showGet = "GetAssistedHighlightShowWhen", showSet = "SetAssistedHighlightShowWhen", showOptions = SHOW_OPTIONS },
    -- Pressed Indicator: enable checkbox + Visibility dropdown + Edit Mode button. Show-When gates the
    -- indicator in LIVE play (Edit Mode always shows it for positioning); see RefreshPressedIndicator.
    -- Shape/colour/position live in its Edit Mode panel.
    EditModeButtonDesc(4),  -- Pressed Indicator
    { type = "enableshow", label = "Pressed Indicator",
      get = function()
        local cfg, defaults = addon:GetElementLayout("pressedIndicator")
        if type(cfg) == "table" and cfg.enabled ~= nil then return cfg.enabled and true or false end
        if defaults and defaults.enabled ~= nil then return defaults.enabled and true or false end
        return true
      end,
      set = function(v)
        if addon.SetElementEnabled then addon:SetElementEnabled("pressedIndicator", v) end
        if addon.RefreshPressedIndicator then addon:RefreshPressedIndicator(true) end
      end,
      showGet = "GetPressedIndicatorShowWhen", showSet = "SetPressedIndicatorShowWhen", showOptions = SHOW_OPTIONS,
      tooltip = "Enable the Pressed Indicator — the image that flashes when you press your macro key. Visibility gates it in normal play (Edit Mode always shows it). Shape, colour and position are in its Edit Mode panel." },
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
        -- DamageMeter Skinner follows the same Native/adopt switch (Retail, no Details!).
        if _G.GSETracker_MeterSkin_Refresh then _G.GSETracker_MeterSkin_Refresh() end
        if _G.GSETrackerDetails_ApplyBorder then _G.GSETrackerDetails_ApplyBorder() end
      end,
      tooltip = "Force Blizzard's native button art (border, icon crop and FONT style). Unchecked: automatically adopt your skin addon (ElvUI, EllesmereUI, ...) if one is installed." },
    -- Quality of Life + Saved Settings (moved here from the old Quality of Life tab).
    { type = "header", text = "Quality of Life" },
    { type = "dualcheck",
      label = "Mute Fizzle Sounds", get = "GetMuteFizzles", set = "SetMuteFizzles",
      tooltip = "Mute the 'fizzle' sound a spell makes when it fails to cast (out of range, not enough resource, etc.).",
      label2 = "Hide Error Messages", get2 = "GetHideErrors", set2 = "SetHideErrors",
      tooltip2 = "Hide the red Blizzard error text at the top of the screen (e.g. 'Not enough rage', 'Out of range')." },
    { type = "check", label = "Performance Mode", get = "GetPerformanceModeEnabled", set = "SetPerformanceModeEnabledCanonical",
      tooltip = "Disable the Action Tracker's icon slide/fade animations — icons snap instantly into place. Lowers CPU on low-end systems; does NOT change how often the tracker updates." },
    { type = "header", text = "Saved Settings" },
    { type = "check", label = "Account Wide", get = "GetAccountWide", set = "SetAccountWide",
      tooltip = "Share these settings across all your characters. Unchecked: settings are saved per-character." },
    -- Show Minimap Button: pinned to the very bottom of the General tab, centred. (The old "Hide Login
    -- Message" checkbox was removed -- the welcome-window popup no longer shows on login.)
    { type = "spacer", h = 12 },
    { type = "check", center = true,
      label = "Show Minimap Button",
      get = function() return not (addon.GetMinimapHidden and addon:GetMinimapHidden()) end,
      set = function(v) if addon.SetMinimapHidden then addon:SetMinimapHidden(not v) end end,
      tooltip = "Show or hide the GSE: Tracker minimap button." },
    -- (Social icons are no longer an in-flow row -- they live in a persistent footer
    -- pinned to the bottom of the whole settings frame; see BuildPanel.)
  }
end

local function ActionTrackerRows()
  return {
    { type = "header", text = "Action Tracker" },
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
    -- Name source row: GSE Sequence Name | Spell Name -- now INDEPENDENT (check both to stack them;
    -- uncheck both for no name). Fixed columns so they stack with the Swap/Modkey row below.
    { type = "dualcheck", cols = { 90, 320 },
      label = "GSE Sequence Name", get = "GetActionTrackerShowSequenceName",
      set = function(v)
        if addon.SetActionTrackerShowSequenceName then addon:SetActionTrackerShowSequenceName(v) end
        if addon.SetElementEnabled then addon:SetElementEnabled("sequenceText", true) end  -- gate open; empty text hides
        if addon.RebuildNameDisplay then addon:RebuildNameDisplay() end
        if addon.ApplyVisibility then addon:ApplyVisibility() end
      end,
      tooltip = "Show the GSE sequence's name as the tracker title. Can be combined with Spell Name (the two stack).",
      -- No GSE installed -> no sequence names: grey this box out (the tracker uses Spell Name).
      disable = function() return not IsGSEAvailable() end,
      label2 = "Spell Name", get2 = "GetActionTrackerShowSpellName",
      set2 = function(v)
        if addon.SetActionTrackerShowSpellName then addon:SetActionTrackerShowSpellName(v) end
        if addon.SetElementEnabled then addon:SetElementEnabled("sequenceText", true) end
        if addon.RebuildNameDisplay then addon:RebuildNameDisplay() end
        if addon.ApplyVisibility then addon:ApplyVisibility() end
      end,
      tooltip2 = "Show the most recently cast spell's name. Can be combined with GSE Sequence Name (the two stack)." },
    -- Under the name toggles: [check] Modifiers (show/hide the modifier-key readout element) paired on the
    -- SAME row with [check] Side (L/R) (the L/R side prefix). inline2 renders them side-by-side.
    { type = "dualcheck", inline2 = true,
      label = "Modifiers",
      get = function()
        local cfg, defaults = addon:GetElementLayout("modifiersText")
        if type(cfg) == "table" and cfg.enabled ~= nil then return cfg.enabled and true or false end
        if defaults and defaults.enabled ~= nil then return defaults.enabled and true or false end
        return true
      end,
      set = function(v)
        if addon.SetElementEnabled then addon:SetElementEnabled("modifiersText", v) end
        if addon.ApplyVisibility then addon:ApplyVisibility() end
      end,
      tooltip = "Show the modifier-key readout (Shift/Ctrl/Alt) above the icons.",
      label2 = "Side (L/R)", get2 = "GetActionTrackerModkeySide", set2 = "SetActionTrackerModkeySide",
      tooltip2 = "Show the L/R side prefix on modifier keys (e.g. 'LShift+RCtrl' vs 'Shift+Ctrl')." },
    -- Swap Name/ModKeys vertical positions -- now its own row (the side toggle moved up to the Modifiers row).
    { type = "check",
      label = "Swap Name > ModKeys", get = "GetActionTrackerSwapNameModkeys",
      set = function(v)
        if addon.SetActionTrackerSwapNameModkeys then addon:SetActionTrackerSwapNameModkeys(v) end
        if addon.ApplyAllElementPositions then addon:ApplyAllElementPositions() end
      end,
      tooltip = "Swap the vertical positions of the Name (sequence/spell) and the modifier-key letters above the icons. Off = Name on top (default); On = ModKeys on top." },
    { type = "spacer", h = 14 },  -- extra padding below the Name/Modkey checkbox block (before the font rows)
    { type = "dropdownslider", label = "Name", get = "GetSeqFontName", set = "SetSeqFontName", options = FontOptions,
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
    { type = "spacer", h = 12 },  -- top padding above the bottom Scale slider
    { type = "slider", label = "Action Tracker Scale", stacked = true,
      get = function() return math.floor(((addon.GetScale and addon:GetScale()) or 1) * 100 + 0.5) end,
      set = function(v) if addon.SetScaleValue then addon:SetScaleValue((tonumber(v) or 100) / 100) end end,
      min = 0, max = 200, step = 5, percent = true, width = 280, center = true,
      tooltip = "Overall size of the Action Tracker. 100% is normal size." },
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
      -- Shown as a PERCENT: 100% == 38px (the neutral point), range 25%-200% (= 9.5px .. 76px).
      sliderLabel = "Scale",
      sliderGet = function()
        local sz = (addon.GetCombatMarkerSize and addon:GetCombatMarkerSize()) or 38
        return math.floor((sz / 38) * 100 + 0.5)
      end,
      sliderSet = function(v)
        local sz = (tonumber(v) or 100) / 100 * 38
        if addon.SetCombatMarkerSize then addon:SetCombatMarkerSize(sz) end
        if addon.RefreshCombatMarker then addon:RefreshCombatMarker(false) end
        if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
      end,
      smin = 25, smax = 200, sstep = 5, percent = true,
      tooltip2 = "Size of the Center Marker (100% = normal; 25%-200%). Works for all marker types, including Assisted Highlight." },
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

-- Bottom of the Meters tab (below the embedded readout panel): the Font controls, then the Meters
-- Scale slider pinned LAST. The Center Marker section sits at the TOP of the tab (see the TABS
-- entry). Kept compact -- the Meters tab is a fixed-height embedded page (no scroll).
local function MetersBottomRows()
  return {
    { type = "dropdownslider",
      label = "Font", get = MetersFontFaceGet, set = MetersFontFaceSet, options = FontOptions,
      tooltip = "Font for the Meters readout text (DPS/HPS/GCD/%).",
      sliderLabel = "Font Size", sliderGet = MetersFontSizeGet, sliderSet = MetersFontSizeSet, smin = 6, smax = 24, sstep = 1,
      tooltip2 = "Meters text size.",
      unavailable = function() return not (ns.Caps and ns.Caps.meters) end },
    { type = "dropdown", label = "Outline", get = MetersFontOutlineGet, set = MetersFontOutlineSet, options = OUTLINE_OPTIONS,
      tooltip = "Outline style for the Meters readout text.",
      unavailable = function() return not (ns.Caps and ns.Caps.meters) end },
    -- 26 (not 12): Meters has one fewer section than Action Tracker, so this extra ~14px makes the Meters
    -- content the same total height as the Action Tracker content -- the two Edit Mode windows then come
    -- out the same height with identical bottom padding below the Scale slider.
    { type = "spacer", h = 26 },
    { type = "slider", label = "Meters Scale", stacked = true,
      get = function() return math.floor(((_G.Meter_GetScale and _G.Meter_GetScale()) or 1) * 100 + 0.5) end,
      set = function(v) if _G.Meter_SetScale then _G.Meter_SetScale((tonumber(v) or 100) / 100) end end,
      min = 0, max = 200, step = 5, percent = true, width = 280, center = true,
      tooltip = "Scale the Meters readout cluster (DPS/HPS/GCD/% text). 100% is normal size; the General Scale multiplies on top." },
  }
end

local function AssistedHighlightRows()
  return {
    { type = "header", text = "Assisted Highlight" },
    -- Anchor dropdown + Opacity slider share one row.
    { type = "dropdownslider", label = "Anchor", get = "GetAssistedHighlightAnchorTarget", set = "SetAssistedHighlightAnchorTarget", options = ANCHOR_OPTIONS,
      tooltip = "Where the highlight sits: fixed on screen, following the mouse cursor, or over the target's portrait (only shown with an attackable target).",
      sliderLabel = "Opacity", sliderGet = "GetAssistedHighlightAlpha", sliderSet = "SetAssistedHighlightAlpha",
      smin = 0.05, smax = 1.00, sstep = 0.05, sfloat = true,
      tooltip2 = "Opacity of the highlight icon (lower = more transparent).",
      -- Target Portrait mode draws the highlight on the portrait emblem at a fixed opacity, so the
      -- Opacity slider has no effect there -- grey it out (matches the Scale slider's behaviour).
      sliderDisableGet = function()
        return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
      end },
    { type = "header", text = "Display" },
    { type = "dualcheck",
      label = "Range Check", get = "GetAssistedHighlightRangeCheckerEnabled", set = "SetAssistedHighlightRangeCheckerEnabled",
      tooltip = "Red-tint the highlight when the suggested ability is out of range of your target.",
      label2 = "Show GCD Swipe", get2 = "GetAssistedHighlightShowGCD", set2 = "SetAssistedHighlightShowGCD",
      tooltip2 = "Sweep a cooldown 'swipe' across the highlight for the global cooldown." },
    { type = "check", label = "Rotation Matching System", get = "GetProcGlowEnabled", set = "SetProcGlowEnabled",
      unavailable = function() return not (ns.Caps and ns.Caps.assistedHighlight) end,
      tooltip = "Track how often your casts match the Assisted Highlight suggestion (drives the AH Match %% readout and the proc-glow flash)." },
    -- AH Match % readout (under the Action Tracker) + AH Match Audible (its own enable checkbox + sound
    -- dropdown). Both are gated by "Rotation Matching System" -- greyed when it's off (see PopulateNative
    -- "matchrow"). SBA % moved to the standalone SLG-SBA Monitor addon -- this is the AH-only readout.
    { type = "matchrow",
      unavailable = function() return not (ns.Caps and ns.Caps.assistedHighlight) end,
      -- Row 1: [check] AH Match % (4/99)
      label = "AH Match % (4/99)", get = "GetAHMatchPercentEnabled", set = "SetAHMatchPercentEnabled",
      tooltip = "Show the AH Match percentage readout (matched/total) under the Action Tracker.",
      -- Row 2: [check] Match Audible  + short-sound dropdown (<=1s cues only)
      label2 = "Match Audible", audGet = "GetAHMatchAudibleEnabled", audSet = "SetAHMatchAudibleEnabled",
      tooltip2 = "Play a short sound each time your cast matches the Assisted Highlight suggestion.",
      ddget = function() return (addon.GetAHMatchSound and addon:GetAHMatchSound()) or nil end,
      ddset = function(v)
        if addon.SetAHMatchSound then addon:SetAHMatchSound(v) end
        if addon.PlayAHMatchSound then addon:PlayAHMatchSound(true) end -- preview the pick
      end,
      ddoptions = SoundOptionsShort },
    -- Border options removed: the icon border now always adopts the player's
    -- action-bar frame art (Blizzard default or skinner), like the rest of the UI.
    { type = "header", text = "Keybind" },
    { type = "check", label = "Show Keybind/Stacks", get = "GetAssistedHighlightShowKeybind", set = "SetAssistedHighlightShowKeybind",
      tooltip = "Show the suggested ability's keybind text AND its stack/charge count on the highlight.",
      -- Hidden in Target Portrait mode (no room on the round emblem) -- grey it out there.
      disable = function() return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate" end },
    -- Font/Size + Location all configure the KEYBIND text, which is hidden in Target Portrait mode --
    -- so grey them out there too (same condition as Show Keybind/Stacks above).
    { type = "dropdownslider", label = "Font", get = "GetAssistedHighlightFontName", set = "SetAssistedHighlightFontName", options = FontOptions,
      tooltip = "Font for the keybind text shown on the highlight.",
      sliderLabel = "Size", sliderGet = "GetAssistedHighlightFontSize", sliderSet = "SetAssistedHighlightFontSize", smin = 6, smax = 24, sstep = 1, tooltip2 = "Keybind text size.",
      disableGet = function() return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate" end },
    { type = "dropdown", label = "Location", get = "GetAssistedHighlightKeybindAnchor", set = "SetAssistedHighlightKeybindAnchor", options = KEYBIND_ANCHOR_OPTIONS,
      tooltip = "Which corner of the highlight the keybind text sits in.",
      disableGet = function() return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate" end },
    { type = "spacer", h = 12 },  -- top padding above the bottom Scale slider
    -- 0-200% of the 52px default (100% = normal). Soft-clamps to the size limits underneath.
    { type = "slider", label = "Assisted Highlight Scale", stacked = true,
      get = function() return math.floor((((addon.GetAssistedHighlightSize and addon:GetAssistedHighlightSize()) or 52) / 52) * 100 + 0.5) end,
      set = function(v) if addon.SetAssistedHighlightSize then addon:SetAssistedHighlightSize((tonumber(v) or 100) / 100 * 52) end end,
      min = 0, max = 200, step = 5, percent = true, width = 280, center = true,
      tooltip = "Size of the Assisted Highlight icon (100% = normal). Auto-sized to fit when anchored to the Target Portrait.",
      -- Target Portrait mode auto-sizes the highlight to the portrait, so Scale has no effect
      -- there -- grey it out.
      disableGet = function()
        return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
      end },
  }
end

-- Pressed Indicator edit-mode panel (its own element now -- opens from the "Click to Edit" box, see
-- ui/editmode.lua). Same controls that used to live on the General tab.
local function PressedIndicatorRows()
  return {
    { type = "header", text = "Pressed Indicator" },
    { type = "dropdownslider", label = "Shape", get = "GetPressedIndicatorShape", set = "SetPressedIndicatorShape", options = PRESSED_SHAPE_OPTIONS,
      tooltip = "Image flashed on screen when you press your macro key. 'None' turns it off.",
      sliderLabel = "Scale", sliderGet = "GetPressedIndicatorSize", sliderSet = "SetPressedIndicatorSize", smin = C.PRESSED_INDICATOR_MIN_SIZE or 4, smax = C.PRESSED_INDICATOR_MAX_SIZE or 24, sstep = 1, tooltip2 = "Size of the pressed indicator." },
    -- Colour source row: [] Class Color  [] Custom Color [swatch]. No Lock toggle -- positioning uses the
    -- element's "Click to Edit" box in Edit Mode, exactly like every other HUD element (locked otherwise).
    { type = "tricolor", label = "Class Color", label2 = "Custom",
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

-- The HUD elements (Action Tracker, Meters, Assisted Highlight, Pressed Indicator) live in Edit Mode -- click
-- each one's box to open its native options pop-up. Everything else (incl. Quality of Life / Saved Settings,
-- moved off their own tab) is on the single General tab now.
local TABS = {
  { key = "General", text = "General", rows = GeneralRows },
}

-- Edit Mode option pop-ups: Meters, Action Tracker and Assisted Highlight, all rendered one-per-row in
-- the native EditModeSystemSettingsDialog style. You position the frame AND tune its options in one place
-- while editing. Index order matters: the boxes in ui/editmode.lua reference these by index
-- (Meters=1, Action Tracker=2, Assisted Highlight=3). winWidth 444 gives equal ~42px L/R padding.

-- The Show GCD/DPS/HPS/SBAssist + Refresh + Opacity controls (formerly the embedded MetersOptionsPanel)
-- expressed as native descriptors. They drive MetersSavedVars + the apply-functions exposed by
-- meters/MetersOptions.lua (Meters_ApplyDisplayToggles / _ApplyOpacity / _ApplyRefreshRate).
local function MetersReadoutRows()
  -- "Show SBAssist %" was moved out to the standalone SLG-SBA Monitor addon (personal GSE testing tool).
  return {
    -- Readout visibility (GCD/DPS/HPS) + the centre Marker are managed in the Layout editor below:
    -- right-click a chip to remove it, "+" to add it back. (No separate "Show" dropdown needed.)
    { type = "meterslots" },
    { type = "slider", label = "Refresh Rate", float = true, min = 0.02, max = 0.15, step = 0.01,
      get = function() return (_G.Meters_GetRefreshRate and _G.Meters_GetRefreshRate()) or 0.10 end,
      set = function(v)
        if MetersSavedVars then MetersSavedVars.refreshRate = v end
        if _G.Meters_ApplyRefreshRate then _G.Meters_ApplyRefreshRate() end
      end,
      tooltip = "How often the readouts refresh (seconds)." },
    { type = "slider", label = "Opacity", percent = true, min = 25, max = 100, step = 1,
      get = function() return (MetersSavedVars and MetersSavedVars.opacity) or 100 end,
      set = function(v)
        if MetersSavedVars then MetersSavedVars.opacity = v end
        if _G.Meters_ApplyOpacity then _G.Meters_ApplyOpacity() end
      end,
      tooltip = "Opacity of the Meters readout text." },
  }
end

local EDITMODE_TABS = {
  { key = "Meters", text = "Meters", titleName = "Meters HUD", centerContent = true, winWidth = 490,
    rows = function()
      local r = {}
      for _, row in ipairs(CenterMarkerRows())   do r[#r + 1] = row end  -- Center Marker + Press Detection/colour
      for _, row in ipairs(MetersReadoutRows())  do r[#r + 1] = row end  -- Layout editor + Refresh + Opacity
      for _, row in ipairs(MetersBottomRows())   do r[#r + 1] = row end  -- Font + Outline + Meters Scale
      return r
    end },
  { key = "ActionTracker", text = "Action Tracker", rows = ActionTrackerRows, enableGet = "IsEnabled", centerContent = true, winWidth = 444 },
  { key = "AssistedHighlight", text = "Assisted Highlight", rows = AssistedHighlightRows, enableGet = "IsAssistedHighlightMirrorEnabled", cap = "assistedHighlight", centerContent = true, winWidth = 444 },
  { key = "PressedIndicator", text = "Pressed Indicator", titleName = "Pressed Indicator", rows = PressedIndicatorRows, centerContent = true, winWidth = 444 },
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
      if entry.tab and PanelTemplates_SelectTab then PanelTemplates_SelectTab(entry.tab) end
      entry.scroll:Show()
    else
      if entry.tab and PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(entry.tab) end
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

-- Build ONE page for a tab definition `t` into `host`, anchored below `topAnchor`, with `bottomReserve`
-- pixels left at the bottom. Handles both whole-frame "embed" tabs (the Meters readout panel + optional
-- top/bottom GSE rows) and plain scroll+rows tabs. Returns the page entry { scroll=, pane=, enableGet= }.
-- Reused by both the settings tab bar and the Edit Mode options panel so the controls are identical.
local function BuildPage(host, t, idx, topAnchor, bottomReserve)
  if t.embed then
    local page = CreateFrame("Frame", "GSETrackerCanvasEmbed" .. idx, host)
    page:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 4, -6)
    page:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, bottomReserve)

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

    local bottomOffset = (bPane and not t.embedHeight) and (bPaneH + 12) or 0
    local embedTopOffset = math.max(0, topOffset - 12)
    local mp = EmbedGlobalPanel(page, t.embed, embedTopOffset, bottomOffset, t.embedHeight)
    if bPane then
      bPane:ClearAllPoints()
      if t.embedHeight and mp then
        bPane:SetPoint("TOPLEFT", mp, "BOTTOMLEFT", 0, -8)
        bPane:SetPoint("TOPRIGHT", mp, "BOTTOMRIGHT", 0, -8)
      else
        bPane:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 8)
        bPane:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 8)
      end
      bPane:SetHeight(bPaneH or 10)
    end
    return { scroll = page, pane = page }
  else
    local scroll = CreateFrame("ScrollFrame", "GSETrackerCanvasScroll" .. idx, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, bottomReserve)  -- no scrollbar gutter (-30 -> -8)
    -- Drop the template's scrollbar entirely (user request). Keep mouse-wheel scrolling so any content
    -- that overflows the canvas is still reachable; Show is no-op'd so OnScrollRangeChanged can't restore it.
    local sb = scroll.ScrollBar or _G[(scroll:GetName() or "") .. "ScrollBar"]
    if sb then sb:Hide(); sb.Show = function() end; sb:SetAlpha(0); sb:EnableMouse(false) end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local range = self:GetVerticalScrollRange() or 0
      local newY = (self:GetVerticalScroll() or 0) - (delta * 40)
      if newY < 0 then newY = 0 elseif newY > range then newY = range end
      self:SetVerticalScroll(newY)
    end)

    local pane = CreateFrame("Frame", nil, scroll)
    pane:SetSize(560, 10)
    scroll:SetScrollChild(pane)

    Populate(pane, t.rows(), t.centerContent)
    if t.cap and not (ns.Caps and ns.Caps[t.cap]) then GreyOutPane(pane) end
    return { scroll = scroll, pane = pane, enableGet = t.enableGet and ResolveGet(t.enableGet) or nil }
  end
end

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

  -- With a single tab there's no point in a tab bar -- hang the page straight off the title and skip
  -- the tab button entirely (reclaims the tab-bar row). Multi-tab support kept for if tabs return.
  local singleTab = (#TABS == 1)
  local firstTab, prev
  for i, t in ipairs(TABS) do
    local tab, topAnchor
    if singleTab then
      topAnchor = titleFrame
    else
      tab = CreateTabButton("$parentTab" .. i, panel, t.text)
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
      topAnchor = firstTab
    end

    local entry = BuildPage(panel, t, i, topAnchor, FOOTER_RESERVE)
    entry.tab = tab
    panel.tabEntries[i] = entry
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

-- ── Edit Mode option windows (one pop-up per element) ────────────────────────
-- Each element ("Click To Edit" box) opens its OWN movable, native-styled pop-up window holding just
-- that element's options (rendered by the shared BuildPage). Built lazily, cached per index. Shown only
-- in Edit Mode; the Meters readout panel (MetersOptionsPanel) reparents into the Meters window.
local emWindows = {}  -- [idx into EDITMODE_TABS] = window frame

-- Persist each Edit Mode pop-up's dragged position in the account DB (GSETrackerDB.editPanels[key] =
-- {point, relPoint, x, y}). Unknown keys survive validation (MergeMissing only ADDS defaults), so this
-- is safe. Falls back to nil when the DB isn't ready yet.
local function EditPanelStore()
  if not _G.GSETrackerDB then return nil end
  _G.GSETrackerDB.editPanels = _G.GSETrackerDB.editPanels or {}
  return _G.GSETrackerDB.editPanels
end

local function BuildEditWindow(idx)
  local t = EDITMODE_TABS[idx]
  if not t then return nil end
  if emWindows[idx] then return emWindows[idx] end
  RebuildMarkerOptionLists()

  local w = CreateFrame("Frame", "GSETrackerEditWin" .. idx, UIParent, "BackdropTemplate")
  w:SetSize(t.winWidth or 580, (t.winHeight or 460) + 200)
  -- Restore the saved dragged position; else stagger so the windows don't fully overlap on first open.
  local store = EditPanelStore()
  local saved = store and store[t.key]
  w:ClearAllPoints()
  if saved and saved[1] then
    w:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
  else
    w:SetPoint("CENTER", UIParent, "CENTER", (idx - 1) * 50 - 25, (idx - 1) * -50 + 25)
  end
  -- DIALOG strata + high level so it floats ABOVE Blizzard's Edit Mode manager (Plumber's pattern).
  w:SetFrameStrata("DIALOG"); w:SetFrameLevel(200); w:SetToplevel(true)
  w:EnableMouse(true); w:SetClampedToScreen(true)
  -- Native Edit Mode dialog look: the same "Dialog" NineSlice the DamageMeter dialog uses.
  local okN = _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName
    and pcall(_G.NineSliceUtil.ApplyLayoutByName, w, "Dialog")
  if not okN and w.SetBackdrop then
    w:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
  end
  -- The "Dialog" NineSlice only draws the border; fill the interior to match the HUD Edit Mode manager.
  -- Dumped: the manager + settings dialogs are NOT fully opaque -- their center fill (a SetColorTexture
  -- inset 7px) is a semi-transparent dark, so the world shows faintly through. We match that with a
  -- single dark fill at ~0.82 alpha (no opaque underlay -- that made ours read fully solid). Inset 7 to
  -- match Blizzard's center-fill inset. (Color value eyeballed to the manager; tweak GSET_EDIT_BG_ALPHA.)
  local GSET_EDIT_BG_ALPHA = 0.82
  local bg = w:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetPoint("TOPLEFT",     w, "TOPLEFT",     7, -7)
  bg:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -7,  7)
  bg:SetColorTexture(0.05, 0.05, 0.06, GSET_EDIT_BG_ALPHA)

  -- Close button: the exact native Edit Mode dialog close (RedButton-Exit atlas, 24x24, flush TOPRIGHT),
  -- not UIPanelCloseButton -- matches EditModeSystemSettingsDialog from the dump.
  local close = CreateFrame("Button", nil, w)
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
  close:SetNormalAtlas("RedButton-Exit")
  close:SetPushedAtlas("RedButton-exit-pressed")
  close:SetHighlightAtlas("RedButton-Highlight")
  local closeHL = close:GetHighlightTexture(); if closeHL then closeHL:SetBlendMode("ADD") end
  close:SetScript("OnClick", function() w:Hide() end)

  -- Top-left corner badge: the round GSE icon in the native minimap-style gold ring, sized/positioned to
  -- match the stock "i" info icon on Blizzard's HUD Edit Mode window. TWO knobs to tweak: BADGE_RING (the
  -- gold-ring diameter) and the badge TOPLEFT offset. Proven LibDBIcon proportions (the icon is inset in
  -- the ring texture) scaled by k, so the icon stays centred in the ring at any size. Decorative (branding).
  -- Icon centred ON the metal DIAMOND stud at the panel's top-left corner (the "Dialog" NineSlice corner
  -- piece), which sits inset from the absolute corner -- BADGE_POS is that inset (x right, y down). The
  -- minimap ring texture isn't centred in its own bounds, so the ring is anchored to the icon with the
  -- proven LibDBIcon offset (-7k, +6k) which makes the visible ring sit centred on the icon.
  local BADGE_RING = 64
  local BADGE_X, BADGE_Y = 12, -12   -- diamond-stud centre, from the panel's TOPLEFT
  local k = BADGE_RING / 54
  local badge = CreateFrame("Frame", nil, w)
  badge:SetSize(BADGE_RING, BADGE_RING)
  badge:SetPoint("CENTER", w, "TOPLEFT", BADGE_X, BADGE_Y)
  local badgeIcon = badge:CreateTexture(nil, "ARTWORK")
  badgeIcon:SetSize(20 * k, 20 * k)
  badgeIcon:SetPoint("CENTER", w, "TOPLEFT", BADGE_X, BADGE_Y)
  badgeIcon:SetTexture("Interface\\AddOns\\GSE_Tracker\\media\\GSE_Tracker_Round.png")
  local badgeRing = badge:CreateTexture(nil, "OVERLAY")
  badgeRing:SetSize(BADGE_RING, BADGE_RING)
  badgeRing:SetPoint("TOPLEFT", badgeIcon, "TOPLEFT", -7 * k, 6 * k)
  badgeRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  w.cornerBadge = badge

  -- Centred title = just the element name (native: GameFontHighlightLarge, TOP offset -15). The "GSE:
  -- Tracker" brand prefix was dropped per request; the corner diamond badge carries the branding now.
  local title = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  title:SetPoint("TOP", w, "TOP", 0, -15)
  title:SetText(t.titleName or t.text or "")
  w.title = title

  -- Drag the window by its title strip.
  w:SetMovable(true)
  local grab = CreateFrame("Frame", nil, w)
  grab:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
  grab:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
  grab:SetHeight(40); grab:EnableMouse(true); grab:RegisterForDrag("LeftButton")
  grab:SetScript("OnDragStart", function() w:StartMoving() end)
  grab:SetScript("OnDragStop",  function()
    w:StopMovingOrSizing()
    local s = EditPanelStore()
    if s then
      local p, _, rp, x, y = w:GetPoint(1)
      if p then s[t.key] = { p, rp, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
    end
  end)

  -- Invisible header anchor under the title; the element's page fills from here to the bottom.
  local header = CreateFrame("Frame", nil, w)
  header:SetPoint("TOPLEFT", w, "TOPLEFT", 8, -40)
  header:SetSize(1, 1)
  -- Both Edit Mode pop-ups (Meters + Action Tracker) render natively now. The embed path is kept only
  -- as a fallback for any future tab that still embeds a prebuilt panel.
  if t.embed then
    BuildPage(w, t, 100 + idx, header, 14)
  else
    -- Native one-per-row layout (matches the HUD Edit Mode dialogs). No scroll bar -- the window sizes
    -- to its content like Blizzard's native dialogs.
    local pane = CreateFrame("Frame", nil, w)
    pane:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -6)
    pane:SetWidth((w:GetWidth() or 580) - 44)
    PopulateNative(pane, t.rows())
    if t.cap and not (ns.Caps and ns.Caps[t.cap]) then GreyOutPane(pane) end
    -- Fit the window height to the content: title strip (~46) + content + bottom padding.
    -- (The "Revert Changes" / "Reset To Default Position" buttons were REMOVED -- they could wipe data.)
    local contentH = (pane.GetHeight and pane:GetHeight()) or 200
    w:SetHeight(46 + contentH + 30)
  end

  -- Meters used to embed MetersOptionsPanel, whose OnShow drove the readout preview (12345/6789 etc.).
  -- That panel is no longer embedded, so refresh the meter display whenever the Meters window opens.
  if t.key == "Meters" then
    w:HookScript("OnShow", function()
      if _G.Meters_ApplyDisplayToggles then pcall(_G.Meters_ApplyDisplayToggles) end
    end)
  end

  w:Hide()
  emWindows[idx] = w
  return w
end

-- Open one element's pop-up window (called when its "Click To Edit" box is clicked). idx -> EDITMODE_TABS.
function _G.GSETracker_EditModeShowTab(idx)
  idx = tonumber(idx); if not idx then return end
  local w = BuildEditWindow(idx)
  -- Native Edit Mode behaviour: only ONE element's panel is open at a time. Hide every other element
  -- window first so switching boxes swaps panels instead of stacking them.
  for i, ow in pairs(emWindows) do
    if i ~= idx and ow.IsShown and ow:IsShown() then ow:Hide() end
  end
  if w then w:Show(); w:Raise() end
end

-- Edit Mode exit (from ui/editmode.lua): hide every element window. (Windows open on box click, not here.)
function _G.GSETracker_SetEditModeOptions(show)
  if show then return end
  for _, w in pairs(emWindows) do w:Hide() end
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

-- Login/welcome window feature removed (popup retired); see git history if it needs to return.
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
