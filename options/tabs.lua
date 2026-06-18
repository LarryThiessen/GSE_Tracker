local _, ns = ...
local API = (ns.Utils and ns.Utils.API) or {}
local Options = ns.Options
local optionsModule = Options
local WHITE8X8 = (ns.Utils and ns.Utils.Constants and ns.Utils.Constants.TEXTURE_WHITE8X8) or "Interface/Buttons/WHITE8x8"

local TAB_HEIGHT = optionsModule.TAB_HEIGHT or 34
local TAB_GAP = optionsModule.TAB_GAP or 2

-- Pull an RGB colour from the active skin palette (falls back to black). Tab
-- alphas are kept as-is below; only the RGB is skin-driven.
local function pc(key)
  local p = optionsModule.Palette
  return (p and p[key]) or { 0, 0, 0 }
end

local function SetTabVisual(button, selected)
  if not button then return end
  local r, g, b = optionsModule.GetClassColor()

  if button._gseBg then
    local c = selected and pc("BG_MEDIUM") or pc("BG_DARK")
    button._gseBg:SetVertexColor(c[1], c[2], c[3], selected and 0.98 or 0.94)
  end

  if button._gseInner then
    local c = selected and pc("BG_LIGHT") or pc("BG_INPUT")
    button._gseInner:SetVertexColor(c[1], c[2], c[3], selected and 0.05 or 0.03)
  end

  if button._gseGlow then
    button._gseGlow:SetVertexColor(r, g, b, selected and 0.03 or 0)
  end

  if button._gseAccent then
    button._gseAccent:SetVertexColor(r, g, b, selected and 0.92 or 0)
  end

  if button._gseLabel then
    local c = selected and pc("TEXT_PRIMARY") or pc("TEXT_MUTED")
    button._gseLabel:SetTextColor(c[1], c[2], c[3])
  end

  if button._gseSubtitle then
    button._gseSubtitle:SetShown(false)
  end

  if button._gsePill then
    button._gsePill:SetShown(false)
  end

  if button._gseBorder then
    for _, tex in ipairs(button._gseBorder) do
      if selected then
        tex:SetVertexColor(r, g, b, 0.42)
      else
        local c = pc("BORDER_DEFAULT")
        tex:SetVertexColor(c[1], c[2], c[3], 1)
      end
    end
  end
end

function optionsModule.CreateTopTab(parent, key, text, subtitle)
  local button = API.CreateFrame("Button", nil, parent)
  button:SetHeight(TAB_HEIGHT)
  button.tabKey = key

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE8X8)
  bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  button._gseBg = bg

  local inner = button:CreateTexture(nil, "BORDER")
  inner:SetTexture(WHITE8X8)
  inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  button._gseInner = inner

  local glow = button:CreateTexture(nil, "BORDER")
  glow:SetTexture(WHITE8X8)
  glow:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  button._gseGlow = glow

  local accent = button:CreateTexture(nil, "ARTWORK")
  accent:SetTexture(WHITE8X8)
  accent:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  accent:SetWidth(3)
  button._gseAccent = accent

  local pill = button:CreateTexture(nil, "ARTWORK")
  pill:SetTexture(WHITE8X8)
  pill:SetPoint("TOPRIGHT", button, "TOPRIGHT", -12, -10)
  pill:SetSize(6, 6)
  button._gsePill = pill

  local borderTop = button:CreateTexture(nil, "ARTWORK")
  borderTop:SetTexture(WHITE8X8)
  borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
  borderTop:SetHeight(1)
  local borderBottom = button:CreateTexture(nil, "ARTWORK")
  borderBottom:SetTexture(WHITE8X8)
  borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  borderBottom:SetHeight(1)
  local borderLeft = button:CreateTexture(nil, "ARTWORK")
  borderLeft:SetTexture(WHITE8X8)
  borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  borderLeft:SetWidth(1)
  local borderRight = button:CreateTexture(nil, "ARTWORK")
  borderRight:SetTexture(WHITE8X8)
  borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
  borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  borderRight:SetWidth(1)
  button._gseBorder = { borderTop, borderBottom, borderLeft, borderRight }

  local label = button:CreateFontString(nil, "ARTWORK")
  label:SetFont(STANDARD_TEXT_FONT, 11, "")
  label:SetShadowOffset(1, -1)
  label:SetShadowColor(0, 0, 0, 0.85)
  label:SetPoint("LEFT", button, "LEFT", 14, 0)
  label:SetPoint("RIGHT", button, "RIGHT", -12, 0)
  label:SetJustifyH("CENTER")
  label:SetJustifyV("MIDDLE")
  label:SetWordWrap(false)
  label:SetText(text)
  button._gseLabel = label

  local subtitleText = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitleText:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
  subtitleText:SetPoint("RIGHT", button, "RIGHT", -18, 0)
  subtitleText:SetJustifyH("LEFT")
  subtitleText:SetText(subtitle or "")
  button._gseSubtitle = subtitleText
  subtitleText:Hide()

  button:HookScript("OnEnter", function(self)
    if self._gseSelected then return end
    local r, g, b = optionsModule.GetClassColor()
    if self._gseBg then local c = pc("BG_LIGHT") self._gseBg:SetVertexColor(c[1], c[2], c[3], 0.98) end
    if self._gseInner then local c = pc("BG_HOVER") self._gseInner:SetVertexColor(c[1], c[2], c[3], 0.05) end
    if self._gseGlow then self._gseGlow:SetVertexColor(r, g, b, 0.02) end
    if self._gseLabel then local c = pc("TEXT_SECONDARY") self._gseLabel:SetTextColor(c[1], c[2], c[3]) end
    if self._gseAccent then self._gseAccent:SetVertexColor(optionsModule.GetClassColor()) end
    if self._gseAccent then self._gseAccent:SetAlpha(0.42) end
    if self._gseBorder then
      for _, tex in ipairs(self._gseBorder) do
        tex:SetVertexColor(r, g, b, 0.24)
      end
    end
  end)
  button:HookScript("OnLeave", function(self)
    SetTabVisual(self, self._gseSelected == true)
  end)

  SetTabVisual(button, false)
  return button
end

function optionsModule.ApplyTopTabSelection(frame, selectedKey)
  if not (frame and frame.topTabs) then return end
  frame.selectedTopTab = selectedKey

  for key, button in pairs(frame.topTabs) do
    local isSelected = key == selectedKey
    button._gseSelected = isSelected
    SetTabVisual(button, isSelected)
  end

  if frame.tabContents then
    for key, content in pairs(frame.tabContents) do
      if content then
        if key == selectedKey then
          content:Show()
        else
          content:Hide()
        end
      end
    end
  end
end

function optionsModule.BuildTopTabs(frame, parent, tabs, onSelected)
  frame.topTabs = frame.topTabs or {}

  local anchor = nil
  for index, tabInfo in ipairs(tabs) do
    local button = optionsModule.CreateTopTab(parent, tabInfo.key, tabInfo.text, tabInfo.subtitle)
    button:SetPoint("LEFT", parent, "LEFT", 0, 0)
    button:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if index == 1 then
      button:SetPoint("TOP", parent, "TOP", 0, 0)
    else
      button:SetPoint("TOP", anchor, "BOTTOM", 0, -TAB_GAP)
    end
    button:SetScript("OnClick", function()
      optionsModule.ApplyTopTabSelection(frame, tabInfo.key)
      if onSelected then onSelected(tabInfo.key) end
      if frame.Refresh then frame:Refresh() end
    end)
    frame.topTabs[tabInfo.key] = button
    anchor = button
  end
end
