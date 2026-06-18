-- Modules\Meters\Details.lua (Optimized)

local addonName, ns = ...
local WINDOW_NAME        = "DetailsFrame"
local STOCK_COMBAT_TEXT  = "-- COMBAT --."
local SESSION_TYPE       = (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current) or 1

local VIEW_DATA = {
    damage = {
        key = "damage", label = "Damage", rateLabel = "DPS",
        emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone) or 0,
        showOverkill = true, showRate = true,
    },
    healing = {
        key = "healing", label = "Healing", rateLabel = "HPS",
        emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone) or 2,
        showOverkill = false, showRate = true,
    },
    dispels = {
        key = "dispels", label = "Dispels", rateLabel = "Dispels",
        emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.Dispels) or 6,
        showOverkill = false, showRate = false,
    },
    interrupts = {
        key = "interrupts", label = "Interrupts", rateLabel = "Interrupts",
        emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.Interrupts) or 5,
        showOverkill = false, showRate = false,
    },
}

local DEFAULT_VIEW    = "damage"
local DEFAULT_WIDTH   = 375
local DEFAULT_HEIGHT  = 200
local MIN_WIDTH       = 375
local MIN_HEIGHT      = 70
local MAX_WIDTH       = 550
local MAX_HEIGHT      = 750

local ICON_SIZE            = 26
local ROW_HEIGHT           = ICON_SIZE
local ROW_GAP              = 0
local EDGE_PADDING         = 8
local TITLE_BAR_HEIGHT     = 26
local TITLE_BAR_GAP        = 2
local TITLE_BUTTON_SIZE    = 24
local TITLE_BUTTON_GAP     = 4
local TITLE_TEXT_SIZE      = 12
local TAB_WIDTH            = 24
local TAB_HEIGHT           = 24
local TAB_GAP              = 2
local TAB_TEXT_SIZE        = 11
local MINIMIZED_WIDTH      = MIN_WIDTH
local MINIMIZED_HEIGHT     = MIN_HEIGHT
local RIGHT_SAFE_PAD       = 0
local BOTTOM_SAFE_PAD      = 0
local BAR_HEIGHT           = ICON_SIZE
local TEXT_SIZE            = 13
local PERCENT_WIDTH        = 42
local VALUE_WIDTH          = 112
local COLUMN_GAP           = 8

local DAMAGE_TAB_TEXTURE_PATH     = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\damage.png"
local HEALING_TAB_TEXTURE_PATH    = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\healing.png"
local DISPELS_TAB_TEXTURE_PATH    = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\dispell.png"
local INTERRUPTS_TAB_TEXTURE_PATH = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\interrupt.png"
local CLOSE_TEXTURE_PATH          = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\close.png"
local MINIMIZE_TEXTURE_PATH       = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\minimize.png"
local EXPAND_TEXTURE_PATH         = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\expand.png"
local DROPDOWN_TEXTURE_PATH       = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\down.png"
local EXPAND_ALL_TEXTURE_PATH     = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\down.png"
local LEFT_CHEVRON_TEXTURE_PATH   = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\left-chevron.png"
local RIGHT_CHEVRON_TEXTURE_PATH  = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\right-chevron.png"

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- OPTIMISATION: module-level constant tables avoid allocations inside hot loops
local CAST_COUNT_KEYS = {
    "castCount","casts","numCasts","totalCasts",
    "spellCastCount","totalCastCount","castAmount","numberOfCasts",
}
local BUILD_INTERFACE       = select(4, GetBuildInfo()) or 0
local USE_STOCK_SPECIAL_VIEWS = BUILD_INTERFACE >= 120000
local CUSTOM_VIEW_KEYS      = USE_STOCK_SPECIAL_VIEWS and {} or { dispels = true, interrupts = true }
local PET_GROUPED_VIEW_KEYS = { damage  = true }

local CUSTOM_ATTEMPT_TIMEOUT    = 0.75
local TAB_DOUBLE_CLICK_THRESHOLD = 0.30

local INTERRUPT_SPELL_IDS = {
    [1766]=true,[2139]=true,[47528]=true,[57994]=true,[6552]=true,
    [96231]=true,[106839]=true,[116705]=true,[147362]=true,[183752]=true,
    [19647]=true,[78675]=true,[187707]=true,[351338]=true,
}
local DISPEL_SPELL_IDS = {
    [370]=true,[475]=true,[527]=true,[528]=true,[2782]=true,[2908]=true,
    [4987]=true,[32375]=true,[30449]=true,[51886]=true,[77130]=true,
    [88423]=true,[115310]=true,[115450]=true,[119905]=true,[213644]=true,
    [278326]=true,
}

local customTracker = {
    dispels    = { entries = {}, pending = {} },
    interrupts = { entries = {}, pending = {} },
}

local rows       = {}
local tabButtons = {}
local frame
local RefreshDetails

-- Combat-session paging: 0 = the live/current session; 1..N pages back through the last
-- 10 completed sessions (Blizzard's C_DamageMeter.GetAvailableCombatSessions history).
local detailsPageOffset = 0
local MAX_DETAILS_PAGES = 10
local currentView = DEFAULT_VIEW
local UpdateWindowButtonVisuals
local ToggleMinimized
local UpdateContentWidth
local UpdateScrollBounds
local MarkPendingPostCombatRefresh
local TryPendingPostCombatRefresh

-- ─── Utilities ────────────────────────────────────────────────────────────────
local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- OPTIMISATION: most-common views first to short-circuit the chain early.
local function NormalizeViewKey(viewKey)
    if type(viewKey) ~= "string" then return DEFAULT_VIEW end
    viewKey = viewKey:lower()
    if viewKey == "damage"  or viewKey == "dmg"    or viewKey == "dps"  then return "damage"     end
    if viewKey == "healing" or viewKey == "heal"   or viewKey == "hps"  then return "healing"    end
    if viewKey == "dispels" or viewKey == "dispel" or viewKey == "disp" then return "dispels"    end
    if viewKey == "interrupts" or viewKey == "interrupt"
       or viewKey == "int"  or viewKey == "kick"   or viewKey == "kicks" then return "interrupts" end
    return DEFAULT_VIEW
end

local function Round(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function IsNonEmptyString(v)
    return type(v) == "string" and v ~= ""
end

-- ─── Database ─────────────────────────────────────────────────────────────────
-- OPTIMISATION: original GetDetailsDB re-checked every field on every call.
-- Now we init once and cache the reference; invalidated on PLAYER_ENTERING_WORLD.
local _detailsDB = nil

local function InitDetailsDB()
    MetersSavedVars           = MetersSavedVars or {}
    MetersSavedVars.Details = MetersSavedVars.Details or {}
    local db = MetersSavedVars.Details
    if MetersSavedVars.showDetails == nil then
        MetersSavedVars.showDetails = db.enabled ~= false
    end
    if MetersSavedVars.hideDetailsInCombat == nil then
        MetersSavedVars.hideDetailsInCombat = db.hideInCombat == true
    end
    if db.enabled      == nil then db.enabled      = MetersSavedVars.showDetails ~= false end
    if db.hideInCombat == nil then db.hideInCombat = MetersSavedVars.hideDetailsInCombat == true end
    db.hideInCombat = MetersSavedVars.hideDetailsInCombat == true
    if db.point         == nil then db.point         = "CENTER"       end
    if db.relativePoint == nil then db.relativePoint = "CENTER"       end
    if db.x             == nil then db.x             = 0              end
    if db.y             == nil then db.y             = 0              end
    if db.width         == nil then db.width         = DEFAULT_WIDTH  end
    if db.height        == nil then db.height        = DEFAULT_HEIGHT end
    if db.expandedWidth  == nil then db.expandedWidth  = DEFAULT_WIDTH  end
    if db.expandedHeight == nil then db.expandedHeight = DEFAULT_HEIGHT end
    if db.isMinimized   == nil then db.isMinimized   = false          end
    if db.wasShown      == nil then db.wasShown      = false          end
    if db.viewKey       == nil then db.viewKey       = DEFAULT_VIEW   end
    if type(db.petGroupExpanded) ~= "table" then db.petGroupExpanded = {} end
    _detailsDB = db
    return db
end

local function GetDetailsDB()
    if _detailsDB then return _detailsDB end
    return InitDetailsDB()
end

-- ─── Pet group state ──────────────────────────────────────────────────────────
local function NormalizePetGroupKey(petName)
    petName = tostring(petName or "")
    return petName ~= "" and petName or nil
end

local function IsPetGroupingEnabled(viewKey)
    return PET_GROUPED_VIEW_KEYS[NormalizeViewKey(viewKey)] == true
end

local function GetPetGroupStateTable(viewKey)
    local db = GetDetailsDB()
    if type(db.petGroupExpanded) ~= "table" then db.petGroupExpanded = {} end
    local nv = NormalizeViewKey(viewKey)
    if type(db.petGroupExpanded[nv]) ~= "table" then db.petGroupExpanded[nv] = {} end
    return db.petGroupExpanded[nv]
end

local function IsPetGroupExpanded(viewKey, petName)
    local key = NormalizePetGroupKey(petName)
    if not key then return false end
    return GetPetGroupStateTable(viewKey)[key] == true
end

local function SetPetGroupExpanded(viewKey, petName, expanded)
    local key = NormalizePetGroupKey(petName)
    if not key then return end
    GetPetGroupStateTable(viewKey)[key] = expanded == true
end

-- ─── Window state ─────────────────────────────────────────────────────────────
local function SaveDetailsWindowState()
    if not frame then return end
    local db = GetDetailsDB()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    db.point         = point         or "CENTER"
    db.relativePoint = relativePoint or "CENTER"
    db.x = Round(x or 0); db.y = Round(y or 0)
    db.isMinimized = frame.isMinimized == true
    db.viewKey     = NormalizeViewKey(currentView)
    if frame.isMinimized then
        db.width  = MINIMIZED_WIDTH;  db.height = MINIMIZED_HEIGHT
        db.expandedWidth  = Round(frame.lastExpandedWidth  or DEFAULT_WIDTH)
        db.expandedHeight = Round(frame.lastExpandedHeight or DEFAULT_HEIGHT)
    else
        local w = Clamp(Round(frame:GetWidth()  or DEFAULT_WIDTH),  MIN_WIDTH,  MAX_WIDTH)
        local h = Clamp(Round(frame:GetHeight() or DEFAULT_HEIGHT), MIN_HEIGHT, MAX_HEIGHT)
        db.width = w; db.height = h; db.expandedWidth = w; db.expandedHeight = h
    end
end

local function RestoreDetailsWindowState()
    if not frame then return end
    local db = GetDetailsDB()
    currentView = NormalizeViewKey(db.viewKey)
    frame.lastExpandedWidth  = Clamp(tonumber(db.expandedWidth)  or DEFAULT_WIDTH,  MIN_WIDTH,  MAX_WIDTH)
    frame.lastExpandedHeight = Clamp(tonumber(db.expandedHeight) or DEFAULT_HEIGHT, MIN_HEIGHT, MAX_HEIGHT)
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER",
                   tonumber(db.x) or 0, tonumber(db.y) or 0)
    if db.isMinimized then
        frame.isMinimized = true; frame:SetSize(MINIMIZED_WIDTH, MINIMIZED_HEIGHT)
    else
        frame.isMinimized = false
        frame:SetSize(Clamp(tonumber(db.width)  or DEFAULT_WIDTH,  MIN_WIDTH,  MAX_WIDTH),
                      Clamp(tonumber(db.height) or DEFAULT_HEIGHT, MIN_HEIGHT, MAX_HEIGHT))
    end
end

local function ApplySavedWindowState(keepCurrentView)
    if not frame then return end
    local wantedView = keepCurrentView and NormalizeViewKey(currentView) or nil
    RestoreDetailsWindowState()
    if wantedView then currentView = wantedView end
    UpdateWindowButtonVisuals(); UpdateContentWidth(); UpdateScrollBounds()
end

local function IsDetailsEnabled()
    return not (MetersSavedVars and MetersSavedVars.showDetails == false)
end

local function ShouldHideDetailsInCombat()
    if not MetersSavedVars then return false end
    return MetersSavedVars.hideDetailsInCombat == true
end

local function SyncDetailsOptionForHiddenWindow()
    if Meters_SetDetailsOptionChecked then
        Meters_SetDetailsOptionChecked(false)
        return
    end

    if not MetersSavedVars then return end
    MetersSavedVars.showDetails = false
    if MetersSavedVars.Details then
        MetersSavedVars.Details.enabled  = false
        MetersSavedVars.Details.wasShown = false
    end
end

local function ApplyInitialWindowState()
    if not frame then return end
    ApplySavedWindowState(false)
    local db = GetDetailsDB()
    if IsDetailsEnabled() then
        db.wasShown = true
        frame:Show(); frame:Raise()
        if frame.isMinimized then
            for i = 1, #rows do rows[i]:Hide() end
            UpdateContentWidth(); frame.content:SetHeight(1)
            frame.emptyText:SetText(""); UpdateScrollBounds()
        else
            RefreshDetails(true)
        end
    else
        frame:Hide()
    end
    SaveDetailsWindowState()
end

-- ─── View helpers ─────────────────────────────────────────────────────────────
local function GetCurrentViewInfo()
    return VIEW_DATA[currentView] or VIEW_DATA[DEFAULT_VIEW]
end

local function IsCustomView(viewKey)
    return CUSTOM_VIEW_KEYS[NormalizeViewKey(viewKey)] == true
end

-- ─── Class / font ─────────────────────────────────────────────────────────────
local function GetPlayerClassColor()
    local _, classTag = UnitClass("player")
    local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classTag and classColors and classColors[classTag]
    if c then return c.r, c.g, c.b end
    return 0.48, 0.66, 0.25
end

-- OPTIMISATION: GetSelectedFontPath is called per-row during a render pass.
-- Cache it for the duration of the pass; invalidated by InvalidateFontCache().
local _cachedFontPath = nil

local function GetSelectedFontPath()
    if _cachedFontPath then return _cachedFontPath end
    -- Auto-adopt the action-bar font FACE when a UI skin is active (mirrors the
    -- tracker text/border/icon adoption); Force-Native falls through to the
    -- player's LibSharedMedia pick below. Re-evaluated each render pass because
    -- RefreshDetails() invalidates this cache at the start of every pass.
    local us = ns and ns._ui
    if us and us.GetAdoptedFontStyle then
        local ap = us.GetAdoptedFontStyle()
        if ap then _cachedFontPath = ap; return ap end
    end
    local fontName = MetersSavedVars and MetersSavedVars.fontType
    if LSM and fontName and fontName ~= "" then
        local fp = LSM:Fetch("font", fontName, true)
        if fp then _cachedFontPath = fp; return fp end
    end
    _cachedFontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    return _cachedFontPath
end

local function InvalidateFontCache() _cachedFontPath = nil end

-- ─── Number formatting ────────────────────────────────────────────────────────
local function AddCommas(value)
    local left, num, right = tostring(value):match("^([^%d]*%d)(%d*)(.-)$")
    return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function FormatMainNumber(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value)) < 0.05 then
        return AddCommas(math.floor(value + 0.5))
    end
    local whole = math.floor(value)
    local frac  = math.floor((value - whole) * 10 + 0.5)
    if frac >= 10 then whole = whole + 1; frac = 0 end
    return AddCommas(whole) .. "." .. tostring(frac)
