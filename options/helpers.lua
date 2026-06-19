local _, ns = ...
local addon = ns
local API = (ns.Utils and ns.Utils.API) or {}
local UIParent = (API.UIParent and API.UIParent()) or UIParent
local Options = ns.Options
local uiShared = addon._ui or {}
local optionsModule = Options
local WHITE8X8 = (ns.Utils and ns.Utils.Constants and ns.Utils.Constants.TEXTURE_WHITE8X8) or "Interface/Buttons/WHITE8x8"

optionsModule.SafeAPI = optionsModule.SafeAPI or {}

optionsModule.MIN_W = 840
optionsModule.MIN_H = 600
optionsModule.DEFAULT_W = 940
optionsModule.DEFAULT_H = 720
optionsModule.PAD = 16
optionsModule.GAP = 12
optionsModule.LABEL_W = 116
optionsModule.CONTROL_TRACK_W = 156
optionsModule.CONTROL_TOTAL_W = 252
optionsModule.CONTROL_X = optionsModule.LABEL_W + 14
optionsModule.ROW_H = 28
optionsModule.SLIDER_ROW_H = 52
optionsModule.SLIDER_EDIT_W = 46
optionsModule.TOGGLE_W = optionsModule.SLIDER_EDIT_W
optionsModule.SLIDER_BOX_GAP = 4
optionsModule.ROW_GAP = 6
optionsModule.SECTION_START_Y = -48
optionsModule.SECTION_INSET_X = 14
optionsModule.SECTION_BOTTOM_PAD = 16
optionsModule.SIDEBAR_W = 184
optionsModule.MAIN_PAD = 16
optionsModule.HEADER_H = 68
optionsModule.FOOTER_H = 44
optionsModule.TAB_HEIGHT = 30
optionsModule.TAB_GAP = 4

local BG_DARK = { 0.025, 0.03, 0.035 }
local BG_MEDIUM = { 0.035, 0.04, 0.045 }
local BG_LIGHT = { 0.05, 0.055, 0.06 }
local BG_INPUT = { 0.06, 0.065, 0.07 }
local BG_HOVER = { 0.08, 0.085, 0.09 }
local BORDER_DARK = { 0.06, 0.06, 0.06 }
local BORDER_DEFAULT = { 0.12, 0.12, 0.12 }
local BORDER_LIGHT = { 0.18, 0.18, 0.18 }
local BORDER_HOVER = { 0.25, 0.25, 0.25 }
local BORDER_INPUT = { 0.15, 0.15, 0.15 }
local TEXT_PRIMARY = { 1, 1, 1 }
local TEXT_SECONDARY = { 0.7, 0.7, 0.7 }
local TEXT_MUTED = { 0.5, 0.5, 0.5 }
local TEXT_DISABLED = { 0.35, 0.35, 0.35 }
local CONTROL_TRACK = { 0.15, 0.15, 0.15 }
local CONTROL_TRACK_OFF = { 0.2, 0.2, 0.2 }
local SCROLL_THUMB = { 0.45, 0.45, 0.45 }
local SCROLL_THUMB_HOVER = { 0.55, 0.55, 0.55 }
-- Modern accent fallback = GSE's MODERN_CUSTOM_COLOR_DEFAULT {0, 0.44, 0.87},
-- copied from GSE_Utils/Appearance.lua (used when the player's class colour is
-- unavailable). Self-contained -- no runtime GSE reference.
local FALLBACK_ACCENT = { 0.00, 0.44, 0.87 }

-- Live palette tables. ApplyActiveSkinPalette() copies the selected skin's
-- colours into these IN PLACE, so every widget that already references them by
-- index (BG_DARK[1] etc.) picks up the active skin with no call-site changes.
-- The same table objects are exposed on optionsModule.Palette so tabs.lua and
-- options.lua can paint matching surfaces from a single source of truth.
local LIVE_PALETTE = {
  BG_DARK = BG_DARK, BG_MEDIUM = BG_MEDIUM, BG_LIGHT = BG_LIGHT,
  BG_INPUT = BG_INPUT, BG_HOVER = BG_HOVER,
  BORDER_DARK = BORDER_DARK, BORDER_DEFAULT = BORDER_DEFAULT,
  BORDER_LIGHT = BORDER_LIGHT, BORDER_HOVER = BORDER_HOVER, BORDER_INPUT = BORDER_INPUT,
  TEXT_PRIMARY = TEXT_PRIMARY, TEXT_SECONDARY = TEXT_SECONDARY,
  TEXT_MUTED = TEXT_MUTED, TEXT_DISABLED = TEXT_DISABLED,
  CONTROL_TRACK = CONTROL_TRACK, CONTROL_TRACK_OFF = CONTROL_TRACK_OFF,
  SCROLL_THUMB = SCROLL_THUMB, SCROLL_THUMB_HOVER = SCROLL_THUMB_HOVER,
  FALLBACK_ACCENT = FALLBACK_ACCENT,
}
optionsModule.Palette = LIVE_PALETTE

-- Copy the active skin's colours into the live palette. Safe to call before
-- the settings window is built; widget hover/state handlers that read the
-- palette tables at event time also pick up the latest values.
function optionsModule.ApplyActiveSkinPalette()
  local skin = optionsModule.GetActiveSkin and optionsModule.GetActiveSkin()
  if type(skin) ~= "table" then return end
  for key, live in pairs(LIVE_PALETTE) do
    local c = skin[key]
    if type(c) == "table" then
      live[1], live[2], live[3] = c[1], c[2], c[3]
    end
  end
  optionsModule._activeSkin = skin
end

function optionsModule.EnsureDB()
  if uiShared and uiShared.EnsureDB then
    uiShared.EnsureDB()
  end
end

function optionsModule.Clamp(v, lo, hi)
  if uiShared and uiShared.Clamp then
    return uiShared.Clamp(v, lo, hi)
  end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function optionsModule.GetClassColor()
  -- Native skin uses a fixed (gold) accent instead of class colour.
  local skin = optionsModule._activeSkin or (optionsModule.GetActiveSkin and optionsModule.GetActiveSkin())
  if type(skin) == "table" and skin.useClassAccent == false then
    local a = skin.accent or FALLBACK_ACCENT
    return a[1], a[2], a[3]
  end

  -- Modern skin: class colour. (Standalone -- must NOT read the GSE addon; the
  -- only permitted GSE link is gse_bridge.lua.)
  local classTag
  if UnitClass then
    _, classTag = UnitClass("player")
  end
  -- Classic quirk: RAID_CLASS_COLORS.SHAMAN is Paladin pink. Force the real blue when there's
  -- no CUSTOM_CLASS_COLORS override (harmless on Retail).
  if classTag == "SHAMAN" and not CUSTOM_CLASS_COLORS then
    return 0.0, 0.44, 0.87
  end
  local color = classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]
  if color then
    return color.r, color.g, color.b
  end
  return FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3]
end

function optionsModule.GetElementXY(name)
  local cfg, defaults = addon:GetElementLayout(name)
  defaults = defaults or { x = 0, y = 0, enabled = true }
  return (cfg and cfg.x) or defaults.x or 0, (cfg and cfg.y) or defaults.y or 0, (cfg and cfg.enabled)
end

function optionsModule.RefreshLiveActionTrackerForOptions()
  return
end

function optionsModule.ResetSettingsWindowGeometry(frame)
  if not frame then return end
  frame:StopMovingOrSizing()
  local minW, minH = optionsModule.MIN_W, optionsModule.MIN_H
  if optionsModule.ComputeMinimumWindowSize and frame._gsetrackerSectionsByTab then
    minW, minH = optionsModule.ComputeMinimumWindowSize(frame._gsetrackerSectionsByTab, frame.GetSelectedTopTab and frame:GetSelectedTopTab() or nil)
  end
  local maxW = ((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or optionsModule.DEFAULT_W) - 40
  local maxH = ((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or optionsModule.DEFAULT_H) - 40
  local w = math.max(tonumber(frame:GetWidth()) or optionsModule.DEFAULT_W, minW)
  local h = math.max(tonumber(frame:GetHeight()) or optionsModule.DEFAULT_H, minH)
  if maxW > 0 then
    w = math.min(w, maxW)
  end
  if maxH > 0 then
    h = math.min(h, maxH)
  end
  frame:SetSize(w, h)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function optionsModule.StyleWindowBorder(frame)
  if not (frame and frame.SetBackdropBorderColor) then return end
  frame:SetBackdropBorderColor(BORDER_LIGHT[1], BORDER_LIGHT[2], BORDER_LIGHT[3], 1)
end

function optionsModule.StyleWindowBackground(frame, bgAlpha)
  if not (frame and frame.SetBackdropColor) then return end
  frame:SetBackdropColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], bgAlpha or 0.98)
end

function optionsModule.CreateBackdrop(parent, bgAlpha, borderAlpha)
  local f = API.CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({
    bgFile = WHITE8X8,
    edgeFile = WHITE8X8,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  f:SetBackdropColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], bgAlpha or 0.98)
  f:SetBackdropBorderColor(BORDER_DEFAULT[1], BORDER_DEFAULT[2], BORDER_DEFAULT[3], borderAlpha or 1)
  return f
end

function optionsModule.CreateCheck(parent, label)
  local cb = API.CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  -- Native skin keeps Blizzard's square check (StyleCheckbox bails); the Modern
  -- skin paints a wider slide-toggle, so size accordingly.
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then
    cb:SetSize(26, 26)
  else
    cb:SetSize(optionsModule.TOGGLE_W or 46, 20)
  end
  cb.rowHeight = optionsModule.ROW_H
  cb.alignLabelOffsetY = 0
  cb:SetHitRectInsets(-4, -4, -4, -4)
  if cb.Text then
    cb.Text:SetText(label or "")
    cb.Text:ClearAllPoints()
    cb.Text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
  end
  if optionsModule.StyleCheckbox then optionsModule.StyleCheckbox(cb) end
  return cb
end

function optionsModule.CreateLabel(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  fs:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 0.9)
  return fs
end

function optionsModule.ApplyMidnightBackdrop(frame, edgeSize, bgAlpha)
  if not frame then return end
  frame:SetBackdrop({
    bgFile = WHITE8X8,
    edgeFile = WHITE8X8,
    edgeSize = edgeSize or 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  frame:SetBackdropColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], bgAlpha or 0.98)
  frame:SetBackdropBorderColor(BORDER_DEFAULT[1], BORDER_DEFAULT[2], BORDER_DEFAULT[3], 1)
end

local function HideTexture(tex)
  if not tex then return end
  if tex.SetTexture then tex:SetTexture(nil) end
  if tex.SetAtlas then tex:SetAtlas(nil, true) end
  tex:SetAlpha(0)
  tex:Hide()
end

local function HideNamedRegion(frame, key)
  if not frame then return end
  local region = frame[key]
  if region then HideTexture(region) end
end

