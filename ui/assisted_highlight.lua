local _, ns = ...
local addon = ns
local UI = ns.UI
local API = (ns.Utils and ns.Utils.API) or {}
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local WHITE8X8 = C.TEXTURE_WHITE8X8 or "Interface/Buttons/WHITE8x8"
local uiShared = addon._ui or {}
local UIParent = (API.UIParent and API.UIParent()) or UIParent

local GetCursorPositionInParentSpace

local AssistedHighlight = addon.AssistedHighlight or {}
addon.AssistedHighlight = AssistedHighlight
AssistedHighlight.Provider = AssistedHighlight.Provider or {}
AssistedHighlight.Display = AssistedHighlight.Display or {}

local Provider = AssistedHighlight.Provider
local Display = AssistedHighlight.Display

local function PixelSnap(v, frame)
  if uiShared.PixelSnap then
    return uiShared.PixelSnap(v, frame)
  end
  return tonumber(v) or 0
end

local function SetPointIfChanged(frame, point, anchor, relativePoint, x, y)
  if uiShared.SetPointIfChanged then
    return uiShared.SetPointIfChanged(frame, point, anchor, relativePoint, x, y)
  end
  frame:ClearAllPoints()
  frame:SetPoint(point, anchor, relativePoint, x, y)
  return true
end

local function CanonicalPixelsToParentUnits(value, parent)
  if uiShared.CanonicalPixelsToParentUnits then
    return uiShared.CanonicalPixelsToParentUnits(value, parent)
  end
  return tonumber(value) or 0
end

local function ClampCenteredOffsetsToScreen(frame, parent, x, y)
  if uiShared.ClampCenteredOffsetsToScreen then
    return uiShared.ClampCenteredOffsetsToScreen(frame, parent, x, y)
  end
  return tonumber(x) or 0, tonumber(y) or 0
end

local function ParentUnitsToCanonicalPixels(value, parent)
  if uiShared.ParentUnitsToCanonicalPixels then
    return uiShared.ParentUnitsToCanonicalPixels(value, parent)
  end
  return tonumber(value) or 0
end

local function GetClassColorRGB()
  if uiShared.GetPlayerClassColorRGB then
    return uiShared.GetPlayerClassColorRGB(C.CLASS_FALLBACK_R or 0.20, C.CLASS_FALLBACK_G or 0.60, C.CLASS_FALLBACK_B or 1.00)
  end
  return C.CLASS_FALLBACK_R or 0.20, C.CLASS_FALLBACK_G or 0.60, C.CLASS_FALLBACK_B or 1.00
end

local function GetResolvedBorderColor()
  if addon.GetAssistedHighlightUseClassColor and addon:GetAssistedHighlightUseClassColor() then
    return GetClassColorRGB()
  end
  if addon.GetAssistedHighlightColor then
    return addon:GetAssistedHighlightColor()
  end
  return GetClassColorRGB()
end

local function GetAssistedHighlightLockState()
  if addon.GetAssistedHighlightLocked then
    return addon:GetAssistedHighlightLocked()
  end
  return addon.IsLocked and addon:IsLocked() or false
end

-- Placement mode: while the mirror is enabled, unlocked and out of combat, show
-- and allow dragging it for positioning (same rule as the Action Tracker).
local function IsAssistedHighlightPlacementActive()
  if not (addon.IsAssistedHighlightMirrorEnabled and addon:IsAssistedHighlightMirrorEnabled()) then return false end
  if GetAssistedHighlightLockState() then return false end
  if API.InCombatLockdown and API.InCombatLockdown() then return false end
  return true
end

local function ResolvePointName(value)
  value = tostring(value or C.ANCHOR_CENTER or "CENTER")
  local compact = value:gsub("%s+", ""):upper()
  if compact == "TOPCENTER" then compact = "TOP" end
  if compact == "BOTTOMCENTER" then compact = "BOTTOM" end
  return compact
end

local function IsRenderableAnchorFrame(frame)
  return frame ~= nil
    and frame ~= UIParent
    and frame.IsObjectType
    and frame:IsObjectType("Frame")
    and not (frame.IsForbidden and frame:IsForbidden())
end

-- Resolve the TARGET FRAME PORTRAIT region (round in retail). The portrait is a Texture,
-- not a Frame, so IsRenderableAnchorFrame is too strict -- we use a relaxed check;
-- SetPoint can still anchor to a texture region (we never SetParent to it). The exact
-- frame path varies by WoW version, so try the known candidates in order.
local function ResolveTargetPortraitFrame()
  if API.UnitExists and not API.UnitExists("target") then
    return nil
  end
  local function usable(region)
    if region and region ~= UIParent and region.GetObjectType
      and not (region.IsForbidden and region:IsForbidden())
      and ((not region.IsShown) or region:IsShown()) then
      return region
    end
  end
  local tf = _G.TargetFrame
  local main = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
  return usable(_G.TargetFramePortrait)
      or (tf and usable(tf.portrait))
      or (main and usable(main.Portrait))
      or nil
end

local function ResolveTargetPortraitArtFrame(portrait)
  local function usable(frame)
    if IsRenderableAnchorFrame(frame) and ((not frame.IsShown) or frame:IsShown()) then
      return frame
    end
  end

  local tf = _G.TargetFrame
  local main = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
  local candidates = {}
  local function addCandidate(frame)
    if frame then candidates[#candidates + 1] = frame end
  end
  addCandidate(_G.TargetFrameTextureFrame)
  addCandidate(tf and tf.TargetFrameTextureFrame)
  addCandidate(tf and tf.TextureFrame)
  addCandidate(tf and tf.TargetFrameContainer)
  addCandidate(main and main.TextureFrame)
  addCandidate(main and main.FrameTexture)
  for _, candidate in ipairs(candidates) do
    candidate = usable(candidate)
    if candidate then return candidate end
  end

  local px1, px2, py1, py2
  if portrait and portrait.GetLeft and portrait.GetRight and portrait.GetTop and portrait.GetBottom then
    px1, px2, py1, py2 = portrait:GetLeft(), portrait:GetRight(), portrait:GetBottom(), portrait:GetTop()
  end
  if not (px1 and px2 and py1 and py2) then return nil end

  local best, bestLevel
  local function overlaps(region)
    if not (region and region.GetLeft and region.GetRight and region.GetTop and region.GetBottom) then return false end
    local x1, x2, y1, y2 = region:GetLeft(), region:GetRight(), region:GetBottom(), region:GetTop()
    if not (x1 and x2 and y1 and y2) then return false end
    return x1 < px2 and x2 > px1 and y1 < py2 and y2 > py1
  end
  local function hasPortraitArt(frame)
    if not frame.GetRegions then return false end
    for _, region in ipairs({ frame:GetRegions() }) do
      if region and region ~= portrait and region.GetObjectType and region:GetObjectType() == "Texture"
        and ((not region.IsShown) or region:IsShown())
        and overlaps(region) then
        return true
      end
    end
    return false
  end
  local function scan(frame, depth)
    if depth <= 0 or not (frame and frame.GetChildren) then return end
    for _, child in ipairs({ frame:GetChildren() }) do
      if usable(child) then
        if hasPortraitArt(child) then
          local level = (child.GetEffectiveFrameLevel and child:GetEffectiveFrameLevel()) or child:GetFrameLevel() or 0
          if not bestLevel or level > bestLevel then
            best, bestLevel = child, level
          end
        end
        scan(child, depth - 1)
      end
    end
  end
  scan(tf, 3)
  return best
end

local function ResetAssistedHighlightPointCache(frame)
  if not frame then return end
  frame._gsetrackerPoint = nil
  frame._gsetrackerAnchor = nil
  frame._gsetrackerRelativePoint = nil
  frame._gsetrackerPointX = nil
  frame._gsetrackerPointY = nil
  frame._assistedHighlightAnchorAvailable = nil
end

local function SetAssistedHighlightParent(frame, parent)
  parent = parent or UIParent
  if not frame or frame:GetParent() == parent then return end
  frame:SetParent(parent)
  frame:ClearAllPoints()
  ResetAssistedHighlightPointCache(frame)
end

local function GetLiveAnchorTargetInfo()
  local target = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() or "Screen"
  if target == "Target Nameplate" then
    -- "Target Nameplate" now anchors over the target's PORTRAIT (kept the saved value
    -- for compatibility; the dropdown label reads "Target Portrait").
    return ResolveTargetPortraitFrame(), "Target Nameplate", false, true
  elseif target == "Mouse Cursor" then
    return UIParent, "Mouse Cursor", true, true
  end
  return UIParent, C.UI_PARENT_NAME or "UIParent", false, true
end

local function GetAnchorPointConfig()
  local point, relName, relPoint, x, y = addon:GetAssistedHighlightPoint()
  return ResolvePointName(point), tostring(relName or C.UI_PARENT_NAME or "UIParent"), ResolvePointName(relPoint), tonumber(x) or 0, tonumber(y) or 0
end

local function ApplyResolvedAnchor(frame, parent, point, relativePoint, x, y)
  local appliedX = CanonicalPixelsToParentUnits(x, parent)
  local appliedY = CanonicalPixelsToParentUnits(y, parent)
  appliedX = PixelSnap(appliedX, parent)
  appliedY = PixelSnap(appliedY, parent)
  SetPointIfChanged(frame, point, parent or UIParent, relativePoint, appliedX, appliedY)
  return appliedX, appliedY
end

local function ResolveAppliedAnchorPoints(point, relativePoint)
  point = ResolvePointName(point)
  relativePoint = ResolvePointName(relativePoint)
  return point, relativePoint
end

local function ApplyCursorAnchor(frame, point, relativePoint, x, y)
  local parent = UIParent
  local cursorX, cursorY = GetCursorPositionInParentSpace(parent)
  local width = (parent.GetWidth and parent:GetWidth()) or 0
  local height = (parent.GetHeight and parent:GetHeight()) or 0
  local centerX = width * 0.5
  local centerY = height * 0.5
  local appliedX = ParentUnitsToCanonicalPixels((cursorX - centerX), parent) + (tonumber(x) or 0)
  local appliedY = ParentUnitsToCanonicalPixels((cursorY - centerY), parent) + (tonumber(y) or 0)
  appliedX, appliedY = ClampCenteredOffsetsToScreen(frame, parent, appliedX, appliedY)
  ApplyResolvedAnchor(frame, parent, point, relativePoint, appliedX, appliedY)
  return appliedX, appliedY
end

local function CreateFont(parent, size, outline)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(C.FONT_PATH_FRIZ or "Fonts\\FRIZQT__.TTF", size, outline or "OUTLINE")
  fs:SetJustifyH("RIGHT")
  fs:SetJustifyV("MIDDLE")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.85)
  return fs
end

local function GetSpellTexture(spellID)
  if API.GetSpellTexture then
    local tex = API.GetSpellTexture(spellID)
    if tex then return tex end
  end
  if C_Spell and C_Spell.GetSpellTexture then
    return C_Spell.GetSpellTexture(spellID)
  end
  if _G.GetSpellTexture then
    return _G.GetSpellTexture(spellID)
  end
  return nil
end

local function GetRangeState(actionSlot)
  actionSlot = tonumber(actionSlot)
  if actionSlot and actionSlot > 0 and HasAction and HasAction(actionSlot) and IsActionInRange then
    -- Mirror the same slot-oriented flow Blizzard action buttons use:
    -- 1) verify the slot really exists, 2) verify that the action supports range,
    -- 3) read the in-range bit from the slot itself.
    if ActionHasRange and not ActionHasRange(actionSlot) then
      return nil
    end

    local result = IsActionInRange(actionSlot)
    if result == 1 or result == true then
      return true
    elseif result == 0 or result == false then
      return false
    end
    return nil
  end

  -- Do not approximate live action-bar range from spell-only checks when no real slot
  -- is available. Returning nil keeps the mirror visually neutral instead of stale/wrong.
  return nil
end

local function FormatBindingKey(key)
  if not key or key == "" then return nil end
  if API.GetBindingText then
    local text = API.GetBindingText(key, "KEY_")
    if text and text ~= "" then
      -- GetBindingText returns the full localized string for mouse buttons:
      -- "Mouse Button 1", "Mouse Button 4", etc.  Collapse all to MB<N>.
      text = text:gsub("Mouse Button (%d+)", "MB%1")
      return text
    end
  end
  key = tostring(key)
  key = key:gsub("ALT%-", "A-")
  key = key:gsub("CTRL%-", "C-")
  key = key:gsub("SHIFT%-", "S-")
  key = key:gsub("NUMPAD", "N")
  key = key:gsub("MOUSEWHEELUP", "MWU")
  key = key:gsub("MOUSEWHEELDOWN", "MWD")
  -- Raw BUTTON<N> tokens (when GetBindingText is unavailable): collapse all to MB<N>.
  key = key:gsub("BUTTON(%d+)", "MB%1")
  return key
end

