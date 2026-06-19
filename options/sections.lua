local _, ns = ...
local addon = ns
local Options = ns.Options
local optionsModule = Options

local CONTROL_TRACK_W = optionsModule.CONTROL_TRACK_W
local CONTROL_TOTAL_W = optionsModule.CONTROL_TOTAL_W
local DEFAULT_W = optionsModule.DEFAULT_W
local DEFAULT_H = optionsModule.DEFAULT_H
local MIN_W = optionsModule.MIN_W
local MIN_H = optionsModule.MIN_H
local PAD = optionsModule.PAD
local GAP = optionsModule.GAP
local ROW_GAP = optionsModule.ROW_GAP
local SECTION_START_Y = optionsModule.SECTION_START_Y
local SECTION_BOTTOM_PAD = optionsModule.SECTION_BOTTOM_PAD or 16
local SIDEBAR_W = optionsModule.SIDEBAR_W or 230
local MAIN_PAD = optionsModule.MAIN_PAD or 22

function optionsModule.BuildElementCard(card, elementName, prefix, withFonts, fontKey, sizeKey, ctx)
  local createCheck = optionsModule.CreateCheck
  local createSlider = optionsModule.CreateSlider
  local createDropdown = optionsModule.CreateDropdown
  local addRow = optionsModule.AddRow
  local addInlineCheckRow = optionsModule.AddInlineCheckRow
  local clampValue = optionsModule.Clamp
  local getElementXY = optionsModule.GetElementXY
  local setSliderBoxValue = optionsModule.SetSliderBoxValue
  local bindNumericSliderBox = optionsModule.BindNumericSliderBox
  local initFontDropdown = optionsModule.InitFontDropdown
  local setDropdownValue = optionsModule.SetDD

  local xHolder, sX = createSlider(card, prefix .. "XSlider", -200, 200, 1, CONTROL_TRACK_W)
  local yHolder, sY = createSlider(card, prefix .. "YSlider", -160, 160, 1, CONTROL_TRACK_W)
  local cbEnable = createCheck(card, "")

  local sFont, ddFont
  if withFonts then
    local sizeHolder, slider = createSlider(card, prefix .. "FontSizeSlider", 6, 24, 1, CONTROL_TRACK_W)
    sFont = slider

    local fontHolder, dropdown = createDropdown(card, prefix .. "FontDropDown", CONTROL_TOTAL_W)
    addInlineCheckRow(card, "Enable", cbEnable)
    addRow(card, "Font", fontHolder)
    addRow(card, "Font Size", sizeHolder)
    addRow(card, "X Offset", xHolder)
    addRow(card, "Y Offset", yHolder)
    ddFont = dropdown
  else
    addInlineCheckRow(card, "Enable", cbEnable)
    addRow(card, "X Offset", xHolder)
    addRow(card, "Y Offset", yHolder)
  end

  local function isRefreshing()
    return ctx and ctx.IsRefreshing and ctx:IsRefreshing()
  end

  local function applyElementUpdate(changeKind)
    if ctx and ctx.ApplyElementUpdate then
      ctx:ApplyElementUpdate(elementName, changeKind)
      return
    end
    if ctx and ctx.RefreshLiveActionTrackerForOptions then
      ctx:RefreshLiveActionTrackerForOptions("element", elementName, changeKind)
    end
  end

  local function bindEnabled(cb)
    cb:SetScript("OnClick", function()
      if isRefreshing() then return end
      optionsModule.EnsureDB()
      addon:SetElementEnabled(elementName, cb:GetChecked())
      applyElementUpdate("visibility")
    end)
  end

  local function bindAxis(slider, axis, minV, maxV)
    slider:SetScript("OnValueChanged", function(_, v)
      if slider._gseApplyingFromInput or isRefreshing() then return end
      local x, y = getElementXY(elementName)
      local value = clampValue(math.floor(v + 0.5), minV, maxV)
      local current = axis == "x" and x or y
      setSliderBoxValue(slider, value)
      if current == value then return end
      optionsModule.EnsureDB()
      if axis == "x" then addon:SetElementOffset(elementName, value, y) else addon:SetElementOffset(elementName, x, value) end
      applyElementUpdate("layout")
    end)
    bindNumericSliderBox(slider,
      function()
        local x, y = getElementXY(elementName)
        return axis == "x" and x or y
      end,
      function(value)
        local x, y = getElementXY(elementName)
        optionsModule.EnsureDB()
      if axis == "x" then addon:SetElementOffset(elementName, value, y) else addon:SetElementOffset(elementName, x, value) end
        applyElementUpdate("layout")
      end,
      minV, maxV)
  end

  bindEnabled(cbEnable)
  bindAxis(sX, "x", -200, 200)
  bindAxis(sY, "y", -160, 160)

  if sFont then
    sFont:SetScript("OnValueChanged", function(_, v)
      if sFont._gseApplyingFromInput or isRefreshing() then return end
      optionsModule.EnsureDB()
      local value = clampValue(math.floor(v + 0.5), 6, 24)
      local current = (sizeKey == "seqFontSize" and addon:GetSeqFontSize()) or (sizeKey == "modFontSize" and addon:GetModFontSize()) or addon:GetKeybindFontSize()
      setSliderBoxValue(sFont, value)
      if current == value then return end
      if sizeKey == "seqFontSize" then addon:SetSeqFontSize(value) elseif sizeKey == "modFontSize" then addon:SetModFontSize(value) else addon:SetKeybindFontSize(value) end
      applyElementUpdate("font")
    end)
    bindNumericSliderBox(sFont,
      function()
        if sizeKey == "seqFontSize" then return addon:GetSeqFontSize() end
        if sizeKey == "modFontSize" then return addon:GetModFontSize() end
        return addon:GetKeybindFontSize()
      end,
      function(value)
        optionsModule.EnsureDB()
        if sizeKey == "seqFontSize" then addon:SetSeqFontSize(value) elseif sizeKey == "modFontSize" then addon:SetModFontSize(value) else addon:SetKeybindFontSize(value) end
        applyElementUpdate("font")
      end,
      6, 24)
  end

  if ddFont then
    initFontDropdown(ddFont, ctx and ctx.fontNames or {},
      function()
        if fontKey == "seqFont" then return addon:GetSeqFontName() end
        if fontKey == "modFont" then return addon:GetModFontName() end
        return addon:GetKeybindFontName()
      end,
      function(value)
        optionsModule.EnsureDB()
        if fontKey == "seqFont" then addon:SetSeqFontName(value) elseif fontKey == "modFont" then addon:SetModFontName(value) else addon:SetKeybindFontName(value) end
        setDropdownValue(ddFont, value, value)
        applyElementUpdate("font")
      end)
  end

  return cbEnable, sX, sY, sFont, ddFont
