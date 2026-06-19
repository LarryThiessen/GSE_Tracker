local _, ns = ...
local addon = ns
local API = (ns.Utils and ns.Utils.API) or {}
local UIParent = (API.UIParent and API.UIParent()) or UIParent
local IsMouseButtonDown = _G.IsMouseButtonDown
local ChatEdit_ChooseBoxForSend = _G.ChatEdit_ChooseBoxForSend
local ChatFrame1EditBox = _G.ChatFrame1EditBox
local ChatFrame_OpenChat = _G.ChatFrame_OpenChat
local ChatEdit_ActivateChat = _G.ChatEdit_ActivateChat
local DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME
local Options = ns.Options
local uiShared = addon._ui or {}
local Constants = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local optionsModule = Options
local WHITE8X8 = (Constants and Constants.TEXTURE_WHITE8X8) or "Interface/Buttons/WHITE8x8"

local MIN_W = optionsModule.MIN_W
local MIN_H = optionsModule.MIN_H
local DEFAULT_W = optionsModule.DEFAULT_W
local DEFAULT_H = optionsModule.DEFAULT_H
local SIDEBAR_W = optionsModule.SIDEBAR_W
local MAIN_PAD = optionsModule.MAIN_PAD
local HEADER_H = optionsModule.HEADER_H
local FOOTER_H = optionsModule.FOOTER_H
local CONTROL_TRACK_W = optionsModule.CONTROL_TRACK_W
local CONTROL_TOTAL_W = optionsModule.CONTROL_TOTAL_W
local ADDON_ICON = "Interface\\AddOns\\GSE_Tracker\\media\\GSE_Tracker.png"
local DISCORD_ICON = "Interface\\AddOns\\GSE_Tracker\\media\\Discord-Logo.png"
local PATREON_ICON = "Interface\\AddOns\\GSE_Tracker\\media\\patreon.png"
local KOFI_ICON = "Interface\\AddOns\\GSE_Tracker\\media\\kofi_s_logo_nolabel.png"

local ensureDatabase = optionsModule.EnsureDB
local clampValue = optionsModule.Clamp
local applyTargetedRefresh = optionsModule.ApplyTargetedRefresh
local resetSettingsWindowGeometry = optionsModule.ResetSettingsWindowGeometry
local styleWindowBorder = optionsModule.StyleWindowBorder
local createCheck = optionsModule.CreateCheck
local createDropdown = optionsModule.CreateDropdown
local createSlider = optionsModule.CreateSlider
local createColorSwatch = optionsModule.CreateColorSwatch
local setSliderBoxValue = optionsModule.SetSliderBoxValue
local bindNumericSliderBox = optionsModule.BindNumericSliderBox
local bindOffsetSlider = optionsModule.BindOffsetSlider
local bindFloatSliderBox = optionsModule.BindFloatSliderBox
local setDropdownValue = optionsModule.SetDD
local initSimpleDropdown = optionsModule.InitSimpleDropdown
local initFontDropdown = optionsModule.InitFontDropdown
local setDropdownEnabled = optionsModule.SetDropdownEnabled
local createBackdrop = optionsModule.CreateBackdrop
local createSection = optionsModule.CreateSection
local addRow = optionsModule.AddRow
local addColorCheckRow = optionsModule.AddColorCheckRow
local addInlineCheckRow = optionsModule.AddInlineCheckRow
local buildElementCard = optionsModule.BuildElementCard
local buildSettingsRefresh = optionsModule.BuildSettingsRefresh
local buildTopTabs = optionsModule.BuildTopTabs
local applyTopTabSelection = optionsModule.ApplyTopTabSelection

local function WireAssistedHighlightCallbacks(C, ctx, fontNames)

  C.frame.UpdateAssistedHighlightColorButton = function(_, r, g, b)
    if C.btnAssistedHighlightColor and C.btnAssistedHighlightColor.SetSwatchColor then
      C.btnAssistedHighlightColor:SetSwatchColor(r, g, b)
    end
  end

  local function ApplyAssistedHighlightColorChange(r, g, b)
    ctx.ensureDB()
    addon:SetAssistedHighlightColor(r, g, b)
    C.frame:UpdateAssistedHighlightColorButton(r, g, b)
    ctx.ApplyEffect("assistedHighlight", nil, "border")
  end

  local function OpenAssistedHighlightColorPicker()
    if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
    local r, g, b = addon:GetAssistedHighlightColor()
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local info = {
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function()
          local nr, ng, nb = ColorPickerFrame:GetColorRGB()
          ApplyAssistedHighlightColorChange(nr, ng, nb)
        end,
        cancelFunc = function(previousValues)
          if type(previousValues) == "table" then
            ApplyAssistedHighlightColorChange(previousValues.r or previousValues[1], previousValues.g or previousValues[2], previousValues.b or previousValues[3])
          end
        end,
      }
      ColorPickerFrame:SetupColorPickerAndShow(info)
      if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
      return
    end
    if not ColorPickerFrame then return end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      ApplyAssistedHighlightColorChange(nr, ng, nb)
    end
    ColorPickerFrame.cancelFunc = function(previousValues)
      if type(previousValues) == "table" then
        ApplyAssistedHighlightColorChange(previousValues.r or previousValues[1], previousValues.g or previousValues[2], previousValues.b or previousValues[3])
      end
    end
    ColorPickerFrame.opacityFunc = nil
    if ColorPickerFrame.SetColorRGB then ColorPickerFrame:SetColorRGB(r, g, b) end
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
  end

  C.cbAssistedHighlightLock:SetScript("OnClick", function()
    ctx.ensureDB()
    addon:SetAssistedHighlightLocked(C.cbAssistedHighlightLock:GetChecked())
    ctx.SetAH(addon:IsAssistedHighlightMirrorEnabled())
    ctx.ApplyEffect("assistedHighlight", nil, "layout")
  end)

  C.cbAssistedHighlightUseClassColor:SetScript("OnClick", function()
    ctx.ensureDB()
    addon:SetAssistedHighlightUseClassColor(C.cbAssistedHighlightUseClassColor:GetChecked())
    ctx.SetAH(addon:IsAssistedHighlightMirrorEnabled())
    ctx.ApplyEffect("assistedHighlight", nil, "border")
  end)

  C.btnAssistedHighlightColor:SetScript("OnClick", function()
    if not addon:IsAssistedHighlightMirrorEnabled() or addon:GetAssistedHighlightUseClassColor() then return end
    OpenAssistedHighlightColorPicker()
  end)

  -- Center Marker slider callbacks (wired here alongside AH due to file ordering)

  C.sCombatMarkerSize:SetScript("OnValueChanged", function(_, v)
    if C.sCombatMarkerSize._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsCombatMarkerEnabled() then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), 16, 128)
    ctx.setSlider(C.sCombatMarkerSize, value)
    if addon:GetCombatMarkerSize() == value then return end
    addon:SetCombatMarkerSize(value)
    ctx.ApplyEffect("centerMarker")
  end)
  ctx.bindNumeric(C.sCombatMarkerSize,
    function() return addon:GetCombatMarkerSize() end,
    function(value)
      ctx.ensureDB()
      addon:SetCombatMarkerSize(value)
      ctx.ApplyEffect("centerMarker")
    end,
    16, 128)

  C.sCombatMarkerAlpha:SetScript("OnValueChanged", function(_, v)
    local value = ctx.clamp(v, 0.05, 1.00)
    if C.sCombatMarkerAlpha.inputBox and not C.sCombatMarkerAlpha.inputBox:HasFocus() then
      C.sCombatMarkerAlpha.inputBox:SetText(string.format("%.2f", value))
    end
    if ctx.IsRefreshing() or not addon:IsCombatMarkerEnabled() then return end
    ctx.ensureDB()
    if addon:GetCombatMarkerAlpha() == value then return end
    addon:SetCombatMarkerAlpha(value)
    ctx.ApplyEffect("centerMarker")
  end)
  ctx.bindFloat(C.sCombatMarkerAlpha,
    function() return addon:GetCombatMarkerAlpha() end,
    function(value)
      ctx.ensureDB()
      addon:SetCombatMarkerAlpha(ctx.clamp(value, 0.05, 1.00))
      ctx.ApplyEffect("centerMarker")
    end,
    0.05, 1.00, 2)

  C.sCombatMarkerX:SetScript("OnValueChanged", function(_, v)
    if C.sCombatMarkerX._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsCombatMarkerEnabled() or (addon.GetCombatMarkerLocked and addon:GetCombatMarkerLocked()) then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), -3000, 3000)
    local _, y = addon:GetCombatMarkerOffset()
    ctx.setSlider(C.sCombatMarkerX, value)
    if value == (addon:GetCombatMarkerOffset()) then return end
    addon:SetCombatMarkerOffset(value, y)
    ctx.ApplyEffect("centerMarker")
  end)
  ctx.bindNumeric(C.sCombatMarkerX,
    function()
      local x = addon:GetCombatMarkerOffset()
      return x
    end,
    function(value)
      local _, y = addon:GetCombatMarkerOffset()
      addon:SetCombatMarkerOffset(value, y)
      ctx.ApplyEffect("centerMarker")
    end,
    -3000, 3000)

  C.sCombatMarkerY:SetScript("OnValueChanged", function(_, v)
    if C.sCombatMarkerY._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsCombatMarkerEnabled() or (addon.GetCombatMarkerLocked and addon:GetCombatMarkerLocked()) then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), -3000, 3000)
    local x, currentY = addon:GetCombatMarkerOffset()
    ctx.setSlider(C.sCombatMarkerY, value)
    if currentY == value then return end
    addon:SetCombatMarkerOffset(x, value)
    ctx.ApplyEffect("centerMarker")
  end)
  ctx.bindNumeric(C.sCombatMarkerY,
    function()
      local _, y = addon:GetCombatMarkerOffset()
      return y
    end,
    function(value)
      local x = addon:GetCombatMarkerOffset()
      addon:SetCombatMarkerOffset(x, value)
      ctx.ApplyEffect("centerMarker")
    end,
    -3000, 3000)

  C.sCombatMarkerThickness:SetScript("OnValueChanged", function(_, v)
    if C.sCombatMarkerThickness._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsCombatMarkerEnabled() then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), 1, 12)
    ctx.setSlider(C.sCombatMarkerThickness, value)
    if addon:GetCombatMarkerThickness() == value then return end
    addon:SetCombatMarkerThickness(value)
    ctx.ApplyEffect("centerMarker")
  end)
  ctx.bindNumeric(C.sCombatMarkerThickness,
    function() return addon:GetCombatMarkerThickness() end,
    function(value)
      ctx.ensureDB()
      addon:SetCombatMarkerThickness(value)
      ctx.ApplyEffect("centerMarker")
    end,
    1, 12)

  C.sCombatMarkerBorderSize:SetScript("OnValueChanged", function(_, v)
    if C.sCombatMarkerBorderSize._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsCombatMarkerEnabled() then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), 0, 8)
    ctx.setSlider(C.sCombatMarkerBorderSize, value)
    if C.cbCombatMarkerBorder then C.cbCombatMarkerBorder:SetChecked(value > 0) end
    if addon:GetCombatMarkerBorderSize() == value then return end
    addon:SetCombatMarkerBorderSize(value)
    ctx.ApplyEffect("centerMarker")
  end)
  ctx.bindNumeric(C.sCombatMarkerBorderSize,
    function() return addon:GetCombatMarkerBorderSize() end,
    function(value)
      ctx.ensureDB()
      addon:SetCombatMarkerBorderSize(value)
      if C.cbCombatMarkerBorder then C.cbCombatMarkerBorder:SetChecked(value > 0) end
      ctx.ApplyEffect("centerMarker")
    end,
    0, 8)

  C.cbAssistedHighlightEnabled:SetScript("OnClick", function()
    ctx.ensureDB()
    addon:SetAssistedHighlightMirrorEnabled(C.cbAssistedHighlightEnabled:GetChecked())
    ctx.SetAH(C.cbAssistedHighlightEnabled:GetChecked())
    ctx.ApplyEffect("assistedHighlight")
  end)

  C.cbAssistedHighlightKeybind:SetScript("OnClick", function()
    ctx.ensureDB()
    addon:SetAssistedHighlightShowKeybind(C.cbAssistedHighlightKeybind:GetChecked())
    ctx.ApplyEffect("assistedHighlight")
  end)

  C.cbAssistedHighlightBorder:SetScript("OnClick", function()
    ctx.ensureDB()
    local checked = C.cbAssistedHighlightBorder:GetChecked() and true or false
    local current = addon:GetAssistedHighlightBorderSize()
    local target = checked and math.max(current, 1) or 0
    if current == target then return end
    addon:SetAssistedHighlightBorderSize(target)
    if C.sAssistedHighlightBorder then
      C.sAssistedHighlightBorder:SetValue(target)
      ctx.setSlider(C.sAssistedHighlightBorder, target)
    end
    ctx.ApplyEffect("assistedHighlight", nil, "border")
  end)

  C.cbAssistedHighlightRangeChecker:SetScript("OnClick", function()
    ctx.ensureDB()
    addon:SetAssistedHighlightRangeCheckerEnabled(C.cbAssistedHighlightRangeChecker:GetChecked())
    ctx.ApplyEffect("assistedHighlight")
  end)

  C.sAssistedHighlightSize:SetScript("OnValueChanged", function(_, v)
    if C.sAssistedHighlightSize._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsAssistedHighlightMirrorEnabled() then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), 28, 96)
    ctx.setSlider(C.sAssistedHighlightSize, value)
    if addon:GetAssistedHighlightSize() == value then return end
    addon:SetAssistedHighlightSize(value)
    ctx.ApplyEffect("assistedHighlight", nil, "size")
  end)
  ctx.bindNumeric(C.sAssistedHighlightSize,
    function() return addon:GetAssistedHighlightSize() end,
    function(value)
      ctx.ensureDB()
      addon:SetAssistedHighlightSize(value)
      ctx.ApplyEffect("assistedHighlight", nil, "size")
    end,
    28, 96)

  C.sAssistedHighlightBorder:SetScript("OnValueChanged", function(_, v)
    if C.sAssistedHighlightBorder._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsAssistedHighlightMirrorEnabled() then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), 0, 12)
    ctx.setSlider(C.sAssistedHighlightBorder, value)
    if addon:GetAssistedHighlightBorderSize() == value then return end
    addon:SetAssistedHighlightBorderSize(value)
    if C.cbAssistedHighlightBorder then C.cbAssistedHighlightBorder:SetChecked(value > 0) end
    ctx.ApplyEffect("assistedHighlight", nil, "border")
  end)
  ctx.bindNumeric(C.sAssistedHighlightBorder,
    function() return addon:GetAssistedHighlightBorderSize() end,
    function(value)
      ctx.ensureDB()
      addon:SetAssistedHighlightBorderSize(value)
      if C.cbAssistedHighlightBorder then C.cbAssistedHighlightBorder:SetChecked(value > 0) end
      ctx.ApplyEffect("assistedHighlight", nil, "border")
    end,
    0, 12)

  C.sAssistedHighlightAlpha:SetScript("OnValueChanged", function(_, v)
    local value = ctx.clamp(v, 0.05, 1.00)
    if C.sAssistedHighlightAlpha.inputBox and not C.sAssistedHighlightAlpha.inputBox:HasFocus() then
      C.sAssistedHighlightAlpha.inputBox:SetText(string.format("%.2f", value))
    end
    if ctx.IsRefreshing() or not addon:IsAssistedHighlightMirrorEnabled() then return end
    ctx.ensureDB()
    if addon:GetAssistedHighlightAlpha() == value then return end
    addon:SetAssistedHighlightAlpha(value)
    ctx.ApplyEffect("assistedHighlight", nil, "alpha")
  end)
  ctx.bindFloat(C.sAssistedHighlightAlpha,
    function() return addon:GetAssistedHighlightAlpha() end,
    function(value)
      ctx.ensureDB()
      addon:SetAssistedHighlightAlpha(ctx.clamp(value, 0.05, 1.00))
      ctx.ApplyEffect("assistedHighlight", nil, "alpha")
    end,
    0.05, 1.00, 2)

  ctx.bindOffset(C.sAssistedHighlightX,
    function()
      local x = addon:GetAssistedHighlightOffset()
      return x
    end,
    function(value)
      local _, y = addon:GetAssistedHighlightOffset()
      addon:SetAssistedHighlightOffset(value, y)
    end,
    -3000, 3000,
    {
      ensureDB = ctx.ensureDB,
      isRefreshing = ctx.IsRefreshing,
      isBlocked = function() return addon:GetAssistedHighlightLocked() end,
      isEnabled = function() return addon:IsAssistedHighlightMirrorEnabled() end,
      onApply = function() ctx.ApplyEffect("assistedHighlight", nil, "layout") end,
    })

  ctx.bindOffset(C.sAssistedHighlightY,
    function()
      local _, y = addon:GetAssistedHighlightOffset()
      return y
    end,
    function(value)
      local x = addon:GetAssistedHighlightOffset()
      addon:SetAssistedHighlightOffset(x, value)
    end,
    -3000, 3000,
    {
      ensureDB = ctx.ensureDB,
      isRefreshing = ctx.IsRefreshing,
      isBlocked = function() return addon:GetAssistedHighlightLocked() end,
      isEnabled = function() return addon:IsAssistedHighlightMirrorEnabled() end,
      onApply = function() ctx.ApplyEffect("assistedHighlight", nil, "layout") end,
    })

  ctx.bindOffset(C.sAssistedHighlightKeybindX,
    function()
      local x = addon:GetAssistedHighlightKeybindOffset()
      return x
    end,
    function(value)
      local _, y = addon:GetAssistedHighlightKeybindOffset()
      addon:SetAssistedHighlightKeybindOffset(value, y)
    end,
    -64, 64,
    {
      ensureDB = ctx.ensureDB,
      isRefreshing = ctx.IsRefreshing,
      isEnabled = function() return addon:IsAssistedHighlightMirrorEnabled() end,
      onApply = function() ctx.ApplyEffect("assistedHighlight", nil, "layout") end,
    })

  ctx.bindOffset(C.sAssistedHighlightKeybindY,
    function()
      local _, y = addon:GetAssistedHighlightKeybindOffset()
      return y
    end,
    function(value)
      local x = addon:GetAssistedHighlightKeybindOffset()
      addon:SetAssistedHighlightKeybindOffset(x, value)
    end,
    -64, 64,
    {
      ensureDB = ctx.ensureDB,
      isRefreshing = ctx.IsRefreshing,
      isEnabled = function() return addon:IsAssistedHighlightMirrorEnabled() end,
      onApply = function() ctx.ApplyEffect("assistedHighlight", nil, "layout") end,
    })

  C.sAssistedHighlightFontSize:SetScript("OnValueChanged", function(_, v)
    if C.sAssistedHighlightFontSize._gseApplyingFromInput or ctx.IsRefreshing() or not addon:IsAssistedHighlightMirrorEnabled() then return end
    ctx.ensureDB()
    local value = ctx.clamp(math.floor(v + 0.5), 6, 40)
    ctx.setSlider(C.sAssistedHighlightFontSize, value)
    if addon:GetAssistedHighlightFontSize() == value then return end
    addon:SetAssistedHighlightFontSize(value)
    ctx.ApplyEffect("assistedHighlight", nil, "font")
  end)
  ctx.bindNumeric(C.sAssistedHighlightFontSize,
    function() return addon:GetAssistedHighlightFontSize() end,
    function(value)
      ctx.ensureDB()
      addon:SetAssistedHighlightFontSize(value)
      ctx.ApplyEffect("assistedHighlight", nil, "font")
    end,
    6, 40)

  initFontDropdown(C.ddAssistedHighlightFont, fontNames,
    function() return addon:GetAssistedHighlightFontName() end,
    function(value)
      ctx.ensureDB()
      addon:SetAssistedHighlightFontName(value)
      ctx.setDD(C.ddAssistedHighlightFont, value, value)
      ctx.ApplyEffect("assistedHighlight", nil, "font")
    end)
