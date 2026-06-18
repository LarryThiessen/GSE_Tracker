local ADDON_NAME, ns = ...
ns.Utils = ns.Utils or {}

local API = (ns.Utils and ns.Utils.API) or {}
local Compat = ns.Utils.Compat or {}
ns.Utils.Compat = Compat

-- Keep this in sync with the TOC "## Interface:" number on every patch bump, or the
-- "future interface / compatibility mode" warning fires on the current client.
Compat.TARGET_INTERFACE = 120007
Compat.MIN_TESTED_INTERFACE = 110000
Compat._warnedKeys = Compat._warnedKeys or {}
Compat._featureCache = Compat._featureCache or {}
local ADDON_TITLE_FALLBACK = ((ns.Constants and ns.Constants.ADDON_DISPLAY_NAME) or "|cFFFFFFFFGS|r|cFF00FFFFE:|r|cFFFFFF00 Tracker|r")

local function GetAddonTitleText()
  if API.GetAddOnMetadata then
    return API.GetAddOnMetadata(ADDON_NAME, "Title") or ADDON_TITLE_FALLBACK
  end
  return ADDON_TITLE_FALLBACK
end

local function WarnOnce(key, message)
  if Compat._warnedKeys[key] then
    return
  end
  Compat._warnedKeys[key] = true

  if _G and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    _G.DEFAULT_CHAT_FRAME:AddMessage(GetAddonTitleText() .. " " .. tostring(message))
  end
end

function Compat:GetRuntimeInfo()
  local version, build, buildDate, interfaceVersion = nil, nil, nil, 0
  if API.GetBuildInfo then
    version, build, buildDate, interfaceVersion = API.GetBuildInfo()
  end
  local addonVersion = API.GetAddOnMetadata and API.GetAddOnMetadata(ADDON_NAME, "Version") or nil

  return {
    addonVersion = addonVersion,
    version = version,
    build = build,
    buildDate = buildDate,
    interface = tonumber(interfaceVersion) or 0,
    target = self.TARGET_INTERFACE,
    minTested = self.MIN_TESTED_INTERFACE,
  }
end

function Compat:IsFutureInterface(interfaceVersion)
  interfaceVersion = tonumber(interfaceVersion) or 0
  return interfaceVersion > (self.TARGET_INTERFACE or 0)
end

function Compat:IsTooOld(interfaceVersion)
  interfaceVersion = tonumber(interfaceVersion) or 0
  return interfaceVersion > 0 and interfaceVersion < (self.MIN_TESTED_INTERFACE or 0)
end

function Compat:DetectFeatures()
  local features = self._featureCache
  features.hasCSpell = (_G.C_Spell and type(_G.C_Spell.GetSpellTexture) == "function") and true or false
  features.hasLegacySpellAPI = (type(_G.GetSpellTexture) == "function") and true or false
  features.hasCAddOns = (_G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function") and true or false
  features.hasLegacyAddOnAPI = (type(_G.GetAddOnMetadata) == "function") and true or false
  return features
end

function Compat:GetStatus()
  return self.runtimeInfo or self:CheckRuntime()
end

function Compat:IsCompatibilityMode()
  local info = self:GetStatus()
  return info and info.isFuture == true
end

function Compat:CheckRuntime()
  local info = self:GetRuntimeInfo()
  info.isFuture = self:IsFutureInterface(info.interface)
  info.isTooOld = self:IsTooOld(info.interface)
  info.features = self:DetectFeatures()
  self.runtimeInfo = info

  if info.isFuture then
    WarnOnce("future_interface", string.format("running on interface %d while addon target is %d. Compatibility mode is active.", info.interface, info.target))
  elseif info.isTooOld then
    WarnOnce("old_interface", string.format("running on interface %d, below the minimum tested %d. Some behavior may be limited.", info.interface, info.minTested))
  end

  if not info.features.hasCSpell and not info.features.hasLegacySpellAPI then
    WarnOnce("spell_api_missing", "spell texture APIs were not found. Spell icons may be unavailable until Blizzard restores one of the supported APIs.")
  end

  if not info.features.hasCAddOns and not info.features.hasLegacyAddOnAPI then
    WarnOnce("addon_metadata_missing", "addon metadata APIs were not found. Version checks will use fallback values.")
  end

  return info
end

function Compat:PrintLoadedMessage()
  local prefix = GetAddonTitleText()
  local message = prefix .. "|cffffffff loaded!|r"

  if _G and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    _G.DEFAULT_CHAT_FRAME:AddMessage(message)
    return
  end

  if print then
    print(message)
  end
end