end

local function FormatParenTotal(value)
    value = tonumber(value) or 0
    if value >= 1000000 then return string.format("%.1f M", value / 1000000) end
    if value >= 100000  then return string.format("%.0f K", value / 1000)    end
    return FormatMainNumber(value)
end

local function FormatPercent(value)
    return string.format("%.0f%%", tonumber(value) or 0)
end

local function FormatCustomRowValue(entry)
    if type(entry) ~= "table" then return "S0 F0 I0 M0 O0 T0" end
    return string.format("S%d F%d I%d M%d O%d T%d",
        tonumber(entry.success)       or 0, tonumber(entry.failed)        or 0,
        tonumber(entry.immune)        or 0, tonumber(entry.missed)        or 0,
        tonumber(entry.overlapped)    or 0, tonumber(entry.totalAttempts) or 0)
end

-- ─── Spell API wrappers ───────────────────────────────────────────────────────
local function GetSpellNameSafe(spellID)
    if spellID then
        if C_Spell and C_Spell.GetSpellName then
            local n = C_Spell.GetSpellName(spellID); if IsNonEmptyString(n) then return n end
        end
        if GetSpellInfo then
            local n = GetSpellInfo(spellID); if IsNonEmptyString(n) then return n end
        end
    end
    return spellID and ("Spell ID " .. tostring(spellID)) or "Unknown Spell"
end

local function GetSpellTextureSafe(spellID)
    if spellID then
        if C_Spell and C_Spell.GetSpellTexture then
            local t = C_Spell.GetSpellTexture(spellID); if t then return t end
        end
        if GetSpellTexture then
            local t = GetSpellTexture(spellID); if t then return t end
        end
    end
    return 134400
end

local function GetTrackerNow()
    if GetTimePreciseSec then return GetTimePreciseSec() end
    if GetTime           then return GetTime()           end
    return 0
end

-- ─── Custom tracker ───────────────────────────────────────────────────────────
local function GetCustomBucket(viewKey)
    return customTracker[NormalizeViewKey(viewKey)]
end

local function RememberCustomSpell(viewKey, spellID)
    spellID = tonumber(spellID); if not spellID then return end
    if NormalizeViewKey(viewKey) == "interrupts" then INTERRUPT_SPELL_IDS[spellID] = true
    else DISPEL_SPELL_IDS[spellID] = true end
end

local function GetCustomViewForSpellID(spellID)
    spellID = tonumber(spellID); if not spellID then return nil end
    if INTERRUPT_SPELL_IDS[spellID] then return "interrupts" end
    if DISPEL_SPELL_IDS[spellID]   then return "dispels"    end
    return nil
end

local function ResetCustomTrackerBucket(viewKey)
    local b = GetCustomBucket(viewKey)
    if b then b.entries = {}; b.pending = {} end
end

local function AddNamedCount(counts, key)
    if type(counts) ~= "table" or not IsNonEmptyString(key) then return end
    counts[key] = (counts[key] or 0) + 1
end

local function EnsureCustomEntry(viewKey, spellID)
    local bucket = GetCustomBucket(viewKey); spellID = tonumber(spellID)
    if not bucket or not spellID then return nil end
    local entry = bucket.entries[spellID]
    if not entry then
        entry = {
            spellID = spellID, success = 0, failed = 0, immune = 0, missed = 0,
            overlapped = 0, totalAttempts = 0, detailCounts = {}, reasonCounts = {},
            lastDetailName = nil, lastReason = nil, lastDestName = nil, lastUpdated = 0,
        }
        bucket.entries[spellID] = entry
    end
    return entry
end

