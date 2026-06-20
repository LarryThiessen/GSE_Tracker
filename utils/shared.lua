local _, ns = ...
local addon = ns
local Utils = ns.Utils or {}
ns.Utils = Utils
addon.Utils = Utils
local API = (ns.Utils and ns.Utils.API) or {}
local SV = (ns.Utils and ns.Utils.SV) or nil
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local uiShared = addon._ui or {}
addon._ui = uiShared

local PAD_X = 10
local PAD_TOP = 1
local PAD_BOTTOM = 7

local NAME_FONT_SIZE = 12
local MOD_FONT_SIZE = 8

local NAME_H = 24
local MODS_H = 14

-- Base icon size at addon-scale 1.0 == Blizzard's default action button icon
-- (so the tracker matches the action bars at base; the Scale setting multiplies
-- past this, and Blizzard UI scale applies to both equally).
local ICON_SIZE = 45
local DEFAULT_ICON_GAP = C.DEFAULT_ICON_GAP or 3

local TEXT_W = 140

local GAP_NAME_ICONS = 8
local GAP_ICONS_MODS = 6

local MIN_W = 180
local MAX_W = 480

local SCROLL_DUR = 0.55

local MOD_ALT_X_NUDGE = 2
local MOD_SHIFT_X_NUDGE = 2
local MOD_CTRL_X_NUDGE = 3

local MOD_FIXED_X_SPACING = (ICON_SIZE + DEFAULT_ICON_GAP)

local ADDON_DISPLAY_NAME = C.ADDON_DISPLAY_NAME or "|cFFFFFFFFGS|r|cFF00FFFFE:|r|cFFFFFF00 Tracker|r"

local function GetRootDefaults()
  if SV and SV.GetRootDefaults then
    local defaults = SV:GetRootDefaults()
    if type(defaults) == "table" then
      return defaults
    end
  end
  return nil
end


local ELEMENT_DEFAULTS = {
  sequenceText = { enabled = true,  point = "CENTER", relativeTo = "content", relativePoint = "CENTER", x = 0, y = 0 },
  modifiersText = { enabled = true, point = "CENTER", relativeTo = "content", relativePoint = "CENTER", x = 0, y = 0 },
  keybindText = { enabled = false, point = "CENTER", relativeTo = "content", relativePoint = "CENTER", x = 0, y = 0 },
  -- pressedIndicator is ALWAYS enabled (like its siblings). It has no enable toggle in
  -- the UI by design: the user hides it by picking the "None" shape in the Shape dropdown
  -- (DrawSymbolOnFrame renders nothing for "None"). So enabled MUST stay true -- a false
  -- default makes the indicator silently never render, with no UI way to turn it back on.
  pressedIndicator = { enabled = true, point = "CENTER", relativeTo = "content", relativePoint = "CENTER", x = 0, y = 0 },
}

local function Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Returns the ACTIVE saved store (account or per-character). Do NOT reassign the
-- GSETrackerDB global to it -- that global IS the account SavedVariable; pointing
-- it at the per-character table would fuse the two stores at logout.
local function EnsureDB()
  if SV and SV.EnsureDB then
    return SV:EnsureDB()
  end
  if _G.GSETrackerDB == nil then _G.GSETrackerDB = {} end
  return _G.GSETrackerDB
end

local function RoundNearest(v)
  v = tonumber(v) or 0
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return math.ceil(v - 0.5)
end

local function GetPixelScale(frame)
  local f = frame or UIParent
  local scale = (f and f.GetEffectiveScale and f:GetEffectiveScale()) or 1
  if not scale or scale <= 0 then
    scale = 1
  end
  return scale
end

local function PixelSnap(v, frame)
  if v == nil then return 0 end
  local scale = GetPixelScale(frame)
  return math.floor((v * scale) + 0.5) / scale
end

local function IconRowWidth(count)
  count = Clamp(count or 4, 4, 8)
  -- Effective gap = setting - 1 so the slider's 0 = visually flush (the frame art
  -- has built-in padding, so spacing 0 with raw gaps still showed a hair of gap).
  local gap = addon:GetIconGap() - 1
  local size = uiShared.ICON_SIZE or ICON_SIZE
  return (count * size) + ((count - 1) * gap)
