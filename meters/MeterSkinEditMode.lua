-- meters/MeterSkinEditMode.lua
-- A small companion window docked beside Blizzard's DEFAULT Edit Mode settings panel (left fully
-- intact) that adds our skin pickers -- Font + Bar texture -- whenever the DamageMeter system is the
-- one being edited. Selections drive MetersSavedVars.skinFont / .skinBarTexture and re-skin live via
-- GSETracker_MeterSkin_Refresh (see meters/MeterSkin.lua). Retail-only.
--
-- (We deliberately do NOT replace/hide/resize Blizzard's panel -- attempts to take it over fought its
-- layout manager and auto-sizing. A separate attached window is robust.)

local addonName, ns = ...
MetersSavedVars = MetersSavedVars or {}

local CreateFrame    = _G.CreateFrame
local hooksecurefunc = _G.hooksecurefunc
local ipairs, pcall  = ipairs, pcall

local function IsMainline()
  return (not _G.WOW_PROJECT_ID) or (_G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1))
end
local function Refresh()
  if _G.GSETracker_MeterSkin_Refresh then _G.GSETracker_MeterSkin_Refresh() end
  -- The custom breakdown (GSETrackerDetails) reads the same skinFont/skinBarTexture, so re-render it
  -- too so a Font/Bar pick shows there immediately (and its border re-adopts any active skinner).
  if _G.GSETrackerDetails_ApplyBorder then _G.GSETrackerDetails_ApplyBorder() end
  if _G.GSETrackerDetails_Refresh then _G.GSETrackerDetails_Refresh() end
end
local function ApplyPicks() Refresh() end  -- the window's OnUpdate loop (below) keeps it asserted