local function QueuePendingAttempt(viewKey, spellID, destGUID, destName)
    local bucket = GetCustomBucket(viewKey); spellID = tonumber(spellID)
    if not bucket or not spellID then return end
    local list = bucket.pending[spellID]
    if not list then list = {}; bucket.pending[spellID] = list end
    list[#list + 1] = { time = GetTrackerNow(), destGUID = destGUID, destName = destName }
end

local function ConsumePendingAttempt(viewKey, spellID)
    local bucket = GetCustomBucket(viewKey); spellID = tonumber(spellID)
    if not bucket or not spellID then return nil end
    local list = bucket.pending[spellID]
    if list and #list > 0 then
        local p = table.remove(list, 1)
        if #list == 0 then bucket.pending[spellID] = nil end
        return p
    end
    return nil
end

local function RecordCustomOutcome(viewKey, spellID, outcome, detailName, reasonText, destName)
    local entry = EnsureCustomEntry(viewKey, spellID)
    if not entry then return end
    if     outcome == "success"    then entry.success    = entry.success    + 1
    elseif outcome == "failed"     then entry.failed     = entry.failed     + 1
    elseif outcome == "immune"     then entry.immune     = entry.immune     + 1
    elseif outcome == "missed"     then entry.missed     = entry.missed     + 1
    elseif outcome == "overlapped" then entry.overlapped = entry.overlapped + 1
    else                                entry.failed     = entry.failed     + 1
    end
    entry.totalAttempts = entry.totalAttempts + 1
    entry.lastUpdated   = GetTrackerNow()
    if IsNonEmptyString(detailName) then entry.lastDetailName = detailName; AddNamedCount(entry.detailCounts, detailName) end
    if IsNonEmptyString(reasonText) then entry.lastReason = reasonText;     AddNamedCount(entry.reasonCounts, reasonText) end
    if IsNonEmptyString(destName)   then entry.lastDestName = destName end
end

local function ResolveCustomAttempt(viewKey, spellID, outcome, detailName, reasonText, destName)
    local pending = ConsumePendingAttempt(viewKey, spellID)
    if pending and not IsNonEmptyString(destName) then destName = pending.destName end
    RecordCustomOutcome(viewKey, spellID, outcome, detailName, reasonText, destName)
end

-- OPTIMISATION: original used table.remove(list,1) in a loop — O(n²).
-- Replace with a forward-compact pass (O(n)).
local function CleanupExpiredPendingView(viewKey, forceAll)
    local bucket = GetCustomBucket(viewKey); if not bucket then return false end
    local now = GetTrackerNow(); local changed = false
    for spellID, list in pairs(bucket.pending) do
        local write = 1
        for i = 1, #list do
            local p = list[i]
            if forceAll or (now - (p.time or now)) >= CUSTOM_ATTEMPT_TIMEOUT then
                RecordCustomOutcome(viewKey, spellID, "overlapped", nil, nil, p.destName)
                changed = true
            else
                list[write] = p; write = write + 1
            end
        end
        for i = write, #list do list[i] = nil end
        if write == 1 then bucket.pending[spellID] = nil end
    end
    return changed
end

local function CleanupExpiredPendingAll(forceAll)
    local changed = false
    for vk in pairs(CUSTOM_VIEW_KEYS) do
        if CleanupExpiredPendingView(vk, forceAll) then changed = true end
    end
    return changed
end

local function ClassifyMissOutcome(missType)
    return tostring(missType or "") == "IMMUNE" and "immune" or "missed"
end

local function IsPlayerOwnedCombatLogSource(sourceGUID, sourceFlags, playerGUID)
    if not sourceGUID or not playerGUID then return false end
    if sourceGUID == playerGUID then return true end

    local petGUID = UnitGUID("pet")
    if petGUID and sourceGUID == petGUID then return true end

    local band = bit and bit.band
    return band and COMBATLOG_OBJECT_AFFILIATION_MINE
        and band(sourceFlags or 0, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
end

local function GetSortedNamedCounts(counts, limit)
    local items = {}
    for name, count in pairs(counts or {}) do
        items[#items + 1] = { name = name, count = tonumber(count) or 0 }
    end
    table.sort(items, function(a, b)
        if a.count == b.count then return tostring(a.name) < tostring(b.name) end
        return a.count > b.count
    end)
    if limit then for i = limit + 1, #items do items[i] = nil end end
    return items
end

local function BuildCustomSpellList(viewKey)
    local bucket = GetCustomBucket(viewKey); if not bucket then return {}, 0 end
    CleanupExpiredPendingView(viewKey, false)
    local spellList = {}; local grandTotal = 0
    for _, entry in pairs(bucket.entries) do
        local total = tonumber(entry and entry.totalAttempts) or 0
        if total > 0 then grandTotal = grandTotal + total; spellList[#spellList + 1] = entry end
    end
    table.sort(spellList, function(a, b)
        local aS = tonumber(a and a.success) or 0; local bS = tonumber(b and b.success) or 0
        if aS == bS then
            local aT = tonumber(a and a.totalAttempts) or 0; local bT = tonumber(b and b.totalAttempts) or 0
            if aT == bT then return (tonumber(a.spellID) or 0) < (tonumber(b.spellID) or 0) end
            return aT > bT
        end
        return aS > bS
    end)
    return spellList, grandTotal
end

-- ─── Combat log ───────────────────────────────────────────────────────────────
local function HandleCustomCombatLogEvent()
    local playerGUID = UnitGUID("player")
    if not playerGUID or not CombatLogGetCurrentEventInfo then
        return CleanupExpiredPendingAll(false)
    end
    local changed = CleanupExpiredPendingAll(false)
    local _, subevent, _, sourceGUID, _, sourceFlags, _, destGUID, destName, _, _, spellID, _, _, arg15, arg16
        = CombatLogGetCurrentEventInfo()
    if not IsPlayerOwnedCombatLogSource(sourceGUID, sourceFlags, playerGUID) then return changed end
    spellID = tonumber(spellID); if not spellID then return changed end

    if subevent == "SPELL_INTERRUPT" then
        RememberCustomSpell("interrupts", spellID)
        ResolveCustomAttempt("interrupts", spellID, "success", arg16, nil, destName); return true
    end
    if subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN" then
        RememberCustomSpell("dispels", spellID)
        ResolveCustomAttempt("dispels", spellID, "success", arg16, nil, destName); return true
    end
    if subevent == "SPELL_DISPEL_FAILED" then
        RememberCustomSpell("dispels", spellID)
        ResolveCustomAttempt("dispels", spellID, "failed", arg16, nil, destName); return true
    end
    local viewKey = GetCustomViewForSpellID(spellID)
    if not viewKey then return changed end
    if subevent == "SPELL_CAST_SUCCESS" then
        QueuePendingAttempt(viewKey, spellID, destGUID, destName); return true
    elseif subevent == "SPELL_MISSED" then
        ResolveCustomAttempt(viewKey, spellID, ClassifyMissOutcome(arg15), nil, tostring(arg15 or ""), destName); return true
    elseif subevent == "SPELL_CAST_FAILED" then
        ResolveCustomAttempt(viewKey, spellID, "failed", nil, tostring(arg15 or ""), destName); return true
    end
    return changed
end

-- ─── Spell data helpers ───────────────────────────────────────────────────────
local function ReadCastCountFromTable(tbl)
    if type(tbl) ~= "table" then return nil end
    for _, key in ipairs(CAST_COUNT_KEYS) do
        local v = tonumber(tbl[key]); if v and v > 0 then return math.floor(v + 0.5) end
    end
    return nil
end

local function IterateSpellDetails(details, callback)
    if type(details) ~= "table" or type(callback) ~= "function" then return end
    if details.unitName ~= nil or details.isPet ~= nil
       or details.amount ~= nil or details.unitClassFilename ~= nil then
        callback(details); return
    end
    local seen = {}
    for _, detail in ipairs(details) do
        if type(detail) == "table" then seen[detail] = true; callback(detail) end
    end
    for _, detail in pairs(details) do
        if type(detail) == "table" and not seen[detail] then callback(detail) end
    end
end

local function GetPetNameForSpell(spellData)
    if type(spellData) ~= "table" then return nil end
    if IsNonEmptyString(spellData.creatureName) then return spellData.creatureName end
    local bestName, bestAmount = nil, -1
    IterateSpellDetails(spellData.combatSpellDetails, function(detail)
        if detail and detail.isPet and IsNonEmptyString(detail.unitName) then
            local amount = tonumber(detail.amount) or 0
            if amount > bestAmount then bestAmount = amount; bestName = detail.unitName end
        end
    end)
    return bestName
end

local function GetFirstStringField(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return nil end
    for _, key in ipairs(keys) do
        local v = tbl[key]; if IsNonEmptyString(v) then return v end
    end
    return nil
end

-- OPTIMISATION: key arrays were rebuilt on every call; promote to module-level upvalues.
local _summonKeys = {
    "summonSpellName","summonedBySpellName","summonerSpellName","ownerSpellName",
    "parentSpellName","sourceSpellName","spellGroupName","groupName","headerName",
}
local _baseNameKeys = {
    "parentSpellName","sourceSpellName","ownerSpellName","baseSpellName",
    "triggerSpellName","triggeredBySpellName","triggeringSpellName",
    "procSpellName","procFromSpellName","appliedBySpellName",
    "spellGroupName","groupName","headerName",
}
local _baseIDKeys = {
    "parentSpellID","sourceSpellID","ownerSpellID","baseSpellID",
    "triggerSpellID","triggeredBySpellID","triggeringSpellID",
    "procSpellID","procFromSpellID","appliedBySpellID",
}

local function GetSummonHeaderNameForSpell(spellData)
    if type(spellData) ~= "table" then return nil end
    local headerName = GetFirstStringField(spellData, _summonKeys)
    if IsNonEmptyString(headerName) then return headerName end
    IterateSpellDetails(spellData.combatSpellDetails, function(detail)
        if not headerName then headerName = GetFirstStringField(detail, _summonKeys) end
    end)
    return IsNonEmptyString(headerName) and headerName or nil
end

local function GetPetGroupInfoForSpell(spellData)
    local petName = GetPetNameForSpell(spellData); if not IsNonEmptyString(petName) then return nil end
    local summonHeader = GetSummonHeaderNameForSpell(spellData)
    if IsNonEmptyString(summonHeader) and summonHeader ~= petName then
        return { groupKey = "SUMMON::" .. summonHeader, headerText = summonHeader, petName = petName, groupType = "summon" }
    end
    return { groupKey = "PET::" .. petName, headerText = petName, petName = petName, groupType = "pet" }
end

local function GetSpellNameFromKeys(tbl, nameKeys, idKeys)
    if type(tbl) ~= "table" then return nil end
    local n = GetFirstStringField(tbl, nameKeys); if IsNonEmptyString(n) then return n end
    if type(idKeys) == "table" then
        for _, key in ipairs(idKeys) do
            local sid = tonumber(tbl[key])
            if sid then n = GetSpellNameSafe(sid); if IsNonEmptyString(n) then return n end end
        end
    end
    return nil
end

local function GetBaseSpellHeaderNameForSpell(spellData)
    if type(spellData) ~= "table" then return nil end
    local spellID = tonumber(spellData.spellID); local spellName = GetSpellNameSafe(spellID)
    local headerName = GetSpellNameFromKeys(spellData, _baseNameKeys, _baseIDKeys)
    if not IsNonEmptyString(headerName) then
        IterateSpellDetails(spellData.combatSpellDetails, function(detail)
            if not headerName then headerName = GetSpellNameFromKeys(detail, _baseNameKeys, _baseIDKeys) end
        end)
    end
    if IsNonEmptyString(headerName) and headerName ~= spellName then return headerName end
    return nil
end

local function BuildExplicitBaseSpellGroupNames(spellList)
    local groupNames = {}
    for _, spellData in ipairs(spellList or {}) do
        if not GetPetGroupInfoForSpell(spellData) then
            local h = GetBaseSpellHeaderNameForSpell(spellData)
            if IsNonEmptyString(h) then groupNames[h] = true end
        end
    end
    return groupNames
end

local function BuildDuplicateSpellNameCounts(spellList)
    local counts = {}
    for _, spellData in ipairs(spellList or {}) do
        if not GetPetGroupInfoForSpell(spellData) then
            local n = GetSpellNameSafe(tonumber(spellData and spellData.spellID))
            if IsNonEmptyString(n) then counts[n] = (counts[n] or 0) + 1 end
        end
    end
    return counts
end

local function GetGroupedDamageInfoForSpell(spellData, eg, dc)
    local pgi = GetPetGroupInfoForSpell(spellData); if pgi then return pgi end
    local spellID = tonumber(spellData and spellData.spellID)
    local displayName = GetSpellNameSafe(spellID)
    local baseHeader  = GetBaseSpellHeaderNameForSpell(spellData)
    if IsNonEmptyString(baseHeader) and baseHeader ~= displayName then
        return { groupKey = "SPELL::" .. baseHeader, headerText = baseHeader, petName = nil, groupType = "spell" }
    end
    if eg and eg[displayName] then
        return { groupKey = "SPELL::" .. displayName, headerText = displayName, petName = nil, groupType = "spell" }
    end
    if dc and (dc[displayName] or 0) > 1 then
        return { groupKey = "SPELLDUP::" .. displayName, headerText = displayName, petName = nil, groupType = "spell" }
    end
    return nil
end

-- ─── Cast tracking ─────────────────────────────────────────────────────────────
-- The stock C_DamageMeter spell data exposes no per-spell cast count, so count the
-- PLAYER's own successful casts (UNIT_SPELLCAST_SUCCEEDED) keyed by spellID and name.
-- Reset at the start of each combat so the counts line up with the current-combat
-- session the meter displays. Used as the fallback in GetSpellCastCount below.
local castsBySpellID = {}
local castsByName    = {}
local function ResetCastCounts()
    wipe(castsBySpellID); wipe(castsByName)
end
local function GetTrackedCastCount(spellID, spellName)
    spellID = tonumber(spellID)
    local n = spellID and castsBySpellID[spellID]
    if n and n > 0 then return n end
    if spellName and castsByName[spellName] then return castsByName[spellName] end
    return nil
end
local castTrackFrame = CreateFrame("Frame")
castTrackFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castTrackFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
castTrackFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        ResetCastCounts()
        return
    end
    spellID = tonumber(spellID)
    if not spellID then return end
    castsBySpellID[spellID] = (castsBySpellID[spellID] or 0) + 1
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
        or (GetSpellInfo and GetSpellInfo(spellID)) or nil
    if name then castsByName[name] = (castsByName[name] or 0) + 1 end
end)

local function GetSpellCastCount(spellData)
    if type(spellData) ~= "table" then return nil end
    local count = ReadCastCountFromTable(spellData); if count then return count end
    local bestCount = nil
    IterateSpellDetails(spellData.combatSpellDetails, function(detail)
        local dc = ReadCastCountFromTable(detail)
        if dc and (not bestCount or dc > bestCount) then bestCount = dc end
    end)
    if bestCount then return bestCount end
    -- Stock meter has no cast count -> fall back to our own per-player cast tracking.
    return GetTrackedCastCount(spellData.spellID, spellData.spellName or spellData.name or spellData.displayName)
end

-- ─── Stock meter ──────────────────────────────────────────────────────────────
local function SourceMatchesPlayer(source, playerGUID)
    if type(source) ~= "table" then return false end
    if source.isLocalPlayer then return true end
    return source.sourceGUID == playerGUID
        or source.guid == playerGUID
        or source.unitGUID == playerGUID
        or source.actorGUID == playerGUID
end

local function GetPlayerSourceFromAvailableSessions(meterType, playerGUID)
    if not (C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionFromID) then
        return nil
    end

    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" then return nil end

    for i = #sessions, 1, -1 do
        local session = sessions[i]
        local sid = session and session.sessionID
        if sid then
            local okInfo, info = pcall(C_DamageMeter.GetCombatSessionFromID, sid, meterType)
            if okInfo and info and type(info.combatSources) == "table" then
                for _, src in ipairs(info.combatSources) do
                    if SourceMatchesPlayer(src, playerGUID) then return src end
                end
            end
        end
    end

    return nil
end

-- How many past combat sessions are available to page through (capped at MAX_DETAILS_PAGES).
local function GetAvailableSessionCount()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return 0 end
    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" then return 0 end
    return math.min(#sessions, MAX_DETAILS_PAGES)
end

-- Resolve the player's combat source for a PAST session (paging back). offset 1 = the most
-- recent available session, 2 = the one before it, etc. Sessions come ordered oldest->newest.
local function GetPagedPlayerSource(meterType, offset, playerGUID)
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionFromID) then
        return nil
    end
    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" or #sessions == 0 then return nil end
    local index = #sessions - (offset - 1)
    if index < 1 or index > #sessions then return nil end
    local session = sessions[index]
    local sid = session and session.sessionID
    if not sid then return nil end
    local okInfo, info = pcall(C_DamageMeter.GetCombatSessionFromID, sid, meterType)
    if okInfo and info and type(info.combatSources) == "table" then
        for _, src in ipairs(info.combatSources) do
            if SourceMatchesPlayer(src, playerGUID) then return src end
        end
    end
    return nil
end

local function GetPlayerSource(meterType)
    if not C_DamageMeter then return nil, "C_DamageMeter is not available." end
    local playerGUID = UnitGUID("player"); if not playerGUID then return nil, "Player GUID is not ready." end

    -- Paged back into history: show that specific past session. If it has rolled off the
    -- available history, fall through to the live/current session below.
    if detailsPageOffset > 0 then
        local paged = GetPagedPlayerSource(meterType, detailsPageOffset, playerGUID)
        if paged then return paged end
    end

    if C_DamageMeter.GetCurrentCombatSessionSource then
        local ok, src = pcall(C_DamageMeter.GetCurrentCombatSessionSource, meterType, playerGUID)
        if ok and src then return src end
        ok, src = pcall(C_DamageMeter.GetCurrentCombatSessionSource, meterType, "player")
        if ok and src then return src end
    end
    if C_DamageMeter.GetCombatSessionSourceFromType then
        local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, SESSION_TYPE, meterType, playerGUID)
        if ok and src then return src end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, SESSION_TYPE, meterType, "player")
        if ok and src then return src end
    end
    local src = GetPlayerSourceFromAvailableSessions(meterType, playerGUID)
    if src then return src end
    return nil, "No stock details session source was returned."
end

local function GetSpellTotalAmount(spellData)
    if type(spellData) ~= "table" then return 0 end
    return tonumber(spellData.totalAmount) or tonumber(spellData.amount)
        or tonumber(spellData.count)       or tonumber(spellData.total) or 0
end

local function GetSpellRateAmount(spellData)
    if type(spellData) ~= "table" then return 0 end
    return tonumber(spellData.amountPerSecond) or tonumber(spellData.rate)
        or tonumber(spellData.perSecond)       or 0
end

local function BuildSpellList(source)
    local spellList, total = {}, 0
    if not source or not source.combatSpells then return spellList, total end
    for _, spellData in ipairs(source.combatSpells) do
        local amount = GetSpellTotalAmount(spellData)
        if amount > 0 then total = total + amount; spellList[#spellList + 1] = spellData end
    end
    table.sort(spellList, function(a, b)
        local aT = GetSpellTotalAmount(a); local bT = GetSpellTotalAmount(b)
        if aT == bT then return (tonumber(a.spellID) or 0) < (tonumber(b.spellID) or 0) end
        return aT > bT
    end)
    return spellList, total
end

local function BuildStockDisplayEntries(viewKey, source)
    viewKey = NormalizeViewKey(viewKey)
    local spellList, grandTotal = BuildSpellList(source)
    local visibleEntries = {}

    if not IsPetGroupingEnabled(viewKey) then
        for _, spellData in ipairs(spellList) do
            local spellID = tonumber(spellData.spellID)
            visibleEntries[#visibleEntries + 1] = {
                entryType = "spell", spellData = spellData, spellID = spellID,
                displayName    = GetSpellNameSafe(spellID),
                petName        = GetPetNameForSpell(spellData),
                totalAmount    = GetSpellTotalAmount(spellData),
                rateAmount     = GetSpellRateAmount(spellData),
                overkillAmount = tonumber(spellData.overkillAmount) or 0,
                castCount      = GetSpellCastCount(spellData),
                texture        = GetSpellTextureSafe(spellID),
            }
        end
        local topTotal = tonumber(visibleEntries[1] and visibleEntries[1].totalAmount) or 0
        return visibleEntries, grandTotal, topTotal, #visibleEntries
    end

    local eg  = BuildExplicitBaseSpellGroupNames(spellList)
    local dc  = BuildDuplicateSpellNameCounts(spellList)
    local topLevelEntries = {}
    local groupedBuckets  = {}

    for _, spellData in ipairs(spellList) do
        local spellID   = tonumber(spellData.spellID)
        local amount    = GetSpellTotalAmount(spellData)
        local rate      = GetSpellRateAmount(spellData)
        local overkill  = tonumber(spellData.overkillAmount) or 0
        local castCount = GetSpellCastCount(spellData)
        local gi        = GetGroupedDamageInfoForSpell(spellData, eg, dc)
        local petName   = gi and gi.petName    or nil
        local groupKey  = gi and gi.groupKey   or nil
        local headerText = gi and gi.headerText or nil
        local groupType = gi and gi.groupType  or nil
        local texture   = GetSpellTextureSafe(spellID)
        local displayName = GetSpellNameSafe(spellID)

        if gi then
            local bucket = groupedBuckets[groupKey]
            if not bucket then
                bucket = {
                    entryType = "petHeader", groupKey = groupKey, groupType = groupType,
                    headerText = headerText, petName = petName, displayName = headerText,
                    totalAmount = 0, rateAmount = 0, overkillAmount = 0, castCount = 0,
                    texture = texture, iconSpellID = spellID, iconAmount = -1, children = {},
                }
                groupedBuckets[groupKey] = bucket; topLevelEntries[#topLevelEntries + 1] = bucket
            end
            bucket.totalAmount    = bucket.totalAmount    + amount
            bucket.rateAmount     = bucket.rateAmount     + rate
            bucket.overkillAmount = bucket.overkillAmount + overkill
            bucket.castCount      = bucket.castCount      + (castCount or 0)
            if amount > (bucket.iconAmount or -1) then
                bucket.iconAmount = amount; bucket.texture = texture; bucket.iconSpellID = spellID
            end
            bucket.children[#bucket.children + 1] = {
                entryType = "petChild", spellData = spellData, spellID = spellID,
                displayName = displayName, petName = petName, groupKey = groupKey,
                groupType = groupType, parentPetName = headerText,
                totalAmount = amount, rateAmount = rate, overkillAmount = overkill,
                castCount = castCount, texture = texture,
            }
        else
            topLevelEntries[#topLevelEntries + 1] = {
                entryType = "spell", spellData = spellData, spellID = spellID,
                displayName = displayName, petName = nil, groupKey = nil, groupType = nil,
                totalAmount = amount, rateAmount = rate, overkillAmount = overkill,
                castCount = castCount, texture = texture,
            }
        end
    end

    local function SortByAmountThenName(a, b)
        local aT = tonumber(a and a.totalAmount) or 0; local bT = tonumber(b and b.totalAmount) or 0
        if aT == bT then return tostring(a and a.displayName or "") < tostring(b and b.displayName or "") end
        return aT > bT
    end

    for _, entry in ipairs(topLevelEntries) do
        if entry.entryType == "petHeader" then
            table.sort(entry.children, SortByAmountThenName)
            entry.childCount = #entry.children
            entry.isExpanded = IsPetGroupExpanded(viewKey, entry.groupKey or entry.petName)
        end
    end
    table.sort(topLevelEntries, SortByAmountThenName)

    for _, entry in ipairs(topLevelEntries) do
        visibleEntries[#visibleEntries + 1] = entry
        if entry.entryType == "petHeader" and entry.isExpanded then
            for _, child in ipairs(entry.children) do visibleEntries[#visibleEntries + 1] = child end
        end
    end

    local topTotal = tonumber(topLevelEntries[1] and topLevelEntries[1].totalAmount) or 0
    return visibleEntries, grandTotal, topTotal, #visibleEntries
end

-- ─── Expand-all helpers ───────────────────────────────────────────────────────
local function GetPetGroupKeysForSource(viewKey, source)
    local nv = NormalizeViewKey(viewKey); local groupKeys, seen = {}, {}
    if not IsPetGroupingEnabled(nv) or not source then return groupKeys end
    local spellList = BuildSpellList(source)
    local eg = BuildExplicitBaseSpellGroupNames(spellList)
    local dc = BuildDuplicateSpellNameCounts(spellList)
    for _, spellData in ipairs(spellList) do
        local gi = GetGroupedDamageInfoForSpell(spellData, eg, dc)
        local gk = gi and gi.groupKey or nil
        if IsNonEmptyString(gk) and not seen[gk] then seen[gk] = true; groupKeys[#groupKeys + 1] = gk end
    end
    return groupKeys
end

local function AreAllPetGroupsExpandedForSource(viewKey, source)
    local groupKeys = GetPetGroupKeysForSource(viewKey, source); local groupCount = #groupKeys
    if groupCount == 0 then return false, 0 end
    for _, gk in ipairs(groupKeys) do if not IsPetGroupExpanded(viewKey, gk) then return false, groupCount end end
    return true, groupCount
end

local function SetAllPetGroupsExpandedForSource(viewKey, source, expanded)
    local groupKeys = GetPetGroupKeysForSource(viewKey, source)
    for _, gk in ipairs(groupKeys) do SetPetGroupExpanded(viewKey, gk, expanded) end
    return #groupKeys
end

local function GetExpandAllPetGroupsStateForView(viewKey)
    local nv = NormalizeViewKey(viewKey)
    if IsCustomView(nv) or not IsPetGroupingEnabled(nv) then return false, false, 0 end
    if InCombatLockdown and InCombatLockdown()           then return false, false, 0 end
    local viewInfo = VIEW_DATA[nv] or VIEW_DATA[DEFAULT_VIEW]
    local source   = GetPlayerSource(viewInfo.meterType); if not source then return false, false, 0 end
    local allExpanded, groupCount = AreAllPetGroupsExpandedForSource(nv, source)
    return groupCount > 0, allExpanded, groupCount
end

-- ─── Opacity / appearance ─────────────────────────────────────────────────────
local function GetConfiguredOpacityAlpha()
    return Clamp(tonumber(MetersSavedVars and MetersSavedVars.opacity) or 100, 25, 100) / 100
end

local function ApplyDetailsOpacity()
    if frame then frame:SetAlpha(GetConfiguredOpacityAlpha()) end
end

local function ApplyRowFonts(row)
    if not row or not row.name or not row.value then return end
    local fp = GetSelectedFontPath()
    row.name:SetFont(fp, TEXT_SIZE, "")
    if row.percent then row.percent:SetFont(fp, TEXT_SIZE, "") end
    row.value:SetFont(fp, TEXT_SIZE, "")
end

local function ApplyTitleBarFont()
    if not frame then return end
    local fp = GetSelectedFontPath()
    if frame.titleText then frame.titleText:SetFont(fp, TITLE_TEXT_SIZE, "OUTLINE") end
    for _, button in pairs(tabButtons) do
        if button and button.text then button.text:SetFont(fp, TAB_TEXT_SIZE, "") end
    end
end

local function UpdateTitleBarText()  return end
local function UpdateTitleBarClassIcon() return end

local function UpdateTabVisuals()
    if not frame then return end
    for viewKey, button in pairs(tabButtons) do
        if button and button.bg then
            local isActive = (viewKey == currentView)
            button.bg:SetColorTexture(0, 0, 0, 0)
            button:SetBackdropColor(0, 0, 0, 0)
            button:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.85)
            if button.icon then
                button.icon:SetVertexColor(isActive and 1 or 0.82, isActive and 1 or 0.82, isActive and 1 or 0.82, 1)
            end
        end
    end
end

local function ApplyTitleBarClassColor()
    if not frame then return end
    local r, g, b = GetPlayerClassColor()
    if frame.titleBarBG   then frame.titleBarBG:SetColorTexture(r, g, b, 0)   end
    if frame.titleBarLine then frame.titleBarLine:SetColorTexture(r, g, b, 0) end
    UpdateTabVisuals()
end

-- ─── Layout ───────────────────────────────────────────────────────────────────
UpdateContentWidth = function()
    if not frame or not frame.scrollFrame or not frame.content then return end
    local width = math.max(1, frame.scrollFrame:GetWidth() or 1)
    frame.content:SetWidth(width)
    if frame.scrollFrame.UpdateScrollChildRect then frame.scrollFrame:UpdateScrollChildRect() end
end

local function CalculateWindowHeightForRows(rowCount)
    rowCount = math.max(0, tonumber(rowCount) or 0)
    local contentH   = rowCount > 0 and (rowCount * (ROW_HEIGHT + ROW_GAP)) or 1
    local reservedTop = EDGE_PADDING + TITLE_BAR_HEIGHT + TITLE_BAR_GAP
    return Clamp(contentH + reservedTop + EDGE_PADDING + BOTTOM_SAFE_PAD, MIN_HEIGHT, MAX_HEIGHT)
end

local function GetRowCountForView(viewKey)
    viewKey = NormalizeViewKey(viewKey)
    if IsCustomView(viewKey) then return #(BuildCustomSpellList(viewKey)) end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local viewInfo = VIEW_DATA[viewKey] or VIEW_DATA[DEFAULT_VIEW]
    local source   = GetPlayerSource(viewInfo.meterType); if not source then return 0 end
    local _, _, _, visibleCount = BuildStockDisplayEntries(viewKey, source)
    return visibleCount or 0
end

local function ApplyAutoWindowHeight(rowCount)
    if not frame or frame.isMinimized then return end
    local desiredH = CalculateWindowHeightForRows(rowCount)
    local left = frame:GetLeft(); local top = frame:GetTop()
    frame:SetHeight(desiredH)
    if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
end

UpdateScrollBounds = function()
    local contentH = frame.content:GetHeight() or 1
    local viewH    = frame.scrollFrame:GetHeight() or 1
    local maxScroll = math.max(0, contentH - viewH)
    frame.scrollFrame:SetVerticalScroll(Clamp(frame.scrollFrame:GetVerticalScroll() or 0, 0, maxScroll))
end

local function ScrollBy(delta)
    local contentH = frame.content:GetHeight() or 1
    local viewH    = frame.scrollFrame:GetHeight() or 1
    frame.scrollFrame:SetVerticalScroll(
        Clamp((frame.scrollFrame:GetVerticalScroll() or 0) + delta, 0, math.max(0, contentH - viewH)))
end

local function HideUnusedRows(fromIndex)
    for i = fromIndex, #rows do rows[i]:Hide() end
end

-- ─── Deferred refresh ─────────────────────────────────────────────────────────
MarkPendingPostCombatRefresh = function()
    if frame then frame.needsPostCombatRefresh = true end
end

TryPendingPostCombatRefresh = function(forceRefresh)
    if not frame or not RefreshDetails or not frame:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then MarkPendingPostCombatRefresh(); return end
    if forceRefresh or frame.needsPostCombatRefresh then
        frame.needsPostCombatRefresh = false; RefreshDetails(true)
    end
end

local function QueueDeferredRefresh()
    if not frame then return end
    if InCombatLockdown and InCombatLockdown() then MarkPendingPostCombatRefresh(); return end
    if frame.pendingDeferredRefresh then return end
    if not C_Timer or not C_Timer.After then TryPendingPostCombatRefresh(true); return end
    frame.pendingDeferredRefresh = true
    C_Timer.After(0.15, function()
        if not frame then return end
        frame.pendingDeferredRefresh = false; TryPendingPostCombatRefresh(true)
    end)
end

-- NOTE: the Details window is intentionally NOT registered with UISpecialFrames. ESC's
-- CloseSpecialWindows() hides EVERY shown special frame at once, so registering it made
-- pressing ESC to close the settings panel also close this window. Close it with its own
-- X button instead (standard meter-window behaviour).

-- ─── Frame ────────────────────────────────────────────────────────────────────
frame = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("HIGH"); frame:SetFrameLevel(30)
frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
frame:SetResizable(true); frame:SetToplevel(true)

frame.pendingDeferredRefresh  = false
frame.needsPostCombatRefresh  = false
frame.hiddenForCombat         = false
frame.isDragging              = false
frame.isMinimized             = false
frame.lastExpandedWidth       = DEFAULT_WIDTH
frame.lastExpandedHeight      = DEFAULT_HEIGHT
frame.dragOffsetX             = 0
frame.dragOffsetY             = 0
frame.suspendMinimizeSizeSync = false

if frame.SetResizeBounds then frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
else frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT); frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT) end

frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.50)
frame:SetBackdropBorderColor(0.70, 0.70, 0.70, 0.95)
frame:SetAlpha(GetConfiguredOpacityAlpha())
frame:Hide()

-- ─── Manual drag ─────────────────────────────────────────────────────────────
local function StartManualDrag()
    if not frame or frame.isDragging then return end
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition(); cx = cx / scale; cy = cy / scale
    frame.dragOffsetX = cx - (frame:GetLeft() or 0)
    frame.dragOffsetY = cy - (frame:GetBottom() or 0)
    frame.isDragging  = true
end

local function StopManualDrag()
    if frame then frame.isDragging = false; SaveDetailsWindowState() end
end

local function UpdateManualDrag()
    if not frame or not frame.isDragging then return end
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition(); cx = cx / scale; cy = cy / scale
    local newLeft   = Clamp(cx - frame.dragOffsetX, 0, math.max(0, (UIParent:GetWidth()  or 0) - (frame:GetWidth()  or 0)))
    local newBottom = Clamp(cy - frame.dragOffsetY, 0, math.max(0, (UIParent:GetHeight() or 0) - (frame:GetHeight() or 0)))
    frame:ClearAllPoints(); frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
end

local function StoreExpandedSize()
    if not frame or frame.isMinimized then return end
    local w = Clamp(math.floor((frame:GetWidth()  or DEFAULT_WIDTH)  + 0.5), MIN_WIDTH,  MAX_WIDTH)
    local h = Clamp(math.floor((frame:GetHeight() or DEFAULT_HEIGHT) + 0.5), MIN_HEIGHT, MAX_HEIGHT)
    if w > MINIMIZED_WIDTH or h > MINIMIZED_HEIGHT then
        frame.lastExpandedWidth = w; frame.lastExpandedHeight = h
    end
end

local function SetSizePreserveTopLeft(w, h)
    if not frame then return end
    local left = frame:GetLeft() or 0; local top = frame:GetTop() or 0
    frame:SetSize(w, h); frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function RefreshTimerIfNeeded()
    if _G.Timer_RefreshAll then _G.Timer_RefreshAll()
    elseif _G.Timer_RefreshVisibility then _G.Timer_RefreshVisibility() end
end

local function ExpandWindowForViewRows(viewKey, rowCount)
    if not frame or not frame.isMinimized then return false end
    rowCount = tonumber(rowCount) or 0; if rowCount <= 0 then return false end
    StopManualDrag(); frame.suspendMinimizeSizeSync = true; frame.isMinimized = false
    SetSizePreserveTopLeft(
        Clamp(tonumber(frame.lastExpandedWidth) or DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH),
        CalculateWindowHeightForRows(rowCount))
    UpdateWindowButtonVisuals(); UpdateContentWidth(); UpdateScrollBounds()
    SaveDetailsWindowState(); RefreshTimerIfNeeded()
    C_Timer.After(0, function()
        if frame then frame.suspendMinimizeSizeSync = false end
        RefreshTimerIfNeeded()
    end)
    return true
end

UpdateWindowButtonVisuals = function()
    if not frame then return end
    if frame.minimizeButton and frame.minimizeButton.icon then
        frame.minimizeButton.icon:SetTexture(frame.isMinimized and EXPAND_TEXTURE_PATH or MINIMIZE_TEXTURE_PATH)
    end
    if frame.expandAllButton and frame.expandAllButton.icon then
        local hasGroups, allExpanded = GetExpandAllPetGroupsStateForView(currentView)
        frame.expandAllButton.icon:SetTexture(EXPAND_ALL_TEXTURE_PATH)
        if hasGroups then
            frame.expandAllButton.icon:SetRotation(allExpanded and 0 or (-math.pi / 2))
            frame.expandAllButton.icon:SetVertexColor(1, 1, 1, 1)
        else
            frame.expandAllButton.icon:SetRotation(-math.pi / 2)
            frame.expandAllButton.icon:SetVertexColor(0.70, 0.70, 0.70, 0.70)
        end
    end
    if frame.resizeGrip then frame.resizeGrip:Show() end
end

ToggleMinimized = function()
    if not frame then return end
    StopManualDrag(); frame.suspendMinimizeSizeSync = true
    local wasMinimized = frame.isMinimized == true
    if frame.isMinimized then
        frame.isMinimized = false
        SetSizePreserveTopLeft(
            Clamp(tonumber(frame.lastExpandedWidth)  or DEFAULT_WIDTH,  MIN_WIDTH,  MAX_WIDTH),
            Clamp(tonumber(frame.lastExpandedHeight) or DEFAULT_HEIGHT, MIN_HEIGHT, MAX_HEIGHT))
    else
        StoreExpandedSize(); frame.isMinimized = true
        SetSizePreserveTopLeft(MINIMIZED_WIDTH, MINIMIZED_HEIGHT)
    end
    UpdateWindowButtonVisuals(); UpdateContentWidth(); UpdateScrollBounds()
    SaveDetailsWindowState()
    if wasMinimized and not frame.isMinimized and frame:IsShown() and RefreshDetails then RefreshDetails(true) end
    RefreshTimerIfNeeded()
    C_Timer.After(0, function()
        if frame then frame.suspendMinimizeSizeSync = false end
        RefreshTimerIfNeeded()
    end)
end

local function ToggleAllPetGroupsForCurrentView()
    local nv = NormalizeViewKey(currentView)
    if IsCustomView(nv) or not IsPetGroupingEnabled(nv) then return end
    if InCombatLockdown and InCombatLockdown() then MarkPendingPostCombatRefresh(); return end
    local viewInfo = VIEW_DATA[nv] or VIEW_DATA[DEFAULT_VIEW]
    local source   = GetPlayerSource(viewInfo.meterType); if not source then return end
    local allExpanded, groupCount = AreAllPetGroupsExpandedForSource(nv, source)
    if groupCount == 0 then return end
    SetAllPetGroupsExpandedForSource(nv, source, not allExpanded)
    GameTooltip_Hide()
    if frame and frame:IsShown() and RefreshDetails then RefreshDetails(true) else SaveDetailsWindowState() end
end

-- ─── Frame scripts ────────────────────────────────────────────────────────────
frame:SetScript("OnHide", function()
    GameTooltip_Hide(); frame.isDragging = false
    frame.pendingDeferredRefresh = false
    local suppressDetailsOptionSync = frame.suppressDetailsOptionSync == true
    frame.suppressDetailsOptionSync = false
    if not suppressDetailsOptionSync and IsDetailsEnabled() then
        local db = GetDetailsDB()
        db.wasShown = false
    end
    SaveDetailsWindowState()
end)

frame:SetScript("OnSizeChanged", function()
    local cw = frame:GetWidth() or DEFAULT_WIDTH; local ch = frame:GetHeight() or DEFAULT_HEIGHT
    local clampW = Clamp(cw, MIN_WIDTH, MAX_WIDTH); local clampH = Clamp(ch, MIN_HEIGHT, MAX_HEIGHT)
    if math.abs(cw - clampW) > 0.5 or math.abs(ch - clampH) > 0.5 then
        local left = frame:GetLeft() or 0; local top = frame:GetTop() or 0
        frame:ClearAllPoints(); frame:SetSize(clampW, clampH)
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        UpdateContentWidth(); UpdateScrollBounds(); UpdateWindowButtonVisuals(); return
    end
    if frame.suspendMinimizeSizeSync then
        UpdateContentWidth(); UpdateScrollBounds(); UpdateWindowButtonVisuals(); return
    end
    local isAtMin = math.abs((frame:GetWidth()  or 0) - MINIMIZED_WIDTH)  <= 0.5
               and  math.abs((frame:GetHeight() or 0) - MINIMIZED_HEIGHT) <= 0.5
    if isAtMin then
        if not frame.isMinimized then StoreExpandedSize() end
        frame.isMinimized = true
    else
        if frame.isMinimized then frame.isMinimized = false end
        StoreExpandedSize()
    end
    UpdateContentWidth(); UpdateScrollBounds(); UpdateWindowButtonVisuals(); SaveDetailsWindowState()
end)

-- ─── Title bar ────────────────────────────────────────────────────────────────
frame.titleBar = CreateFrame("Frame", nil, frame)
frame.titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  4, -4)
frame.titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
frame.titleBar:SetHeight(TITLE_BAR_HEIGHT); frame.titleBar:EnableMouse(true)
frame.titleBar:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then StartManualDrag() end end)
frame.titleBar:SetScript("OnMouseUp",   function(_, btn)
    if btn == "LeftButton" then StopManualDrag(); SaveDetailsWindowState() end
end)
frame.titleBar:SetScript("OnUpdate", UpdateManualDrag)

frame.titleBarBG   = frame.titleBar:CreateTexture(nil, "BACKGROUND"); frame.titleBarBG:SetAllPoints()
frame.titleBarLine = frame.titleBar:CreateTexture(nil, "BORDER")
frame.titleBarLine:SetPoint("BOTTOMLEFT",  frame.titleBar, "BOTTOMLEFT",  0, 0)
frame.titleBarLine:SetPoint("BOTTOMRIGHT", frame.titleBar, "BOTTOMRIGHT", 0, 0)
frame.titleBarLine:SetHeight(1)

-- OPTIMISATION: three nearly-identical close/minimize button definitions
-- collapsed into a single factory.
local function MakeIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:SetHighlightTexture(""); btn:SetPushedTexture(""); btn:SetNormalTexture("")
    btn.icon = btn:CreateTexture(nil, "ARTWORK"); btn.icon:SetAllPoints(btn)
    btn.icon:SetVertexColor(1, 1, 1, 0.90)
    btn:SetScript("OnEnter",    function(s) s.icon:SetVertexColor(1,    1,    1,    1)    end)
    btn:SetScript("OnLeave",    function(s) s.icon:SetVertexColor(1,    1,    1,    0.90) end)
    btn:SetScript("OnMouseDown",function(s) s.icon:SetVertexColor(0.85, 0.85, 0.85, 1)    end)
    btn:SetScript("OnMouseUp",  function(s) s.icon:SetVertexColor(1,    1,    1,    1)    end)
    return btn
end

frame.closeButton = MakeIconButton(frame.titleBar, TITLE_BUTTON_SIZE)
frame.closeButton:SetPoint("RIGHT", frame.titleBar, "RIGHT", -2, 0)
frame.closeButton.icon:SetTexture(CLOSE_TEXTURE_PATH)
frame.closeButton:SetScript("OnClick", function() Details_Hide(true) end)

frame.minimizeButton = MakeIconButton(frame.titleBar, TITLE_BUTTON_SIZE)
frame.minimizeButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -TITLE_BUTTON_GAP, 0)
frame.minimizeButton:SetScript("OnClick", function() ToggleMinimized() end)

