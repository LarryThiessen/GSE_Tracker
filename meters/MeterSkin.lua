-- meters/MeterSkin.lua
-- "DamageMeter Skinner": cosmetically restyle Blizzard's built-in DamageMeter frame so it matches
-- GSE_Tracker's skin instead of the rough stock look. ONLY active when:
--   * Retail (the DamageMeter frame only exists there),
--   * the Details! addon is NOT the active backend (Details! has its own look and wins -- see
--     Details.lua's backend priority), and
--   * MetersSavedVars.skinDamageMeter ~= false (on by default).
--
-- It FOLLOWS the global skin mode exactly like the rest of the addon (no separate toggle needed):
--   * Force-Native / stock bars  -> a clean default (subtle border + smooth bar texture + the
--     standard UI font), which is the whole point: Blizzard's raw default looks rough.
--   * a skinner active (AUTO)     -> adopt that skinner's thin-border colour + font (ElvUI,
--     EllesmereUI, ...), the same adoption GetActionButtonBorder/GetActionButtonFont already do.
--
-- Cosmetic ONLY (a border frame we own + font face/flags + statusbar texture). Applied OUT OF
-- COMBAT only (taint-safe -- we never poke a Blizzard combat frame mid-combat) and re-applied on
-- show + after combat, because the meter's rows are pooled/created on demand. The frame's interior
-- layout is left entirely to Blizzard.

local addonName, ns = ...
local uiShared = ns._ui or {}

MetersSavedVars = MetersSavedVars or {}

local CreateFrame       = _G.CreateFrame
local InCombatLockdown  = _G.InCombatLockdown
local ipairs            = ipairs

-- Clean defaults used when nothing is adopted (Force-Native / stock bars).
local DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"   -- smooth, vs the flat stock bar
local DEFAULT_BG          = "Interface\\Tooltips\\UI-Tooltip-Background"
local DEFAULT_EDGE        = "Interface\\Tooltips\\UI-Tooltip-Border"
local PIXEL_EDGE          = "Interface\\Buttons\\WHITE8x8"

local function IsMainline()
  return (not _G.WOW_PROJECT_ID) or (_G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1))
end

local function BlizzMeter()
  local f = _G.DamageMeter
  return (type(f) == "table" and f.GetObjectType) and f or nil
end

-- Active only on Retail, with the Blizzard meter present, Details! NOT the backend, and enabled.
local function Eligible()
  if not IsMainline() then return false end
  if MetersSavedVars.skinDamageMeter == false then return false end
  if _G.GSETracker_DetailsWindowAvailable and _G.GSETracker_DetailsWindowAvailable() then return false end
  return BlizzMeter() ~= nil
end

-- ── Border frame (ours, anchored around the meter -- never touches Blizzard's own art) ──────────
local borderFrame
local function EnsureBorder(meter)
  if borderFrame then return borderFrame end
  borderFrame = CreateFrame("Frame", "GSETracker_DamageMeterSkin", meter, "BackdropTemplate")
  borderFrame:SetPoint("TOPLEFT", meter, "TOPLEFT", -4, 4)
  borderFrame:SetPoint("BOTTOMRIGHT", meter, "BOTTOMRIGHT", 4, -4)
  borderFrame:SetFrameStrata(meter:GetFrameStrata())
  -- Sit at the meter's own level so our backdrop renders BEHIND the content rows (which are
  -- deeper children at a higher level).
  borderFrame:SetFrameLevel(math.max(0, (meter:GetFrameLevel() or 1) - 1))
  return borderFrame
end

