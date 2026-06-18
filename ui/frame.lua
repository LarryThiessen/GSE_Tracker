local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
addon._ui = addon._ui or {}
local uiShared = addon._ui
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local WHITE8X8 = C.TEXTURE_WHITE8X8 or "Interface/Buttons/WHITE8x8"
local SV = (ns.Utils and ns.Utils.SV) or nil

local function Clamp(v, lo, hi)
  return uiShared.Clamp(v, lo, hi)
end

local function EnsureDB()
  return uiShared.EnsureDB()
end

local function PixelSnap(v, frame)
  return uiShared.PixelSnap(v, frame)
end

local function IconRowWidth(count)
  return uiShared.IconRowWidth(count)
end

local function SetFramePointIfChanged(frame, point, anchor, relativePoint, x, y)
  return uiShared.SetPointIfChanged(frame, point, anchor, relativePoint, x, y)
end

local function IsCanonicalActionTrackerPoint(point, relName, relPoint)
  return point == (C.ANCHOR_CENTER or "CENTER")
    and relName == (C.UI_PARENT_NAME or "UIParent")
    and relPoint == (C.ANCHOR_CENTER or "CENTER")
end

local function GetCenteredOffsets(frame, parent)
  if uiShared.GetCenteredOffsets then
    return uiShared.GetCenteredOffsets(frame, parent)
  end
  return 0, 0
end

local function ApplyCenteredOffsets(frame, parent, x, y)
  if uiShared.ApplyCenteredOffsets then
    return uiShared.ApplyCenteredOffsets(frame, parent, x, y)
  end
  x = PixelSnap(x, parent)
  y = PixelSnap(y, parent)
  SetFramePointIfChanged(frame, "CENTER", parent, "CENTER", x, y)
  return x, y
end

local function ClampCenteredOffsetsToScreen(frame, parent, x, y)
  if uiShared.ClampCenteredOffsetsToScreen then
    return uiShared.ClampCenteredOffsetsToScreen(frame, parent, x, y)
  end
  return PixelSnap(x, parent), PixelSnap(y, parent)
end

local function ParentUnitsToCanonicalPixels(value, parent)
  if uiShared.ParentUnitsToCanonicalPixels then
    return uiShared.ParentUnitsToCanonicalPixels(value, parent)
  end
  return tonumber(value) or 0
end

local function SetTextureInsetsIfChanged(texture, owner, inset)
  if not (texture and owner) then return end
  if texture._gsetrackerInset == inset then return end
  texture._gsetrackerInset = inset
  texture:ClearAllPoints()
  texture:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
  texture:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
end

local function EnsureActionTrackerRowRelativeAnchorFrames(ui)
  if not (ui and ui.content) then return nil end
  ui.elementAnchors = ui.elementAnchors or {}
  local names = { "sequenceText", "modifiersText", "keybindText", "pressedIndicator" }
  for _, name in ipairs(names) do
    if not ui.elementAnchors[name] then
      local anchor = API.CreateFrame("Frame", nil, ui.content)
      anchor:SetSize(1, 1)
      ui.elementAnchors[name] = anchor
    end
  end
  return ui.elementAnchors
end

local function GetActionTrackerRowRelativeBaselineOffsets(ui)
  local pressedSize = tonumber(ui and ui.pressedIndicator and ui.pressedIndicator.GetWidth and ui.pressedIndicator:GetWidth()) or 0
  -- Offsets are measured from the icon-holder CENTRE. The text (name above, mods
  -- below) must clear the holder's vertical extent -- ICON_SIZE/2 for a horizontal
  -- row, but the whole column half-height when vertical -- or it sits on the icons.
  local rowHalfY = ((ui and ui.iconHolder and ui.iconHolder.GetHeight and ui.iconHolder:GetHeight()) or (tonumber(uiShared.ICON_SIZE) or 45)) * 0.5
  if not rowHalfY or rowHalfY <= 0 then rowHalfY = (tonumber(uiShared.ICON_SIZE) or 45) * 0.5 end
  local layout = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) or "HORIZONTAL"

  if layout == "VERTICAL" then
    -- Vertical icon column: the labels render as stacked (top-to-bottom) glyph columns
    -- beside the icons (see FormatLabelForLayout) -- so each is only ~1 glyph wide and
    -- sits close to the column, centred on its vertical centre. Modifiers go to the
    -- LEFT; the sequence/spell name (inner) and keybind (outer) go to the RIGHT as two
    -- narrow columns. _ResizeToContent narrows the frame to match.
    local rowHalfX = ((ui and ui.iconHolder and ui.iconHolder.GetWidth and ui.iconHolder:GetWidth()) or (tonumber(uiShared.ICON_SIZE) or 45)) * 0.5
    if not rowHalfX or rowHalfX <= 0 then rowHalfX = (tonumber(uiShared.ICON_SIZE) or 45) * 0.5 end
    local gap = (uiShared.GAP_ICONS_MODS or 6)
    local colW = uiShared.VERTICAL_LABEL_W or 24
    local innerX = rowHalfX + gap + (colW * 0.5)
    return {
      sequenceText  = { x = innerX,            y = 0 },
      keybindText   = { x = innerX + colW + 2, y = 0 },
      modifiersText = { x = -innerX,           y = 0 },
      pressedIndicator = { x = 0, y = 0, point = "CENTER", relativePoint = "CENTER" },
    }
  end

  -- Sit just below the icon row, nudged up 2px to tuck the labels closer.
  local modsY = -(rowHalfY + (uiShared.GAP_ICONS_MODS or 6) + ((uiShared.MODS_H or 14) * 0.5)) + 2
  -- Sequence name sits above the icon with the SAME gap the mods use below it
  -- (mirror of modsY); keybind stacks 10px above the name (the original spacing).
  -- Was hardcoded 17/27, which overlapped the icon's top.
  local nameY = (rowHalfY + (uiShared.GAP_ICONS_MODS or 6) + ((uiShared.NAME_H or 24) * 0.5)) - 5
  local keybindY = nameY + 10
  return {
    sequenceText = { x = 0, y = nameY },
    modifiersText = { x = 0, y = modsY },
    keybindText = { x = 0, y = keybindY },
    -- Centred on the icon row (was offset to the right of it).
    pressedIndicator = { x = 0, y = 0, point = "CENTER", relativePoint = "CENTER" },
  }