-- ─── Combat-session paging (step through the last 10 sessions) ───────────────
local function UpdatePageButtonVisuals()
    if not frame then return end
    local maxOffset = GetAvailableSessionCount()
    if detailsPageOffset > maxOffset then detailsPageOffset = maxOffset end
    if detailsPageOffset < 0 then detailsPageOffset = 0 end
    -- IMPORTANT: do NOT call button:SetEnabled() here. Disabling a button while the mouse is
    -- over it fires OnLeave, and OnLeave re-runs this function -> SetEnabled -> OnLeave -> ...
    -- a C stack overflow. We only DIM the icon to signal "at the end"; StepDetailsPage clamps
    -- clicks so a press on a dimmed arrow is a harmless no-op.
    if frame.pageLeftButton and frame.pageLeftButton.icon then
        frame.pageLeftButton.icon:SetVertexColor(1, 1, 1, (detailsPageOffset < maxOffset) and 0.90 or 0.25)
    end
    if frame.pageRightButton and frame.pageRightButton.icon then
        frame.pageRightButton.icon:SetVertexColor(1, 1, 1, (detailsPageOffset > 0) and 0.90 or 0.25)
    end
end

local function StepDetailsPage(delta)
    local maxOffset = GetAvailableSessionCount()
    local newOffset = detailsPageOffset + delta
    if newOffset > maxOffset then newOffset = maxOffset end
    if newOffset < 0 then newOffset = 0 end
    if newOffset == detailsPageOffset then return end   -- already at the end; nothing to do
    detailsPageOffset = newOffset
    UpdatePageButtonVisuals()
    if RefreshDetails then RefreshDetails(true) end
