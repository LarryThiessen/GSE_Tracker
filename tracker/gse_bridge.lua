local _, ns = ...
local addon = ns
local Tracker = ns.Tracker
local API = (ns.Utils and ns.Utils.API) or {}

local SafeHooksecurefunc = API.SafeHooksecurefunc or function() return false, nil end
local next = next
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local rawget = rawget
local type = type

local hookedButtons = {}
local pendingButtons = {}

local seqObjCache = {}
local cacheLib = nil
local function EnsureSeqCache(lib)
  if lib ~= cacheLib then
    cacheLib = lib
    seqObjCache = {}
  end
end

local lateProbeStarted = false
local lateProbeFrame = nil
local bindingEventFrame = Tracker._bindingEventFrame or API.CreateFrame("Frame")
Tracker._bindingEventFrame = bindingEventFrame
local StartLateProbe
local StopLateProbe
local LATE_PROBE_INTERVAL = 0.25
local LATE_PROBE_MAX_TRIES = 40
local lateProbeElapsed = 0
local lateProbeTries = 0

local function GetLibrary()
  local GSE = _G.GSE
  local lib = GSE and rawget(GSE, "Library")
  return (type(lib) == "table") and lib or nil
end

local function GetUsedSequences()
  local GSE = _G.GSE
  local used = GSE and rawget(GSE, "UsedSequences")
  return (type(used) == "table") and used or nil
end

local function FindSequenceObject(seqKey)
  if type(seqKey) ~= "string" or seqKey == "" then return nil end

  local lib = GetLibrary()
  if not lib then return nil end
  EnsureSeqCache(lib)

  local cached = seqObjCache[seqKey]
  if cached then return cached end

  for _, bucket in pairs(lib) do
    if type(bucket) == "table" then
      local seq = rawget(bucket, seqKey)
      if type(seq) == "table" then
        seqObjCache[seqKey] = seq
        return seq
      end
    end
  end

  local direct = rawget(lib, seqKey)
  if type(direct) == "table" then
    seqObjCache[seqKey] = direct
    return direct
  end

  return nil
end

local function IsValidSequenceKey(seqKey)
  if FindSequenceObject(seqKey) ~= nil then return true end
  -- GSE compiles each sequence into a global secure button named after the
  -- sequence (it uses _G[Sequence] as the clickbutton target). If that global
  -- exists the key is a real, in-use GSE sequence even when its Library entry is
  -- still compressed / not yet decompressed -- so don't reject it.
  if type(seqKey) == "string" and seqKey ~= "" and type(rawget(_G, seqKey)) == "table" then
    return true
  end
  return false
end

local function GetPrettyName(seqKey)
  local seq = FindSequenceObject(seqKey)
  if not seq then return seqKey end

  local md = rawget(seq, "MetaData") or rawget(seq, "metadata")
  if type(md) == "table" then
    local name = rawget(md, "Name") or rawget(md, "name")
    if type(name) == "string" and name ~= "" then
      return name
    end
  end

  return seqKey
end

local function SetActiveSequence(seqKey)
  if not IsValidSequenceKey(seqKey) then return end

  if addon._activeSeqKey ~= seqKey then
    addon._activeSeqKey = seqKey
    addon._gseActive = true
    addon._lastGSEPressTime = API.GetTime()

    if addon.ResetIcons then
      addon:ResetIcons()
    end

    -- Feed the GSE sequence name into its slot; RebuildNameDisplay combines it with the spell name
    -- per the independent toggles (so it shows whenever "GSE Sequence Name" is enabled, alone or
    -- stacked with the spell name).
    addon._gseSeqName = GetPrettyName(seqKey)
    if addon.RebuildNameDisplay then addon:RebuildNameDisplay() end
    if addon.RefreshPressedIndicator then
      addon:RefreshPressedIndicator(true)
    end
  else
    addon._lastGSEPressTime = API.GetTime()

    if addon.ui and addon.ui.nameText and addon._activeSeqKey == seqKey then
      local cur = addon.ui.nameText:GetText()
      local alpha = addon.ui.nameText.GetAlpha and addon.ui.nameText:GetAlpha() or 1
      if not cur or cur == "" or alpha == 0 then
        addon._gseSeqName = GetPrettyName(seqKey)
        if addon.RebuildNameDisplay then addon:RebuildNameDisplay() end
      end
    end
    if addon.RefreshPressedIndicator then
      addon:RefreshPressedIndicator(true)
    end
  end