end

-- Resolve the base icon size from the real Blizzard ActionButton (so the tracker
-- matches the player's action bars, whatever size their UI/skinner uses). Falls
-- back to the default. Updates uiShared.ICON_SIZE (the single source of truth).
function uiShared.RefreshIconSize(refFrame)
  local size
  -- Read the player's ACTIVE bar button (ElvUI/EllesmereUI/Dominos when present),
  -- not the hidden stock ActionButton1 -- otherwise the size comes from a button the
  -- player isn't using.
  local btn = (uiShared.GetActiveActionButton and uiShared.GetActiveActionButton()) or _G.ActionButton1
  if btn then
    local icon = btn.icon or (btn.GetName and _G[(btn:GetName() or "") .. "Icon"])
    local w = (icon and icon.GetWidth and icon:GetWidth()) or (btn.GetWidth and btn:GetWidth())
    if w and w > 0 then
      -- Match the button's ON-SCREEN size, not its raw width: bar addons (Dominos,
      -- etc.) scale their bars down (e.g. 0.64), so raw width overstates the visible
      -- size. Convert the button's screen pixels (raw * its effective scale) into the
      -- TRACKER icon area's coordinate space (refFrame's effective scale) so the
      -- rendered icon == the bar on screen EXACTLY, whatever the tracker's own scale
      -- is. Falls back to UIParent when no reference frame is supplied.
      local btnEff = (btn.GetEffectiveScale and btn:GetEffectiveScale()) or 1
      -- Convert the button's screen size into UIParent space (the WoW UI scale) -- NOT the
      -- tracker's own effective scale. Using the tracker's effective scale (which includes its
      -- Scale slider, display.scale) cancelled that slider for the icons, so only the text
      -- scaled. Sizing in UIParent space means the tracker's SetScale(display.scale) scales the
      -- icons too; at Scale 1.00 they still match the action-bar button exactly.
      local refEff = (_G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale()) or 1
      size = (refEff > 0) and (w * btnEff / refEff) or w
    end
  end
  size = tonumber(size)
  if not size or size < 16 or size > 80 then size = ICON_SIZE end
  uiShared.ICON_SIZE = math.floor(size + 0.5)
  return uiShared.ICON_SIZE
end