local function HideTextureRegions(frame)
  if not frame or not frame.GetRegions then return end
  for _, region in ipairs({ frame:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
      HideTexture(region)
    end
  end
end

local function HideTextureRegionsRecursive(frame)
  if not frame then return end
  HideTextureRegions(frame)
  if frame.GetNormalTexture then HideTexture(frame:GetNormalTexture()) end
  if frame.GetPushedTexture then HideTexture(frame:GetPushedTexture()) end
  if frame.GetHighlightTexture then HideTexture(frame:GetHighlightTexture()) end
  if frame.GetDisabledTexture then HideTexture(frame:GetDisabledTexture()) end
  if frame.GetCheckedTexture then HideTexture(frame:GetCheckedTexture()) end
  if frame.GetDisabledCheckedTexture then HideTexture(frame:GetDisabledCheckedTexture()) end
end

local function StripUIPanelButtonRegions(button)
  if not button then return end
  HideNamedRegion(button, "Left")
  HideNamedRegion(button, "Middle")
  HideNamedRegion(button, "Right")
  HideNamedRegion(button, "LeftDisabled")
  HideNamedRegion(button, "MiddleDisabled")
  HideNamedRegion(button, "RightDisabled")
end

local function StripUICheckButtonRegions(button)
  if not button then return end
  HideNamedRegion(button, "Left")
  HideNamedRegion(button, "Middle")
  HideNamedRegion(button, "Right")
end

local function EnsureButtonLabel(button)
  local text = button.GetFontString and button:GetFontString()
  if not text then
    text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button:SetFontString(text)
  end
  text:ClearAllPoints()
  text:SetPoint("CENTER", button, "CENTER", 0, 0)
  text:SetJustifyH("CENTER")
  text:SetJustifyV("MIDDLE")
  text:SetWordWrap(false)
  return text
end

local function CreateEdgeTexture(parent, layer)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK")
  tex:SetTexture(WHITE8X8)
  return tex
end

local function SetButtonBorderVertexColor(data, r, g, b, a)
  if not data then return end
  if data.borderTop then data.borderTop:SetVertexColor(r, g, b, a) end
  if data.borderBottom then data.borderBottom:SetVertexColor(r, g, b, a) end
  if data.borderLeft then data.borderLeft:SetVertexColor(r, g, b, a) end
  if data.borderRight then data.borderRight:SetVertexColor(r, g, b, a) end
end

local function SetNeutralBorder(data, alpha)
  SetButtonBorderVertexColor(data, BORDER_DEFAULT[1], BORDER_DEFAULT[2], BORDER_DEFAULT[3], alpha or 1)
end

local function ApplyControlBackground(bg, inner, outerAlpha, innerAlpha)
  if bg then bg:SetVertexColor(BG_INPUT[1], BG_INPUT[2], BG_INPUT[3], outerAlpha or 1) end
  if inner then inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], innerAlpha or 0.18) end
end

local function ApplyHoverInner(inner, alpha)
  if inner then inner:SetVertexColor(BG_HOVER[1], BG_HOVER[2], BG_HOVER[3], alpha or 0.18) end
end


local function UpdateActionButtonVisual(button, state)
  if not button then return end
  state = state or ((button:IsEnabled() and "normal") or "disabled")
  local data = button._gseActionStyle
  if not data then return end

  local classR, classG, classB = optionsModule.GetClassColor()
  local bg = data.bg
  local inner = data.inner
  local glow = data.glow
  local accent = data.accent
  local text = data.text

  if state == "disabled" then
    if bg then bg:SetVertexColor(BG_INPUT[1], BG_INPUT[2], BG_INPUT[3], 0.68) end
    if inner then inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.08) end
    SetButtonBorderVertexColor(data, BORDER_DARK[1], BORDER_DARK[2], BORDER_DARK[3], 1)
    glow:SetVertexColor(classR, classG, classB, 0)
    accent:SetVertexColor(classR, classG, classB, 0)
    text:SetTextColor(TEXT_DISABLED[1], TEXT_DISABLED[2], TEXT_DISABLED[3], 1)
  elseif state == "pressed" then
    if bg then bg:SetVertexColor(BG_HOVER[1], BG_HOVER[2], BG_HOVER[3], 1) end
    if inner then inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.02) end
    SetButtonBorderVertexColor(data, classR, classG, classB, 0.78)
    glow:SetVertexColor(classR, classG, classB, 0.05)
    accent:SetVertexColor(classR, classG, classB, 0.22)
    text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
  elseif state == "hover" then
    if bg then bg:SetVertexColor(BG_LIGHT[1], BG_LIGHT[2], BG_LIGHT[3], 1) end
    if inner then inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.02) end
    SetButtonBorderVertexColor(data, classR, classG, classB, 0.62)
    glow:SetVertexColor(classR, classG, classB, 0.03)
    accent:SetVertexColor(classR, classG, classB, 0.14)
    text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
  else
    if bg then bg:SetVertexColor(BG_INPUT[1], BG_INPUT[2], BG_INPUT[3], 0.96) end
    if inner then inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.08) end
    SetButtonBorderVertexColor(data, BORDER_INPUT[1], BORDER_INPUT[2], BORDER_INPUT[3], 1)
    glow:SetVertexColor(classR, classG, classB, 0)
    accent:SetVertexColor(classR, classG, classB, 0)
    text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
  end
end

local function SetCheckboxBorderVertexColor(data, r, g, b, a)
  if not data then return end
  if data.borderTop then data.borderTop:SetVertexColor(r, g, b, a) end
  if data.borderBottom then data.borderBottom:SetVertexColor(r, g, b, a) end
  if data.borderLeft then data.borderLeft:SetVertexColor(r, g, b, a) end
  if data.borderRight then data.borderRight:SetVertexColor(r, g, b, a) end
end

local function SetToggleKnobPosition(button, centerX)
  local data = button and button._gseCheckboxStyle
  if not data then return end
  data.currentKnobX = centerX
  if data.knob then
    data.knob:ClearAllPoints()
    data.knob:SetPoint("CENTER", button, "LEFT", centerX, 0)
  end
  if data.glow then
    data.glow:ClearAllPoints()
    data.glow:SetPoint("CENTER", button, "LEFT", centerX, 0)
  end
end

local function StartToggleKnobAnimation(button, targetX)
  local data = button and button._gseCheckboxStyle
  if not data then return end
  if not data.knobDriver then
    local driver = API.CreateFrame("Frame", nil, button)
    driver:Hide()
    driver:SetAllPoints(button)
    data.knobDriver = driver
  end

  local fromX = data.currentKnobX or targetX
  data.animFromX = fromX
  data.animToX = targetX
  data.animElapsed = 0
  data.animDuration = 0.08

  data.knobDriver:SetScript("OnUpdate", function(self, elapsed)
    data.animElapsed = math.min((data.animElapsed or 0) + (elapsed or 0), data.animDuration or 0.08)
    local t = (data.animDuration and data.animDuration > 0) and (data.animElapsed / data.animDuration) or 1
    local eased = 1 - ((1 - t) ^ 3)
    SetToggleKnobPosition(button, data.animFromX + ((data.animToX - data.animFromX) * eased))
    if t >= 1 then
      SetToggleKnobPosition(button, data.animToX)
      self:SetScript("OnUpdate", nil)
      self:Hide()
    end
  end)
  data.knobDriver:Show()
end

local function UpdateCheckboxVisual(button, state)
  if not button then return end
  local data = button._gseCheckboxStyle
  if not data then return end

  local checked = button:GetChecked() and true or false
  state = state or ((button:IsEnabled() and (checked and "checked" or "normal")) or "disabled")
  if checked and state == "hover" then
    state = "checked"
  end

  local classR, classG, classB = optionsModule.GetClassColor()
  local buttonWidth = button.GetWidth and button:GetWidth() or 34
  local knobWidth = (data.knob and data.knob.GetWidth and data.knob:GetWidth()) or 10
  local knobHalf = math.floor((knobWidth * 0.5) + 0.5)
  local knobInset = 3
  local knobCenterX = checked and (buttonWidth - knobInset - knobHalf) or (knobInset + knobHalf)

  if data.currentKnobX == nil then
    SetToggleKnobPosition(button, knobCenterX)
  elseif data.lastChecked ~= checked then
    StartToggleKnobAnimation(button, knobCenterX)
  elseif math.abs((data.currentKnobX or 0) - knobCenterX) > 0.05 then
    SetToggleKnobPosition(button, knobCenterX)
  end
  data.lastChecked = checked

  if state == "disabled" then
    if data.bg then data.bg:SetVertexColor(BG_INPUT[1], BG_INPUT[2], BG_INPUT[3], 0.55) end
    if data.inner then data.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0) end
    data.fill:SetVertexColor(classR, classG, classB, checked and 0.18 or 0)
    if data.knob then data.knob:SetVertexColor(TEXT_DISABLED[1], TEXT_DISABLED[2], TEXT_DISABLED[3], 1) end
    SetCheckboxBorderVertexColor(data, BORDER_DARK[1], BORDER_DARK[2], BORDER_DARK[3], 1)
    data.glow:SetVertexColor(classR, classG, classB, 0)
    if button.Text then button.Text:SetTextColor(TEXT_DISABLED[1], TEXT_DISABLED[2], TEXT_DISABLED[3], 1) end
  elseif state == "pressed" then
    if checked then
      if data.bg then data.bg:SetVertexColor(classR, classG, classB, 0.86) end
      data.fill:SetVertexColor(classR, classG, classB, 0.18)
      SetCheckboxBorderVertexColor(data, classR, classG, classB, 1)
    else
      if data.bg then data.bg:SetVertexColor(BG_LIGHT[1], BG_LIGHT[2], BG_LIGHT[3], 1) end
      data.fill:SetVertexColor(CONTROL_TRACK_OFF[1], CONTROL_TRACK_OFF[2], CONTROL_TRACK_OFF[3], 1)
      SetCheckboxBorderVertexColor(data, BORDER_HOVER[1], BORDER_HOVER[2], BORDER_HOVER[3], 1)
    end
    if data.inner then data.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0) end
    if data.knob then data.knob:SetVertexColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1) end
    data.glow:SetVertexColor(classR, classG, classB, checked and 0.12 or 0.04)
    if button.Text then button.Text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1) end
  elseif state == "hover" then
    if checked then
      if data.bg then data.bg:SetVertexColor(classR, classG, classB, 0.82) end
      data.fill:SetVertexColor(classR, classG, classB, 0.14)
      SetCheckboxBorderVertexColor(data, classR, classG, classB, 1)
    else
      if data.bg then data.bg:SetVertexColor(BG_LIGHT[1], BG_LIGHT[2], BG_LIGHT[3], 1) end
      data.fill:SetVertexColor(CONTROL_TRACK_OFF[1], CONTROL_TRACK_OFF[2], CONTROL_TRACK_OFF[3], 1)
      SetCheckboxBorderVertexColor(data, BORDER_HOVER[1], BORDER_HOVER[2], BORDER_HOVER[3], 1)
    end
    if data.inner then data.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0) end
    if data.knob then data.knob:SetVertexColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1) end
    data.glow:SetVertexColor(classR, classG, classB, checked and 0.08 or 0.03)
    if button.Text then button.Text:SetTextColor(checked and TEXT_PRIMARY[1] or TEXT_SECONDARY[1], checked and TEXT_PRIMARY[2] or TEXT_SECONDARY[2], checked and TEXT_PRIMARY[3] or TEXT_SECONDARY[3], 1) end
  elseif state == "checked" then
    if data.bg then data.bg:SetVertexColor(classR, classG, classB, 0.78) end
    if data.inner then data.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0) end
    data.fill:SetVertexColor(classR, classG, classB, 0.12)
    if data.knob then data.knob:SetVertexColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1) end
    SetCheckboxBorderVertexColor(data, classR, classG, classB, 1)
    data.glow:SetVertexColor(classR, classG, classB, 0.05)
    if button.Text then button.Text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1) end
  else
    if data.bg then data.bg:SetVertexColor(CONTROL_TRACK_OFF[1], CONTROL_TRACK_OFF[2], CONTROL_TRACK_OFF[3], 1) end
    if data.inner then data.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0) end
    data.fill:SetVertexColor(CONTROL_TRACK_OFF[1], CONTROL_TRACK_OFF[2], CONTROL_TRACK_OFF[3], 1)
    if data.knob then data.knob:SetVertexColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1) end
    SetCheckboxBorderVertexColor(data, BORDER_DEFAULT[1], BORDER_DEFAULT[2], BORDER_DEFAULT[3], 1)
    data.glow:SetVertexColor(classR, classG, classB, 0)
    if button.Text then button.Text:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3], 1) end
  end
