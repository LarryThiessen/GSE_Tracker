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
-- Spells with a base cooldown of 6s+ are discovered from the spellbook (rebuilt on spell/spec changes) and
-- offered alongside the static items. id = "Spell:<spellID>".
local SPELL_ELEMENTS = {}
local BY_ID = {}
local function RebuildIndex()
  wipe(BY_ID)
  for _, e in ipairs(ELEMENTS)       do BY_ID[e.id] = e end
  for _, e in ipairs(SPELL_ELEMENTS) do BY_ID[e.id] = e end
end
RebuildIndex()

-- ── Spell cooldown elements (player's 6s+ base-cooldown spells) ───────────────
local MIN_SPELL_CD = 6  -- seconds
local function SpellTex(sid)
  return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
      or (GetSpellTexture and GetSpellTexture(sid)) or nil
end
local function SpellNm(sid)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(sid) end
  if GetSpellInfo then return (GetSpellInfo(sid)) end
  return nil
end
local function SpellBaseCDSec(sid)
  if not GetSpellBaseCooldown then return 0 end
  local ms = GetSpellBaseCooldown(sid)   -- returns (cooldownMS, gcdMS) -- keep only the first
  return (tonumber(ms) or 0) / 1000
end

-- Player cast times, recorded from UNIT_SPELLCAST_SUCCEEDED (GetTime() is non-secret). We drive the spell
-- cooldown display from THESE + the spell's BASE cooldown, NEVER from C_Spell.GetSpellCooldown: that returns
-- SECRET values in combat (remaining time = start+duration-now is arithmetic, which throws on a secret), and
-- the engine refuses to animate a secret-fed cooldown on our tainted frame until combat ends. Cast-time +
-- base-CD is all non-secret, so the engine Cooldown frame ticks through combat.
-- ponytail: base CD ignores talent reductions / charges / resets / overrides, and a spell already on CD at
-- login shows ready until first cast. Good enough for a simple bar; revisit if accuracy matters.
local lastCast = {}
local castEv = CreateFrame("Frame")
castEv:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castEv:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if unit == "player" and spellID then lastCast[spellID] = GetTime() end
end)

-- start, duration for the engine Cooldown frame, from non-secret cast time + base CD.
local function SpellCD(sid)
  local d = SpellBaseCDSec(sid)
  if d <= 0 then return 0, 0 end
  return lastCast[sid] or 0, d
end

-- Follow an active override/upgrade (a proc or talent that swaps the button to another spell -- e.g. a
-- tracked ability that flips to an upgraded version mid-fight) so we show the spell you'd actually cast,
-- icon AND cooldown, instead of a stale base or a blank once the base leaves the spellbook. Returns sid
-- unchanged when there's no override (or no API on this flavor).
local function ResolveSpell(sid)
  local o = (C_Spell and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(sid))
         or (FindSpellOverrideByID and FindSpellOverrideByID(sid))
  return o or sid
end

-- Spellbook subtext ("rank" line). Racials carry "Racial" here (racial defensives too); junk General-tab
-- entries carry "Guild Perk"/"Battle Pets"/empty. ponytail: "Racial" is the enUS subtext -- a non-English
-- client would need its localised word here; revisit if anyone runs GSE_Tracker non-enUS.
local RACIAL_SUB = "Racial"
local GENERAL_NAME = _G.GENERAL or "General"
local function SpellSub(slot, bank, sid)
  local _, sub = C_SpellBook.GetSpellBookItemName(slot, bank)
  if (not sub or sub == "") and C_Spell and C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(sid) end
  return sub
end

-- Shared "consider this spell for the picker" gate, used by BOTH the retail (C_SpellBook) and the legacy
-- Classic (GetSpellTabInfo) scans: drop passives, drop General-tab non-racials (Mobile Banking / Battle Pets
-- / special items -- racials and class/spec defensives are kept), require a 6s+ base cooldown, de-dupe.
-- `sub` is the spellbook rank/subtext, only needed for the General-tab racial test.
local function AddSpellElement(seen, sid, name, isPassive, isGeneral, sub)
  if not sid or isPassive or seen[sid] then return end
  if isGeneral and sub ~= RACIAL_SUB then return end
  if SpellBaseCDSec(sid) < MIN_SPELL_CD then return end
  name = name or SpellNm(sid)
  if not name or name == "" then return end
  seen[sid] = true
  SPELL_ELEMENTS[#SPELL_ELEMENTS + 1] = {
    id = "Spell:" .. sid, label = name, spellID = sid,
    icon      = function() return SpellTex(sid) end,
    cooldown  = function() return SpellCD(sid) end,
    available = function() return true end,
  }
end