-- Describe the action button's border/frame art so the tracker can match the
-- player's action-bar look (Blizzard default or a skinner like
-- ActionBarsEnhanced). The frame art is a separate texture that is SIZED LARGER
-- than the icon and extends beyond it (e.g. ~64px around a 45px icon), with its
-- own texcoords -- so we return its size ratio vs the button (to scale it onto
-- our icon) and its coords, not just the file. Returns a table or nil.
-- For the ICON BORDER + MASK only the EXPLICIT "Force Blizzard Native Skin" uses the
-- hardcoded Blizzard atlas. In AUTO we ADOPT whatever the player's action buttons actually
-- use (ActionButton1's NormalTexture / IconMask), so ANY skinner is matched -- ElvUI,
-- EllesmereUI, ActionBarEnhanced, ... -- without a hardcoded provider list. With the default
-- bars, ActionButton1 IS the Blizzard art, and the atlas-intrinsic-size handling below keeps
-- it from over-sizing, so AUTO-with-no-skinner still renders like Native.
-- (The options-window widget palette uses options.IsNativeSkin separately; this is decoupled
-- from it so an undetected skinner's button art is still adopted.)
-- Is ANY action-bar skinner active? True when the player's ACTIVE bar button is a
-- skinner's OWN button (ElvUI/EllesmereUI/Dominos/Bartender4 -- non-stock), OR an
-- in-place skinner that restyles the stock buttons is present (Masque / ActionBars-
-- Enhanced -- detected by addon AND by the stock button's NormalTexture no longer
-- being the pristine Blizzard frame). False = no skinner -> the tracker resolves to
-- the Blizzard native look while keeping the player's own options.
local IN_PLACE_SKINNERS = { "Masque", "ActionBarsEnhanced", "ActionBarEnhanced" }
function uiShared.IsSkinnerActive()
  local btn, _, isStock = uiShared.GetActiveActionButton and uiShared.GetActiveActionButton()
  if isStock == false then return true end
  local C = _G.C_AddOns
  if C and C.IsAddOnLoaded then
    for _, n in ipairs(IN_PLACE_SKINNERS) do
      local ok, loaded = pcall(C.IsAddOnLoaded, n)
      if ok and loaded then return true end
    end
  end
  -- Stock button: a skinner is active only if its NormalTexture is no longer the
  -- pristine Blizzard frame -- a custom atlas/file, or the Blizzard atlas drawn
  -- noticeably larger than default (ABE enlarges it). Otherwise = default bars.
  if btn then
    local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or btn.NormalTexture
    if nt and (not nt.IsShown or nt:IsShown()) then
      local atlas = nt.GetAtlas and nt:GetAtlas()
      if atlas and atlas ~= "" then
        if not atlas:find("UI%-HUD%-ActionBar%-IconFrame") then return true end
        local icon = btn.icon or (btn.GetName and _G[(btn:GetName() or "") .. "Icon"])
        local nw = nt.GetWidth and nt:GetWidth()
        local iw = icon and icon.GetWidth and icon:GetWidth()
        if nw and iw and iw > 0 and (nw / iw) > 1.22 then return true end
      else
        local file = (nt.GetTextureFilePath and nt:GetTextureFilePath()) or (nt.GetTexture and nt:GetTexture())
        if file and file ~= "" then return true end
      end
    end
  end
  return false
end

function uiShared.IsResolvedNativeSkin()
  if addon.GetSkin and addon:GetSkin() == "NATIVE" then return true end
  -- AUTO with NO skinner active -> resolve to NATIVE: render the Blizzard frame but
  -- keep the player's OWN chosen options (font, colours) instead of adopting the
  -- stock button's style. A skinner being present switches AUTO into adoption.
  if uiShared.IsSkinnerActive and not uiShared.IsSkinnerActive() then return true end
  return false
end

-- The action button whose style the tracker adopts: the player's ACTIVE bar
-- button. Skinners like ElvUI REPLACE the Blizzard bars with their own buttons
-- (ElvUI_Bar1Button1...) and leave stock ActionButton1 hidden with default
-- Blizzard art -- so prefer the skinner's button to adopt what the player
-- actually sees. Returns: button frame, its name, and isStock (a Blizzard button
-- vs a skinner-provided one). Falls back to stock ActionButton1.
local STOCK_ACTION_BUTTONS = {
  ActionButton1 = true,
  MultiBarBottomLeftButton1 = true,
  MultiBarBottomRightButton1 = true,
  MultiBarRightButton1 = true,
  MultiBarLeftButton1 = true,
}
-- Skinner buttons that REPLACE the Blizzard bars (ElvUI/EllesmereUI). Their mere
-- EXISTENCE means the skinner owns the bars, so adopt them even when the bar is
-- currently faded/hidden (mouseover bars, preview context). Requiring IsVisible here
-- would intermittently fall back to the hidden stock ActionButton1 -> wrong border
-- (Blizzard frame art + the tracker's own colour, e.g. the pink/off-bottom flicker).
local SKINNER_BUTTON_ORDER = { "ElvUI_Bar1Button1", "EABButton1", "DominosActionButton1", "BT4Button1" }
local STOCK_BUTTON_ORDER = { "ActionButton1", "MultiBarBottomLeftButton1", "MultiBarRightButton1" }
function uiShared.GetActiveActionButton()
  local G = _G
  -- 1) A VISIBLE skinner button -- the bar actually on screen. When BOTH ElvUI and
  -- EllesmereUI are installed, this picks whichever is really showing its bars (so we
  -- don't adopt ElvUI's colour while EllesmereUI's bar is the one displayed).
  for _, n in ipairs(SKINNER_BUTTON_ORDER) do
    local b = G[n]
    if b and (not b.IsVisible or b:IsVisible()) then return b, n, false end
  end
  -- 2) Else a skinner button that merely EXISTS (its bar may be faded/hidden on
  -- mouseover -- still the player's real bar style, better than the hidden stock one).
  for _, n in ipairs(SKINNER_BUTTON_ORDER) do
    if G[n] then return G[n], n, false end
  end
  -- 3) No replacing skinner: the VISIBLE Blizzard bar. IsVisible (NOT IsShown) skips a
  -- stock bar a skin hid -- stock ActionButton1 stays IsShown()=true even when
  -- parented under a hidden frame.
  for _, n in ipairs(STOCK_BUTTON_ORDER) do
    local b = G[n]
    if b and (not b.IsVisible or b:IsVisible()) then
      return b, n, STOCK_ACTION_BUTTONS[n] == true
    end
  end
  return G.ActionButton1, "ActionButton1", true
end

-- Read the player's CURRENT skinner border STYLE (colour + thickness) from the
-- skinner's OWN settings -- the same source of truth the skin draws from -- so the
-- tracker's thin border tracks the skin's live config, not a guessed default.
-- ElvUI: reads ElvUI[1].media.bordercolor and its pixel/border size. Returns
-- r,g,b,thickness, or nil when no recognised thin-border skinner is active.
-- The skin's LIVE accent colour for borders -- driven by the skinner, not guessed.
-- EllesmereUI exposes its resolved border/accent colour via GetAccentColor() (which
-- already reflects the active theme, e.g. class colour under "Class Colored"), so we
-- read that directly; it re-reads on EllesmereUI's accent/theme hooks. Falls back to
-- the player's class colour, then black.
function uiShared.GetSkinAccentColor()
  local EUI = _G.EllesmereUI
  if EUI and type(EUI.GetAccentColor) == "function" then
    local ok, r, g, b = pcall(EUI.GetAccentColor, EUI)
    if ok and type(r) == "number" then return r, g, b end
  end
  local ok, _, class = pcall(API.UnitClass or _G.UnitClass, "player")
  -- Classic quirk: RAID_CLASS_COLORS.SHAMAN is Paladin pink; force the real blue (no CUSTOM override).
  if ok and class == "SHAMAN" and not _G.CUSTOM_CLASS_COLORS then return 0.0, 0.44, 0.87 end
  local t = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
  local c = ok and class and t and t[class]
  if c then return c.r, c.g, c.b end
  return 0, 0, 0
end

function uiShared.GetSkinnerBorderStyle()
  -- Key off the ACTIVE bar button so the colour comes from the skinner that owns the
  -- bars. BOTH ElvUI and EllesmereUI can be loaded at once -- keying off mere
  -- _G.ElvUI existence wrongly used ElvUI's border colour under EllesmereUI (the
  -- pink/red borders), even though EllesmereUI's button is the one on screen.
  local _, btnName = (uiShared.GetActiveActionButton and uiShared.GetActiveActionButton())
  if btnName == "ElvUI_Bar1Button1" then
    local E = _G.ElvUI and _G.ElvUI[1]
    if E and E.media then
      local c = E.media.bordercolor
      local r = (c and (c[1] or c.r)) or 0
      local g = (c and (c[2] or c.g)) or 0
      local b = (c and (c[3] or c.b)) or 0
      -- ElvUI pixel mode = 1px; non-pixel = 2px.
      local thickness = E.PixelMode and 1 or 2
      return r, g, b, thickness
    end
  elseif btnName == "EABButton1" then
    -- EllesmereUI: thin line in its live accent (class colour under "Class Colored").
    local r, g, b = uiShared.GetSkinAccentColor()
    return r, g, b, 1
  end
  return nil
end

-- A whole-PANEL border texture to wrap the entire tracker frame so it reads as part
-- of the skin (vs the per-icon border above). EllesmereUI: its themed "glow-border"
-- edge texture (panel-scale, edgeSize 12) tinted to the accent (class colour).
-- Returns edgeFile, edgeSize, r, g, b -- or nil when no panel skin applies.
function uiShared.GetSkinnerPanelBorder()
  -- Disabled per user preference (icons-only): the whole-tracker panel frame was
  -- "an extra border around everything". Per-icon borders carry the skin match.
  -- The EllesmereUI-driven panel-border implementation lived here; it read the live
  -- _bdBorderData backdrop to mirror EllesmereUI's current theme. Removed for release
  -- (recoverable from git history); restore it to re-enable a whole-tracker panel border.
  return nil
end

-- Hook the active skinner so any media/skin change re-skins the tracker LIVE --
-- the "adopt the skinner's SETTINGS" contract. ElvUI fires E:UpdateMedia() on any
-- border/backdrop/colour change; we hooksecurefunc it (insecure, runs after ElvUI)
-- and re-apply our border/icons/fonts + meters. Runs once; no-op if ElvUI or
-- UpdateMedia is absent. `addon` is the tracker namespace table.
function uiShared.SetupSkinnerHooks(addon)
  if uiShared._skinnerHooked then return end
  if not _G.hooksecurefunc then return end
  local pending = false
  local function doReskin()
    pending = false
    if addon.RebuildIcons then addon:RebuildIcons(true) end
    if addon.ApplyBorderThickness then addon:ApplyBorderThickness() end
    if addon.ApplyFontFaces then addon:ApplyFontFaces() end
    if addon.RefreshAssistedHighlight then addon:RefreshAssistedHighlight(true) end
    if _G.Meter_ApplyFont then _G.Meter_ApplyFont() end
    if _G.RefreshDetails then _G.RefreshDetails() end
  end
  -- Skinners can fire their apply hook many times in a burst (per element); coalesce
  -- into one re-skin a tick later.
  local function reskin()
    if pending then return end
    pending = true
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.1, doReskin) else doReskin() end
  end
  local hooked = false
  -- ElvUI: any media/skin change.
  local Elv = _G.ElvUI
  local E = Elv and Elv[1]
  if E and type(E.UpdateMedia) == "function" then
    _G.hooksecurefunc(E, "UpdateMedia", reskin)
    hooked = true
  end
  -- EllesmereUI: theme / border-colour / accent changes.
  local EUI = _G.EllesmereUI
  if EUI then
    for _, fn in ipairs({ "SetActiveTheme", "SetBorderStyleColor", "SetAccentColor", "ApplyBorderStyle" }) do
      if type(EUI[fn]) == "function" then
        _G.hooksecurefunc(EUI, fn, reskin)
        hooked = true
      end
    end
  end
  -- Generic: follow the player's ACTIVE bar button LIVE so any bar addon (Bartender4,
  -- Dominos, ...) drives the tracker when the user changes its config. Button SIZE
  -- changes fire OnSizeChanged; bar SCALE changes (BT4/Dominos scale the parent bar,
  -- not the button) fire the bar's SetScale. Both are safe, non-protected hooks.
  local active = uiShared.GetActiveActionButton and uiShared.GetActiveActionButton()
  if active and active.HookScript and not active._gsetTrackerHooked then
    active._gsetTrackerHooked = true
    active:HookScript("OnSizeChanged", reskin)
    local bar = active.GetParent and active:GetParent()
    if bar and bar.SetScale and not bar._gsetTrackerScaleHooked then
      bar._gsetTrackerScaleHooked = true
      _G.hooksecurefunc(bar, "SetScale", reskin)
    end
    hooked = true
  end
  if hooked then uiShared._skinnerHooked = true end
