local _, ns = ...
ns.Utils = ns.Utils or {}

local API = ns.Utils.API or {}
ns.Utils.API = API

local G = _G
local noop = function() end

function API.CreateFrame(...)
  return G.CreateFrame(...)
end

function API.GetTime()
  return G.GetTime and G.GetTime() or 0
end

function API.InCombatLockdown()
  return G.InCombatLockdown and G.InCombatLockdown() or false
end

function API.GetBuildInfo()
  if G.GetBuildInfo then
    local version, build, buildDate, interfaceVersion = G.GetBuildInfo()
    return version, build, buildDate, tonumber(interfaceVersion) or 0
  end
  return nil, nil, nil, 0
end

function API.GetSpellTexture(spellID)

  if G.C_Spell and G.C_Spell.GetSpellTexture then
    return G.C_Spell.GetSpellTexture(spellID)
  end

  if G.GetSpellTexture then
    return G.GetSpellTexture(spellID)
  end

  if G.C_Spell and G.C_Spell.GetSpellInfo then
    local info = G.C_Spell.GetSpellInfo(spellID)
    if type(info) == "table" then
      return info.iconID or info.iconFileID or nil
    end
  end

  if G.GetSpellInfo then
    local _, _, icon = G.GetSpellInfo(spellID)
    return icon
  end

  return nil
end

function API.GetSpellName(spellID)
  if not spellID then return nil end
  if G.C_Spell and G.C_Spell.GetSpellName then
    return G.C_Spell.GetSpellName(spellID)
  end
  if G.C_Spell and G.C_Spell.GetSpellInfo then
    local info = G.C_Spell.GetSpellInfo(spellID)
    if type(info) == "table" then return info.name end
  end
  if G.GetSpellInfo then
    local name = G.GetSpellInfo(spellID)
    return name
  end
  return nil
end

function API.UnitExists(unit)
  return G.UnitExists and G.UnitExists(unit) or false
end

function API.UnitCanAttack(unit, otherUnit)
  return G.UnitCanAttack and G.UnitCanAttack(unit, otherUnit) or false
end

-- True when the player has a target that can be attacked (the macro [harm] sense),
-- as opposed to merely having any target (which would include friendly units).
function API.HasHarmTarget()
  if not (G.UnitExists and G.UnitExists("target")) then
    return false
  end
  return G.UnitCanAttack and G.UnitCanAttack("player", "target") and true or false
end

function API.IsAltKeyDown()
  return G.IsAltKeyDown and G.IsAltKeyDown() or false
end

function API.IsShiftKeyDown()
  return G.IsShiftKeyDown and G.IsShiftKeyDown() or false
end

function API.IsControlKeyDown()
  return G.IsControlKeyDown and G.IsControlKeyDown() or false
end

function API.UnitClass(unit)
  if G.UnitClass then
    return G.UnitClass(unit)
  end
  return nil, nil
end

function API.hooksecurefunc(...)
  if G.hooksecurefunc then
    return G.hooksecurefunc(...)
  end
  return noop
end

function API.SafeHooksecurefunc(...)
  local ok, result = pcall(API.hooksecurefunc, ...)
  if ok then
    return true, result
  end
  return false, nil
end

function API.wipe(t)
  if G.wipe then
    return G.wipe(t)
  end
  if type(t) == "table" then
    for k in pairs(t) do
      t[k] = nil
    end
  end
  return t
end

function API.IsAddOnLoaded(name)
  return G.IsAddOnLoaded and G.IsAddOnLoaded(name) or false
end

function API.GetBindingText(...)
  return G.GetBindingText and G.GetBindingText(...) or nil
end

function API.GetCursorPosition()
  if G.GetCursorPosition then
    return G.GetCursorPosition()
  end
  return 0, 0
end

function API.GetEffectiveScale(frame)
  if frame and frame.GetEffectiveScale then
    return frame:GetEffectiveScale()
  end
  return 1
end

function API.UIParent()
  return G.UIParent
end

function API.GetAddOnMetadata(addonName, field)

  if G.C_AddOns and G.C_AddOns.GetAddOnMetadata then
    local ok, value = pcall(G.C_AddOns.GetAddOnMetadata, addonName, field)
    if ok then
      return value
    end
  end

  if G.GetAddOnMetadata then
    local ok, value = pcall(G.GetAddOnMetadata, addonName, field)
    if ok then
      return value
    end
  end

  return nil
end

function API.SafeUnregisterEvent(frame, eventName)
  if not (frame and frame.UnregisterEvent and type(eventName) == "string" and eventName ~= "") then
    return false
  end
  local ok = pcall(frame.UnregisterEvent, frame, eventName)
  return ok and true or false
end

function API.SafeSetScript(frame, scriptName, handler)
  if not (frame and frame.SetScript and type(scriptName) == "string" and scriptName ~= "") then
    return false
  end
  local ok = pcall(frame.SetScript, frame, scriptName, handler)
  return ok and true or false
end

function API.SafeRegisterEvent(frame, eventName)
  if not (frame and frame.RegisterEvent and type(eventName) == "string" and eventName ~= "") then
    return false
  end
  local ok = pcall(frame.RegisterEvent, frame, eventName)
  return ok and true or false
end

function API.SafeRegisterUnitEvent(frame, eventName, unit)
  if not frame or type(eventName) ~= "string" or eventName == "" then
    return false, false
  end

  if frame.RegisterUnitEvent and type(unit) == "string" and unit ~= "" then
    local ok = pcall(frame.RegisterUnitEvent, frame, eventName, unit)
    if ok then
      return true, true
    end
  end

  return API.SafeRegisterEvent(frame, eventName), false
end

return API