end

function optionsModule.StyleCheckbox(button)
  if not button then return end
  -- Native skin: leave Blizzard's default checkbox textures intact.
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then return end

  local normal = button.GetNormalTexture and button:GetNormalTexture()
  local pushed = button.GetPushedTexture and button:GetPushedTexture()
  local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
  local checked = button.GetCheckedTexture and button:GetCheckedTexture()
  local disabledChecked = button.GetDisabledCheckedTexture and button:GetDisabledCheckedTexture()
  HideTexture(normal)
  HideTexture(pushed)
  HideTexture(highlight)
  HideTexture(checked)
  HideTexture(disabledChecked)
  StripUICheckButtonRegions(button)

  if not button._gseCheckboxStyle then
    button:SetSize(optionsModule.TOGGLE_W or 46, 20)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE8X8)
    bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

    local inner = button:CreateTexture(nil, "BORDER")
    inner:SetTexture(WHITE8X8)
    inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local fill = button:CreateTexture(nil, "BORDER")
    fill:SetTexture(WHITE8X8)
    fill:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    local knob = button:CreateTexture(nil, "ARTWORK")
    knob:SetTexture(WHITE8X8)
    knob:SetSize(16, 16)

    local borderTop = CreateEdgeTexture(button, "ARTWORK")
    borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)

    local borderBottom = CreateEdgeTexture(button, "ARTWORK")
    borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)

    local borderLeft = CreateEdgeTexture(button, "ARTWORK")
    borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)

    local borderRight = CreateEdgeTexture(button, "ARTWORK")
    borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)

    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(WHITE8X8)
    glow:SetSize(16, 16)

    local slash = button:CreateTexture(nil, "OVERLAY")
    slash:SetTexture(WHITE8X8)
    slash:SetPoint("CENTER", button, "CENTER", 0, 0)
    slash:SetSize(math.min((optionsModule.TOGGLE_W or 46) - 12, 32), 1)
    slash:SetRotation(math.rad(-45))
    slash:SetVertexColor(0.55, 0.57, 0.62, 0.65)
    slash:Hide()

    button._gseCheckboxStyle = {
      bg = bg,
      inner = inner,
      fill = fill,
      knob = knob,
      borderTop = borderTop,
      borderBottom = borderBottom,
      borderLeft = borderLeft,
      borderRight = borderRight,
      glow = glow,
      disabledSlash = slash,
    }

    if hooksecurefunc then
      hooksecurefunc(button, "SetChecked", function(self)
        UpdateCheckboxVisual(self)
      end)
    end

    button:HookScript("OnEnter", function(self)
      UpdateCheckboxVisual(self, self:GetChecked() and "checked" or "hover")
    end)
    button:HookScript("OnLeave", function(self)
      UpdateCheckboxVisual(self)
    end)
    button:HookScript("OnMouseDown", function(self)
      if self:IsEnabled() then UpdateCheckboxVisual(self, "pressed") end
    end)
    button:HookScript("OnMouseUp", function(self)
      if not self:IsEnabled() then
        UpdateCheckboxVisual(self, "disabled")
      elseif self:IsMouseOver() then
        UpdateCheckboxVisual(self, self:GetChecked() and "checked" or "hover")
      else
        UpdateCheckboxVisual(self)
      end
    end)
    button:HookScript("OnClick", function(self)
      UpdateCheckboxVisual(self, self:GetChecked() and "checked" or "hover")
    end)
    button:HookScript("OnEnable", function(self)
      if self._gseCheckboxStyle and self._gseCheckboxStyle.disabledSlash then
        self._gseCheckboxStyle.disabledSlash:Hide()
      end
      UpdateCheckboxVisual(self)
    end)
    button:HookScript("OnDisable", function(self)
      if self._gseCheckboxStyle and self._gseCheckboxStyle.disabledSlash then
        self._gseCheckboxStyle.disabledSlash:Show()
      end
      UpdateCheckboxVisual(self, "disabled")
    end)
  end

  if button.Text then
    button.Text:SetFontObject("GameFontNormal")
    button.Text:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3], 1)
  end
  if button._gseCheckboxStyle and button._gseCheckboxStyle.disabledSlash then
    if button:IsEnabled() then button._gseCheckboxStyle.disabledSlash:Hide() else button._gseCheckboxStyle.disabledSlash:Show() end
  end
  UpdateCheckboxVisual(button)
end

function optionsModule.StyleActionButton(button)
  if not button then return end
  -- Native skin: leave Blizzard's default UIPanelButton look (text already set).
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then return end

  local normal = button.GetNormalTexture and button:GetNormalTexture()
  local pushed = button.GetPushedTexture and button:GetPushedTexture()
  local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
  local disabled = button.GetDisabledTexture and button:GetDisabledTexture()
  HideTexture(normal)
  HideTexture(pushed)
  HideTexture(highlight)
  HideTexture(disabled)
  StripUIPanelButtonRegions(button)

  if not button._gseActionStyle then
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE8X8)
    bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

    local inner = button:CreateTexture(nil, "BORDER")
    inner:SetTexture(WHITE8X8)
    inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local borderTop = CreateEdgeTexture(button, "ARTWORK")
    borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)

    local borderBottom = CreateEdgeTexture(button, "ARTWORK")
    borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)

    local borderLeft = CreateEdgeTexture(button, "ARTWORK")
    borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)

    local borderRight = CreateEdgeTexture(button, "ARTWORK")
    borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)

    local accent = button:CreateTexture(nil, "OVERLAY")
    accent:SetTexture(WHITE8X8)
    accent:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(WHITE8X8)
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local text = EnsureButtonLabel(button)

    button._gseActionStyle = {
      bg = bg,
      inner = inner,
      borderTop = borderTop,
      borderBottom = borderBottom,
      borderLeft = borderLeft,
      borderRight = borderRight,
      accent = accent,
      glow = glow,
      text = text,
    }

    button:HookScript("OnEnter", function(self) UpdateActionButtonVisual(self, "hover") end)
    button:HookScript("OnLeave", function(self) UpdateActionButtonVisual(self) end)
    button:HookScript("OnMouseDown", function(self)
      if self:IsEnabled() then UpdateActionButtonVisual(self, "pressed") end
    end)
    button:HookScript("OnMouseUp", function(self)
      if not self:IsMouseOver() then
        UpdateActionButtonVisual(self)
      elseif self:IsEnabled() then
        UpdateActionButtonVisual(self, "hover")
      end
    end)
    if button.HookScript then
      button:HookScript("OnEnable", function(self) UpdateActionButtonVisual(self) end)
      button:HookScript("OnDisable", function(self) UpdateActionButtonVisual(self, "disabled") end)
    end
  end

  local text = button._gseActionStyle and button._gseActionStyle.text
  if text then
    text:SetFont(STANDARD_TEXT_FONT, 11, "")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.85)
  end

  UpdateActionButtonVisual(button)
end

local function UpdateCloseButtonVisual(button, state)
  if not button then return end
  state = state or ((button:IsEnabled() and "normal") or "disabled")
  local data = button._gseCloseStyle
  if not data then return end
  for _, tex in ipairs({ data.bg, data.inner, data.borderTop, data.borderBottom, data.borderLeft, data.borderRight, data.glow }) do
    if tex then tex:SetAlpha(0) end
  end
  if state == "disabled" then
    data.x:SetTextColor(TEXT_DISABLED[1], TEXT_DISABLED[2], TEXT_DISABLED[3], 1)
  elseif state == "pressed" then
    data.x:SetTextColor(1, 0.55, 0.55, 1)
  elseif state == "hover" then
    data.x:SetTextColor(1, 0.4, 0.4, 1)
  else
    data.x:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3], 1)
  end
end

function optionsModule.StyleCloseButton(button)
  if not button then return end

  local regions = { button:GetRegions() }
  for _, region in ipairs(regions) do
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
      HideTexture(region)
    end
  end
  HideTexture(button.GetNormalTexture and button:GetNormalTexture())
  HideTexture(button.GetPushedTexture and button:GetPushedTexture())
  HideTexture(button.GetHighlightTexture and button:GetHighlightTexture())
  HideTexture(button.GetDisabledTexture and button:GetDisabledTexture())

  if not button._gseCloseStyle then
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE8X8)
    bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

    local inner = button:CreateTexture(nil, "BORDER")
    inner:SetTexture(WHITE8X8)
    inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local borderTop = CreateEdgeTexture(button, "ARTWORK")
    borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)

    local borderBottom = CreateEdgeTexture(button, "ARTWORK")
    borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)

    local borderLeft = CreateEdgeTexture(button, "ARTWORK")
    borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)

    local borderRight = CreateEdgeTexture(button, "ARTWORK")
    borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)

    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(WHITE8X8)
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local x = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER", button, "CENTER", 0, 0)
    x:SetText("×")
    x:SetShadowOffset(1, -1)
    x:SetShadowColor(0, 0, 0, 0.85)
    x:SetText("x")
    x:SetFont(STANDARD_TEXT_FONT, 18, "")
    x:SetShadowOffset(0, 0)
    x:SetShadowColor(0, 0, 0, 0)

    button._gseCloseStyle = {
      bg = bg,
      inner = inner,
      borderTop = borderTop,
      borderBottom = borderBottom,
      borderLeft = borderLeft,
      borderRight = borderRight,
      glow = glow,
      x = x,
    }

    button:HookScript("OnEnter", function(self) UpdateCloseButtonVisual(self, "hover") end)
    button:HookScript("OnLeave", function(self) UpdateCloseButtonVisual(self) end)
    button:HookScript("OnMouseDown", function(self)
      if self:IsEnabled() then UpdateCloseButtonVisual(self, "pressed") end
    end)
    button:HookScript("OnMouseUp", function(self)
      if not self:IsMouseOver() then
        UpdateCloseButtonVisual(self)
      elseif self:IsEnabled() then
        UpdateCloseButtonVisual(self, "hover")
      end
    end)
    button:HookScript("OnEnable", function(self) UpdateCloseButtonVisual(self) end)
    button:HookScript("OnDisable", function(self) UpdateCloseButtonVisual(self, "disabled") end)
  end

  button:SetSize(28, 28)
  button:SetHitRectInsets(0, 0, 0, 0)
  UpdateCloseButtonVisual(button)
end

local SkinDropdownListButton

