local _, ns = ...
local addon = ns
local UI = ns.UI
local Tracker = ns.Tracker or {}
local API = (ns.Utils and ns.Utils.API) or {}
local uiShared = addon._ui or {}
local pixelSnap = uiShared.PixelSnap
local copyArrayInto = uiShared.CopyArrayInto
local clearArray = uiShared.ClearArray or uiShared.ClearTable
local iconRowWidth = uiShared.IconRowWidth
local ICON_SIZE = uiShared.ICON_SIZE
local SCROLL_DUR = uiShared.SCROLL_DUR
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local FLOW_FADE_IN_DUR = 0.10
local FLOW_FADE_OUT_DUR = 0.12

local CLASS_SAMPLE_SPELL_IDS = {
  WARRIOR     = { 12294, 1464,   5308,  1680,  23922,  85288  }, -- Mortal Strike, Slam, Execute, Whirlwind, Shield Slam, Raging Blow
  PALADIN     = { 35395, 20271, 85256, 20473,  31935,  53600  }, -- Crusader Strike, Judgment, Templar's Verdict, Holy Shock, Avenger's Shield, Shield of the Righteous
  HUNTER      = { 34026,185358, 19434,217200, 257620, 259387  }, -- Kill Command, Arcane Shot, Aimed Shot, Barbed Shot, Multi-Shot, Mongoose Bite
  ROGUE       = {  1752,    53,196819,  2098,   1329,  51723  }, -- Sinister Strike, Backstab, Eviscerate, Dispatch, Mutilate, Fan of Knives
  PRIEST      = {   589,  8092,  2061,    17,    585,  34433  }, -- Shadow Word: Pain, Mind Blast, Flash Heal, Power Word: Shield, Smite, Dispel Magic
  DEATHKNIGHT = { 49998, 49020, 49143, 55090, 195182, 343294  }, -- Death Strike, Obliterate, Frost Strike, Scourge Strike, Marrowrend, Soul Reaper
  SHAMAN      = {188196, 17364, 51505, 61882, 188443,  73899  }, -- Lightning Bolt, Stormstrike, Lava Burst, Earthquake, Chain Lightning, Unleash Elements
  MAGE        = {   133,   116, 30451,108853,  30455,  84714  }, -- Fireball, Frostbolt, Arcane Blast, Fire Blast, Ice Lance, Frozen Orb
  WARLOCK     = { 29722,   686,   172,116858,    980,    348  }, -- Incinerate, Shadow Bolt, Corruption, Chaos Bolt, Agony, Immolate
  MONK        = {100780,100784,107428,113656, 101546, 152175, 123986, 322101}, -- Tiger Palm, Blackout Kick, Rising Sun Kick, Fists of Fury, Spinning Crane Kick, Whirling Dragon Punch, Chi Burst, Expel Harm
  DRUID       = { 78674,  5176,  1822,  1079,  33917,   8921  }, -- Starsurge, Wrath, Rake, Rip, Mangle, Moonfire
  DEMONHUNTER = {162794,195072,188499,204596, 258920, 198013  }, -- Chaos Strike, Fel Rush, Blade Dance, Sigil of Flame, Immolation Aura, Eye Beam
  EVOKER      = {356995,357211,357208,359073, 367226, 355913  }, -- Disintegrate, Pyre, Fire Breath, Eternity Surge, Spiritbloom, Emerald Blossom
}

local function GetEditModePreviewTexture(index)
  local _, classToken = UnitClass("player")
  local spellIDs = (classToken and CLASS_SAMPLE_SPELL_IDS[classToken])
               or CLASS_SAMPLE_SPELL_IDS.MONK
  local count = #spellIDs
  if count == 0 then
    return 134400 -- INV_Misc_QuestionMark fileID fallback
  end

  index = tonumber(index) or 1
  local spellID = spellIDs[((index - 1) % count) + 1]
  local texture = nil

  if API.GetSpellTexture then
    texture = API.GetSpellTexture(spellID)
  end

  if not texture and C_Spell and C_Spell.GetSpellTexture then
    texture = C_Spell.GetSpellTexture(spellID)
  end

  if not texture and _G.GetSpellTexture then
    texture = _G.GetSpellTexture(spellID)
  end

  return texture or 134400 -- INV_Misc_QuestionMark
end

local function GetClassColor()
  return uiShared.GetPlayerClassColorRGB(1, 1, 1)
end

local function GetSequenceColor(seqKey)
  if ns.Utils and ns.Utils.GetSequenceColorRGB then
    return ns.Utils:GetSequenceColorRGB(seqKey, GetClassColor())
  end
  return GetClassColor()
end

local function EnsureFlowFadeIn(icon)
  if icon._flowFadeInAG then return end
  local ag = icon:CreateAnimationGroup()
  ag:SetToFinalAlpha(true)
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(0)
  a:SetToAlpha(1)
  a:SetDuration(FLOW_FADE_IN_DUR)
  a:SetOrder(1)
  icon._flowFadeInAG = ag
end

local function PlayFlowFadeIn(icon)
  if not icon then return end
  EnsureFlowFadeIn(icon)
  icon._flowFadeInAG:Stop()
  icon:SetAlpha(0)
  icon._flowFadeInAG:Play()
end

-- Layout + scroll direction. The slot model is 1D: slot 1 = newest (entry end),
-- higher slots = older (toward the exit end). We store a CENTRED axis coordinate
-- per slot and project it to (x,y) per the layout/direction, so horizontal and
-- vertical (and all four scroll directions) share one positioning path.
local function RefreshLayoutCache(ui)
  ui._layout = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) or "HORIZONTAL"
  ui._scrollDir = (addon.GetActionTrackerScroll and addon:GetActionTrackerScroll()) or "LEFT"
end

local function IconAxisToXY(ui, v)
  if ui._layout == "VERTICAL" then
    if ui._scrollDir == "UP" then return 0, v end
    return 0, -v -- DOWN (default for vertical)
  end
  if ui._scrollDir == "RIGHT" then return v, 0 end
  return -v, 0 -- LEFT (default for horizontal)
end

local function PlaceFrameAtAxis(ui, frame, v)
  local x, y = IconAxisToXY(ui, v)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", ui.iconHolder, "CENTER", pixelSnap(x, ui), pixelSnap(y, ui))
end
local PlaceIcon = PlaceFrameAtAxis

-- Centred axis coordinate for a slot (slot 1 most negative -> entry end).
local function SlotAxisCoord(slot, count, step)
  return (slot - (count + 1) / 2) * step
end

local function EnsureFadeGhost(ui)
  if ui._fadeGhost then return ui._fadeGhost end
  local ghost = API.CreateFrame("Frame", nil, ui.iconHolder, "BackdropTemplate")
  ghost:SetSize(pixelSnap(ICON_SIZE, ui), pixelSnap(ICON_SIZE, ui))
  ghost:SetFrameLevel((ui.iconHolder:GetFrameLevel() or 0) + 10)
  ghost:SetAlpha(0)
  ghost:Hide()

  local tex = ghost:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", ghost, "TOPLEFT", 0, 0)
  tex:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", 0, 0)
  tex:SetTexCoord(0, 1, 0, 1)
  ghost.tex = tex

  local ag = ghost:CreateAnimationGroup()
  ag:SetToFinalAlpha(true)
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0)
  a:SetDuration(FLOW_FADE_OUT_DUR)
  a:SetOrder(1)
  ag:SetScript("OnFinished", function()
    ghost:Hide()
  end)
  ghost._fadeOutAG = ag

  ui._fadeGhost = ghost
  return ghost