-- ── LibSharedMedia font/bar lists (optional; built-in fallback) ──────────────────────────────────
local function LSM() return (_G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)) or nil end
local BUILTIN_FONTS = {
  { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" }, { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
  { name = "Skurri", path = "Fonts\\SKURRI.TTF" }, { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
}
local BUILTIN_BARS = {
  { name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { name = "Smooth", path = "Interface\\Buttons\\WHITE8x8" },
  { name = "Flat", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
local function FontList()
  local lsm = LSM()
  if lsm then local out = {} for _, n in ipairs(lsm:List("font")) do out[#out + 1] = { name = n, path = lsm:Fetch("font", n) } end if #out > 0 then return out end end
  return BUILTIN_FONTS
end
local function BarList()
  local lsm = LSM()
  if lsm then local out = {} for _, n in ipairs(lsm:List("statusbar")) do out[#out + 1] = { name = n, path = lsm:Fetch("statusbar", n) } end if #out > 0 then return out end end
  return BUILTIN_BARS
end

-- ── The companion window ──────────────────────────────────────────────────────────────────────────
local win, fontDD, barDD

local function MakeDropdown(parent, w)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if not ok or not dd then return nil end
  dd:SetWidth(w or 180)
  return dd
end

local function CurrentFontName()
  local p = MetersSavedVars.skinFont
  if not p or p == "" then return "Default" end
  for _, it in ipairs(FontList()) do if it.path == p then return it.name end end
  return "Custom"
end

-- Native-looking font picker: a real WowStyle1 dropdown for the LOOK (matches the Bar dropdown), but
-- its click opens OUR scroll list instead of a Compositor menu -- so we keep the in-font previews
-- (SetFont is allowed in our own frame, banned in Blizzard menus).
local function BuildFontPicker(parent)
  local btn = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  btn:SetWidth(150)
  btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -38)

  local function updateBtn()
    if btn.SetDefaultText then btn:SetDefaultText(CurrentFontName()) end
  end

  -- the drop list
  local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
  list:SetSize(178, 280)
  list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetFrameLevel((parent:GetFrameLevel() or 1) + 50)
  if list.SetBackdrop then
    list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    list:SetBackdropColor(0.05, 0.05, 0.06, 0.97); list:SetBackdropBorderColor(0.50, 0.45, 0.35, 1)
  end
  list:Hide()

  local sf = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -28, 8)
  local content = CreateFrame("Frame", nil, sf); content:SetSize(140, 10); sf:SetScrollChild(content)

  local rowH = 20
  local fonts = FontList()
  for i, it in ipairs(fonts) do
    local row = CreateFrame("Button", nil, content)
    row:SetSize(140, rowH); row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local txt = row:CreateFontString(nil, "OVERLAY")
    txt:SetPoint("LEFT", 4, 0); txt:SetPoint("RIGHT", -4, 0); txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
    if not pcall(txt.SetFont, txt, it.path, 14, "") then txt:SetFontObject("GameFontHighlight") end
    txt:SetText(it.name)
    row:SetScript("OnClick", function()
      MetersSavedVars.skinFont = it.path; ApplyPicks(); updateBtn(); list:Hide()
    end)
  end
  content:SetHeight(#fonts * rowH + 4)

  local function toggle()
    if list:IsShown() then list:Hide() else updateBtn(); list:Show() end
  end
  -- Intercept the dropdown's open so OUR preview list shows instead of a Compositor menu (which can't
  -- render font faces). The native open is on OnMouseDown -- suppress it there; toggle once on the
  -- OnClick release (overriding both with toggle would fire twice -> show-then-hide).
  btn:SetScript("OnMouseDown", function() end)
  btn:SetScript("OnClick", function() toggle() end)

  updateBtn()
  parent.fontBtn = btn
  btn.Refresh = updateBtn
  return btn
end

local function BuildWindow(dialog)
  if win then return win end
  win = CreateFrame("Frame", "GSETracker_MeterSkinWindow", dialog, "BackdropTemplate")
  win:SetSize(250, 196)
  win:SetFrameStrata(dialog:GetFrameStrata())
  win:SetFrameLevel((dialog:GetFrameLevel() or 1) + 10)
  -- Match the Edit Mode panel EXACTLY: apply the same NineSlice it uses (the "Dialog" layout =
  -- DiamondMetal border). A dark fill sits behind in case the layout's center is translucent. Falls
  -- back to a tooltip backdrop only if NineSliceUtil is unavailable.
  local bg = win:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetPoint("TOPLEFT", 8, -8); bg:SetPoint("BOTTOMRIGHT", -8, 8)
  bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)
  local okN = _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName
    and pcall(_G.NineSliceUtil.ApplyLayoutByName, win, "Dialog")
  if not okN and win.SetBackdrop then
    win:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    win:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    win:SetBackdropBorderColor(0.60, 0.55, 0.42, 1)
  end

  -- Continuously re-skin while this window is open (it's shown only when the DamageMeter is being
  -- edited). The in-combat skinner loop sits idle in Edit Mode -- DamageMeter:IsShown() reads false --
  -- so without this, the meter recycles its pooled row fontstrings and our font/bar "stops" sticking
  -- after a few changes. OnUpdate fires only while the frame is visible, so there's no idle cost.
  local accum = 0
  win:SetScript("OnUpdate", function(_, e)
    accum = accum + (e or 0)
    if accum < 0.1 then return end
    accum = 0
    Refresh()
  end)

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", win, "TOP", 12, -14)  -- shifted right to leave room for the icon
  local brand = (ns.Utils and ns.Utils.Constants and ns.Utils.Constants.ADDON_DISPLAY_NAME)
    or (ns.Constants and ns.Constants.ADDON_DISPLAY_NAME)
    or "|cFFFFFFFFGS|r|cFF00FFFFE:|r|cFFFFFF00 Tracker|r"
  title:SetText(brand .. " Skinner")  -- GS white / E: cyan / Tracker yellow; "Skinner" = base white
  title:SetTextColor(1, 1, 1)
  local icon = win:CreateTexture(nil, "OVERLAY")
  icon:SetSize(20, 20)
  icon:SetTexture("Interface\\AddOns\\GSE_Tracker\\media\\GSE_Tracker.png")
  icon:SetPoint("RIGHT", title, "LEFT", -4, 0)
  win.title = title

  local fl = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fl:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -42)
  fl:SetText("Font")
  win.fontLabel = fl
  BuildFontPicker(win)

  local bl = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  bl:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -74)
  bl:SetText("Bar")
  win.barLabel = bl
  barDD = MakeDropdown(win, 150)
  if barDD then
    barDD:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -70)
    if barDD.SetDefaultText then barDD:SetDefaultText("Default") end
    barDD:SetupMenu(function(_, root)
      for _, it in ipairs(BarList()) do
        local r = root:CreateRadio(it.name, function() return MetersSavedVars.skinBarTexture == it.path end,
          function() MetersSavedVars.skinBarTexture = it.path; ApplyPicks(); if barDD.GenerateMenu then barDD:GenerateMenu() end end)
        -- live texture swatch behind each name (Compositor disallows CreateTexture; use AttachTexture)
        if r and r.AddInitializer then
          r:AddInitializer(function(button)
            if not button then return end
            -- shared menu pool: a frame reused from a font entry may have its label hidden -> restore.
            if button.fontString then pcall(button.fontString.SetAlpha, button.fontString, 1) end
            if not button.AttachTexture then return end
            local ok, sw = pcall(button.AttachTexture, button)
            if not ok or not sw then return end
            sw:SetTexture(it.path); sw:SetVertexColor(0.30, 0.42, 0.70, 0.85)
            if sw.SetDrawLayer then sw:SetDrawLayer("BACKGROUND") end
            sw:ClearAllPoints(); sw:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1); sw:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 1)
          end)
        end
      end
    end)
  end

  -- ── Meter source: which meter shows the breakdown (radio-style; only one active) ──────────────────
  -- Routed via GSETracker_Get/SetMeterMode (meters/Details.lua). "Use Details! Damage Meter" greys out
  -- when the Details! addon isn't loaded.
  -- Anchored RELATIVE to the Bar label so it follows the dialog-matched layout (OnAttach repositions
  -- the Font/Bar rows); the window height is extended in OnAttach to fit this block.
  local sl = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sl:SetPoint("TOPLEFT", win.barLabel, "BOTTOMLEFT", 0, -24)
  sl:SetText("Details Window")
  win.sourceLabel = sl

  local MODE_ROWS = {
    { mode = "details",  text = "Use Details! Damage Meter" },
    { mode = "skinner",  text = "Use GSE: Tracker Skinner" },
    { mode = "blizzard", text = "Use Blizzard Meter Details" },
  }
  win.modeChecks = {}
  local prevAnchor = sl
  for i, row in ipairs(MODE_ROWS) do
    local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    cb:SetSize(28, 28)  -- match the Edit Mode setting checkboxes (larger box + checkmark)
    cb:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", (i == 1) and -4 or 0, (i == 1) and -16 or -2)
    prevAnchor = cb
    cb.mode = row.mode
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(row.text)
    cb.label = lbl
    cb:SetScript("OnClick", function(self)
      if self.mode == "details" and not _G.Details then self:SetChecked(false); return end
      if _G.GSETracker_SetMeterMode then _G.GSETracker_SetMeterMode(self.mode) end
      if win.RefreshModes then win.RefreshModes() end
      ApplyPicks()
    end)
    win.modeChecks[i] = cb
  end

  function win.RefreshModes()
    local mode = (_G.GSETracker_GetMeterMode and _G.GSETracker_GetMeterMode()) or "skinner"
    local detailsLoaded = _G.Details ~= nil
    for _, cb in ipairs(win.modeChecks) do
      cb:SetChecked(cb.mode == mode)
      if cb.mode == "details" and not detailsLoaded then
        cb:Disable(); if cb.label.SetTextColor then cb.label:SetTextColor(0.5, 0.5, 0.5) end
      else
        cb:Enable(); if cb.label.SetTextColor then cb.label:SetTextColor(1, 1, 1) end
      end
    end
  end
  win.RefreshModes()

  return win