local SLOT_BINDINGS = {
  [1] = "ACTIONBUTTON1", [2] = "ACTIONBUTTON2", [3] = "ACTIONBUTTON3", [4] = "ACTIONBUTTON4", [5] = "ACTIONBUTTON5", [6] = "ACTIONBUTTON6",
  [7] = "ACTIONBUTTON7", [8] = "ACTIONBUTTON8", [9] = "ACTIONBUTTON9", [10] = "ACTIONBUTTON10", [11] = "ACTIONBUTTON11", [12] = "ACTIONBUTTON12",
  [13] = "MULTIACTIONBAR3BUTTON1", [14] = "MULTIACTIONBAR3BUTTON2", [15] = "MULTIACTIONBAR3BUTTON3", [16] = "MULTIACTIONBAR3BUTTON4", [17] = "MULTIACTIONBAR3BUTTON5", [18] = "MULTIACTIONBAR3BUTTON6",
  [19] = "MULTIACTIONBAR3BUTTON7", [20] = "MULTIACTIONBAR3BUTTON8", [21] = "MULTIACTIONBAR3BUTTON9", [22] = "MULTIACTIONBAR3BUTTON10", [23] = "MULTIACTIONBAR3BUTTON11", [24] = "MULTIACTIONBAR3BUTTON12",
  [25] = "MULTIACTIONBAR4BUTTON1", [26] = "MULTIACTIONBAR4BUTTON2", [27] = "MULTIACTIONBAR4BUTTON3", [28] = "MULTIACTIONBAR4BUTTON4", [29] = "MULTIACTIONBAR4BUTTON5", [30] = "MULTIACTIONBAR4BUTTON6",
  [31] = "MULTIACTIONBAR4BUTTON7", [32] = "MULTIACTIONBAR4BUTTON8", [33] = "MULTIACTIONBAR4BUTTON9", [34] = "MULTIACTIONBAR4BUTTON10", [35] = "MULTIACTIONBAR4BUTTON11", [36] = "MULTIACTIONBAR4BUTTON12",
  [37] = "MULTIACTIONBAR2BUTTON1", [38] = "MULTIACTIONBAR2BUTTON2", [39] = "MULTIACTIONBAR2BUTTON3", [40] = "MULTIACTIONBAR2BUTTON4", [41] = "MULTIACTIONBAR2BUTTON5", [42] = "MULTIACTIONBAR2BUTTON6",
  [43] = "MULTIACTIONBAR2BUTTON7", [44] = "MULTIACTIONBAR2BUTTON8", [45] = "MULTIACTIONBAR2BUTTON9", [46] = "MULTIACTIONBAR2BUTTON10", [47] = "MULTIACTIONBAR2BUTTON11", [48] = "MULTIACTIONBAR2BUTTON12",
  [49] = "MULTIACTIONBAR1BUTTON1", [50] = "MULTIACTIONBAR1BUTTON2", [51] = "MULTIACTIONBAR1BUTTON3", [52] = "MULTIACTIONBAR1BUTTON4", [53] = "MULTIACTIONBAR1BUTTON5", [54] = "MULTIACTIONBAR1BUTTON6",
  [55] = "MULTIACTIONBAR1BUTTON7", [56] = "MULTIACTIONBAR1BUTTON8", [57] = "MULTIACTIONBAR1BUTTON9", [58] = "MULTIACTIONBAR1BUTTON10", [59] = "MULTIACTIONBAR1BUTTON11", [60] = "MULTIACTIONBAR1BUTTON12",
  [61] = "MULTIACTIONBAR5BUTTON1", [62] = "MULTIACTIONBAR5BUTTON2", [63] = "MULTIACTIONBAR5BUTTON3", [64] = "MULTIACTIONBAR5BUTTON4", [65] = "MULTIACTIONBAR5BUTTON5", [66] = "MULTIACTIONBAR5BUTTON6",
  [67] = "MULTIACTIONBAR5BUTTON7", [68] = "MULTIACTIONBAR5BUTTON8", [69] = "MULTIACTIONBAR5BUTTON9", [70] = "MULTIACTIONBAR5BUTTON10", [71] = "MULTIACTIONBAR5BUTTON11", [72] = "MULTIACTIONBAR5BUTTON12",
  [73] = "MULTIACTIONBAR6BUTTON1", [74] = "MULTIACTIONBAR6BUTTON2", [75] = "MULTIACTIONBAR6BUTTON3", [76] = "MULTIACTIONBAR6BUTTON4", [77] = "MULTIACTIONBAR6BUTTON5", [78] = "MULTIACTIONBAR6BUTTON6",
  [79] = "MULTIACTIONBAR6BUTTON7", [80] = "MULTIACTIONBAR6BUTTON8", [81] = "MULTIACTIONBAR6BUTTON9", [82] = "MULTIACTIONBAR6BUTTON10", [83] = "MULTIACTIONBAR6BUTTON11", [84] = "MULTIACTIONBAR6BUTTON12",
  [85] = "MULTIACTIONBAR7BUTTON1", [86] = "MULTIACTIONBAR7BUTTON2", [87] = "MULTIACTIONBAR7BUTTON3", [88] = "MULTIACTIONBAR7BUTTON4", [89] = "MULTIACTIONBAR7BUTTON5", [90] = "MULTIACTIONBAR7BUTTON6",
  [91] = "MULTIACTIONBAR7BUTTON7", [92] = "MULTIACTIONBAR7BUTTON8", [93] = "MULTIACTIONBAR7BUTTON9", [94] = "MULTIACTIONBAR7BUTTON10", [95] = "MULTIACTIONBAR7BUTTON11", [96] = "MULTIACTIONBAR7BUTTON12",
  [97] = "MULTIACTIONBAR8BUTTON1", [98] = "MULTIACTIONBAR8BUTTON2", [99] = "MULTIACTIONBAR8BUTTON3", [100] = "MULTIACTIONBAR8BUTTON4", [101] = "MULTIACTIONBAR8BUTTON5", [102] = "MULTIACTIONBAR8BUTTON6",
  [103] = "MULTIACTIONBAR8BUTTON7", [104] = "MULTIACTIONBAR8BUTTON8", [105] = "MULTIACTIONBAR8BUTTON9", [106] = "MULTIACTIONBAR8BUTTON10", [107] = "MULTIACTIONBAR8BUTTON11", [108] = "MULTIACTIONBAR8BUTTON12",
}

-- Maps Blizzard default action button frame names to their binding command names.
-- Unlike SLOT_BINDINGS (slot→command), this mapping is keyed on the FRAME NAME and is
-- stable regardless of action bar paging, stances, or bar visibility.
-- Slot 13 may be shown by ActionButton1 (main bar page 2) OR MultiBarRightButton1
-- (fixed right bar).  SLOT_BINDINGS[13] = MULTIACTIONBAR3BUTTON1, which is wrong for
-- the paged case.  Frame-name lookup is always right: ActionButton1 → ACTIONBUTTON1.
local BUTTON_NAME_TO_BINDING = {}
do
  local function _reg(prefix, bindPrefix, count)
    for i = 1, count do
      BUTTON_NAME_TO_BINDING[prefix .. i] = bindPrefix .. i
    end
  end
  _reg("ActionButton",               "ACTIONBUTTON",          12)
  _reg("MultiBarBottomLeftButton",   "MULTIACTIONBAR1BUTTON", 12)
  _reg("MultiBarBottomRightButton",  "MULTIACTIONBAR2BUTTON", 12)
  _reg("MultiBarRightButton",        "MULTIACTIONBAR3BUTTON", 12)
  _reg("MultiBarLeftButton",         "MULTIACTIONBAR4BUTTON", 12)
  -- Override Action Bar shares ACTIONBUTTON bindings (vehicle / possess bar).
  _reg("OverrideActionBarButton",    "ACTIONBUTTON",           6)
end

local LIVE_REFRESH_INTERVAL = 0.12
local HASHLESS_REFRESH_INTERVAL = 0.25
local ACTION_SLOT_CACHE_MAX = 64

local function IsEditingAssistedHighlightTab()
  if not addon._editingOptions then return false end
  local settingsWindow = addon.settingsWindow
  if not (settingsWindow and settingsWindow.GetSelectedTopTab) then return true end
  return settingsWindow:GetSelectedTopTab() == "AssistedHighlight"
end

local StopPortraitGCDSwipe

local function SetMirrorShown(frame, shouldShow)
  if not frame then return end
  shouldShow = shouldShow and true or false

  local shownChanged = frame._assistedHighlightShown ~= shouldShow
  local actualMismatch = (shouldShow and (not frame:IsShown())) or ((not shouldShow) and frame:IsShown())
  if not shownChanged and not actualMismatch then
    return
  end

  frame._assistedHighlightShown = shouldShow
  if shouldShow then
    frame:Show()
  else
    if StopPortraitGCDSwipe then StopPortraitGCDSwipe(frame) end
    frame:Hide()
  end
end

local function MarkAssistedHighlightDirty(reason)
  addon._assistedHighlightDirty = true
  if reason ~= nil then
    addon._assistedHighlightDirtyReason = reason
  end
end

local function MarkAssistedHighlightPositionDirty()
  addon._assistedHighlightPositionDirty = true
end

local function CacheActionSlot(self, spellID, slot)
  if not spellID then return end
  self._actionSlotCache = self._actionSlotCache or {}
  local cache = self._actionSlotCache

  if cache[spellID] == nil then
    local count = self._actionSlotCacheCount or 0
    if count >= ACTION_SLOT_CACHE_MAX then
      if API.wipe then
        API.wipe(cache)
      else
        for key in pairs(cache) do
          cache[key] = nil
        end
      end
      count = 0
    end
    self._actionSlotCacheCount = count + 1
  end

  cache[spellID] = slot
end

local function GetBindingForActionSlot(slot)
  slot = tonumber(slot) or 0
  if slot <= 0 then return nil end
  Provider._bindingCache = Provider._bindingCache or {}
  local cached = Provider._bindingCache[slot]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end

  local command = SLOT_BINDINGS[slot]
  if not command or not GetBindingKey then
    Provider._bindingCache[slot] = false
    return nil
  end

  local key1, key2 = GetBindingKey(command)
  key1 = key1 and FormatBindingKey(key1) or nil
  key2 = key2 and FormatBindingKey(key2) or nil
  local value = key1 or key2
  if key1 and key2 then
    value = key1 .. " / " .. key2
  end
  Provider._bindingCache[slot] = value or false
  return value
end

-- Resolve the keybind for an action button by its FRAME NAME, not its slot number.
-- This is always correct regardless of action bar paging:
--   ActionButton1.action may be 1 (page 1) or 13 (page 2), but its binding command
--   is always ACTIONBUTTON1.  SLOT_BINDINGS[13] would return MULTIACTIONBAR3BUTTON1,
--   which is wrong for a paged main bar.  Frame-name lookup has no such ambiguity.
local function GetBindingForButton(button)
  if not button then return nil end
  local name = button.GetName and button:GetName()
  if not name then return nil end
  Provider._buttonBindingCache = Provider._buttonBindingCache or {}
  local cached = Provider._buttonBindingCache[name]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local cmd = BUTTON_NAME_TO_BINDING[name]
  if not cmd or not GetBindingKey then
    Provider._buttonBindingCache[name] = false
    return nil
  end
  local k1, k2 = GetBindingKey(cmd)
  k1 = k1 and FormatBindingKey(k1) or nil
  k2 = k2 and FormatBindingKey(k2) or nil
  local value = k1 or k2
  if k1 and k2 then value = k1 .. " / " .. k2 end
  Provider._buttonBindingCache[name] = value or false
  return value
end

local function SpellMatchesActionSlot(slot, spellID, slotType, id, subType)
  if not slot or not spellID then return false end
  if slotType == nil and GetActionInfo then
    slotType, id, subType = GetActionInfo(slot)
  end
  -- Assisted-combat slots are found by FindAssistedCombatSlot, not by spell-ID search.
  -- Matching them here causes a tautology: GetActionSpell() always equals the spell we
  -- are searching for, so every assistedcombat slot unconditionally matches, and the
  -- first one in slot-number order (which may belong to a visually-stacked wrong bar)
  -- is returned instead of the slot the player actually presses.
  if subType == "assistedcombat" then return false end
  if slotType == "spell" then
    if tonumber(id) == tonumber(spellID) then
      return true
    end
  end
  if C_ActionBar and C_ActionBar.GetSpell then
    local actionSpell = C_ActionBar.GetSpell(slot)
    if tonumber(actionSpell) == tonumber(spellID) then
      return true
    end
  end
  return false
end

-- ── Assisted-combat slot discovery ────────────────────────────────────────────
-- Find the slot that holds the Blizzard Rotation Helper (assisted-combat) action.
-- This is the EXACT slot Blizzard highlights; its binding is always the correct
-- keybind regardless of which spell is currently recommended.
--
-- Design notes:
--   • Do NOT gate on HasAction().  HasAction returns false when the action is
--     currently unusable (OOM, on cooldown, no target).  That would cause the
--     scan to skip the correct slot and fall through to a wrong one.  GetActionInfo
--     alone is authoritative for slot-identity purposes.
--   • Do NOT require slotType == "spell".  The subType field alone uniquely
--     identifies the Rotation Helper action; guarding on slotType makes the check
--     brittle against future API shape changes.
--   • false  = scanned the full bar, not found
--   • nil    = not yet scanned (triggers scan on next call)
local function FindAssistedCombatSlot(self)
  if self._assistedCombatSlot ~= nil then
    return self._assistedCombatSlot ~= false and self._assistedCombatSlot or nil
  end

  if not GetActionInfo then
    self._assistedCombatSlot = false
    return nil
  end

  for slot = 1, 120 do
    local _, _, subType = GetActionInfo(slot)
    if subType == "assistedcombat" then
      self._assistedCombatSlot = slot
      return slot
    end
  end

  self._assistedCombatSlot = false
  return nil
end