end

local function PlayFlowFadeOutGhost(ui, texture, baseX)
  if not (ui and texture and texture ~= "") then return end
  if addon.IsPerformanceModeEnabled and addon:IsPerformanceModeEnabled() then return end
  local ghost = EnsureFadeGhost(ui)
  ghost._fadeOutAG:Stop()
  PlaceFrameAtAxis(ui, ghost, baseX or 0)
  ghost.tex:SetTexture(texture)
  ghost:Show()
  ghost:SetAlpha(1)
  ghost._fadeOutAG:Play()
end

local function StopManualSlideDriver(ui)
  if ui and ui.iconHolder then
    ui.iconHolder:SetScript("OnUpdate", nil)
  end
  if ui then
    ui._slidePending = nil
    ui._slideDriver = nil
  end
end
local function ReleaseIconFrame(icon)
  if not icon then return end
  if icon._flowFadeInAG then icon._flowFadeInAG:Stop() end
  icon._animStartX = nil
  icon._animTargetX = nil
  icon._animElapsed = nil
  icon._animating = nil
  icon:Hide()
  icon:SetAlpha(0)
  if icon.tex then
    icon.tex:SetTexture(nil)
    icon.tex:Hide()
  end
  icon:ClearAllPoints()
  icon:SetParent(nil)
end

-- Detect an icon mask the player's UI applies to action buttons (e.g.
-- ActionBarsEnhanced / other skinners add a MaskTexture named IconMask to each
-- ActionButton). Returns atlas, fileID/path AND the mask:icon size ratio, or nil
-- when the icons are plain square. The ratio matters: Blizzard's default mask is
-- a 64px texture whose opaque rounded square fills only its centre, applied at
-- 64px over a 45px icon (ratio ~1.42) so the opaque region lands on the icon. If
-- we instead size the mask to the icon (ratio 1) the opaque centre shrinks and
-- clips the icon well inside the frame (a dark gap). So we replicate the ratio.
local function GetActiveActionIconMask()
  -- Resolved-Native forces the Blizzard default look (ignore any UI skinner);
  -- MODERN / AUTO-with-skinner adopt whatever the player's bars use. Resolved-Native
  -- = literal NATIVE, OR AUTO with no skin provider installed -- so "no skinner"
  -- looks the same whether Native is checked or not (matches GetActionButtonBorder).
  if uiShared.IsResolvedNativeSkin and uiShared.IsResolvedNativeSkin() then
    if _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo("UI-HUD-ActionBar-IconFrame-Mask") then
      return "UI-HUD-ActionBar-IconFrame-Mask", nil, 64 / 45
    end
    return nil, nil, 1 -- atlas absent (e.g. Classic) -> plain square
  end
  -- Tie the icon SHAPE to the BORDER kind so the icon matches its frame: thin-border
  -- skins (ElvUI / EllesmereUI) draw SQUARE icons -> no mask (ignore any vestigial
  -- IconMask their buttons carry, which reports ~0 width). Frame-art skins (Blizzard
  -- default, ABE, and Dominos -- which reuses Blizzard buttons) round their icons, so
  -- adopt the mask below.
  local sb = uiShared.GetActionButtonBorder and uiShared.GetActionButtonBorder()
  if sb and sb.thin then return nil, nil, 1 end

  local G = _G
  local names = { "ActionButton1", "MultiBarBottomLeftButton1", "MultiBarRightButton1" }
  if uiShared.GetActiveActionButton then
    local _, an = uiShared.GetActiveActionButton()
    if an then table.insert(names, 1, an) end
  end
  for _, name in ipairs(names) do
    local btn = G[name]
    local mask = btn and btn.IconMask
    if mask then
      local mw = mask.GetWidth and mask:GetWidth()
      local icon = btn.icon or (btn.GetName and G[(btn:GetName() or "") .. "Icon"])
      local iw = icon and icon.GetWidth and icon:GetWidth()
      local atlas = mask.GetAtlas and mask:GetAtlas()
      local file = (mask.GetTextureFilePath and mask:GetTextureFilePath())
        or (mask.GetTexture and mask:GetTexture())
      if (atlas and atlas ~= "") or (file and file ~= "") then
        -- Real mask:icon ratio when readable; otherwise the Blizzard mask's intrinsic
        -- 64:45 (some buttons report a ~0 width even with an active rounding mask) so
        -- the opaque centre still covers the icon.
        local ratio = (mw and iw and mw > 1 and iw > 0) and (mw / iw) or (64 / 45)
        if atlas and atlas ~= "" then return atlas, nil, ratio end
        return nil, file, ratio
      end
    end
  end
  return nil, nil, 1
end

-- Size a tracker icon's mask the way the action buttons do: centred on the icon
-- texture, scaled by the mask:icon ratio (NOT SetAllPoints) so the mask's opaque
-- region covers the whole visible icon. Called both on creation and after the
-- texture is resized in ApplyBorderThickness. Exposed for frame.lua to reuse.
local function SizeIconMask(b)
  if not (b and b._iconMask and b.tex) then return end
  local ratio = b._iconMaskRatio or 1
  if not ratio or ratio <= 0 then ratio = 1 end
  local w = (b.tex.GetWidth and b.tex:GetWidth()) or 0
  local h = (b.tex.GetHeight and b.tex:GetHeight()) or 0
  if w <= 0 then w = uiShared.ICON_SIZE or 45 end
  if h <= 0 then h = w end
  b._iconMask:ClearAllPoints()
  b._iconMask:SetSize(w * ratio, h * ratio)
  b._iconMask:SetPoint("CENTER", b.tex, "CENTER", 0, 0)
end
uiShared.SizeIconMask = SizeIconMask

-- WoW spell-icon files have a ~7% grey bevel baked into the texture. Action bars
-- (Blizzard and skinners like ActionBarsEnhanced) crop it off with this standard
-- zoom so only the art shows. Used as the fallback when we can't read a stronger
-- crop from the player's bars -- without it the bevel renders as a faint grey
-- inner border around the tracker icon.
local ICON_ZOOM_MIN, ICON_ZOOM_MAX = 0.0703125, 0.9296875

-- Read the icon zoom the player's action buttons use (skinners like
-- ActionBarsEnhanced crop the icon's native edge so the art fills out to the
-- button frame). Returns left, right, top, bottom or nil when no real crop.
local function GetActionIconCrop()
  local G = _G
  local names = { "ActionButton1", "MultiBarBottomLeftButton1", "MultiBarRightButton1" }
  if uiShared.GetActiveActionButton then
    local _, an = uiShared.GetActiveActionButton()
    if an then table.insert(names, 1, an) end
  end
  for _, name in ipairs(names) do
    local btn = G[name]
    local icon = btn and (btn.icon or (btn.GetName and G[(btn:GetName() or "") .. "Icon"]))
    if icon and icon.GetTexCoord then
      local ulx, uly, _, lly, urx = icon:GetTexCoord()
      if ulx and urx and uly and lly then
        local left, right, top, bottom = ulx, urx, uly, lly
        if (right - left) > 0.5 and (bottom - top) > 0.5 and (right - left) < 0.99 then
          return left, right, top, bottom
        end
      end
    end
  end
  return nil