end

-- ── Hook: show the window beside the dialog when the DamageMeter is selected ─────────────────────
local function IsDamageMeterSystem(systemFrame)
  local f, n = systemFrame, 0
  while f and n < 5 do if f == _G.DamageMeter then return true end f = f.GetParent and f:GetParent() or nil n = n + 1 end
  return false
end

-- Read the font the Edit Mode dialog uses for its setting labels (e.g. "Style") so our Font/Bar
-- labels match it exactly. Find the Style control (carries .setting) and grab its first FontString.
local STYLE_SETTING = _G.Enum and _G.Enum.EditModeDamageMeterSetting and _G.Enum.EditModeDamageMeterSetting.Style
local NUMBERS_SETTING = _G.Enum and _G.Enum.EditModeDamageMeterSetting and _G.Enum.EditModeDamageMeterSetting.Numbers
local function FindSettingControl(frame, setting, depth)
  if not frame or depth > 8 or not frame.GetChildren then return nil end
  for _, c in ipairs({ frame:GetChildren() }) do
    if c.setting == setting then return c end
    local f = FindSettingControl(c, setting, depth + 1)
    if f then return f end
  end
end
local function StyleLabelFont(dialog)
  local ctrl = STYLE_SETTING and FindSettingControl(dialog, STYLE_SETTING, 0)
  if not ctrl then return nil end
  local function scan(f, d)
    if not f or d > 4 then return nil end
    if f.GetRegions then
      for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetFont and (r:GetText() or "") ~= "" then
          local p, s, fl = r:GetFont()
          if p and s then return p, s, fl end
        end
      end
    end
    if f.GetChildren then for _, c in ipairs({ f:GetChildren() }) do local p, s, fl = scan(c, d + 1) if p then return p, s, fl end end end
  end
  return scan(ctrl, 0)
end