end

local function UpdateActionTrackerRowRelativeAnchors(ui)
  if not (ui and ui.content and ui.iconHolder) then return end
  local anchors = EnsureActionTrackerRowRelativeAnchorFrames(ui)
  if not anchors then return end
  local baselines = GetActionTrackerRowRelativeBaselineOffsets(ui)
  for elementName, cfg in pairs(baselines) do
    local anchor = anchors[elementName]
    if anchor then
      local point = cfg.point or "CENTER"
      local relativePoint = cfg.relativePoint or "CENTER"
      SetFramePointIfChanged(anchor, point, ui.iconHolder, relativePoint, PixelSnap(cfg.x or 0, ui), PixelSnap(cfg.y or 0, ui))
    end
  end
end

local function UpdateActionTrackerIconRowAnchor(ui)
  if not (ui and ui.content and ui.iconHolder) then return end
  SetFramePointIfChanged(ui.iconHolder, "CENTER", ui.content, "CENTER", 0, 0)
  UpdateActionTrackerRowRelativeAnchors(ui)
end

local function UpdateActionTrackerContentFrame(ui)
  if not (ui and ui.content) then return end
  local innerW = math.max(1, (ui:GetWidth() or 0) - ((uiShared.PAD_X or 0) * 2))
  local innerH = math.max(1, (ui:GetHeight() or 0) - ((uiShared.PAD_TOP or 0) + (uiShared.PAD_BOTTOM or 0)))
  ui.content:ClearAllPoints()
  ui.content:SetSize(PixelSnap(innerW, ui), PixelSnap(innerH, ui))
  ui.content:SetPoint("CENTER", ui, "CENTER", 0, 0)
  UpdateActionTrackerIconRowAnchor(ui)
end

local function ActionTrackerDragOnUpdate(frame)
  if frame and frame._isDragging and addon.SyncActiveActionTrackerDragPosition then
    addon:SyncActiveActionTrackerDragPosition()
  end
end

function UI:GetClassColorRGB()
  return uiShared.GetPlayerClassColorRGB(C.CLASS_FALLBACK_R or 0.20, C.CLASS_FALLBACK_G or 0.60, C.CLASS_FALLBACK_B or 1.00)
end