-- ── Glow hook (authoritative keybind signal) ──────────────────────────────────
-- Hook Blizzard's ActionButton_ShowOverlayGlow / ActionButton_HideOverlayGlow to
-- track which action button frames Blizzard is currently highlighting.
--
-- This is more reliable than slot-number ordering or frame-level sorting because:
--  • Blizzard calls ShowOverlayGlow on the EXACT button it wants the player to press.
--  • button.action gives the real action slot, regardless of bar name or position.
--  • No guesswork about frame names, prefix lists, or visual stacking order.
--
-- Provider._glowedButtonList : { {slot=N, button=F}, … } for each currently-glowing button.
-- Cleared on PLAYER_ENTERING_WORLD (bar layout reset) and ACTIONBAR_SLOT_CHANGED.

local function SetupGlowHook(provider)
  if provider._glowHookDone then return end
  provider._glowHookDone = true

  -- Track {slot, button} pairs rather than bare slot numbers.
  -- Blizzard fires ShowOverlayGlow on EVERY button that shows the recommended spell,
  -- including buttons on hidden/disabled bars.  Storing the button frame lets
  -- GetState filter by visibility and pick the topmost visible button, rather than
  -- selecting randomly from all glowed slots via pairs() with undefined order.
  local function OnGlowShow(button)
    local slot = button and tonumber(
      button.action or (button.GetAttribute and button:GetAttribute("action")))
    if not (slot and slot >= 1 and slot <= 120) then return end
    provider._glowedButtonList = provider._glowedButtonList or {}
    local list = provider._glowedButtonList
    for _, entry in ipairs(list) do
      if entry.button == button then return end  -- already tracked
    end
    list[#list + 1] = { slot = slot, button = button }
    provider:MarkDirty()
    MarkAssistedHighlightDirty("GlowShow")
  end

  local function OnGlowHide(button)
    local list = provider._glowedButtonList
    if not list then return end
    for i = #list, 1, -1 do
      if list[i].button == button then
        table.remove(list, i)
        break
      end
    end
    provider:MarkDirty()
    MarkAssistedHighlightDirty("GlowHide")
  end

  API.SafeHooksecurefunc("ActionButton_ShowOverlayGlow", OnGlowShow)
  API.SafeHooksecurefunc("ActionButton_HideOverlayGlow", OnGlowHide)
end

-- ── Frame-priority slot lookup ─────────────────────────────────────────────────
-- When the same spell exists on multiple bars (stacked / overlapping layout), the
-- slot-number scan (1→120) is wrong: it returns the lowest slot regardless of which
-- bar is visually on top and which key the player actually presses.
--
-- The correct answer is the button with the highest effective frame level — that is
-- the button "on top" in the visual stack, the one that intercepts mouse input, and
-- the one whose keybind the player uses.
--
-- We build this registry once per session from standard Blizzard action bar frame
-- names and sort it by GetEffectiveFrameLevel() descending.  It is invalidated on
-- ACTIONBAR_SLOT_CHANGED, PLAYER_ENTERING_WORLD, and PLAYER_SPECIALIZATION_CHANGED.
--
-- AddOn-created bars (Bartender4, Dominos, etc.) are not in the registry; if no
-- frame-priority match is found, FindActionSlotForSpell provides the slot-scan
-- fallback that covers them.

local _buttonRegistry        = nil   -- { {slot=N, frame=F}, … } sorted desc by level
local _buttonRegistryValid   = false

-- Standard Blizzard action bar button name prefixes (Retail / TWW / Midnight).
-- Count is always 12 per bar.  Names are part of the shipped UI and are stable.
local BUTTON_PREFIXES = {
  "ActionButton",
  "MultiBarBottomLeftButton",
  "MultiBarBottomRightButton",
  "MultiBarRightButton",
  "MultiBarLeftButton",
}
local BUTTONS_PER_BAR = 12

local function InvalidateButtonRegistry()
  _buttonRegistryValid = false
end

local function GetButtonRegistry()
  if _buttonRegistryValid and _buttonRegistry then
    return _buttonRegistry
  end

  local reg = _buttonRegistry or {}
  _buttonRegistry = reg
  for i = #reg, 1, -1 do reg[i] = nil end   -- wipe in-place, reuse table

  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, BUTTONS_PER_BAR do
      local btn = _G[prefix .. i]
      if btn and type(btn) == "table" then
        -- btn.action is set by Blizzard's ActionButton_Update; GetAttribute is the
        -- secure-frame fallback for buttons created by some addon bars.
        local slot = btn.action
        if slot == nil and btn.GetAttribute then
          slot = tonumber(btn:GetAttribute("action"))
        end
        slot = tonumber(slot)
        if slot and slot >= 1 and slot <= 120 then
          reg[#reg + 1] = { slot = slot, frame = btn }
        end
      end
    end
  end

  -- Sort: highest effective frame level first (visually topmost button).
  -- GetEffectiveFrameLevel sums the frame's own level plus all parent levels,
  -- giving the true draw order.  Tiebreak by slot ascending so the result is
  -- deterministic when levels are equal (common on same-strata bars).
  table.sort(reg, function(a, b)
    local la = (a.frame.GetEffectiveFrameLevel and a.frame:GetEffectiveFrameLevel())
            or (a.frame.GetFrameLevel          and a.frame:GetFrameLevel()) or 0
    local lb = (b.frame.GetEffectiveFrameLevel and b.frame:GetEffectiveFrameLevel())
            or (b.frame.GetFrameLevel          and b.frame:GetFrameLevel()) or 0
    if la ~= lb then return la > lb end
    return (a.slot or 999) < (b.slot or 999)
  end)

  _buttonRegistryValid = true
  return reg
end

-- Find the action slot for spellID by iterating known button frames in visual
-- priority order (topmost bar first).  Returns slot, frame for the first match;
-- nil, nil if none found.
local function FindSlotByFramePriority(spellID)
  local reg = GetButtonRegistry()
  for _, entry in ipairs(reg) do
    if SpellMatchesActionSlot(entry.slot, spellID) then
      return entry.slot, entry.frame
    end
  end
  return nil, nil
end

-- Return the first registered button frame whose current .action == slot.
-- Used to attach a button frame to an assistedcombat or raw-scan slot result so
-- GetBindingForButton can be used instead of the SLOT_BINDINGS fallback.
local function FindButtonForSlot(slot)
  if not slot then return nil end
  local reg = GetButtonRegistry()
  for _, entry in ipairs(reg) do
    if entry.slot == slot then
      return entry.frame
    end
  end
  return nil
end

function Provider:FindActionSlotForSpell(spellID)
  if not spellID then return nil end
  self._actionSlotCache = self._actionSlotCache or {}

  local cachedSlot = self._actionSlotCache[spellID]
  if cachedSlot and SpellMatchesActionSlot(cachedSlot, spellID) then
    return cachedSlot
  end
  self._actionSlotCache[spellID] = nil

  -- Single pass: find the slot containing the spell.
  -- Assisted-combat slots are excluded by SpellMatchesActionSlot; they are resolved
  -- separately by FindAssistedCombatSlot and used for the keybind in GetState.
  if GetActionInfo then
    for slot = 1, 120 do
      if (not HasAction) or HasAction(slot) then  ---@diagnostic disable-line: undefined-global
        local slotType, id, subType = GetActionInfo(slot)
        if SpellMatchesActionSlot(slot, spellID, slotType, id, subType) then
          CacheActionSlot(self, spellID, slot)
          return slot
        end
      end
    end
  end
  return nil
end

-- Resolve the keybind for a spell by its ICON TEXTURE: find an action slot whose
-- texture matches and return its key (frame-name binding preferred, slot-number map
-- fallback) -- the same resolver the assisted-highlight icon uses, but keyed by texture
-- so the recent-spell icons can show whatever key the spell is bound to (GSE override
-- OR a plain Blizzard binding). Returns the formatted key string, or nil if the spell
-- isn't on a bar / has no binding. Read-only (no hooks, no taint).
function UI:GetTextureKeybindText(texture)
  if not texture or texture == "" or not GetActionInfo then return nil end  ---@diagnostic disable-line: undefined-global
  for slot = 1, 120 do
    if (not HasAction) or HasAction(slot) then  ---@diagnostic disable-line: undefined-global
      local t = GetActionTexture and GetActionTexture(slot)  ---@diagnostic disable-line: undefined-global
      if t and t == texture then
        local button = FindButtonForSlot(slot)
        local key = (button and GetBindingForButton(button)) or GetBindingForActionSlot(slot)
        if key and key ~= "" then return key end
      end
    end
  end
  return nil
end

function Provider:MarkDirty()
  self._stateDirty = true
end

function Provider:IsAvailable()
  return C_AssistedCombat and C_AssistedCombat.IsAvailable and C_AssistedCombat.IsAvailable() or false
end

-- Source the recommended spell EXACTLY like Gnomester's MyAHLight: ask
-- C_AssistedCombat directly and NEVER touch the action bars.
--   • GetNextCastSpell() with NO argument is taint-free. (The checkForVisibleButton
--     = true variant is what pokes Blizzard's on-bar highlight system and taints
--     ON_BAR_HIGHLIGHT_MARKS, which then hides empty action-bar slots while you
--     drag a spell onto your bars.)
--   • GetActionSpell() is the fallback when there is no specific next cast.
function Provider:GetRecommendedSpellID()
  if not C_AssistedCombat then return nil end
  if type(C_AssistedCombat.GetNextCastSpell) == "function" then
    local id = C_AssistedCombat.GetNextCastSpell()
    if id and id ~= 0 then return tonumber(id) end
  end
  if type(C_AssistedCombat.GetActionSpell) == "function" then
    local id = C_AssistedCombat.GetActionSpell()
    if id and id ~= 0 then return tonumber(id) end
  end
  return nil
end

function Provider:GetState(force)
  -- Gnomester MyAHLight pattern: get the recommended spell from C_AssistedCombat
  -- and show that SPELL'S OWN icon on our own frame. We never read or scan the
  -- real ActionButton / MultiBar frames for the icon, so we never entangle with
  -- Blizzard's ON_BAR_HIGHLIGHT_MARKS subsystem -- which is the thing that was
  -- hiding the empty action-bar slots when dragging a spell.
  local spellID = self:GetRecommendedSpellID()
  if not spellID then
    self._lastState = nil
    self._stateDirty = false
    return nil
  end

  local texture = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
               or (GetSpellTexture and GetSpellTexture(spellID)) or nil
  if not texture then
    self._lastState = nil
    self._stateDirty = false
    return nil
  end

  -- Keybind + range are OPTIONAL extras. We locate the slot with a plain
  -- GetActionInfo scan (read-only, taint-free) -- NOT the glow hook or frame-
  -- priority registry, which were the parts that reached into live action buttons.
  -- If the spell isn't on a bar we simply show the icon with no keybind.
  local bindSlot = self:FindActionSlotForSpell(spellID)
  -- Keybind: prefer the button FRAME NAME (paging-safe, e.g. ACTIONBUTTON1) over the
  -- slot-number map; fall back to slot bindings only when no frame is found. Both are
  -- read-only (FindButtonForSlot just reads btn.action) -- no hooks, no taint.
  local bindButton = bindSlot and FindButtonForSlot(bindSlot) or nil
  local keybind  = (bindButton and GetBindingForButton(bindButton))
                or (bindSlot and GetBindingForActionSlot(bindSlot)) or nil
  -- NOTE: do NOT write `bindSlot and GetRangeState(bindSlot) or nil` -- when
  -- GetRangeState returns FALSE (out of range) the `or nil` collapses it to nil,
  -- so state.inRange would never be false and the grey-out never triggers.
  local inRange
  if bindSlot then inRange = GetRangeState(bindSlot) end

  -- Charge/stack count, mirroring Blizzard's ActionButton.Count: show the number
  -- only for spells that actually have multiple charges (e.g. 2-charge abilities).
  -- IMPORTANT: ci.currentCharges of the assisted next-cast spell is a "secret"
  -- value in tainted execution -- it can be DISPLAYED (SetText) but NOT compared,
  -- or it throws "attempt to compare a secret value". So we keep a SAFE boolean
  -- (hasCount, from the non-secret maxCharges) for the cache/show logic and never
  -- compare the secret count itself.
  local count, hasCount
  if C_Spell and C_Spell.GetSpellCharges then
    local ci = C_Spell.GetSpellCharges(spellID)
    if ci and (ci.maxCharges or 0) > 1 then
      count = ci.currentCharges
      hasCount = true
    end
  end
  hasCount = hasCount and true or false

  local lastState = self._lastState
  if not force and (not self._stateDirty) and lastState
    and lastState.spellID == spellID
    and lastState.bindSlot == bindSlot
    and lastState.texture == texture
    and lastState.keybind == keybind
    and lastState.inRange == inRange
    and lastState.hasCount == hasCount then
    return lastState
  end

  local state = lastState or {}
  state.spellID = spellID
  state.texture = texture
  state.bindSlot = bindSlot
  state.actionSlot = bindSlot
  state.keybind = keybind
  state.inRange = inRange
  state.count = count
  state.hasCount = hasCount
  state.isAssistedFallback = nil
  self._lastState = state
  self._stateDirty = false
  return state
end

function Display:ApplyFont(frame)
  frame = frame or addon.assistedHighlightFrame
  if not (frame and frame.keybindText) then return end
  local fontName = (addon.GetAssistedHighlightFontName and addon:GetAssistedHighlightFontName()) or (addon.GetKeybindFontName and addon:GetKeybindFontName()) or (addon.GetModFontName and addon:GetModFontName()) or (addon.DEFAULT_MOD_FONT or C.FONT_FRIZ or "Friz Quadrata TT")
  local fontSize = tonumber((addon.GetAssistedHighlightFontSize and addon:GetAssistedHighlightFontSize()) or (addon.GetKeybindFontSize and addon:GetKeybindFontSize()) or 8) or 8
  local fontVersion = addon._fontRegistryVersion or 0
  if frame._assistedHighlightFontName == fontName
    and frame._assistedHighlightFontSize == fontSize
    and frame._assistedHighlightFontVersion == fontVersion then
    return
  end
  local fontPath = (addon.GetFontPathByName and addon:GetFontPathByName(fontName)) or C.FONT_PATH_FRIZ or STANDARD_TEXT_FONT
  frame._assistedHighlightFontName = fontName
  frame._assistedHighlightFontPath = fontPath
  frame._assistedHighlightFontSize = fontSize
  frame._assistedHighlightFontVersion = fontVersion
  if not frame.keybindText:SetFont(fontPath, fontSize, "OUTLINE") then
    frame.keybindText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
  end
  if frame.countText then
    if not frame.countText:SetFont(fontPath, fontSize, "OUTLINE") then
      frame.countText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    end
  end
end

-- Per-corner placement model for the keybind text. sx/sy give the inset direction
-- from that corner (negative = left/down at a TOP/RIGHT anchor); CENTER has no inset.
local AH_KEYBIND_ANCHORS = {
  TOPRIGHT    = { point = "TOPRIGHT",    jh = "RIGHT",  jv = "TOP",    sx = -1, sy = -1 },
  TOPLEFT     = { point = "TOPLEFT",     jh = "LEFT",   jv = "TOP",    sx =  1, sy = -1 },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", jh = "RIGHT",  jv = "BOTTOM", sx = -1, sy =  1 },
  BOTTOMLEFT  = { point = "BOTTOMLEFT",  jh = "LEFT",   jv = "BOTTOM", sx =  1, sy =  1 },
  CENTER      = { point = "CENTER",      jh = "CENTER", jv = "MIDDLE", sx =  0, sy =  0 },
}

function Display:ApplyKeybindPosition(frame)
  frame = frame or addon.assistedHighlightFrame
  if not frame then return end
  -- Mirror Blizzard's ActionButton text placement:
  --   HotKey (keybind) -> TOP-RIGHT corner, right-justified
  --   Count  (charges) -> BOTTOM-RIGHT corner, right-justified
  -- The inset scales with the icon so the text sits in the corner at any size
  -- (~2px on a 36px icon, like Blizzard). The keybind offset slider nudges the
  -- keybind from that corner.
  local w = (frame.GetWidth and frame:GetWidth()) or 36
  local inset = math.max(1, w * 0.06)

  if frame.keybindText then
    -- The keybind text anchors to one of the icon's four corners or its centre
    -- (user-selectable), inset INWARD so the text sits inside the icon (Blizzard
    -- HotKey style). The inset direction (sx/sy) and text justification follow the
    -- chosen corner; CENTER uses no inset and centred justification. We intentionally
    -- ignore the legacy keybind X/Y offset (tuned for an old CENTER-only layout).
    local anchorKey = (addon.GetAssistedHighlightKeybindAnchor and addon:GetAssistedHighlightKeybindAnchor()) or "TOPRIGHT"
    local a = AH_KEYBIND_ANCHORS[anchorKey] or AH_KEYBIND_ANCHORS.TOPRIGHT
    local px = PixelSnap(a.sx * (inset + 5), frame)
    local py = PixelSnap(a.sy * (inset + 2), frame)
    if frame._assistedHighlightKeybindAnchor ~= anchorKey
      or frame._assistedHighlightKeybindX ~= px or frame._assistedHighlightKeybindY ~= py then
      frame._assistedHighlightKeybindAnchor = anchorKey
      frame._assistedHighlightKeybindX = px
      frame._assistedHighlightKeybindY = py
      frame.keybindText:ClearAllPoints()
      frame.keybindText:SetPoint(a.point, frame, a.point, px, py)
      frame.keybindText:SetJustifyH(a.jh)
      frame.keybindText:SetJustifyV(a.jv)
    end
  end

  if frame.countText then
    -- Mirror the keybind's corner padding (5px left, 2px in) so the bottom-right
    -- stack count lines up symmetrically with the top-right keybind.
    local cx = PixelSnap(-inset - 5, frame)
    local cy = PixelSnap(inset + 2, frame)
    if frame._assistedHighlightCountX ~= cx or frame._assistedHighlightCountY ~= cy then
      frame._assistedHighlightCountX = cx
      frame._assistedHighlightCountY = cy
      frame.countText:ClearAllPoints()
      frame.countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", cx, cy)
      frame.countText:SetJustifyH("RIGHT")
      frame.countText:SetJustifyV("BOTTOM")
    end
  end
end

-- Owns a single circular MaskTexture on the AH frame (frame._gsetPortraitMask),
-- used in Target Portrait mode to round the icon to match the round target portrait.
local function EnsurePortraitMask(frame, w, h)
  local m = frame._gsetPortraitMask
  if not m then m = frame:CreateMaskTexture(); frame._gsetPortraitMask = m end
  m:SetTexture(C.MASK_CIRCLE or "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:Show()
  m:ClearAllPoints()
  if not w or w <= 0 then w = uiShared.ICON_SIZE or 45 end
  if not h or h <= 0 then h = w end
  m:SetSize(w, h)
  m:SetPoint("CENTER", frame, "CENTER", 0, 0)
  return m
end

local function SetTextureMask(tex, mask, key)
  if not (tex and tex.AddMaskTexture and tex.RemoveMaskTexture) then return end
  key = key or "_gsetMaskHandle"
  if tex[key] == mask then return end
  if tex[key] then tex:RemoveMaskTexture(tex[key]) end
  if mask then tex:AddMaskTexture(mask) end
  tex[key] = mask
end

local COOLDOWN_SWIPE_TEXTURE_KEYS = {
  "SwipeTexture",
  "swipeTexture",
  "CooldownSwipeTexture",
  "cooldownSwipeTexture",
  "Swipe",
  "swipe",
}

local function AddCooldownSwipeTexture(list, seen, tex)
  if not (tex and tex.GetObjectType and tex:GetObjectType() == "Texture" and tex.AddMaskTexture and tex.RemoveMaskTexture) then return end
  if seen[tex] then return end
  seen[tex] = true
  list[#list + 1] = tex
end

local function GetCooldownSwipeTextures(cd)
  local list, seen = {}, {}
  if not cd then return list end
  if cd.GetCooldownSwipeTexture then AddCooldownSwipeTexture(list, seen, cd:GetCooldownSwipeTexture()) end
  if cd.GetSwipeTexture then AddCooldownSwipeTexture(list, seen, cd:GetSwipeTexture()) end
  for _, key in ipairs(COOLDOWN_SWIPE_TEXTURE_KEYS) do
    AddCooldownSwipeTexture(list, seen, cd[key])
  end
  if cd.GetRegions then
    for _, region in ipairs({ cd:GetRegions() }) do
      AddCooldownSwipeTexture(list, seen, region)
    end
  end
  return list
end

local function ApplyCooldownSwipeMask(frame, mask)
  local cd = frame and frame.cooldown
  if not cd then return end
  local active = {}
  for _, tex in ipairs(GetCooldownSwipeTextures(cd)) do
    active[tex] = true
    SetTextureMask(tex, mask, "_gsetSwipeMask")
  end
  if cd._gsetSwipeMaskTextures then
    for tex in pairs(cd._gsetSwipeMaskTextures) do
      if not active[tex] then SetTextureMask(tex, nil, "_gsetSwipeMask") end
    end
  end
  cd._gsetSwipeMaskTextures = active
end

local function ConfigureGCDCooldown(cd)
  if not cd then return end
  if cd.SetDrawEdge             then cd:SetDrawEdge(false)             end
  if cd.SetDrawBling            then cd:SetDrawBling(false)            end
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true)  end
  if cd.SetDrawSwipe            then cd:SetDrawSwipe(true)             end
  if cd.SetReverse              then cd:SetReverse(false)             end
  if cd.SetSwipeColor           then cd:SetSwipeColor(0, 0, 0, 0.65)   end
end

local function EnsurePortraitCooldown(frame)
  if not frame then return nil end
  if frame.portraitCooldown then return frame.portraitCooldown end
  local cd = API.CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  ConfigureGCDCooldown(cd)
  if cd.SetUseCircularEdge then cd:SetUseCircularEdge(true) end
  cd:Hide()
  frame.portraitCooldown = cd
  return cd
end

local function HideCooldown(cd)
  if not cd then return end
  cd:SetCooldown(0, 0)
  cd:Hide()
end

local PORTRAIT_GCD_GRID = 18
local TWO_PI = math.pi * 2

local function Atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
  if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end

local function GetPortraitGCDCellAngle(col, row, grid)
  local cx = ((col + 0.5) / grid) - 0.5
  local cy = 0.5 - ((row + 0.5) / grid)
  local angle = Atan2(cx, cy) -- clockwise from 12 o'clock.
  if angle < 0 then angle = angle + TWO_PI end
  return angle / TWO_PI, math.sqrt((cx * cx) + (cy * cy))
end

local function ApplyPortraitGCDCellMask(frame, mask)
  local cells = frame and frame._portraitGCDCells
  if not cells then return end
  for _, cell in ipairs(cells) do
    SetTextureMask(cell, mask, "_gsetSwipeMask")
  end
end

local function EnsurePortraitGCDCells(frame, texture, width, height)
  if not frame then return nil end
  local cells = frame._portraitGCDCells
  local grid = PORTRAIT_GCD_GRID
  if not cells then
    cells = {}
    frame._portraitGCDCells = cells
    for row = 0, grid - 1 do
      for col = 0, grid - 1 do
        local cell = frame:CreateTexture(nil, "OVERLAY")
        if cell.SetDrawLayer then cell:SetDrawLayer("OVERLAY", 2) end
        cell:SetBlendMode("BLEND")
        cell:Hide()
        cell._gcdAngleProgress, cell._gcdRadius = GetPortraitGCDCellAngle(col, row, grid)
        cell._gcdCol = col
        cell._gcdRow = row
        cells[#cells + 1] = cell
      end
    end
  end

  width = tonumber(width) or 0
  height = tonumber(height) or 0
  if width <= 0 then width = uiShared.ICON_SIZE or 45 end
  if height <= 0 then height = width end
  local layoutKey = tostring(texture or "") .. ":" .. tostring(width) .. ":" .. tostring(height) .. ":" .. tostring(frame._gsetPortraitMask)
  if frame._portraitGCDLayoutKey ~= layoutKey then
    frame._portraitGCDLayoutKey = layoutKey
    local icon = frame.icon or frame
    local cellW = width / grid
    local cellH = height / grid
    for _, cell in ipairs(cells) do
      local col, row = cell._gcdCol or 0, cell._gcdRow or 0
      cell:SetTexture(texture or (C.TEXTURE_WHITE8X8 or WHITE8X8))
      cell:SetVertexColor(0, 0, 0, 0.65)
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", icon, "TOPLEFT", cellW * col, -(cellH * row))
      cell:SetSize(cellW + 0.5, cellH + 0.5)
      cell:SetTexCoord(col / grid, (col + 1) / grid, row / grid, (row + 1) / grid)
      SetTextureMask(cell, frame._gsetPortraitMask, "_gsetSwipeMask")
    end
  end
  return cells
end

StopPortraitGCDSwipe = function(frame)
  if not frame then return end
  if frame.portraitGCDSwipe then frame.portraitGCDSwipe:Hide() end
  if frame._portraitGCDCells then
    for _, cell in ipairs(frame._portraitGCDCells) do cell:Hide() end
  end
  if frame.portraitGCDDriver then
    frame.portraitGCDDriver:SetScript("OnUpdate", nil)
    frame.portraitGCDDriver:Hide()
  end
  frame._portraitGCDStart = nil
  frame._portraitGCDDuration = nil
  frame._portraitGCDModRate = nil
end

local function UpdatePortraitGCDSwipeVisual(frame)
  if not frame then return false end
  local start = tonumber(frame._portraitGCDStart) or 0
  local duration = tonumber(frame._portraitGCDDuration) or 0
  if start <= 0 or duration <= 0 then
    StopPortraitGCDSwipe(frame)
    return false
  end

  local now = (API.GetTime and API.GetTime()) or 0
  local modRate = tonumber(frame._portraitGCDModRate) or 1
  if modRate <= 0 then modRate = 1 end
  local remaining = duration - ((now - start) * modRate)
  if remaining <= 0 then
    StopPortraitGCDSwipe(frame)
    return false
  end

  local icon = frame.icon
  local w = (icon and icon.GetWidth and icon:GetWidth()) or (frame.GetWidth and frame:GetWidth()) or 0
  local h = (icon and icon.GetHeight and icon:GetHeight()) or (frame.GetHeight and frame:GetHeight()) or 0
  if w <= 0 then w = uiShared.ICON_SIZE or 45 end
  if h <= 0 then h = w end

  local frac = remaining / duration
  if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
  local elapsedFrac = 1 - frac
  local texture = frame._assistedHighlightTexture or (icon and icon.GetTexture and icon:GetTexture())
  local cells = EnsurePortraitGCDCells(frame, texture, w, h)
  if not cells then return false end
  for _, cell in ipairs(cells) do
    local showCell = elapsedFrac <= 0
      or cell._gcdRadius < 0.08
      or ((cell._gcdAngleProgress or 0) >= elapsedFrac)
    if showCell then
      if not cell:IsShown() then cell:Show() end
    elseif cell:IsShown() then
      cell:Hide()
    end
  end
  return true
end

local function PortraitGCDSwipeOnUpdate(driver)
  local frame = driver and driver._owner
  if not UpdatePortraitGCDSwipeVisual(frame) then
    StopPortraitGCDSwipe(frame)
  end
end

local function StartPortraitGCDSwipe(frame, start, duration, modRate)
  if not frame then return end
  HideCooldown(frame.cooldown)
  HideCooldown(frame.portraitCooldown)
  frame._portraitGCDStart = start
  frame._portraitGCDDuration = duration
  frame._portraitGCDModRate = modRate or 1
  if not UpdatePortraitGCDSwipeVisual(frame) then
    StopPortraitGCDSwipe(frame)
    return
  end
  if not frame.portraitGCDDriver then
    frame.portraitGCDDriver = API.CreateFrame("Frame", nil, frame)
    frame.portraitGCDDriver._owner = frame
  end
  frame.portraitGCDDriver:SetScript("OnUpdate", PortraitGCDSwipeOnUpdate)
  frame.portraitGCDDriver:Show()
end

local function GetActiveGCDCooldown(frame, portraitMode)
  if not frame then return nil end
  if portraitMode then
    HideCooldown(frame.cooldown)
    return EnsurePortraitCooldown(frame)
  end
  HideCooldown(frame.portraitCooldown)
  return frame.cooldown
end

-- Target Portrait mode REPLACES the portrait rather than overlaying it: we dim the
-- Blizzard target portrait texture to fully transparent while the AH icon stands in
-- for it, and restore it when leaving the mode / hiding the highlight. The resolved
-- region is remembered so we can restore exactly what we hid.
local function SetTargetPortraitHidden(frame, hidden)
  if not frame then return end
  if hidden then
    local portrait = ResolveTargetPortraitFrame()
    if portrait and portrait.SetAlpha then
      frame._gsetReplacedPortrait = portrait
      portrait:SetAlpha(0)
    end
  else
    local portrait = frame._gsetReplacedPortrait
    if portrait and portrait.SetAlpha then portrait:SetAlpha(1) end
    frame._gsetReplacedPortrait = nil
  end
end

-- Make the highlight icon match the player's action bars: full icon shaped by
-- the player's icon mask (rounded skins etc.), and when the bars use a frame/
-- border art (Blizzard default or a skinner) show that art with the icon filling
-- to it. Mirrors the tracker icon rules. Returns true when the skin border is in
-- use (so the plain coloured square border is suppressed to avoid a square border
-- clashing with the rounded masked icon).
--
-- In Target Portrait mode (anchored over the round target portrait) the square
-- action-bar frame art is dropped and the icon is rounded with a circular portrait
-- mask instead, so the highlight reads as a round badge on the portrait.
function Display:ApplyIconSkin(frame)
  frame = frame or addon.assistedHighlightFrame
  if not frame or not frame.icon then return false end

  local skinBorder = uiShared.GetActionButtonBorder and uiShared.GetActionButtonBorder() or nil
  -- The icon border always ADOPTS the player's action-bar frame art (Blizzard
  -- default or skinner) when present -- no user toggle. When the bars have no frame
  -- art (e.g. Classic), there's simply no border. The coloured square is never used.
  -- Only frame ART (atlas/file) drives the adopted-texture path; a thin-border skin
  -- (ElvUI, skinBorder.thin) has no texture to draw, so treat it as no-frame-art.
  local skinActive = (skinBorder and (skinBorder.atlas or skinBorder.file)) and true or false

  -- Target Portrait mode: anchored over the (round) target portrait. Drop the square
  -- action-bar frame art so the icon fills the frame, then round it below with a
  -- circular portrait mask instead of the action-button mask.
  local portraitMode = (addon.GetAssistedHighlightAnchorTarget
    and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate") or false
  if portraitMode then skinActive = false end

  local fw = (frame.GetWidth and frame:GetWidth()) or 0
  local fh = (frame.GetHeight and frame:GetHeight()) or 0
  if fw <= 0 then fw = uiShared.ICON_SIZE or 45 end
  if fh <= 0 then fh = fw end

  -- The final icon footprint (so we can size the mask from a known value rather
  -- than reading the texture width back before layout settles). The icon stays at
  -- the FRAME size -- the frame art (sb) is drawn larger at the skin's real ratio
  -- and frames it; scaling the icon up to the frame footprint ballooned it for
  -- ornate frames like ActionBarsEnhanced.
  local iw, ih = fw, fh
  if skinActive then
    local bw = fw * (skinBorder.wRatio or 1)
    local bh = fh * (skinBorder.hRatio or 1)
    -- Shave 0.5px per side so the icon art tucks just INSIDE the frame's inner edge.
    for _, t in ipairs({ frame.icon, frame.bg }) do
      if t then
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0.5, -0.5)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -0.5, 0.5)
      end
    end
    if not frame._skinBorder then frame._skinBorder = frame:CreateTexture(nil, "OVERLAY") end
    local sb = frame._skinBorder
    if skinBorder.atlas then
      sb:SetAtlas(skinBorder.atlas, false)
    else
      sb:SetTexture(skinBorder.file)
      if skinBorder.coords then sb:SetTexCoord(unpack(skinBorder.coords)) end
    end
    sb:ClearAllPoints()
    sb:SetSize(bw, bh)
    sb:SetPoint("CENTER", frame, "CENTER", 0, 0)
    sb:Show()
  else
    for _, t in ipairs({ frame.icon, frame.bg }) do
      if t then t:ClearAllPoints(); t:SetAllPoints(frame) end
    end
    if frame._skinBorder then frame._skinBorder:Hide() end
  end

  -- Mask the icon. In Target Portrait mode round it with a circular portrait mask
  -- (matching the round target portrait); otherwise use the player's action-button
  -- mask sized to the KNOWN footprint. `mask` is whichever handle is active so the
  -- backings below match the icon.
  local mask
  if portraitMode then
    -- Drop any action-bar mask the icon carried from a previous (non-portrait) pass.
    local am = frame._gsetActionMask
    if am and frame._gsetActionMaskTarget == frame.icon then
      frame.icon:RemoveMaskTexture(am)
      am:Hide()
      frame._gsetActionMaskTarget = nil
      frame._gsetActionMaskKey = nil
    end
    frame.icon:SetTexCoord(0, 1, 0, 1)
    mask = EnsurePortraitMask(frame, iw, ih)
    frame._isMasked = true
    if not frame.icon._gsetCircleMasked then
      frame.icon._gsetCircleMasked = true
      frame.icon:AddMaskTexture(mask)
    end
    -- Replace (not overlay) the portrait: hide the Blizzard portrait beneath us.
    SetTargetPortraitHidden(frame, true)
  else
    -- Remove the circular portrait mask if we just left portrait mode.
    if frame.icon._gsetCircleMasked and frame._gsetPortraitMask then
      frame.icon._gsetCircleMasked = false
      frame.icon:RemoveMaskTexture(frame._gsetPortraitMask)
    end
    if frame._gsetPortraitMask then frame._gsetPortraitMask:Hide() end
    -- Restore the Blizzard portrait we were standing in for.
    SetTargetPortraitHidden(frame, false)
    frame._isMasked = uiShared.ApplyActionMaskTo and uiShared.ApplyActionMaskTo(frame, frame.icon, iw, ih) or false
    mask = frame._gsetActionMask
  end

  -- The dark backing and range-tint are full squares; round them with the SAME mask
  -- as the icon (circle in portrait mode, action mask otherwise) so no square corners
  -- show behind/over the rounded icon. Track the applied handle so switching masks
  -- swaps cleanly rather than stacking two masks.
  for _, tex in ipairs({ frame.bg, frame.rangeOverlay }) do
    SetTextureMask(tex, (frame._isMasked and mask) or nil)
  end

  -- GCD swipe fills frame.icon and animates (MyMeter style). Keep it on the same
  -- footprint/mask as the icon so rounded action skins and portrait mode do not show
  -- square swipe corners.
  if portraitMode then
    HideCooldown(frame.cooldown)
    HideCooldown(frame.portraitCooldown)
    ApplyPortraitGCDCellMask(frame, (frame._isMasked and mask) or nil)
  else
    StopPortraitGCDSwipe(frame)
  end

  local cd = (not portraitMode) and GetActiveGCDCooldown(frame, false) or nil
  if cd then
    cd:ClearAllPoints()
    cd:SetAllPoints(frame.icon)
    if cd.SetFrameLevel then
      local level = (frame:GetFrameLevel() or 0) + (portraitMode and 1 or 5)
      if portraitMode and frame._assistedHighlightPortraitChildMaxLevel then
        level = math.min(level, frame._assistedHighlightPortraitChildMaxLevel)
      end
      cd:SetFrameLevel(level)
    end
    if cd.SetUseCircularEdge then cd:SetUseCircularEdge(portraitMode and true or false) end
    ApplyCooldownSwipeMask(frame, (frame._isMasked and mask) or nil)
  end

  return skinActive
end

function Display:ApplyBorder(frame)
  frame = frame or addon.assistedHighlightFrame
  if not frame then return end
  local skinActive = self:ApplyIconSkin(frame)

  -- Frame art keeps its natural colour; the icon border just adopts it.
  if frame._skinBorder then frame._skinBorder:SetVertexColor(1, 1, 1) end

  -- Thin-border skin (ElvUI/EllesmereUI): the icon skin draws no frame art, so put a
  -- thin accent border on frame.border so the AH icon matches the main tracker icons.
  -- Frame-art skins (skinActive) keep their texture border; Classic clears it.
  local thinSkin = uiShared.GetActionButtonBorder and uiShared.GetActionButtonBorder() or nil
  thinSkin = ((not skinActive) and thinSkin and thinSkin.thin) and thinSkin or nil
  if frame.border then
    if thinSkin then
      local th = (thinSkin.thickness and thinSkin.thickness > 0) and thinSkin.thickness or 1
      frame._assistedHighlightBorderEdgeSize = th
      frame.border:SetBackdrop({ edgeFile = WHITE8X8, edgeSize = th, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
      frame.border:SetBackdropColor(0, 0, 0, 0)
      frame.border:SetBackdropBorderColor(thinSkin.r or 0, thinSkin.g or 0, thinSkin.b or 0, 1)
    elseif frame._assistedHighlightBorderEdgeSize ~= 0 then
      frame._assistedHighlightBorderEdgeSize = 0
      frame.border:SetBackdrop(nil)
    end
  end

  -- No placement box: the highlight is dragged directly via its mouse handlers,
  -- so keep the drag-border hidden (it otherwise showed as a square box OOC).
  if frame._dragBorder and frame._assistedHighlightDragBorderShown ~= false then
    frame._assistedHighlightDragBorderShown = false
    frame._dragBorder:Hide()
  end
end

function Display:ApplyPosition(force)
  local frame = addon.assistedHighlightFrame
  if not frame then return false end
  local point, _, relativePoint, x, y = GetAnchorPointConfig()
  local parent, relName, followsCursor, anchorAvailable = GetLiveAnchorTargetInfo()
  local targetMode = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() or "Screen"
  local appliedPoint, appliedRelativePoint = ResolveAppliedAnchorPoints(point, relativePoint)
  local resolvedAnchorAvailable = anchorAvailable and parent ~= nil

  -- "Pinned" anchor modes (Target Portrait, Mouse Cursor) ride a live anchor, so the
  -- icon must sit dead-centre on that anchor. The stored point/offset is tuned for
  -- Screen mode (and may be a leftover drag position); reusing it here scatters the
  -- icon to a corner. Force CENTER-to-CENTER with zero offset so portrait mode lands
  -- on the portrait and cursor mode lands exactly under the pointer. (For cursor mode
  -- ApplyCursorAnchor then adds the live cursor delta to this zeroed offset.)
  if targetMode == "Target Nameplate" or targetMode == "Mouse Cursor" then
    appliedPoint, appliedRelativePoint = "CENTER", "CENTER"
    x, y = 0, 0
  end

  if force or frame._assistedHighlightAnchorMode ~= targetMode or frame._assistedHighlightAnchorAvailable ~= resolvedAnchorAvailable then
    frame._gsetrackerPoint = nil
    frame._gsetrackerAnchor = nil
    frame._gsetrackerRelativePoint = nil
    frame._gsetrackerPointX = nil
    frame._gsetrackerPointY = nil
    frame:ClearAllPoints()
  end

  frame._assistedHighlightAnchorMode = targetMode
  frame._assistedHighlightAnchorName = relName
  frame._assistedHighlightAnchorAvailable = resolvedAnchorAvailable

  if not frame._assistedHighlightAnchorAvailable then
    frame._assistedHighlightResolvedX = nil
    frame._assistedHighlightResolvedY = nil
    return false
  end

  if followsCursor then
    local ax, ay = ApplyCursorAnchor(frame, appliedPoint, appliedRelativePoint, x, y)
    frame._assistedHighlightResolvedX = ax
    frame._assistedHighlightResolvedY = ay
  else
    ApplyResolvedAnchor(frame, parent, appliedPoint, appliedRelativePoint, x, y)
    frame._assistedHighlightResolvedX = x
    frame._assistedHighlightResolvedY = y
  end

  return true
end

function Display:UpdateMovableState()
  local frame = addon.assistedHighlightFrame
  if not frame then return end

  -- In "pinned" anchor modes (Target Portrait, Mouse Cursor) the highlight rides a
  -- live anchor rather than a free offset, so dragging is disabled -- a drag would
  -- overwrite the shared stored offset and scatter Screen mode. Only Screen mode is
  -- freely draggable.
  local pinnedMode = false
  local mode = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget()
  if mode == "Target Nameplate" or mode == "Mouse Cursor" then pinnedMode = true end

  local canDrag = not not (
    (IsEditingAssistedHighlightTab() or IsAssistedHighlightPlacementActive())
    and (not GetAssistedHighlightLockState())
    and (not (API.InCombatLockdown and API.InCombatLockdown()))
    and addon:IsAssistedHighlightMirrorEnabled()
    and (not pinnedMode)
  )

  if not canDrag and frame._isDragging and addon.EndAssistedHighlightDrag then
    addon:EndAssistedHighlightDrag(false)
  end

  if frame._canDragAssistedHighlight ~= canDrag then
    frame._canDragAssistedHighlight = canDrag
    frame:EnableMouse(canDrag)
  end

  self:ApplyBorder(frame)
end

GetCursorPositionInParentSpace = function(parent)
  parent = parent or UIParent
  local scale = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
  if not scale or scale == 0 then scale = 1 end
  local cursorX, cursorY = API.GetCursorPosition()
  return (tonumber(cursorX) or 0) / scale, (tonumber(cursorY) or 0) / scale
end

function UI:SyncActiveAssistedHighlightDragPosition()
  local frame = addon.assistedHighlightFrame
  if not (frame and frame._isDragging) then return false end

  local origin = self._assistedHighlightDragOrigin
  local startCursorX = self._assistedHighlightDragCursorOriginX
  local startCursorY = self._assistedHighlightDragCursorOriginY

  local point, relName, relativePoint = addon:GetAssistedHighlightPoint()
  local parent, _, followsCursor, anchorAvailable = GetLiveAnchorTargetInfo()
  local x, y
  if origin and startCursorX ~= nil and startCursorY ~= nil then
    local cursorX, cursorY = GetCursorPositionInParentSpace(UIParent)
    x = (tonumber(origin[4]) or 0) + ParentUnitsToCanonicalPixels(cursorX - startCursorX, UIParent)
    y = (tonumber(origin[5]) or 0) + ParentUnitsToCanonicalPixels(cursorY - startCursorY, UIParent)
  else
    x, y = addon:GetAssistedHighlightOffset()
  end

  x, y = ClampCenteredOffsetsToScreen(frame, UIParent, x, y)
  self:SetAssistedHighlightPoint(point, relName, relativePoint, x, y)
  local appliedPoint = ResolvePointName(point)
  local appliedRelativePoint = ResolvePointName(relativePoint)
  if followsCursor then
    local ax, ay = ApplyCursorAnchor(frame, appliedPoint, appliedRelativePoint, x, y)
    frame._assistedHighlightResolvedX = ax
    frame._assistedHighlightResolvedY = ay
  elseif anchorAvailable and parent then
    ApplyResolvedAnchor(frame, parent, appliedPoint, appliedRelativePoint, x, y)
    frame._assistedHighlightResolvedX = x
    frame._assistedHighlightResolvedY = y
  else
    frame._assistedHighlightResolvedX = nil
    frame._assistedHighlightResolvedY = nil
    return false
  end
  self:RefreshAssistedHighlightPositionControls()
  return true
end

function UI:BeginAssistedHighlightDrag(frame)
  frame = frame or addon.assistedHighlightFrame
  if not frame then return false end
  if frame._isDragging then return true end

  local point, relName, relativePoint, x, y = self:GetAssistedHighlightPoint()
  self._assistedHighlightDragOrigin = { point, relName, relativePoint, x, y }
  self._assistedHighlightDragCursorOriginX, self._assistedHighlightDragCursorOriginY = GetCursorPositionInParentSpace(UIParent)
  frame._isDragging = true
  self:SyncActiveAssistedHighlightDragPosition()
  return true
end

function UI:EndAssistedHighlightDrag(commitPosition)
  local frame = addon.assistedHighlightFrame
  if not (frame and frame._isDragging) then return false end

  if commitPosition then
    self:SyncActiveAssistedHighlightDragPosition()
  else
    local origin = self._assistedHighlightDragOrigin
    if origin then
      self:SetAssistedHighlightPoint(origin[1], origin[2], origin[3], origin[4], origin[5])
    end
    self:ApplyAssistedHighlightPosition(true)
  end

  frame._isDragging = false
  MarkAssistedHighlightPositionDirty()
  self._assistedHighlightDragOrigin = nil
  self._assistedHighlightDragCursorOriginX = nil
  self._assistedHighlightDragCursorOriginY = nil
  self:RefreshAssistedHighlightPositionControls()
  return true
end

function Display:ApplyLiveStrata(frame)
  frame = frame or addon.assistedHighlightFrame
  if not frame or frame.isPreview then return end

  if addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate" then
    local portrait = ResolveTargetPortraitFrame()
    local artFrame = ResolveTargetPortraitArtFrame(portrait)
    local parent = (artFrame and artFrame.GetParent and artFrame:GetParent())
      or (portrait and portrait.GetParent and portrait:GetParent())
      or _G.TargetFrame
      or UIParent
    SetAssistedHighlightParent(frame, parent)

    local strata = (artFrame and artFrame.GetFrameStrata and artFrame:GetFrameStrata())
      or (parent.GetFrameStrata and parent:GetFrameStrata())
      or (C.STRATA_MEDIUM or "MEDIUM")
    local parentLevel = (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
    local artLevel = artFrame and artFrame.GetFrameLevel and artFrame:GetFrameLevel() or nil
    local level = artLevel and math.max(parentLevel, artLevel - 2) or (parentLevel + 1)
    frame._assistedHighlightPortraitArtLevel = artLevel
    frame._assistedHighlightPortraitChildMaxLevel = artLevel and math.max(parentLevel, artLevel - 1) or nil
    if frame._assistedHighlightFrameStrata ~= strata then
      frame._assistedHighlightFrameStrata = strata
      frame:SetFrameStrata(strata)
    end
    if frame._assistedHighlightFrameLevel ~= level then
      frame._assistedHighlightFrameLevel = level
      frame:SetFrameLevel(level)
    end
    return
  end

  SetAssistedHighlightParent(frame, UIParent)
  frame._assistedHighlightPortraitArtLevel = nil
  frame._assistedHighlightPortraitChildMaxLevel = nil
  local strata = (addon.ui and addon.ui.GetFrameStrata and addon.ui:GetFrameStrata()) or (addon.GetStrata and addon:GetStrata()) or (C.DEFAULT_COMBAT_TRACKER_STRATA or C.STRATA_MEDIUM or "MEDIUM")
  local level = (addon.ui and addon.ui.GetFrameLevel and addon.ui:GetFrameLevel()) or 0
  if frame._assistedHighlightFrameStrata ~= strata then
    frame._assistedHighlightFrameStrata = strata
    frame:SetFrameStrata(strata)
  end
  if frame._assistedHighlightFrameLevel ~= level then
    frame._assistedHighlightFrameLevel = level
    frame:SetFrameLevel(level)
  end
end

-- ── GCD swipe (ported from Gnomester MyAHLight) ───────────────────────────────
-- A Cooldown widget overlay that animates the global-cooldown swipe over the AH
-- icon. Reading the GCD spell's cooldown is a plain query -- it does NOT touch
-- any action button, so it stays taint-free like the rest of the new AH path.
local GCD_SPELL_ID = 61304

local function GetGCDCooldownInfo()
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    if info then
      return info.startTime or 0, info.duration or 0, info.isEnabled, info.modRate or 1
    end
  end
  if _G.GetSpellCooldown then
    local s, d, e, m = _G.GetSpellCooldown(GCD_SPELL_ID)
    return s or 0, d or 0, e, m or 1
  end
  return 0, 0, false, 1
end

function Display:UpdateGCDSwipe(frame)
  frame = frame or addon.assistedHighlightFrame
  local portraitMode = addon.GetAssistedHighlightAnchorTarget
    and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
  local cd = (not portraitMode) and GetActiveGCDCooldown(frame, false) or nil
  local showGCD = (addon.GetAssistedHighlightShowGCD == nil) or addon:GetAssistedHighlightShowGCD()
  if (not showGCD) or frame.isPreview or not frame:IsShown() then
    HideCooldown(frame.cooldown)
    HideCooldown(frame.portraitCooldown)
    StopPortraitGCDSwipe(frame)
    return
  end
  local start, duration, enabled, modRate = GetGCDCooldownInfo()
  if (not enabled) or enabled == 0 or start <= 0 or duration <= 0 then
    HideCooldown(frame.cooldown)
    HideCooldown(frame.portraitCooldown)
    StopPortraitGCDSwipe(frame)
    return
  end

  if portraitMode then
    StartPortraitGCDSwipe(frame, start, duration, modRate or 1)
    return
  end

  if not cd then return end

  -- MyMeter Center Marker code: paint square/action-skinned AH with the icon's OWN
  -- texture so it JUST swipes the art. Target Portrait mode returned above and uses
  -- the custom masked texture wipe, because CooldownFrameTemplate keeps squaring off.
  if cd.SetSwipeTexture then
    if not portraitMode then
      local tex = frame._assistedHighlightTexture or (frame.icon and frame.icon.GetTexture and frame.icon:GetTexture())
      if tex then cd:SetSwipeTexture(tex) end
    end
  end
  cd:SetCooldown(start, duration, modRate or 1)
  cd:Show()

  -- SetCooldown can create/rebind the internal swipe region, so re-apply the same
  -- mask the icon is using after starting the swipe.
  local want = nil
  if frame._isMasked then
    want = portraitMode and frame._gsetPortraitMask or frame._gsetActionMask
  end
  ApplyCooldownSwipeMask({ cooldown = cd }, want)
end

-- ── Center-marker mirror ─────────────────────────────────────────────────────
-- When the Player Tracker "Center Marker" is set to AHLight, we show a SECOND copy of
-- THIS Assisted Highlight icon at the unified marker centre. There is only one AH
-- engine (this file) -- the centre display is just a mirror of the same suggestion +
-- GCD swipe. "One at the centre, one wherever the AH tab placed it." No second engine.
local function EnsureAHCenterMirror()
  local f = addon.assistedHighlightCenterFrame
  if f then return f end
  f = API.CreateFrame("Frame", nil, UIParent)
  f:SetSize(uiShared.ICON_SIZE or 45, uiShared.ICON_SIZE or 45)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:Hide()
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  -- GCD swipe -- Gnomester Center Marker code: the swipe is painted with the icon's
  -- OWN texture (SetSwipeTexture) under a dark 0.65 overlay, filling the icon.
  f.cooldown = API.CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  if f.cooldown.SetDrawEdge              then f.cooldown:SetDrawEdge(false)              end
  if f.cooldown.SetDrawBling             then f.cooldown:SetDrawBling(false)             end
  if f.cooldown.SetDrawSwipe             then f.cooldown:SetDrawSwipe(true)              end
  if f.cooldown.SetHideCountdownNumbers  then f.cooldown:SetHideCountdownNumbers(true)   end
  if f.cooldown.SetReverse               then f.cooldown:SetReverse(false)              end
  if f.cooldown.SetFrameLevel            then f.cooldown:SetFrameLevel((f:GetFrameLevel() or 0) + 5) end
  if f.cooldown.SetSwipeColor            then f.cooldown:SetSwipeColor(0, 0, 0, 0.65)    end
  f.cooldown:SetAllPoints(f.icon)
  f.cooldown:Hide()
  addon.assistedHighlightCenterFrame = f
  return f
end

local function IsCenterMarkerAHLight()
  return (addon.GetCombatMarkerSymbol and addon:GetCombatMarkerSymbol() == "AHLight") or false
end

local function HideAHCenterMirror()
  local f = addon.assistedHighlightCenterFrame
  if f then
    if f.cooldown then f.cooldown:SetCooldown(0, 0); f.cooldown:Hide() end
    f:Hide()
  end
end
addon._HideAHCenterMirror = HideAHCenterMirror

-- Mirror the current AH suggestion (state) at the marker centre. Driven from
-- Display:Render so it always tracks the same texture as the primary AH icon.
local function RenderAHCenterMirror(state)
  if not IsCenterMarkerAHLight() or not (state and state.texture)
    or not (addon.IsAssistedHighlightMirrorEnabled and addon:IsAssistedHighlightMirrorEnabled()) then
    HideAHCenterMirror()
    return
  end

  local f = EnsureAHCenterMirror()
  -- Anchor by POINT (not SetParent) to the combat-marker frame so the mirror sits at
  -- the unified centre (screen centre + offset, scale-independent) while its show/hide
  -- stays driven by the AH -- not by whether the combat marker itself is shown.
  local anchor = (addon.EnsureCombatMarker and addon:EnsureCombatMarker()) or addon.combatMarkerFrame
  if anchor and addon.ApplyCombatMarkerPosition then addon:ApplyCombatMarkerPosition(anchor) end
  f:ClearAllPoints()
  f:SetPoint("CENTER", anchor or UIParent, "CENTER", 0, 0)

  -- This mirror IS the Center Marker (Player Marker) when "Assisted Highlight" is chosen,
  -- so it follows the Player Marker SCALE slider (GetCombatMarkerSize), NOT the AH tab size.
  local size = (addon.GetCombatMarkerSize and addon:GetCombatMarkerSize())
    or (addon.GetAssistedHighlightSize and addon:GetAssistedHighlightSize())
    or (uiShared.ICON_SIZE or 45)
  f:SetSize(size, size)
  f:SetAlpha((addon.GetAssistedHighlightAlpha and addon:GetAssistedHighlightAlpha()) or 1)
  f.icon:SetTexture(state.texture)
  f.icon:SetTexCoord(0, 1, 0, 1)
  f:Show()

  -- Gnomester Center Marker swipe: paint the swipe with the icon's own texture.
  -- Gated by the Meters tab "Show GCD" option (MetersSavedVars.showGCD) and hidden while
  -- mounted/on a taxi -- exactly Gnomester's ShouldShowCenterGCDSwipe.
  local cd = f.cooldown
  local mounted = (IsMounted and IsMounted()) or (API.UnitOnTaxi and API.UnitOnTaxi("player"))
    or (UnitOnTaxi and UnitOnTaxi("player")) or false
  local showGCD = not (_G.MetersSavedVars and _G.MetersSavedVars.showGCD == false) and not mounted
  local start, duration, enabled, modRate = GetGCDCooldownInfo()
  if showGCD and enabled and enabled ~= 0 and start > 0 and duration > 0 then
    if cd.SetSwipeTexture then cd:SetSwipeTexture(state.texture) end
    cd:SetCooldown(start, duration, modRate or 1)
    cd:Show()
  else
    if cd.Clear then cd:Clear() else cd:SetCooldown(0, 0) end
    cd:Hide()
  end
end

local function CreateMirrorFrame(parent, isPreview)
  local frame = API.CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
  frame.isPreview = isPreview and true or false
  if frame.isPreview then
    frame:SetFrameStrata(C.STRATA_DIALOG or "DIALOG")
    frame:SetFrameLevel(80)
  else
    local strata = (addon.ui and addon.ui.GetFrameStrata and addon.ui:GetFrameStrata()) or (addon.GetStrata and addon:GetStrata()) or (C.DEFAULT_COMBAT_TRACKER_STRATA or C.STRATA_MEDIUM or "MEDIUM")
    local level = (addon.ui and addon.ui.GetFrameLevel and addon.ui:GetFrameLevel()) or 0
    frame:SetFrameStrata(strata)
    frame:SetFrameLevel(level)
  end
  frame:SetClampedToScreen(true)
  frame:SetIgnoreParentScale(false)
  frame:Hide()

  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(frame)
  bg:SetTexture(C.TEXTURE_WHITE8X8 or WHITE8X8)
  bg:SetVertexColor(0.02, 0.02, 0.02, frame.isPreview and 0.84 or 0.72)
  -- Hidden by default so the highlight matches the Action Tracker icons (no dark
  -- slot backing showing as a black border behind the icon).
  bg:Hide()
  frame.bg = bg

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(frame)
  -- texcoord/mask are applied by Display:ApplyIconSkin to match the player's bars
  icon:SetTexCoord(0, 1, 0, 1)
  frame.icon = icon

  -- GCD swipe overlay (ported from Gnomester MyAHLight). Animates the global
  -- cooldown over the icon; updated by Display:UpdateGCDSwipe.
  -- MyMeter Center Marker swipe setup: dark 0.65 overlay, non-reversed, swipe painted
  -- with the icon texture (set per-update in UpdateGCDSwipe) so it just swipes the art.
  local cooldown = API.CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  cooldown:SetAllPoints(frame.icon)  -- swipe stays on the icon art, not the frame/border
  ConfigureGCDCooldown(cooldown)
  cooldown:Hide()
  frame.cooldown = cooldown

  local border = API.CreateFrame("Frame", nil, frame, "BackdropTemplate")
  border:SetAllPoints(frame)
  frame.border = border

  local dragBorder = API.CreateFrame("Frame", nil, frame, "BackdropTemplate")
  dragBorder:SetAllPoints(frame)
  dragBorder:SetBackdrop({ bgFile = C.TEXTURE_WHITE8X8 or WHITE8X8, edgeFile = C.TEXTURE_WHITE8X8 or WHITE8X8, edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
  dragBorder:SetBackdropColor(0, 0, 0, 0)
  dragBorder:Hide()
  frame._dragBorder = dragBorder

  local keybind = CreateFont(frame, 11)
  keybind:SetDrawLayer("OVERLAY", 7)
  frame.keybindText = keybind

  -- Charges / stack count, mirroring Blizzard's ActionButton.Count (bottom-right).
  local count = CreateFont(frame, 11)
  count:SetDrawLayer("OVERLAY", 7)
  frame.countText = count

  local rangeTint = frame:CreateTexture(nil, "OVERLAY")
  rangeTint:SetAllPoints(frame)
  rangeTint:SetTexture(C.TEXTURE_WHITE8X8 or WHITE8X8)
  -- Red wash for the out-of-range state (alpha driven in RenderToFrame).
  rangeTint:SetVertexColor(1, 0.1, 0.1, 0)
  frame.rangeOverlay = rangeTint

  Display:ApplyFont(frame)
  Display:ApplyKeybindPosition(frame)
  Display:ApplyBorder(frame)

  if not frame.isPreview then
    frame:SetScript("OnMouseDown", function(self, button)
      if button ~= "LeftButton" then return end
      if not self._canDragAssistedHighlight then return end
      if not addon:IsAssistedHighlightMirrorEnabled() or GetAssistedHighlightLockState() then return end
      addon:BeginAssistedHighlightDrag(self)
    end)

    frame:SetScript("OnMouseUp", function(self, button)
      if button ~= "LeftButton" then return end
      if self._isDragging then
        addon:EndAssistedHighlightDrag(true)
      end
    end)

    frame:SetScript("OnHide", function(self)
      if self._isDragging then
        addon:EndAssistedHighlightDrag(false)
      end
      -- If we were replacing the target portrait, give it back when we hide (target
      -- lost, AH disabled, etc.) so the portrait isn't left invisible.
      StopPortraitGCDSwipe(self)
      SetTargetPortraitHidden(self, false)
    end)

    frame:SetScript("OnUpdate", function(self, elapsed)
      if self._isDragging and addon.SyncActiveAssistedHighlightDragPosition then
        addon:SyncActiveAssistedHighlightDragPosition()
        return
      end

      local mirrorEnabled = addon.IsAssistedHighlightMirrorEnabled and addon:IsAssistedHighlightMirrorEnabled()
      if IsEditingAssistedHighlightTab() or not mirrorEnabled then
        return
      end

      -- Hidden mirrors should not keep doing cursor-follow or provider work.
      -- Event-driven refreshes wake the frame back up when visibility changes.
      if not self:IsShown() then
        return
      end

      local followsCursor = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Mouse Cursor"
      if followsCursor then
        Display:ApplyPosition()
      end

      self._elapsed = (self._elapsed or 0) + (elapsed or 0)
      local refreshInterval = (API.InCombatLockdown and API.InCombatLockdown()) and LIVE_REFRESH_INTERVAL or HASHLESS_REFRESH_INTERVAL
      local dirty = addon._assistedHighlightDirty == true

      if self._elapsed < refreshInterval then
        return
      end

      self._elapsed = 0
      addon._assistedHighlightDirty = nil
      addon._assistedHighlightDirtyReason = nil
      if addon.RefreshAssistedHighlight then
        addon:RefreshAssistedHighlight(dirty)
      end
    end)
  end

  return frame
end

-- Target Portrait mode REPLACES the portrait, so the highlight fills the portrait
-- texture's footprint exactly (1.0). Blizzard's border ring sits OUTSIDE this footprint
-- and still frames the replacement. (Lower this slightly if the icon ever bleeds past
-- the ring's inner edge on a given client.)
local PORTRAIT_FIT_INSET = 1.0

function Display:ApplySize(frame)
  frame = frame or addon.assistedHighlightFrame or self:Create()
  local size = addon:GetAssistedHighlightSize()

  -- Target Portrait mode: auto-fit to the target portrait (inset to sit INSIDE the
  -- border ring) instead of the Scale slider, so the icon always tucks behind the
  -- portrait border. Falls back to the slider size when no portrait is resolvable
  -- (e.g. no target) -- a target refresh re-runs this once the portrait exists.
  local mode = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget()
  if mode == "Target Nameplate" then
    local portrait = ResolveTargetPortraitFrame()
    local pw = portrait and portrait.GetWidth and portrait:GetWidth() or 0
    local ph = portrait and portrait.GetHeight and portrait:GetHeight() or 0
    local d = math.min(pw > 0 and pw or ph, ph > 0 and ph or pw)
    if d and d > 0 then size = d * PORTRAIT_FIT_INSET end
  end

  local snappedW = PixelSnap(size, frame)
  local snappedH = PixelSnap(size, frame)
  if frame._assistedHighlightWidth == snappedW and frame._assistedHighlightHeight == snappedH then return end
  frame._assistedHighlightWidth = snappedW
  frame._assistedHighlightHeight = snappedH
  frame:SetSize(snappedW, snappedH)
  -- Re-fit the icon/mask/skin-border to the new size (matches the action bars).
  if self.ApplyIconSkin then self:ApplyIconSkin(frame) end
end

function Display:ApplyAlpha(frame)
  frame = frame or addon.assistedHighlightFrame or self:Create()
  if not frame then return end
  local alpha = addon.GetAssistedHighlightAlpha and addon:GetAssistedHighlightAlpha() or (C.ASSISTED_HIGHLIGHT_DEFAULT_ALPHA or 0.85)
  alpha = math.max(0.05, math.min(1.00, tonumber(alpha) or (C.ASSISTED_HIGHLIGHT_DEFAULT_ALPHA or 0.85)))
  if frame._assistedHighlightAlpha == alpha then return end
  frame._assistedHighlightAlpha = alpha
  frame:SetAlpha(alpha)
end

function Display:RenderToFrame(frame, state)
  if not frame then return end
  self:ApplySize(frame)
  self:ApplyAlpha(frame)
  self:ApplyFont(frame)
  self:ApplyKeybindPosition(frame)
  self:ApplyBorder(frame)

  if not state or not state.texture then
    if frame._assistedHighlightTexture ~= false then
      frame._assistedHighlightTexture = false
      frame.icon:SetTexture(nil)
    end
    if frame._assistedHighlightIconR ~= 1 or frame._assistedHighlightIconG ~= 1 or frame._assistedHighlightIconB ~= 1 then
      frame._assistedHighlightIconR, frame._assistedHighlightIconG, frame._assistedHighlightIconB = 1, 1, 1
      frame.icon:SetVertexColor(1, 1, 1, 1)
    end
    if frame._assistedHighlightRangeAlpha ~= 0 then
      frame._assistedHighlightRangeAlpha = 0
      frame.rangeOverlay:SetAlpha(0)
    end
    if frame._assistedHighlightKeybindText ~= "" then
      frame._assistedHighlightKeybindText = ""
      frame.keybindText:SetText("")
    end
    if frame._assistedHighlightKeybindVisible ~= false then
      frame._assistedHighlightKeybindVisible = false
      frame.keybindText:Hide()
    end
    if frame.countText and frame._assistedHighlightCountVisible ~= false then
      frame._assistedHighlightCountText = ""
      frame._assistedHighlightCountVisible = false
      frame.countText:SetText("")
      frame.countText:Hide()
    end

    HideCooldown(frame.cooldown)
    HideCooldown(frame.portraitCooldown)
    StopPortraitGCDSwipe(frame)

    local shouldShow = false
    if (not frame.isPreview) and (IsEditingAssistedHighlightTab() or IsAssistedHighlightPlacementActive()) and addon:IsAssistedHighlightMirrorEnabled() and (not GetAssistedHighlightLockState()) then
      shouldShow = true
    end
    SetMirrorShown(frame, shouldShow)
    return
  end

  if frame._assistedHighlightTexture ~= state.texture then
    frame._assistedHighlightTexture = state.texture
    frame.icon:SetTexture(state.texture)
  end
  -- Out-of-range feedback = red tint + red wash (applied below). Computed once.
  local outOfRange = addon:GetAssistedHighlightRangeCheckerEnabled() and state.inRange == false
  if frame._assistedHighlightDesaturated ~= false then
    frame._assistedHighlightDesaturated = false
    frame.icon:SetDesaturated(false)
  end

  -- On the small round Target Portrait there's no clean corner to tuck text into, so the
  -- keybind and the stack/charge count just overlap the emblem. Hide both in that mode.
  local ahPortraitMode = (addon.GetAssistedHighlightAnchorTarget
    and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate") and true or false

  local showKeybind = (not ahPortraitMode) and addon:GetAssistedHighlightShowKeybind() and state.keybind and true or false
  local keybindText = showKeybind and state.keybind or ""
  if frame._assistedHighlightKeybindText ~= keybindText then
    frame._assistedHighlightKeybindText = keybindText
    frame.keybindText:SetText(keybindText)
  end
  if frame._assistedHighlightKeybindVisible ~= showKeybind then
    frame._assistedHighlightKeybindVisible = showKeybind
    if showKeybind then frame.keybindText:Show() else frame.keybindText:Hide() end
  end

  if frame.countText then
    -- state.count is a "secret" value (assisted spell charges) -- displaying it via
    -- SetText is allowed, but COMPARING it (or a string from it) throws. So gate
    -- show/hide on the SAFE boolean state.hasCount and SetText directly each render;
    -- never compare the secret value.
    -- Stacks/charge count follows the same "Show Keybind/Stacks" toggle as the keybind.
    local showCount = (not ahPortraitMode) and addon:GetAssistedHighlightShowKeybind() and state.hasCount and true or false
    if showCount then
      frame.countText:SetText(tostring(state.count))
    else
      frame.countText:SetText("")
    end
    if frame._assistedHighlightCountVisible ~= showCount then
      frame._assistedHighlightCountVisible = showCount
      if showCount then frame.countText:Show() else frame.countText:Hide() end
    end
  end

  local iconR, iconG, iconB = 1, 1, 1
  local rangeAlpha = 0
  if outOfRange then
    iconR, iconG, iconB = 0.82, 0.18, 0.18
    rangeAlpha = frame.isPreview and 0.10 or 0.16
  end
  if frame._assistedHighlightIconR ~= iconR or frame._assistedHighlightIconG ~= iconG or frame._assistedHighlightIconB ~= iconB then
    frame._assistedHighlightIconR, frame._assistedHighlightIconG, frame._assistedHighlightIconB = iconR, iconG, iconB
    frame.icon:SetVertexColor(iconR, iconG, iconB, 1)
  end
  if frame._assistedHighlightRangeAlpha ~= rangeAlpha then
    frame._assistedHighlightRangeAlpha = rangeAlpha
    frame.rangeOverlay:SetAlpha(rangeAlpha)
  end

  SetMirrorShown(frame, true)
  self:UpdateGCDSwipe(frame)
end

function Display:Render(state)
  local frame = addon.assistedHighlightFrame or self:Create()
  self:ApplyLiveStrata(frame)
  local followsCursor = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Mouse Cursor"
  local anchorApplied = true
  if followsCursor or addon._assistedHighlightPositionDirty or frame._assistedHighlightAnchorAvailable == nil then
    anchorApplied = self:ApplyPosition(addon._assistedHighlightPositionDirty)
    addon._assistedHighlightPositionDirty = nil
  end
  self:UpdateMovableState()
  -- Mirror the same suggestion at the marker centre (if Center Marker = AHLight). The
  -- centre copy tracks the suggestion regardless of the primary's anchor availability.
  RenderAHCenterMirror(state)
  if not anchorApplied then
    SetMirrorShown(frame, false)
    return
  end
  self:RenderToFrame(frame, state)
end

function Display:Create()
  if addon.assistedHighlightFrame then return addon.assistedHighlightFrame end
  addon.assistedHighlightFrame = CreateMirrorFrame(UIParent, false)
  return addon.assistedHighlightFrame
end

-- Capture the AH's current suggestion (spellID + texture, plus the one just before
-- it) so the tracker can proc-glow a main-row icon when the next successful cast
-- matches what the AH was suggesting -- INDEPENDENT of whether the AH icon is shown.
-- Keeping the previous value covers the race where GetNextCastSpell advances to the
-- NEXT spell before UNIT_SPELLCAST_SUCCEEDED is processed. Texture is matched too so
-- base/override spellIDs of one ability count.
local function CaptureAHSuggestion()
  if addon.GetProcGlowEnabled and not addon:GetProcGlowEnabled() then return end
  local spellID = Provider:GetRecommendedSpellID()
  if not spellID then return end
  if spellID ~= addon._ahSuggestedSpellID then
    addon._ahPrevSuggestedSpellID = addon._ahSuggestedSpellID
    addon._ahPrevSuggestedTexture = addon._ahSuggestedTexture
    addon._ahPrevSuggestedAt = (API.GetTime and API.GetTime()) or 0
    addon._ahSuggestedSpellID = spellID
    addon._ahSuggestedTexture = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
      or (GetSpellTexture and GetSpellTexture(spellID)) or addon._ahSuggestedTexture
  end
end

function UI:EnsureAssistedHighlightEvents()
  if self.assistedHighlightEvents then return self.assistedHighlightEvents end
  local frame = API.CreateFrame("Frame")
  self.assistedHighlightEvents = frame
  local events = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "UNIT_TARGET",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_UPDATE_USABLE",
    "SPELL_UPDATE_USABLE",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_BINDINGS",
    "UNIT_AURA",
    "CURRENT_SPELL_CAST_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ASSISTED_COMBAT_ACTION_SPELL_CAST",
  }
  for _, event in ipairs(events) do
    API.SafeRegisterEvent(frame, event)
  end
  frame:SetScript("OnEvent", function(_, event, unit)
    local mirrorEnabled = addon.IsAssistedHighlightMirrorEnabled and addon:IsAssistedHighlightMirrorEnabled()

    if event == "UNIT_AURA" or event == "UNIT_TARGET" then
      if unit and unit ~= "player" and unit ~= "target" then return end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
      if not (unit and UnitIsUnit and UnitIsUnit(unit, "target")) then return end
    end

    if event == "UPDATE_BINDINGS" then
      Provider._bindingCache = nil
      Provider._buttonBindingCache = nil  -- frame-name based cache, also keybind data
    end

    if event == "PLAYER_ENTERING_WORLD"
      or event == "ACTIONBAR_SLOT_CHANGED"
      or event == "PLAYER_SPECIALIZATION_CHANGED" then
      Provider._actionSlotCache = nil
      Provider._actionSlotCacheCount = nil
      -- The Rotation Helper slot, frame-priority registry, and glow tracking all
      -- reflect bar layout; invalidate them whenever the bar layout may have changed.
      Provider._assistedCombatSlot = nil
      Provider._glowedButtonList = nil
      InvalidateButtonRegistry()
    end

    -- Capture the AH suggestion for the proc-glow BEFORE the visibility gate, so it
    -- works even when the AH mirror is hidden or disabled. GetNextCastSpell is a game
    -- API independent of our frame being shown.
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES"
      or event == "CURRENT_SPELL_CAST_CHANGED" or event == "ASSISTED_COMBAT_ACTION_SPELL_CAST"
      or event == "PLAYER_REGEN_DISABLED" then
      CaptureAHSuggestion()
    end

    -- Single-Button Assistant cast detection. The event fires for the assisted-combat
    -- action from ANY source (button or a GSE sequence), so we correlate it to the
    -- UNIT_SPELLCAST_SUCCEEDED in the tracker by TIME WINDOW (not the spell payload,
    -- which is unreliable -- this is also how GSE's own tracker does it). Handles
    -- EITHER event order. Captured before the gate so AH visibility doesn't matter.
    if event == "ASSISTED_COMBAT_ACTION_SPELL_CAST"
      and (addon.GetProcGlowEnabled == nil or addon:GetProcGlowEnabled()) then
      local now = (API.GetTime and API.GetTime()) or 0
      if addon._lastCastAt and (now - addon._lastCastAt) <= 0.3 and not addon._lastCastSbaCounted then
        -- Event arrived JUST AFTER the cast: count that cast retroactively.
        addon._lastCastSbaCounted = true
        addon._ahSbaCastCount = (addon._ahSbaCastCount or 0) + 1
        if addon._lastCastMatched then addon._ahSbaMatchCount = (addon._ahSbaMatchCount or 0) + 1 end
        if addon.UpdateAHMatchReadout then addon:UpdateAHMatchReadout() end
      else
        -- Event arrived BEFORE the cast: arm it for the upcoming SUCCEEDED.
        addon._sbaEventAt = now
        addon._sbaEventActive = true
      end
    end

    if (not mirrorEnabled) and (not IsEditingAssistedHighlightTab()) then
      return
    end

    -- GCD swipe only: update the cooldown overlay without rebuilding state.
    -- The Cooldown widget self-animates once SetCooldown is set, so this just
    -- (re)starts the swipe when the global cooldown ticks over on a cast.
    if event == "SPELL_UPDATE_COOLDOWN" then
      Display:UpdateGCDSwipe(addon.assistedHighlightFrame)
      return
    end

    if event == "PLAYER_ENTERING_WORLD"
      or event == "PLAYER_TARGET_CHANGED"
      or event == "UNIT_TARGET"
      or event == "NAME_PLATE_UNIT_ADDED"
      or event == "NAME_PLATE_UNIT_REMOVED"
      or event == "PLAYER_REGEN_DISABLED"
      or event == "PLAYER_REGEN_ENABLED" then
      MarkAssistedHighlightPositionDirty()
    end

    Provider:MarkDirty()
    MarkAssistedHighlightDirty(event)

    local immediate = (
      event == "PLAYER_ENTERING_WORLD"
      or event == "PLAYER_TARGET_CHANGED"
      or event == "UNIT_TARGET"
      or event == "NAME_PLATE_UNIT_ADDED"
      or event == "NAME_PLATE_UNIT_REMOVED"
      or event == "ACTIONBAR_SLOT_CHANGED"
      or event == "PLAYER_SPECIALIZATION_CHANGED"
      or event == "UPDATE_BINDINGS"
      or event == "PLAYER_REGEN_DISABLED"
      or event == "PLAYER_REGEN_ENABLED"
      or event == "ASSISTED_COMBAT_ACTION_SPELL_CAST"
      or event == "SPELL_UPDATE_CHARGES"
    )

    if immediate and addon.RefreshAssistedHighlight then
      addon:RefreshAssistedHighlight(true)
    end
  end)

  -- NOTE: We no longer install the ActionButton_ShowOverlayGlow hook. The
  -- Assisted Highlight now mirrors the recommended spell's OWN icon (sourced from
  -- C_AssistedCombat, like Gnomester's MyAHLight) and never reaches into the live
  -- action buttons -- so there is nothing to entangle with ON_BAR_HIGHLIGHT_MARKS.

  return frame
end

function UI:EnsureAssistedHighlight()
  -- Retail-only: C_AssistedCombat doesn't exist on Classic, so the whole feature is inert there.
  if not (ns.Caps and ns.Caps.assistedHighlight) then return end
  self:EnsureAssistedHighlightEvents()
  return Display:Create()
end

function UI:ApplyAssistedHighlightPosition(force)
  MarkAssistedHighlightPositionDirty()
  local applied = Display:ApplyPosition(force)
  if applied == false and addon.assistedHighlightFrame then
    SetMirrorShown(addon.assistedHighlightFrame, false)
  end
  return applied
end

function UI:ApplyAssistedHighlightSize()
  Display:ApplySize(addon.assistedHighlightFrame)
  Display:ApplyBorder(addon.assistedHighlightFrame)
  Display:ApplyFont(addon.assistedHighlightFrame)
  Display:ApplyKeybindPosition(addon.assistedHighlightFrame)
end

function UI:ApplyAssistedHighlightAlpha()
  Display:ApplyAlpha(addon.assistedHighlightFrame)
end

function UI:ApplyAssistedHighlightFont()
  Display:ApplyFont(addon.assistedHighlightFrame)
end

function UI:ApplyAssistedHighlightKeybindPosition()
  Display:ApplyKeybindPosition(addon.assistedHighlightFrame)
end

function UI:ApplyAssistedHighlightBorder()
  Display:ApplyBorder(addon.assistedHighlightFrame)
end

function UI:ApplyAssistedHighlightLayout(force)
  local applied = self:ApplyAssistedHighlightPosition(force)
  self:ApplyAssistedHighlightKeybindPosition()
  return applied
end

function UI:RefreshAssistedHighlightPositionControls()
  local settingsWindow = addon.settingsWindow
  if not (settingsWindow and settingsWindow.RefreshAssistedHighlightPositionControls) then return end
  settingsWindow:RefreshAssistedHighlightPositionControls()
end

function UI:HideAssistedHighlightPreview()
end

function UI:ShouldShowAssistedHighlight()
  if not (addon.IsAssistedHighlightMirrorEnabled and addon:IsAssistedHighlightMirrorEnabled()) then
    return false
  end

  local editingOverride = IsEditingAssistedHighlightTab() or IsAssistedHighlightPlacementActive()

  local showWhen = (addon.GetAssistedHighlightShowWhen and addon:GetAssistedHighlightShowWhen())
    or (C.MODE_ALWAYS or "Always")

  local ui = addon and addon.ui
  local inCombat
  if ui and ui._combatState ~= nil then
    inCombat = (ui._combatState == true)
  else
    inCombat = (API.InCombatLockdown and API.InCombatLockdown()) and true or false
  end
  local hasTarget = (API.HasHarmTarget and API.HasHarmTarget()) and true or false

  -- Target Portrait mode REPLACES the enemy target's portrait, so it only makes sense
  -- with an attackable (harm) target. With no harm target there's no portrait to ride --
  -- don't place it there. (Editing/placement still shows it so the user can position it.)
  local anchorTarget = addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget()
  if anchorTarget == "Target Nameplate" and not editingOverride and not hasTarget then
    return false
  end

  if self.EvaluateVisibilityMode then
    return self:EvaluateVisibilityMode(showWhen, inCombat, hasTarget, editingOverride)
  end

  if editingOverride then return true end
  if showWhen == (C.MODE_NEVER or "Never") then return false end
  if showWhen == (C.MODE_IN_COMBAT or "InCombat") then return inCombat end
  if showWhen == (C.MODE_HAS_TARGET or "HasTarget") then return hasTarget end
  return true
end

function UI:RefreshAssistedHighlight(force)
  if not (ns.Caps and ns.Caps.assistedHighlight) then return end
  local frame = self:EnsureAssistedHighlight()
  if not addon:IsAssistedHighlightMirrorEnabled() then
    SetMirrorShown(frame, false)
    if addon._HideAHCenterMirror then addon:_HideAHCenterMirror() end
    self:HideAssistedHighlightPreview()
    return
  end

  local shouldShow = self:ShouldShowAssistedHighlight()
  if not shouldShow then
    SetMirrorShown(frame, false)
    if addon._HideAHCenterMirror then addon:_HideAHCenterMirror() end
  else
    local providerAvailable = Provider:IsAvailable()
    local state = providerAvailable and Provider:GetState(force) or nil
    Display:Render(state)
  end

end
