local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local uiShared = addon._ui or {}
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)

-- Bundled custom match sounds (media/bloop.mp3 + media/sounds/*.mp3). Registered with LibSharedMedia so
-- the AH Match dropdown + PlayAHMatchSound (the LSM:Fetch path) can use them by name. The {value,text}
-- list is exposed as _G.GSETracker_BundledSounds for the options dropdown to consume.
local BUNDLED_SOUNDS = {
  { name = "Bloop",        file = [[Interface\AddOns\GSE_Tracker\media\bloop.mp3]] },
  { name = "Analog",       file = [[Interface\AddOns\GSE_Tracker\media\sounds\analog.mp3]] },
  { name = "Clap",         file = [[Interface\AddOns\GSE_Tracker\media\sounds\clap.mp3]] },
  { name = "Cymbal",       file = [[Interface\AddOns\GSE_Tracker\media\sounds\cym.mp3]] },
  { name = "Distortion",   file = [[Interface\AddOns\GSE_Tracker\media\sounds\distortion.mp3]] },
  { name = "Drum",         file = [[Interface\AddOns\GSE_Tracker\media\sounds\drum.mp3]] },
  { name = "Drum 2",       file = [[Interface\AddOns\GSE_Tracker\media\sounds\drum 2.mp3]] },
  { name = "Fight",        file = [[Interface\AddOns\GSE_Tracker\media\sounds\fight.mp3]] },
  { name = "Kick 1",       file = [[Interface\AddOns\GSE_Tracker\media\sounds\kick 1.mp3]] },
  { name = "Kick 2",       file = [[Interface\AddOns\GSE_Tracker\media\sounds\kick 2.mp3]] },
  { name = "Korg",         file = [[Interface\AddOns\GSE_Tracker\media\sounds\korg.mp3]] },
  { name = "Notification", file = [[Interface\AddOns\GSE_Tracker\media\sounds\notification.mp3]] },
  { name = "Snare",        file = [[Interface\AddOns\GSE_Tracker\media\sounds\snare.mp3]] },
  { name = "Snare Drum",   file = [[Interface\AddOns\GSE_Tracker\media\sounds\snare drum.mp3]] },
  { name = "Sound Effect", file = [[Interface\AddOns\GSE_Tracker\media\sounds\sound effect.mp3]] },
  { name = "Success",      file = [[Interface\AddOns\GSE_Tracker\media\sounds\success.mp3]] },
  { name = "Swoosh",       file = [[Interface\AddOns\GSE_Tracker\media\sounds\swoosh.mp3]] },
  { name = "Swoosh 2",     file = [[Interface\AddOns\GSE_Tracker\media\sounds\swoosh 2.mp3]] },
  { name = "Trip",         file = [[Interface\AddOns\GSE_Tracker\media\sounds\trip.mp3]] },
}
_G.GSETracker_BundledSounds = _G.GSETracker_BundledSounds or {}
for _, s in ipairs(BUNDLED_SOUNDS) do
  if LSM and LSM.Register then LSM:Register("sound", s.name, s.file) end
  _G.GSETracker_BundledSounds[#_G.GSETracker_BundledSounds + 1] = { value = s.name, text = s.name }
end

-- ── ModKey burst stack ───────────────────────────────────────────────────────
-- When abilities are fired WHILE a modifier is held, they also feed a centered,
-- z-ordered "stack" overlay (separate from the main sliding row, which keeps
-- recording everything). The newest icon grows in at the centre on top at full
-- opacity; older ones cascade slightly DOWN and fade with depth; the oldest beyond
-- the user's icon count drops off. Each modifier combo (LShift, RCtrl, LShift+RCtrl,
-- ...) keeps its OWN rolling history; the centre shows the combo currently in use.
-- A NON-modkey cast clears the stacks and the main row carries on alone.

local STACK_OFFSET_Y = 0       -- icons stack directly on top of each other (same slot)
local ALPHA_STEP     = 0.22    -- alpha lost per depth step (hidden behind top when offset 0)
local MIN_ALPHA      = 0.15    -- floor so the oldest is faint but visible
local GROW_FROM      = 0.55    -- newest icon scales up from this to 1.0
local GROW_DUR       = 0.14
local FADE_OUT_DUR   = 0.18
local ICON_SCALE     = 1.25    -- modkey icons are 25% larger than the main row
local WHITE8X8       = C.TEXTURE_WHITE8X8 or "Interface\\Buttons\\WHITE8x8"

-- Build the icon border EXACTLY like the main Action Tracker row (AcquireIconFrame):
-- same backdrop, same thickness, same colour source -- so it matches everything else.
local backdropCache = {}
local function GetBorderBackdrop(thickness)
  local b = backdropCache[thickness]
  if not b then
    b = { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = thickness,
          insets = { left = thickness, right = thickness, top = thickness, bottom = thickness } }
    backdropCache[thickness] = b
  end
  return b
end
-- Apply the SAME border every other icon uses: the action-button frame art from
-- GetActionButtonBorder (Blizzard native default, or the adopted UI skin), mirroring
-- frame.lua's main-row logic exactly. Returns the icon footprint to mask.
local function ApplyStackBorder(self, f, sw, sh)
  local skinBorder = uiShared.GetActionButtonBorder and uiShared.GetActionButtonBorder() or nil
  -- Only the frame-ART case draws the adopted texture; a thin-border skin (ElvUI,
  -- skinBorder.thin -- no atlas/file) falls through to the coloured-square border
  -- below, which already renders a thin border.
  if skinBorder and (skinBorder.atlas or skinBorder.file) then
    if f.SetBackdrop then f:SetBackdrop(nil) end
    local bw = sw * (skinBorder.wRatio or 1)
    local bh = sh * (skinBorder.hRatio or 1)
    if not f._skinBorder then f._skinBorder = f:CreateTexture(nil, "OVERLAY") end
    local sb = f._skinBorder
    if skinBorder.atlas then
      sb:SetAtlas(skinBorder.atlas, false)
    else
      sb:SetTexture(skinBorder.file)
      if skinBorder.coords then sb:SetTexCoord(unpack(skinBorder.coords)) end
    end
    sb:ClearAllPoints()
    sb:SetSize(bw, bh)
    sb:SetPoint("CENTER", f, "CENTER", 0, 0)
    sb:SetVertexColor(1, 1, 1)
    sb:Show()
    -- Keep the icon at its OWN size; the frame art (sb, drawn larger at the skin's
    -- real ratio) frames it. Scaling the icon up to the frame footprint ballooned it
    -- for ornate frames like ActionBarsEnhanced. Shave 0.5px/side so it tucks inside.
    f.tex:ClearAllPoints()
    f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 0.5, -0.5)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -0.5, 0.5)
    return sw, sh
  end

  -- Thin-border skin (ElvUI/EllesmereUI) OR coloured-square fallback (Classic).
  if f._skinBorder then f._skinBorder:Hide() end
  local thinSkin = skinBorder and skinBorder.thin
  local thickness, r, g, b, showBorder
  if thinSkin then
    -- Match the main row's thin border: the SKIN's thickness (1px) + accent colour.
    -- Using the tracker's own thickness here drew the border a full thickness OUT
    -- from the icon, so the border looked "larger than the icon".
    thickness = (skinBorder.thickness and skinBorder.thickness > 0) and skinBorder.thickness or 1
    r, g, b = skinBorder.r, skinBorder.g, skinBorder.b
    showBorder = true
  else
    thickness = (self.GetBorderThickness and self:GetBorderThickness()) or 1
    if thickness < 1 then thickness = 1 end
    showBorder = (self.IsBorderEnabled == nil) or self:IsBorderEnabled()
    r, g, b = 0, 0, 0
    if self.GetActionTrackerUseClassColor and self:GetActionTrackerUseClassColor() then
      r, g, b = self:GetClassColorRGB()
    elseif self.GetActionTrackerBorderColor then
      r, g, b = self:GetActionTrackerBorderColor()
    end
  end
  if f.SetBackdrop then
    f:SetBackdrop(GetBorderBackdrop(thickness))
    f:SetBackdropColor(0, 0, 0, 0)
    if showBorder then
      f:SetBackdropBorderColor(r or 0, g or 0, b or 0, 1)
    else
      f:SetBackdropBorderColor(0, 0, 0, 0)
    end
  end
  -- Thin skin: the icon FILLS the frame so the 1px border hugs it (insetting by the
  -- thickness leaves a gap = "border larger than icon"). Otherwise inset as before.
  local texInset = thinSkin and 0 or thickness
  f.tex:ClearAllPoints()
  f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", texInset, -texInset)
  f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -texInset, texInset)
  return sw - texInset * 2, sh - texInset * 2
end

local function Now()
  return (API.GetTime and API.GetTime()) or (_G.GetTime and _G.GetTime()) or 0
end

local function StackCount(self)
  local n = (self.GetIconCount and self:GetIconCount()) or 4
  if n < 1 then n = 1 end
  return n
end

local function EnsureContainer(self)
  local ui = self.ui
  if not (ui and ui.content) then return nil end
  if ui._modkeyContainer then return ui._modkeyContainer end

  local container = API.CreateFrame("Frame", nil, ui.content)
  container:SetSize(1, 1)
  container:SetPoint("CENTER", ui.iconHolder or ui.content, "CENTER", 0, 0)
  -- Draw above the main icon row.
  container:SetFrameLevel((ui.content:GetFrameLevel() or 0) + 30)
  ui._modkeyContainer = container
  ui._modkeyFrames = {}
  ui._modkeyStacks = {}     -- [modString] = { newestTexture, ... }
  ui._modkeyActive = nil
  return container
end

local function AcquireStackFrame(self, index)
  local ui = self.ui
  local container = ui._modkeyContainer
  ui._modkeyFrames = ui._modkeyFrames or {}
  local f = ui._modkeyFrames[index]
  if f then return f end

  f = API.CreateFrame("Frame", nil, container, "BackdropTemplate")
  f:SetFrameLevel((container:GetFrameLevel() or 0) + 1)
  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetTexCoord(0, 1, 0, 1)
  f.tex = tex
  f:Hide()
  f:SetAlpha(0)
  ui._modkeyFrames[index] = f
  return f
end

-- Animation driver: handles the grow-in of the newest icon and fade-out on clear.
local function StackOnUpdate(driver)
  local self = driver._self
  local ui = self and self.ui
  if not (ui and ui._modkeyFrames) then
    driver:SetScript("OnUpdate", nil)
    return
  end

  local now = Now()
  local anyActive = false

  for i = 1, #ui._modkeyFrames do
    local f = ui._modkeyFrames[i]
    if f then
      if f._growStart then
        local t = (now - f._growStart) / GROW_DUR
        if t >= 1 then
          f._growStart = nil
          f:SetScale(1)
          f:SetAlpha(f._targetAlpha or 1)
        else
          anyActive = true
          local e = 1 - (1 - t) * (1 - t)         -- ease-out
          f:SetScale(GROW_FROM + (1 - GROW_FROM) * e)
          f:SetAlpha((f._targetAlpha or 1) * e)
        end
      elseif f._fadeStart then
        local t = (now - f._fadeStart) / FADE_OUT_DUR
        if t >= 1 then
          f._fadeStart = nil
          f:SetAlpha(0)
          f:Hide()
          if f.tex then f.tex:SetTexture(nil) end
        else
          anyActive = true
          f:SetAlpha((f._fadeFrom or 1) * (1 - t))
        end
      end
    end
  end

  if not anyActive then driver:SetScript("OnUpdate", nil) end
end

local function StartDriver(self)
  local ui = self.ui
  local driver = ui._modkeyStackDriver
  if not driver then
    driver = (API.CreateFrame or _G.CreateFrame)("Frame")
    ui._modkeyStackDriver = driver
  end
  driver._self = self
  driver:SetScript("OnUpdate", StackOnUpdate)
end

-- Lay the visible frames out for the active combo's history.
local function RenderStack(self, animateTop)
  local ui = self.ui
  local container = ui._modkeyContainer
  if not container then return end

  local size = uiShared.PixelSnap((uiShared.ICON_SIZE or 45) * ICON_SCALE, ui)
  local count = StackCount(self)
  local list = (ui._modkeyActive and ui._modkeyStacks[ui._modkeyActive]) or {}

  for i = 1, count do
    local f = AcquireStackFrame(self, i)
    local tex = list[i]
    if tex then
      f:SetSize(size, size)
      local mw, mh = ApplyStackBorder(self, f, size, size)
      if uiShared.ApplyActionMaskTo then
        uiShared.ApplyActionMaskTo(f, f.tex, mw, mh)
      end
      f.tex:SetTexture(tex)
      f.tex:Show()
      f:ClearAllPoints()
      f:SetPoint("CENTER", container, "CENTER", 0, (i - 1) * STACK_OFFSET_Y)
      f:SetFrameLevel((container:GetFrameLevel() or 0) + (count - i) + 1) -- newest highest
      local targetAlpha = math.max(MIN_ALPHA, 1 - (i - 1) * ALPHA_STEP)
      f._targetAlpha = targetAlpha
      f._fadeStart = nil
      if i == 1 and animateTop then
        f._growStart = Now()
        f:SetScale(GROW_FROM)
        f:SetAlpha(0)
      else
        f._growStart = nil
        f:SetScale(1)
        f:SetAlpha(targetAlpha)
      end
      f:Show()
    elseif f:IsShown() then
      f._growStart = nil
      f:SetScale(1)
      f:SetAlpha(0)
      f:Hide()
      if f.tex then f.tex:SetTexture(nil) end
    end
  end

  -- Hide any frames left over from a previously larger icon count.
  for i = count + 1, #(ui._modkeyFrames or {}) do
    local f = ui._modkeyFrames[i]
    if f and f:IsShown() then
      f._growStart = nil
      f._fadeStart = nil
      f:SetScale(1)
      f:SetAlpha(0)
      f:Hide()
      if f.tex then f.tex:SetTexture(nil) end
    end
  end

  if animateTop then StartDriver(self) end
end

-- Push one modkey-fired ability into its combo stack and (re)render.
function UI:PushModkeyStackIcon(texture, modString)
  if not texture or type(modString) ~= "string" or modString == "" then return end
  if not EnsureContainer(self) then return end
  local ui = self.ui

  ui._modkeyStacks[modString] = ui._modkeyStacks[modString] or {}
  local stack = ui._modkeyStacks[modString]
  table.insert(stack, 1, texture)              -- newest first
  local count = StackCount(self)
  for i = #stack, count + 1, -1 do stack[i] = nil end

  ui._modkeyActive = modString
  RenderStack(self, true)
end

-- A non-modkey cast happened: fade the stacks out and forget the histories so the
-- main row carries on alone (the user picked "resume on next non-modkey cast").
function UI:ClearModkeyStacks()
  local ui = self.ui
  if not (ui and ui._modkeyFrames) then return end
  ui._modkeyActive = nil
  if ui._modkeyStacks then
    for k in pairs(ui._modkeyStacks) do ui._modkeyStacks[k] = nil end
  end
  local fading = false
  for i = 1, #ui._modkeyFrames do
    local f = ui._modkeyFrames[i]
    if f and f:IsShown() then
      f._growStart = nil
      f._fadeFrom = f:GetAlpha() or 1
      f._fadeStart = Now()
      fading = true
    end
  end
  if fading then StartDriver(self) end
end

-- ── Center proc icon ─────────────────────────────────────────────────────────
-- AH-suggestion match: show the matched spell's icon CENTRE as a transient "proc"
-- that grows in, glows, holds, and fades -- leaving the main row undisturbed. The
-- frame is centred on the container with ZERO offset, so SetScale grows cleanly
-- from its own centre (no anchor-offset drift).
local PROC_CENTER_DUR = 0.70
local procCenterDriver

local function ProcCenterOnUpdate(driver, elapsed)
  local f = driver._frame
  if not f then driver:SetScript("OnUpdate", nil); return end
  f._pcT = (f._pcT or 0) + (elapsed or 0)
  local t = f._pcT / PROC_CENTER_DUR
  if t >= 1 then
    f:SetScale(1); f:SetAlpha(0); f:Hide()
    if f._procGlow then f._procGlow:SetAlpha(0) end
    f._pcT = nil; driver._frame = nil; driver:SetScript("OnUpdate", nil)
    return
  end
  -- Grow in over the first 30% (ease-out, 0.6 -> 1.0), then settle.
  local gi = math.min(t / 0.30, 1)
  local eased = 1 - (1 - gi) * (1 - gi)
  f:SetScale(0.6 + 0.4 * eased)
  -- Alpha: fade in (0-0.12), hold, fade out (0.6-1.0).
  local a
  if t < 0.12 then a = t / 0.12
  elseif t > 0.60 then a = 1 - (t - 0.60) / 0.40
  else a = 1 end
  f:SetAlpha(a)
  if f._procGlow then f._procGlow:SetAlpha(a) end
end

local function EnsureProcCenterFrame(self)
  local container = EnsureContainer(self)
  if not container then return nil end
  local ui = self.ui
  if ui._procCenterFrame then return ui._procCenterFrame end
  local f = API.CreateFrame("Frame", nil, container, "BackdropTemplate")
  f:SetFrameLevel((container:GetFrameLevel() or 0) + 25) -- above the modkey stack
  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetTexCoord(0, 1, 0, 1)
  f.tex = tex
  -- Proc "border glow": a thin frame just outside the icon with a glowing edge,
  -- locked to the icon footprint (anchored to f, +2px) so it always follows the
  -- icon's size -- a BORDER glow, not a fill over the whole icon. Pulsed via
  -- f.glow:SetAlpha in ProcCenterOnUpdate.
  local gf = API.CreateFrame("Frame", nil, f, "BackdropTemplate")
  gf:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
  gf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
  gf:SetFrameLevel((f:GetFrameLevel() or 0) + 1)
  gf:SetBackdrop({ edgeFile = WHITE8X8, edgeSize = 3, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
  gf:SetBackdropBorderColor(1, 0.85, 0.25, 1) -- gold proc glow
  gf:SetAlpha(0)
  f.glow = gf
  -- Frame-art skins (Blizzard/Dominos/ABE) ROUND their icons, so the square edge glow
  -- (f.glow) looks wrong against them. For those, the proc glow is an additive gold
  -- copy of the frame-ART texture (same rounded shape). ShowProcCenterIcon picks
  -- whichever matches the active skin.
  local ga = f:CreateTexture(nil, "OVERLAY", nil, 6)
  ga:SetBlendMode("ADD")
  ga:SetVertexColor(1, 0.85, 0.25, 1)
  ga:SetAlpha(0)
  ga:Hide()
  f.glowArt = ga
  f:Hide()
  ui._procCenterFrame = f
  return f
end

function UI:ShowProcCenterIcon(texture)
  if not texture then return end
  if self.GetProcGlowEnabled and not self:GetProcGlowEnabled() then return end
  local f = EnsureProcCenterFrame(self)
  if not f then return end
  local ui = self.ui
  local size = uiShared.PixelSnap((uiShared.ICON_SIZE or 45) * ICON_SCALE, ui)
  f:SetSize(size, size)
  f:ClearAllPoints()
  f:SetPoint("CENTER", ui._modkeyContainer, "CENTER", 0, 0)
  local mw, mh = ApplyStackBorder(self, f, size, size)
  if uiShared.ApplyActionMaskTo then
    uiShared.ApplyActionMaskTo(f, f.tex, mw, mh)
  end
  f.tex:SetTexture(texture)
  f.tex:Show()
  -- Pick the proc glow shape to MATCH the icon: frame-art (rounded) skins glow with a
  -- copy of the rounded frame texture; thin (square) skins use the square edge glow.
  local skin = uiShared.GetActionButtonBorder and uiShared.GetActionButtonBorder()
  if skin and (skin.atlas or skin.file) and f._skinBorder and f.glowArt then
    local ga = f.glowArt
    if skin.atlas then ga:SetAtlas(skin.atlas, false)
    else ga:SetTexture(skin.file); if skin.coords then ga:SetTexCoord(unpack(skin.coords)) end end
    ga:ClearAllPoints()
    ga:SetSize(f._skinBorder:GetSize())
    ga:SetPoint("CENTER", f, "CENTER", 0, 0)
    ga:Show()
    if f.glow then f.glow:Hide() end
    f._procGlow = ga
  else
    if f.glowArt then f.glowArt:Hide() end
    if f.glow then f.glow:Show() end
    f._procGlow = f.glow
  end
  f:SetAlpha(0)
  if f._procGlow then f._procGlow:SetAlpha(0) end
  f:Show()
  f._pcT = 0
  if not procCenterDriver then procCenterDriver = (API.CreateFrame or _G.CreateFrame)("Frame") end
  procCenterDriver._frame = f
  procCenterDriver:SetScript("OnUpdate", ProcCenterOnUpdate)
end

function UI:StopProcCenterIcon()
  if procCenterDriver then procCenterDriver._frame = nil; procCenterDriver:SetScript("OnUpdate", nil) end
  local ui = self.ui
  if ui and ui._procCenterFrame then
    ui._procCenterFrame._pcT = nil
    ui._procCenterFrame:SetScale(1)
    ui._procCenterFrame:SetAlpha(0)
    ui._procCenterFrame:Hide()
  end
end

-- ── AH match audible alert ───────────────────────────────────────────────────
-- Play the chosen sound on a match. force=true previews it (ignores the on/off so
-- picking a sound in options plays it).
function UI:PlayAHMatchSound(force)
  if not force and self.GetAHMatchAudibleEnabled and not self:GetAHMatchAudibleEnabled() then return end
  -- Throttle so rapid back-to-back matches don't garble overlapping sounds.
  if not force then
    local now = (API.GetTime and API.GetTime()) or 0
    if (now - (addon._ahLastSoundAt or 0)) < 0.2 then return end
    addon._ahLastSoundAt = now
  end
  local name = self.GetAHMatchSound and self:GetAHMatchSound() or nil
  -- Built-in Blizzard sound (stored as "kit:<id>") -> PlaySound by ID.
  if type(name) == "string" and name:sub(1, 4) == "kit:" then
    local id = tonumber(name:sub(5))
    if id and _G.PlaySound then pcall(_G.PlaySound, id, "Master") end
    return
  end
  -- LibSharedMedia sound -> file path -> PlaySoundFile.
  local file = (LSM and name) and LSM:Fetch("sound", name, true) or nil
  if file then
    pcall(_G.PlaySoundFile, file, "Master")
  elseif _G.PlaySound then
    pcall(_G.PlaySound, 8959, "Master") -- fallback chime when nothing chosen
  end
end

-- ── AH match % readout ───────────────────────────────────────────────────────
-- A small "AH Match: 75% (3/4)" line under the tracker. Parented to UIParent and
-- anchored to the tracker so it stays readable even when the tracker hides.

-- Host frame for the "AH %" readout when it's placed on the Meters Layout Control grid. The Meters
-- engine positions this frame (PlaceMeterElement, via METER_ELEMENTS id "AHMatch") and hugs matchText to
-- its edge. When AH %% is NOT slotted, this stays hidden and the under-Action-Tracker fontstring
-- (ui._ahMatchReadout) is used instead. Created at file scope so it exists before SetupFrames runs.
do
  local f = _G.CreateFrame("Frame", "AHMatchFrame", _G.UIParent)
  f:SetSize(120, 20)
  f:Hide()
  f.matchText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.matchText:SetPoint("CENTER", f, "CENTER", 0, 0)
end

local function EnsureMatchReadout(self)
  local ui = self.ui
  if not ui then return nil end
  if ui._ahMatchReadout then return ui._ahMatchReadout end
  local fs = _G.UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:ClearAllPoints()
  fs:SetPoint("TOP", ui.content or ui, "CENTER", 0, 0)  -- placeholder; AnchorMatchReadoutBelowModkeys sets the real (baseline) spot
  fs:Hide()
  ui._ahMatchReadout = fs
  return fs
end

-- Anchor the AH Match readout at the MODKEYS *baseline* spot (a fixed 1x1 anchor positioned relative
-- to the icon row), NOT the live modifiersFrame. This keeps it PUT: it stays at the default modkeys
-- position and does NOT follow when the user repositions the MODKEYS element (modifiersFrame = baseline
-- + the user's offset; we pin to the baseline only). It still tracks layout/icon-size/vertical changes
-- via the baseline. Offset clears the modkeys frame (half its height + a 4px gap). Falls back to the
-- live frame / tracker bottom if the baseline anchor isn't available.
local function AnchorMatchReadoutBelowModkeys(ui, fs)
  if not (ui and fs) then return end
  fs:ClearAllPoints()
  local anchor = ui.elementAnchors and ui.elementAnchors.modifiersText
  if anchor then
    local clear = ((uiShared.MODS_H or 14) * 0.5) + 4 + 5  -- 4px base gap below modkeys + 5px down-nudge
    fs:SetPoint("TOP", anchor, "CENTER", 0, -clear)
  else
    fs:SetPoint("TOP", ui.modifiersFrame or ui.content or ui, "BOTTOM", 0, -4)
  end
end

-- Second line, just under the match %: how many of the matches were Single-Button
-- Assistant casts. Only shown when the SBA was actually used this combat.
local function EnsureSbaReadout(self)
  local ui = self.ui
  if not ui then return nil end
  if ui._ahSbaReadout then return ui._ahSbaReadout end
  local anchor = EnsureMatchReadout(self)
  if not anchor then return nil end
  local fs = _G.UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:ClearAllPoints()
  fs:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
  fs:Hide()
  ui._ahSbaReadout = fs
  return fs
end

-- Colour the AH Match %% on a 0->100 gradient: red (low) -> yellow (mid) -> green (high). The match
-- counts are addon-computed (NOT C_DamageMeter "secret" values), so plain numeric math is safe here.
local function MatchColor(pct)
  local t = (tonumber(pct) or 0) / 100
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  if t < 0.5 then
    local k = t / 0.5            -- red -> yellow
    return 1, 0.2 + 0.8 * k, 0.2
  end
  local k = (t - 0.5) / 0.5      -- yellow -> green
  return 1 - 0.8 * k, 1, 0.2
end

-- Pulse the readout at 50%+ (sine alpha), FASTER as the %% climbs: ~1 pulse/sec at 50% up to ~4/sec at
-- 100%. A tiny OnUpdate frame breathes the alpha; below 50% (or during the post-combat fade) it holds
-- steady. The match %% is addon-computed (not "secret"), so the numeric math here is safe.
local PULSE_MIN_ALPHA = 0.35
local function MatchPulseFreq(pct)
  pct = tonumber(pct) or 0
  if pct < 50 then return 0 end
  return 1 + ((pct - 50) / 50) * 3   -- 50% -> 1 Hz, 100% -> 4 Hz
end
local function EnsureMatchPulseDriver(ui)
  if ui._ahMatchPulseDriver then return ui._ahMatchPulseDriver end
  local d = _G.CreateFrame("Frame")
  d:Hide()
  d:SetScript("OnUpdate", function(self, elapsed)
    local fs = ui._ahMatchActiveFS   -- the currently-shown readout (under-AT OR grid), set in UpdateAHMatchReadout
    if not (fs and fs:IsShown() and self._freq and self._freq > 0) then
      self:Hide()
      return
    end
    self._t = (self._t or 0) + (elapsed or 0)
    local a = PULSE_MIN_ALPHA + (1 - PULSE_MIN_ALPHA) * (0.5 + 0.5 * math.sin(self._t * self._freq * 2 * math.pi))
    fs:SetAlpha(a)
  end)
  ui._ahMatchPulseDriver = d
  return d
end
local function StartMatchPulse(ui, pct)
  local d = EnsureMatchPulseDriver(ui)
  d._freq = MatchPulseFreq(pct)
  if not d:IsShown() then d._t = 0; d:Show() end   -- keep phase continuous across %% updates
end
local function StopMatchPulse(ui, resetAlpha)
  local d = ui and ui._ahMatchPulseDriver
  if d then d._freq = nil; d:Hide() end
  if resetAlpha and ui and ui._ahMatchActiveFS then ui._ahMatchActiveFS:SetAlpha(1) end
end

function UI:UpdateAHMatchReadout()
  local ui = self.ui
  if not ui then return end
  local underAT = EnsureMatchReadout(self)
  if not underAT then return end
  -- Pick the active widget: the grid readout when AH %% is placed on the Meters Layout Control, else the
  -- under-Action-Tracker fontstring. The inactive one is hidden so only one ever shows.
  local gridFS = _G.AHMatchFrame and _G.AHMatchFrame.matchText
  local slotted = (_G.GSETracker_IsAHMatchSlotted and _G.GSETracker_IsAHMatchSlotted()) and gridFS and true or false
  local fs = (slotted and gridFS) or underAT
  ui._ahMatchActiveFS = fs
  if slotted then
    underAT:Hide()
  else
    if gridFS then gridFS:Hide() end
    if _G.AHMatchFrame then _G.AHMatchFrame:Hide() end
  end

  local enabled = (self.GetAHMatchPercentEnabled and self:GetAHMatchPercentEnabled()) or false
  local casts = addon._ahCastCount or 0
  local matches = addon._ahMatchCount or 0
  -- Combat-only, then a short post-combat hold (mirrors the DPS/HPS readouts). Edit Mode shows an EXAMPLE
  -- (gated on the feature being enabled, like the AT example names/modkeys).
  local now = (API.GetTime and API.GetTime()) or (GetTime and GetTime()) or 0
  local inCombat = (API.UnitAffectingCombat and API.UnitAffectingCombat("player"))
    or (UnitAffectingCombat and UnitAffectingCombat("player"))
  local holdActive = addon._ahMatchHoldUntil and (now < addon._ahMatchHoldUntil)
  local inPreview = (self.IsEditModePreviewActive and self:IsEditModePreviewActive()) or false
  if not enabled or not (inCombat or holdActive or inPreview) then
    StopMatchPulse(ui, false)
    fs:Hide()
    if slotted and _G.AHMatchFrame then _G.AHMatchFrame:Hide() end
    if ui._ahSbaReadout then ui._ahSbaReadout:Hide() end
    return
  end
  local pct
  local previewing = inPreview and not (inCombat or holdActive)
  if previewing then
    pct = 75
    if _G.GSETracker_CancelFade then _G.GSETracker_CancelFade(fs) end  -- examples don't fade
    fs:SetAlpha(1)
    fs:SetText("75% (15/20)")
  else
    pct = (casts > 0) and (matches / casts * 100) or 0
    fs:SetText(string.format("%d%% (%d/%d)", math.floor(pct + 0.5), matches, casts))
  end
  -- "AH Animated" toggle: colour gradient + pulse when ON; plain WHITE static text when OFF.
  local animated = (self.GetAHMatchAnimated == nil) or self:GetAHMatchAnimated()
  if animated then fs:SetTextColor(MatchColor(pct)) else fs:SetTextColor(1, 1, 1) end
  if slotted then
    if _G.AHMatchFrame then _G.AHMatchFrame:Show() end  -- Meters SetupFrames positions it; we own show+value
  else
    AnchorMatchReadoutBelowModkeys(ui, fs)  -- under-AT: pin at the modkeys baseline
  end
  fs:Show()
  -- Pulse at 50%+ while actively shown (in combat or Edit Mode preview) AND animation is on. During the
  -- post-combat fade (holdActive, not in combat) leave the alpha to the fade -- don't pulse or reset it.
  local activeShow = inCombat or previewing
  if animated and pct >= 50 and activeShow then
    StartMatchPulse(ui, pct)
  else
    StopMatchPulse(ui, activeShow)
  end

  -- SBA sub-line removed: only the AH Match %% is shown here. The SBA % readout lives in the standalone
  -- SLG-SBA Monitor addon now. Keep the sub-line frame hidden if it was ever created.
  if ui._ahSbaReadout then ui._ahSbaReadout:Hide() end
end

-- Global wrapper so the Meters engine (no `ns` upvalue) can refresh the readout on grid changes.
function _G.GSETracker_UpdateAHMatchReadout()
  if addon.UpdateAHMatchReadout then addon:UpdateAHMatchReadout() end
end

-- Post-combat hold for the AH Match / SBA readout: keep it on screen briefly after combat ends
-- (mirrors the DPS/HPS hold), then hide. Counters reset on combat ENTER (see events.lua), so the
-- final values stay readable during the hold.
local AH_MATCH_FADE = 0.12  -- seconds (matches the DPS/HPS/SBAssist/name fades + the icon flow fade-out)
do
  local matchEvents = _G.CreateFrame("Frame")
  matchEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
  matchEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
  matchEvents:SetScript("OnEvent", function(_, ev)
    local ui = addon.ui
    local activeFS = ui and (ui._ahMatchActiveFS or ui._ahMatchReadout)
    if ev == "PLAYER_REGEN_DISABLED" then
      addon._ahMatchHoldUntil = nil
      -- Cancel any post-combat fade still ramping and restore full opacity for this fight.
      if ui and _G.GSETracker_CancelFade then
        _G.GSETracker_CancelFade(activeFS)
        _G.GSETracker_CancelFade(ui._ahSbaReadout)
      end
    else  -- PLAYER_REGEN_ENABLED: hold the readout for AH_MATCH_FADE seconds, fading it out, then hide.
      local now = (API.GetTime and API.GetTime()) or (GetTime and GetTime()) or 0
      addon._ahMatchHoldUntil = now + AH_MATCH_FADE
      -- Smoothly ramp the % out over the hold window instead of snapping off at the end.
      if ui and _G.GSETracker_SmoothFadeOut then
        _G.GSETracker_SmoothFadeOut(activeFS, AH_MATCH_FADE)
        _G.GSETracker_SmoothFadeOut(ui._ahSbaReadout, AH_MATCH_FADE)
      end
      if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(AH_MATCH_FADE + 0.05, function()
          addon._ahMatchHoldUntil = nil
          if addon.UpdateAHMatchReadout then addon:UpdateAHMatchReadout() end
        end)
      end
    end
    if addon.UpdateAHMatchReadout then addon:UpdateAHMatchReadout() end
  end)
end