function optionsModule.SkinDropdownListFrame(listFrame)
  if not listFrame then return end
  listFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  listFrame:SetClampedToScreen(true)
  HideTextureRegionsRecursive(listFrame)
  for _, key in ipairs({"Backdrop", "MenuBackdrop", "NineSlice", "Bg", "Background", "Border", "Top", "Bottom", "Left", "Right", "Middle"}) do
    if listFrame[key] then
      HideTextureRegionsRecursive(listFrame[key])
      if listFrame[key].Hide then listFrame[key]:Hide() end
    end
  end

  if not listFrame._gseMidnightSkinned then
    listFrame._gseMidnightSkinned = true
    local backdrop = API.CreateFrame("Frame", nil, listFrame, "BackdropTemplate")
    backdrop:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 6, -10)
    backdrop:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, 10)
    backdrop:SetFrameLevel(math.max(listFrame:GetFrameLevel() - 1, 0))
    listFrame._midnightBackdrop = backdrop
  end

  local backdrop = listFrame._midnightBackdrop
  if backdrop then
    backdrop:SetFrameLevel(math.max(listFrame:GetFrameLevel() - 1, 0))
    backdrop:SetBackdrop({
      bgFile = WHITE8X8,
      edgeFile = WHITE8X8,
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    backdrop:SetBackdropColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.98)
    backdrop:SetBackdropBorderColor(BORDER_LIGHT[1], BORDER_LIGHT[2], BORDER_LIGHT[3], 1)
    backdrop:Show()
  end

  if listFrame.MenuBackdrop then listFrame.MenuBackdrop:Hide() end
  if listFrame.Backdrop then listFrame.Backdrop:Hide() end
  for index = 1, UIDROPDOWNMENU_MAXBUTTONS or 32 do
    local button = _G[listFrame:GetName() .. "Button" .. index]
    if button then SkinDropdownListButton(button) end
  end
end

function optionsModule.StyleColorPickerFrame(frame)
  frame = frame or ColorPickerFrame
  if not frame then return end

  local function CollectFrames(root, out, depth)
    if not root or depth > 4 or not root.GetChildren then return end
    local children = { root:GetChildren() }
    for _, child in ipairs(children) do
      out[#out + 1] = child
      CollectFrames(child, out, depth + 1)
    end
  end

  local function FindColorPickerButtons(target)
    local buttons = {}
    local seen = {}

    local function AddButton(btn)
      if btn and not seen[btn] then
        seen[btn] = true
        buttons[#buttons + 1] = btn
      end
    end

    AddButton(target.OkayButton)
    AddButton(target.CancelButton)
    AddButton(target.DefaultButton)
    AddButton(_G.ColorPickerOkayButton)
    AddButton(_G.ColorPickerCancelButton)
    AddButton(_G.ColorPickerDefaultButton)

    local frames = {}
    CollectFrames(target, frames, 1)
    for _, child in ipairs(frames) do
      if child and child.GetObjectType and child:GetObjectType() == "Button" then
        local name = child.GetName and child:GetName() or ""
        local textObj = child.GetFontString and child:GetFontString() or nil
        local text = textObj and textObj.GetText and textObj:GetText() or ""
        name = tostring(name or ""):lower()
        text = tostring(text or ""):lower()
        if name:find("okay", 1, true) or name:find("cancel", 1, true) or name:find("default", 1, true)
          or text == tostring(OKAY):lower() or text == tostring(CANCEL):lower() or text == tostring(DEFAULT):lower() then
          AddButton(child)
        end
      end
    end

    return buttons
  end

  local function RestyleColorPickerButtons(target)
    for _, btn in ipairs(FindColorPickerButtons(target)) do
      if btn._gseActionStyle then
        local style = btn._gseActionStyle
        if style.bg then style.bg:Show() end
        if style.inner then style.inner:Show() end
        if style.borderTop then style.borderTop:Show() end
        if style.borderBottom then style.borderBottom:Show() end
        if style.borderLeft then style.borderLeft:Show() end
        if style.borderRight then style.borderRight:Show() end
        if style.accent then style.accent:Show() end
        if style.glow then style.glow:Show() end
      else
        HideTexture(btn.GetNormalTexture and btn:GetNormalTexture())
        HideTexture(btn.GetPushedTexture and btn:GetPushedTexture())
        HideTexture(btn.GetHighlightTexture and btn:GetHighlightTexture())
        HideTexture(btn.GetDisabledTexture and btn:GetDisabledTexture())
        StripUIPanelButtonRegions(btn)
      end
      if optionsModule.StyleActionButton then optionsModule.StyleActionButton(btn) end
    end
  end

  if not frame._gseColorPickerStyled then
    frame._gseColorPickerStyled = true

    for _, key in ipairs({
      "Header", "TitleContainer", "NineSlice", "Border", "Background", "Bg", "Top", "Bottom", "Left", "Right"
    }) do
      local region = frame[key]
      if region then HideTextureRegionsRecursive(region) end
    end
    if frame.NineSlice then HideTextureRegionsRecursive(frame.NineSlice) end
    if frame.Header then HideTextureRegionsRecursive(frame.Header) end
    if frame.TitleContainer then HideTextureRegionsRecursive(frame.TitleContainer) end

    local backdropParent = frame.Content or frame
    local backdrop = API.CreateFrame("Frame", nil, backdropParent, "BackdropTemplate")
    backdrop:SetPoint("TOPLEFT", backdropParent, "TOPLEFT", -8, 8)
    backdrop:SetPoint("BOTTOMRIGHT", backdropParent, "BOTTOMRIGHT", 8, -8)
    backdrop:SetFrameLevel(math.max(backdropParent:GetFrameLevel() - 1, 0))

    local bg = backdrop:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE8X8)
    bg:SetAllPoints(backdrop)

    local inner = backdrop:CreateTexture(nil, "BORDER")
    inner:SetTexture(WHITE8X8)
    inner:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 1)

    local borderTop = CreateEdgeTexture(backdrop, "ARTWORK")
    borderTop:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)
    local borderBottom = CreateEdgeTexture(backdrop, "ARTWORK")
    borderBottom:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)
    local borderLeft = CreateEdgeTexture(backdrop, "ARTWORK")
    borderLeft:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)
    local borderRight = CreateEdgeTexture(backdrop, "ARTWORK")
    borderRight:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)

    frame._gseColorPickerStyle = {
      backdrop = backdrop,
      bg = bg,
      inner = inner,
      borderTop = borderTop,
      borderBottom = borderBottom,
      borderLeft = borderLeft,
      borderRight = borderRight,
    }

    for _, slider in ipairs({ frame.OpacitySliderFrame, frame.OpacitySlider, frame.HueSlider }) do
      if slider and slider.GetObjectType and slider:GetObjectType() == "Slider" then optionsModule.StyleSlider(slider) end
    end
    for _, box in ipairs({ frame.HexBox, frame.OpacityBox, frame.RedBox, frame.GreenBox, frame.BlueBox }) do
      if box and box.GetObjectType and box:GetObjectType() == "EditBox" then optionsModule.StyleEditBox(box) end
    end
    if frame.SwatchBg then HideTexture(frame.SwatchBg) end

    frame:HookScript("OnShow", function(self)
      RestyleColorPickerButtons(self)
      local currentStyle = self._gseColorPickerStyle
      if currentStyle and currentStyle.backdrop then
        currentStyle.backdrop:Show()
        currentStyle.backdrop:SetFrameLevel(math.max(((self.Content or self):GetFrameLevel()) - 1, 0))
      end
    end)
  end

  RestyleColorPickerButtons(frame)

  local style = frame._gseColorPickerStyle
  if style then
    local r, g, b = optionsModule.GetClassColor()
    ApplyControlBackground(style.bg, style.inner, 0.98, 0.18)
    SetButtonBorderVertexColor(style, r, g, b, 0.80)
    if style.backdrop then style.backdrop:Show() end
  end
end
function optionsModule.EnsureMidnightDropdownLists()
  if not UIDROPDOWNMENU_MAXLEVELS then return end
  for i = 1, UIDROPDOWNMENU_MAXLEVELS or 2 do
    local listFrame = _G["DropDownList" .. i]
    if listFrame then
      optionsModule.SkinDropdownListFrame(listFrame)
      if not listFrame._gseMidnightHooked then
        listFrame._gseMidnightHooked = true
        listFrame:HookScript("OnShow", function(self)
          optionsModule.SkinDropdownListFrame(self)
          if self._midnightBackdrop then self._midnightBackdrop:Show() end
          if self.MenuBackdrop then self.MenuBackdrop:Hide() end
          if self.Backdrop then self.Backdrop:Hide() end
          for index = 1, UIDROPDOWNMENU_MAXBUTTONS or 32 do
            local button = _G[self:GetName() .. "Button" .. index]
            if button then SkinDropdownListButton(button) end
          end
        end)
      end
    end
  end
end

local function ApplyDropdownVisual(dropdown, hover)
  if not dropdown then return end
  local data = dropdown._gseDropdownStyle
  if not data then return end
  local r, g, b = optionsModule.GetClassColor()
  if data.bg then
    local base = hover and BG_HOVER or BG_INPUT
    data.bg:SetVertexColor(base[1], base[2], base[3], 1)
  end
  if data.inner then
    data.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)
  end
  if hover then
    SetButtonBorderVertexColor(data, r, g, b, 1)
  else
    SetButtonBorderVertexColor(data, BORDER_INPUT[1], BORDER_INPUT[2], BORDER_INPUT[3], 1)
  end
  if data.arrowLeft and data.arrowRight then
    if hover then
      data.arrowLeft:SetVertexColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
      data.arrowRight:SetVertexColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
    else
      data.arrowLeft:SetVertexColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1)
      data.arrowRight:SetVertexColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1)
    end
  end
  if dropdown.Text then
    if hover then
      dropdown.Text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
    else
      dropdown.Text:SetTextColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1)
    end
  end
end

local function IsDropdownListButtonChecked(button)
  if not button then return false end
  if button.checked ~= nil then return button.checked and true or false end
  local openMenu = _G.UIDROPDOWNMENU_OPEN_MENU
  if openMenu and button.value ~= nil then
    local selectedValue = openMenu.selectedValue
    local getSelectedValue = _G.UIDropDownMenu_GetSelectedValue
    if selectedValue == nil and getSelectedValue then
      selectedValue = getSelectedValue(openMenu)
    end
    if selectedValue ~= nil and selectedValue == button.value then
      return true
    end
  end
  if button.Check and button.Check.IsShown and button.Check:IsShown() then return true end
  return false
end

local function ApplyDropdownListButtonVisual(button, hovered)
  if not button or not button._gseMenuItemStyle then return end
  local d = button._gseMenuItemStyle
  local r, g, b = optionsModule.GetClassColor()
  local checked = IsDropdownListButtonChecked(button)

  if hovered or checked then
    d.bg:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)
    d.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)
    d.selection:SetVertexColor(r, g, b, hovered and 0.30 or 0.14)
    if d.hover then
      d.hover:SetVertexColor(r, g, b, hovered and 0.08 or 0)
    end
    d.accent:SetVertexColor(r, g, b, 0)
    d.accent:SetWidth(0)
    if d.text then d.text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1) end
  else
    d.bg:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)
    d.inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)
    d.selection:SetVertexColor(r, g, b, 0)
    if d.hover then
      d.hover:SetVertexColor(BG_LIGHT[1], BG_LIGHT[2], BG_LIGHT[3], 0)
    end
    d.accent:SetVertexColor(r, g, b, 0)
    d.accent:SetWidth(0)
    if d.text then d.text:SetTextColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1) end
  end
end