end

-- Paging arrows sit BETWEEN the combat timer and the minimize ("-") button.
-- Left chevron = page BACK (older session); right chevron = page FORWARD (newer / live).
frame.pageRightButton = MakeIconButton(frame.titleBar, TITLE_BUTTON_SIZE)
frame.pageRightButton:SetPoint("RIGHT", frame.minimizeButton, "LEFT", -TITLE_BUTTON_GAP, 0)
frame.pageRightButton.icon:SetTexture(RIGHT_CHEVRON_TEXTURE_PATH)
frame.pageRightButton:SetScript("OnClick", function() StepDetailsPage(-1) end)
frame.pageRightButton:SetScript("OnEnter", function(s)
    s.icon:SetVertexColor(1, 1, 1, 1)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT"); GameTooltip:ClearLines()
    GameTooltip:AddLine("Newer combat → (live)", 1, 1, 1); GameTooltip:Show()
end)
frame.pageRightButton:SetScript("OnLeave", function() GameTooltip_Hide(); UpdatePageButtonVisuals() end)

frame.pageLeftButton = MakeIconButton(frame.titleBar, TITLE_BUTTON_SIZE)
frame.pageLeftButton:SetPoint("RIGHT", frame.pageRightButton, "LEFT", -TITLE_BUTTON_GAP, 0)
frame.pageLeftButton.icon:SetTexture(LEFT_CHEVRON_TEXTURE_PATH)
frame.pageLeftButton:SetScript("OnClick", function() StepDetailsPage(1) end)
frame.pageLeftButton:SetScript("OnEnter", function(s)
    s.icon:SetVertexColor(1, 1, 1, 1)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT"); GameTooltip:ClearLines()
    GameTooltip:AddLine("← Older combat", 1, 1, 1); GameTooltip:Show()
end)
frame.pageLeftButton:SetScript("OnLeave", function() GameTooltip_Hide(); UpdatePageButtonVisuals() end)