end

-- Mirror the player's action-button icon mask onto a tracker icon so the icons
-- match their UI skin. No-op (plain square) when no mask is in use.
local function ApplyIconMask(b)
  if not (b and b.tex) then return end
  local atlas, file, ratio = GetActiveActionIconMask()
  -- Flag the mask state and force ApplyBorderThickness to re-apply the correct
  -- texture insets (masked icons fill the frame so the border hugs them; unmasked
  -- icons inset by the border thickness).
  b._isMasked = (atlas or file) and true or false
  b._iconMaskRatio = ratio or 1
  b.tex._gsetrackerInset = nil
  if b._isMasked then
    -- Match the player's action-bar icon crop. If the bars report a crop use it;
    -- otherwise fall back to the standard zoom (NOT 0,1) so the icon's baked-in
    -- grey bevel is cropped off the way the action bars do -- leaving it uncropped
    -- showed a faint grey inner border inside the adopted skin frame.
    local l, r, t, btm = GetActionIconCrop()
    if not l then l, r, t, btm = ICON_ZOOM_MIN, ICON_ZOOM_MAX, ICON_ZOOM_MIN, ICON_ZOOM_MAX end
    b.tex:SetTexCoord(l, r, t, btm)
    if not b._iconMask then b._iconMask = b:CreateMaskTexture() end
    b._iconMask:Show()
    if atlas then
      -- false = keep our full-icon size; don't shrink the mask to the atlas size.
      b._iconMask:SetAtlas(atlas, false)
    else
      b._iconMask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    SizeIconMask(b)
    b.tex:AddMaskTexture(b._iconMask)
  else
    -- No mask in use. Still adopt the bars' icon CROP if they crop WITHOUT a mask
    -- (ElvUI crops square at ~0.08 and draws a thin border, no rounded mask) so the
    -- baked grey bevel is removed; only TRUE native (no crop reported) stays at 0,1.
    local l, r, t, btm = GetActionIconCrop()
    if l then
      b.tex:SetTexCoord(l, r, t, btm)
    else
      b.tex:SetTexCoord(0, 1, 0, 1) -- no skinner: exact Blizzard native, no zoom
    end
    if b._iconMask then
      b.tex:RemoveMaskTexture(b._iconMask)
      b._iconMask:Hide()
    end
  end
end

-- Generic version of the above for any icon (e.g. the Assisted Highlight mirror,
-- which is a single frame + texture rather than a pooled tracker icon). Applies
-- the player's action-button icon mask to `iconTex`, owned by `holder`, using the
-- same crop + mask:icon ratio logic. Returns true when a mask is active. The mask
-- handle is stored on holder._gsetActionMask so it survives re-application.
function uiShared.ApplyActionMaskTo(holder, iconTex, explicitW, explicitH)
  if not (holder and iconTex) then return false end
  local atlas, file, ratio = GetActiveActionIconMask()
  local masked = (atlas or file) and true or false
  if masked then
    local l, r, t, btm = GetActionIconCrop()
    if not l then l, r, t, btm = ICON_ZOOM_MIN, ICON_ZOOM_MAX, ICON_ZOOM_MIN, ICON_ZOOM_MAX end
    iconTex:SetTexCoord(l, r, t, btm)
    if not holder._gsetActionMask then holder._gsetActionMask = holder:CreateMaskTexture() end
    local m = holder._gsetActionMask
    m:Show()
    -- Set the atlas/texture only when it changes, and AddMaskTexture only once per
    -- texture (re-running both every frame can leave the mask ineffective). Always
    -- re-size below.
    local key = atlas or file
    if holder._gsetActionMaskKey ~= key then
      holder._gsetActionMaskKey = key
      if atlas then
        m:SetAtlas(atlas, false)
      else
        m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      end
    end
    if holder._gsetActionMaskTarget ~= iconTex then
      holder._gsetActionMaskTarget = iconTex
      iconTex:AddMaskTexture(m)
    end
    ratio = (ratio and ratio > 0) and ratio or 1
    -- Prefer the explicit size (the caller knows the final icon footprint). Reading
    -- iconTex:GetWidth() right after re-anchoring can return a stale/0 value, which
    -- sizes the mask wrong so the icon lands in the mask's flat centre (no rounding).
    local w = explicitW or (iconTex.GetWidth and iconTex:GetWidth()) or 0
    local h = explicitH or (iconTex.GetHeight and iconTex:GetHeight()) or 0
    if not w or w <= 0 then w = uiShared.ICON_SIZE or 45 end
    if not h or h <= 0 then h = w end
    m:ClearAllPoints()
    m:SetSize(w * ratio, h * ratio)
    m:SetPoint("CENTER", iconTex, "CENTER", 0, 0)
  else
    -- No mask: still adopt the bars' icon CROP if they crop without a mask (ElvUI/
    -- EllesmereUI draw square cropped icons); only TRUE native (no crop) stays at 0,1.
    local l, r, t, btm = GetActionIconCrop()
    if l then
      iconTex:SetTexCoord(l, r, t, btm)
    else
      iconTex:SetTexCoord(0, 1, 0, 1)
    end
    if holder._gsetActionMask then
      iconTex:RemoveMaskTexture(holder._gsetActionMask)
      holder._gsetActionMask:Hide()
      holder._gsetActionMaskTarget = nil
      holder._gsetActionMaskKey = nil
    end
  end
  return masked
end

-- Per-icon keybind placement model (matches the Assisted Highlight keybind anchors):
-- corner/centre + inset direction + justification.
local ICON_KB_ANCHORS = {
  TOPRIGHT    = { point = "TOPRIGHT",    jh = "RIGHT",  jv = "TOP",    sx = -1, sy = -1 },
  TOPLEFT     = { point = "TOPLEFT",     jh = "LEFT",   jv = "TOP",    sx =  1, sy = -1 },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", jh = "RIGHT",  jv = "BOTTOM", sx = -1, sy =  1 },
  BOTTOMLEFT  = { point = "BOTTOMLEFT",  jh = "LEFT",   jv = "BOTTOM", sx =  1, sy =  1 },
  CENTER      = { point = "CENTER",      jh = "CENTER", jv = "MIDDLE", sx =  0, sy =  0 },
}

-- Anchor an icon's keybind label to the user-selected corner/centre of the icon.
function UI:PositionIconKeybind(b)
  if not (b and b.keybindText) then return end
  local key = (addon.GetActionTrackerKeybindAnchor and addon:GetActionTrackerKeybindAnchor()) or "TOPRIGHT"
  local a = ICON_KB_ANCHORS[key] or ICON_KB_ANCHORS.TOPRIGHT
  local inset = math.max(2, ICON_SIZE * 0.08)
  b.keybindText:ClearAllPoints()
  b.keybindText:SetPoint(a.point, b, a.point, a.sx * inset, a.sy * inset)
  b.keybindText:SetJustifyH(a.jh)
  b.keybindText:SetJustifyV(a.jv)
