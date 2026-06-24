-- GSE: Tracker -- meters/CooldownElements.lua
--
-- Optional cooldown widgets the user can drop into EMPTY Meters grid cells (Trinkets, Healthstone, ... ).
-- Each is a small icon + cooldown swipe + remaining-time text. A registry describes each element (label +
-- how to read its icon/cooldown/availability); one generic widget renders any of them. Meters.lua owns the
-- slot system and places/positions/sizes these frames; this file only builds + updates them.
--
-- Cross-version: every data source is guarded (item-cooldown API moved to C_Container/C_Item on retail;
-- GetInventoryItem* exist on all flavors). Adding an element = one descriptor in ELEMENTS below.
--
-- MUST load before Meters.lua (which consumes the GSETracker_CooldownElements_* globals).

local ADDON_NAME = ...

-- ── Cross-version cooldown / icon readers ────────────────────────────────────
local function EquipSlotCD(slot)
  local s, d, e = GetInventoryItemCooldown("player", slot)
  return tonumber(s) or 0, tonumber(d) or 0, (e ~= 0)
end

local function ItemCD(itemID)
  if C_Container and C_Container.GetItemCooldown then
    local s, d, e = C_Container.GetItemCooldown(itemID)
    return tonumber(s) or 0, tonumber(d) or 0, (e ~= 0)
  elseif C_Item and C_Item.GetItemCooldown then
    local s, d, e = C_Item.GetItemCooldown(itemID)
    return tonumber(s) or 0, tonumber(d) or 0, (e ~= 0)
  elseif GetItemCooldown then
    local s, d, e = GetItemCooldown(itemID)
    return tonumber(s) or 0, tonumber(d) or 0, (e ~= 0)
  end
  return 0, 0, false
end

local function ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
  if GetItemIcon then return GetItemIcon(itemID) end
  return nil
end

local QUESTION_MARK = 134400  -- Interface/Icons/INV_Misc_QuestionMark

-- ── Element registry (order = dropdown order) ────────────────────────────────
local HEALTHSTONE_ITEM = 5512
local ELEMENTS = {
  { id = "Trinket1", label = "Trinket 1",
    icon      = function() return GetInventoryItemTexture("player", 13) end,
    cooldown  = function() return EquipSlotCD(13) end,
    available = function() return GetInventoryItemID("player", 13) ~= nil end },
  { id = "Trinket2", label = "Trinket 2",
    icon      = function() return GetInventoryItemTexture("player", 14) end,
    cooldown  = function() return EquipSlotCD(14) end,
    available = function() return GetInventoryItemID("player", 14) ~= nil end },
  { id = "Healthstone", label = "Healthstone",
    icon      = function() return ItemIcon(HEALTHSTONE_ITEM) end,
    cooldown  = function() return ItemCD(HEALTHSTONE_ITEM) end,
    available = function() return true end },
  -- TODO (next increment): Potion (bag-scan for a usable combat potion), Racial (UnitRace+class -> spell),
  -- Custom (user-entered spell/item ID -- needs an input field in the arranger).
}
local BY_ID = {}
for _, e in ipairs(ELEMENTS) do BY_ID[e.id] = e end

-- ── Public registry queries (consumed by Meters.lua + the arranger) ──────────
function GSETracker_CooldownElements_List()  -- ordered {id,label} of ALL optional elements
  local out = {}
  for _, e in ipairs(ELEMENTS) do out[#out + 1] = { id = e.id, label = e.label } end
  return out
end

function GSETracker_CooldownElements_IsValid(id) return BY_ID[id] ~= nil end
function GSETracker_CooldownElements_Label(id) return (BY_ID[id] and BY_ID[id].label) or id end

-- ── Widget (one frame per element id, created on demand, cached) ──────────────
local frames = {}

function GSETracker_CooldownElements_Ensure(id, parent)
  local desc = BY_ID[id]
  if not desc then return nil end
  local f = frames[id]
  if not f then
    f = CreateFrame("Frame", "GSETrackerCDElem_" .. id, parent or UIParent)
    f:SetSize(24, 24)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the default icon border
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetHideCountdownNumbers(true)
    f.cd:SetDrawEdge(false)
    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("BOTTOM", f, "BOTTOM", 0, -2)
    f._desc = desc
    frames[id] = f
  end
  if parent then f:SetParent(parent) end
  return f
end

function GSETracker_CooldownElements_Hide(id)
  local f = frames[id]
  if f then f:Hide() end
end

local function FmtTime(rem)
  if rem >= 60 then return string.format("%dm", math.floor(rem / 60 + 0.5)) end
  if rem >= 10 then return string.format("%d", math.floor(rem + 0.5)) end
  return string.format("%.1f", rem)
end

function GSETracker_CooldownElements_Update(id)
  local f = frames[id]
  if not (f and f._desc) then return end
  local desc = f._desc
  f.icon:SetTexture(desc.icon() or QUESTION_MARK)
  local s, d, e = desc.cooldown()
  if e and s > 0 and d and d > 1.5 then  -- > 1.5 so the GCD doesn't flash a swipe on every press
    f.cd:SetCooldown(s, d)
    local rem = (s + d) - GetTime()
    f.time:SetText(rem > 0 and FmtTime(rem) or "")
  else
    if f.cd.Clear then f.cd:Clear() end
    f.time:SetText("")
  end
end

-- ── Ticker: refresh every shown widget ~5x/sec ───────────────────────────────
local ticker = CreateFrame("Frame")
ticker._t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  self._t = self._t + elapsed
  if self._t < 0.2 then return end
  self._t = 0
  for id, f in pairs(frames) do
    if f:IsShown() then GSETracker_CooldownElements_Update(id) end
  end
end)