SkinDropdownListButton = function(button)
  if not button then return end
  HideTexture(button.GetNormalTexture and button:GetNormalTexture())
  HideTexture(button.GetPushedTexture and button:GetPushedTexture())
  HideTexture(button.GetHighlightTexture and button:GetHighlightTexture())
  HideTexture(button.GetDisabledTexture and button:GetDisabledTexture())
  HideTexture(button.GetCheckedTexture and button:GetCheckedTexture())
  HideTexture(button.GetDisabledCheckedTexture and button:GetDisabledCheckedTexture())
  for _, key in ipairs({"NormalTexture", "Highlight", "HighlightTexture", "Check", "UnCheck", "ExpandArrow", "ColorSwatch", "InvisibleButton", "Icon"}) do
    local region = button[key]
    if region then HideTexture(region) end
  end
  local name = button.GetName and button:GetName()
  local text = name and (_G[name .. "NormalText"] or _G[name .. "Text"]) or button.NormalText
  for _, suffix in ipairs({"NormalTexture", "Highlight", "HighlightTexture", "Check", "UnCheck", "ExpandArrow", "ColorSwatch"}) do
    if name and _G[name .. suffix] then HideTexture(_G[name .. suffix]) end
  end
  if text then text:SetTextColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1) end

  if not button._gseMenuItemStyle then
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE8X8)
    bg:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
    bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 1)

    local inner = button:CreateTexture(nil, "BORDER")
    inner:SetTexture(WHITE8X8)
    inner:SetPoint("TOPLEFT", bg, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -1, 1)

    local selection = button:CreateTexture(nil, "ARTWORK")
    selection:SetTexture(WHITE8X8)
    selection:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
    selection:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)

    local hover = button:CreateTexture(nil, "ARTWORK")
    hover:SetTexture(WHITE8X8)
    hover:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)

    local accent = button:CreateTexture(nil, "ARTWORK")
    accent:SetTexture(WHITE8X8)
    accent:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(0)

    button._gseMenuItemStyle = {
      bg = bg,
      inner = inner,
      selection = selection,
      hover = hover,
      accent = accent,
      text = text,
    }

    button:HookScript("OnEnter", function(self)
      ApplyDropdownListButtonVisual(self, true)
    end)
    button:HookScript("OnLeave", function(self)
      ApplyDropdownListButtonVisual(self, false)
    end)
    button:HookScript("OnShow", function(self)
      ApplyDropdownListButtonVisual(self, self:IsMouseOver())
    end)
    button:HookScript("OnHide", function(self)
      ApplyDropdownListButtonVisual(self, false)
    end)
  else
    button._gseMenuItemStyle.text = text
    if button._gseMenuItemStyle.bg then button._gseMenuItemStyle.bg:Show() end
    if button._gseMenuItemStyle.inner then button._gseMenuItemStyle.inner:Show() end
    if button._gseMenuItemStyle.selection then button._gseMenuItemStyle.selection:Show() end
    if button._gseMenuItemStyle.hover then button._gseMenuItemStyle.hover:Show() end
    if button._gseMenuItemStyle.accent then button._gseMenuItemStyle.accent:Show() end
  end

  ApplyDropdownListButtonVisual(button, button:IsMouseOver())
end

function optionsModule.StyleDropdown(dropdown, holder)
  if not dropdown or dropdown._gseDropdownStyled then return end
  dropdown._gseDropdownStyled = true
  -- Native skin: leave Blizzard's default UIDropDownMenu look.
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then return end

  local parent = holder or dropdown
  local bg = parent:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE8X8)
  bg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

  local inner = parent:CreateTexture(nil, "BORDER")
  inner:SetTexture(WHITE8X8)
  inner:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)

  local borderTop = CreateEdgeTexture(parent, "ARTWORK")
  borderTop:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  borderTop:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  borderTop:SetHeight(1)
  local borderBottom = CreateEdgeTexture(parent, "ARTWORK")
  borderBottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  borderBottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  borderBottom:SetHeight(1)
  local borderLeft = CreateEdgeTexture(parent, "ARTWORK")
  borderLeft:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  borderLeft:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  borderLeft:SetWidth(1)
  local borderRight = CreateEdgeTexture(parent, "ARTWORK")
  borderRight:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  borderRight:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  borderRight:SetWidth(1)

  local arrowFrame = API.CreateFrame("Frame", nil, parent)
  arrowFrame:SetSize(12, 8)
  arrowFrame:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
  if arrowFrame.EnableMouse then arrowFrame:EnableMouse(false) end

  local arrowLeft = arrowFrame:CreateTexture(nil, "OVERLAY")
  arrowLeft:SetTexture(WHITE8X8)
  arrowLeft:SetSize(7, 1.5)
  arrowLeft:SetPoint("CENTER", arrowFrame, "CENTER", -2, 0)
  arrowLeft:SetRotation(math.rad(-45))

  local arrowRight = arrowFrame:CreateTexture(nil, "OVERLAY")
  arrowRight:SetTexture(WHITE8X8)
  arrowRight:SetSize(7, 1.5)
  arrowRight:SetPoint("CENTER", arrowFrame, "CENTER", 2, 0)
  arrowRight:SetRotation(math.rad(45))

  local data = {
    bg = bg,
    inner = inner,
    borderTop = borderTop,
    borderBottom = borderBottom,
    borderLeft = borderLeft,
    borderRight = borderRight,
    arrowFrame = arrowFrame,
    arrowLeft = arrowLeft,
    arrowRight = arrowRight,
  }
  dropdown._gseDropdownStyle = data

  HideTextureRegionsRecursive(dropdown)

  local button
  if dropdown._gseModern then
    if dropdown.Text then dropdown.Text:SetAlpha(0) end
    if dropdown.fontString then dropdown.fontString:SetAlpha(0) end
    button = dropdown.Button or dropdown.DropDownButton
  else
    local prefix = dropdown:GetName()
    for _, suffix in ipairs({"Left", "Middle", "Right"}) do
      local region = prefix and _G[prefix .. suffix]
      if region then HideTexture(region) end
    end
    button = prefix and _G[prefix .. "Button"]
  end

  if button then
    HideTextureRegionsRecursive(button)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    button:SetHitRectInsets(0, 0, 0, 0)
    button:RegisterForClicks("LeftButtonUp")
    button:SetAlpha(1)
    button:SetFrameStrata(parent:GetFrameStrata())
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    data.button = button
    dropdown.button = button
  end

  if dropdown.Text then
    dropdown.Text:ClearAllPoints()
    dropdown.Text:SetPoint("LEFT", parent, "LEFT", 12, 0)
    dropdown.Text:SetPoint("RIGHT", parent, "RIGHT", -30, 0)
    dropdown.Text:SetJustifyH("LEFT")
    dropdown.Text:SetWordWrap(false)
    dropdown.Text:SetTextColor(0.92, 0.92, 0.98)
  end

  dropdown:HookScript("OnEnter", function() ApplyDropdownVisual(dropdown, true) end)
  dropdown:HookScript("OnLeave", function() ApplyDropdownVisual(dropdown, false) end)
  if button then
    button:HookScript("OnEnter", function() ApplyDropdownVisual(dropdown, true) end)
    button:HookScript("OnLeave", function() ApplyDropdownVisual(dropdown, false) end)
    button:HookScript("OnMouseDown", function() ApplyDropdownVisual(dropdown, true) end)
    button:HookScript("OnMouseUp", function()
      if dropdown:IsMouseOver() or button:IsMouseOver() then
        ApplyDropdownVisual(dropdown, true)
      else
        ApplyDropdownVisual(dropdown, false)
      end
    end)
  end
  ApplyDropdownVisual(dropdown, false)
end

function optionsModule.GetDropdownButton(dropdown)
  if not dropdown then return nil end
  local style = dropdown._gseDropdownStyle
  return (style and style.button) or dropdown.button or dropdown.Button or dropdown.DropDownButton
end

function optionsModule.SetDropdownEnabled(dropdown, enabled, alpha)
  local button = optionsModule.GetDropdownButton(dropdown)
  if not button then return false end
  if enabled then button:Enable() else button:Disable() end
  button:SetAlpha(alpha ~= nil and alpha or (enabled and 1 or 0.5))
  return true
end

