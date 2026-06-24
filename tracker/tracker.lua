local _, ns = ...
local addon = ns
local Tracker = ns.Tracker
local API = (ns.Utils and ns.Utils.API) or {}

local frame = Tracker._eventFrame or API.CreateFrame("Frame")
Tracker._eventFrame = frame

local DUPLICATE_SPELL_WINDOW = 0.05
local TEXTURE_CACHE_MAX = 256

local function TrackerEventOnEvent(_, _, unitTarget, castGUID, spellID)
  if not spellID then
    return
  end

  if frame._unitSpellcastFiltered then
    if unitTarget ~= "player" then
      return
    end
  elseif unitTarget and unitTarget ~= "player" then
    return
  end

  if not API.InCombatLockdown() then
    return
  end

  Tracker:HandleSpellcast(spellID, castGUID)
end

addon._recentIcons = addon._recentIcons or {}
Tracker._recentIcons = addon._recentIcons
Tracker._recentIconCount = Tracker._recentIconCount or 0
Tracker._textureCache = Tracker._textureCache or {}
Tracker._textureCacheCount = Tracker._textureCacheCount or 0
Tracker._lastSpellID = Tracker._lastSpellID or false
Tracker._lastSpellAt = Tracker._lastSpellAt or 0
Tracker._lastCastGUID = Tracker._lastCastGUID or nil
Tracker._lastTexture = Tracker._lastTexture or false

local function GetMaxIconCount()
  local count = (addon.GetIconCount and addon:GetIconCount()) or 4
  if count < 4 then
    return 4
  end
  return count
end

local function GetSpellTextureByID(spellID)
  if not spellID then
    return nil
  end

  local cache = Tracker._textureCache
  local cached = cache[spellID]
  if cached then
    return cached
  end

  local tex = API.GetSpellTexture(spellID)
  if tex then
    local count = Tracker._textureCacheCount or 0
    if count >= TEXTURE_CACHE_MAX then
      if API.wipe then
        API.wipe(cache)
      else
        for key in pairs(cache) do
          cache[key] = nil
        end
      end
      count = 0
    end
    cache[spellID] = tex
    Tracker._textureCacheCount = count + 1
  end
  return tex or nil
end

function Tracker:ResetIcons()
  local recent = self._recentIcons or addon._recentIcons or {}
  self._recentIcons = recent
  addon._recentIcons = recent

  local hadIcons = (self._recentIconCount or 0) > 0 or recent[1] ~= nil

  self._recentIconCount = 0
  addon._recentIconCount = 0
  self._lastSpellID = false
  self._lastSpellAt = 0
  self._lastCastGUID = nil
  self._lastTexture = false

  local names = addon._recentNames
  if API.wipe then
    API.wipe(recent)
    if names then API.wipe(names) end
  else
    for i = #recent, 1, -1 do
      recent[i] = nil
    end
    if names then for i = #names, 1, -1 do names[i] = nil end end
  end

  if not hadIcons then
    return
  end

  if addon.ClearSpellHistory then
    addon:ClearSpellHistory()
  elseif addon.SetIconRow then
    addon:SetIconRow(recent)
  end

  if addon.ClearModkeyStacks then
    addon:ClearModkeyStacks()
  end
end

function Tracker:PushRecentTexture(texture, name)
  if not texture then
    return false
  end

  local setIconRow = addon.SetIconRow
  if not setIconRow then
    return false
  end

  local recent = self._recentIcons or addon._recentIcons or {}
  self._recentIcons = recent
  addon._recentIcons = recent
  -- Per-slot spell names, kept in lockstep with `recent` so name[i] always belongs to texture[i]
  -- (the per-icon name labels in vertical layout read this; SetIconRow picks it up via addon._recentNames).
  local names = addon._recentNames or {}
  addon._recentNames = names

  local maxCount = GetMaxIconCount()
  local currentCount = self._recentIconCount or #recent
  if currentCount > maxCount then
    currentCount = maxCount
  end

  for i = currentCount, 1, -1 do
    if i < maxCount then
      recent[i + 1] = recent[i]
      names[i + 1] = names[i]
    end
  end
  recent[1] = texture
  names[1] = name or ""

  if currentCount < maxCount then
    currentCount = currentCount + 1
  end
  self._recentIconCount = currentCount
  addon._recentIconCount = currentCount

  for i = currentCount + 1, #recent do
    recent[i] = nil
    names[i] = nil
  end

  setIconRow(addon, recent)
  return true
end