end

function optionsModule.GetSectionHeight(container)
  local rows = container and container.rows or {}
  local total = math.abs(SECTION_START_Y) + SECTION_BOTTOM_PAD
  for i, row in ipairs(rows) do
    total = total + row:GetHeight()
    if i < #rows then total = total + ROW_GAP end
  end
  return total
end

local function GetSingleColumnWidth()
  return (optionsModule.CONTROL_X or 0) + (optionsModule.CONTROL_TOTAL_W or 0) + ((optionsModule.SECTION_INSET_X or 14) * 2)
end

local function ShouldUseSingleColumn(contentW)
  local multiColumnThreshold = (GetSingleColumnWidth() * 2) + GAP + 20
  return contentW < multiColumnThreshold
end

local function FinalizeScrollableContent(content, requiredHeight)
  if not content then return end
  local scrollFrame = content.GetParent and content:GetParent() or nil
  local viewportHeight = (scrollFrame and scrollFrame.GetHeight and scrollFrame:GetHeight()) or 0
  content:SetHeight(math.max(requiredHeight + 8, viewportHeight))
end

function optionsModule.ComputeMinimumWindowSize()
  local columnMinW = GetSingleColumnWidth()
  local shellWidth = SIDEBAR_W + (MAIN_PAD * 2) + (PAD * 2)
  local minW = math.max(MIN_W, columnMinW + shellWidth)
  local minH = MIN_H

  return math.ceil(minW), math.ceil(minH)
end