end

local function AcquireIconFrame(owner, ui, index, showBorder, thickness)
  ui._iconPool = ui._iconPool or {}
  ui._iconBackdropCache = ui._iconBackdropCache or {}
  local backdrop = ui._iconBackdropCache[thickness]
  if not backdrop then
    backdrop = { bgFile = C.TEXTURE_WHITE8X8 or "Interface/Buttons/WHITE8x8", edgeFile = C.TEXTURE_WHITE8X8 or "Interface/Buttons/WHITE8x8", edgeSize = thickness, insets = { left = thickness, right = thickness, top = thickness, bottom = thickness } }
    ui._iconBackdropCache[thickness] = backdrop
  end
  local b = ui._iconPool[index]
  if not b then
    b = API.CreateFrame("Frame", nil, ui.iconHolder, "BackdropTemplate")
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:ClearAllPoints()
    tex:SetTexCoord(0, 1, 0, 1)
    b.tex = tex
    -- Per-icon keybind label (top-right, Blizzard HotKey style): shows the key the
    -- spell on this icon is bound to. Filled by UpdateIconKeybind.
    b.keybindText = b:CreateFontString(nil, "OVERLAY")
    b.keybindText:SetDrawLayer("OVERLAY", 7)
    b.keybindText:SetJustifyH("RIGHT")
    b.keybindText:Hide()
    ui._iconPool[index] = b
  else
    b:SetParent(ui.iconHolder)
  end

  b:SetSize(pixelSnap(ICON_SIZE, ui), pixelSnap(ICON_SIZE, ui))
  b:SetBackdrop(backdrop)
  b:SetBackdropColor(0, 0, 0, 0)

  local borderR, borderG, borderB = 0, 0, 0
  -- When a thin-border skinner is active (ElvUI/EllesmereUI), freshly-acquired icons
  -- adopt the SKIN's accent colour so they match the rest -- otherwise (depending on
  -- render order) they'd show the user's own border-colour setting instead of the
  -- adopted colour. Falls back to the class/border-colour pickers.
  local skin = uiShared.GetActionButtonBorder and uiShared.GetActionButtonBorder()
  if skin and skin.thin and skin.r then
    borderR, borderG, borderB = skin.r, skin.g, skin.b
  elseif owner and owner.GetActionTrackerUseClassColor and owner:GetActionTrackerUseClassColor() then
    borderR, borderG, borderB = owner:GetClassColorRGB()
  elseif owner and owner.GetActionTrackerBorderColor then
    borderR, borderG, borderB = owner:GetActionTrackerBorderColor()
  end

  if showBorder then
    b:SetBackdropBorderColor(borderR or 0, borderG or 0, borderB or 0, 1)
  else
    b:SetBackdropBorderColor(0, 0, 0, 0)
  end
  b.tex:ClearAllPoints()
  b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", thickness, -thickness)
  b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -thickness, thickness)
  if b.keybindText and UI.PositionIconKeybind then
    UI:PositionIconKeybind(b)
  end
  ApplyIconMask(b)
  b:SetAlpha(0)
  b:Hide()
  b.tex:SetTexture(nil)
  b.tex:Hide()
  return b
end

local function HideUnusedIconPool(ui, keepCount)
  if not (ui and ui._iconPool) then return end
  for i = keepCount + 1, #ui._iconPool do
    ReleaseIconFrame(ui._iconPool[i])
  end
end

local function BorrowScratch(ui, key)
  ui._scratch = ui._scratch or {}
  local t = ui._scratch[key]
  if not t then
    t = {}
    ui._scratch[key] = t
  end
  if API.wipe then
    API.wipe(t)
  else
    for k in pairs(t) do t[k] = nil end
  end
  return t
end

local function BorrowArray(ui, key, count)
  local t = BorrowScratch(ui, key)
  if count and count > 0 then
    clearArray(t, count + 1)
  end
  return t
end

local function TexturesMatch(ui, textures, count)
  local last = ui and ui._lastTextures
  if not last then return false end
  for i = 1, count do
    if last[i] ~= (textures and textures[i] or nil) then
      return false
    end
  end
  return last[count + 1] == nil
end