frame.timerAnchor = CreateFrame("Frame", nil, frame.titleBar)
frame.timerAnchor:SetSize(76, TITLE_BUTTON_SIZE)
frame.timerAnchor:SetPoint("RIGHT", frame.pageLeftButton, "LEFT", -2, 0)
frame.timerAnchor:EnableMouse(false)

UpdatePageButtonVisuals()

UpdateWindowButtonVisuals(); UpdateTitleBarClassIcon()

-- ─── Tabs ────────────────────────────────────────────────────────────────────
local function CreateTabButton(viewKey, texturePath)
    local button = CreateFrame("Button", nil, frame.titleBar, "BackdropTemplate")
    button.viewKey = viewKey; button:SetSize(TAB_WIDTH, TAB_HEIGHT)
    button:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=8, edgeSize=10, insets={left=2,right=2,top=2,bottom=2},
    })
    button:SetBackdropColor(0,0,0,0)
    button.bg = button:CreateTexture(nil,"BACKGROUND"); button.bg:SetAllPoints(); button.bg:SetColorTexture(0,0,0,0)
    button.icon = button:CreateTexture(nil,"ARTWORK"); button.icon:SetAllPoints(button)
    button.icon:SetTexture(texturePath); button.icon:SetTexCoord(0,1,0,1)

    button:SetScript("OnClick", function(self)
        local newView    = NormalizeViewKey(self.viewKey)
        local rowCount   = GetRowCountForView(newView)
        local wasMin     = frame and frame.isMinimized == true
        local now        = GetTrackerNow()
        local isDblClick = (not wasMin) and self.lastClickTime
                        and ((now - self.lastClickTime) <= TAB_DOUBLE_CLICK_THRESHOLD)
        self.lastClickTime = now
        currentView = newView; SaveDetailsWindowState(); UpdateTabVisuals()
        if not frame:IsShown() then return end
        if isDblClick then ToggleMinimized(); self.lastClickTime = nil; return end
        if rowCount > 0 then
            if frame.isMinimized then ExpandWindowForViewRows(newView, rowCount) end
            RefreshDetails(); return
        end
        RefreshDetails(true)
        if not frame.isMinimized then ToggleMinimized()
        else UpdateWindowButtonVisuals(); UpdateContentWidth(); UpdateScrollBounds(); SaveDetailsWindowState() end
    end)
    button:SetScript("OnEnter", function(s) s.bg:SetColorTexture(0,0,0,0); s:SetBackdropColor(0,0,0,0) end)
    button:SetScript("OnLeave", function(s) s.bg:SetColorTexture(0,0,0,0); s:SetBackdropColor(0,0,0,0); UpdateTabVisuals() end)
    tabButtons[viewKey] = button
    return button
end

frame.damageTab     = CreateTabButton("damage",     DAMAGE_TAB_TEXTURE_PATH)
frame.damageTab:SetPoint("LEFT", frame.titleBar, "LEFT", 4, -2)
frame.healingTab    = CreateTabButton("healing",    HEALING_TAB_TEXTURE_PATH)
frame.healingTab:SetPoint("LEFT", frame.damageTab, "RIGHT", TAB_GAP, 0)
frame.dispelsTab    = CreateTabButton("dispels",    DISPELS_TAB_TEXTURE_PATH)
frame.dispelsTab:SetPoint("LEFT", frame.healingTab, "RIGHT", TAB_GAP, 0)
frame.interruptsTab = CreateTabButton("interrupts", INTERRUPTS_TAB_TEXTURE_PATH)
frame.interruptsTab:SetPoint("LEFT", frame.dispelsTab, "RIGHT", TAB_GAP, 0)

frame.expandAllButton = CreateFrame("Button", nil, frame.titleBar)
frame.expandAllButton:SetSize(TAB_WIDTH, TAB_HEIGHT)
frame.expandAllButton:SetPoint("LEFT", frame.interruptsTab, "RIGHT", TAB_GAP, 0)
frame.expandAllButton.icon = frame.expandAllButton:CreateTexture(nil, "ARTWORK")
frame.expandAllButton.icon:SetAllPoints(frame.expandAllButton)
frame.expandAllButton.icon:SetTexture(EXPAND_ALL_TEXTURE_PATH)
frame.expandAllButton.icon:SetTexCoord(0, 1, 0, 1)
frame.expandAllButton:SetScript("OnClick", ToggleAllPetGroupsForCurrentView)
frame.expandAllButton:SetScript("OnEnter", function(self)
    local hasGroups, allExpanded = GetExpandAllPetGroupsStateForView(currentView)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT"); GameTooltip:ClearLines()
    GameTooltip:AddLine("Expand / Collapse All", 1, 1, 1)
    if hasGroups then
        GameTooltip:AddLine(allExpanded and "Click to collapse all grouped rows."
                                        or "Click to expand all grouped rows.", 0.80, 0.80, 0.80)
        self.icon:SetVertexColor(1, 1, 1, 1)
    else
        GameTooltip:AddLine("No grouped rows are available in this view.", 0.80, 0.80, 0.80)
        self.icon:SetVertexColor(0.75, 0.75, 0.75, 0.70)
    end
    GameTooltip:Show()
end)
frame.expandAllButton:SetScript("OnLeave", function() GameTooltip_Hide(); UpdateWindowButtonVisuals() end)
frame.expandAllButton:SetScript("OnMouseDown", function(self)
    if select(1, GetExpandAllPetGroupsStateForView(currentView)) then self.icon:SetVertexColor(0.90,0.90,0.90,1) end
end)
frame.expandAllButton:SetScript("OnMouseUp", UpdateWindowButtonVisuals)
UpdateWindowButtonVisuals()