function optionsModule.LayoutSettingsWindow(frame, content, sections, selectedTab)
  local w = math.max(frame:GetWidth() or DEFAULT_W, MIN_W)
  local h = math.max(frame:GetHeight() or DEFAULT_H, MIN_H)
  if frame:GetWidth() ~= w or frame:GetHeight() ~= h then
    frame:SetSize(w, h)
  end

  local contentW = math.max((content and content.GetWidth and content:GetWidth()) or 0, 0)
  if contentW <= 0 then
    contentW = w - SIDEBAR_W - (MAIN_PAD * 2) - PAD
  end

  local singleColumn = ShouldUseSingleColumn(contentW)
  local singleColumnWidth = math.min(contentW, GetSingleColumnWidth())

  local function StackSections(sectionList)
    local totalHeight = 0
    for index, section in ipairs(sectionList) do
      local sectionHeight = optionsModule.GetSectionHeight(section)
      section:ClearAllPoints()
      section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -totalHeight)
      section:SetSize(singleColumnWidth, sectionHeight)
      optionsModule.LayoutRows(section, SECTION_START_Y)
      totalHeight = totalHeight + sectionHeight
      if index < #sectionList then
        totalHeight = totalHeight + GAP
      end
    end
    FinalizeScrollableContent(content, totalHeight)
  end

  if ((selectedTab == "CenterMarker") or (selectedTab == "PlayerTracker") or (selectedTab == "Combat")) and sections.centerMarkerGeneralSection and sections.centerMarkerDisplaySection then
    local generalSection = sections.centerMarkerGeneralSection
    local displaySection = sections.centerMarkerDisplaySection

    if singleColumn then
      StackSections({ generalSection, displaySection })
      return
    end

    local leftW = math.floor((contentW - GAP) / 2)
    local rightW = contentW - GAP - leftW
    local topRowH = math.max(optionsModule.GetSectionHeight(generalSection), optionsModule.GetSectionHeight(displaySection))

    generalSection:ClearAllPoints()
    generalSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    generalSection:SetSize(leftW, topRowH)

    displaySection:ClearAllPoints()
    displaySection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    displaySection:SetSize(rightW, topRowH)

    optionsModule.LayoutRows(generalSection, SECTION_START_Y)
    optionsModule.LayoutRows(displaySection, SECTION_START_Y)
    FinalizeScrollableContent(content, topRowH)
    return
  elseif ((selectedTab == "CenterMarker") or (selectedTab == "PlayerTracker") or (selectedTab == "Combat")) and (sections.centerMarkerSection or sections.combatSection) then
    local centerMarkerSection = sections.centerMarkerSection or sections.combatSection
    local contentLeftInset = optionsModule.SECTION_INSET_X or 14
    local contentRightInset = optionsModule.SECTION_INSET_X or 14
    local desiredSectionW = (optionsModule.CONTROL_X or 0) + (optionsModule.CONTROL_TOTAL_W or 0) + contentLeftInset + contentRightInset + 18
    local minSectionW = math.max(desiredSectionW, 500)
    local sectionW = math.min(contentW, minSectionW)
    centerMarkerSection:ClearAllPoints()
    centerMarkerSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    centerMarkerSection:SetWidth(sectionW)
    centerMarkerSection:SetHeight(optionsModule.GetSectionHeight(centerMarkerSection))
    optionsModule.LayoutRows(centerMarkerSection, SECTION_START_Y)
    FinalizeScrollableContent(content, optionsModule.GetSectionHeight(centerMarkerSection))
    return
  end

  if selectedTab == "AssistedHighlight" and sections.assistedHighlightGeneralSection and sections.assistedHighlightDisplaySection and sections.assistedHighlightKeybindSection then
    local generalSection = sections.assistedHighlightGeneralSection
    local displaySection = sections.assistedHighlightDisplaySection
    local keybindSection = sections.assistedHighlightKeybindSection

    if singleColumn then
      StackSections({ generalSection, displaySection, keybindSection })
      return
    end

    local leftW = math.floor((contentW - GAP) / 2)
    local rightW = contentW - GAP - leftW
    local topRowH = math.max(optionsModule.GetSectionHeight(generalSection), optionsModule.GetSectionHeight(displaySection))
    local keybindH = optionsModule.GetSectionHeight(keybindSection)

    generalSection:ClearAllPoints()
    generalSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    generalSection:SetSize(leftW, topRowH)

    displaySection:ClearAllPoints()
    displaySection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    displaySection:SetSize(rightW, topRowH)

    keybindSection:ClearAllPoints()
    keybindSection:SetPoint("TOPLEFT", generalSection, "BOTTOMLEFT", 0, -GAP)
    keybindSection:SetSize(leftW, keybindH)

    optionsModule.LayoutRows(generalSection, SECTION_START_Y)
    optionsModule.LayoutRows(displaySection, SECTION_START_Y)
    optionsModule.LayoutRows(keybindSection, SECTION_START_Y)
    FinalizeScrollableContent(content, topRowH + GAP + keybindH)
    return
  end

  if singleColumn then
    StackSections({
      sections.generalSection,
      sections.displaySection,
      sections.seqCard,
      sections.modsCard,
      sections.keyCard,
      sections.pressedCard,
    })
    return
  end

  local leftW = math.floor((contentW - GAP) / 2)
  local rightW = contentW - GAP - leftW

  local topRowH = math.max(optionsModule.GetSectionHeight(sections.generalSection), optionsModule.GetSectionHeight(sections.displaySection))
  local middleRowH = math.max(optionsModule.GetSectionHeight(sections.seqCard), optionsModule.GetSectionHeight(sections.modsCard))
  local bottomRowH = math.max(optionsModule.GetSectionHeight(sections.keyCard), optionsModule.GetSectionHeight(sections.pressedCard))

  sections.generalSection:ClearAllPoints()
  sections.generalSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  sections.generalSection:SetSize(leftW, topRowH)

  sections.displaySection:ClearAllPoints()
  sections.displaySection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  sections.displaySection:SetSize(rightW, topRowH)

  local topY = -(topRowH + GAP)

  sections.seqCard:ClearAllPoints()
  sections.seqCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, topY)
  sections.seqCard:SetSize(leftW, middleRowH)

  sections.modsCard:ClearAllPoints()
  sections.modsCard:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, topY)
  sections.modsCard:SetSize(rightW, middleRowH)

  local bottomY = topY - middleRowH - GAP

  sections.keyCard:ClearAllPoints()
  sections.keyCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, bottomY)
  sections.keyCard:SetSize(leftW, bottomRowH)

  sections.pressedCard:ClearAllPoints()
  sections.pressedCard:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, bottomY)
  sections.pressedCard:SetSize(rightW, bottomRowH)

  for _, section in ipairs({
    sections.generalSection,
    sections.displaySection,
    sections.seqCard,
    sections.modsCard,
    sections.keyCard,
    sections.pressedCard,
  }) do
    optionsModule.LayoutRows(section, SECTION_START_Y)
  end
  FinalizeScrollableContent(content, topRowH + GAP + middleRowH + GAP + bottomRowH)
end