end

function uiShared.GetActionButtonBorder()
  -- The Blizzard default frame atlas -- used when "Force Native" is on, and as the FALLBACK
  -- in AUTO when the player's button border can't be read (nil = Classic, no atlas).
  local function NativeAtlasBorder()
    if _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo("UI-HUD-ActionBar-IconFrame") then
      return { atlas = "UI-HUD-ActionBar-IconFrame", wRatio = 46 / 45, hRatio = 45 / 45 }
    end
    return nil
  end

  -- Classic flavors have no clean icon-frame atlas, and their stock button border (the gold
  -- Quickslot art) has a big transparent margin that, when adopted, leaves a GAP between the
  -- icon and the visible ring. Don't auto-adopt it -- use the native atlas if present, else no
  -- frame art (icons render tight, no gap).
  local mainline = (not _G.WOW_PROJECT_ID) or (_G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1))
  if not mainline then
    return NativeAtlasBorder()
  end

  -- Force Native -> Blizzard default; AUTO -> adopt the player's actual ActionButton1 art.
  if uiShared.IsResolvedNativeSkin() then
    return NativeAtlasBorder()
  end

  -- AUTO: read the player's ACTIVE bar button (ElvUI's own button when present,
  -- else stock ActionButton1). When that button has NO NormalTexture frame ART, a
  -- thin-border skinner is in play (ElvUI draws a ~1px backdrop border, not frame
  -- art): adopt a THIN border. Only the STOCK Blizzard button falls back to the
  -- ornate atlas, so a skinned bar never renders the wrong (Blizzard) frame.
  local btn, _btnName, btnIsStock = uiShared.GetActiveActionButton()
  if not btn then return NativeAtlasBorder() end
  local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or btn.NormalTexture
  local ntShown = nt and (not nt.IsShown or nt:IsShown()) or false

  local atlas = (ntShown and nt.GetAtlas and nt:GetAtlas()) or nil
  -- The Blizzard "IconFrame-AddRow" atlas has an OFF-CENTRE window that skews the
  -- adopted icon up-left and mis-sizes it. When it's drawn at ~its native size
  -- (stock / Dominos / Bartender4 bars), use the clean centred IconFrame at 46/45 --
  -- exactly like Force-Native. BUT if a skinner draws it noticeably LARGER (e.g.
  -- ActionBarsEnhanced enlarges the frame, ratio ~1.33), keep adopting it via the
  -- measured ratio below so the enlarged frame isn't shrunk back to native.
  if atlas == "UI-HUD-ActionBar-IconFrame-AddRow" then
    local ic = btn.icon or (btn.GetName and _G[(btn:GetName() or "") .. "Icon"])
    local ntw = nt.GetWidth and nt:GetWidth()
    local icw = ic and ic.GetWidth and ic:GetWidth()
    if not (ntw and icw and icw > 0 and (ntw / icw) > 1.20) then
      return NativeAtlasBorder()
    end
  end
  local file
  if atlas and atlas ~= "" then
    file = nil
  else
    atlas = nil
    file = (ntShown and ((nt.GetTextureFilePath and nt:GetTextureFilePath()) or (nt.GetTexture and nt:GetTexture()))) or nil
    if not (file and file ~= "") then
      -- No frame art: stock Blizzard -> ornate atlas fallback; skinner -> thin border,
      -- styled from the skinner's OWN live settings (ElvUI colour + pixel thickness).
      if btnIsStock then return NativeAtlasBorder() end
      local r, g, b, thickness = uiShared.GetSkinnerBorderStyle and uiShared.GetSkinnerBorderStyle()
      return { thin = true, r = r, g = g, b = b, thickness = thickness }
    end
  end

  -- Adopt the skinner's frame ART (atlas/file/coords) AND its REAL draw ratio.
  -- Skinners like ActionBarsEnhanced draw their NormalTexture LARGER than the icon
  -- (measured: 60px frame over a 45px icon = 1.333) so the ornate border sits just
  -- OUTSIDE the icon and the frame's transparent inner window lands exactly on the
  -- icon edge. We MEASURE that ratio from ActionButton1 (NormalTexture : icon) and
  -- replicate it so the adopted frame hugs the icon like the bars do. Drawing the
  -- art at icon size (46/45) instead shrinks the window INSIDE the icon and pulls
  -- the grey decoration into the icon body. Clamped to a sane range, with the
  -- native 46/45 as the fallback when the live sizes can't be read.
  -- (The icon's own baked bevel is removed separately via the icon texcoord crop.)
  local wRatio, hRatio = 46 / 45, 45 / 45
  local iconRegion = btn.icon or (btn.GetName and _G[(btn:GetName() or "") .. "Icon"])
  local nw = nt.GetWidth and nt:GetWidth()
  local nh = nt.GetHeight and nt:GetHeight()
  local iw = iconRegion and iconRegion.GetWidth and iconRegion:GetWidth()
  local ih = iconRegion and iconRegion.GetHeight and iconRegion:GetHeight()
  if nw and iw and nw > 0 and iw > 0 then wRatio = math.min(2, math.max(1, nw / iw)) end
  if nh and ih and nh > 0 and ih > 0 then hRatio = math.min(2, math.max(1, nh / ih)) end
  local info = {
    atlas = atlas,
    file = file,
    wRatio = wRatio,
    hRatio = hRatio,
  }
  -- Copy the texcoords so a plain SetTexture(file) frame renders the same region
  -- the bars do (atlas case sets its own coords via SetAtlas).
  if not atlas and nt.GetTexCoord then
    local a, b, c, d, e, f, g, h = nt:GetTexCoord()
    if a then info.coords = { a, b, c, d, e, f, g, h } end
  end
  return info
end

-- Adopt the player's action-bar font STYLE (face + outline flags) so the tracker's
-- text matches the UI skin, exactly like GetActionButtonBorder adopts the frame art.
-- kind: "hotkey" (keybind/modifiers), "name" (sequence/macro/spell) or "count".
-- Returns path, size, flags -- or nil when Force-Native is on or the region can't be
-- read, in which case callers keep the user's configured font.
function uiShared.GetActionButtonFont(kind)
  local btn
  if addon.GetSkin and addon:GetSkin() == "NATIVE" then
    -- Force-Native: the GENUINE Blizzard DEFAULT font (the client's standard UI font). Return it
    -- directly rather than reading ActionButton1 -- a skinner that restyles the STOCK buttons in
    -- place (ABE, ElvUI "skin Blizzard", Masque...) would otherwise leak its own font into
    -- "native", so Force-Native would look adopted. Size/outline stay caller-controlled (nil flags
    -- = keep the user's configured outline). This is the per-client default on every flavor.
    return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", nil, nil
  else
    if uiShared.IsResolvedNativeSkin and uiShared.IsResolvedNativeSkin() then return nil end
    btn = (uiShared.GetActiveActionButton and uiShared.GetActiveActionButton()) or _G.ActionButton1
  end
  if not btn then return nil end
  local name = (btn.GetName and btn:GetName()) or "ActionButton1"
  local region
  if kind == "name" then
    region = btn.Name or _G[name .. "Name"]
  elseif kind == "count" then
    region = btn.Count or _G[name .. "Count"]
  else
    region = btn.HotKey or _G[name .. "HotKey"]
  end
  if not (region and region.GetFont) then return nil end
  local path, size, flags = region:GetFont()
  if not (path and path ~= "" and size and size > 0) then return nil end
  return path, size, flags
end

-- Convenience for non-tracker UI (the Meters: Details / DPS / HPS / GCD, and any
-- previews) to adopt the SAME action-bar font STYLE the tracker text uses --
-- automatically, whenever a UI skin is active. Returns path, flags when a skin is
-- in use and ActionButton1's HotKey font is readable; nil under Force-Native or
-- when it can't be read, so callers fall back to the player's configured font.
-- Mirrors how GetActionButtonBorder auto-adopts the frame art. (Sizes stay
-- caller-controlled, exactly like the tracker text.)
function uiShared.GetAdoptedFontStyle()
  if not uiShared.GetActionButtonFont then return nil end
  local path, _, flags = uiShared.GetActionButtonFont("hotkey")
  if not path then return nil end
  return path, flags or ""
end

local function GetPlayerClassColorRGB(fallbackR, fallbackG, fallbackB)
  local localizedClass, classFile
  if API.UnitClass then
    localizedClass, classFile = API.UnitClass("player")
  end

  local class = classFile or localizedClass
  -- Classic data quirk: RAID_CLASS_COLORS.SHAMAN is the Paladin PINK (Shaman/Paladin are
  -- faction-mirror classes in Classic). With no CUSTOM_CLASS_COLORS override, force the real
  -- Shaman blue. Harmless on Retail (already this colour).
  if class == "SHAMAN" and not CUSTOM_CLASS_COLORS then
    return 0.0, 0.44, 0.87
  end
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = class and colors and colors[class]
  if c then
    return c.r, c.g, c.b
  end

  return fallbackR or 1, fallbackG or 1, fallbackB or 1
end

local function SetPointIfChanged(frame, point, anchor, relativePoint, x, y)
  if not frame then return end
  if frame._gsetrackerPoint == point
    and frame._gsetrackerAnchor == anchor
    and frame._gsetrackerRelativePoint == relativePoint
    and frame._gsetrackerPointX == x
    and frame._gsetrackerPointY == y then
    return
  end
  frame._gsetrackerPoint = point
  frame._gsetrackerAnchor = anchor
  frame._gsetrackerRelativePoint = relativePoint
  frame._gsetrackerPointX = x
  frame._gsetrackerPointY = y
  frame:ClearAllPoints()
  frame:SetPoint(point, anchor, relativePoint, x, y)
end

local function ClearTable(t)
  if type(t) ~= "table" then return end
  if API.wipe then
    API.wipe(t)
    return
  end
  for k in pairs(t) do
    t[k] = nil
  end
end

local function ClearArray(t, fromIndex)
  if type(t) ~= "table" then return end
  local startIndex = tonumber(fromIndex) or 1
  for i = #t, startIndex, -1 do
    t[i] = nil
  end
end

local function CopyArrayInto(dst, src, maxN)
  dst = dst or {}
  if type(dst) ~= "table" then dst = {} end
  local n = 0
  if type(src) == "table" then
    n = maxN or #src
    for i = 1, n do
      dst[i] = src[i]
    end
  end
  ClearArray(dst, n + 1)
  return dst
end

uiShared.PAD_X = PAD_X
uiShared.PAD_TOP = PAD_TOP
uiShared.PAD_BOTTOM = PAD_BOTTOM
uiShared.NAME_FONT_SIZE = NAME_FONT_SIZE
uiShared.MOD_FONT_SIZE = MOD_FONT_SIZE
uiShared.NAME_H = NAME_H
uiShared.MODS_H = MODS_H
uiShared.ICON_SIZE = ICON_SIZE
uiShared.DEFAULT_ICON_GAP = DEFAULT_ICON_GAP
uiShared.TEXT_W = TEXT_W
uiShared.GAP_NAME_ICONS = GAP_NAME_ICONS
uiShared.GAP_ICONS_MODS = GAP_ICONS_MODS
uiShared.MIN_W = MIN_W
uiShared.MAX_W = MAX_W
-- Width of a stacked (vertical-layout) glyph-column label, beside the icon column.
uiShared.VERTICAL_LABEL_W = 24
uiShared.SCROLL_DUR = SCROLL_DUR
uiShared.MOD_ALT_X_NUDGE = MOD_ALT_X_NUDGE
uiShared.MOD_SHIFT_X_NUDGE = MOD_SHIFT_X_NUDGE
uiShared.MOD_CTRL_X_NUDGE = MOD_CTRL_X_NUDGE
uiShared.MOD_FIXED_X_SPACING = MOD_FIXED_X_SPACING
uiShared.ADDON_DISPLAY_NAME = ADDON_DISPLAY_NAME
uiShared.GetRootDefaults = GetRootDefaults
uiShared.ELEMENT_DEFAULTS = ELEMENT_DEFAULTS
uiShared.Clamp = Clamp
uiShared.RoundNearest = RoundNearest
uiShared.EnsureDB = EnsureDB
uiShared.GetPixelScale = GetPixelScale
uiShared.PixelSnap = PixelSnap
uiShared.IconRowWidth = IconRowWidth
uiShared.GetPlayerClassColorRGB = GetPlayerClassColorRGB
uiShared.SetPointIfChanged = SetPointIfChanged
uiShared.ClearTable = ClearTable
uiShared.ClearArray = ClearArray
uiShared.CopyArrayInto = CopyArrayInto

function Utils:IsPerformanceModeEnabled()
  if Utils.GetPerformanceModeEnabled then
    return Utils:GetPerformanceModeEnabled()
  end
  local db = EnsureDB() or {}
  local flags = type(db.flags) == "table" and db.flags or {}
  return flags.performanceMode and true or false
end

function Utils:SetPerformanceModeEnabled(enabled)
  if Utils.SetPerformanceModeEnabledCanonical then
    return Utils:SetPerformanceModeEnabledCanonical(enabled)
  end
  local db = EnsureDB() or {}
  db.flags = db.flags or {}
  db.flags.performanceMode = not not enabled
end