-- ─── Scroll frame ─────────────────────────────────────────────────────────────
frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame)
frame.scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",
    EDGE_PADDING, -(EDGE_PADDING + TITLE_BAR_HEIGHT + TITLE_BAR_GAP))
frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
    -(EDGE_PADDING + RIGHT_SAFE_PAD), EDGE_PADDING + BOTTOM_SAFE_PAD)
frame.content = CreateFrame("Frame", nil, frame.scrollFrame)
frame.content:SetSize(1, 1); frame.scrollFrame:SetScrollChild(frame.content)

frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
frame.emptyText:SetPoint("CENTER", frame.scrollFrame, "CENTER", 0, 0)
frame.emptyText:SetWidth(320); frame.emptyText:SetJustifyH("CENTER")
frame.emptyText:SetJustifyV("MIDDLE"); frame.emptyText:SetText("")

frame.resizeGrip = CreateFrame("Button", nil, frame)
frame.resizeGrip:SetSize(14, 14)
frame.resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
frame.resizeGrip:SetScript("OnMouseDown", function() StopManualDrag(); frame:StartSizing("BOTTOMRIGHT") end)
frame.resizeGrip:SetScript("OnMouseUp",   function() frame:StopMovingOrSizing(); StoreExpandedSize(); SaveDetailsWindowState() end)

frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", function(_, delta) ScrollBy(-delta * 32) end)

-- ─── Row layout helper ────────────────────────────────────────────────────────
local function ApplyRowIndent(row, indent)
    indent = tonumber(indent) or 0
    local expandIconWidth = 10
    row.iconBG:ClearAllPoints(); row.iconBG:SetPoint("LEFT", row, "LEFT", indent, 0)
    row.icon:ClearAllPoints();   row.icon:SetPoint("CENTER", row.iconBG, "CENTER", 0, 0)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT",  row.iconBG, "BOTTOMRIGHT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.value:ClearAllPoints(); row.value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    if row.percent then row.percent:ClearAllPoints(); row.percent:SetPoint("RIGHT", row.value, "LEFT", -COLUMN_GAP, 0) end
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    if row.isPetHeader then
        local reservedRight = VALUE_WIDTH + 4 + expandIconWidth
            + (row.percent and (PERCENT_WIDTH + COLUMN_GAP) or 12)
        local avail = math.max(1, (row:GetWidth() or 1) - indent - ICON_SIZE - 4 - reservedRight)
        local textW = (row.name.GetStringWidth and row.name:GetStringWidth()) or avail
        row.name:SetWidth(math.max(1, math.min(textW, avail)))
        row.expandIcon:ClearAllPoints(); row.expandIcon:SetPoint("LEFT", row.name, "RIGHT", 0, 0)
    else
        row.name:SetWidth(0)
        if row.percent then row.name:SetPoint("RIGHT", row.percent, "LEFT", -COLUMN_GAP, 0)
        else                row.name:SetPoint("RIGHT", row.value,   "LEFT", -12,         0) end
        row.expandIcon:ClearAllPoints(); row.expandIcon:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    end
end

-- ─── Row factory ─────────────────────────────────────────────────────────────
local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(ROW_HEIGHT)
    local yOff = -((index-1)*(ROW_HEIGHT+ROW_GAP))
    row:SetPoint("TOPLEFT",  frame.content, "TOPLEFT",  0, yOff)
    row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, yOff)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.bg = row:CreateTexture(nil,"BACKGROUND"); row.bg:SetAllPoints(); row.bg:SetColorTexture(0,0,0,0)
    row.iconBG = row:CreateTexture(nil,"BORDER"); row.iconBG:SetSize(ICON_SIZE,ICON_SIZE)
    row.iconBG:SetPoint("LEFT",row,"LEFT",0,0); row.iconBG:SetColorTexture(0,0,0,0.95)
    row.icon = row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(ICON_SIZE,ICON_SIZE)
    row.icon:SetPoint("CENTER",row.iconBG,"CENTER",0,0)

    local classR, classG, classB = GetPlayerClassColor()
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetFrameLevel(row:GetFrameLevel())
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetMinMaxValues(0,1); row.bar:SetValue(0)
    row.bar:SetStatusBarColor(classR,classG,classB,0.95); row.bar:SetHeight(BAR_HEIGHT)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT",  row.iconBG, "BOTTOMRIGHT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.barBG = row.bar:CreateTexture(nil,"BACKGROUND"); row.barBG:SetAllPoints()
    row.barBG:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.barBG:SetVertexColor(classR*0.25,classG*0.25,classB*0.25,0.45)

    row.separator = row:CreateTexture(nil,"OVERLAY")
    row.separator:SetPoint("BOTTOMLEFT",row,"BOTTOMLEFT",0,0)
    row.separator:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
    row.separator:SetHeight(1); row.separator:SetColorTexture(1,1,1,0.08)

    row.expandIcon = row:CreateTexture(nil,"OVERLAY"); row.expandIcon:SetSize(10,10)
    row.expandIcon:SetTexture(DROPDOWN_TEXTURE_PATH); row.expandIcon:Hide()

    -- OPTIMISATION: three font-string definitions share a local factory.
    local function MakeLabel()
        local fs = row:CreateFontString(nil,"OVERLAY")
        fs:SetJustifyV("MIDDLE"); fs:SetWordWrap(false)
        fs:SetTextColor(1,1,1,1); fs:SetShadowOffset(1,-1); fs:SetShadowColor(0,0,0,1)
        return fs
    end
    row.name    = MakeLabel(); row.name:SetJustifyH("LEFT"); row.name:SetPoint("LEFT",row.icon,"RIGHT",4,0)
    row.percent = MakeLabel(); row.percent:SetWidth(PERCENT_WIDTH); row.percent:SetJustifyH("RIGHT")
    row.value   = MakeLabel(); row.value:SetWidth(VALUE_WIDTH);     row.value:SetJustifyH("RIGHT")

    ApplyRowFonts(row)

    function row:UpdateBar(pf)
        pf = Clamp(pf or 0, 0, 1); self.percentFraction = pf; self.bar:SetValue(pf)
    end

    row:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if self.isPetHeader and IsNonEmptyString(self.groupKey or self.petName) then
            local stateKey = self.groupKey or self.petName
            SetPetGroupExpanded(self.viewKey, stateKey, not IsPetGroupExpanded(self.viewKey, stateKey))
            GameTooltip_Hide()
            if frame and frame:IsShown() and RefreshDetails then RefreshDetails(true) end
        end
    end)

    row:SetScript("OnEnter", function(self)
        local viewInfo = VIEW_DATA[self.viewKey] or GetCurrentViewInfo()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        if self.isPetHeader and IsNonEmptyString(self.headerText or self.petName) then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.headerText or self.petName, 1,1,1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Included Rows", tostring(tonumber(self.childCount) or 0), 1,1,1,1,1,1)
            if self.petName and self.groupType == "summon" then
                GameTooltip:AddDoubleLine("Summoned Pet", self.petName, 1,1,1,1,1,1)
            elseif self.groupType == "spell" then
                GameTooltip:AddDoubleLine("Base Spell", self.headerText or "", 1,1,1,1,1,1)
            end
            if self.castCount and self.castCount > 0 then
                GameTooltip:AddDoubleLine("Casts", tostring(self.castCount), 1,1,1,1,1,1)
            end
            if viewInfo.showRate then
                GameTooltip:AddDoubleLine(viewInfo.rateLabel, FormatMainNumber(self.rateAmount),  1,1,1,1,1,1)
                GameTooltip:AddDoubleLine("Total",            FormatMainNumber(self.totalAmount), 1,1,1,1,1,1)
            else
                GameTooltip:AddDoubleLine(viewInfo.rateLabel, FormatMainNumber(self.totalAmount), 1,1,1,1,1,1)
            end
            GameTooltip:AddDoubleLine("Percent", FormatPercent(self.percentValue), 1,1,1,1,1,1)
            GameTooltip:AddLine(self.isExpanded and "Click to collapse." or "Click to expand.", 0.70,0.70,0.70)
            GameTooltip:Show(); return
        end

        if not self.spellID then return end
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID)
        else GameTooltip:SetText(GetSpellNameSafe(self.spellID)) end
        GameTooltip:AddLine(" ")

        if self.isCustomTracker and self.customEntry then
            local e = self.customEntry
            GameTooltip:AddDoubleLine("Success",        tostring(tonumber(e.success)       or 0), 1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Failed",         tostring(tonumber(e.failed)        or 0), 1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Immune",         tostring(tonumber(e.immune)        or 0), 1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Missed",         tostring(tonumber(e.missed)        or 0), 1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Overlapped",     tostring(tonumber(e.overlapped)    or 0), 1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Total Attempts", tostring(tonumber(e.totalAttempts) or 0), 1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Percent",        FormatPercent(self.percentValue),          1,1,1,1,1,1)
            if IsNonEmptyString(e.lastDestName) then
                GameTooltip:AddDoubleLine("Last Target", e.lastDestName, 1,1,1,1,1,1)
            end
            local dLabel = (NormalizeViewKey(self.viewKey) == "interrupts") and "Interrupted" or "Removed"
            for _, item in ipairs(GetSortedNamedCounts(e.detailCounts, 3)) do
                GameTooltip:AddDoubleLine(dLabel, item.name.." x"..tostring(item.count), 1,1,1,1,1,1)
            end
            for _, item in ipairs(GetSortedNamedCounts(e.reasonCounts, 3)) do
                GameTooltip:AddDoubleLine("Fail Reason", item.name.." x"..tostring(item.count), 1,1,1,1,1,1)
            end
        else
            if self.petName and self.petName ~= "" then
                GameTooltip:AddDoubleLine("Pet", self.petName, 1,1,1,1,1,1)
            elseif self.parentPetName and self.groupType == "spell" then
                GameTooltip:AddDoubleLine("Base Spell", self.parentPetName, 1,1,1,1,1,1)
            end
            if self.castCount and self.castCount > 0 then
                GameTooltip:AddDoubleLine("Casts", tostring(self.castCount), 1,1,1,1,1,1)
            end
            if viewInfo.showRate then
                GameTooltip:AddDoubleLine(viewInfo.rateLabel, FormatMainNumber(self.rateAmount),  1,1,1,1,1,1)
                GameTooltip:AddDoubleLine("Total",            FormatMainNumber(self.totalAmount), 1,1,1,1,1,1)
            else
                GameTooltip:AddDoubleLine(viewInfo.rateLabel, FormatMainNumber(self.totalAmount), 1,1,1,1,1,1)
            end
            GameTooltip:AddDoubleLine("Percent", FormatPercent(self.percentValue), 1,1,1,1,1,1)
            if viewInfo.showOverkill and (tonumber(self.overkillAmount) or 0) > 0 then
                GameTooltip:AddDoubleLine("Overkill", FormatMainNumber(self.overkillAmount), 1,1,1,1,1,1)
            end
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[index] = row
    return row
end

local function GetRow(index)
    return rows[index] or CreateRow(index)
end