end

function Options:OpenSettingsWindow()
  if not self.settingsWindow then self:InitOptions() end
  if self.settingsWindow then self.settingsWindow:Show() end
end

function Options:CloseSettingsWindow()
  if self.settingsWindow then self.settingsWindow:Hide() end
end

function Options:ToggleSettingsWindow()
  if not self.settingsWindow then self:InitOptions() end
  if not self.settingsWindow then return end
  if self.settingsWindow:IsShown() then
    self.settingsWindow:Hide()
  else
    self.settingsWindow:Show()
  end
end

function Options:InitOptions()
  if self.settingsWindow then return end
  ensureDatabase()
  if optionsModule.ApplyActiveSkinPalette then optionsModule.ApplyActiveSkinPalette() end
  local nativeSkin = (optionsModule.IsNativeSkin and optionsModule.IsNativeSkin()) or false

  local frame = _G.GSE_TrackerSettingsWindow
  if frame then
    self.settingsWindow = frame
    return
  end

  frame = API.CreateFrame("Frame", "GSE_TrackerSettingsWindow", UIParent, nativeSkin and "ButtonFrameTemplate" or "BackdropTemplate")
  self.settingsWindow = frame
  frame:SetSize(DEFAULT_W, DEFAULT_H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetFrameStrata("DIALOG")
  frame:SetFrameLevel(40)
  if nativeSkin then
    -- Genuine Blizzard window chrome: gold portrait border, title bar, native close.
    local nativeTitle = (API.GetAddOnMetadata and API.GetAddOnMetadata(addon.name, "Title")) or uiShared.ADDON_DISPLAY_NAME or "GSE Tracker"
    if frame.SetTitle then frame:SetTitle(nativeTitle) end
    if frame.SetPortraitToAsset then
      frame:SetPortraitToAsset(ADDON_ICON)
    elseif frame.portrait and frame.portrait.SetTexture then
      frame.portrait:SetTexture(ADDON_ICON)
    end
    if frame.CloseButton then frame.closeButton = frame.CloseButton end
  else
    frame:SetBackdrop({
      bgFile = WHITE8X8,
      edgeFile = WHITE8X8,
      edgeSize = 2,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if optionsModule.StyleWindowBackground then
      optionsModule.StyleWindowBackground(frame, 0.98)
    else
      frame:SetBackdropColor(0.025, 0.03, 0.035, 0.98)
    end
    styleWindowBorder(frame)
  end
  -- Children anchor to the inset area in Native (clears the gold border + title
  -- bar); to the full frame in Modern.
  local contentRoot = (nativeSkin and frame.Inset) or frame
  frame:Hide()
  table.insert(UISpecialFrames, "GSE_TrackerSettingsWindow")

  local function GetResizeBounds()
    local minW, minH = MIN_W, MIN_H
    if optionsModule.ComputeMinimumWindowSize then
      minW, minH = optionsModule.ComputeMinimumWindowSize(frame._gsetrackerSectionsByTab, frame.GetSelectedTopTab and frame:GetSelectedTopTab() or nil)
    end
    local maxW = math.max(((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or DEFAULT_W) - 40, minW)
    local maxH = math.max(((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or DEFAULT_H) - 40, minH)
    return minW, minH, maxW, maxH
  end

  local function ApplyResizeBounds()
    local minW, minH, maxW, maxH = GetResizeBounds()
    if frame.SetResizeBounds then
      frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
      if frame.SetMinResize then frame:SetMinResize(minW, minH) end
      if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
    return minW, minH, maxW, maxH
  end

  local function AnchorFrameForBottomRightResize()
    local frameScale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local parentScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local scaleRatio = frameScale / parentScale
    local left = ((frame.GetLeft and frame:GetLeft()) or 0) * scaleRatio
    local top = ((frame.GetTop and frame:GetTop()) or 0) * scaleRatio

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end

  local classR, classG, classB = optionsModule.GetClassColor()
  local function ToColorHex(r, g, b)
    local function clamp01(value)
      value = tonumber(value) or 0
      if value < 0 then return 0 end
      if value > 1 then return 1 end
      return value
    end

    local function brighten(value)
      value = clamp01(value)
      return math.min(1, value + ((1 - value) * 0.18))
    end

    return string.format("%02X%02X%02X",
      math.floor(brighten(r) * 255 + 0.5),
      math.floor(brighten(g) * 255 + 0.5),
      math.floor(brighten(b) * 255 + 0.5)
    )
  end

  if not nativeSkin then
    local frameGlow = frame:CreateTexture(nil, "BACKGROUND")
    frameGlow:SetTexture(WHITE8X8)
    frameGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frameGlow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frameGlow:SetVertexColor(classR, classG, classB, 0.012)
    frame.frameGlow = frameGlow
  end

  local sidebar = createBackdrop(frame, 0.98, 1)
  frame.sidebar = sidebar
  sidebar:SetPoint("TOPLEFT", contentRoot, "TOPLEFT", 0, 0)
  sidebar:SetPoint("BOTTOMLEFT", contentRoot, "BOTTOMLEFT", 0, 0)
  sidebar:SetWidth(SIDEBAR_W)
  sidebar:SetBackdropColor(0.025, 0.03, 0.035, 0.98)
  sidebar:SetBackdropBorderColor(0.06, 0.06, 0.06, 1)

  local sidebarGlow = sidebar:CreateTexture(nil, "BORDER")
  sidebarGlow:SetTexture(WHITE8X8)
  sidebarGlow:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 1, -1)
  sidebarGlow:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -1)
  sidebarGlow:SetHeight(40)
  sidebarGlow:SetVertexColor(classR, classG, classB, 0.006)
  frame.sidebarGlow = sidebarGlow

  local sidebarDivider = frame:CreateTexture(nil, "ARTWORK")
  frame.sidebarDivider = sidebarDivider
  sidebarDivider:SetTexture(WHITE8X8)
  sidebarDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, -1)
  sidebarDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 1)
  sidebarDivider:SetWidth(1)
  sidebarDivider:SetVertexColor(0.08, 0.08, 0.08, 1)

  local addonTitle = (API.GetAddOnMetadata and API.GetAddOnMetadata(addon.name, "Title")) or uiShared.ADDON_DISPLAY_NAME or "GSE Tracker"

  local brandBar = API.CreateFrame("Frame", nil, sidebar)
  frame.brandBar = brandBar
  brandBar:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -8)
  brandBar:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, -8)
  brandBar:SetHeight(26)
  brandBar:SetFrameLevel(frame:GetFrameLevel() + 8)

  local logoFrame = API.CreateFrame("Frame", nil, brandBar)
  frame.logoFrame = logoFrame
  logoFrame:SetSize(26, 26)

  local logo = logoFrame:CreateTexture(nil, "ARTWORK")
  frame.logoTexture = logo
  logo:SetAllPoints(logoFrame)
  logo:SetTexture(ADDON_ICON)
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local brandTitle = brandBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.brandTitle = brandTitle
  brandTitle:SetJustifyH("LEFT")
  brandTitle:SetText(addonTitle)
  brandTitle:SetFont(STANDARD_TEXT_FONT, 14, "")

  local function LayoutBrandBar(selfBar)
    local barWidth = (selfBar and selfBar.GetWidth and selfBar:GetWidth()) or 0
    local titleWidth = math.ceil((brandTitle.GetStringWidth and brandTitle:GetStringWidth()) or 0)
    local iconWidth = logoFrame:GetWidth() or 26
    local gap = 8
    local totalWidth = iconWidth + gap + titleWidth
    local leftOffset = math.floor(math.max((barWidth - totalWidth) * 0.5, 0) + 0.5)

    logoFrame:ClearAllPoints()
    logoFrame:SetPoint("LEFT", selfBar, "LEFT", leftOffset, 0)

    brandTitle:ClearAllPoints()
    brandTitle:SetPoint("LEFT", logoFrame, "RIGHT", gap, 0)
    brandTitle:SetWidth(math.max(barWidth - leftOffset - iconWidth - gap, titleWidth))
  end

  brandBar:SetScript("OnSizeChanged", LayoutBrandBar)
  LayoutBrandBar(brandBar)

  local brandDivider = frame:CreateTexture(nil, "BORDER")
  frame.brandDivider = brandDivider
  brandDivider:SetTexture(WHITE8X8)
  brandDivider:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -44)
  brandDivider:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, -44)
  brandDivider:SetHeight(1)
  brandDivider:SetVertexColor(1, 1, 1, 0.03)

  local panelInset = 12
  local panelOuterInset = MAIN_PAD

  local navPanel = createBackdrop(sidebar, 0.96, 1)
  frame.navPanel = navPanel
  navPanel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", panelOuterInset, -HEADER_H)
  navPanel:SetPoint("RIGHT", sidebar, "RIGHT", -panelOuterInset, 0)
  navPanel:SetHeight(120)
  navPanel:SetBackdropColor(0.015, 0.018, 0.022, 0.98)
  navPanel:SetBackdropBorderColor(0.12, 0.12, 0.12, 1)

  local navRail = API.CreateFrame("Frame", nil, navPanel)
  frame.navRail = navRail
  navRail:SetPoint("TOPLEFT", navPanel, "TOPLEFT", panelInset, -panelInset)
  navRail:SetPoint("BOTTOMRIGHT", navPanel, "BOTTOMRIGHT", -panelInset, panelInset)

  local navFooter = sidebar:CreateTexture(nil, "BORDER")
  frame.navFooter = navFooter
  navFooter:SetTexture(WHITE8X8)
  navFooter:SetPoint("TOPLEFT", navPanel, "BOTTOMLEFT", 0, -16)
  navFooter:SetPoint("TOPRIGHT", navPanel, "BOTTOMRIGHT", 0, -16)
  navFooter:SetHeight(1)
  navFooter:SetVertexColor(1, 1, 1, 0.02)

  local sidebarVersion = sidebar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.sidebarVersion = sidebarVersion
  sidebarVersion:SetPoint("LEFT", sidebar, "BOTTOMLEFT", 16, 24)
  sidebarVersion:SetJustifyH("LEFT")
  sidebarVersion:SetFont(STANDARD_TEXT_FONT, 11, "")
  sidebarVersion:SetTextColor(0.84, 0.86, 0.91, 1)
  sidebarVersion:SetAlpha(1)
  do
    local versionText = (API.GetAddOnMetadata and API.GetAddOnMetadata(addon.name, "Version")) or (Constants.ADDON_VERSION or "1.1.4")
    local versionColor = ToColorHex(classR, classG, classB)
    sidebarVersion:SetText(("Version: |cFF%s%s|r"):format(versionColor, tostring(versionText)))
  end

  local function EnsureExternalLinkDialog()
    if frame.externalLinkDialog then
      return frame.externalLinkDialog
    end

    local overlay = API.CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.externalLinkDialog = overlay
    overlay:SetAllPoints(frame)
    overlay:SetFrameStrata(frame:GetFrameStrata())
    overlay:SetFrameLevel(frame:GetFrameLevel() + 40)
    overlay:EnableMouse(true)
    overlay:Hide()

    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetTexture(WHITE8X8)
    shade:SetAllPoints(overlay)
    shade:SetVertexColor(0, 0, 0, 0.68)
    overlay.shade = shade

    local panel = createBackdrop(overlay, 0.99, 1)
    overlay.panel = panel
    panel:SetSize(392, 172)
    panel:SetPoint("CENTER", overlay, "CENTER", 0, 8)
    panel:SetFrameLevel(overlay:GetFrameLevel() + 2)
    panel:SetBackdropColor(0.018, 0.022, 0.028, 0.99)
    panel:SetBackdropBorderColor(0.12, 0.12, 0.12, 1)

    local header = panel:CreateTexture(nil, "BORDER")
    header:SetTexture(WHITE8X8)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    header:SetHeight(30)
    header:SetVertexColor(classR, classG, classB, 0.14)
    overlay.header = header

    local titleRow = API.CreateFrame("Frame", nil, panel)
    overlay.titleRow = titleRow
    titleRow:SetSize(120, 18)
    titleRow:SetPoint("CENTER", header, "CENTER", 0, 0)

    local titleIcon = panel:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(14, 14)
    overlay.titleIcon = titleIcon

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetJustifyH("LEFT")
    title:SetJustifyV("MIDDLE")
    title:SetFont(STANDARD_TEXT_FONT, 12, "")
    title:SetTextColor(0.96, 0.97, 0.99, 1)
    overlay.title = title

    local function LayoutExternalLinkDialogHeader()
      local row = overlay.titleRow
      local iconTexture = overlay.titleIcon and overlay.titleIcon.GetTexture and overlay.titleIcon:GetTexture()
      local iconWidth = iconTexture and 14 or 0
      local gap = iconWidth > 0 and 8 or 0
      local textWidth = math.ceil((overlay.title and overlay.title.GetStringWidth and overlay.title:GetStringWidth()) or 0)
      local rowWidth = math.max(iconWidth + gap + textWidth, 1)

      row:SetWidth(rowWidth)

      overlay.titleIcon:ClearAllPoints()
      if iconWidth > 0 then
        overlay.titleIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
        overlay.titleIcon:Show()
      else
        overlay.titleIcon:Hide()
      end

      overlay.title:ClearAllPoints()
      if iconWidth > 0 then
        overlay.title:SetPoint("LEFT", overlay.titleIcon, "RIGHT", gap, 0)
      else
        overlay.title:SetPoint("LEFT", row, "LEFT", 0, 0)
      end
      overlay.title:SetPoint("RIGHT", row, "RIGHT", 0, 0)
      overlay.title:SetHeight(18)
    end

    overlay.LayoutHeader = LayoutExternalLinkDialogHeader
    LayoutExternalLinkDialogHeader()

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -44)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.68, 0.70, 0.76, 1)
    overlay.subtitle = subtitle

    local editBox = API.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    overlay.editBox = editBox
    editBox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    editBox:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    editBox:SetHeight(30)
    editBox:SetAutoFocus(false)
    editBox:SetFont(STANDARD_TEXT_FONT, 11, "")
    editBox:SetTextInsets(10, 10, 0, 0)
    optionsModule.StyleEditBox(editBox)
    editBox:SetScript("OnEscapePressed", function()
      overlay:Hide()
    end)
    editBox:SetScript("OnEnterPressed", function(selfBox)
      selfBox:HighlightText()
      selfBox:SetCursorPosition(0)
    end)
    editBox:HookScript("OnEditFocusGained", function(selfBox)
      selfBox:HighlightText()
      selfBox:SetCursorPosition(0)
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 2, -8)
    hint:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.50, 0.54, 0.60, 1)
    overlay.hint = hint

    local footerLine = panel:CreateTexture(nil, "BORDER")
    footerLine:SetTexture(WHITE8X8)
    footerLine:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 44)
    footerLine:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 44)
    footerLine:SetHeight(1)
    footerLine:SetVertexColor(1, 1, 1, 0.04)
    overlay.footerLine = footerLine

    local closeButton = API.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    overlay.closeButton = closeButton
    closeButton:SetSize(94, 28)
    closeButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
    closeButton:SetText("Close")
    optionsModule.StyleActionButton(closeButton)
    closeButton:SetScript("OnClick", function()
      overlay:Hide()
    end)

    overlay:SetScript("OnHide", function(selfOverlay)
      if selfOverlay.editBox then
        selfOverlay.editBox:ClearFocus()
      end
      selfOverlay._highlightPending = nil
      selfOverlay:SetScript("OnUpdate", nil)
    end)

    return overlay
  end

  local function ShowExternalLinkDialog(label, url, iconPath)
    local dialog = EnsureExternalLinkDialog()
    dialog.title:SetText(("%s Link"):format(label))
    dialog.subtitle:SetText(("Press Ctrl+C while the %s link is selected below."):format(label))
    dialog.hint:SetText("The link is already selected for copy.")
    dialog.editBox:SetText(url or "")
    dialog.titleIcon:SetTexture(iconPath or ADDON_ICON)
    if dialog.LayoutHeader then
      dialog:LayoutHeader()
    end
    dialog:Show()
    dialog._highlightPending = true
    dialog:SetScript("OnUpdate", function(selfDialog)
      if not selfDialog._highlightPending then
        selfDialog:SetScript("OnUpdate", nil)
        return
      end
      selfDialog._highlightPending = nil
      if selfDialog.editBox then
        selfDialog.editBox:SetFocus()
        selfDialog.editBox:HighlightText()
        selfDialog.editBox:SetCursorPosition(0)
      end
      selfDialog:SetScript("OnUpdate", nil)
    end)
  end

  local socialLinksRow = API.CreateFrame("Frame", nil, sidebar)
  frame.socialLinksRow = socialLinksRow
  socialLinksRow:SetPoint("LEFT", sidebarVersion, "RIGHT", 10, 0)
  socialLinksRow:SetSize(74, 20)

  local function CreateSocialLinkButton(parent, iconPath, glyph, label, url)
    local button = API.CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)
    button:RegisterForClicks("LeftButtonUp")
    button:SetHitRectInsets(-4, -4, -4, -4)

    local hover = button:CreateTexture(nil, "BACKGROUND")
    hover:SetPoint("CENTER", button, "CENTER", 0, 0)
    hover:SetSize(18, 18)
    hover:SetBlendMode("ADD")
    hover:SetVertexColor(1, 1, 1, 1)
    hover:SetAlpha(0)
    button._hover = hover

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetSize(16, 16)
    button._icon = icon

    local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetTextColor(0.92, 0.93, 0.96, 0.82)
    text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    button._gseText = text

    if iconPath then
      hover:SetTexture(iconPath)
      if hover.SetDesaturated then hover:SetDesaturated(true) end
      icon:SetTexture(iconPath)
      icon:SetAlpha(0.76)
      text:Hide()
    else
      hover:Hide()
      icon:Hide()
      text:SetText(glyph or "?")
      text:Show()
    end

    button:SetScript("OnEnter", function(btn)
      if btn._hover and btn._hover.IsShown and btn._hover:IsShown() then
        btn._hover:SetAlpha(0.34)
      end
      if btn._icon and btn._icon.IsShown and btn._icon:IsShown() then
        btn._icon:SetAlpha(1)
      end
      if btn._gseText and btn._gseText.IsShown and btn._gseText:IsShown() then
        btn._gseText:SetTextColor(1, 1, 1, 1)
      end
      -- Tooltip: name the link and show where it goes.
      if (label and label ~= "") or (url and url ~= "") then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        if label and label ~= "" then GameTooltip:SetText(label, 1, 0.82, 0) end
        if url and url ~= "" then GameTooltip:AddLine(url, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine("Click to open in your browser", 0.6, 0.8, 1, true)
        GameTooltip:Show()
      end
    end)

    button:SetScript("OnLeave", function(btn)
      if btn._hover and btn._hover.IsShown and btn._hover:IsShown() then
        btn._hover:SetAlpha(0)
      end
      if btn._icon and btn._icon.IsShown and btn._icon:IsShown() then
        btn._icon:SetAlpha(0.76)
      end
      if btn._gseText and btn._gseText.IsShown and btn._gseText:IsShown() then
        btn._gseText:SetTextColor(0.92, 0.93, 0.96, 0.82)
      end
      GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function()
      ShowExternalLinkDialog(label, url, iconPath)
    end)

    return button
  end

  local discordButton = CreateSocialLinkButton(socialLinksRow, DISCORD_ICON, nil, "Discord", "https://discord.gg/gseunited")
  local patreonButton = CreateSocialLinkButton(socialLinksRow, PATREON_ICON, nil, "Patreon", "https://www.patreon.com/c/ScaryLarryGames646")
  local kofiButton = CreateSocialLinkButton(socialLinksRow, KOFI_ICON, nil, "Ko-Fi", "https://ko-fi.com/scarylarrygames")
  frame.discordButton = discordButton
  frame.patreonButton = patreonButton
  frame.kofiButton = kofiButton

  discordButton:SetPoint("LEFT", socialLinksRow, "LEFT", 0, 0)
  patreonButton:SetPoint("LEFT", discordButton, "RIGHT", 6, 0)
  kofiButton:SetPoint("LEFT", patreonButton, "RIGHT", 6, 0)

  local mainPanel = createBackdrop(frame, 0.95, 1)
  frame.mainPanel = mainPanel
  mainPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
  mainPanel:SetPoint("BOTTOMRIGHT", contentRoot, "BOTTOMRIGHT", 0, 0)
  mainPanel:SetBackdropColor(0.025, 0.03, 0.035, 0.98)
  mainPanel:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)

  local mainInner = mainPanel:CreateTexture(nil, "BORDER")
  mainInner:SetTexture(WHITE8X8)
  mainInner:SetPoint("TOPLEFT", mainPanel, "TOPLEFT", 1, -1)
  mainInner:SetPoint("BOTTOMRIGHT", mainPanel, "BOTTOMRIGHT", -1, 1)
  mainInner:SetVertexColor(0.025, 0.03, 0.035, 0.98)
  frame.mainInner = mainInner

  local ApplyOptionEffect

  frame.RequestRefresh = function(selfFrame)
    if selfFrame._gseRefreshPending then return end
    selfFrame._gseRefreshPending = true
    selfFrame:SetScript("OnUpdate", function(updateFrame)
      updateFrame._gseRefreshPending = nil
      updateFrame:SetScript("OnUpdate", nil)
      if updateFrame:IsShown() and updateFrame.Refresh then
        updateFrame:Refresh()
      end
    end)
  end

  frame:SetScript("OnDragStart", function(selfFrame)
    selfFrame:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(selfFrame)
    selfFrame:StopMovingOrSizing()
  end)

  frame:SetScript("OnShow", function()
    ApplyResizeBounds()
    resetSettingsWindowGeometry(frame)
    addon._editingOptions = true
    if addon.ApplyVisibility then addon:ApplyVisibility() end
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.UpdateActionTrackerMoveMarker then addon:UpdateActionTrackerMoveMarker() end
    if addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    styleWindowBorder(frame)
    if frame.SelectTopTab then frame:SelectTopTab(frame:GetSelectedTopTab()) end
    ApplyOptionEffect("full")
  end)

  frame:SetScript("OnHide", function()
    addon._editingOptions = false
    if addon.ApplyVisibility then addon:ApplyVisibility() end
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.HideActionTrackerMoveMarker then addon:HideActionTrackerMoveMarker() end
    if addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
  end)

  if not nativeSkin then
    local close = API.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton = close
    close:SetPoint("TOPRIGHT", mainPanel, "TOPRIGHT", -10, -8)
    close:SetFrameLevel(frame:GetFrameLevel() + 8)
    optionsModule.StyleCloseButton(close)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.titleText = title
    title:SetPoint("TOPLEFT", mainPanel, "TOPLEFT", MAIN_PAD, -12)
    title:SetText((API.GetAddOnMetadata and API.GetAddOnMetadata(addon.name, "Title")) or uiShared.ADDON_DISPLAY_NAME or "GSE Tracker")

    local titleSubtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.titleSubtitle = titleSubtitle
    titleSubtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    titleSubtitle:SetTextColor(0.48, 0.50, 0.56)
    titleSubtitle:SetText("Tracker control surface")

    local headerLine = frame:CreateTexture(nil, "BORDER")
    frame.headerLine = headerLine
    headerLine:SetColorTexture(1, 1, 1, 0.05)
    headerLine:SetPoint("TOPLEFT", mainPanel, "TOPLEFT", MAIN_PAD, -(HEADER_H - 2))
    headerLine:SetPoint("TOPRIGHT", mainPanel, "TOPRIGHT", -MAIN_PAD, -(HEADER_H - 2))
    headerLine:SetHeight(1)
  end

  local contentPanel = createBackdrop(mainPanel, 0.96, 1)
  frame.contentPanel = contentPanel
  contentPanel:SetPoint("TOPLEFT", mainPanel, "TOPLEFT", MAIN_PAD, -HEADER_H)
  contentPanel:SetPoint("BOTTOMRIGHT", mainPanel, "BOTTOMRIGHT", -MAIN_PAD, FOOTER_H)
  contentPanel:SetBackdropColor(0.015, 0.018, 0.022, 0.98)
  contentPanel:SetBackdropBorderColor(0.12, 0.12, 0.12, 1)

  local content = API.CreateFrame("Frame", nil, contentPanel)
  content:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", panelInset, -panelInset)
  content:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -panelInset, panelInset)
  frame.content = content

  local function CreateTabScrollContent(parent)
    local scroll = API.CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetAllPoints(parent)
    if scroll.ScrollBar then
      scroll.ScrollBar:ClearAllPoints()
      scroll.ScrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -2)
      scroll.ScrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -2, 2)
      if optionsModule.StyleScrollBar then
        optionsModule.StyleScrollBar(scroll.ScrollBar)
      end
    end

    local canvas = API.CreateFrame("Frame", nil, scroll)
    canvas:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    canvas:SetWidth(math.max((parent:GetWidth() or 0) - 28, 0))
    canvas:SetHeight(math.max(parent:GetHeight() or 0, 1))
    scroll:SetScrollChild(canvas)
    scroll.canvas = canvas

    scroll:SetScript("OnSizeChanged", function(selfScroll, width, height)
      local canvasWidth = math.max((width or 0) - 28, 0)
      selfScroll.canvas:SetWidth(canvasWidth)
      if (selfScroll.canvas:GetHeight() or 0) < (height or 0) then
        selfScroll.canvas:SetHeight(height or 1)
      end
    end)

    return scroll, canvas
  end

  local actionTrackerScroll, actionTrackerContent = CreateTabScrollContent(content)
  local centerMarkerScroll, centerMarkerContent = CreateTabScrollContent(content)
  local assistedHighlightScroll, assistedHighlightContent = CreateTabScrollContent(content)

  frame.tabContents = {
    ActionTracker = actionTrackerScroll,
    CenterMarker = centerMarkerScroll,
    Combat = centerMarkerScroll,
    AssistedHighlight = assistedHighlightScroll,
  }
  frame.tabCanvases = {
    ActionTracker = actionTrackerContent,
    CenterMarker = centerMarkerContent,
    Combat = centerMarkerContent,
    AssistedHighlight = assistedHighlightContent,
  }

  local sidebarTabs = {
    { key = "ActionTracker", text = "Action Tracker" },
    { key = "CenterMarker", text = "Center Marker" },
    { key = "AssistedHighlight", text = "Assisted Highlight" },
  }
  buildTopTabs(frame, navRail, sidebarTabs)
  do
    local navHeight = (#sidebarTabs * (optionsModule.TAB_HEIGHT or 30))
      + (math.max(#sidebarTabs - 1, 0) * (optionsModule.TAB_GAP or 4))
      + (panelInset * 2)
    navPanel:SetHeight(navHeight)
  end

  local generalSection = createSection(actionTrackerContent, "General")
  local displaySection = createSection(actionTrackerContent, "Display")
  local seqCard = createSection(actionTrackerContent, "Sequence")
  local modsCard = createSection(actionTrackerContent, "Modifiers")
  local keyCard = createSection(actionTrackerContent, "Keybind")
  local pressedCard = createSection(actionTrackerContent, "Indicator")
  local centerMarkerGeneralSection = createSection(centerMarkerContent, "General")
  local centerMarkerDisplaySection = createSection(centerMarkerContent, "Display")
  local assistedHighlightGeneralSection = createSection(assistedHighlightContent, "General")
  local assistedHighlightDisplaySection = createSection(assistedHighlightContent, "Display")
  local assistedHighlightKeybindSection = createSection(assistedHighlightContent, "Keybind")

  local refreshing = false

  local showOptions = {
    { text = Constants.MODE_ALWAYS or "Always", value = Constants.MODE_ALWAYS or "Always" },
    { text = "Has Harm Target", value = "HasTarget" },
    { text = "In Combat", value = "InCombat" },
    { text = "Never", value = "Never" },
  }

  local skinOptions = {
    { text = "Auto", value = "AUTO" },
    { text = "Modern", value = "MODERN" },
    { text = "Native", value = "NATIVE" },
  }

  local shapeOptions = {
    { text = "Square", value = "square" },
    { text = "Circle", value = "circle" },
    { text = "Dot", value = "dot" },
    { text = "Cross", value = "cross" },
  }

  local assistedHighlightAnchorOptions = {
    { text = "Screen", value = "Screen" },
    { text = "Mouse Cursor", value = "Mouse Cursor" },
    { text = "Target Nameplate", value = "Target Nameplate" },
  }

  local function getFontNames()
    return (addon.GetFontDropdownList and addon:GetFontDropdownList()) or {
      Constants.FONT_FRIZ or "Friz Quadrata TT",
      "Arial Narrow",
      "Morpheus",
      "Skurri",
    }
  end

  local cbEnable = createCheck(generalSection, "")
  local cbLock = createCheck(generalSection, "")
  local actionTrackerXHolder, sActionTrackerX = createSlider(generalSection, "GSE_TrackerActionTrackerXSlider", -3000, 3000, 1, CONTROL_TRACK_W)
  local actionTrackerYHolder, sActionTrackerY = createSlider(generalSection, "GSE_TrackerActionTrackerYSlider", -3000, 3000, 1, CONTROL_TRACK_W)
  local cbBorder = createCheck(displaySection, "")
  local cbPerformance = createCheck(generalSection, "")
  local cbActionTrackerUseClassColor = createCheck(displaySection, "")
  local btnActionTrackerBorderColor = createColorSwatch(displaySection, 20, 20)
  local scaleHolder, sScale = createSlider(generalSection, "GSE_TrackerCustomScaleSlider", 0.70, 1.80, 0.01, CONTROL_TRACK_W)
  if sScale.inputBox then sScale.inputBox:Show() end
  local showHolder, ddShowWhen = createDropdown(generalSection, "GSE_TrackerCustomShowWhenDropDown", CONTROL_TOTAL_W)
  local skinHolder, ddSkin = createDropdown(generalSection, "GSE_TrackerSkinDropDown", CONTROL_TOTAL_W)
  local borderThickHolder, sBorderThickness = createSlider(displaySection, "GSE_TrackerCustomBorderThicknessSlider", 0, 5, 1, CONTROL_TRACK_W)
  local countHolder, sIconCount = createSlider(displaySection, "GSE_TrackerCustomIconCountSlider", 4, 8, 1, CONTROL_TRACK_W)
  local gapHolder, sIconGap = createSlider(displaySection, "GSE_TrackerCustomIconGapSlider", 0, 5, 1, CONTROL_TRACK_W)

  addInlineCheckRow(generalSection, "Enable", cbEnable)
  addInlineCheckRow(generalSection, "Lock", cbLock)
  addRow(generalSection, "Show", showHolder)
  addRow(generalSection, "Skin", skinHolder)
  addRow(generalSection, "Scale", scaleHolder)
  addInlineCheckRow(generalSection, "Performance Mode", cbPerformance)
  addRow(generalSection, "X Offset", actionTrackerXHolder)
  addRow(generalSection, "Y Offset", actionTrackerYHolder)

  addInlineCheckRow(displaySection, "Border", cbBorder)
  addRow(displaySection, "Border Size", borderThickHolder)
  addColorCheckRow(displaySection, "Border Color", btnActionTrackerBorderColor, "Class Color", cbActionTrackerUseClassColor)
  addRow(displaySection, "Icon Count", countHolder)
  addRow(displaySection, "Icon Spacing", gapHolder)

  ApplyOptionEffect = function(effect, elementName, changeKind)
    applyTargetedRefresh(effect, elementName, changeKind)
    if not (frame and frame:IsShown()) then return end

    if effect == "assistedHighlight" then
      if frame.SyncPreviewMode then frame:SyncPreviewMode() end
    end

    if effect == "actionTrackerPosition" then
      if frame.RefreshActionTrackerPositionControls then frame:RefreshActionTrackerPositionControls() end
    elseif effect == "centerMarker" or effect == "combatMarker" then
      if frame.RefreshCombatMarkerControls then frame:RefreshCombatMarkerControls() end
    end

    if changeKind == "layout" then
      frame._gsetrackerSettingsLayoutSig = nil
    end

    local needsWindowRefresh = (
      effect == "full"
    )

    if needsWindowRefresh and frame.RequestRefresh then
      frame:RequestRefresh()
    end
  end

  local buildCtx = {
    fontNames = getFontNames,
    IsRefreshing = function() return refreshing end,
    RefreshLiveActionTrackerForOptions = function(effect, elementName, changeKind) ApplyOptionEffect(effect, elementName, changeKind) end,
    ApplyElementUpdate = function(_, elementName, changeKind)
      ApplyOptionEffect("element", elementName, changeKind)
    end,
  }

  local cbSeqEnabled, sSeqX, sSeqY, sSeqSize, ddSeqFont = buildElementCard(seqCard, "sequenceText", "GSE_TrackerSeq", true, "seqFont", "seqFontSize", buildCtx)
  local cbModsEnabled, sModsX, sModsY, sModsSize, ddModsFont = buildElementCard(modsCard, "modifiersText", "GSE_TrackerMods", true, "modFont", "modFontSize", buildCtx)
  local cbKeybindEnabled, sKeybindX, sKeybindY, sKeybindSize, ddKeybindFont = buildElementCard(keyCard, "keybindText", "GSE_TrackerKeybind", true, "keybindFont", "keybindFontSize", buildCtx)
  local cbPressedEnabled, sPressedX, sPressedY = buildElementCard(pressedCard, "pressedIndicator", "GSE_TrackerPressed", false, nil, nil, buildCtx)
  local pressedSizeHolder, sPressedSize = createSlider(pressedCard, "GSE_TrackerPressedSizeSlider", 4, 24, 1, CONTROL_TRACK_W)
  addRow(pressedCard, "Size", pressedSizeHolder)
  local shapeHolder, ddIndicatorShape = createDropdown(pressedCard, "GSE_TrackerCustomPressedShapeDropDown", CONTROL_TOTAL_W)
  addRow(pressedCard, "Shape", shapeHolder)

  local combatMarkerOptions = {
    { text = "X", value = "x" },
    { text = "Plus", value = "plus" },
    { text = "Diamond", value = "diamond" },
    { text = "Square", value = "square" },
    { text = "Circle", value = "circle" },
  }
  local assistedHighlightShowOptions = {
    { text = Constants.MODE_ALWAYS or "Always", value = Constants.MODE_ALWAYS or "Always" },
    { text = "Has Harm Target", value = Constants.MODE_HAS_TARGET or "HasTarget" },
    { text = "In Combat", value = Constants.MODE_IN_COMBAT or "InCombat" },
    { text = "Never", value = Constants.MODE_NEVER or "Never" },
  }
  local combatMarkerShowOptions = {
    { text = Constants.MODE_ALWAYS or "Always", value = Constants.MODE_ALWAYS or "Always" },
    { text = "Has Harm Target", value = Constants.MODE_HAS_TARGET or "HasTarget" },
    { text = "In Combat", value = Constants.MODE_IN_COMBAT or "InCombat" },
    { text = "Never", value = Constants.MODE_NEVER or "Never" },
  }
  local cbCombatMarkerEnabled = createCheck(centerMarkerGeneralSection, "")
  local cbCombatMarkerLock = createCheck(centerMarkerGeneralSection, "")
  local combatMarkerShowWhenHolder, ddCombatMarkerShowWhen = createDropdown(centerMarkerGeneralSection, "GSE_TrackerCombatMarkerShowWhenDropDown", CONTROL_TOTAL_W)
  local combatMarkerSymbolHolder, ddCombatMarkerSymbol = createDropdown(centerMarkerDisplaySection, "GSE_TrackerCombatMarkerSymbolDropDown", CONTROL_TOTAL_W)
  local combatMarkerXHolder, sCombatMarkerX = createSlider(centerMarkerGeneralSection, "GSE_TrackerCombatMarkerXSlider", -3000, 3000, 1, CONTROL_TRACK_W)
  local combatMarkerYHolder, sCombatMarkerY = createSlider(centerMarkerGeneralSection, "GSE_TrackerCombatMarkerYSlider", -3000, 3000, 1, CONTROL_TRACK_W)
  local combatMarkerSizeHolder, sCombatMarkerSize = createSlider(centerMarkerGeneralSection, "GSE_TrackerCombatMarkerSizeSlider", 16, 128, 1, CONTROL_TRACK_W)
  local combatMarkerAlphaHolder, sCombatMarkerAlpha = createSlider(centerMarkerDisplaySection, "GSE_TrackerCombatMarkerAlphaSlider", 0.05, 1.00, 0.01, CONTROL_TRACK_W)
  if sCombatMarkerAlpha.inputBox then sCombatMarkerAlpha.inputBox:Show() end
  local cbCombatMarkerBorder = createCheck(centerMarkerDisplaySection, "")
  local combatMarkerBorderSizeHolder, sCombatMarkerBorderSize = createSlider(centerMarkerDisplaySection, "GSE_TrackerCombatMarkerBorderSizeSlider", 0, 8, 1, CONTROL_TRACK_W)
  local combatMarkerThicknessHolder, sCombatMarkerThickness = createSlider(centerMarkerDisplaySection, "GSE_TrackerCombatMarkerThicknessSlider", 1, 12, 1, CONTROL_TRACK_W)

  addInlineCheckRow(centerMarkerGeneralSection, "Enable", cbCombatMarkerEnabled)
  addInlineCheckRow(centerMarkerGeneralSection, "Lock", cbCombatMarkerLock)
  addRow(centerMarkerGeneralSection, "Show", combatMarkerShowWhenHolder)
  addRow(centerMarkerGeneralSection, "Size", combatMarkerSizeHolder)
  addRow(centerMarkerGeneralSection, "X Offset", combatMarkerXHolder)
  addRow(centerMarkerGeneralSection, "Y Offset", combatMarkerYHolder)

  local function normalizeSectionVerticalAlignment(section)
    if not (section and section.rows) then return end
    for _, row in ipairs(section.rows) do
      local control = row.control or row.leftControl or row.rightControl
      if row.control and control then
        local targetHeight = control.rowHeight or optionsModule.ROW_H
        if row.GetHeight and row:GetHeight() ~= targetHeight then
          row:SetHeight(targetHeight)
        end
      end
    end
  end

  local function normalizeActionTrackerVerticalAlignment()
    for _, section in ipairs({ generalSection, displaySection, seqCard, modsCard, keyCard, pressedCard }) do
      normalizeSectionVerticalAlignment(section)
    end
  end

  normalizeActionTrackerVerticalAlignment()

  local function normalizeAssistedHighlightVerticalAlignment()
    for _, section in ipairs({ assistedHighlightGeneralSection, assistedHighlightDisplaySection, assistedHighlightKeybindSection }) do
      normalizeSectionVerticalAlignment(section)
    end
  end

  local function normalizeCenterMarkerVerticalAlignment()
    for _, section in ipairs({ centerMarkerGeneralSection, centerMarkerDisplaySection }) do
      normalizeSectionVerticalAlignment(section)
    end
  end

  local cbCombatMarkerUseClassColor = createCheck(centerMarkerDisplaySection, "")
  local btnCombatMarkerColor = createColorSwatch(centerMarkerDisplaySection, 20, 20)
  addRow(centerMarkerDisplaySection, "Symbol", combatMarkerSymbolHolder)
  addRow(centerMarkerDisplaySection, "Alpha", combatMarkerAlphaHolder)
  addRow(centerMarkerDisplaySection, "Thickness", combatMarkerThicknessHolder)
  addInlineCheckRow(centerMarkerDisplaySection, "Border", cbCombatMarkerBorder)
  addRow(centerMarkerDisplaySection, "Border Size", combatMarkerBorderSizeHolder)
  addColorCheckRow(centerMarkerDisplaySection, "Symbol Color", btnCombatMarkerColor, "Class Color", cbCombatMarkerUseClassColor)

  local cbAssistedHighlightEnabled = createCheck(assistedHighlightGeneralSection, "")
  local cbAssistedHighlightLock = createCheck(assistedHighlightGeneralSection, "")
  local assistedHighlightXHolder, sAssistedHighlightX = createSlider(assistedHighlightGeneralSection, "GSE_TrackerAssistedHighlightXSlider", -3000, 3000, 1, CONTROL_TRACK_W)
  local assistedHighlightYHolder, sAssistedHighlightY = createSlider(assistedHighlightGeneralSection, "GSE_TrackerAssistedHighlightYSlider", -3000, 3000, 1, CONTROL_TRACK_W)
  local assistedHighlightSizeHolder, sAssistedHighlightSize = createSlider(assistedHighlightGeneralSection, "GSE_TrackerAssistedHighlightSizeSlider", 28, 96, 1, CONTROL_TRACK_W)
  local assistedHighlightShowWhenHolder, ddAssistedHighlightShowWhen = createDropdown(assistedHighlightGeneralSection, "GSE_TrackerAssistedHighlightShowWhenDropDown", CONTROL_TOTAL_W)
  local cbAssistedHighlightBorder = createCheck(assistedHighlightDisplaySection, "")
  local cbAssistedHighlightRangeChecker = createCheck(assistedHighlightDisplaySection, "")
  local assistedHighlightBorderHolder, sAssistedHighlightBorder = createSlider(assistedHighlightDisplaySection, "GSE_TrackerAssistedHighlightBorderSlider", 0, 12, 1, CONTROL_TRACK_W)
  local cbAssistedHighlightUseClassColor = createCheck(assistedHighlightDisplaySection, "")
  local btnAssistedHighlightColor = createColorSwatch(assistedHighlightDisplaySection, 20, 20)
  local assistedHighlightAlphaHolder, sAssistedHighlightAlpha = createSlider(assistedHighlightDisplaySection, "GSE_TrackerAssistedHighlightAlphaSlider", 0.05, 1.00, 0.01, CONTROL_TRACK_W)
  if sAssistedHighlightAlpha.inputBox then sAssistedHighlightAlpha.inputBox:Show() end
  local assistedHighlightAnchorHolder, ddAssistedHighlightAnchorTarget = createDropdown(assistedHighlightDisplaySection, "GSE_TrackerAssistedHighlightAnchorTargetDropDown", CONTROL_TOTAL_W)
  local cbAssistedHighlightKeybind = createCheck(assistedHighlightKeybindSection, "")
  local assistedHighlightKeybindXHolder, sAssistedHighlightKeybindX = createSlider(assistedHighlightKeybindSection, "GSE_TrackerAssistedHighlightKeybindXSlider", -64, 64, 1, CONTROL_TRACK_W)
  local assistedHighlightKeybindYHolder, sAssistedHighlightKeybindY = createSlider(assistedHighlightKeybindSection, "GSE_TrackerAssistedHighlightKeybindYSlider", -64, 64, 1, CONTROL_TRACK_W)
  local assistedHighlightFontSizeHolder, sAssistedHighlightFontSize = createSlider(assistedHighlightKeybindSection, "GSE_TrackerAssistedHighlightFontSizeSlider", 6, 40, 1, CONTROL_TRACK_W)
  local assistedHighlightFontHolder, ddAssistedHighlightFont = createDropdown(assistedHighlightKeybindSection, "GSE_TrackerAssistedHighlightFontDropDown", CONTROL_TOTAL_W)
  addInlineCheckRow(assistedHighlightGeneralSection, "Enable", cbAssistedHighlightEnabled)
  addInlineCheckRow(assistedHighlightGeneralSection, "Lock", cbAssistedHighlightLock)
  addRow(assistedHighlightGeneralSection, "Show", assistedHighlightShowWhenHolder)
  addRow(assistedHighlightGeneralSection, "Anchor", assistedHighlightAnchorHolder)
  addRow(assistedHighlightGeneralSection, "Size", assistedHighlightSizeHolder)
  addRow(assistedHighlightGeneralSection, "X Offset", assistedHighlightXHolder)
  addRow(assistedHighlightGeneralSection, "Y Offset", assistedHighlightYHolder)

  addInlineCheckRow(assistedHighlightDisplaySection, "Border", cbAssistedHighlightBorder)
  addInlineCheckRow(assistedHighlightDisplaySection, "Range Check", cbAssistedHighlightRangeChecker)
  addRow(assistedHighlightDisplaySection, "Alpha", assistedHighlightAlphaHolder)
  addRow(assistedHighlightDisplaySection, "Border Size", assistedHighlightBorderHolder)
  addColorCheckRow(assistedHighlightDisplaySection, "Border Color", btnAssistedHighlightColor, "Class Color", cbAssistedHighlightUseClassColor)

  addInlineCheckRow(assistedHighlightKeybindSection, "Enable", cbAssistedHighlightKeybind)
  addRow(assistedHighlightKeybindSection, "Font", assistedHighlightFontHolder)
  addRow(assistedHighlightKeybindSection, "Font Size", assistedHighlightFontSizeHolder)
  addRow(assistedHighlightKeybindSection, "X Offset", assistedHighlightKeybindXHolder)
  addRow(assistedHighlightKeybindSection, "Y Offset", assistedHighlightKeybindYHolder)

  normalizeAssistedHighlightVerticalAlignment()
  normalizeCenterMarkerVerticalAlignment()

  local function SetSliderInteractivity(slider, enabled, alpha)
    if not slider then return end
    alpha = alpha ~= nil and alpha or (enabled and 1 or 0.5)
    if enabled then slider:Enable() else slider:Disable() end
    slider:SetAlpha(alpha)
    if slider.inputBox then
      slider.inputBox:SetEnabled(enabled)
      slider.inputBox:SetAlpha(alpha)
      if not enabled then slider.inputBox:ClearFocus() end
    end
    for _, button in ipairs({ slider.minusButton, slider.plusButton }) do
      if button then
        if enabled then button:Enable() else button:Disable() end
        button:SetAlpha(alpha)
      end
    end
  end

  local _ahControlsSig = nil
  local function SetAssistedHighlightControlsEnabled(enabled)
    enabled = enabled and true or false
    local locked = addon:GetAssistedHighlightLocked()
    local colorEnabled = enabled and (not addon:GetAssistedHighlightUseClassColor())
    local sig = (enabled and 4 or 0) + (locked and 2 or 0) + (colorEnabled and 1 or 0)
    if _ahControlsSig == sig then return end
    _ahControlsSig = sig
    local alpha = enabled and 1 or 0.5
    for _, slider in ipairs({ sAssistedHighlightSize, sAssistedHighlightBorder, sAssistedHighlightAlpha, sAssistedHighlightKeybindX, sAssistedHighlightKeybindY, sAssistedHighlightFontSize }) do
      if slider then
        SetSliderInteractivity(slider, enabled, alpha)
      end
    end
    for _, slider in ipairs({ sAssistedHighlightX, sAssistedHighlightY }) do
      local sliderEnabled = enabled and (not locked)
      if slider then
        SetSliderInteractivity(slider, sliderEnabled, sliderEnabled and 1 or 0.5)
      end
    end
    for _, cb in ipairs({ cbAssistedHighlightBorder, cbAssistedHighlightKeybind, cbAssistedHighlightRangeChecker, cbAssistedHighlightLock, cbAssistedHighlightUseClassColor }) do
      if cb then
        cb:SetEnabled(enabled)
        cb:SetAlpha(alpha)
      end
    end
    for _, dd in ipairs({ ddAssistedHighlightShowWhen, ddAssistedHighlightFont, ddAssistedHighlightAnchorTarget }) do
      setDropdownEnabled(dd, enabled, alpha)
    end
    if btnAssistedHighlightColor then
      btnAssistedHighlightColor:SetEnabled(colorEnabled)
      btnAssistedHighlightColor:SetAlpha(colorEnabled and 1 or 0.5)
    end
  end

  frame.UpdateAssistedHighlightPlacementPanel = function()
    return
  end


  initSimpleDropdown(ddShowWhen, showOptions,
    function() return addon:GetShowWhen() end,
    function(value, text)
      ensureDatabase()
      addon:SetShowWhen(value)
      setDropdownValue(ddShowWhen, value, text)
      ApplyOptionEffect("visibility")
    end)

  initSimpleDropdown(ddSkin, skinOptions,
    function() return (addon.GetSkin and addon:GetSkin()) or "AUTO" end,
    function(value, text)
      ensureDatabase()
      if addon.SetSkin then addon:SetSkin(value) end
      setDropdownValue(ddSkin, value, text)
      -- Update the live palette now (hover states pick it up immediately); a
      -- /reload re-paints every already-built widget with the new skin.
      if optionsModule.ApplyActiveSkinPalette then optionsModule.ApplyActiveSkinPalette() end
      local prefix = (Constants and Constants.ADDON_DISPLAY_NAME) or "GSE: Tracker"
      if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "|cffffffff Skin set to " .. tostring(text) .. " \226\128\148 type /reload to fully apply.|r")
      end
    end)

  initSimpleDropdown(ddIndicatorShape, shapeOptions,
    function() return addon:GetPressedIndicatorShape() end,
    function(value, text)
      ensureDatabase()
      addon:SetPressedIndicatorShape(value)
      setDropdownValue(ddIndicatorShape, value, text)
      ApplyOptionEffect("indicator")
    end)

  initSimpleDropdown(ddAssistedHighlightShowWhen, assistedHighlightShowOptions,
    function() return addon:GetAssistedHighlightShowWhen() end,
    function(value, text)
      ensureDatabase()
      addon:SetAssistedHighlightShowWhen(value)
      setDropdownValue(ddAssistedHighlightShowWhen, value, text)
      ApplyOptionEffect("assistedHighlight")
    end)

  initSimpleDropdown(ddCombatMarkerShowWhen, combatMarkerShowOptions,
    function() return addon:GetCombatMarkerShowWhen() end,
    function(value, text)
      ensureDatabase()
      addon:SetCombatMarkerShowWhen(value)
      setDropdownValue(ddCombatMarkerShowWhen, value, text)
      ApplyOptionEffect("centerMarker")
    end)

  initSimpleDropdown(ddCombatMarkerSymbol, combatMarkerOptions,
    function() return addon:GetCombatMarkerSymbol() end,
    function(value, text)
      ensureDatabase()
      addon:SetCombatMarkerSymbol(value)
      setDropdownValue(ddCombatMarkerSymbol, value, text)
      ApplyOptionEffect("centerMarker")
    end)


  initSimpleDropdown(ddAssistedHighlightAnchorTarget, assistedHighlightAnchorOptions,
    function() return addon:GetAssistedHighlightAnchorTarget() end,
    function(value, text)
      ensureDatabase()
      addon:SetAssistedHighlightAnchorTarget(value)
      setDropdownValue(ddAssistedHighlightAnchorTarget, value, text)
      ApplyOptionEffect("assistedHighlight", nil, "layout")
    end)

  sPressedSize:SetScript("OnValueChanged", function(_, v)
    if sPressedSize._gseApplyingFromInput or refreshing then return end
    ensureDatabase()

    local value = clampValue(math.floor(v + 0.5), 4, 24)
    setSliderBoxValue(sPressedSize, value)
    if addon:GetPressedIndicatorSize() == value then return end
    addon:SetPressedIndicatorSize(value)
    ApplyOptionEffect("indicator")
  end)
  bindNumericSliderBox(sPressedSize,
    function() return addon:GetPressedIndicatorSize() end,
    function(value)
      ensureDatabase()
      addon:SetPressedIndicatorSize(value)
      ApplyOptionEffect("indicator")
    end,
    4, 24)

  local function SetActionTrackerSliderEnabled(enabled)
    for _, slider in ipairs({ sActionTrackerX, sActionTrackerY }) do
      if slider then
        SetSliderInteractivity(slider, enabled, enabled and 1 or 0.5)
      end
    end
  end

  local _cmControlsSig = nil
  local function SetCombatMarkerControlsEnabled(enabled)
    enabled = enabled and true or false
    local locked = addon.GetCombatMarkerLocked and addon:GetCombatMarkerLocked() or false
    local colorEnabled = enabled and (not addon:GetCombatMarkerUseClassColor())
    local sig = (enabled and 4 or 0) + (locked and 2 or 0) + (colorEnabled and 1 or 0)
    if _cmControlsSig == sig then return end
    _cmControlsSig = sig
    for _, slider in ipairs({ sCombatMarkerSize, sCombatMarkerThickness, sCombatMarkerBorderSize, sCombatMarkerAlpha }) do
      if slider then
        SetSliderInteractivity(slider, enabled, enabled and 1 or 0.5)
      end
    end
    for _, slider in ipairs({ sCombatMarkerX, sCombatMarkerY }) do
      local sliderEnabled = enabled and (not locked)
      if slider then
        SetSliderInteractivity(slider, sliderEnabled, sliderEnabled and 1 or 0.5)
      end
    end
    for _, dd in ipairs({ ddCombatMarkerShowWhen, ddCombatMarkerSymbol }) do
      setDropdownEnabled(dd, enabled, enabled and 1 or 0.5)
    end
    for _, cb in ipairs({ cbCombatMarkerBorder, cbCombatMarkerUseClassColor, cbCombatMarkerLock }) do
      if cb then
        cb:SetEnabled(enabled)
        cb:SetAlpha(enabled and 1 or 0.5)
      end
    end
    if btnCombatMarkerColor then
      btnCombatMarkerColor:SetEnabled(colorEnabled)
      btnCombatMarkerColor:SetAlpha(colorEnabled and 1 or 0.5)
    end
  end

  cbLock:SetScript("OnClick", function()
    ensureDatabase()
    addon:Lock(cbLock:GetChecked())
    SetActionTrackerSliderEnabled(not cbLock:GetChecked())
    SetCombatMarkerControlsEnabled(addon:IsCombatMarkerEnabled())
    ApplyOptionEffect("lock")
  end)

  cbEnable:SetScript("OnClick", function()
    ensureDatabase()
    addon:SetEnabled(cbEnable:GetChecked())
    if btnActionTrackerBorderColor then
      local enabled = cbEnable:GetChecked() and (not addon:GetActionTrackerUseClassColor())
      btnActionTrackerBorderColor:SetEnabled(enabled)
      btnActionTrackerBorderColor:SetAlpha(enabled and 1 or 0.5)
    end
    ApplyOptionEffect("visibility")
  end)



  sActionTrackerX:SetScript("OnValueChanged", function(_, v)
    if sActionTrackerX._gseApplyingFromInput or refreshing or addon:IsLocked() then return end
    local value = clampValue(math.floor(v + 0.5), -3000, 3000)
    local currentX, y = addon:GetActionTrackerOffset()
    setSliderBoxValue(sActionTrackerX, value)
    if currentX == value then return end
    addon:SetActionTrackerOffset(value, y)
    ApplyOptionEffect("actionTrackerPosition")
  end)
  bindNumericSliderBox(sActionTrackerX,
    function()
      local x = addon:GetActionTrackerOffset()
      return x
    end,
    function(value)
      local _, y = addon:GetActionTrackerOffset()
      addon:SetActionTrackerOffset(value, y)
      ApplyOptionEffect("actionTrackerPosition")
    end,
    -3000, 3000)


  sActionTrackerY:SetScript("OnValueChanged", function(_, v)
    if sActionTrackerY._gseApplyingFromInput or refreshing or addon:IsLocked() then return end
    local value = clampValue(math.floor(v + 0.5), -3000, 3000)
    local x, currentY = addon:GetActionTrackerOffset()
    setSliderBoxValue(sActionTrackerY, value)
    if currentY == value then return end
    addon:SetActionTrackerOffset(x, value)
    ApplyOptionEffect("actionTrackerPosition")
  end)
  bindNumericSliderBox(sActionTrackerY,
    function()
      local _, y = addon:GetActionTrackerOffset()
      return y
    end,
    function(value)
      local x = addon:GetActionTrackerOffset()
      addon:SetActionTrackerOffset(x, value)
      ApplyOptionEffect("actionTrackerPosition")
    end,
    -3000, 3000)

  cbBorder:SetScript("OnClick", function()
    ensureDatabase()
    local checked = cbBorder:GetChecked() and true or false
    local current = addon:GetBorderThickness()
    local target = checked and math.max(current, 1) or 0
    if current == target then
      if cbBorder then cbBorder:SetChecked(target > 0) end
      return
    end
    addon:SetBorderThickness(target)
    if sBorderThickness then
      sBorderThickness:SetValue(target)
      setSliderBoxValue(sBorderThickness, target)
    end
    if cbBorder then cbBorder:SetChecked(target > 0) end
    ApplyOptionEffect("border")
  end)

  cbPerformance:SetScript("OnClick", function()
    ensureDatabase()
    addon:SetPerformanceModeEnabled(cbPerformance:GetChecked())
    ApplyOptionEffect("performanceMode")
  end)


  sScale:SetScript("OnValueChanged", function(_, v)
    local value = clampValue(v, 0.70, 1.80)
    if sScale.inputBox and not sScale.inputBox:HasFocus() then
      sScale.inputBox:SetText(string.format("%.2f", value))
    end
    if refreshing then return end
    ensureDatabase()
    if math.abs(((addon:GetDesiredScale() or 1) - value)) < 0.0001 then return end
    addon:SetScaleValue(value)
    ApplyOptionEffect("scale")
  end)
  bindFloatSliderBox(sScale,
    function() return addon:GetScale() end,
    function(value)
      ensureDatabase()
      addon:SetScaleValue(clampValue(value, 0.70, 1.80))
      ApplyOptionEffect("scale")
    end,
    0.70, 1.80, 2)

  sIconCount:SetScript("OnValueChanged", function(_, v)
    if sIconCount._gseApplyingFromInput or refreshing then return end
    ensureDatabase()

    local value = clampValue(math.floor(v + 0.5), 4, 8)
    setSliderBoxValue(sIconCount, value)
    if addon:GetIconCount() == value then return end
    addon:SetIconCount(value)
    ApplyOptionEffect("iconLayout")
  end)
  bindNumericSliderBox(sIconCount,
    function() return addon:GetIconCount() end,
    function(value)
      ensureDatabase()
      addon:SetIconCount(value)
      ApplyOptionEffect("iconLayout")
    end,
    4, 8)

  sIconGap:SetScript("OnValueChanged", function(_, v)
    if sIconGap._gseApplyingFromInput or refreshing then return end
    ensureDatabase()

    local value = clampValue(math.floor(v + 0.5), 0, 5)
    setSliderBoxValue(sIconGap, value)
    if addon:GetIconGap() == value then return end
    addon:SetIconGap(value)
    ApplyOptionEffect("iconLayout")
  end)
  bindNumericSliderBox(sIconGap,
    function() return addon:GetIconGap() end,
    function(value)
      ensureDatabase()
      addon:SetIconGap(value)
      ApplyOptionEffect("iconLayout")
    end,
    0, 5)

  sBorderThickness:SetScript("OnValueChanged", function(_, v)
    if sBorderThickness._gseApplyingFromInput or refreshing then return end
    ensureDatabase()

    local value = clampValue(math.floor(v + 0.5), 0, 5)
    setSliderBoxValue(sBorderThickness, value)
    if addon:GetBorderThickness() == value then
      if cbBorder then cbBorder:SetChecked(value > 0) end
      return
    end
    addon:SetBorderThickness(value)
    if cbBorder then cbBorder:SetChecked(value > 0) end
    ApplyOptionEffect("border")
  end)
  bindNumericSliderBox(sBorderThickness,
    function() return addon:GetBorderThickness() end,
    function(value)
      ensureDatabase()
      addon:SetBorderThickness(value)
      if cbBorder then cbBorder:SetChecked(value > 0) end
      ApplyOptionEffect("border")
    end,
    0, 5)

  cbCombatMarkerEnabled:SetScript("OnClick", function()
    ensureDatabase()
    addon:SetCombatMarkerEnabled(cbCombatMarkerEnabled:GetChecked())
    SetCombatMarkerControlsEnabled(cbCombatMarkerEnabled:GetChecked())
    ApplyOptionEffect("centerMarker")
  end)

  cbCombatMarkerLock:SetScript("OnClick", function()
    ensureDatabase()
    addon:SetCombatMarkerLocked(cbCombatMarkerLock:GetChecked())
    SetCombatMarkerControlsEnabled(addon:IsCombatMarkerEnabled())
    ApplyOptionEffect("centerMarker")
  end)


  cbCombatMarkerBorder:SetScript("OnClick", function()
    ensureDatabase()
    local checked = cbCombatMarkerBorder:GetChecked() and true or false
    local current = addon:GetCombatMarkerBorderSize()
    local target = checked and math.max(current, 1) or 0
    if current == target then
      cbCombatMarkerBorder:SetChecked(target > 0)
      return
    end
    addon:SetCombatMarkerBorderSize(target)
    if sCombatMarkerBorderSize then
      sCombatMarkerBorderSize:SetValue(target)
      setSliderBoxValue(sCombatMarkerBorderSize, target)
    end
    cbCombatMarkerBorder:SetChecked(target > 0)
    ApplyOptionEffect("centerMarker")
  end)

  frame.UpdateCombatMarkerColorButton = function(_, r, g, b)
    if btnCombatMarkerColor and btnCombatMarkerColor.SetSwatchColor then
      btnCombatMarkerColor:SetSwatchColor(r, g, b)
    end
  end

  local function ApplyCombatMarkerColorChange(r, g, b)
    ensureDatabase()
    addon:SetCombatMarkerColor(r, g, b)
    frame:UpdateCombatMarkerColorButton(r, g, b)
    ApplyOptionEffect("centerMarker")
  end

  local function OpenCombatMarkerColorPicker()
    if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
    local r, g, b = addon:GetCombatMarkerColor()
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local info = {
        r = r,
        g = g,
        b = b,
        hasOpacity = false,
        swatchFunc = function()
          local nr, ng, nb = ColorPickerFrame:GetColorRGB()
          ApplyCombatMarkerColorChange(nr, ng, nb)
        end,
        cancelFunc = function(previousValues)
          if type(previousValues) == "table" then
            ApplyCombatMarkerColorChange(previousValues.r or previousValues[1], previousValues.g or previousValues[2], previousValues.b or previousValues[3])
          end
        end,
      }
      ColorPickerFrame:SetupColorPickerAndShow(info)
      if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
      return
    end

    if not ColorPickerFrame then return end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      ApplyCombatMarkerColorChange(nr, ng, nb)
    end
    ColorPickerFrame.cancelFunc = function(previousValues)
      if type(previousValues) == "table" then
        ApplyCombatMarkerColorChange(previousValues.r or previousValues[1], previousValues.g or previousValues[2], previousValues.b or previousValues[3])
      end
    end
    ColorPickerFrame.opacityFunc = nil
    if ColorPickerFrame.SetColorRGB then
      ColorPickerFrame:SetColorRGB(r, g, b)
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
  end

  frame.UpdateActionTrackerBorderColorButton = function(_, r, g, b)
    if btnActionTrackerBorderColor and btnActionTrackerBorderColor.SetSwatchColor then
      btnActionTrackerBorderColor:SetSwatchColor(r, g, b)
    end
  end

  local function ApplyActionTrackerBorderColorChange(r, g, b)
    ensureDatabase()
    addon:SetActionTrackerBorderColor(r, g, b)
    frame:UpdateActionTrackerBorderColorButton(r, g, b)
    ApplyOptionEffect("border")
  end

  local function OpenActionTrackerBorderColorPicker()
    local r, g, b = addon:GetActionTrackerBorderColor()
    if not ColorPickerFrame then return end
    if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end

    if ColorPickerFrame.SetupColorPickerAndShow then
      local info = {
        r = r,
        g = g,
        b = b,
        opacity = 1,
        hasOpacity = false,
        swatchFunc = function()
          local nr, ng, nb = ColorPickerFrame:GetColorRGB()
          ApplyActionTrackerBorderColorChange(nr, ng, nb)
        end,
        cancelFunc = function(previousValues)
          if type(previousValues) == "table" then
            ApplyActionTrackerBorderColorChange(previousValues.r or previousValues[1], previousValues.g or previousValues[2], previousValues.b or previousValues[3])
          end
        end,
      }
      ColorPickerFrame:SetupColorPickerAndShow(info)
      if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
      return
    end

    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      ApplyActionTrackerBorderColorChange(nr, ng, nb)
    end
    ColorPickerFrame.cancelFunc = function(previousValues)
      if type(previousValues) == "table" then
        ApplyActionTrackerBorderColorChange(previousValues.r or previousValues[1], previousValues.g or previousValues[2], previousValues.b or previousValues[3])
      end
    end
    ColorPickerFrame.opacityFunc = nil
    if ColorPickerFrame.SetColorRGB then
      ColorPickerFrame:SetColorRGB(r, g, b)
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    if optionsModule.StyleColorPickerFrame then optionsModule.StyleColorPickerFrame(ColorPickerFrame) end
  end

  cbActionTrackerUseClassColor:SetScript("OnClick", function()
    ensureDatabase()
    addon:SetActionTrackerUseClassColor(cbActionTrackerUseClassColor:GetChecked())
    if btnActionTrackerBorderColor then
      local enabled = addon:IsEnabled() and (not addon:GetActionTrackerUseClassColor())
      btnActionTrackerBorderColor:SetEnabled(enabled)
      btnActionTrackerBorderColor:SetAlpha(enabled and 1 or 0.5)
    end
    ApplyOptionEffect("border")
  end)

  btnActionTrackerBorderColor:SetScript("OnClick", function()
    if not addon:IsEnabled() or addon:GetActionTrackerUseClassColor() then return end
    OpenActionTrackerBorderColorPicker()
  end)

  cbCombatMarkerUseClassColor:SetScript("OnClick", function()
    ensureDatabase()
    addon:SetCombatMarkerUseClassColor(cbCombatMarkerUseClassColor:GetChecked())
    SetCombatMarkerControlsEnabled(addon:IsCombatMarkerEnabled())
    ApplyOptionEffect("centerMarker")
  end)

  btnCombatMarkerColor:SetScript("OnClick", function()
    if not addon:IsCombatMarkerEnabled() or addon:GetCombatMarkerUseClassColor() then return end
    OpenCombatMarkerColorPicker()
  end)


  do
    local wC = {
      frame = frame,
      cbCombatMarkerBorder = cbCombatMarkerBorder,
      cbCombatMarkerUseClassColor = cbCombatMarkerUseClassColor,
      sCombatMarkerSize = sCombatMarkerSize,
      sCombatMarkerAlpha = sCombatMarkerAlpha,
      sCombatMarkerX = sCombatMarkerX,
      sCombatMarkerY = sCombatMarkerY,
      sCombatMarkerThickness = sCombatMarkerThickness,
      sCombatMarkerBorderSize = sCombatMarkerBorderSize,
      cbAssistedHighlightEnabled = cbAssistedHighlightEnabled,
      cbAssistedHighlightLock = cbAssistedHighlightLock,
      cbAssistedHighlightUseClassColor = cbAssistedHighlightUseClassColor,
      cbAssistedHighlightBorder = cbAssistedHighlightBorder,
      cbAssistedHighlightRangeChecker = cbAssistedHighlightRangeChecker,
      cbAssistedHighlightKeybind = cbAssistedHighlightKeybind,
      btnAssistedHighlightColor = btnAssistedHighlightColor,
      sAssistedHighlightSize = sAssistedHighlightSize,
      sAssistedHighlightBorder = sAssistedHighlightBorder,
      sAssistedHighlightAlpha = sAssistedHighlightAlpha,
      sAssistedHighlightX = sAssistedHighlightX,
      sAssistedHighlightY = sAssistedHighlightY,
      sAssistedHighlightKeybindX = sAssistedHighlightKeybindX,
      sAssistedHighlightKeybindY = sAssistedHighlightKeybindY,
      sAssistedHighlightFontSize = sAssistedHighlightFontSize,
      ddAssistedHighlightFont = ddAssistedHighlightFont,
    }
    local wCtx = {
      IsRefreshing = function() return refreshing end,
      ensureDB = ensureDatabase,
      ApplyEffect = ApplyOptionEffect,
      clamp = clampValue,
      setSlider = setSliderBoxValue,
      setDD = setDropdownValue,
      bindNumeric = bindNumericSliderBox,
      bindFloat = bindFloatSliderBox,
      bindOffset = bindOffsetSlider,
      SetAH = SetAssistedHighlightControlsEnabled,
      SetCM = SetCombatMarkerControlsEnabled,
    }
    WireAssistedHighlightCallbacks(wC, wCtx, getFontNames)
  end

  frame.RefreshFontDropdowns = function()
    for _, dd in ipairs({ ddSeqFont, ddModsFont, ddKeybindFont, ddAssistedHighlightFont }) do
      if dd and dd._gseRefreshMenu then
        dd._gseRefreshMenu()
      end
    end
  end
  addon.RefreshFontDropdowns = function()
    if frame and frame.RefreshFontDropdowns then
      frame:RefreshFontDropdowns()
    end
  end

  local footerLine = frame:CreateTexture(nil, "BORDER")
  frame.footerLine = footerLine
  footerLine:SetColorTexture(1, 1, 1, 0.04)
  footerLine:SetPoint("BOTTOMLEFT", mainPanel, "BOTTOMLEFT", MAIN_PAD, FOOTER_H - 8)
  footerLine:SetPoint("BOTTOMRIGHT", mainPanel, "BOTTOMRIGHT", -MAIN_PAD, FOOTER_H - 8)
  footerLine:SetHeight(1)

  local function CreateFooterButton(width, text, point, relativeTo, relativePoint, x, y)
    local button = API.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, 28)
    button:SetPoint(point, relativeTo, relativePoint, x, y)
    button:SetText(text)
    optionsModule.StyleActionButton(button)
    return button
  end

  -- No GSE launcher buttons: GSE_Tracker is standalone and connects to the GSE
  -- addon ONLY via gse_bridge.lua.
  local reloadBtn = CreateFooterButton(102, "Reload", "BOTTOMRIGHT", mainPanel, "BOTTOMRIGHT", -MAIN_PAD, 10)
  frame.reloadButton = reloadBtn

  local resize = API.CreateFrame("Button", nil, frame)
  frame.resizeHandle = resize
  resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  resize:SetSize(14, 14)
  resize:SetHitRectInsets(-10, 0, 0, -10)
  do
    local triangle = resize:CreateTexture(nil, "OVERLAY")
    triangle:SetTexture(WHITE8X8)
    triangle:SetSize(10, 10)
    triangle:SetPoint("BOTTOMRIGHT", resize, "BOTTOMRIGHT", -2, 2)
    triangle:SetVertexColor(0.4, 0.4, 0.4, 1)
    if triangle.SetVertexOffset then
      triangle:SetVertexOffset(1, 10, -10)
    end
    resize._gseTriangle = triangle

    local function SetTriangleColor(handle, active)
      local tex = handle and handle._gseTriangle
      if not tex then return end
      if active then
        tex:SetVertexColor(1, 1, 1, 1)
      else
        tex:SetVertexColor(0.4, 0.4, 0.4, 1)
      end
    end

    resize:HookScript("OnEnter", function(handle)
      if not frame._gseIsResizing then
        SetTriangleColor(handle, true)
      end
    end)
    resize:HookScript("OnLeave", function(handle)
      if not frame._gseIsResizing then
        SetTriangleColor(handle, false)
      end
    end)
    resize._gseSetTriangleColor = SetTriangleColor
  end
  local function StopResize()
    if not frame._gseIsResizing then return end
    frame._gseIsResizing = nil
    resize:SetScript("OnUpdate", nil)
    frame:StopMovingOrSizing()
    ApplyResizeBounds()
    if resize._gseSetTriangleColor then
      resize._gseSetTriangleColor(resize, resize:IsMouseOver())
    end
    if frame:IsShown() and frame.Refresh then
      frame:Refresh()
    end
  end
  resize:SetScript("OnMouseDown", function(_, button)
    if button and button ~= "LeftButton" then return end
    ApplyResizeBounds()
    AnchorFrameForBottomRightResize()
    frame._gseIsResizing = true
    if resize._gseSetTriangleColor then
      resize._gseSetTriangleColor(resize, true)
    end
    resize:SetScript("OnUpdate", function()
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        StopResize()
      end
    end)
    frame:StartSizing("BOTTOMRIGHT")
  end)
  resize:SetScript("OnMouseUp", StopResize)
  resize:SetScript("OnHide", StopResize)

  local sectionGroups = {
    ActionTracker = {
      generalSection = generalSection,
      displaySection = displaySection,
      seqCard = seqCard,
      modsCard = modsCard,
      keyCard = keyCard,
      pressedCard = pressedCard,
    },
    CenterMarker = {
      centerMarkerGeneralSection = centerMarkerGeneralSection,
      centerMarkerDisplaySection = centerMarkerDisplaySection,
    },
    AssistedHighlight = {
      assistedHighlightGeneralSection = assistedHighlightGeneralSection,
      assistedHighlightDisplaySection = assistedHighlightDisplaySection,
      assistedHighlightKeybindSection = assistedHighlightKeybindSection,
    },
  }
  frame._gsetrackerSectionsByTab = sectionGroups

  local function GetLayoutSignature()
    local selectedTab = frame.GetSelectedTopTab and frame:GetSelectedTopTab() or "ActionTracker"
    return table.concat({
      tostring(math.floor((frame.GetWidth and frame:GetWidth()) or DEFAULT_W)),
      tostring(math.floor((frame.GetHeight and frame:GetHeight()) or DEFAULT_H)),
      tostring(selectedTab),
    }, "|"), selectedTab
  end

  frame.PerformLayout = function(selfFrame, force)
    if not (selfFrame and selfFrame:IsShown()) then return end

    local layoutSig, selectedTab = GetLayoutSignature()
    if (not force) and selfFrame._gsetrackerSettingsLayoutSig == layoutSig then
      return
    end

    selfFrame._gsetrackerSettingsLayoutSig = layoutSig
    local sections = sectionGroups[selectedTab] or sectionGroups.ActionTracker or {}
    local contentTarget = (selfFrame.tabCanvases and selfFrame.tabCanvases[selectedTab]) or (selfFrame.tabContents and selfFrame.tabContents[selectedTab])
    if contentTarget then
      optionsModule.LayoutSettingsWindow(selfFrame, contentTarget, sections, selectedTab)
    end
  end

  frame.RequestLayout = function(selfFrame, force)
    if not selfFrame then return end
    if force then
      selfFrame._gseForceLayoutPending = true
    end
    if selfFrame._gseLayoutPending then return end

    selfFrame._gseLayoutPending = true
    local function runLayout()
      selfFrame._gseLayoutPending = nil
      local forceLayout = selfFrame._gseForceLayoutPending
      selfFrame._gseForceLayoutPending = nil
      if selfFrame:IsShown() and selfFrame.PerformLayout then
        selfFrame:PerformLayout(forceLayout)
      end
    end

    if C_Timer and C_Timer.After then
      C_Timer.After(0, runLayout)
    else
      runLayout()
    end
  end

  frame.SyncPreviewMode = function()
    if addon.RefreshCombatMarker then addon:RefreshCombatMarker() end
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
    if addon.ApplyVisibility then addon:ApplyVisibility() end
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
    if addon.UpdateActionTrackerMoveMarker then addon:UpdateActionTrackerMoveMarker() end
  end

  frame.SelectTopTab = function(_, tabKey)
    local normalized
    -- "PlayerTracker" / "Combat" are legacy tab keys kept for backward compatibility.
    if (tabKey == "CenterMarker") or (tabKey == "PlayerTracker") or (tabKey == "Combat") then
      normalized = "CenterMarker"
    elseif tabKey == "AssistedHighlight" then
      normalized = "AssistedHighlight"
    else
      normalized = "ActionTracker"
    end
    applyTopTabSelection(frame, normalized)
    frame._gsetrackerSettingsLayoutSig = nil
    if frame.SyncPreviewMode then frame:SyncPreviewMode() end
    if frame.Refresh then frame:Refresh() end
  end
  frame.GetSelectedTopTab = function()
    return frame.selectedTopTab or "ActionTracker"
  end
  frame:SelectTopTab("ActionTracker")

  local function syncSliderControl(slider, value)
    if not slider then return end
    if slider:GetValue() ~= value then
      slider:SetValue(value)
    end
    if slider.inputBox and not slider.inputBox:HasFocus() then
      setSliderBoxValue(slider, value)
    end
  end

  frame.RefreshActionTrackerPositionControls = function()
    if not frame:IsShown() then return end
    refreshing = true
    local actionTrackerX, actionTrackerY = addon:GetActionTrackerOffset()
    if sActionTrackerX then
      sActionTrackerX:SetValue(actionTrackerX)
      setSliderBoxValue(sActionTrackerX, actionTrackerX)
    end
    if sActionTrackerY then
      sActionTrackerY:SetValue(actionTrackerY)
      setSliderBoxValue(sActionTrackerY, actionTrackerY)
    end
    SetActionTrackerSliderEnabled(not addon:IsLocked())
    if cbActionTrackerUseClassColor then
      cbActionTrackerUseClassColor:SetChecked(addon:GetActionTrackerUseClassColor())
    end
    if frame.UpdateActionTrackerBorderColorButton then
      local r, g, b = addon:GetActionTrackerBorderColor()
      frame:UpdateActionTrackerBorderColorButton(r, g, b)
    end
    if btnActionTrackerBorderColor then
      local enabled = addon:IsEnabled() and (not addon:GetActionTrackerUseClassColor())
      btnActionTrackerBorderColor:SetEnabled(enabled)
      btnActionTrackerBorderColor:SetAlpha(enabled and 1 or 0.5)
    end
    refreshing = false
  end

  frame.RefreshAssistedHighlightPositionControls = function()
    if not frame:IsShown() then return end
    refreshing = true
    local ax, ay = addon:GetAssistedHighlightOffset()
    local kx, ky = addon:GetAssistedHighlightKeybindOffset()
    syncSliderControl(sAssistedHighlightX, ax)
    syncSliderControl(sAssistedHighlightY, ay)
    syncSliderControl(sAssistedHighlightKeybindX, kx)
    syncSliderControl(sAssistedHighlightKeybindY, ky)
    syncSliderControl(sAssistedHighlightSize, addon:GetAssistedHighlightSize())
    local alpha = addon:GetAssistedHighlightAlpha()
    if sAssistedHighlightAlpha then
      sAssistedHighlightAlpha:SetValue(alpha)
      if sAssistedHighlightAlpha.inputBox and not sAssistedHighlightAlpha.inputBox:HasFocus() then
        sAssistedHighlightAlpha.inputBox:SetText(string.format("%.2f", alpha))
      end
    end
    local borderSize = addon:GetAssistedHighlightBorderSize()
    syncSliderControl(sAssistedHighlightBorder, borderSize)
    if cbAssistedHighlightBorder then
      cbAssistedHighlightBorder:SetChecked(borderSize > 0)
    end
    syncSliderControl(sAssistedHighlightFontSize, addon:GetAssistedHighlightFontSize())
    if ddAssistedHighlightFont then
      local fontName = addon:GetAssistedHighlightFontName()
      setDropdownValue(ddAssistedHighlightFont, fontName, fontName)
    end
    if ddAssistedHighlightAnchorTarget then
      local anchorTarget = addon:GetAssistedHighlightAnchorTarget()
      setDropdownValue(ddAssistedHighlightAnchorTarget, anchorTarget, anchorTarget)
    end
    if cbAssistedHighlightLock then
      cbAssistedHighlightLock:SetChecked(addon:GetAssistedHighlightLocked())
    end
    if cbAssistedHighlightUseClassColor then
      cbAssistedHighlightUseClassColor:SetChecked(addon:GetAssistedHighlightUseClassColor())
    end
    if frame.UpdateAssistedHighlightColorButton then
      local r, g, b = addon:GetAssistedHighlightColor()
      frame:UpdateAssistedHighlightColorButton(r, g, b)
    end
    SetAssistedHighlightControlsEnabled(addon:IsAssistedHighlightMirrorEnabled())
    if frame.SyncPreviewMode then frame:SyncPreviewMode() end
    refreshing = false
  end
  addon.RefreshAssistedHighlightPositionControls = function()
    if frame.RefreshAssistedHighlightPositionControls then
      frame:RefreshAssistedHighlightPositionControls()
    end
  end

  frame.SetAssistedHighlightControlsEnabled = SetAssistedHighlightControlsEnabled
  frame.SetCombatMarkerControlsEnabled = SetCombatMarkerControlsEnabled
  frame.RefreshCombatMarkerControls = function()
    if not frame:IsShown() then return end
    refreshing = true
    local r, g, b = addon:GetCombatMarkerColor()
    if frame.UpdateCombatMarkerColorButton then
      frame:UpdateCombatMarkerColorButton(r, g, b)
    end
    local mx, my = addon:GetCombatMarkerOffset()
    syncSliderControl(sCombatMarkerX, mx)
    syncSliderControl(sCombatMarkerY, my)
    syncSliderControl(sCombatMarkerThickness, addon:GetCombatMarkerThickness())
    syncSliderControl(sCombatMarkerBorderSize, addon:GetCombatMarkerBorderSize())
    if cbCombatMarkerBorder then
      cbCombatMarkerBorder:SetChecked(addon:GetCombatMarkerBorderSize() > 0)
    end
    SetCombatMarkerControlsEnabled(addon:IsCombatMarkerEnabled())
    refreshing = false
  end


  frame.Refresh = buildSettingsRefresh({
    frame = frame,
    sectionsByTab = sectionGroups,
    IsRefreshing = function() return refreshing end,
    SetRefreshing = function(value) refreshing = value end,
    SetActionTrackerSliderEnabled = SetActionTrackerSliderEnabled,
    controls = {
      cbEnable = cbEnable,
      cbLock = cbLock,
      cbBorder = cbBorder,
      cbPerformance = cbPerformance,
      cbActionTrackerUseClassColor = cbActionTrackerUseClassColor,
      cbSeqEnabled = cbSeqEnabled,
      cbModsEnabled = cbModsEnabled,
      cbKeybindEnabled = cbKeybindEnabled,
      cbPressedEnabled = cbPressedEnabled,
      cbCombatMarkerEnabled = cbCombatMarkerEnabled,
      cbCombatMarkerLock = cbCombatMarkerLock,
      cbCombatMarkerBorder = cbCombatMarkerBorder,
      cbCombatMarkerUseClassColor = cbCombatMarkerUseClassColor,
      cbAssistedHighlightEnabled = cbAssistedHighlightEnabled,
      cbAssistedHighlightBorder = cbAssistedHighlightBorder,
      cbAssistedHighlightKeybind = cbAssistedHighlightKeybind,
      cbAssistedHighlightRangeChecker = cbAssistedHighlightRangeChecker,
      cbAssistedHighlightLock = cbAssistedHighlightLock,
      cbAssistedHighlightUseClassColor = cbAssistedHighlightUseClassColor,
      ddAssistedHighlightShowWhen = ddAssistedHighlightShowWhen,
      btnCombatMarkerColor = btnCombatMarkerColor,
      btnActionTrackerBorderColor = btnActionTrackerBorderColor,
      btnAssistedHighlightColor = btnAssistedHighlightColor,
      sActionTrackerX = sActionTrackerX,
      sActionTrackerY = sActionTrackerY,
      sScale = sScale,
      sIconCount = sIconCount,
      sIconGap = sIconGap,
      sBorderThickness = sBorderThickness,
      sSeqX = sSeqX,
      sSeqY = sSeqY,
      sModsX = sModsX,
      sModsY = sModsY,
      sKeybindX = sKeybindX,
      sKeybindY = sKeybindY,
      sPressedX = sPressedX,
      sPressedY = sPressedY,
      sPressedSize = sPressedSize,
      sCombatMarkerX = sCombatMarkerX,
      sCombatMarkerY = sCombatMarkerY,
      sCombatMarkerSize = sCombatMarkerSize,
      sCombatMarkerThickness = sCombatMarkerThickness,
      sCombatMarkerBorderSize = sCombatMarkerBorderSize,
      sAssistedHighlightFontSize = sAssistedHighlightFontSize,
      sCombatMarkerAlpha = sCombatMarkerAlpha,
      sAssistedHighlightSize = sAssistedHighlightSize,
      sAssistedHighlightBorder = sAssistedHighlightBorder,
      sAssistedHighlightAlpha = sAssistedHighlightAlpha,
      sAssistedHighlightX = sAssistedHighlightX,
      sAssistedHighlightY = sAssistedHighlightY,
      sAssistedHighlightKeybindX = sAssistedHighlightKeybindX,
      sAssistedHighlightKeybindY = sAssistedHighlightKeybindY,
      sSeqSize = sSeqSize,
      sModsSize = sModsSize,
      sKeybindSize = sKeybindSize,
      ddShowWhen = ddShowWhen,
      ddIndicatorShape = ddIndicatorShape,
      ddCombatMarkerShowWhen = ddCombatMarkerShowWhen,
      ddCombatMarkerSymbol = ddCombatMarkerSymbol,
      ddSeqFont = ddSeqFont,
      ddModsFont = ddModsFont,
      ddKeybindFont = ddKeybindFont,
      ddAssistedHighlightFont = ddAssistedHighlightFont,
      ddAssistedHighlightAnchorTarget = ddAssistedHighlightAnchorTarget,
    },
  })


  frame:SetScript("OnSizeChanged", function()
    local w = frame:GetWidth() or DEFAULT_W
    local h = frame:GetHeight() or DEFAULT_H
    local minW, minH, maxW, maxH = ApplyResizeBounds()
    local clampedW = math.min(math.max(w, minW), maxW)
    local clampedH = math.min(math.max(h, minH), maxH)
    if w ~= clampedW or h ~= clampedH then
      frame:SetSize(clampedW, clampedH)
      return
    end
    if not frame:IsShown() then return end
    if frame._gseIsResizing and frame.RequestLayout then
      frame:RequestLayout()
    elseif frame.Refresh then
      frame:Refresh()
    end
  end)

  local function SendChatCommand(commandText)
    local editBox = (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()) or ChatFrame1EditBox
    if not editBox then return end

    if ChatFrame_OpenChat then
      ChatFrame_OpenChat(commandText, DEFAULT_CHAT_FRAME)
    else
      editBox:SetText(commandText)
      if ChatEdit_ActivateChat then ChatEdit_ActivateChat(editBox) end
    end

    if editBox:GetText() ~= commandText then
      editBox:SetText(commandText)
    end

    if ChatEdit_SendText then
      ChatEdit_SendText(editBox, 0)
    end
  end

  reloadBtn:SetScript("OnClick", function()
    ReloadUI()
  end)

end