function optionsModule.StyleEditBox(box)
  if not box or box._gseEditStyled then return end
  box._gseEditStyled = true
  -- Native skin: leave Blizzard's default InputBoxTemplate look.
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then return end
  for _, region in ipairs({ box:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then HideTexture(region) end
  end
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE8X8)
  bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
  local inner = box:CreateTexture(nil, "BORDER")
  inner:SetTexture(WHITE8X8)
  inner:SetPoint("TOPLEFT", bg, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -1, 1)
  local borderTop = CreateEdgeTexture(box, "ARTWORK")
  borderTop:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
  borderTop:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
  borderTop:SetHeight(1)
  local borderBottom = CreateEdgeTexture(box, "ARTWORK")
  borderBottom:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
  borderBottom:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
  borderBottom:SetHeight(1)
  local borderLeft = CreateEdgeTexture(box, "ARTWORK")
  borderLeft:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
  borderLeft:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
  borderLeft:SetWidth(1)
  local borderRight = CreateEdgeTexture(box, "ARTWORK")
  borderRight:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
  borderRight:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
  borderRight:SetWidth(1)
  local data={bg=bg,inner=inner,borderTop=borderTop,borderBottom=borderBottom,borderLeft=borderLeft,borderRight=borderRight}
  box._gseEditStyle=data
  local function restyle(active)
    ApplyControlBackground(bg, nil, 0.96)
    if active then
      local r, g, b = optionsModule.GetClassColor()
      ApplyHoverInner(inner, 0.16)
      SetButtonBorderVertexColor(data, r, g, b, 0.70)
    else
      ApplyControlBackground(nil, inner, nil, 0.12)
      SetNeutralBorder(data, 0.96)
    end
  end
  box:HookScript("OnEditFocusGained", function() restyle(true) end)
  box:HookScript("OnEditFocusLost", function() restyle(false) end)
  box:HookScript("OnEnter", function(self) if not self:HasFocus() then restyle(true) end end)
  box:HookScript("OnLeave", function(self) if not self:HasFocus() then restyle(false) end end)
  restyle(false)
end

function optionsModule.StyleSlider(slider)
  if not slider or slider._gseSliderStyled then return end
  slider._gseSliderStyled = true
  -- Native skin: keep Blizzard's default slider thumb/track; provide a no-op
  -- visual updater so callers (SetSliderBoxValue path) stay safe.
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then
    slider._gseSliderVisualUpdate = function() end
    return
  end

  HideTextureRegionsRecursive(slider)
  local low = _G[slider:GetName() .. "Low"]
  local high = _G[slider:GetName() .. "High"]
  local text = _G[slider:GetName() .. "Text"]
  if text then text:Hide() end

  local trackOuter = slider:CreateTexture(nil, "BACKGROUND")
  trackOuter:SetTexture(WHITE8X8)
  trackOuter:SetPoint("LEFT", slider, "LEFT", 0, 0)
  trackOuter:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
  trackOuter:SetHeight(4)

  local trackInner = slider:CreateTexture(nil, "BORDER")
  trackInner:SetTexture(WHITE8X8)
  trackInner:SetPoint("TOPLEFT", trackOuter, "TOPLEFT", 1, -1)
  trackInner:SetPoint("BOTTOMRIGHT", trackOuter, "BOTTOMRIGHT", -1, 1)

  local fill = slider:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(WHITE8X8)
  fill:SetPoint("LEFT", trackInner, "LEFT", 0, 0)
  fill:SetWidth(0)
  fill:SetPoint("TOP", trackInner, "TOP", 0, 0)
  fill:SetPoint("BOTTOM", trackInner, "BOTTOM", 0, 0)

  slider:SetThumbTexture(WHITE8X8)
  local nativeThumb = slider:GetThumbTexture()
  if nativeThumb then
    nativeThumb:SetSize(12, 18)
    nativeThumb:SetVertexColor(1, 1, 1, 0.01)
  end

  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture(WHITE8X8)
  thumb:SetSize(10, 14)

  local thumbGlow = slider:CreateTexture(nil, "OVERLAY")
  thumbGlow:SetTexture(WHITE8X8)
  thumbGlow:SetSize(12, 18)

  slider._gseSliderStyle = {
    trackOuter = trackOuter,
    trackInner = trackInner,
    fill = fill,
    nativeThumb = nativeThumb,
    thumb = thumb,
    thumbGlow = thumbGlow,
    dragging = false,
  }

  local function update()
    local data = slider._gseSliderStyle
    if not data then return end
    local minV, maxV = slider:GetMinMaxValues()
    local v = slider:GetValue()
    local pct = (maxV and minV and maxV ~= minV) and ((v - minV) / (maxV - minV)) or 0
    pct = math.max(0, math.min(1, pct or 0))
    local width = math.max((data.trackInner:GetWidth() or 0), 0)
    local thumbWidth = (data.thumb and data.thumb:GetWidth()) or 0
    local usableWidth = math.max(width - thumbWidth, 0)
    local thumbOffset = math.floor((usableWidth * pct) + 0.5) + math.floor((thumbWidth * 0.5) + 0.5)
    thumbOffset = math.max(0, math.min(width, thumbOffset))
    local fillWidth = math.max(0, math.min(width, thumbOffset - math.floor((thumbWidth * 0.5) + 0.5)))
    data.fill:SetWidth(fillWidth)

    local r, g, b = optionsModule.GetClassColor()
    local hot = data.dragging or slider:IsMouseOver()
    data.trackOuter:SetVertexColor(CONTROL_TRACK[1], CONTROL_TRACK[2], CONTROL_TRACK[3], 1)
    data.trackInner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)
    data.fill:SetVertexColor(r, g, b, slider:IsEnabled() and 1 or 0.35)
    data.thumb:SetVertexColor(r, g, b, slider:IsEnabled() and 1 or 0.45)
    data.thumbGlow:SetVertexColor(r, g, b, hot and 0.22 or (slider:IsEnabled() and 0.12 or 0.05))

    data.thumb:ClearAllPoints()
    data.thumb:SetPoint("CENTER", data.trackInner, "LEFT", thumbOffset, 0)
    data.thumbGlow:ClearAllPoints()
    data.thumbGlow:SetPoint("CENTER", data.trackInner, "LEFT", thumbOffset, 0)
  end

  slider._gseSliderVisualUpdate = update

  local dragDriver = API.CreateFrame("Frame", nil, slider)
  dragDriver:Hide()
  dragDriver:SetAllPoints(slider)
  dragDriver:SetScript("OnUpdate", function(self)
    if slider._gseSliderStyle and slider._gseSliderStyle.dragging then
      update()
    else
      self:Hide()
    end
  end)
  slider._gseSliderDragDriver = dragDriver

  slider:HookScript("OnMouseDown", function(self)
    if self:IsEnabled() and self._gseSliderStyle then
      self._gseSliderStyle.dragging = true
      if self._gseSliderDragDriver then self._gseSliderDragDriver:Show() end
      update()
    end
  end)
  slider:HookScript("OnMouseUp", function(self)
    if self._gseSliderStyle then
      self._gseSliderStyle.dragging = false
      if self._gseSliderDragDriver then self._gseSliderDragDriver:Hide() end
      update()
    end
  end)
  slider:HookScript("OnHide", function(self)
    if self._gseSliderStyle then
      self._gseSliderStyle.dragging = false
    end
    if self._gseSliderDragDriver then self._gseSliderDragDriver:Hide() end
  end)
  slider:HookScript("OnValueChanged", function()
    update()
    if slider._gseSliderStyle and slider._gseSliderStyle.dragging and slider._gseSliderDragDriver then
      slider._gseSliderDragDriver:Show()
    end
  end)
  slider:HookScript("OnShow", update)
  slider:HookScript("OnSizeChanged", update)
  slider:HookScript("OnEnter", update)
  slider:HookScript("OnLeave", update)
  slider:HookScript("OnEnable", update)
  slider:HookScript("OnDisable", update)

  if low then low:Hide() end
  if high then high:Hide() end
  update()
end

function optionsModule.StyleScrollBar(scrollBar)
  if not scrollBar or scrollBar._gseScrollBarStyled then return end
  scrollBar._gseScrollBarStyled = true
  -- Native skin: leave Blizzard's default scrollbar.
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then return end

  HideTextureRegionsRecursive(scrollBar)

  local up = scrollBar.ScrollUpButton
  local down = scrollBar.ScrollDownButton
  for _, button in ipairs({ up, down }) do
    if button then
      HideTextureRegionsRecursive(button)
      button:SetAlpha(0)
      button:SetSize(10, 10)
    end
  end

  local track = scrollBar:CreateTexture(nil, "BACKGROUND")
  track:SetTexture(WHITE8X8)
  track:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 4, -10)
  track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", -4, 10)
  track:SetVertexColor(BG_INPUT[1], BG_INPUT[2], BG_INPUT[3], 0)

  local inner = scrollBar:CreateTexture(nil, "BORDER")
  inner:SetTexture(WHITE8X8)
  inner:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -1, 1)
  inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0)

  scrollBar:SetThumbTexture(WHITE8X8)
  local thumb = scrollBar.GetThumbTexture and scrollBar:GetThumbTexture() or nil
  if thumb then
    thumb:SetSize(6, 28)
    thumb:SetVertexColor(SCROLL_THUMB[1], SCROLL_THUMB[2], SCROLL_THUMB[3], 1)
  end
  scrollBar:HookScript("OnEnter", function(self)
    local currentThumb = self.GetThumbTexture and self:GetThumbTexture() or nil
    if currentThumb then
      currentThumb:SetVertexColor(SCROLL_THUMB_HOVER[1], SCROLL_THUMB_HOVER[2], SCROLL_THUMB_HOVER[3], 1)
    end
  end)
  scrollBar:HookScript("OnLeave", function(self)
    local currentThumb = self.GetThumbTexture and self:GetThumbTexture() or nil
    if currentThumb then
      currentThumb:SetVertexColor(SCROLL_THUMB[1], SCROLL_THUMB[2], SCROLL_THUMB[3], 1)
    end
  end)
end

function optionsModule.SafeAPI.CreateFrame(frameType, name, parent, template)
  local ok, frame = pcall(API.CreateFrame, frameType, name, parent, template)
  if ok then
    return frame
  end
end

function optionsModule.CreateDropdownLabel(dd)
  local label = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", dd, "LEFT", 12, 0)
  label:SetPoint("RIGHT", dd, "RIGHT", -28, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  label:SetTextColor(0.92, 0.92, 0.98)
  dd._gseText = label
  return label
end

function optionsModule.CreateDropdown(parent, name, width)
  local effectiveWidth = math.max(width or optionsModule.CONTROL_TOTAL_W, 140)
  local holder = API.CreateFrame("Frame", nil, parent)
  holder._gseControlWidth = effectiveWidth
  holder:SetSize(effectiveWidth, 20)
  if holder.SetClipsChildren then holder:SetClipsChildren(false) end
  holder.rowHeight = optionsModule.ROW_H
  holder.alignLabelOffsetY = 0

  local dd = API.CreateFrame("Frame", name, holder, "UIDropDownMenuTemplate")
  dd._gseModern = false
  if dd.SetClipsChildren then dd:SetClipsChildren(false) end
  dd:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  UIDropDownMenu_SetWidth(dd, math.max(effectiveWidth - 34, 80))
  UIDropDownMenu_JustifyText(dd, "LEFT")

  local left = _G[name .. "Left"]
  local middle = _G[name .. "Middle"]
  local right = _G[name .. "Right"]
  local button = _G[name .. "Button"]
  if left then left:SetAlpha(1) end
  if middle then middle:SetAlpha(1) end
  if right then right:SetAlpha(1) end
  if button then
    local normal = button:GetNormalTexture()
    local pushed = button:GetPushedTexture()
    local highlight = button:GetHighlightTexture()
    if normal then normal:SetAlpha(1) end
    if pushed then pushed:SetAlpha(1) end
    if highlight then highlight:SetAlpha(1) end
  end

  local txt = _G[name .. "Text"]
  if txt then
    txt:ClearAllPoints()
    txt:SetPoint("LEFT", holder, "LEFT", 12, 0)
    txt:SetPoint("RIGHT", holder, "RIGHT", -30, 0)
    txt:SetJustifyH("LEFT")
    txt:SetWordWrap(false)
    txt:SetTextColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3], 1)
  end
  optionsModule.EnsureMidnightDropdownLists()
  optionsModule.StyleDropdown(dd, holder)
  return holder, dd
end

function optionsModule.CreateSlider(parent, name, minV, maxV, step, width)
  local holder = API.CreateFrame("Frame", nil, parent)
  local requestedSliderW = width or optionsModule.CONTROL_TRACK_W
  local alignedTotalW = math.max(optionsModule.CONTROL_TOTAL_W or 0, 140)
  local stepButtonW = 20
  local minimumTotalW = (optionsModule.SLIDER_BOX_GAP * 3) + optionsModule.SLIDER_EDIT_W + (stepButtonW * 2) + 80
  local totalW = math.max(alignedTotalW, minimumTotalW)
  local maxAlignedSliderW = math.max(totalW - (optionsModule.SLIDER_BOX_GAP * 3) - optionsModule.SLIDER_EDIT_W - (stepButtonW * 2), 80)
  local sliderW = maxAlignedSliderW
  if requestedSliderW and requestedSliderW > 0 then
    sliderW = math.min(requestedSliderW, maxAlignedSliderW)
  end
  holder._gseControlWidth = totalW
  holder:SetSize(totalW, 28)
  holder.rowHeight = 28
  holder.alignLabelOffsetY = 0

  local slider = optionsModule.SafeAPI.CreateFrame("Slider", name, holder, "MinimalSliderTemplate")
  if slider then
    slider._gseModern = true
  else
    slider = API.CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    slider._gseModern = false
  end

  slider:ClearAllPoints()
  slider:SetPoint("LEFT", holder, "LEFT", stepButtonW + optionsModule.SLIDER_BOX_GAP, 0)
  slider:SetWidth(sliderW)
  slider:SetHeight(slider._gseModern and 14 or 18)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(minV, maxV)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)

  local thumb = slider:GetThumbTexture()
  if thumb and not slider._gseModern then thumb:SetSize(16, 24) end

  local label = _G[name .. "Text"] or slider:CreateFontString(name .. "Text", "ARTWORK", "GameFontNormal")
  label:SetText("")
  label:Hide()

  local low = _G[name .. "Low"] or slider:CreateFontString(name .. "Low", "ARTWORK", "GameFontHighlightSmall")
  low:SetText(tostring(minV))
  low:Hide()

  local high = _G[name .. "High"] or slider:CreateFontString(name .. "High", "ARTWORK", "GameFontHighlightSmall")
  high:SetText(tostring(maxV))
  high:Hide()

  _G[name .. "Text"] = label
  _G[name .. "Low"] = low
  _G[name .. "High"] = high

  local minusBtn = API.CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
  minusBtn:SetSize(stepButtonW, 20)
  minusBtn:SetPoint("LEFT", holder, "LEFT", 0, 0)
  minusBtn:SetText("-")
  optionsModule.StyleActionButton(minusBtn)

  local box = API.CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
  box:SetAutoFocus(false)
  box:SetSize(optionsModule.SLIDER_EDIT_W, 20)
  box:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
  box:SetJustifyH("CENTER")
  box:SetFont(STANDARD_TEXT_FONT, 12, "")
  box:SetTextInsets(0, 0, 0, 0)
  box:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
    self:SetCursorPosition(0)
  end)

  local plusBtn = API.CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
  plusBtn:SetSize(stepButtonW, 20)
  plusBtn:SetPoint("RIGHT", box, "LEFT", -optionsModule.SLIDER_BOX_GAP, 0)
  plusBtn:SetText("+")
  optionsModule.StyleActionButton(plusBtn)

  slider.inputBox = box
  slider.minusButton = minusBtn
  slider.plusButton = plusBtn
  optionsModule.StyleSlider(slider)
  optionsModule.StyleEditBox(box)
  minusBtn:SetScript("OnClick", function()
    if slider:IsEnabled() then
      local current = slider:GetValue() or minV
      slider:SetValue((current or 0) - (step or 1))
    end
  end)
  plusBtn:SetScript("OnClick", function()
    if slider:IsEnabled() then
      local current = slider:GetValue() or minV
      slider:SetValue((current or 0) + (step or 1))
    end
  end)
  slider:SetValue(minV)
  return holder, slider