function UI:EnsureActionTrackerMoveMarker()
  if self._actionTrackerMoveMarker then return self._actionTrackerMoveMarker end
  local marker = API.CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  marker:SetSize(C.ACTION_TRACKER_MARKER_BASE_SIZE or 48, C.ACTION_TRACKER_MARKER_BASE_SIZE or 48)
  marker:SetFrameStrata(C.STRATA_TOOLTIP or "TOOLTIP")
  marker:SetFrameLevel(C.ACTION_TRACKER_MARKER_FRAME_LEVEL or 50)
  marker:SetBackdrop({
    bgFile = WHITE8X8,
    edgeFile = WHITE8X8,
    edgeSize = 2,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  local glow = marker:CreateTexture(nil, "BACKGROUND")
  glow:SetPoint("TOPLEFT", marker, "TOPLEFT", -6, 6)
  glow:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", 6, -6)
  glow:SetTexture(WHITE8X8)
  marker.glow = glow
  local crossH = marker:CreateTexture(nil, "ARTWORK")
  crossH:SetTexture(WHITE8X8)
  crossH:SetHeight(2)
  crossH:SetPoint("LEFT", marker, "LEFT", 6, 0)
  crossH:SetPoint("RIGHT", marker, "RIGHT", -6, 0)
  marker.crossH = crossH
  local crossV = marker:CreateTexture(nil, "ARTWORK")
  crossV:SetTexture(WHITE8X8)
  crossV:SetWidth(2)
  crossV:SetPoint("TOP", marker, "TOP", 0, -6)
  crossV:SetPoint("BOTTOM", marker, "BOTTOM", 0, 6)
  marker.crossV = crossV
  marker:Hide()
  self._actionTrackerMoveMarker = marker
  return marker
end

function UI:UpdateActionTrackerMoveMarker()
  local marker = self:EnsureActionTrackerMoveMarker()
  EnsureDB()
  if not addon._editingOptions or self:IsLocked() then
    marker:Hide()
    return
  end

  local r, g, b = self:GetClassColorRGB()
  local ui = self.ui

  marker:ClearAllPoints()
  if ui then
    local markerTarget = ui.content or ui
    if marker:GetParent() ~= markerTarget then
      marker:SetParent(markerTarget)
    end
    marker:SetFrameStrata(ui:GetFrameStrata() or (C.STRATA_TOOLTIP or "TOOLTIP"))
    marker:SetFrameLevel((ui:GetFrameLevel() or 0) + 20)
    marker:SetAllPoints(markerTarget)
  else
    if marker:GetParent() ~= UIParent then
      marker:SetParent(UIParent)
    end
    marker:SetFrameStrata(C.STRATA_TOOLTIP or "TOOLTIP")
    marker:SetFrameLevel(C.ACTION_TRACKER_MARKER_FRAME_LEVEL or 50)
    local x, y = self:GetActionTrackerOffset()
    marker:SetSize(C.ACTION_TRACKER_MARKER_BASE_SIZE or 48, C.ACTION_TRACKER_MARKER_BASE_SIZE or 48)
    SetFramePointIfChanged(marker, "CENTER", UIParent, "CENTER", x, y)
  end
  marker:SetBackdropColor(r, g, b, C.ALPHA_SOFT or 0.10)
  marker:SetBackdropBorderColor(r, g, b, C.ALPHA_STRONG or 0.95)
  marker.glow:SetVertexColor(r, g, b, C.ALPHA_GLOW or 0.18)
  marker.crossH:SetVertexColor(r, g, b, C.ALPHA_STRONG or 0.95)
  marker.crossV:SetVertexColor(r, g, b, C.ALPHA_STRONG or 0.95)
  marker:Show()
end

function UI:HideActionTrackerMoveMarker()
  if self._actionTrackerMoveMarker then self._actionTrackerMoveMarker:Hide() end
end

function UI:UpdateActionTrackerIconRowAnchor()
  UpdateActionTrackerIconRowAnchor(self.ui)
end

function UI:UpdateActionTrackerRowRelativeAnchors()
  UpdateActionTrackerRowRelativeAnchors(self.ui)
end

local function ResolveActionTrackerCenteredOffsets(self)
  local ui = self.ui
  local point, relName, relPoint, rawX, rawY = self:GetActionTrackerPoint()
  rawX = tonumber(rawX) or 0
  rawY = tonumber(rawY) or 0

  if IsCanonicalActionTrackerPoint(point, relName, relPoint) then
    if ui then
      return ClampCenteredOffsetsToScreen(ui, UIParent, rawX, rawY)
    end
    return rawX, rawY
  end

  if not ui then
    return rawX, rawY
  end

  local anchor = (_G[relName] or UIParent)
  SetFramePointIfChanged(ui, point, anchor, relPoint, rawX, rawY)

  local nx, ny = GetCenteredOffsets(ui, UIParent)
  -- Persist the migration so it only happens once.
  self:SetActionTrackerPoint(C.ANCHOR_CENTER or "CENTER", C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", nx, ny)
  return nx, ny
end

function UI:GetActionTrackerOffset()
  EnsureDB()
  -- Read-only: return saved canonical values without writing back.
  local point, relName, relPoint, rawX, rawY = self:GetActionTrackerPoint()
  rawX = tonumber(rawX) or 0
  rawY = tonumber(rawY) or 0
  if IsCanonicalActionTrackerPoint(point, relName, relPoint) then
    return rawX, rawY
  end
  if not self.ui then return rawX, rawY end
  local anchor = (_G[relName] or UIParent)
  SetFramePointIfChanged(self.ui, point, anchor, relPoint, rawX, rawY)
  return GetCenteredOffsets(self.ui, UIParent)
end

function UI:ApplyActionTrackerPosition()
  if not self.ui then return end
  EnsureDB()
  local x, y = ResolveActionTrackerCenteredOffsets(self)
  ApplyCenteredOffsets(self.ui, UIParent, x, y)
  self:UpdateActionTrackerMoveMarker()
end

function UI:SetActionTrackerOffset(x, y)
  EnsureDB()
  if self:IsLocked() then return end
  local nx, ny = self:GetActionTrackerOffset()
  if x ~= nil then nx = x end
  if y ~= nil then ny = y end
  self:SetActionTrackerPoint(C.ANCHOR_CENTER or "CENTER", C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", nx, ny)
  self:ApplyActionTrackerPosition()
  self:RefreshSettingsPositionDisplay()
  self:UpdateActionTrackerMoveMarker()
end

function UI:ApplyStrata()
  local ui = self.ui
  if not ui then return end
  ui:SetFrameStrata(self:GetStrata())
  if self.ApplyCombatMarkerStrata then
    self:ApplyCombatMarkerStrata()
  end
end

function UI:ApplyFontFaces()
  EnsureDB()
  if not (self.ui and self.ui.nameText and self.ui.modShift) then
    self._pendingFontApply = true
    return
  end

  if self.EnsureRowRelativeAnchorOffsetModel and self:EnsureRowRelativeAnchorOffsetModel() then
    if self.ApplyAllElementPositions then
      self:ApplyAllElementPositions()
    end
  end

  self._pendingFontApply = nil

  local seqName = self:GetSeqFontName()
  local modName = self:GetModFontName()
  local keybindName = self:GetKeybindFontName()
  local seqPath = (self.GetFontPathByName and self:GetFontPathByName(seqName)) or STANDARD_TEXT_FONT
  local modPath = (self.GetFontPathByName and self:GetFontPathByName(modName)) or STANDARD_TEXT_FONT
  local keybindPath = (self.GetFontPathByName and self:GetFontPathByName(keybindName)) or modPath or STANDARD_TEXT_FONT
  local seqSize = self:GetSeqFontSize()
  local modSize = self:GetModFontSize()
  local keybindSize = self:GetKeybindFontSize()

  -- Shared outline flag from the Fonts "Outline" selector ("NONE" -> no flag).
  local outline = (ns.Utils and ns.Utils.GetActionTrackerFontOutline and ns.Utils:GetActionTrackerFontOutline()) or "OUTLINE"
  local flags = (outline == "NONE") and "" or outline

  -- Adopt the player's action-bar font STYLE (face + outline) for ALL tracker text
  -- when a UI skin is in use -- mirrors the border/mask/crop adoption. We use the
  -- HotKey font for everything (sequence/macro/spell name, keybind AND modifier
  -- letters): skinners like ActionBarsEnhanced restyle the HotKey/Count fonts but
  -- typically leave the macro Name font at the Blizzard default, so HotKey is the
  -- font that actually reflects the skin. Forced-native keeps the user's configured
  -- fonts. Sizes stay user-controlled (tracker text differs in size from the bars).
  local seqFlags, modFlags, keybindFlags = flags, flags, flags
  if uiShared.GetActionButtonFont then
    local hp, _, hf = uiShared.GetActionButtonFont("hotkey")
    if hp then
      seqPath, seqFlags = hp, hf or ""
      keybindPath, keybindFlags = hp, hf or ""
      modPath, modFlags = hp, hf or ""
    end
  end

  local function SafeSet(fs, path, size, fl)
    if not (fs and fs.SetFont) then return end
    fl = fl or flags
    if not fs:SetFont(path, size, fl) then
      fs:SetFont(STANDARD_TEXT_FONT, size, fl)
    end
  end

  SafeSet(self.ui.nameText, seqPath, seqSize, seqFlags)
  SafeSet(self.ui.keybindText, keybindPath, keybindSize, keybindFlags)
  SafeSet(self.ui.modShift, modPath, modSize, modFlags)
  -- Per-icon keybind labels (the key shown on each recent-spell icon) also use the
  -- Keybind Font, so a font change restyles them immediately.
  if self.ui.icons then
    for i = 1, #self.ui.icons do
      local b = self.ui.icons[i]
      if b and b.keybindText then
        SafeSet(b.keybindText, keybindPath, keybindSize, keybindFlags)
        if self.PositionIconKeybind then self:PositionIconKeybind(b) end
      end
    end
  end
  SafeSet(self.ui.modAlt,   modPath, modSize, modFlags)
  SafeSet(self.ui.modCtrl,  modPath, modSize, modFlags)
  -- Re-space the labels for the new font size so they don't touch at large sizes.
  if self._AlignModsToIcons then self:_AlignModsToIcons() end
  if self._ResizeToContent then self:_ResizeToContent() end
end

function UI:GetBorderThickness()
  if ns.Utils and ns.Utils.GetBorderThickness then
    return ns.Utils:GetBorderThickness()
  end
  EnsureDB()
  return Clamp(tonumber(C.DEFAULT_BORDER_THICKNESS) or 1, 0, 5)
end

function UI:ApplyBorderThickness()
  if not self.ui then return end
  local thickness = self:GetBorderThickness()
  -- Border now always ADOPTS the player's action-bar frame art (no toggle). It is
  -- shown only when the bars have frame art (set from useSkinBorder below); when
  -- there's none (e.g. Classic) there's simply no border -- no coloured fallback.
  local showBorder
  local edgeSize = math.max(1, thickness > 0 and thickness or 1)
  local borderR, borderG, borderB
  if self.GetActionTrackerUseClassColor and self:GetActionTrackerUseClassColor() then
    borderR, borderG, borderB = self:GetClassColorRGB()
  elseif self.GetActionTrackerBorderColor then
    borderR, borderG, borderB = self:GetActionTrackerBorderColor()
  else
    borderR, borderG, borderB = 0, 0, 0
  end

  if self.ui.SetBackdrop then
    -- Panel border: wrap the whole tracker in the skin's themed panel border when one
    -- applies (EllesmereUI's class-coloured glow-border) so the tracker reads as part
    -- of the skin. Otherwise a transparent 1px edge (no panel border).
    local pe, ps, pr, pg, pb
    if uiShared.GetSkinnerPanelBorder then pe, ps, pr, pg, pb = uiShared.GetSkinnerPanelBorder() end
    if pe then
      self.ui:SetBackdrop({
        edgeFile = pe,
        edgeSize = ps or 12,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 }
      })
      self.ui:SetBackdropColor(0, 0, 0, 0)
      self.ui:SetBackdropBorderColor(pr or 0, pg or 0, pb or 0, 1)
    else
      self.ui:SetBackdrop({
        bgFile   = WHITE8X8,
        edgeFile = WHITE8X8,
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 }
      })
      self.ui:SetBackdropColor(0, 0, 0, 0)
      self.ui:SetBackdropBorderColor(0, 0, 0, 0)
    end
  end

  -- Prefer the player's action-button border art (Blizzard default or skinner)
  -- so the tracker matches the bars; fall back to our coloured square border.
  local skinBorder
  if uiShared.GetActionButtonBorder then skinBorder = uiShared.GetActionButtonBorder() end
  -- Frame-art skin (Blizzard/ABE) -> draw the adopted frame texture. Thin-border
  -- skin (ElvUI: no frame art, just a ~1px backdrop) -> draw our thin coloured
  -- border instead. No skin info at all (Classic) -> no border.
  local useSkinBorder = (skinBorder and (skinBorder.atlas or skinBorder.file)) and true or false
  local thinBorder = (skinBorder and skinBorder.thin) and true or false
  showBorder = useSkinBorder or thinBorder

  -- A thin-border skin (ElvUI) drives the tracker border's COLOUR + THICKNESS from
  -- the skin's own live settings, so it tracks the skin exactly (e.g. ElvUI's black
  -- 1px border) instead of the tracker's own colour pickers. Only applies when the
  -- skinner reported a style; otherwise the tracker's colour settings above stand.
  if thinBorder and skinBorder and skinBorder.r then
    borderR, borderG, borderB = skinBorder.r, skinBorder.g, skinBorder.b
    if skinBorder.thickness and skinBorder.thickness > 0 then
      edgeSize = math.max(1, skinBorder.thickness)
    end
  end

  local icons = self.ui.icons or {}
  for _, icon in ipairs(icons) do
    if icon and icon.SetBackdrop then
      -- When masked, using frame art, OR a thin-border skin, the icon fills the whole
      -- frame so the thin border hugs the icon edge (insetting leaves a 1px gap that
      -- reads as "the border is larger than the icon").
      local fillFrame = icon._isMasked or useSkinBorder or thinBorder
      local bdInset = fillFrame and 0 or edgeSize
      icon:SetBackdrop({
        bgFile   = WHITE8X8,
        edgeFile = WHITE8X8,
        edgeSize = edgeSize,
        insets   = { left = bdInset, right = bdInset, top = bdInset, bottom = bdInset }
      })
      icon:SetBackdropColor(0, 0, 0, 0)

      local sw = (icon.GetWidth and icon:GetWidth()) or uiShared.ICON_SIZE or 45
      local sh = (icon.GetHeight and icon:GetHeight()) or sw
      if not sw or sw <= 0 then sw = uiShared.ICON_SIZE or 45 end
      if not sh or sh <= 0 then sh = sw end

      if showBorder and useSkinBorder then
        -- Use the action button's border/frame art (matches the UI skin). The
        -- frame art is sized by the bars' border:button ratio and centred on our
        -- icon (mirroring how skinners like ActionBarsEnhanced anchor the
        -- NormalTexture, which can sit outside the base icon).
        local bw = sw * (skinBorder.wRatio or 1)
        local bh = sh * (skinBorder.hRatio or 1)
        if not icon._skinBorder then
          icon._skinBorder = icon:CreateTexture(nil, "OVERLAY")
        end
        local sb = icon._skinBorder
        if skinBorder.atlas then
          sb:SetAtlas(skinBorder.atlas, false)
        else
          sb:SetTexture(skinBorder.file)
          if skinBorder.coords then
            sb:SetTexCoord(unpack(skinBorder.coords))
          end
        end
        sb:ClearAllPoints()
        sb:SetSize(bw, bh)
        sb:SetPoint("CENTER", icon, "CENTER", 0, 0)
        -- Frame art keeps its natural colour (tinting multiplies a dark texture =
        -- washed/black). Colour is applied via the coloured square border instead.
        sb:SetVertexColor(1, 1, 1)
        sb:Show()
        icon:SetBackdropBorderColor(0, 0, 0, 0)

        -- Keep the icon at its OWN size and let the frame art (drawn larger at the
        -- skin's real ratio) frame it -- the border's transparent inner window is
        -- sized to the icon, so its inner edge lands on the icon edge like the bars.
        -- Scaling the icon up to the frame footprint (as before) balloons the icon
        -- for ornate frames like ActionBarsEnhanced. Shave 0.5px per side so the art
        -- tucks just INSIDE the frame's inner edge instead of poking past it.
        if icon.tex then
          local ox = -0.5
          local oy = -0.5
          icon.tex:ClearAllPoints()
          icon.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -ox, oy)
          icon.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", ox, -oy)
          icon.tex._gsetrackerInset = nil
        end
      else
        if icon._skinBorder then icon._skinBorder:Hide() end
        local texInset = fillFrame and 0 or thickness
        if icon.tex then
          SetTextureInsetsIfChanged(icon.tex, icon, texInset)
        end
        if showBorder then
          icon:SetBackdropBorderColor(borderR or 0, borderG or 0, borderB or 0, 1)
        else
          icon:SetBackdropBorderColor(0, 0, 0, 0)
        end
      end

      -- Re-size the icon mask to the texture's FINAL geometry. The mask must be
      -- scaled by the bars' mask:icon ratio and centred (NOT SetAllPoints) so its
      -- opaque region covers the whole visible icon -- otherwise it clips the icon
      -- well inside the frame, leaving a dark gap. Established at creation while
      -- the texture was smaller, so re-assert after the resize above.
      if icon._isMasked and icon._iconMask and icon.tex then
        if uiShared.SizeIconMask then
          uiShared.SizeIconMask(icon)
        else
          icon._iconMask:ClearAllPoints()
          icon._iconMask:SetAllPoints(icon.tex)
        end
      end
    end
  end
end

function UI:ApplyScale()
  if not self.ui then return end
  self.ui:SetScale(self:GetDesiredScale())
  self:_ResizeToContent()
  self:_AlignModsToIcons()
  self:UpdateActionTrackerMoveMarker()
end

local function GetCursorPositionInParentSpace(parent)
  parent = parent or UIParent
  local scale = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
  if not scale or scale == 0 then scale = 1 end
  local cursorX, cursorY = API.GetCursorPosition()
  return (tonumber(cursorX) or 0) / scale, (tonumber(cursorY) or 0) / scale
end

local function SyncRuntimeActionTrackerPointCache(ui, x, y)
  if not ui then return end
  local appliedX = uiShared.CanonicalPixelsToParentUnits and uiShared.CanonicalPixelsToParentUnits(x, UIParent) or (tonumber(x) or 0)
  local appliedY = uiShared.CanonicalPixelsToParentUnits and uiShared.CanonicalPixelsToParentUnits(y, UIParent) or (tonumber(y) or 0)
  ui._gsetrackerPoint = C.ANCHOR_CENTER or "CENTER"
  ui._gsetrackerAnchor = UIParent
  ui._gsetrackerRelativePoint = C.ANCHOR_CENTER or "CENTER"
  ui._gsetrackerPointX = appliedX
  ui._gsetrackerPointY = appliedY
end

local function CopyActionTrackerPoint(point, relName, relPoint, x, y)
  return {
    type(point) == "string" and point or (C.ANCHOR_CENTER or "CENTER"),
    type(relName) == "string" and relName or (C.UI_PARENT_NAME or "UIParent"),
    type(relPoint) == "string" and relPoint or (C.ANCHOR_CENTER or "CENTER"),
    tonumber(x) or 0,
    tonumber(y) or 0,
  }
end

function UI:RefreshSettingsPositionDisplay()
  local settingsWindow = addon.settingsWindow
  if not (settingsWindow and settingsWindow.IsShown and settingsWindow:IsShown()) then return end
  if settingsWindow.RefreshActionTrackerPositionControls then
    settingsWindow:RefreshActionTrackerPositionControls()
    return
  end
  if settingsWindow.Refresh then
    settingsWindow:Refresh()
  end
end

function UI:SyncActiveActionTrackerDragPosition()
  local frame = self.ui
  if not (frame and frame._isDragging) then return false end

  local origin = self._actionTrackerDragOrigin
  local startCursorX = self._actionTrackerDragCursorOriginX
  local startCursorY = self._actionTrackerDragCursorOriginY

  local x, y
  if origin and startCursorX ~= nil and startCursorY ~= nil then
    local cursorX, cursorY = GetCursorPositionInParentSpace(UIParent)
    x = (tonumber(origin[4]) or 0) + ParentUnitsToCanonicalPixels(cursorX - startCursorX, UIParent)
    y = (tonumber(origin[5]) or 0) + ParentUnitsToCanonicalPixels(cursorY - startCursorY, UIParent)
  else
    x, y = GetCenteredOffsets(frame, UIParent)
  end

  x, y = ClampCenteredOffsetsToScreen(frame, UIParent, x, y)
  self:SetActionTrackerPoint(C.ANCHOR_CENTER or "CENTER", C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", x, y)
  ApplyCenteredOffsets(frame, UIParent, x, y)
  SyncRuntimeActionTrackerPointCache(frame, x, y)
  self:RefreshSettingsPositionDisplay()
  self:UpdateActionTrackerMoveMarker()
  return true
end

function UI:BeginActionTrackerDrag(frame)
  frame = frame or self.ui
  if not frame then return false end
  if frame._isDragging then return true end

  local x, y = self:GetActionTrackerOffset()
  self._actionTrackerDragOrigin = CopyActionTrackerPoint(C.ANCHOR_CENTER or "CENTER", C.UI_PARENT_NAME or "UIParent", C.ANCHOR_CENTER or "CENTER", x, y)
  self._actionTrackerDragCursorOriginX, self._actionTrackerDragCursorOriginY = GetCursorPositionInParentSpace(UIParent)
  frame._isDragging = true
  frame:SetScript("OnUpdate", ActionTrackerDragOnUpdate)
  ApplyCenteredOffsets(frame, UIParent, x, y)
  SyncRuntimeActionTrackerPointCache(frame, x, y)
  self:SyncActiveActionTrackerDragPosition()
  self:UpdateActionTrackerMoveMarker()
  return true
end

function UI:EndActionTrackerDrag(commitPosition)
  local frame = self.ui
  if not (frame and frame._isDragging) then return false end

  if frame.StopMovingOrSizing then
    frame:StopMovingOrSizing()
  end

  if commitPosition then
    self:SyncActiveActionTrackerDragPosition()
    local x, y = self:GetActionTrackerOffset()
    ApplyCenteredOffsets(frame, UIParent, x, y)
    SyncRuntimeActionTrackerPointCache(frame, x, y)
    self:RefreshSettingsPositionDisplay()
  else
    local origin = self._actionTrackerDragOrigin
    if origin then
      self:SetActionTrackerPoint(origin[1], origin[2], origin[3], origin[4], origin[5])
    end
    self:ApplyActionTrackerPosition()
  end

  frame._isDragging = false
  frame:SetScript("OnUpdate", nil)
  self._actionTrackerDragOrigin = nil
  self._actionTrackerDragCursorOriginX = nil
  self._actionTrackerDragCursorOriginY = nil
  self:RefreshDragMouseState()
  self:UpdateActionTrackerMoveMarker()
  return true
end

function UI:CanDragActionTracker()
  local ui = self.ui
  if not ui then return false end
  if not ui:IsShown() then return false end
  if self:IsLocked() then return false end
  if API.InCombatLockdown and API.InCombatLockdown() then return false end
  return true
end

function UI:RefreshDragMouseState()
  local ui = self.ui
  if not ui then return end
  EnsureDB()

  local canDrag = self:CanDragActionTracker()

  if (not canDrag) and ui._isDragging then
    self:EndActionTrackerDrag(true)
    return
  end

  ui:SetMovable(canDrag)
  ui:EnableMouse(canDrag)
  if ui.RegisterForDrag then
    if canDrag then
      ui:RegisterForDrag("LeftButton")
    else
      ui:RegisterForDrag()
    end
  end
end

function UI:Lock(locked)
  EnsureDB()
  self:SetLocked(locked)
  if self.ui then
    self:RefreshDragMouseState()
  end
  if self.ApplyEditModeIconPreview then
    self:ApplyEditModeIconPreview(true)
  end
  self:UpdateActionTrackerMoveMarker()
end

function UI:SetBorder(on)
  EnsureDB()
  self:SetBorderEnabled(on)
  if self.ApplyBorderThickness then
    self:ApplyBorderThickness()
  end
  if self.RequestUIRebuild then
    self:RequestUIRebuild("settings")
  elseif self.RebuildIcons then
    self:RebuildIcons(true)
  end
end

function UI:SetBackground(on)
  return self:SetBorder(on)
end

local STRUCTURAL_REBUILD_REASONS = {
  init = true,
  settings = true,
  iconCount = true,
}

function UI:_GetRenderSettingsSignature()
  EnsureDB()
  return table.concat({
    tostring((self.GetEditModePreviewIconCount and self:GetEditModePreviewIconCount()) or self:GetIconCount()),
    tostring(self:GetIconGap()),
    tostring(self:GetBorderThickness()),
    tostring(self:IsBorderEnabled() and 1 or 0),
    tostring(string.format("%.2f", self:GetDesiredScale() or 1)),
    tostring(self:GetShowWhen()),
  }, "|")
end

function UI:_GetDeterministicRenderSignature()
  local ui = self.ui
  if not ui then return nil end
  return table.concat({
    self:_GetRenderSettingsSignature(),
    tostring(ui._lastVisible == true),
  }, "|")
end

function UI:_CanRunStructuralRebuild(reason)
  reason = reason or self._pendingUIRebuildReason or "settings"
  if not STRUCTURAL_REBUILD_REASONS[reason] then
    return false
  end

  return true
end

function UI:RequestUIRebuild(reason)
  reason = reason or "settings"
  if not STRUCTURAL_REBUILD_REASONS[reason] then
    return false
  end

  self._pendingUIRebuild = true
  self._pendingUIRebuildReason = reason

  if self.ui and self.ApplyDeterministicRenderPipeline then
    return self:ApplyDeterministicRenderPipeline(reason)
  end

  return false
end

function UI:ApplyDeterministicRenderPipeline(reason)
  local ui = self.ui
  if not ui then return false end

  reason = reason or self._pendingUIRebuildReason or "settings"
  if not self:_CanRunStructuralRebuild(reason) then
    return false
  end

  local renderSig = self:_GetDeterministicRenderSignature()
  if (not self._pendingUIRebuild) and ui._lastRenderPipelineSig == renderSig then
    return false
  end

  ui._lastRenderPipelineSig = renderSig
  self._pendingUIRebuild = nil
  self._pendingUIRebuildReason = nil

  if self.RebuildIcons then
    return self:RebuildIcons(true)
  end

  return false
end

function UI:ResetToDefaults()
  -- SV:ResetToDefaults resets the ACTIVE store (account or per-character) and sets
  -- the right global internally -- don't reassign GSETrackerDB here.
  if SV and SV.ResetToDefaults then
    SV:ResetToDefaults({ colors = true })
  end

  EnsureDB()

  local ui = self.ui
  if not ui then return end

  if ui._isDragging then
    self:EndActionTrackerDrag(false)
  end

  self._pendingUIRebuild = nil
  self._pendingUIRebuildReason = nil
  ui._lastRenderPipelineSig = nil

  self:ApplyScale()
  self:ApplyStrata()
  self:ApplyFontFaces()
  self:ApplyBorderThickness()
  self:ApplyActionTrackerPosition()
  self:Lock(self:IsLocked())

  self:RequestUIRebuild("settings")
  if self.ApplyDeterministicRenderPipeline then
    self:ApplyDeterministicRenderPipeline("settings")
  end

  self:ApplyAllElementPositions()
  self:ApplyVisibility()
  self:ClearSpellHistory()
  self:RefreshDragMouseState()
  self:UpdateActionTrackerMoveMarker()
  if self.RefreshMinimapButton then
    self:RefreshMinimapButton()
  end
end

function UI:_AlignModsToIcons()
  local ui = self.ui
  if not (ui and ui.modifiersFrame) then return end
  local function PS(v) return PixelSnap(v, ui) end

  -- Keep the labels spread at the fixed spacing, but expand it when needed so they
  -- never touch -- always leave at least a one-space gap between adjacent labels,
  -- scaled to the modifier font (the labels grow with the Modifiers Font size).
  local altW   = (ui.modAlt and ui.modAlt.GetStringWidth and ui.modAlt:GetStringWidth()) or 0
  local shiftW = (ui.modShift and ui.modShift.GetStringWidth and ui.modShift:GetStringWidth()) or 0
  local ctrlW  = (ui.modCtrl and ui.modCtrl.GetStringWidth and ui.modCtrl:GetStringWidth()) or 0
  local modSize = (self.GetModFontSize and self:GetModFontSize()) or uiShared.MOD_FONT_SIZE or 8
  local spaceGap = math.max(3, modSize * 0.35) -- ~one space at the current font size
  local base = uiShared.MOD_FIXED_X_SPACING or 48
  -- Symmetric spacing: ALT and CTRL sit EQUIDISTANT from the centred SHIFT.
  -- Using per-side widths (CTRL is wider than ALT) pushed the group visibly right
  -- of the icon centre. Take the larger of the two so neither label can touch.
  local spacing = math.max(base, (shiftW + altW) * 0.5 + spaceGap, (shiftW + ctrlW) * 0.5 + spaceGap)
  local leftSpacing, rightSpacing = spacing, spacing

  local xAlt   = PS(-leftSpacing + (uiShared.MOD_ALT_X_NUDGE or 0))
  local xShift = PS(0 + (uiShared.MOD_SHIFT_X_NUDGE or 0))
  local xCtrl  = PS(rightSpacing + (uiShared.MOD_CTRL_X_NUDGE or 0))
  ui.modifiersFrame:SetSize(PS(uiShared.TEXT_W), PS(uiShared.MODS_H))
  ui.modAlt:ClearAllPoints(); ui.modAlt:SetPoint("CENTER", ui.modifiersFrame, "CENTER", xAlt, 0)
  ui.modShift:ClearAllPoints(); ui.modShift:SetPoint("CENTER", ui.modifiersFrame, "CENTER", xShift, 0)
  ui.modCtrl:ClearAllPoints(); ui.modCtrl:SetPoint("CENTER", ui.modifiersFrame, "CENTER", xCtrl, 0)
  -- Remember each label's resting x so the press slide-in animation can re-anchor
  -- it (x stays, only y is animated).
  ui.modAlt._modBaseX, ui.modShift._modBaseX, ui.modCtrl._modBaseX = xAlt, xShift, xCtrl
end

function UI:_ResizeToContent()
  local ui = self.ui
  if not ui then return end
  local function PS(v) return PixelSnap(v, ui) end
  local count = (self.GetEditModePreviewIconCount and self:GetEditModePreviewIconCount()) or self:GetIconCount()
  local layout = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) or "HORIZONTAL"
  local rowLen = IconRowWidth(count) -- icon row long-axis length

  if layout == "VERTICAL" then
    -- Labels are narrow stacked glyph columns (mods left; name inner + keybind outer on
    -- the right), so the frame stays narrow. Text is centred within its (invisible)
    -- label frame, so only the tracker frame size matters here. Height is the icon
    -- column plus padding.
    local colW = uiShared.VERTICAL_LABEL_W or 24
    local gap = uiShared.GAP_ICONS_MODS
    local rowHalfX = uiShared.ICON_SIZE * 0.5
    local innerX = rowHalfX + gap + (colW * 0.5)
    local halfW = (innerX + colW + 2) + (colW * 0.5) -- out to the keybind (outer) column edge
    local w = Clamp(2 * halfW + uiShared.PAD_X * 2, uiShared.MIN_W, uiShared.MAX_W)
    local frameW = PS(w)
    local colH = math.max(rowLen, (uiShared.NAME_H * 2) + 4)
    local frameH = PS(uiShared.PAD_TOP + colH + uiShared.PAD_BOTTOM)

    local sizeSig = table.concat({ "V", tostring(frameW), tostring(frameH), tostring(count) }, "|")
    if ui._lastResizeSig ~= sizeSig then
      ui._lastResizeSig = sizeSig
      ui:SetSize(frameW, frameH)
      UpdateActionTrackerContentFrame(ui)
      self:ApplyAllElementPositions()
      self:UpdateActionTrackerMoveMarker()
    else
      UpdateActionTrackerIconRowAnchor(ui)
    end
    return
  end

  local nameW = (ui.nameText:GetStringWidth() or 0) + uiShared.PAD_X * 2
  local keybindW = (ui.keybindText and ui.keybindText:GetStringWidth() or 0) + uiShared.PAD_X * 2
  -- Icon block extent: horizontal row is wide x ICON_SIZE; vertical column is
  -- ICON_SIZE wide x rowLen tall.
  local iconBlockW = ((layout == "VERTICAL") and uiShared.ICON_SIZE or rowLen) + uiShared.PAD_X * 2
  local iconBlockH = (layout == "VERTICAL") and rowLen or uiShared.ICON_SIZE
  local stableTextW = math.max(nameW, keybindW, uiShared.TEXT_W + uiShared.PAD_X * 2)
  ui._stableTextWidth = math.max(ui._stableTextWidth or 0, stableTextW)
  local w = Clamp(math.max(ui._stableTextWidth or stableTextW, iconBlockW, uiShared.MIN_W), uiShared.MIN_W, uiShared.MAX_W)
  local innerW = PS(w - (uiShared.PAD_X * 2))
  local frameW = PS(w)
  local h = uiShared.PAD_TOP + uiShared.NAME_H + uiShared.GAP_NAME_ICONS + iconBlockH + uiShared.GAP_ICONS_MODS + uiShared.MODS_H + uiShared.PAD_BOTTOM
  local frameH = PS(h)

  local sizeSig = table.concat({ tostring(innerW), tostring(frameW), tostring(frameH), tostring(count), tostring(ui._stableTextWidth or stableTextW) }, "|")
  local changed = ui._lastResizeSig ~= sizeSig
  ui._lastResizeSig = sizeSig

  if changed then
    if ui.sequenceTextFrame then ui.sequenceTextFrame:SetSize(innerW, PS(uiShared.NAME_H)) end
    if ui.keybindFrame then ui.keybindFrame:SetSize(innerW, PS(uiShared.NAME_H)) end
    if ui.modifiersFrame then ui.modifiersFrame:SetSize(innerW, PS(uiShared.MODS_H)) end
    ui:SetSize(frameW, frameH)
    UpdateActionTrackerContentFrame(ui)
  end

  UpdateActionTrackerIconRowAnchor(ui)

  if changed then
    self:ApplyAllElementPositions()
    self:UpdateActionTrackerMoveMarker()
  end
end

function UI:BuildMainFrame()
  if self.ui then return end
  EnsureDB()

  local ui = _G.GSE_TrackerFrame
  if ui then
    self.ui = ui
    return
  end

  ui = API.CreateFrame("Frame", "GSE_TrackerFrame", UIParent, "BackdropTemplate")
  self.ui = ui

  ui:SetScale(self:GetDesiredScale())
  ui:SetFrameStrata(self:GetStrata())
  ui:SetClampedToScreen(true)
  ui:SetMovable(true)
  ui:EnableMouse(true)

  ui._combatState = false

  ui:SetBackdrop({
    bgFile   = WHITE8X8,
    edgeFile = WHITE8X8,
    edgeSize = math.max(1, (addon:GetBorderThickness() or 0) > 0 and addon:GetBorderThickness() or 1),
    insets   = { left = 0, right = 0, top = 0, bottom = 0 }
  })

  ui:SetBackdropColor(0, 0, 0, 0)
  ui:SetBackdropBorderColor(0, 0, 0, 0)

  local function PS(v) return PixelSnap(v, ui) end

  ui.content = API.CreateFrame("Frame", nil, ui)
  UpdateActionTrackerContentFrame(ui)

  ui.elements = ui.elements or {}
  EnsureActionTrackerRowRelativeAnchorFrames(ui)

  ui.sequenceTextFrame = API.CreateFrame("Frame", nil, ui.content)
  ui.sequenceTextFrame:SetSize(PS(uiShared.TEXT_W), PS(uiShared.NAME_H))
  ui.elements.sequenceText = ui.sequenceTextFrame

  ui.nameText = ui.sequenceTextFrame:CreateFontString(nil, "OVERLAY")
  ui.nameText:SetPoint(C.ANCHOR_CENTER or "CENTER", ui.sequenceTextFrame, C.ANCHOR_CENTER or "CENTER", 0, 0)
  ui.nameText:SetJustifyH("CENTER")
  ui.nameText:SetFont(STANDARD_TEXT_FONT, uiShared.NAME_FONT_SIZE, "OUTLINE")
  ui.nameText:SetText("")


  ui.modifiersFrame = API.CreateFrame("Frame", nil, ui.content)
  ui.modifiersFrame:SetSize(PS(uiShared.TEXT_W), PS(uiShared.MODS_H))
  ui.elements.modifiersText = ui.modifiersFrame

  ui.modShift = ui.modifiersFrame:CreateFontString(nil, "OVERLAY")
  ui.modShift:SetFont(STANDARD_TEXT_FONT, uiShared.MOD_FONT_SIZE, "OUTLINE")
  ui.modShift:SetJustifyH("CENTER")
  ui.modShift:SetText("SHIFT")

  ui.modAlt = ui.modifiersFrame:CreateFontString(nil, "OVERLAY")
  ui.modAlt:SetFont(STANDARD_TEXT_FONT, uiShared.MOD_FONT_SIZE, "OUTLINE")
  ui.modAlt:SetJustifyH("CENTER")
  ui.modAlt:SetText("ALT")

  ui.modCtrl = ui.modifiersFrame:CreateFontString(nil, "OVERLAY")
  ui.modCtrl:SetFont(STANDARD_TEXT_FONT, uiShared.MOD_FONT_SIZE, "OUTLINE")
  ui.modCtrl:SetJustifyH("CENTER")
  ui.modCtrl:SetText("CTRL")

  -- modShift is the single combined modifier readout (e.g. "RShift+LCtrl"); make it
  -- wide enough to hold the full string and centre it. modAlt/modCtrl are unused.
  ui.modShift:SetWidth(PS(uiShared.TEXT_W))
  ui.modAlt:SetWidth(PS(uiShared.ICON_SIZE + 10))
  ui.modCtrl:SetWidth(PS(uiShared.ICON_SIZE + 10))

  if addon and addon.ApplyFontFaces then addon:ApplyFontFaces() end

  ui.iconHolder = API.CreateFrame("Frame", nil, ui.content)
  UpdateActionTrackerIconRowAnchor(ui)

  ui.keybindFrame = API.CreateFrame("Frame", nil, ui.content)
  ui.keybindFrame:SetSize(PS(uiShared.TEXT_W), PS(uiShared.NAME_H))
  ui.elements.keybindText = ui.keybindFrame
  ui.keybindText = ui.keybindFrame:CreateFontString(nil, "OVERLAY")
  ui.keybindText:SetPoint("CENTER", ui.keybindFrame, "CENTER", 0, 0)
  ui.keybindText:SetJustifyH("CENTER")
  ui.keybindText:SetFont(STANDARD_TEXT_FONT, uiShared.MOD_FONT_SIZE, "OUTLINE")
  ui.keybindText:SetText("")
  if self.SetupPressedIndicator then
    self:SetupPressedIndicator(ui)
  end

  if addon and addon.ApplyFontFaces then
    addon:ApplyFontFaces()
  end

  ui.icons = {}
  ui._iconBaseX = {}
  ui._lastTextures = {}
  ui._castsInCombat = 0
  if self.RegisterModifierEvents then
    self:RegisterModifierEvents(ui)
  else
    uiShared.SyncModifiers(ui)
    if addon.RefreshDragMouseState then addon:RefreshDragMouseState() end
  end

  if self.RegisterCombatEvents then
    self:RegisterCombatEvents(ui)
  end

  ui:SetScript("OnDragStart", function(frame)
    if not addon:CanDragActionTracker() then return end
    addon:BeginActionTrackerDrag(frame)
  end)

  ui:SetScript("OnDragStop", function()
    addon:EndActionTrackerDrag(true)
  end)

  self:RequestUIRebuild("init")
  self:_AlignModsToIcons()
  self:ClearSpellHistory()

  -- Show and size the frame BEFORE applying position so that
  -- ClampCenteredOffsetsToScreen sees the final frame dimensions.
  ui:Show()
  self:_ResizeToContent()
  if self.EnsureCenteredElementOffsetModel then
    self:EnsureCenteredElementOffsetModel()
  end
  self:ApplyAllElementPositions()
  if self.RefreshPressedIndicator then self:RefreshPressedIndicator() end

  -- Position is applied after the frame has its final size to prevent
  -- incorrect clamping from overwriting saved offsets.
  self:ApplyActionTrackerPosition()

  self:UpdateModifiers()
  self:Lock(self:IsLocked())
  self:ApplyVisibility()
  self:UpdateActionTrackerMoveMarker()
end