end

local FIELD_KEYS = {
  "GSESequence",
  "Sequence",
  "name",
}

local ATTR_KEYS = {
  -- GSE now tags its click buttons with the "gse-button" attribute holding the
  -- sequence name (GSE/API/Events.lua: SetAttribute("gse-button", Sequence)).
  -- This replaced the older GSESequence/Sequence attributes; keep the legacy
  -- names as fallbacks for older GSE builds.
  "gse-button",
  "GSESequence",
  "Sequence",
  "name",
}

local function TryGetField(btn, key)
  local v = rawget(btn, key)
  if type(v) == "string" and v ~= "" then
    return v
  end
end

local function TryGetAttribute(btn, attr)
  if not (btn and btn.GetAttribute) then return nil end
  local ok, v = pcall(btn.GetAttribute, btn, attr)
  if ok and type(v) == "string" and v ~= "" then
    return v
  end
end

local function TryResolveUsedSequence(buttonName)
  if type(buttonName) ~= "string" or buttonName == "" then return nil end

  local used = GetUsedSequences()
  local entry = used and rawget(used, buttonName) or nil
  if type(entry) == "string" and IsValidSequenceKey(entry) then
    return entry
  end

  if type(entry) == "table" then
    local candidates = {
      rawget(entry, "Sequence"),
      rawget(entry, "sequence"),
      rawget(entry, "GSESequence"),
      rawget(entry, "Name"),
      rawget(entry, "name"),
      rawget(entry, "Macro"),
      rawget(entry, "macro"),
      rawget(entry, 1),
    }
    for i = 1, #candidates do
      local candidate = candidates[i]
      if type(candidate) == "string" and candidate ~= "" and IsValidSequenceKey(candidate) then
        return candidate
      end
    end
  end

  return nil
end

local function ResolveSequenceKey(btn)
  if not btn then return nil end

  for _, key in ipairs(FIELD_KEYS) do
    local v = TryGetField(btn, key)
    if v and IsValidSequenceKey(v) then
      return v
    end
  end

  for _, attr in ipairs(ATTR_KEYS) do
    local v = TryGetAttribute(btn, attr)
    if v and IsValidSequenceKey(v) then
      return v
    end
  end

  local buttonName = btn and btn.GetName and btn:GetName() or nil
  local usedSeq = TryResolveUsedSequence(buttonName)
  if usedSeq then
    return usedSeq
  end

  return nil
end

local function HookButton(buttonName)
  if hookedButtons[buttonName] then return end

  local btn = _G[buttonName]
  if not btn or not btn.HookScript then return end

  btn:HookScript("PostClick", function(self)
    local seqKey = ResolveSequenceKey(self)
    if seqKey then
      SetActiveSequence(seqKey)
    end
  end)

  hookedButtons[buttonName] = true
  pendingButtons[buttonName] = nil
end

local function RememberButton(buttonName)
  if type(buttonName) ~= "string" or buttonName == "" then return end
  if hookedButtons[buttonName] then return end

  HookButton(buttonName)
  if hookedButtons[buttonName] then
    pendingButtons[buttonName] = nil
    return
  end

  pendingButtons[buttonName] = true
  if not lateProbeStarted then
    StartLateProbe()
  end
end