end

function optionsModule.SetSliderBoxValue(slider, value)
  if not (slider and slider.inputBox) then return end
  local text = tostring(value)
  if slider.inputBox:GetText() ~= text then
    slider.inputBox._gseInternalSet = true
    slider.inputBox:SetText(text)
    slider.inputBox._gseInternalSet = nil
  end
end

function optionsModule.BindNumericSliderBox(slider, getter, setter, minV, maxV)
  if not (slider and slider.inputBox) then return end
  local function apply(self)
    if self._gseInternalSet then return end
    local num = tonumber(self:GetText())
    if not num then
      local fallback = getter()
      optionsModule.SetSliderBoxValue(slider, math.floor((fallback or 0) + 0.5))
      self:ClearFocus()
      return
    end
    num = optionsModule.Clamp(math.floor(num + 0.5), minV, maxV)
    slider._gseApplyingFromInput = true
    slider:SetValue(num)
    slider._gseApplyingFromInput = nil
    setter(num)
    self:ClearFocus()
  end
  slider.inputBox:SetScript("OnEnterPressed", apply)
  slider.inputBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    optionsModule.SetSliderBoxValue(slider, math.floor((getter() or 0) + 0.5))
  end)
  slider.inputBox:SetScript("OnEditFocusLost", apply)
end

function optionsModule.BindOffsetSlider(slider, getter, setter, minV, maxV, opts)
  if not slider then return end
  opts = opts or {}
  local isBlocked = opts.isBlocked
  local isEnabled = opts.isEnabled
  local onApply = opts.onApply

  slider:SetScript("OnValueChanged", function(_, v)
    if slider._gseApplyingFromInput or (opts.isRefreshing and opts.isRefreshing()) or (isBlocked and isBlocked()) or (isEnabled and not isEnabled()) then return end
    local value = optionsModule.Clamp(math.floor((tonumber(v) or 0) + 0.5), minV, maxV)
    local current = getter()
    optionsModule.SetSliderBoxValue(slider, value)
    if current == value then return end
    if opts.ensureDB then opts.ensureDB() end
    setter(value)
    if onApply then onApply(value) end
  end)

  optionsModule.BindNumericSliderBox(slider,
    function()
      return getter()
    end,
    function(value)
      if (isBlocked and isBlocked()) or (isEnabled and not isEnabled()) then return end
      if opts.ensureDB then opts.ensureDB() end
      setter(value)
      if onApply then onApply(value) end
    end,
    minV, maxV)
end

function optionsModule.BindFloatSliderBox(slider, getter, setter, minV, maxV, decimals)
  if not (slider and slider.inputBox) then return end
  local fmt = "%0." .. tostring(decimals or 2) .. "f"
  local function writeBack()
    local current = tonumber(getter()) or 0
    local text = string.format(fmt, current)
    if slider.inputBox:GetText() ~= text then
      slider.inputBox._gseInternalSet = true
      slider.inputBox:SetText(text)
      slider.inputBox._gseInternalSet = nil
    end
  end
  local function apply(self)
    if self._gseInternalSet then return end
    local num = tonumber(self:GetText())
    if not num then
      writeBack()
      self:ClearFocus()
      return
    end
    num = optionsModule.Clamp(num, minV, maxV)
    slider._gseApplyingFromInput = true
    slider:SetValue(num)
    slider._gseApplyingFromInput = nil
    setter(num)
    self:ClearFocus()
    writeBack()
  end
  slider.inputBox:SetScript("OnEnterPressed", apply)
  slider.inputBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    writeBack()
  end)
  slider.inputBox:SetScript("OnEditFocusLost", apply)
  writeBack()
end

function optionsModule.SetDD(dd, value, text)
  if not dd then return end
  dd._gseSelectedValue = value
  dd._gseSelectedText = text
  if dd._gseModern then
    if dd._gseText then dd._gseText:SetText(text or "") end
    if dd.SetDefaultText then dd:SetDefaultText(text or "") end
    return
  end
  UIDropDownMenu_SetSelectedValue(dd, value)
  UIDropDownMenu_SetText(dd, text)
  if dd.Text then dd.Text:SetText(text or "") end
end

function optionsModule.InitSimpleDropdown(dd, options, getter, setter)
  if dd and dd._gseModern and MenuUtil and MenuUtil.CreateRadioMenu then
    local items, textByValue = {}, {}
    for _, opt in ipairs(options) do
      table.insert(items, { opt.text, opt.value })
      textByValue[opt.value] = opt.text
    end
    MenuUtil.CreateRadioMenu(dd,
      function(value)
        return getter() == value
      end,
      function(value)
        setter(value, textByValue[value] or tostring(value or ""))
      end,
      unpack(items))
    local cur = getter()
    optionsModule.SetDD(dd, cur, textByValue[cur] or tostring(cur or ""))
    return
  end

  local function initialize(_, level)
    if level and level ~= 1 then return end
    local current = getter()
    for _, opt in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.text
      info.value = opt.value
      info.checked = (current == opt.value)
      info.func = function() setter(opt.value, opt.text) end
      UIDropDownMenu_AddButton(info, level)
    end
  end

  dd._gseRefreshMenu = function()
    UIDropDownMenu_Initialize(dd, initialize)
  end
  dd._gseRefreshMenu()

  local cur = getter()
  local shown = nil
  for _, opt in ipairs(options) do
    if opt.value == cur then shown = opt.text break end
  end
  optionsModule.SetDD(dd, cur, shown or tostring(cur or ""))
end

function optionsModule.InitFontDropdown(dd, fontNames, getter, setter)
  if not dd then return end

  dd._gseFontDropdownConfig = {
    fontNames = fontNames,
    getter = getter,
    setter = setter,
  }

  local function resolveFontNames()
    local cfg = dd._gseFontDropdownConfig or {}
    local source = cfg.fontNames
    if type(source) == "function" then
      source = source()
    end

    local names = {}
    local seen = {}
    if type(source) == "table" then
      for _, fontName in ipairs(source) do
        if type(fontName) == "string" and fontName ~= "" and not seen[fontName] then
          seen[fontName] = true
          table.insert(names, fontName)
        end
      end
    end

    local current = cfg.getter and cfg.getter() or nil
    if type(current) == "string" and current ~= "" and not seen[current] then
      seen[current] = true
      table.insert(names, current)
    end

    if #names == 0 then
      for _, fontName in ipairs({
        (addon and addon.DEFAULT_SEQ_FONT) or "Friz Quadrata TT",
        "Arial Narrow",
        "Morpheus",
        "Skurri",
      }) do
        if not seen[fontName] then
          seen[fontName] = true
          table.insert(names, fontName)
        end
      end
    end

    table.sort(names)
    return names
  end

  dd._gseRefreshMenu = function()
    local cfg = dd._gseFontDropdownConfig or {}
    local currentGetter = cfg.getter
    local currentSetter = cfg.setter
    local names = resolveFontNames()

    if dd._gseModern and MenuUtil and MenuUtil.CreateRadioMenu then
      local items = {}
      for _, fontName in ipairs(names) do
        table.insert(items, { fontName, fontName })
      end
      MenuUtil.CreateRadioMenu(dd,
        function(value)
          return currentGetter() == value
        end,
        function(value)
          currentSetter(value)
        end,
        unpack(items))
    else
      local function initialize(_, level)
        if level and level ~= 1 then return end
        local current = currentGetter()
        for _, fontName in ipairs(names) do
          local info = UIDropDownMenu_CreateInfo()
          info.text = fontName
          info.value = fontName
          info.checked = (current == fontName)
          info.func = function() currentSetter(fontName) end
          UIDropDownMenu_AddButton(info, level)
        end
      end

      UIDropDownMenu_Initialize(dd, initialize)
    end

    local current = currentGetter and currentGetter() or nil
    optionsModule.SetDD(dd, current, current)
  end

  dd._gseRefreshMenu()
end

function optionsModule.CreateColorSwatch(parent, width, height)
  local size = math.max(math.min(height or width or 18, 22), 16)
  local button = API.CreateFrame("Button", nil, parent)
  button:SetSize(size, size)
  button.rowHeight = optionsModule.ROW_H

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE8X8)
  bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  bg:SetVertexColor(BG_INPUT[1], BG_INPUT[2], BG_INPUT[3], 1)

  local inner = button:CreateTexture(nil, "BORDER")
  inner:SetTexture(WHITE8X8)
  inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  inner:SetVertexColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 1)

  local borderTop = CreateEdgeTexture(button, "ARTWORK")
  borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
  borderTop:SetHeight(1)
  local borderBottom = CreateEdgeTexture(button, "ARTWORK")
  borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  borderBottom:SetHeight(1)
  local borderLeft = CreateEdgeTexture(button, "ARTWORK")
  borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  borderLeft:SetWidth(1)
  local borderRight = CreateEdgeTexture(button, "ARTWORK")
  borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
  borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  borderRight:SetWidth(1)

  local chip = button:CreateTexture(nil, "OVERLAY")
  chip:SetTexture(WHITE8X8)
  chip:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
  chip:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
  chip:SetVertexColor(1, 1, 1, 1)
  button._gseColorChip = chip
  button._gseColorBorder = {
    borderTop,
    borderBottom,
    borderLeft,
    borderRight,
  }

  local function UpdateColorSwatchVisual(hovered)
    local borderColor = hovered and BORDER_HOVER or BORDER_INPUT
    for _, tex in ipairs(button._gseColorBorder or {}) do
      tex:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], 1)
    end
  end

  button:HookScript("OnEnter", function()
    UpdateColorSwatchVisual(true)
  end)
  button:HookScript("OnLeave", function()
    UpdateColorSwatchVisual(false)
  end)
  UpdateColorSwatchVisual(false)

  function button:SetSwatchColor(r, g, b)
    local color = self._gseStoredColor
    if not color then
      color = { 1, 1, 1 }
      self._gseStoredColor = color
    end
    color[1], color[2], color[3] = r or 1, g or 1, b or 1
    if self._gseColorChip then
      self._gseColorChip:SetVertexColor(color[1], color[2], color[3], 1)
    end
  end

  return button
end

-- Native section: a stock Blizzard inset panel with a plain header label.
function optionsModule.CreateNativeSection(parent, title)
  local box = API.CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  box:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
  box:SetBackdropBorderColor(0.50, 0.45, 0.35, 1)

  local header = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
  header:SetJustifyH("LEFT")
  header:SetText(title)
  box.header = header

  box.rows = {}
  return box
end