local function RebuildBaseSlots(ui)
  local count = (ui.icons and #ui.icons) or 0
  local gap = addon:GetIconGap() -- slider 0 = icons touching (flush, no overlap)
  local step = (ICON_SIZE + gap)
  RefreshLayoutCache(ui)
  ui._iconBaseX = ui._iconBaseX or {}
  for slot = 1, count do
    ui._iconBaseX[slot] = SlotAxisCoord(slot, count, step)
  end
end

local function SyncIconLayout(ui)
  if not (ui and ui.icons) then return end
  for slot = 1, #ui.icons do
    local icon = ui.icons[slot]
    if icon then
      local baseX = icon._baseX
      if baseX == nil then baseX = (ui._iconBaseX and ui._iconBaseX[slot]) or 0 end
      icon._animStartX = nil
      icon._animTargetX = nil
      icon._animElapsed = nil
      icon._animating = nil
      PlaceIcon(ui, icon, baseX)
    end
  end
end

local RevealPendingSequenceTextIfReady

local function PostSlideResyncOnUpdate(holder)
  local ui = holder and holder._gsetrackerOwnerUI
  if not ui or not ui._postSlideResyncFrames then
    if holder then holder:SetScript("OnUpdate", nil) end
    return
  end
  ui._postSlideResyncFrames = ui._postSlideResyncFrames - 1
  SyncIconLayout(ui)
  if ui._postSlideResyncFrames <= 0 then
    ui._postSlideResyncFrames = nil
    holder:SetScript("OnUpdate", nil)
    RevealPendingSequenceTextIfReady(ui)
  end
end

local function QueuePostSlideResync(ui)
  if not (ui and ui.iconHolder and ui.icons and #ui.icons > 0) then return end
  ui._postSlideResyncFrames = 2
  ui.iconHolder._gsetrackerOwnerUI = ui
  ui.iconHolder:SetScript("OnUpdate", PostSlideResyncOnUpdate)
end

RevealPendingSequenceTextIfReady = function(ui)
  if not ui then return end
  if ui._slidePending and ui._slidePending > 0 then return end
  if addon and addon.RevealPendingSequenceText then
    addon:RevealPendingSequenceText()
  end
end

local function ManualSlideOnUpdate(holder, elapsed)
  local ui = holder and holder._gsetrackerOwnerUI
  if not ui then
    if holder then holder:SetScript("OnUpdate", nil) end
    return
  end

  local anyAnimating = false
  for i = 1, #(ui.icons or {}) do
    local icon = ui.icons[i]
    if icon and icon._animating then
      anyAnimating = true
      local dur = SCROLL_DUR
      local t = (icon._animElapsed or 0) + elapsed
      icon._animElapsed = t
      local p = dur > 0 and math.min(t / dur, 1) or 1
      local eased = 1 - ((1 - p) * (1 - p))
      local x = (icon._animStartX or 0) + (((icon._animTargetX or 0) - (icon._animStartX or 0)) * eased)
      PlaceIcon(ui, icon, x)
      if p >= 1 then
        icon._animating = nil
        icon._animElapsed = nil
        icon._baseX = icon._animTargetX or icon._baseX or 0
        PlaceIcon(ui, icon, icon._baseX)
        if ui._slidePending and ui._slidePending > 0 then
          ui._slidePending = ui._slidePending - 1
        end
      end
    end
  end

  if not anyAnimating then
    StopManualSlideDriver(ui)
    SyncIconLayout(ui)
    QueuePostSlideResync(ui)
  end
end

local function StartManualSlideDriver(ui)
  if not (ui and ui.iconHolder) then return end
  ui.iconHolder._gsetrackerOwnerUI = ui
  ui.iconHolder:SetScript("OnUpdate", ManualSlideOnUpdate)
end

local function SetIconBaseX(ui, icon, newBaseX, animate)
  animate = animate and not (addon.IsPerformanceModeEnabled and addon:IsPerformanceModeEnabled())
  local oldBaseX = icon._baseX
  if oldBaseX == nil then
    icon._baseX = newBaseX
    PlaceIcon(ui, icon, newBaseX)
    return false
  end
  if not animate or newBaseX == oldBaseX then
    icon._animating = nil
    icon._animElapsed = nil
    icon._baseX = newBaseX
    PlaceIcon(ui, icon, newBaseX)
    return false
  end

  icon._animStartX = oldBaseX
  icon._animTargetX = newBaseX
  icon._animElapsed = 0
  icon._animating = true
  PlaceIcon(ui, icon, oldBaseX)
  return true
end

function UI:RevealPendingSequenceText()
  local ui = self.ui
  if not ui then return end
  if ui._pendingSeqText == nil then return end
  local txt = ui._pendingSeqText
  local key = ui._pendingSeqKey
  ui._pendingSeqText = nil
  ui._pendingSeqKey = nil
  self:SetSequenceText(txt, nil, nil, key)
end

function UI:SetKeybindText(text)
  local ui = self.ui
  if not (ui and ui.keybindText) then return end
  local txt = type(text) == "string" and text or ""
  local rendered = (ui.keybindText.GetText and ui.keybindText:GetText()) or ""
  if ui._lastKeybindText == txt and rendered == txt then return end
  ui._lastKeybindText = txt
  ui.keybindText:SetText((uiShared.FormatLabelForLayout and uiShared.FormatLabelForLayout(txt)) or txt)

  if ui.keybindFrame then
    local cfg = (self.GetElementLayout and self:GetElementLayout("keybindText")) or nil
    local enabled = cfg and cfg.enabled ~= false
    local shouldShow = txt ~= "" and enabled and (ui._lastVisible ~= false)
    if shouldShow then
      ui.keybindFrame:Show()
    else
      ui.keybindFrame:Hide()
    end
  end

  self:_ResizeToContent()
end

-- A two-line (stacked) name centres on the one-line anchor, which drops the bottom line toward the
-- icons. Raise the block by half a line when it's two lines so the BOTTOM line keeps the normal
-- one-line gap above the icons; single line sits at the usual centre.
function UI:_ApplyNameVOffset(rawText)
  local ui = self.ui
  if not (ui and ui.nameText and ui.sequenceTextFrame) then return end
  local twoLine = type(rawText) == "string" and rawText:find("\n", 1, true) ~= nil
  local up = twoLine and math.floor(((uiShared.NAME_FONT_SIZE or 16) * 0.5) + 0.5) or 0
  ui.nameText:ClearAllPoints()
  ui.nameText:SetPoint("CENTER", ui.sequenceTextFrame, "CENTER", 0, up)
end

-- Lay out the name label(s) from the independent "GSE Sequence Name" / "Spell Name" toggles.
--   * SWAP on + BOTH names -> SPLIT: GSE hoisted to the top label (nameText2, above the ModKeys
--     row) while the Spell name stays in the main name slot (below the icons).
--   * otherwise -> a single combined label (GSE on top when both are on; one line each); the top
--     label is hidden.
-- GSE name (addon._gseSeqName) is fed by the GSE bridge; spell name (addon._lastSpellName) by the
-- tracker -- each calls this after updating its own slot.
function UI:RebuildNameDisplay()
  -- A fresh name means a new cast/press: cancel any post-combat fade-out still ramping the name
  -- labels so they snap back to full opacity (covers casting out of combat during the fade window).
  local nui = self.ui
  if nui and nui._namesFading then
    nui._namesFading = false
    if uiShared.CancelFade then
      uiShared.CancelFade(nui.nameText)
      uiShared.CancelFade(nui.nameText2)
      uiShared.CancelFade(nui.keybindText)
    end
  end
  local showSeq = self.GetActionTrackerShowSequenceName and self:GetActionTrackerShowSequenceName()
  local showSpell = self.GetActionTrackerShowSpellName and self:GetActionTrackerShowSpellName()
  local gse = (showSeq and self._gseSeqName) or ""
  local spell = (showSpell and self._lastSpellName) or ""
  local split = self:_NameSplitActive()
  if split then
    self:SetSequenceText(spell, nil, nil, self._activeSeqKey)  -- main slot = Spell (below icons)
  else
    local parts = {}
    if gse ~= "" then parts[#parts + 1] = gse end
    if spell ~= "" then parts[#parts + 1] = spell end
    self:SetSequenceText(table.concat(parts, "\n"), nil, nil, self._activeSeqKey)
  end
  self:_UpdateTopNameLabel(self._gseSeqName, split)
end

-- True when the layout SPLITS into two separate labels: BOTH name toggles on AND both names are
-- currently present. GSE always becomes the OUTER (top) label; Spell stays the inner/main name.
-- (Swap only decides WHERE the top label anchors -- above ModKeys when swapped, else above the
-- inner name -- handled in _UpdateTopNameLabel.)
function UI:_NameSplitActive()
  local showSeq = self.GetActionTrackerShowSequenceName and self:GetActionTrackerShowSequenceName()
  local showSpell = self.GetActionTrackerShowSpellName and self:GetActionTrackerShowSpellName()
  return showSeq and showSpell
    and (self._gseSeqName or "") ~= "" and (self._lastSpellName or "") ~= "" and true or false
end

-- Render the hoisted top GSE label (nameText2): visible ONLY when doSplit (the layout is actually
-- splitting) and the main name is showing; mirrors the main name's colour/alpha. `gseText` is the
-- text (the unlocked example preview passes its sample); r/g/b/a override the colour (else copied).
function UI:_UpdateTopNameLabel(gseText, doSplit, r, g, b, a)
  local ui = self.ui
  if not (ui and ui.nameText2) then return end
  gseText = gseText or self._gseSeqName or ""
  local nr, ng, nb, na
  if ui.nameText and ui.nameText.GetTextColor then nr, ng, nb, na = ui.nameText:GetTextColor() end
  local mainText = (ui.nameText and ui.nameText:GetText()) or ""
  local mainShown = mainText ~= "" and ((na == nil) or (na > 0))
  if doSplit and gseText ~= "" and mainShown then
    -- Anchor the top (GSE) label centred above the nearest upper element: ModKeys when swapped
    -- (names are on opposite sides of the icons), else directly above the inner (Spell) name.
    local swapped = self.GetActionTrackerSwapNameModkeys and self:GetActionTrackerSwapNameModkeys()
    ui.nameText2:ClearAllPoints()
    if swapped and ui.modifiersFrame then
      ui.nameText2:SetPoint("BOTTOM", ui.modifiersFrame, "TOP", 0, 3)
    else
      ui.nameText2:SetPoint("BOTTOM", ui.nameText, "TOP", 0, 3)
    end
    ui.nameText2:SetText((uiShared.FormatLabelForLayout and uiShared.FormatLabelForLayout(gseText)) or gseText)
    ui.nameText2:SetTextColor(r or nr or 1, g or ng or 1, b or nb or 1, a or na or 1)
    ui.nameText2:Show()
  else
    ui.nameText2:SetText("")
    ui.nameText2:Hide()
  end
end

function UI:SetSequenceText(displayName, _, _, seqKey)
  local ui = self.ui
  if not ui then return end
  local txt = (type(displayName) == "string") and displayName or ""
  if txt == "-" or txt == "Sequence Standing By" then txt = "" end

  if ui._slidePending and ui._slidePending > 0 then
    ui._pendingSeqText = txt
    ui._pendingSeqKey = seqKey
    return
  end

  ui._pendingSeqText = nil
  ui._pendingSeqKey = nil

  if txt == "" then
    local renderedName = (ui.nameText and ui.nameText.GetText and ui.nameText:GetText()) or ""
    local renderedKeybind = (ui.keybindText and ui.keybindText.GetText and ui.keybindText:GetText()) or ""
    if ui._lastSeqText == "" and ui._lastSeqKey == nil and ui._accentA == 0 and renderedName == "" and renderedKeybind == "" then return end
    ui._lastSeqText = ""
    ui._lastSeqKey = nil
    ui._accentR, ui._accentG, ui._accentB, ui._accentA = 1, 1, 1, 0
    ui.nameText:SetText("")
    ui.nameText:SetTextColor(1, 1, 1, 0)
    if ui.sequenceTextFrame then ui.sequenceTextFrame:Hide() end
    if ui.nameText2 then ui.nameText2:SetText(""); ui.nameText2:Hide() end
    ui._seqWasVisible = false
    self:SetKeybindText("")
    self:_ResizeToContent()
    return
  end

  local r, g, b = GetSequenceColor(seqKey)
  local liveKeybindText = nil
  if self.GetActiveSequenceBindingText then
    liveKeybindText = self:GetActiveSequenceBindingText(seqKey) or ""
  end

  local renderedName = (ui.nameText and ui.nameText.GetText and ui.nameText:GetText()) or ""
  local renderedNameAlpha = (ui.nameText and ui.nameText.GetAlpha and ui.nameText:GetAlpha()) or 1
  local nameWasVisible = (renderedName ~= "" and (renderedNameAlpha or 0) > 0)
  local renderedKeybind = (ui.keybindText and ui.keybindText.GetText and ui.keybindText:GetText()) or ""
  local keybindInSync = (liveKeybindText == nil) or (renderedKeybind == liveKeybindText)

  if ui._lastSeqText == txt
    and ui._lastSeqKey == seqKey
    and ui._accentR == r
    and ui._accentG == g
    and ui._accentB == b
    and ui._accentA == 1
    and renderedName == txt
    and renderedNameAlpha > 0
    and keybindInSync then
    return
  end

  ui._lastSeqText = txt
  ui._lastSeqKey = seqKey
  ui._accentR, ui._accentG, ui._accentB, ui._accentA = r, g, b, 1
  ui.nameText:SetText((uiShared.FormatLabelForLayout and uiShared.FormatLabelForLayout(txt)) or txt)
  self:_ApplyNameVOffset(txt)
  if liveKeybindText ~= nil then
    self:SetKeybindText(liveKeybindText)
  end
  ui.nameText:SetTextColor(r, g, b, 1)

  if ui.sequenceTextFrame and ui._lastVisible ~= false then
    local seqCfg = (self.GetElementLayout and self:GetElementLayout("sequenceText")) or nil
    local seqEnabled = seqCfg and seqCfg.enabled ~= false
    if seqEnabled then
      ui.sequenceTextFrame:Show()
      -- Slide the name UP whenever it appears or changes (reaching here means the
      -- text genuinely changed -- SetSequenceText early-returns when unchanged).
      if self.SlideSequenceNameIn then self:SlideSequenceNameIn() end
      ui._seqWasVisible = true
    end
  end

  self:UpdateModifiers(true)
  self:_ResizeToContent()
end

function UI:_GetIconLayoutSignature()
  local ui = self.ui
  if not ui then return nil end

  return table.concat({
    tostring((self.GetEditModePreviewIconCount and self:GetEditModePreviewIconCount()) or self:GetIconCount()),
    tostring(self:GetIconGap()),
    tostring(self:GetBorderThickness()),
    tostring(self:IsBorderEnabled() and 1 or 0),
    tostring(string.format("%.2f", self:GetDesiredScale() or 1)),
    tostring(uiShared.ICON_SIZE or ICON_SIZE),
    tostring((addon.GetActionTrackerLayout and addon:GetActionTrackerLayout()) or "HORIZONTAL"),
    tostring((addon.GetActionTrackerScroll and addon:GetActionTrackerScroll()) or "LEFT"),
    tostring((addon.GetSkin and addon:GetSkin()) or "AUTO"),
    tostring(ui._lastVisible == true),
  }, "|")
end

-- Placement preview: while the Action Tracker is unlocked and the player is out
-- of combat, show the chosen number of icons (sample textures) so the row can be
-- positioned. Requires the tracker to be enabled.
function UI:IsEditModePreviewActive()
  -- Blizzard Edit Mode (addon._editingOptions) counts as "editing": show the example icons even when
  -- the frames are Locked, so the Action Tracker is visible/positionable. Outside Edit Mode, the
  -- unlocked preview still requires the frames to be unlocked.
  local editing = addon and addon._editingOptions
  if not editing and self.IsLocked and self:IsLocked() then return false end
  if self.IsEnabled and not self:IsEnabled() then return false end

  local ui = self.ui
  local inCombat
  if ui and ui._combatState ~= nil then
    inCombat = ui._combatState == true
  else
    inCombat = (API.InCombatLockdown and API.InCombatLockdown()) or false
  end
  return not inCombat
end

function UI:GetEditModePreviewIconCount()
  local count = (self.GetIconCount and self:GetIconCount()) or 4
  if self:IsEditModePreviewActive() and count < 4 then
    return 4
  end
  return count
end

function UI:ApplyEditModeIconPreview(force)
  local ui = self.ui
  if not (ui and ui.icons) then return false end

  local active = self:IsEditModePreviewActive()
  local targetCount = (self.GetEditModePreviewIconCount and self:GetEditModePreviewIconCount()) or #ui.icons

  if #ui.icons ~= targetCount and self.RebuildIcons then
    return self:RebuildIcons(true)
  end

  if not active then
    if not ui._editModePreviewIconsActive and not force then
      return false
    end

    ui._editModePreviewIconsActive = false
    local restored = false
    local lastTextures = ui._lastTextures
    if lastTextures then
      for i = 1, #ui.icons do
        local tex = lastTextures[i]
        if tex and tex ~= "" then
          restored = true
          break
        end
      end
    end

    if restored and self.SetIconRow then
      local restoreTextures = BorrowArray(ui, "restoreTextures", #ui.icons)
      copyArrayInto(restoreTextures, lastTextures, #ui.icons)
      clearArray(ui._lastTextures, 1)
      self:SetIconRow(restoreTextures)
    else
      for i = 1, #ui.icons do
        local btn = ui.icons[i]
        if btn then
          btn:SetAlpha(0)
          btn:Hide()
          if btn.tex then
            btn.tex:SetTexture(nil)
            btn.tex:Hide()
          end
        end
      end
    end

    return true
  end

  if self.ApplyBorderThickness then
    self:ApplyBorderThickness()
  end

  local changed = force or not ui._editModePreviewIconsActive
  ui._editModePreviewIconsActive = true
  for i = 1, #ui.icons do
    local btn = ui.icons[i]
    if btn then
      local texture = GetEditModePreviewTexture(i)
      if btn.tex then
        if btn.tex:GetTexture() ~= texture then
          btn.tex:SetTexture(texture)
          changed = true
        end
        btn.tex:Show()
      end
      if not btn:IsShown() or (btn.GetAlpha and math.abs((btn:GetAlpha() or 0) - 1) > 0.001) then
        changed = true
      end
      btn:SetAlpha(1)
      btn:Show()
    end
  end

  return changed
end

function UI:RebuildIcons(force)
  local ui = self.ui
  if not ui then return false end

  -- Track the live action-button size as the base (updates the shared upvalue
  -- used by all the icon layout functions in this file).
  if uiShared.RefreshIconSize then uiShared.RefreshIconSize(ui.iconHolder or ui) end
  ICON_SIZE = uiShared.ICON_SIZE or ICON_SIZE

  local layoutSig = self._GetIconLayoutSignature and self:_GetIconLayoutSignature() or nil
  if not force and ui._lastIconRebuildSig and layoutSig == ui._lastIconRebuildSig then
    return false
  end
  ui._lastIconRebuildSig = layoutSig

  ui:SetScale(self:GetDesiredScale())
  local function PS(v) return pixelSnap(v, ui) end
  ui._lastTextures = ui._lastTextures or {}
  ui._preservedTextures = copyArrayInto(ui._preservedTextures or {}, ui._lastTextures, #ui._lastTextures)
  local preserved = ui._preservedTextures

  StopManualSlideDriver(ui)
  ui.icons = ui.icons or {}
  ui._iconBaseX = ui._iconBaseX or {}
  clearArray(ui.icons, 1)
  clearArray(ui._iconBaseX, 1)

  local count = (self.GetEditModePreviewIconCount and self:GetEditModePreviewIconCount()) or self:GetIconCount()
  local gap = self:GetIconGap() -- slider 0 = icons touching (flush, no overlap)
  local step = (ICON_SIZE + gap)

  RefreshLayoutCache(ui)
  -- Size the holder to the row's long axis (wide for horizontal, tall for vertical).
  local rowLen = iconRowWidth(count)
  if ui._layout == "VERTICAL" then
    ui.iconHolder:SetSize(PS(ICON_SIZE), PS(rowLen))
  else
    ui.iconHolder:SetSize(PS(rowLen), PS(ICON_SIZE))
  end
  if self.UpdateActionTrackerIconRowAnchor then
    self:UpdateActionTrackerIconRowAnchor()
  end

  local showBorder = self:IsBorderEnabled()
  local thickness = self:GetBorderThickness()

  for i = 1, count do
    local b = AcquireIconFrame(self, ui, i, showBorder, thickness)
    ui._iconBaseX[i] = SlotAxisCoord(i, count, step)
    b._baseX = ui._iconBaseX[i]
    PlaceIcon(ui, b, b._baseX)
    ui.icons[i] = b
  end
  HideUnusedIconPool(ui, count)

  RebuildBaseSlots(ui)
  self:_AlignModsToIcons()
  self:_ResizeToContent()

  local hasAny = false
  for i = 1, count do if preserved[i] then hasAny = true; break end end
  clearArray(ui._lastTextures, 1)

  if hasAny then
    local reapplied = BorrowArray(ui, "reappliedTextures", count)
    copyArrayInto(reapplied, preserved, count)
    copyArrayInto(ui._lastTextures, preserved, count)
    self:SetIconRow(reapplied)
  else
    for i = 1, count do
      local btn = ui.icons[i]
      btn:Hide(); btn:SetAlpha(0)
      if btn.tex then btn.tex:SetTexture(nil) end
    end
  end

  if self.ApplyBorderThickness then
    self:ApplyBorderThickness()
  end

  if self.ApplyEditModeIconPreview and self:ApplyEditModeIconPreview(true) then
    return true
  end

  return true
end

-- NOTE: the AH-suggestion proc effect was moved OFF the main row to a dedicated
-- centered "proc" icon (ui/modkey_stack.lua: ShowProcCenterIcon) so the row stays
-- undisturbed. The tracker calls addon:ShowProcCenterIcon(texture) on a match.

-- Set an icon's keybind label from its texture (the key the spell is bound to, GSE or
-- Blizzard). Uses the Keybind Font so that setting finally has a visible target.
local function UpdateIconKeybind(b, texture)
  if not (b and b.keybindText) then return end
  local key = (texture and texture ~= "" and addon.GetTextureKeybindText and addon:GetTextureKeybindText(texture)) or nil
  if key and key ~= "" then
    local name = addon.GetKeybindFontName and addon:GetKeybindFontName()
    local path = (addon.GetFontPathByName and addon:GetFontPathByName(name)) or STANDARD_TEXT_FONT
    local size = (addon.GetKeybindFontSize and addon:GetKeybindFontSize()) or 10
    local flags = "OUTLINE"
    -- Adopt the action-bar keybind (HotKey) font face/outline when a UI skin is in
    -- use, mirroring ApplyFontFaces; size stays user-controlled. Forced-native or no
    -- readable region -> keep the configured keybind font.
    if uiShared.GetActionButtonFont then
      local hp, _, hf = uiShared.GetActionButtonFont("hotkey")
      if hp then path, flags = hp, hf or "" end
    end
    if not b.keybindText:SetFont(path, size, flags) then
      b.keybindText:SetFont(STANDARD_TEXT_FONT, size, flags)
    end
    b.keybindText:SetText(key)
    b.keybindText:Show()
  else
    b.keybindText:SetText("")
    b.keybindText:Hide()
  end
end

function UI:SetIconRow(textures)
  local ui = self.ui
  if not ui or not ui.icons then return end

  local count = #ui.icons
  ui._lastTextures = ui._lastTextures or {}
  if TexturesMatch(ui, textures, count) then
    self:RefreshPressedIndicator()
    return false
  end
  local prevTextures = BorrowArray(ui, "prevTextures", count)
  copyArrayInto(prevTextures, ui._lastTextures, count)
  local hadVisibleBefore = false
  local hasVisibleNow = false
  for i = 1, count do
    if prevTextures[i] and prevTextures[i] ~= "" then hadVisibleBefore = true; break end
  end

  local sourceSlotForTarget = BorrowArray(ui, "sourceSlotForTarget", count)
  local isFrontQueueShift = true
  for i = 1, count do
    local tex = textures and textures[i] or nil
    if tex and tex ~= "" then hasVisibleNow = true end
  end

  if hadVisibleBefore and hasVisibleNow then
    for i = 2, count do
      local tex = textures and textures[i] or nil
      local prev = prevTextures[i - 1]
      if tex ~= prev then
        isFrontQueueShift = false
        break
      end
    end
  else
    isFrontQueueShift = false
  end

  if isFrontQueueShift then
    for i = 2, count do
      local tex = textures and textures[i] or nil
      local prev = prevTextures[i - 1]
      if tex and tex ~= "" and prev and prev ~= "" then
        sourceSlotForTarget[i] = i - 1
      end
    end
  else
    local oldSlotsByTexture = BorrowScratch(ui, "oldSlotsByTexture")
    ui._oldSlotBuckets = ui._oldSlotBuckets or {}
    local oldSlotBuckets = ui._oldSlotBuckets
    local oldSlotBucketCount = 0
    for i = 1, count do
      local prev = prevTextures[i]
      if prev and prev ~= "" then
        local bucket = oldSlotsByTexture[prev]
        if not bucket then
          oldSlotBucketCount = oldSlotBucketCount + 1
          bucket = oldSlotBuckets[oldSlotBucketCount]
          if bucket then
            clearArray(bucket, 1)
          else
            bucket = {}
            oldSlotBuckets[oldSlotBucketCount] = bucket
          end
          bucket.first = 1
          oldSlotsByTexture[prev] = bucket
        end
        bucket[#bucket + 1] = i
      end
    end

    for i = 1, count do
      local tex = textures and textures[i] or nil
      if tex and tex ~= "" then
        local bucket = oldSlotsByTexture[tex]
        local first = bucket and bucket.first
        if first and first <= #bucket then
          sourceSlotForTarget[i] = bucket[first]
          bucket[first] = nil
          bucket.first = first + 1
        end
      end
    end

    for i = 1, oldSlotBucketCount do
      local bucket = oldSlotBuckets[i]
      if bucket then
        bucket.first = nil
        clearArray(bucket, 1)
      end
    end
  end

  for i = 1, count do
    local btn = ui.icons[i]
    local tex = textures and textures[i] or nil

    if tex and tex ~= "" then
      btn.tex:SetTexture(tex)
      btn.tex:Show()
      btn:SetAlpha(1)
      btn:Show()
      UpdateIconKeybind(btn, tex)
    else
      btn.tex:SetTexture(nil)
      btn.tex:Hide()
      btn:SetAlpha(0)
      btn:Hide()
      UpdateIconKeybind(btn, nil)
    end
    ui._lastTextures[i] = tex
  end
  clearArray(ui._lastTextures, count + 1)

  RebuildBaseSlots(ui)
  local removedTexture = nil
  if isFrontQueueShift then
    removedTexture = prevTextures[count]
  end
  local shouldAnimate = hadVisibleBefore and hasVisibleNow and not (addon.IsPerformanceModeEnabled and addon:IsPerformanceModeEnabled())
  local pending = 0
  for i = 1, count do
    local btn = ui.icons[i]
    local tex = textures and textures[i] or nil
    local targetBaseX = ui._iconBaseX[i] or 0
    local sourceSlot = sourceSlotForTarget[i]

    if tex and tex ~= "" and shouldAnimate and sourceSlot and sourceSlot ~= i then
      btn._baseX = ui._iconBaseX[sourceSlot] or btn._baseX or targetBaseX
      if SetIconBaseX(ui, btn, targetBaseX, true) then
        pending = pending + 1
      end
    elseif tex and tex ~= "" and shouldAnimate and isFrontQueueShift and i == 1 and hadVisibleBefore then
      -- Enter from one step beyond slot 1 (the entry end), in the scroll direction.
      btn._baseX = (0 - (count + 1) / 2) * (ICON_SIZE + self:GetIconGap())
      if SetIconBaseX(ui, btn, targetBaseX, true) then
        pending = pending + 1
      end
      PlayFlowFadeIn(btn)
    else
      SetIconBaseX(ui, btn, targetBaseX, false)
    end
  end

  if removedTexture and removedTexture ~= "" then
    PlayFlowFadeOutGhost(ui, removedTexture, ui._iconBaseX[count] or 0)
  end

  if pending > 0 then
    ui._slidePending = pending
    StartManualSlideDriver(ui)
  else
    ui._slidePending = nil
    SyncIconLayout(ui)
    RevealPendingSequenceTextIfReady(ui)
  end

  self:RefreshPressedIndicator()
end

local function ResetRuntimeSpellHistoryState(ui)
  if not ui then return end

  ui._castsInCombat = 0
  ui._lastTextures = ui._lastTextures or {}
  clearArray(ui._lastTextures, 1)

  local recent = Tracker._recentIcons or addon._recentIcons or {}
  if API.wipe then
    API.wipe(recent)
  else
    clearArray(recent, 1)
  end

  Tracker._recentIcons = recent
  addon._recentIcons = recent
  Tracker._recentIconCount = 0
  addon._recentIconCount = 0
  Tracker._lastSpellID = false
  Tracker._lastSpellAt = 0
end

function UI:ClearSpellHistory()
  local ui = self.ui
  if not (ui and ui.icons) then return end
  ResetRuntimeSpellHistoryState(ui)
  if self.ClearModkeyStacks then self:ClearModkeyStacks() end
  if self.StopProcCenterIcon then self:StopProcCenterIcon() end
  if self.ApplyEditModeIconPreview and self:IsEditModePreviewActive() then
    StopManualSlideDriver(ui)
    ui._postSlideResyncFrames = nil
    if ui.iconHolder then
      ui.iconHolder:SetScript("OnUpdate", nil)
    end
    self:ApplyEditModeIconPreview(true)
    self:RefreshPressedIndicator(true)
    return
  end
  StopManualSlideDriver(ui)
  ui._postSlideResyncFrames = nil
  if ui.iconHolder then
    ui.iconHolder:SetScript("OnUpdate", nil)
  end
  for i = 1, #ui.icons do
    local btn = ui.icons[i]
    if btn and btn.tex then
      btn.tex:SetTexture("")
      btn.tex:SetColorTexture(0, 0, 0, 0)
      btn.tex:Hide()
    end
    if btn then btn:SetAlpha(0); btn:Hide() end
  end
  self:RefreshPressedIndicator(true)
end