local function OnAttach(dialog, systemFrame)
  if not IsDamageMeterSystem(systemFrame) then
    if win then win:Hide() end
    return
  end
  local w = BuildWindow(dialog)
  w:ClearAllPoints()
  -- Dock to the right edge of Blizzard's panel, butted up against it (its layout never touches us out here).
  w:SetPoint("TOPLEFT", dialog, "TOPRIGHT", -16, 0)
  w:Show()
  if w.RefreshModes then w.RefreshModes() end  -- reflect current meter source + Details! availability
  -- Match our Font/Bar labels to the dialog's setting-label font (e.g. "Style") exactly.
  local p, s, fl = StyleLabelFont(dialog)
  if p and s then
    if w.fontLabel then pcall(w.fontLabel.SetFont, w.fontLabel, p, s, fl or "") end
    if w.barLabel then pcall(w.barLabel.SetFont, w.barLabel, p, s, fl or "") end
    if w.sourceLabel then pcall(w.sourceLabel.SetFont, w.sourceLabel, p, s, fl or "") end
    -- Match the Edit Mode setting-row labels (e.g. "Show Spec Icon") on our checkboxes too.
    for _, cb in ipairs(w.modeChecks or {}) do
      if cb.label then pcall(cb.label.SetFont, cb.label, p, s, fl or "") end
    end
  end

  -- Match the dialog's padding: read the first-row offset, row pitch and left margin from the Style
  -- and Numbers controls, then lay our two rows out to the same metrics (labels vertically centred on
  -- their dropdowns, like the dialog).
  local dt, dl, dr = dialog:GetTop(), dialog:GetLeft(), dialog:GetRight()
  local sc = STYLE_SETTING and FindSettingControl(dialog, STYLE_SETTING, 0)
  local nc = NUMBERS_SETTING and FindSettingControl(dialog, NUMBERS_SETTING, 0)
  if dt and dl and dr and sc and nc and sc:GetTop() and nc:GetTop() and sc:GetLeft() and sc:GetRight() then
    local oy = (dt - sc:GetTop()) + 4    -- window top -> first row (+4 mirrors the title's extra top
                                          -- padding so the title->row gap still matches the dialog)
    local pitch = sc:GetTop() - nc:GetTop()  -- row spacing
    local lx = sc:GetLeft() - dl          -- left margin (border -> label)
    local rm = dr - sc:GetRight()         -- right margin (dropdown -> border) -- reuse for the bottom too
    if oy > 0 and pitch > 0 then
      local DH, DROP_W = 22, 150
      w:SetWidth(lx + 56 + DROP_W + rm)   -- left margin + label area + dropdown + matched right margin
      -- Match the dialog's title position (top padding) too.
      local dTitle = dialog.Title or dialog.TitleText or (dialog.Header and dialog.Header.Text)
      if w.title and dTitle and dTitle.GetTop and dTitle:GetTop() then
        w.title:ClearAllPoints()
        w.title:SetPoint("TOP", w, "TOP", 12, -(dt - dTitle:GetTop()) - 4)
      end
      if w.fontBtn then w.fontBtn:ClearAllPoints(); w.fontBtn:SetPoint("TOPRIGHT", w, "TOPRIGHT", -rm, -oy) end
      if w.fontLabel then w.fontLabel:ClearAllPoints(); w.fontLabel:SetPoint("LEFT", w, "TOPLEFT", lx, -(oy + DH / 2)) end
      if barDD then barDD:ClearAllPoints(); barDD:SetPoint("TOPRIGHT", w, "TOPRIGHT", -rm, -(oy + pitch)) end
      if w.barLabel then w.barLabel:ClearAllPoints(); w.barLabel:SetPoint("LEFT", w, "TOPLEFT", lx, -(oy + pitch + DH / 2)) end
      -- Bar row bottom + the Meter source block (label gap + label + 3 checkboxes) + bottom margin.
      local SOURCE_BLOCK = 24 + 16 + (3 * 30)
      w:SetHeight(oy + pitch + DH + SOURCE_BLOCK + rm)
    end
  end
  if win and win.fontBtn and win.fontBtn.Refresh then win.fontBtn.Refresh() end
  if barDD and barDD.GenerateMenu then barDD:GenerateMenu() end
end

local hooked = false
local function Setup()
  if hooked or not IsMainline() then return end
  local d = _G.EditModeSystemSettingsDialog
  if type(d) ~= "table" or type(d.AttachToSystemFrame) ~= "function" then return end
  hooked = true
  hooksecurefunc(d, "AttachToSystemFrame", OnAttach)
  if d.HookScript then d:HookScript("OnHide", function() if win then win:Hide() end end) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function() Setup() end)

function _G.GSETracker_MeterEditMode_Debug()
  local p = (_G.DEFAULT_CHAT_FRAME and function(m) _G.DEFAULT_CHAT_FRAME:AddMessage(m) end) or print
  p(("Meter Skin window: built=%s  fontDD=%s  barDD=%s")
    :format(tostring(win ~= nil), tostring(fontDD ~= nil), tostring(barDD ~= nil)))
end