function optionsModule.CreateSection(parent, title)
  if optionsModule.IsNativeSkin and optionsModule.IsNativeSkin() then
    return optionsModule.CreateNativeSection(parent, title)
  end

  local box = optionsModule.CreateBackdrop(parent, 0.92, 1)
  local classR, classG, classB = optionsModule.GetClassColor()

  box:SetBackdropColor(BG_MEDIUM[1], BG_MEDIUM[2], BG_MEDIUM[3], 0.98)
  box:SetBackdropBorderColor(BORDER_DEFAULT[1], BORDER_DEFAULT[2], BORDER_DEFAULT[3], 1)

  local headerBar = box:CreateTexture(nil, "BORDER")
  headerBar:SetTexture(WHITE8X8)
  headerBar:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
  headerBar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
  headerBar:SetHeight(32)
  headerBar:SetVertexColor(BG_LIGHT[1], BG_LIGHT[2], BG_LIGHT[3], 0.92)
  box.headerBar = headerBar

  local headerTint = box:CreateTexture(nil, "ARTWORK")
  headerTint:SetTexture(WHITE8X8)
  headerTint:SetPoint("TOPLEFT", headerBar, "TOPLEFT", 0, 0)
  headerTint:SetPoint("BOTTOMRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
  headerTint:SetVertexColor(classR, classG, classB, 0.12)
  box.headerTint = headerTint

  local header = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("LEFT", headerBar, "LEFT", 14, 0)
  header:SetJustifyH("LEFT")
  header:SetText(title)
  header:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3], 1)
  box.header = header

  local line = box:CreateTexture(nil, "BORDER")
  line:SetColorTexture(1, 1, 1, 0.03)
  line:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -33)
  line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -33)
  line:SetHeight(1)
  box.line = line

  box.rows = {}
  return box
end

local FIELD_COLUMN_GAP = 18
local FIELD_CONTROL_GAP = 12
local FIELD_RIGHT_INSET = 0
local FIELD_MIN_LABEL_W = 40

local function GetFieldMetrics(totalWidth, columnIndex, columnCount, gap)
  gap = gap or FIELD_COLUMN_GAP
  columnCount = math.max(columnCount or 1, 1)
  local totalGap = gap * math.max(columnCount - 1, 0)
  local fieldWidth = math.max((totalWidth - totalGap) / columnCount, 0)
  local fieldLeft = ((columnIndex or 1) - 1) * (fieldWidth + gap)
  return fieldLeft, fieldWidth
end

local function LayoutField(row, label, control, fieldLeft, fieldWidth, opts)
  if not (row and label and control) then return end
  opts = opts or {}

  local labelOffsetX = opts.labelOffsetX or (control.alignLabelOffsetX or 0)
  local labelOffsetY = opts.labelOffsetY or (control.alignLabelOffsetY or 0)
  local controlOffsetX = opts.controlOffsetX or (control.alignColumnOffsetX or 0)
  local controlOffsetY = opts.controlOffsetY or (control.alignControlOffsetY or 0)
  local rightInset = opts.rightInset or FIELD_RIGHT_INSET
  local gap = opts.gap or FIELD_CONTROL_GAP
  local minLabelWidth = opts.minLabelWidth or FIELD_MIN_LABEL_W
  local controlWidth = (control.GetWidth and control:GetWidth()) or 0

  label:ClearAllPoints()
  label:SetPoint("LEFT", row, "LEFT", fieldLeft + labelOffsetX, labelOffsetY)
  label:SetWidth(math.max(fieldWidth - controlWidth - gap - rightInset - labelOffsetX, minLabelWidth))

  control:ClearAllPoints()
  control:SetPoint("RIGHT", row, "LEFT", fieldLeft + fieldWidth - rightInset + controlOffsetX, controlOffsetY)
end

function optionsModule.AddRow(container, labelText, controlFrame, rowHeight, opts)
  opts = opts or {}

  local row = API.CreateFrame("Frame", nil, container)
  local resolvedRowHeight = rowHeight or controlFrame.rowHeight or optionsModule.ROW_H
  row:SetHeight(resolvedRowHeight)

  local label = optionsModule.CreateLabel(row, labelText)
  row.label = label

  controlFrame:SetParent(row)
  row.control = controlFrame

  row:SetScript("OnSizeChanged", function(self, w)
    LayoutField(self, self.label, self.control, 0, w, opts)
  end)

  table.insert(container.rows, row)
  return row
end

function optionsModule.AddDualSliderRow(container, leftTitle, leftControl, rightTitle, rightControl, rowHeight)
  local row = API.CreateFrame("Frame", nil, container)
  row:SetHeight(rowHeight or ((math.max(leftControl.rowHeight or 0, rightControl.rowHeight or 0) > 0) and ((math.max(leftControl.rowHeight or 0, rightControl.rowHeight or 0)) + 10) or 52))

  row.leftLabel = optionsModule.CreateLabel(row, leftTitle)
  row.rightLabel = optionsModule.CreateLabel(row, rightTitle)
  row.leftControl = leftControl
  row.rightControl = rightControl

  leftControl:SetParent(row)
  rightControl:SetParent(row)

  row:SetScript("OnSizeChanged", function(self, w)
    local leftX, fieldWidth = GetFieldMetrics(w, 1, 2)
    local rightX = select(1, GetFieldMetrics(w, 2, 2))
    LayoutField(self, self.leftLabel, self.leftControl, leftX, fieldWidth)
    LayoutField(self, self.rightLabel, self.rightControl, rightX, fieldWidth)
  end)

  table.insert(container.rows, row)
  return row
end

function optionsModule.AddInlineCheckRow(container, title, control, rowHeight)
  local row = API.CreateFrame("Frame", nil, container)
  row:SetHeight(rowHeight or optionsModule.ROW_H)
  control.alignLabelOffsetY = 0

  row.label = optionsModule.CreateLabel(row, title)
  row.control = control

  control:SetParent(row)

  row:SetScript("OnSizeChanged", function(self, w)
    LayoutField(self, self.label, self.control, 0, w)
  end)

  table.insert(container.rows, row)
  return row
end

function optionsModule.AddDualCheckRow(container, leftTitle, leftControl, rightTitle, rightControl, rowHeight)
  local row = API.CreateFrame("Frame", nil, container)
  row:SetHeight(rowHeight or optionsModule.ROW_H)
  leftControl.alignLabelOffsetY = 0
  rightControl.alignLabelOffsetY = 0

  row.leftLabel = optionsModule.CreateLabel(row, leftTitle)
  row.rightLabel = optionsModule.CreateLabel(row, rightTitle)
  row.leftControl = leftControl
  row.rightControl = rightControl

  leftControl:SetParent(row)
  rightControl:SetParent(row)

  row:SetScript("OnSizeChanged", function(self, w)
    local leftX, fieldWidth = GetFieldMetrics(w, 1, 2)
    local rightX = select(1, GetFieldMetrics(w, 2, 2))
    LayoutField(self, self.leftLabel, self.leftControl, leftX, fieldWidth)
    LayoutField(self, self.rightLabel, self.rightControl, rightX, fieldWidth)
  end)

  table.insert(container.rows, row)
  return row
end


function optionsModule.AddColorCheckRow(container, leftTitle, buttonControl, checkTitle, checkControl, rowHeight)
  local row = API.CreateFrame("Frame", nil, container)
  row:SetHeight(rowHeight or optionsModule.ROW_H)

  row.leftLabel = optionsModule.CreateLabel(row, leftTitle)
  row.checkLabel = optionsModule.CreateLabel(row, checkTitle)
  row.buttonControl = buttonControl
  row.checkControl = checkControl

  buttonControl:SetParent(row)
  checkControl:SetParent(row)
  row.checkLabel:SetJustifyH("RIGHT")

  row:SetScript("OnSizeChanged", function(self, w)
    local controlAreaWidth = math.min(optionsModule.CONTROL_TOTAL_W or w, w)
    local controlStartX = math.max(w - controlAreaWidth, 0)
    local controlGap = FIELD_CONTROL_GAP
    local swatchWidth = (self.buttonControl.GetWidth and self.buttonControl:GetWidth()) or 0
    local toggleWidth = (self.checkControl.GetWidth and self.checkControl:GetWidth()) or 0
    local rightEdge = w - FIELD_RIGHT_INSET + (self.checkControl.alignColumnOffsetX or 0)
    local toggleLeft = rightEdge - toggleWidth
    local labelLeft = controlStartX + swatchWidth + controlGap
    local labelRight = toggleLeft - controlGap

    self.leftLabel:ClearAllPoints()
    self.leftLabel:SetPoint("LEFT", self, "LEFT", self.buttonControl.alignLabelOffsetX or 0, self.buttonControl.alignLabelOffsetY or 0)
    self.leftLabel:SetWidth(math.max(controlStartX - controlGap, FIELD_MIN_LABEL_W))

    self.buttonControl:ClearAllPoints()
    self.buttonControl:SetPoint("LEFT", self, "LEFT", controlStartX + (self.buttonControl.alignColumnOffsetX or 0), self.buttonControl.alignControlOffsetY or 0)

    self.checkControl:ClearAllPoints()
    self.checkControl:SetPoint("RIGHT", self, "LEFT", rightEdge, self.checkControl.alignControlOffsetY or 0)

    self.checkLabel:ClearAllPoints()
    self.checkLabel:SetPoint("LEFT", self, "LEFT", labelLeft + (self.checkControl.alignLabelOffsetX or 0), self.checkControl.alignLabelOffsetY or 0)
    self.checkLabel:SetWidth(math.max(labelRight - labelLeft, 72))
  end)

  table.insert(container.rows, row)
  return row
end

function optionsModule.AddTripleCheckRow(container, firstTitle, firstControl, secondTitle, secondControl, thirdTitle, thirdControl, rowHeight)
  local row = API.CreateFrame("Frame", nil, container)
  row:SetHeight(rowHeight or optionsModule.ROW_H)

  firstControl.alignLabelOffsetY = 0
  secondControl.alignLabelOffsetY = 0
  thirdControl.alignLabelOffsetY = 0

  row.firstLabel = optionsModule.CreateLabel(row, firstTitle)
  row.secondLabel = optionsModule.CreateLabel(row, secondTitle)
  row.thirdLabel = optionsModule.CreateLabel(row, thirdTitle)
  row.firstControl = firstControl
  row.secondControl = secondControl
  row.thirdControl = thirdControl

  firstControl:SetParent(row)
  secondControl:SetParent(row)
  thirdControl:SetParent(row)

  row:SetScript("OnSizeChanged", function(self, w)
    local columnCount = 3
    local columnGap = FIELD_COLUMN_GAP + (self.alignColumnGapAdjust or 0)
    local controls = { self.firstControl, self.secondControl, self.thirdControl }
    local labels = { self.firstLabel, self.secondLabel, self.thirdLabel }

    for index = 1, columnCount do
      local control = controls[index]
      local label = labels[index]
      local fieldLeft, fieldWidth = GetFieldMetrics(w, index, columnCount, columnGap)
      LayoutField(self, label, control, fieldLeft, fieldWidth)
    end
  end)

  table.insert(container.rows, row)
  return row
end

function optionsModule.LayoutRows(container, startY)
  local y = startY or optionsModule.SECTION_START_Y
  local insetX = optionsModule.SECTION_INSET_X or 14
  for _, row in ipairs(container.rows) do
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", container, "TOPLEFT", insetX, y)
    row:SetPoint("TOPRIGHT", container, "TOPRIGHT", -insetX, y)
    y = y - row:GetHeight() - optionsModule.ROW_GAP
  end
end
