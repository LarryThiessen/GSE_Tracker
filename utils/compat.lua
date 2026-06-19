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
  -- Retail-only subsystems (AssistedCombat, the damage-meter API). Gate on the project
  -- FLAVOR too, not just API presence: some Classic clients expose stub C_* tables that
  -- pass a bare existence check, which made these features wrongly appear "available".
  local mainline = (not _G.WOW_PROJECT_ID) or (_G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1))
  features.isMainline = mainline
  features.hasAssistedCombat = mainline and (_G.C_AssistedCombat and type(_G.C_AssistedCombat.GetNextCastSpell) == "function") and true or false
  features.hasDamageMeter = mainline and (_G.C_DamageMeter and type(_G.C_DamageMeter.GetAvailableCombatSessions) == "function") and true or false
  features.hasSettingsCanvas = (_G.Settings and type(_G.Settings.RegisterCanvasLayoutCategory) == "function") and true or false
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

  -- Publish capability flags for feature gating + options grey-out. Read as ns.Caps.*
  -- (true on Retail; false on Classic where the C_* API is absent).
  ns.Caps = ns.Caps or {}
  ns.Caps.assistedHighlight = info.features.hasAssistedCombat
  ns.Caps.meters = info.features.hasDamageMeter
  ns.Caps.settingsPanel = info.features.hasSettingsCanvas
  -- Global mirror for the meters engine files (DPS/HPS/GCD/Details), which don't capture
  -- the `ns` upvalue. Set before any meter readout runs (PLAYER_LOGIN is later).
  _G.GSETracker_MetersCapable = info.features.hasDamageMeter

  if info.isFuture then
    WarnOnce("future_interface", string.format("running on interface %d while addon target is %d. Compatibility mode is active.", info.interface, info.target))
  end
  -- No "below minimum tested" warning: Classic flavors use low interface numbers by design
  -- and are supported, so MIN_TESTED_INTERFACE (a retail number) would false-alarm there.
  -- The running interface is shown in the friendly "loaded!" line instead.

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
  local info = self:GetStatus()
  local iface = (info and tonumber(info.interface)) or 0
  local ver = info and info.addonVersion
  local suffix = ""
  if ver and iface > 0 then
    suffix = string.format(" |cff808080(v%s, interface %d)|r", tostring(ver), iface)
  elseif iface > 0 then
    suffix = string.format(" |cff808080(interface %d)|r", iface)
  end
  local message = prefix .. "|cffffffff loaded!|r" .. suffix

  -- On clients where some features are unavailable (Classic -- no AssistedCombat/DamageMeter),
  -- add a one-line note in chat that greyed-out options aren't available here.
  local caps = ns.Caps
  local note
  if caps and not (caps.assistedHighlight and caps.meters) then
    note = prefix .. "|cffffffff Greyed-out features aren't available in this WoW version.|r"
  end

  if _G and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    _G.DEFAULT_CHAT_FRAME:AddMessage(message)
    if note then _G.DEFAULT_CHAT_FRAME:AddMessage(note) end
    return
  end

  if print then
    print(message)
    if note then print(note) end
  end
end