local function RebuildSpellElements()
  wipe(SPELL_ELEMENTS)
  local seen = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
    -- Retail (Dragonflight+): C_SpellBook skill lines. Skip OFF-spec lines so we only see the current spec.
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for line = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
      local li = C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookSkillLineInfo(line)
      local offSpec = li and ((li.offSpecID and li.offSpecID ~= 0) or li.isOffSpec)
      if li and li.numSpellBookItems and not offSpec then
        local isGeneral = li.name and (li.name == GENERAL_NAME or li.name == "General")
        local off = li.itemIndexOffset or 0
        for slot = off + 1, off + li.numSpellBookItems do
          local it = C_SpellBook.GetSpellBookItemInfo(slot, bank)
          local sid = it and it.spellID
          local isSpell = it and (not (Enum and Enum.SpellBookItemType) or it.itemType == Enum.SpellBookItemType.Spell)
          if sid and isSpell then
            local isPassive = it.isPassive or (C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(sid))
            local sub = isGeneral and SpellSub(slot, bank, sid) or nil
            AddSpellElement(seen, sid, nil, isPassive, isGeneral, sub)
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellBookItemInfo and GetSpellTabInfo then
    -- Classic / MoP / Cata / TBC / Vanilla: the legacy spellbook tab API (no C_SpellBook there). Same gate;
    -- skip the inactive spec's tab (offSpecID ~= 0). GetSpellBookItemInfo returns (itemType, spellID).
    local BOOK = BOOKTYPE_SPELL or "spell"
    for tab = 1, (GetNumSpellTabs() or 0) do
      local tabName, _, offset, numSpells, _, tabOffSpec = GetSpellTabInfo(tab)
      if not (tabOffSpec and tabOffSpec ~= 0) then
        local isGeneral = tabName and (tabName == GENERAL_NAME or tabName == "General")
        offset = offset or 0
        for i = offset + 1, offset + (numSpells or 0) do
          local stype, sid = GetSpellBookItemInfo(i, BOOK)
          if sid and stype == "SPELL" then
            local isPassive = IsPassiveSpell and IsPassiveSpell(i, BOOK)
            local name, sub = GetSpellBookItemName(i, BOOK)
            AddSpellElement(seen, sid, name, isPassive, isGeneral, sub)
          end
        end
      end
    end
  end
  table.sort(SPELL_ELEMENTS, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
  RebuildIndex()
end

local spellEv = CreateFrame("Frame")
spellEv:RegisterEvent("PLAYER_LOGIN")
spellEv:RegisterEvent("SPELLS_CHANGED")
local function safeReg(e) pcall(spellEv.RegisterEvent, spellEv, e) end
safeReg("PLAYER_SPECIALIZATION_CHANGED")
safeReg("ACTIVE_TALENT_GROUP_CHANGED")
spellEv:SetScript("OnEvent", function() RebuildSpellElements() end)

-- ── Public registry queries (consumed by Meters.lua + the arranger) ──────────
function GSETracker_CooldownElements_List()  -- ordered {id,label} of ALL optional elements (items + spells)
  local out = {}
  for _, e in ipairs(ELEMENTS)       do out[#out + 1] = { id = e.id, label = e.label } end
  for _, e in ipairs(SPELL_ELEMENTS) do out[#out + 1] = { id = e.id, label = e.label } end
  return out
end

function GSETracker_CooldownElements_IsValid(id) return BY_ID[id] ~= nil end
function GSETracker_CooldownElements_Label(id) return (BY_ID[id] and BY_ID[id].label) or id end

-- ── Widget (one frame per element id, created on demand, cached) ──────────────
local frames = {}

-- Build a cooldown widget: icon + engine-driven swipe + engine countdown numbers. The numbers are rendered
-- by the Cooldown frame itself (SetHideCountdownNumbers(false)). We feed it only non-secret start/duration
-- (item cooldowns, or spell cast-time + base CD) so it animates through combat without touching secret values.
local function BuildCDWidget(name, parent)
  local f = CreateFrame("Frame", name, parent or UIParent)
  f:SetSize(24, 24)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints(f)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the default icon border
  f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cd:SetAllPoints(f)
  f.cd:SetHideCountdownNumbers(false)   -- engine renders the centred number (secret-safe)
  f.cd:SetDrawEdge(false)
  return f
end

function GSETracker_CooldownElements_Ensure(id, parent)
  local desc = BY_ID[id]
  if not desc then return nil end
  local f = frames[id]
  if not f then
    f = BuildCDWidget("GSETrackerCDElem_" .. id, parent)
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

-- Run fn(frame) for each currently-shown cooldown item (so the Edit Mode box can measure them into its fit).
function GSETracker_CooldownElements_ForEachShown(fn)
  for _, f in pairs(frames) do
    if f.IsShown and f:IsShown() then fn(f) end
  end
end

-- Push the icon + cooldown onto a widget. s/d are non-secret (item CD, or spell cast-time + base CD); the
-- engine-side Cooldown frame draws the swipe and (SetHideCountdownNumbers(false)) the countdown number and
-- animates them itself, including in combat. SetCooldown(0, 0) clears when there's no cooldown. (pcall is
-- defensive only -- there's no secret-value math here.)
local function PaintCDWidget(f, iconTex, s, d)
  f.icon:SetTexture(iconTex or QUESTION_MARK)
  s = s or 0; d = d or 0
  -- Only (re)apply when the cooldown actually changed. Re-issuing SetCooldown every tick with identical
  -- values restarts the swipe and shows as a flicker. (Values are non-secret here, so comparing is safe.)
  if f._cdStart ~= s or f._cdDur ~= d then
    f._cdStart, f._cdDur = s, d
    pcall(f.cd.SetCooldown, f.cd, s, d)
  end
end

function GSETracker_CooldownElements_Update(id)
  local f = frames[id]
  if not (f and f._desc) then return end
  local s, d = f._desc.cooldown()
  PaintCDWidget(f, f._desc.icon(), s, d)
end

-- ── Tracked Cooldowns bar ────────────────────────────────────────────────────
-- Up to 5 chosen 30s+ spells, assigned per-slot in the "Cooldowns" config grid and rendered as a
-- side-by-side bar wherever the "Cooldowns" element is placed on the main Layout Control grid.
local TRACKED_SLOTS = 5
local trackedFrames = {}
local function TrackedStore()
  MetersSavedVars.trackedCooldowns = MetersSavedVars.trackedCooldowns or {}
  return MetersSavedVars.trackedCooldowns
end
-- The store holds generic ELEMENT IDS ("Trinket1", "Healthstone", "Spell:12345", ...) so the bar can mix
-- items and spells. Legacy saves stored a bare spellID number -- normalise those to "Spell:<id>" on read.
local function NormId(v)
  if type(v) == "number" then return "Spell:" .. v end
  return v
end
function GSETracker_TrackedCooldowns_Count() return TRACKED_SLOTS end
function GSETracker_TrackedCooldowns_SpellAt(slot) return NormId(TrackedStore()[slot]) end
function GSETracker_TrackedCooldowns_SetSpell(slot, id)
  if not (slot and slot >= 1 and slot <= TRACKED_SLOTS) then return end
  if id then                            -- no duplicates: ignore if this element is already in another slot
    local store = TrackedStore()
    for s = 1, TRACKED_SLOTS do
      if s ~= slot and NormId(store[s]) == id then return end
    end
  end
  TrackedStore()[slot] = id
end
-- True if element `id` is assigned to any slot other than exceptSlot (used to filter the picker menu).
function GSETracker_TrackedCooldowns_IsAssigned(id, exceptSlot)
  local store = TrackedStore()
  for s = 1, TRACKED_SLOTS do
    if s ~= exceptSlot and NormId(store[s]) == id then return true end
  end
  return false
end
-- Everything offered in the per-slot picker: the static items (trinkets/healthstone) + discovered spells.
function GSETracker_TrackedCooldowns_SpellList()
  return GSETracker_CooldownElements_List()
end
function GSETracker_TrackedCooldowns_SpellTexture(id)
  local desc = BY_ID[id]
  return desc and desc.icon and desc.icon() or nil
end
function GSETracker_TrackedCooldowns_Ensure(slot, parent)
  if not (slot and slot >= 1 and slot <= TRACKED_SLOTS) then return nil end
  local f = trackedFrames[slot]
  if not f then f = BuildCDWidget("GSETrackerTrackedCD" .. slot, parent); trackedFrames[slot] = f end
  if parent then f:SetParent(parent) end
  return f
end
function GSETracker_TrackedCooldowns_Update(slot)
  local f = trackedFrames[slot]; if not f then return end
  local id = NormId(TrackedStore()[slot])
  if not id then f.icon:SetTexture(nil); f:Hide(); return end
  -- Spell slots render straight from the stored id (override-resolved), NOT via BY_ID: BY_ID is rebuilt
  -- from the spellbook scan and drops a spell the instant it's overridden/upgraded, which made the icon
  -- vanish (and flicker as the entry toggled). Items (no override) still use the descriptor.
  local sidStr = id:match("^Spell:(%d+)")
  if sidStr then
    local sid = ResolveSpell(tonumber(sidStr))
    f:Show()
    PaintCDWidget(f, SpellTex(sid), SpellCD(sid))
    return
  end
  local desc = BY_ID[id]
  if not desc then f.icon:SetTexture(nil); f:Hide(); return end
  PaintCDWidget(f, desc.icon and desc.icon(), desc.cooldown())
end
function GSETracker_TrackedCooldowns_HideAll()
  for _, f in pairs(trackedFrames) do f:Hide() end
end
-- Show occupied slots / hide everything, so the bar follows the Meters HUD visibility (showWhen). Empty
-- slots stay hidden either way; this only governs the slots that actually hold a spell/trinket.
function GSETracker_TrackedCooldowns_SetShown(shown)
  for slot, f in pairs(trackedFrames) do
    f:SetShown(shown and NormId(TrackedStore()[slot]) ~= nil)
  end
end
function GSETracker_TrackedCooldowns_ForEachShown(fn)
  for _, f in pairs(trackedFrames) do if f.IsShown and f:IsShown() then fn(f) end end
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
  for slot, f in pairs(trackedFrames) do
    if f:IsShown() then GSETracker_TrackedCooldowns_Update(slot) end
  end
end)