local function HookBindingAPIs()
  if addon.__BridgeBindingHooks then return end
  addon.__BridgeBindingHooks = true

  -- We hook GSE's binding calls only to DISCOVER the click buttons it creates, so we
  -- can PostClick-hook them for sequence detection. The bound KEY itself is ignored --
  -- this addon no longer displays keybinds; GSE provides its own keybind tooling.
  -- SetOverrideBindingClick(owner, isPriority, KEY, buttonName, clickButton)
  SafeHooksecurefunc("SetOverrideBindingClick", function(_, _, _, buttonName)
    RememberButton(buttonName)
  end)

  -- SetBindingClick(KEY, buttonName, clickButton)
  SafeHooksecurefunc("SetBindingClick", function(_, buttonName)
    RememberButton(buttonName)
  end)
end

local function LateProbeOnUpdate(_, dt)
  lateProbeElapsed = lateProbeElapsed + dt
  if lateProbeElapsed < LATE_PROBE_INTERVAL then return end
  lateProbeElapsed = 0
  lateProbeTries = lateProbeTries + 1

  if next(pendingButtons) == nil then
    StopLateProbe(false)
    return
  end

  for buttonName in pairs(pendingButtons) do
    HookButton(buttonName)
  end

  if next(pendingButtons) == nil then
    StopLateProbe(false)
    return
  end

  if lateProbeTries >= LATE_PROBE_MAX_TRIES then
    StopLateProbe(true)
  end
end

StopLateProbe = function(clearPending)
  if lateProbeFrame then
    lateProbeFrame:SetScript("OnUpdate", nil)
  end
  lateProbeStarted = false

  if clearPending then
    for buttonName in pairs(pendingButtons) do
      pendingButtons[buttonName] = nil
    end
  end
end

StartLateProbe = function()
  if lateProbeStarted or next(pendingButtons) == nil then return end
  lateProbeStarted = true
  lateProbeElapsed = 0
  lateProbeTries = 0
  lateProbeFrame = lateProbeFrame or API.CreateFrame("Frame")
  lateProbeFrame:SetScript("OnUpdate", LateProbeOnUpdate)
end

local function ScanExistingBindings()
  if type(GetNumBindings) == "function" and type(GetBinding) == "function" then
    local numBindings = GetNumBindings() or 0
    for i = 1, numBindings do
      local command = GetBinding(i)
      if type(command) == "string" then
        local buttonName = command:match("^CLICK%s+([^:]+):")
        if buttonName and buttonName ~= "" then
          RememberButton(buttonName)
        end
      end
    end
  end

  local used = GetUsedSequences()
  if used then
    local buttonNames = {}
    for buttonName in pairs(used) do
      if type(buttonName) == "string" and buttonName ~= "" then
        buttonNames[#buttonNames + 1] = buttonName
      end
    end
    table.sort(buttonNames)

    for i = 1, #buttonNames do
      RememberButton(buttonNames[i])
    end
  end
end

local function BindingEventOnEvent(_, event, arg1)
  if event == "UPDATE_BINDINGS" then
    -- Rescan live bindings so newly-bound GSE buttons are discovered and hooked.
    ScanExistingBindings()
    return
  end

  if event == "ADDON_LOADED" and arg1 == "GSE" then
    -- Without an OptionalDeps ordering guarantee, rescan as soon as GSE finishes
    -- loading so existing buttons and UsedSequences are picked up immediately.
    ScanExistingBindings()
  end
end

function Tracker:GetActiveSequenceDisplayText(seqKey)
  seqKey = seqKey or self._activeSeqKey
  if type(seqKey) ~= "string" or seqKey == "" then
    return nil
  end
  if not IsValidSequenceKey(seqKey) then
    return nil
  end
  local displayName = GetPrettyName(seqKey)
  if type(displayName) == "string" and displayName ~= "" then
    return displayName
  end
  return nil
end

function Tracker:InitGSEBridge()
  HookBindingAPIs()
  ScanExistingBindings()
  if bindingEventFrame then
    bindingEventFrame:UnregisterAllEvents()
    API.SafeRegisterEvent(bindingEventFrame, "UPDATE_BINDINGS")
    API.SafeRegisterEvent(bindingEventFrame, "ADDON_LOADED")
    API.SafeSetScript(bindingEventFrame, "OnEvent", BindingEventOnEvent)
  end
end