local function ApplyBorder(meter)
  local f = EnsureBorder(meter)
  if not f.SetBackdrop then return end
  local r, g, b, thickness = (uiShared.GetSkinnerBorderStyle and uiShared.GetSkinnerBorderStyle())
  if r then
    -- Adopt the active thin-border skinner (ElvUI/EllesmereUI): a pixel line in its own colour.
    f:SetBackdrop({
      bgFile = DEFAULT_BG,
      edgeFile = PIXEL_EDGE,
      edgeSize = thickness or 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropBorderColor(r, g, b, 1)
  else
    -- Clean default (Force-Native / stock bars): a subtle tooltip-style border in the addon's
    -- muted-gold chrome colour.
    f:SetBackdrop({
      bgFile = DEFAULT_BG,
      edgeFile = DEFAULT_EDGE,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropBorderColor(0.60, 0.55, 0.42, 1)
  end
  f:SetBackdropColor(0.05, 0.05, 0.06, 0.55)
  f:Show()
end

-- ── Font + bar walk (the rows are pooled, so re-walk every apply) ────────────────────────────────
local function ResolveFont()
  -- Explicit user pick (Edit Mode Font dropdown) wins over the adopted/default font.
  local pick = MetersSavedVars.skinFont
  if pick and pick ~= "" then return pick, nil end
  local path, flags
  if uiShared.GetAdoptedFontStyle then path, flags = uiShared.GetAdoptedFontStyle() end
  if not path then path = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
  return path, flags
end

local fontCount, barCount = 0, 0
local function SkinFontString(r, fontPath, fontFlags)
  if not (r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetFont and r.SetFont) then return end
  local _, size, curFlags = r:GetFont()
  if size and size > 0 then
    -- Keep Blizzard's SIZE; swap only the face (+ adopted outline when a skinner provides one).
    pcall(r.SetFont, r, fontPath, size, (fontFlags ~= nil and fontFlags ~= "") and fontFlags or curFlags or "")
    fontCount = fontCount + 1
  end
end

local function SkinStatusBar(frame)
  if frame and frame.GetObjectType and frame:GetObjectType() == "StatusBar" and frame.SetStatusBarTexture then
    -- Keep Blizzard's bar COLOUR; swap to the user-picked texture (Edit Mode Bar dropdown) or the
    -- smooth default.
    local tex = (MetersSavedVars.skinBarTexture and MetersSavedVars.skinBarTexture ~= "" and MetersSavedVars.skinBarTexture)
                or DEFAULT_BAR_TEXTURE
    pcall(frame.SetStatusBarTexture, frame, tex)
    barCount = barCount + 1
  end
end

local function Walk(frame, fontPath, fontFlags, depth)
  if not frame or depth > 12 then return end
  if frame.GetRegions then
    for _, r in ipairs({ frame:GetRegions() }) do SkinFontString(r, fontPath, fontFlags) end
  end
  if frame.GetChildren then
    for _, c in ipairs({ frame:GetChildren() }) do
      SkinStatusBar(c)
      Walk(c, fontPath, fontFlags, depth + 1)
    end
  end
end

-- ── Apply / lifecycle ─────────────────────────────────────────────────────────────────────────
local driver  -- throttle frame that re-asserts the skin while the meter is shown (defined below)
local function ApplySkin()
  -- Cosmetic only (SetFont / SetStatusBarTexture / our own border frame) -- taint-safe on this
  -- non-secure HUD frame in or out of combat, so we DON'T bail in combat: the meter restyles itself
  -- during the fight and we need to keep re-asserting or the skin only shows out of combat.
  local meter = BlizzMeter()
  if not meter then return end
  if not Eligible() then
    if borderFrame then borderFrame:Hide() end
    return
  end
  ApplyBorder(meter)
  fontCount, barCount = 0, 0
  local fontPath, fontFlags = ResolveFont()
  Walk(meter, fontPath, fontFlags, 0)
  -- WoW can have several stock meter windows open (DamageMeterSessionWindow1/2/3...). Skin the
  -- font/bars in every shown one, not just whatever sits under the primary DamageMeter frame.
  for i = 1, 5 do
    local sw = _G["DamageMeterSessionWindow" .. i]
    if type(sw) == "table" and sw ~= meter and sw.IsShown and sw:IsShown() then
      Walk(sw, fontPath, fontFlags, 0)
    end
  end
end

-- Blizzard re-applies its OWN font/bar styling whenever the meter updates (a data tick, a stock
-- option change in the Edit Mode panel, a relayout), so a one-shot skin doesn't stick. Re-assert on
-- a light throttle while the meter is shown. (Declared before EnsureHooks so OnShow can start it.)
local _accum = 0
driver = CreateFrame("Frame")
driver:Hide()  -- stays hidden until the meter first exists (EnsureHooks shows it), then runs for good
driver:SetScript("OnUpdate", function(_, elapsed)
  _accum = _accum + (elapsed or 0)
  if _accum < 0.1 then return end
  _accum = 0
  -- Resilient: never self-disable on a transient hidden/ineligible tick (that was the "stops
  -- updating until you toggle an option" bug). Just gate the work and keep ticking.
  local meter = BlizzMeter()
  if meter and meter:IsShown() then ApplySkin() end
end)

local hookedShow = false
local function EnsureHooks()
  local meter = BlizzMeter()
  if not meter or hookedShow then return end
  hookedShow = true
  -- Start the re-assert loop once the meter exists; OnShow also forces an immediate apply.
  meter:HookScript("OnShow", function() driver:Show(); ApplySkin() end)
  driver:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")  -- re-skin out of combat (rows built during the fight)
ev:SetScript("OnEvent", function()
  EnsureHooks()
  ApplySkin()
  -- The player may enable the Blizzard meter AFTER login (it doesn't exist until then). Retry a
  -- couple of times so we hook OnShow once the frame finally appears.
  if not hookedShow and _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(2, function() EnsureHooks(); ApplySkin() end)
    _G.C_Timer.After(5, function() EnsureHooks(); ApplySkin() end)
  end
end)

-- ── Public API ──────────────────────────────────────────────────────────────────────────────────
-- Re-apply (called after a global skin/font change, or manually). Safe to call anytime.
function _G.GSETracker_MeterSkin_Refresh()
  EnsureHooks()
  ApplySkin()
end