function Tracker:HandleSpellcast(spellID, castGUID)
  if not spellID then
    return false
  end

  -- Exact-duplicate guard: the same cast instance always carries the same castGUID,
  -- so a re-delivered UNIT_SPELLCAST_SUCCEEDED for that cast is rejected.
  if castGUID and castGUID == self._lastCastGUID then
    return false
  end

  local texture = GetSpellTextureByID(spellID)
  if not texture then
    return false
  end

  local now = API.GetTime()

  -- Same-ability double-fire guard. Some abilities fire TWO
  -- UNIT_SPELLCAST_SUCCEEDED events in the SAME frame under different spellIDs that
  -- share one name/icon (proven: Shadow Dance = 185313 + 185422, identical
  -- timestamp). They differ in spellID and castGUID, so only the shared TEXTURE
  -- identifies them -- reject the second when its texture matches the last push
  -- within the window. Real recasts of the same ability are GCD-spaced (~1s+), far
  -- outside DUPLICATE_SPELL_WINDOW, so legitimate repeats still register.
  if self._lastTexture == texture and (now - (self._lastSpellAt or 0)) <= DUPLICATE_SPELL_WINDOW then
    self._lastCastGUID = castGUID or self._lastCastGUID
    return false
  end

  self._lastSpellID = spellID
  self._lastSpellAt = now
  self._lastCastGUID = castGUID or self._lastCastGUID
  self._lastTexture = texture

  -- Resolve the cast's spell name once; it feeds BOTH the single name display AND the per-icon name
  -- labels beside each icon in vertical layout (carried through PushRecentTexture into its slot).
  local spellName = (API.GetSpellName and API.GetSpellName(spellID)) or ""
  if type(spellName) ~= "string" then spellName = "" end
  if addon.RebuildNameDisplay and spellName ~= "" then
    addon._lastSpellName = spellName
    addon:RebuildNameDisplay()
  end

  -- Did this cast match what the AH was suggesting? (current suggestion, or the one
  -- just before it if GetNextCastSpell already advanced). Match by spellID OR texture
  -- so base/override IDs of one ability still count. Evaluated for EVERY cast so the
  -- % stat covers all of them; the proc icon below only shows on the main-row path.
  local matchedSuggestion = false
  local procEnabled = (addon.GetProcGlowEnabled == nil) or addon:GetProcGlowEnabled()
  if procEnabled then
    if addon._ahSuggestedSpellID and (spellID == addon._ahSuggestedSpellID or texture == addon._ahSuggestedTexture) then
      matchedSuggestion = true
    elseif addon._ahPrevSuggestedSpellID
      and (spellID == addon._ahPrevSuggestedSpellID or texture == addon._ahPrevSuggestedTexture)
      and (now - (addon._ahPrevSuggestedAt or 0)) <= 0.5 then
      matchedSuggestion = true
    end
    -- Per-combat stats (the "AH Match %" readout) + audible alert.
    addon._ahCastCount = (addon._ahCastCount or 0) + 1
    if matchedSuggestion then
      addon._ahMatchCount = (addon._ahMatchCount or 0) + 1
      if addon.PlayAHMatchSound then addon:PlayAHMatchSound() end
    end

    -- Single-Button Assistant correlation by time window. Record this cast so the AH
    -- event handler can retro-count it if the SBA event arrives just AFTER; and count
    -- it now if the SBA event was already armed (event BEFORE the cast).
    addon._lastCastAt = now
    addon._lastCastMatched = matchedSuggestion
    addon._lastCastSbaCounted = false
    if addon._sbaEventActive and (now - (addon._sbaEventAt or 0)) <= 1.0 then
      addon._sbaEventActive = false
      addon._lastCastSbaCounted = true
      addon._ahSbaCastCount = (addon._ahSbaCastCount or 0) + 1
      if matchedSuggestion then addon._ahSbaMatchCount = (addon._ahSbaMatchCount or 0) + 1 end
    end

    if addon.UpdateAHMatchReadout then addon:UpdateAHMatchReadout() end
  end

  -- Route the cast. A Ctrl/Alt-bearing modifier combo is a "proc" -- it goes ONLY to
  -- the centered stack (main row pauses). SHIFT-ONLY (any side, no Ctrl/Alt) and the
  -- no-modifier case both scroll the MAIN row normally and clear the stack.
  local mod = ""
  local stackEnabled = (addon.GetModkeyStackEnabled == nil) or addon:GetModkeyStackEnabled()
  if stackEnabled and addon.GetHeldModifierString then
    mod = addon:GetHeldModifierString() or ""
  end
  local isModkeyStack = (mod ~= "") and (mod:find("Ctrl") ~= nil or mod:find("Alt") ~= nil)

  if isModkeyStack then
    if addon.PushModkeyStackIcon then
      addon:PushModkeyStackIcon(texture, mod)
    end
    return true
  end

  if addon.ClearModkeyStacks then
    addon:ClearModkeyStacks()
  end

  local pushed = self:PushRecentTexture(texture, spellName)
  -- On an AH-suggestion match, show the proc as a separate CENTERED icon (grows in,
  -- glows, fades) so the main row stays undisturbed.
  if pushed and matchedSuggestion and addon.ShowProcCenterIcon then
    addon:ShowProcCenterIcon(texture)
  end
  return pushed
end

function Tracker:InitTracker()
  frame:UnregisterAllEvents()
  local registered, unitFiltered = API.SafeRegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
  frame._unitSpellcastFiltered = unitFiltered and true or false

  if not registered then
    API.SafeSetScript(frame, "OnEvent", nil)
    return
  end

  API.SafeSetScript(frame, "OnEvent", TrackerEventOnEvent)
end