-- ─── Rendering ────────────────────────────────────────────────────────────────
local function RenderCustomDetails(viewInfo)
    local spellList, grandTotal = BuildCustomSpellList(currentView)
    local topTotal = tonumber(spellList[1] and spellList[1].totalAttempts) or 0
    if #spellList == 0 then
        HideUnusedRows(1); UpdateContentWidth(); frame.content:SetHeight(1)
        ApplyAutoWindowHeight(0); UpdateContentWidth()
        frame.emptyText:SetText(viewInfo.emptyText); UpdateScrollBounds(); return
    end
    frame.emptyText:SetText("")
    for index, entry in ipairs(spellList) do
        local row = GetRow(index)
        local total = tonumber(entry.totalAttempts) or 0
        local pct   = (grandTotal > 0) and ((total / grandTotal) * 100) or 0
        local frac  = (topTotal   > 0) and (total / topTotal)           or 0
        row.isCustomTracker = true;  row.customEntry   = entry
        row.viewKey = currentView;   row.spellID       = tonumber(entry.spellID)
        row.totalAmount = total;     row.rateAmount    = tonumber(entry.success) or 0
        row.percentValue = pct;      row.overkillAmount = 0
        row.petName = nil;           row.groupKey = nil;       row.groupType = nil
        row.headerText = nil;        row.castCount = nil;      row.isPetHeader = false
        row.isExpanded = false;      row.childCount = nil;     row.parentPetName = nil
        row.icon:SetTexture(GetSpellTextureSafe(entry.spellID))
        row.expandIcon:Hide(); row.expandIcon:SetRotation(0)
        row.name:SetText(GetSpellNameSafe(entry.spellID))
        if row.percent then row.percent:SetText(FormatPercent(pct)) end
        row.value:SetText(FormatCustomRowValue(entry))
        row.bg:SetColorTexture(0,0,0,0)
        ApplyRowIndent(row, 0); ApplyRowFonts(row); row:Show(); row:UpdateBar(frac)
    end
    HideUnusedRows(#spellList + 1)
    UpdateContentWidth(); frame.content:SetHeight(math.max(1, #spellList * (ROW_HEIGHT + ROW_GAP)))
    ApplyAutoWindowHeight(#spellList); UpdateContentWidth(); UpdateScrollBounds()
end

local function RenderStockDetails(viewInfo, skipDeferred)
    if InCombatLockdown() then
        MarkPendingPostCombatRefresh(); HideUnusedRows(1); UpdateContentWidth()
        frame.content:SetHeight(1); ApplyAutoWindowHeight(0); UpdateContentWidth()
        frame.emptyText:SetText(STOCK_COMBAT_TEXT); UpdateScrollBounds()
        if not skipDeferred then QueueDeferredRefresh() end; return
    end
    local source, errorText = GetPlayerSource(viewInfo.meterType)
    if not source then
        HideUnusedRows(1); UpdateContentWidth(); frame.content:SetHeight(1)
        ApplyAutoWindowHeight(0); UpdateContentWidth()
        frame.emptyText:SetText(errorText or viewInfo.emptyText); UpdateScrollBounds()
        if not skipDeferred then QueueDeferredRefresh() end; return
    end
    local displayEntries, grandTotal, topTotal, visibleCount = BuildStockDisplayEntries(currentView, source)
    if visibleCount == 0 then
        HideUnusedRows(1); UpdateContentWidth(); frame.content:SetHeight(1)
        ApplyAutoWindowHeight(0); UpdateContentWidth()
        frame.emptyText:SetText(viewInfo.emptyText); UpdateScrollBounds()
        if not skipDeferred then QueueDeferredRefresh() end; return
    end
    frame.emptyText:SetText(""); frame.needsPostCombatRefresh = false

    for index, entry in ipairs(displayEntries) do
        local row = GetRow(index)
        local totalAmount  = tonumber(entry.totalAmount)  or 0
        local rateAmount   = tonumber(entry.rateAmount)   or 0
        local percentValue = (grandTotal > 0) and ((totalAmount / grandTotal) * 100) or 0
        local percentFrac  = (topTotal   > 0) and (totalAmount  / topTotal)          or 0
        local displayName  = entry.displayName or ""
        local indent       = 0

        row.isCustomTracker = false; row.customEntry   = nil
        row.viewKey = currentView;   row.totalAmount   = totalAmount
        row.rateAmount = rateAmount; row.percentValue  = percentValue
        row.overkillAmount = tonumber(entry.overkillAmount) or 0
        row.petName = entry.petName; row.groupKey      = entry.groupKey
        row.groupType = entry.groupType
        row.headerText = entry.headerText or entry.displayName or entry.petName
        row.castCount = entry.castCount
        row.isPetHeader = (entry.entryType == "petHeader")
        row.isExpanded  = entry.isExpanded == true
        row.childCount  = entry.childCount
        row.parentPetName = entry.parentPetName

        if entry.entryType == "petHeader" then
            row.spellID = nil
            row.icon:SetTexture(entry.texture or 134400)
            row.expandIcon:SetTexture(DROPDOWN_TEXTURE_PATH)
            row.expandIcon:SetRotation(row.isExpanded and 0 or (-math.pi / 2))
            row.expandIcon:Show()
            row.name:SetText(tostring(entry.headerText or entry.displayName or entry.petName or "Pet"))
            if row.percent then row.percent:SetText(FormatPercent(percentValue)) end
            row.value:SetText(viewInfo.showRate
                and FormatMainNumber(rateAmount).." ("..FormatParenTotal(totalAmount)..")"
                or  FormatMainNumber(totalAmount))
            row.bg:SetColorTexture(1,1,1,0.035)
        else
            row.spellID = tonumber(entry.spellID)
            row.icon:SetTexture(entry.texture or GetSpellTextureSafe(row.spellID))
            row.expandIcon:Hide(); row.expandIcon:SetRotation(0)
            if entry.entryType == "petChild" then
                indent = 14
            elseif entry.petName and entry.petName ~= "" and not IsPetGroupingEnabled(currentView) then
                displayName = displayName .. " (" .. entry.petName .. ")"
            end
            row.name:SetText(displayName)
            if row.percent then row.percent:SetText(FormatPercent(percentValue)) end
            row.value:SetText(viewInfo.showRate
                and FormatMainNumber(rateAmount).." ("..FormatParenTotal(totalAmount)..")"
                or  FormatMainNumber(totalAmount))
            row.bg:SetColorTexture(0,0,0,0)
        end
        ApplyRowIndent(row, indent); ApplyRowFonts(row); row:Show(); row:UpdateBar(percentFrac)
    end

    HideUnusedRows(visibleCount + 1)
    UpdateContentWidth(); frame.content:SetHeight(math.max(1, visibleCount * (ROW_HEIGHT + ROW_GAP)))
    ApplyAutoWindowHeight(visibleCount); UpdateContentWidth(); UpdateScrollBounds()
    if not skipDeferred then QueueDeferredRefresh() end
end

-- OPTIMISATION: invalidate the font path cache at the start of each pass so
-- ApplyRowFonts uses a single shared string rather than re-fetching per row.
RefreshDetails = function(skipDeferred)
    if not frame:IsShown() then return end
    InvalidateFontCache()
    local viewInfo = GetCurrentViewInfo()
    ApplyDetailsOpacity(); ApplyTitleBarFont()
    UpdateTitleBarText(); ApplyTitleBarClassColor()
    frame.emptyText:SetText(""); UpdateContentWidth()
    if IsCustomView(currentView) then
        RenderCustomDetails(viewInfo); UpdateWindowButtonVisuals(); return
    end
    RenderStockDetails(viewInfo, skipDeferred)
    UpdateWindowButtonVisuals()
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function Details_SetView(viewKey)
    currentView = NormalizeViewKey(viewKey)
    SaveDetailsWindowState(); UpdateTabVisuals()
    if frame:IsShown() then RefreshDetails() end
end

function Details_Show(viewKey)
    if not IsDetailsEnabled() then return end
    local db = GetDetailsDB()
    currentView = viewKey and NormalizeViewKey(viewKey) or NormalizeViewKey(db.viewKey)
    if ShouldHideDetailsInCombat() and UnitAffectingCombat and UnitAffectingCombat("player") then
        db.wasShown = true
        db.hideInCombat = true
        frame.hiddenForCombat = true
        frame.needsPostCombatRefresh = true
        SaveDetailsWindowState()
        return
    end
    ApplySavedWindowState(true); db.wasShown = true
    ApplyDetailsOpacity(); ApplyTitleBarFont(); UpdateTitleBarText()
    UpdateTitleBarClassIcon(); ApplyTitleBarClassColor()
    UpdateTabVisuals(); UpdateWindowButtonVisuals()
    frame.hiddenForCombat = false
    frame:Show(); frame:Raise()
    frame.needsPostCombatRefresh = true
    SaveDetailsWindowState(); RefreshDetails()
end

function Details_Hide(syncDetailsOption)
    local db = GetDetailsDB(); db.wasShown = false; SaveDetailsWindowState()
    if syncDetailsOption then SyncDetailsOptionForHiddenWindow() end
    frame.hiddenForCombat = false
    frame.needsPostCombatRefresh = false
    if frame:IsShown() then
        frame.suppressDetailsOptionSync = syncDetailsOption ~= true
        frame:Hide()
    else
        frame.suppressDetailsOptionSync = false
    end
end

function Details_Refresh()       RefreshDetails()        end
function Details_ApplyOpacity()  ApplyDetailsOpacity() end
function Details_ToggleMinimized() ToggleMinimized()      end

function Details_ApplyCombatVisibility()
    if not frame then return end
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    local db = GetDetailsDB()
    db.hideInCombat = ShouldHideDetailsInCombat()

    if inCombat then
        if ShouldHideDetailsInCombat() and IsDetailsEnabled() and frame:IsShown() then
            db.wasShown = true
            frame.hiddenForCombat = true
            frame.needsPostCombatRefresh = true
            frame.suppressDetailsOptionSync = true
            frame:Hide()
        elseif frame.hiddenForCombat and not ShouldHideDetailsInCombat() then
            frame.hiddenForCombat = false
            if IsDetailsEnabled() then
                Details_Show()
            end
        end
        return
    end

    if frame.hiddenForCombat then
        frame.hiddenForCombat = false
        if IsDetailsEnabled() then
            Details_Show()
        end
    end
end

-- ─── Events ───────────────────────────────────────────────────────────────────
local refreshEvents = CreateFrame("Frame")
refreshEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
refreshEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
refreshEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
refreshEvents:RegisterEvent("PLAYER_CAMPING")
refreshEvents:RegisterEvent("PLAYER_LOGOUT")
refreshEvents:SetScript("OnEvent", function(_, event)
    if not frame then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Details_ApplyCombatVisibility()
        TryPendingPostCombatRefresh(true)
        -- Pop the Details window up when the fight ends so the results are visible. Deferred
        -- a tick so the combat flag has fully cleared (UnitAffectingCombat can linger on this
        -- event, which would make Details_Show bail when "Hide in Combat" is set). Only when
        -- the Details feature is enabled; a window the user closed (which clears showDetails)
        -- stays closed.
        local function popUp()
            if frame and IsDetailsEnabled() and not frame:IsShown() and Details_Show then
                Details_Show()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, popUp) else popUp() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Details_ApplyCombatVisibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        _detailsDB = nil   -- force re-init of DB cache
        ApplyInitialWindowState()
        Details_ApplyCombatVisibility()
        if frame:IsShown() and not frame.isMinimized then QueueDeferredRefresh() end
    elseif event == "PLAYER_CAMPING" then
        if frame:IsShown() then Details_Hide()
        else local db = GetDetailsDB(); db.wasShown = false; SaveDetailsWindowState() end
    elseif event == "PLAYER_LOGOUT" then
        SaveDetailsWindowState()
    end
end)

if not USE_STOCK_SPECIAL_VIEWS then
    -- Midnight (12.0+) blocks addon registration for CLEU, so only keep the
    -- legacy custom tracker on older clients where the event is still allowed.
    local combatLogFrame = CreateFrame("Frame")
    combatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    combatLogFrame:SetScript("OnEvent", function()
        local changed = HandleCustomCombatLogEvent()
        if changed and frame and frame:IsShown() and IsCustomView(currentView) then
            QueueDeferredRefresh()
        end
    end)
end

-- ─── Startup ─────────────────────────────────────────────────────────────────
InitDetailsDB()
ApplyInitialWindowState()
ApplyDetailsOpacity()
ApplyTitleBarFont()
UpdateTitleBarText()
UpdateTitleBarClassIcon()
ApplyTitleBarClassColor()
UpdateTabVisuals()

if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
        if not frame then return end
        ApplyInitialWindowState()
    end)
end

