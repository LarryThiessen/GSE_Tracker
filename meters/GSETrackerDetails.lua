-- Modules\MyMeters\GSETrackerDetails.lua (Optimized)

local addonName, ns = ...
local uiShared = (ns and ns._ui) or {}
local WINDOW_NAME        = "GSETrackerDetailsFrame"
local STOCK_COMBAT_TEXT  = "-- COMBAT --."
local SESSION_TYPE       = (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current) or 1

local VIEW_DATA = {
    damage = {
        key = "damage", label = "Damage Done", rateLabel = "DPS",
        emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone) or 0,
        showOverkill = true, showRate = true,
    },
    healing = {
        key = "healing", label = "Healing Done", rateLabel = "HPS",
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
    -- Extra meter-type views, surfaced through the category dropdowns (match the native meter dropdown).
    dps = {
        key = "dps", label = "DPS", rateLabel = "DPS", emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.Dps) or 1,
        showOverkill = true, showRate = true,
    },
    damagetaken = {
        key = "damagetaken", label = "Damage Taken", rateLabel = "DTPS", emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken) or 7,
        showOverkill = false, showRate = false,
    },
    avoidable = {
        key = "avoidable", label = "Avoidable Damage Taken", rateLabel = "Avoidable", emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.AvoidableDamageTaken) or 8,
        showOverkill = false, showRate = false,
    },
    enemy = {
        key = "enemy", label = "Enemy Damage Taken", rateLabel = "Damage", emptyText = "-- No Targets --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.EnemyDamageTaken) or 10,
        showOverkill = false, showRate = false, isEnemy = true,
    },
    hps = {
        key = "hps", label = "HPS", rateLabel = "HPS", emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.Hps) or 3,
        showOverkill = false, showRate = true,
    },
    deaths = {
        key = "deaths", label = "Deaths", rateLabel = "Deaths", emptyText = "-- No Data Found --",
        meterType = (Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths) or 9,
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
local ROW_HEIGHT           = 28   -- matches the native meter's default BarHeight (per-entry height)
local ROW_GAP              = 0
local EDGE_PADDING         = 8
local SIDE_PADDING         = 4    -- left/right inset from the window edge to the rows
local TITLE_BAR_HEIGHT     = 31   -- matches the stock meter's drawn header height (atlas 28, drawn 31)
local TITLE_BAR_TOP        = 1    -- gap between the window top edge and the header bar
local TITLE_BAR_GAP        = 2    -- gap between the header bar and the first row
local TITLE_BUTTON_SIZE    = 18
local TITLE_BUTTON_GAP     = 4
local TITLE_TEXT_SIZE      = 12
local TAB_WIDTH            = 20
local TAB_HEIGHT           = 18
local TAB_GAP              = 2
local TAB_TEXT_SIZE        = 11
local MINIMIZED_WIDTH      = MIN_WIDTH
local MINIMIZED_HEIGHT     = MIN_HEIGHT
local RIGHT_SAFE_PAD       = 0
local BOTTOM_SAFE_PAD      = 0
local BAR_HEIGHT           = ICON_SIZE
local TEXT_RISE            = 3     -- raise the name/value text above row centre to match the meter
local TEXT_SIZE            = 13
local st                   = {}    -- live driver state: .spec (native bar geometry) + .lastSession/.lastStyle/.lastBarH
local PERCENT_WIDTH        = 42
local VALUE_WIDTH          = 112
local COLUMN_GAP           = 8

local DAMAGE_TAB_TEXTURE_PATH     = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\damage.png"
local HEALING_TAB_TEXTURE_PATH    = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\healing.png"
local ACTION_TAB_TEXTURE_PATH     = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\action.png"
local CLOSE_TEXTURE_PATH          = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\close.png"
local MINIMIZE_TEXTURE_PATH       = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\minimize.png"
local EXPAND_TEXTURE_PATH         = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\expand.png"
local DROPDOWN_TEXTURE_PATH       = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\down.png"
local EXPAND_ALL_TEXTURE_PATH     = "Interface\\AddOns\\GSE_Tracker\\media\\Details\\down.png"

-- Title-bar CATEGORY icons -> each opens a dropdown of meter-type views (matches the native meter's
-- dropdown). One icon per category; selecting a view filters the breakdown.
st.categories = {
    { id = "damage",  icon = DAMAGE_TAB_TEXTURE_PATH,  label = "Damage",
      views = { "damage", "dps", "damagetaken", "avoidable", "enemy" } },
    { id = "healing", icon = HEALING_TAB_TEXTURE_PATH, label = "Healing",
      views = { "healing", "hps" } },
    { id = "actions", icon = ACTION_TAB_TEXTURE_PATH,  label = "Actions",
      views = { "interrupts", "dispels", "deaths" } },
}


local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- OPTIMISATION: module-level constant tables avoid allocations inside hot loops
local CAST_COUNT_KEYS = {
    "castCount","casts","numCasts","totalCasts",
    "spellCastCount","totalCastCount","castAmount","numberOfCasts",
}
local BUILD_INTERFACE       = select(4, GetBuildInfo()) or 0
local USE_STOCK_SPECIAL_VIEWS = BUILD_INTERFACE >= 120000
local CUSTOM_VIEW_KEYS      = USE_STOCK_SPECIAL_VIEWS and {} or { dispels = true, interrupts = true }
-- Pet grouping for every player-source view (Damage/Healing/Actions areas). Not the enemy view (its
-- rows are enemies, not your abilities).
local PET_GROUPED_VIEW_KEYS = {
    damage = true, dps = true, damagetaken = true, avoidable = true,
    healing = true, hps = true,
    interrupts = true, dispels = true, deaths = true,
}

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
local instances = {}   -- [stockWindowId] = instance table (frame/rows/tabButtons/currentView)
local activeInst       -- the instance the file-local pointers currently target
local SetActive        -- SetActive(inst): aim the file-local pointers at an instance (defined w/ the factory)
local RefreshDetails
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
    if viewKey == "dmg" then viewKey = "damage" end
    if viewKey == "heal" then viewKey = "healing" end
    if viewKey == "dispel" or viewKey == "disp" then viewKey = "dispels" end
    if viewKey == "interrupt" or viewKey == "int" or viewKey == "kick" or viewKey == "kicks" then viewKey = "interrupts" end
    if VIEW_DATA[viewKey] then return viewKey end   -- any defined view (incl. dps/hps/damagetaken/etc.)
    return DEFAULT_VIEW
end

-- Map a stock window's Enum.DamageMeterType (its damageMeterType field) to our matching view key, so a
-- DPS-window bar opens the DPS view, an HPS-window bar opens the HPS view, etc.
local function ViewKeyForMeterType(mt)
    if type(mt) ~= "number" then return nil end
    for vk, info in pairs(VIEW_DATA) do
        if info.meterType == mt then return vk end
    end
    return nil
end

local function Round(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function IsNonEmptyString(v)
    return type(v) == "string" and v ~= ""
end

-- ─── Database ─────────────────────────────────────────────────────────────────
-- OPTIMISATION: original GetGSETrackerDetailsDB re-checked every field on every call.
-- Now we init once and cache the reference; invalidated on PLAYER_ENTERING_WORLD.
local _detailsDB = nil

local function InitGSETrackerDetailsDB()
    MetersSavedVars           = MetersSavedVars or {}
    MetersSavedVars.gseTrackerDetails = MetersSavedVars.gseTrackerDetails or {}
    local db = MetersSavedVars.gseTrackerDetails
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

local function GetGSETrackerDetailsDB()
    if _detailsDB then return _detailsDB end
    return InitGSETrackerDetailsDB()
end

-- Per-window saved state lives in db.windows[id]; global settings (enabled/hideInCombat/petGroupExpanded)
-- stay at the root. Window 1 inherits the legacy flat keys so existing layouts carry over unchanged.
local function GetWindowDB(id)
    local db = GetGSETrackerDetailsDB()
    id = id or (activeInst and activeInst.id) or 1
    db.windows = db.windows or {}
    local w = db.windows[id]
    if not w then
        w = {}
        if id == 1 then
            w.point=db.point; w.relativePoint=db.relativePoint; w.x=db.x; w.y=db.y
            w.width=db.width; w.height=db.height
            w.expandedWidth=db.expandedWidth; w.expandedHeight=db.expandedHeight
            w.isMinimized=db.isMinimized; w.wasShown=db.wasShown; w.viewKey=db.viewKey; w.pinned=db.pinned
        end
        if w.point         == nil then w.point         = "CENTER"       end
        if w.relativePoint == nil then w.relativePoint = "CENTER"       end
        if w.x             == nil then w.x             = 0              end
        if w.y             == nil then w.y             = 0              end
        if w.width         == nil then w.width         = DEFAULT_WIDTH  end
        if w.height        == nil then w.height        = DEFAULT_HEIGHT end
        if w.expandedWidth  == nil then w.expandedWidth  = DEFAULT_WIDTH  end
        if w.expandedHeight == nil then w.expandedHeight = DEFAULT_HEIGHT end
        if w.isMinimized   == nil then w.isMinimized   = false          end
        if w.wasShown      == nil then w.wasShown      = false          end
        if w.viewKey       == nil then w.viewKey       = DEFAULT_VIEW    end
        if w.pinned        == nil then w.pinned        = false          end
        db.windows[id] = w
    end
    return w
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
    local db = GetGSETrackerDetailsDB()
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
local function SaveGSETrackerDetailsWindowState()
    if not frame then return end
    -- Normalize to a UIParent-relative anchor BEFORE reading the point. Save discards the relativeTo
    -- frame and Restore always re-applies against UIParent, so a stock-window-relative anchor (set once
    -- by AnchorToStockMeter, e.g. TOPLEFT->stock TOPRIGHT) would be reinterpreted as UIParent's TOPRIGHT
    -- on reopen -- landing the window on the opposite side of the screen. Re-anchoring to UIParent at the
    -- same on-screen spot (the file's GetLeft/GetTop -> BOTTOMLEFT convention) makes save/restore round-trip.
    local _, relTo = frame:GetPoint(1)
    if relTo and relTo ~= UIParent then
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end
    local db = GetWindowDB(activeInst and activeInst.id)
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

local function RestoreGSETrackerDetailsWindowState()
    if not frame then return end
    local db = GetWindowDB(activeInst and activeInst.id)
    currentView = NormalizeViewKey(db.viewKey)
    if activeInst then activeInst.currentView = currentView end
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
    RestoreGSETrackerDetailsWindowState()
    if wantedView then currentView = wantedView end
    UpdateWindowButtonVisuals(); UpdateContentWidth(); UpdateScrollBounds()
end

-- True when the user has picked OUR window ("GSE: Tracker Skinner") as the meter source. On `st` (not
-- a new local) to respect the 200-locals limit. Falls back to the old "active unless Details! present"
-- rule if the meterMode router (Details.lua) hasn't loaded.
st.isSkinnerMode = function()
    if _G.GSETracker_GetMeterMode then return _G.GSETracker_GetMeterMode() == "skinner" end
    return not _G.Details
end
local function IsDetailsEnabled()
    return st.isSkinnerMode()  -- the breakdown is available whenever the Skinner source is selected
end

local function ShouldHideDetailsInCombat()
    return false  -- "Hide Details in Combat" option removed
end

local function SyncDetailsOptionForHiddenWindow() end  -- "Show Details" checkbox removed (no-op)

local function ApplyInitialWindowState()
    if not frame then return end
    ApplySavedWindowState(false)
    frame.hiddenForCombat = false      -- so ApplyCombatVisibility doesn't auto-restore it
    local db = GetWindowDB(activeInst and activeInst.id)
    if db.pinned then
        -- A PINNED window persists across /reload: reopen it, pinned + locked.
        frame.pinned = true
        if frame.closeButton and frame.closeButton.icon then
            frame.closeButton.icon:SetTexture("Interface\\AddOns\\GSE_Tracker\\media\\Details\\pingoldglow.png")
        end
        if frame.resizeGrip then frame.resizeGrip:Show() end  -- pinned locks position, not size
        db.wasShown = true
        frame:Show(); frame:Raise()
        if RefreshDetails then RefreshDetails(true) end
    else
        -- UNPINNED: reloads always start closed + unpinned (opened later by a meter line-click).
        frame.pinned = false
        if frame.closeButton and frame.closeButton.icon then
            frame.closeButton.icon:SetTexture("Interface\\AddOns\\GSE_Tracker\\media\\Details\\pin.png")
        end
        if frame.resizeGrip then frame.resizeGrip:Show() end
        db.wasShown = false
        frame:Hide()
    end
    if st.applyEscClose then st.applyEscClose() end  -- pinned windows ignore Esc
    SaveGSETrackerDetailsWindowState()
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

-- The class colour to paint the breakdown bars with: the player's own, UNLESS the window is focused on
-- another combatant (clicked their stock-meter row) -- then THEIR class colour, resolved from the GUID via
-- GetPlayerInfoByGUID (works for grouped/seen players). Falls back to the player's colour if it can't
-- resolve a class (e.g. focus is a pet/NPC or info not cached yet).
local function GetFocusClassColor()
    local focusGUID = activeInst and activeInst.focusGUID
    -- No GUID compare: focusGUID can be a SECRET C_DamageMeter value (== throws while tainted). When nothing
    -- is focused, use the player's colour; otherwise resolve via GetPlayerInfoByGUID below -- which returns
    -- the player's own class (hence colour) when the focus happens to be the player, so self still works.
    if not focusGUID then
        return GetPlayerClassColor()
    end
    local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local ok, _, classTag = pcall(GetPlayerInfoByGUID, focusGUID)  -- (localizedClass, englishClass, ...)
    local c = ok and classTag and classColors and classColors[classTag]
    if c then return c.r, c.g, c.b end
    return GetPlayerClassColor()
end

local function GetPlayerClassIconInfo()
    local _, classTag = UnitClass("player")
    return classTag, classTag and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag]
end

-- OPTIMISATION: GetSelectedFontPath is called per-row during a render pass.
-- Cache it for the duration of the pass; invalidated by InvalidateFontCache().
local _cachedFontPath = nil

local function GetSelectedFontPath()
    local sv = MetersSavedVars
    -- Prefer the GSE: Tracker Skinner's explicit Font pick (a path) so this breakdown matches the
    -- meter skin. Read live (cheap) so a new pick shows on the next refresh; only the LSM-name
    -- fallback is cached.
    local pick = sv and sv.skinFont
    if pick and pick ~= "" then return pick end
    if _cachedFontPath then return _cachedFontPath end
    local fontName = sv and sv.fontType
    if LSM and fontName and fontName ~= "" then
        local fp = LSM:Fetch("font", fontName, true)
        if fp then _cachedFontPath = fp; return fp end
    end
    _cachedFontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    return _cachedFontPath
end

-- Bar texture matches the Skinner's Bar pick (a path); falls back to the smooth default.
local function GetSelectedBarTexture()
    local sv = MetersSavedVars
    local pick = sv and sv.skinBarTexture
    if pick and pick ~= "" then return pick end
    return "Interface\\TargetingFrame\\UI-StatusBar"
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

local function ResetAllCustomTrackers()
    for vk in pairs(CUSTOM_VIEW_KEYS) do ResetCustomTrackerBucket(vk) end
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
    return nil   -- the player's own spells stay flat (not wrapped in a group)
end

local function GetSpellCastCount(spellData)
    if type(spellData) ~= "table" then return nil end
    local count = ReadCastCountFromTable(spellData); if count then return count end
    local bestCount = nil
    IterateSpellDetails(spellData.combatSpellDetails, function(detail)
        local dc = ReadCastCountFromTable(detail)
        if dc and (not bestCount or dc > bestCount) then bestCount = dc end
    end)
    return bestCount
end

-- ─── Stock meter ──────────────────────────────────────────────────────────────
local function SourceMatchesPlayer(source, playerGUID)
    if type(source) ~= "table" then return false end
    if source.isLocalPlayer then return true end
    -- C_DamageMeter source GUIDs can be SECRET (taint) -- a direct `==` throws while tainted. pcall the
    -- compare so a secret GUID just fails to match here (the engine-side lookups in ResolveSourceForGUID
    -- resolve the match secret-safely) instead of erroring out the whole breakdown render.
    local ok, match = pcall(function()
        return source.sourceGUID == playerGUID
            or source.guid == playerGUID
            or source.unitGUID == playerGUID
            or source.actorGUID == playerGUID
    end)
    return (ok and match) or false
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

-- Follow the segment the user picked in the stock meter: its window exposes the displayed session's
-- ID (DamageMeterSessionWindow1.sessionID). Read the TARGET combatant's source for THAT session so our
-- breakdown matches the meter's segment (Current / Overall / a past combat). `targetGUID` is the player
-- by default, or another combatant when one was clicked. `isSelf` lets the self lookup also try the
-- "player" convenience string the API accepts; for OTHER combatants we MUST pass their real GUID (the
-- "player" string would wrongly return us). SourceMatchesPlayer matches any GUID, not just the player.
local function GetMeterSelectedSource(meterType, targetGUID, isSelf)
    local w = _G.DamageMeterSessionWindow1
    local sid = w and w.sessionID
    if not sid then return nil end
    -- Direct source-by-session-ID lookup (works for past/Expired combats, where the combatSources
    -- iteration below comes back empty).
    if C_DamageMeter.GetCombatSessionSourceFromID then
        local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, meterType, targetGUID)
        if ok and src then return src end
        if isSelf then
            ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, meterType, "player")
            if ok and src then return src end
        end
    end
    -- Fallback: pull the session and find the target among its combatSources (Current/Overall).
    if C_DamageMeter.GetCombatSessionFromID then
        local ok, info = pcall(C_DamageMeter.GetCombatSessionFromID, sid, meterType)
        if ok and info and type(info.combatSources) == "table" then
            for _, src in ipairs(info.combatSources) do
                if SourceMatchesPlayer(src, targetGUID) then return src end
            end
        end
    end
    return nil
end

-- Resolve the session source for a SPECIFIC combatant GUID through every available avenue (selected
-- segment first, then current/typed sessions, then a scan of available sessions). `isSelf` enables the
-- "player" convenience-string fallbacks; for other combatants only the real GUID is used.
local function ResolveSourceForGUID(meterType, targetGUID, isSelf)
    local sel = GetMeterSelectedSource(meterType, targetGUID, isSelf)  -- the meter's selected segment wins
    if sel then return sel end
    if C_DamageMeter.GetCurrentCombatSessionSource then
        local ok, src = pcall(C_DamageMeter.GetCurrentCombatSessionSource, meterType, targetGUID)
        if ok and src then return src end
        if isSelf then
            ok, src = pcall(C_DamageMeter.GetCurrentCombatSessionSource, meterType, "player")
            if ok and src then return src end
        end
    end
    if C_DamageMeter.GetCombatSessionSourceFromType then
        local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, SESSION_TYPE, meterType, targetGUID)
        if ok and src then return src end
        if isSelf then
            ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, SESSION_TYPE, meterType, "player")
            if ok and src then return src end
        end
    end
    return GetPlayerSourceFromAvailableSessions(meterType, targetGUID)
end

-- The breakdown normally shows YOU, but clicking another combatant's row in the stock meter focuses
-- THEM for that window (activeInst.focusGUID). If the focused combatant has no data in the shown
-- segment, revert to self so the window is never stranded empty. activeInst.focusName carries who is
-- actually rendered (nil = self) for the title bar.
local function GetPlayerSource(meterType)
    if not C_DamageMeter then return nil, "C_DamageMeter is not available." end
    local playerGUID = UnitGUID("player"); if not playerGUID then return nil, "Player GUID is not ready." end
    -- focusGUID is a C_DamageMeter combatant GUID (from clicking a row) and can be a SECRET value -- comparing
    -- it (== playerGUID) throws while tainted. "Self" = nothing focused (we only set focusGUID on a row
    -- click); the engine-side source lookups below take the GUID itself and handle secret values.
    local focus = activeInst and activeInst.focusGUID
    local targetGUID = focus or playerGUID
    local isSelf = not focus
    local src = ResolveSourceForGUID(meterType, targetGUID, isSelf)
    if not src and not isSelf then
        if activeInst then activeInst.focusGUID = nil end  -- focused combatant absent here -> back to self
        isSelf = true
        src = ResolveSourceForGUID(meterType, playerGUID, true)
    end
    if activeInst then activeInst.focusName = (not isSelf and src and src.name) or nil end
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

local function ApplyGSETrackerDetailsOpacity()
    if not frame then return end
    -- Follow the meter's Opacity (Transparency) setting when available; else the addon's own setting.
    local a = st.cfg and tonumber(st.cfg.opacity)
    a = a and (a / 100) or GetConfiguredOpacityAlpha()
    frame:SetAlpha(Clamp(a, 0.15, 1))
    -- Match the meter's ACTUAL background: the stock window's `backgroundAlpha` is the exact alpha
    -- Blizzard renders its "damagemeters-background" atlas at (its own slider curve + floor; 0 = clear).
    -- We tint OUR copy of that same atlas with it, so our body reads identically to the native meter.
    local bgTex = frame.gseBorder and frame.gseBorder.meterBG
    if bgTex and bgTex.SetVertexColor then
        local sw = (activeInst and activeInst.stockWindow) or _G.DamageMeterSessionWindow1 or _G.DamageMeter
        local a  = sw and sw.backgroundAlpha
        if type(a) ~= "number" then
            local bg = st.cfg and tonumber(st.cfg.bg)   -- fallback: the raw setting
            a = bg and (bg / 100) or 0.55
        end
        bgTex:SetVertexColor(1, 1, 1, Clamp(a, 0, 1))
    end
end

-- Read the native DamageMeter's "Style" Edit Mode setting (0 Default / 2 Bordered / 1 Thin) so the
-- breakdown rows match it. Retail-only; returns 0 (Default) when the meter/enum is absent.
local function GetMeterStyle()
    local f = _G.DamageMeter
    local E = Enum and Enum.EditModeDamageMeterSetting
    if f and f.GetSettingValue and E and E.Style then
        local ok, v = pcall(f.GetSettingValue, f, E.Style)
        if ok and v ~= nil then return v end
    end
    return 0
end

-- Bar thickness per Style, scaled to the current ROW_HEIGHT (which follows the meter's BarHeight
-- setting) so taller rows get proportionally taller bars, like the native meter.
local function StyleBarHeight(style)
    if style == 1 then return math.max(4, math.floor(ROW_HEIGHT * 0.46 + 0.5)) end  -- Thin: slim
    return math.max(6, ROW_HEIGHT - 2)                                              -- Default/Bordered: near-full
end

-- Read the native meter's Edit Mode SETTINGS (config values, NOT the secret combat geometry) so the
-- breakdown mirrors them: Numbers (0 Minimal/1 Compact/2 Complete), Padding, Opacity(Transparency),
-- Background, BarHeight, TextSize. All pcall-guarded; defaults when the meter/enum is absent.
st.refreshCfg = function()
    local cfg = st.cfg or {}
    local f = _G.DamageMeter
    local E = Enum and Enum.EditModeDamageMeterSetting
    if f and f.GetSettingValue and E then
        local function g(keys, d)
            if type(keys) == "string" then keys = { keys } end
            for _, k in ipairs(keys) do
                local s = E[k]
                if s ~= nil then
                    local ok, v = pcall(f.GetSettingValue, f, s)
                    if ok and tonumber(v) then return tonumber(v) end
                end
            end
            return d
        end
        cfg.numbers   = g("Numbers", 2)
        cfg.padding   = g("Padding", 2)
        cfg.opacity   = g({ "Transparency", "Opacity" }, 100)            -- 50..100
        cfg.bg        = g({ "BackgroundTransparency", "Background" }, 0)   -- 0..100
        cfg.barHeight = g("BarHeight", 28)                   -- 15..40 (= row height)
        cfg.textSize  = g("TextSize", 100)                   -- 50..150 (%)
    end
    st.cfg = cfg
end

-- Value text honoring the Numbers setting: Complete = "rate (total)"; Compact = "rate"; Minimal =
-- one abbreviated number. `rate`/`total` are the row's numbers; showRate=false views use total only.
st.fmtValue = function(rate, total, showRate)
    local n = (st.cfg and st.cfg.numbers) or 2
    local main = showRate and rate or total
    if n <= 0 then return FormatParenTotal(main) end                          -- Minimal
    if n == 1 then return FormatMainNumber(main) end                          -- Compact
    if showRate then return FormatMainNumber(rate) .. " (" .. FormatParenTotal(total) .. ")" end
    return FormatMainNumber(total)                                            -- Complete
end

-- COPY THE DEFAULT: read the native meter's live bar so the breakdown uses its EXACT size/shape.
-- st.spec.barH   = the native StatusBar's height (full row for Default/Bordered, slim for Thin).
-- st.spec.bottom = how far that bar sits above the row's bottom (so a thin bar lands where Blizzard's does).
-- st.spec.barAtlas/barTex = the native bar's fill texture (its atlas gives the rounded end caps).
-- Refreshed by the lineDriver (and on Style/skin changes); ApplyRowIndent reads it for every row.
-- Measured native-meter geometry (retail 11.x). WoW now returns the meter's positions as protected
-- "secret" values, so arithmetic on them throws AND taints us. We read live inside pcall and fall back
-- to these constants whenever that fails -- the breakdown still matches without ever erroring. barH is
-- intentionally omitted so ApplyRowIndent uses the style-aware StyleBarHeight (Style IS readable).
-- barH and textVc intentionally omitted -> ApplyRowIndent derives them style-aware (StyleBarHeight +
-- the per-style text rise), since the live read that would give exact per-style values is secret-blocked.
st.defaultSpec = {
    bottom = 1, barLeft = 29, barRight = 0, barTex = 423819,
    iconSize = 24, fontSize = 14, valueRight = 3, nameLeft = 29,
    frames = {
        { atlas = "ui-damagemeters-bar-shadowbg",   layer = "BACKGROUND", sub = 0, dL = -2, dT = 2, dR = -2, dB = 2 },
        { atlas = "ui-damagemeters-bar-shadowedge", layer = "OVERLAY",    sub = 0, dL = -2, dT = 2, dR = -2, dB = 2 },
    },
}

local function RefreshNativeSpec()
    -- Wrapped in pcall: reading/arithmetic on the meter's protected "secret" values throws; we must
    -- never let that propagate (it taints us and spams errors). On any failure -> measured constants.
    local ok, s = pcall(function()
        local win = _G.DamageMeterSessionWindow1
        if not (win and win.GetChildren) then return nil end
        local found
        local function walk(fr, d)
            if found or d > 6 or not fr.GetChildren then return end
            for _, c in ipairs({ fr:GetChildren() }) do
                if c.GetObjectType and c:GetObjectType() == "StatusBar" then found = c; return end
                walk(c, d + 1); if found then return end
            end
        end
        walk(win, 0)
        if not found then return nil end
        local row = found:GetParent()
        local s = {}
        local bh = found:GetHeight()
        if bh and bh > 0 then s.barH = bh end
        if found.GetBottom and found:GetBottom() and row and row.GetBottom and row:GetBottom() then
            s.bottom = found:GetBottom() - row:GetBottom()
        end
        local t = found.GetStatusBarTexture and found:GetStatusBarTexture()
        if t then
            s.barAtlas = (t.GetAtlas and t:GetAtlas()) or nil
            if not s.barAtlas then s.barTex = (t.GetTexture and t:GetTexture()) or nil end
        end
        local function relL(o) return (o.GetLeft and o:GetLeft() and row.GetLeft and row:GetLeft()) and (o:GetLeft() - row:GetLeft()) or nil end
        local function relR(o) return (o.GetRight and o:GetRight() and row.GetRight and row:GetRight()) and (row:GetRight() - o:GetRight()) or nil end
        local function relVc(o)
            if not (o.GetTop and o:GetTop() and o:GetBottom() and row.GetTop and row:GetTop() and row:GetBottom()) then return nil end
            return ((o:GetTop() + o:GetBottom()) / 2) - ((row:GetTop() + row:GetBottom()) / 2)
        end
        s.barLeft, s.barRight = relL(found), relR(found)
        local nameFS, valFS
        local function scan(obj)
            if not (obj and obj.GetRegions) then return end
            for _, r in ipairs({ obj:GetRegions() }) do
                local ty = r.GetObjectType and r:GetObjectType()
                if ty == "Texture" then
                    local w, h = r:GetWidth() or 0, r:GetHeight() or 0
                    if w > 10 and h > 10 and math.abs(w - h) <= 2 and h > (s.iconSize or 0) then s.iconSize = h end
                elseif ty == "FontString" then
                    if r.GetFont then local _, sz = r:GetFont(); if sz and sz > (s.fontSize or 0) then s.fontSize = sz end end
                    local l = relL(r)
                    if l then
                        if not nameFS or l < (relL(nameFS) or 1e9) then nameFS = r end
                        if not valFS or (relR(r) or 1e9) < (relR(valFS) or 1e9) then valFS = r end
                    end
                end
            end
        end
        scan(row)
        for _, c in ipairs({ row:GetChildren() }) do scan(c) end
        if nameFS then s.nameLeft = relL(nameFS); s.textVc = relVc(nameFS) end
        if valFS  then s.valueRight = relR(valFS) end
        s.frames = {}
        for _, r in ipairs({ found:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" and r.GetAtlas and r:GetAtlas() then
                local layer, sub = r:GetDrawLayer()
                local fr = { atlas = r:GetAtlas(), layer = layer, sub = sub or 0 }
                fr.dL = (r:GetLeft()   and found:GetLeft())   and (r:GetLeft()   - found:GetLeft())   or 0
                fr.dT = (r:GetTop()    and found:GetTop())    and (r:GetTop()    - found:GetTop())    or 0
                fr.dR = (found:GetRight()  and r:GetRight())  and (found:GetRight()  - r:GetRight())  or 0
                fr.dB = (found:GetBottom() and r:GetBottom()) and (found:GetBottom() - r:GetBottom()) or 0
                s.frames[#s.frames + 1] = fr
            end
        end
        return s
    end)
    st.spec = (ok and type(s) == "table") and s or st.defaultSpec
end

-- Texture for a row's bar: the Skinner's Bar pick wins; otherwise copy the native meter's bar (atlas
-- = rounded caps); final fallback is a smooth statusbar texture.
local function ApplyBarTexture(bar, bg)
    if not bar then return end
    local pick = MetersSavedVars and MetersSavedVars.skinBarTexture
    if pick and pick ~= "" then
        bar:SetStatusBarTexture(pick)
        if bg and bg.SetTexture then bg:SetTexture(pick) end
        return
    end
    local spec = st.spec
    if spec and spec.barAtlas then
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        local tx = bar:GetStatusBarTexture()
        if tx and tx.SetAtlas then pcall(tx.SetAtlas, tx, spec.barAtlas, false) end
        if bg and bg.SetAtlas then pcall(bg.SetAtlas, bg, spec.barAtlas) end
        return
    end
    local tex = (spec and spec.barTex) or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(tex)
    if bg and bg.SetTexture then bg:SetTexture(tex) end
end

-- Copy the meter's bar "track" pieces (rounded shadowbg/shadowedge atlases -- and the Bordered
-- style's border atlas) onto the row's bar so it gets Blizzard's exact rounded ends + per-style look.
-- Each piece is an atlas texture, slightly larger than the bar, at the captured draw layer/sublevel.
-- (Bar height/location + text are in ApplyRowIndent so the layout stays in one spot.)
local function ApplyRowStyle(row)
    if not row or not row.bar then return end
    row._frames = row._frames or {}
    local defs = st.spec and st.spec.frames
    local n = 0
    if defs then
        for i, d in ipairs(defs) do
            n = i
            local tx = row._frames[i]
            if not tx then tx = row.bar:CreateTexture(); row._frames[i] = tx end
            -- Force layering vs our fill (statusbar texture = ARTWORK): bg pieces behind, edge/border over.
            local layer, lname = d.layer or "ARTWORK", (d.atlas or ""):lower()
            if lname:find("bg") then layer = "BACKGROUND"
            elseif lname:find("edge") or lname:find("border") then layer = "OVERLAY" end
            tx:SetDrawLayer(layer, d.sub or 0)
            tx:ClearAllPoints()
            tx:SetPoint("TOPLEFT",     row.bar, "TOPLEFT",     d.dL or 0,    d.dT or 0)
            tx:SetPoint("BOTTOMRIGHT", row.bar, "BOTTOMRIGHT", -(d.dR or 0), -(d.dB or 0))
            if tx.SetAtlas then tx:SetAtlas(d.atlas) end
            tx:Show()
        end
    end
    for i = n + 1, #row._frames do row._frames[i]:Hide() end
    -- The native shadowbg IS the track; hide our plain barBG (and any old manual border) when we have it.
    if row.barBG then row.barBG:SetAlpha(n > 0 and 0 or 1) end
    if row.barBorder then row.barBorder:Hide() end
end

local function ApplyRowFonts(row)
    if not row or not row.name or not row.value then return end
    local fp = GetSelectedFontPath()
    -- Follow the meter's TextSize setting (% of base); fall back to the copied native font size.
    local sz
    local ts = st.cfg and tonumber(st.cfg.textSize)
    if ts then sz = math.max(6, math.floor(TEXT_SIZE * ts / 100 + 0.5))
    else sz = (st.spec and st.spec.fontSize) or TEXT_SIZE end
    row.name:SetFont(fp, sz, "")
    if row.percent then row.percent:SetFont(fp, sz, "") end
    row.value:SetFont(fp, sz, "")
    -- Bar texture: Skinner pick > native bar atlas (rounded caps) > smooth fallback (rows are pooled).
    ApplyBarTexture(row.bar, row.barBG)
    ApplyRowStyle(row)  -- match the meter's Default/Bordered/Thin Style
end

local function ApplyTitleBarFont()
    if not frame then return end
    local fp = GetSelectedFontPath()
    if frame.titleText then frame.titleText:SetFont(fp, TITLE_TEXT_SIZE, "OUTLINE") end
    for _, button in pairs(tabButtons) do
        if button and button.text then button.text:SetFont(fp, TAB_TEXT_SIZE, "") end
    end
end

local function UpdateTitleBarText()
    if not (frame and frame.titleText) then return end
    local info = VIEW_DATA[currentView] or VIEW_DATA[DEFAULT_VIEW]
    local label = (info and info.label) or ""
    -- Focused on another combatant (clicked their row in the stock meter) -> show their name; else self.
    local who = activeInst and activeInst.focusName
    if type(who) == "string" and who ~= "" then
        frame.titleText:SetText(who .. " - " .. label)
    else
        frame.titleText:SetText("Filter: " .. label)
    end
end
local function UpdateTitleBarClassIcon() return end

local function UpdateTabVisuals()
    if not frame then return end
    for _, button in pairs(tabButtons) do
        if button and button.bg then
            local isActive = false  -- a category is active if it owns the current view
            if button.cat then
                for _, vk in ipairs(button.cat.views) do
                    if vk == currentView then isActive = true; break end
                end
            end
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
    -- titleBarBG keeps the stock "ui-damagemeters-header-bar" atlas (don't overwrite with a color).
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
    local reservedTop = TITLE_BAR_TOP + TITLE_BAR_HEIGHT + TITLE_BAR_GAP
    return Clamp(contentH + reservedTop + EDGE_PADDING + BOTTOM_SAFE_PAD, MIN_HEIGHT, MAX_HEIGHT)
end

local function GetRowCountForView(viewKey)
    viewKey = NormalizeViewKey(viewKey)
    if viewKey == "enemy" then return st.lastEnemyCount or 0 end  -- enemy list count (set by st.renderEnemies)
    if IsCustomView(viewKey) then return #(BuildCustomSpellList(viewKey)) end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local viewInfo = VIEW_DATA[viewKey] or VIEW_DATA[DEFAULT_VIEW]
    local source   = GetPlayerSource(viewInfo.meterType); if not source then return 0 end
    local _, _, _, visibleCount = BuildStockDisplayEntries(viewKey, source)
    return visibleCount or 0
end

-- Window no longer auto-grows to fit rows: it keeps the user's height and the content scrolls inside it
-- (native minimal scrollbar). Kept as a no-op so the many callers don't need touching.
local function ApplyAutoWindowHeight(rowCount) end

UpdateScrollBounds = function()
    -- Refresh the scroll child rect so the native scrollbar recomputes its range for the new content
    -- height, then clamp the current scroll (the bar tracks SetVerticalScroll via its OnVerticalScroll hook).
    if frame.scrollFrame.UpdateScrollChildRect then frame.scrollFrame:UpdateScrollChildRect() end
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

-- ─── UISpecialFrames ──────────────────────────────────────────────────────────
local function RegisterSpecialFrame(frameName)
    if not UISpecialFrames then return end
    for _, name in ipairs(UISpecialFrames) do if name == frameName then return end end
    table.insert(UISpecialFrames, frameName)
end
-- Esc closes a UISpecialFrame. We keep the window registered ONLY while it's unpinned; pinning
-- removes it so Esc leaves it open (matches the click-away lock). Lives on `st` (an upvalue) so the
-- earlier ApplyInitialWindowState can reach it without a top-level local (200-locals limit).
st.applyEscClose = function()
    if not UISpecialFrames then return end
    local name = (frame and frame.GetName and frame:GetName()) or WINDOW_NAME
    if frame and frame.pinned then
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
        end
    else
        RegisterSpecialFrame(name)
    end
end

-- ─── Frame (per-stock-window instance factory) ──────────────────────────────────
-- One breakdown window per stock meter window. The render/layout/data code all operate on the
-- file-local "active" pointers (frame/rows/tabButtons/currentView); SetActive() aims them at an
-- instance, and every entry point selects its instance first. BuildInstance() creates one window's
-- widget tree (this whole block) and snapshots it onto `inst`. Inner helpers stay local to the factory
-- (nothing outside this block calls them) and read the active `frame`, so a single shared copy works.
SetActive = function(inst)
    if not inst then return end
    activeInst  = inst
    frame       = inst.frame
    rows        = inst.rows
    tabButtons  = inst.tabButtons
    currentView = inst.currentView or DEFAULT_VIEW
end
local function BuildInstance(id)
    local inst = { id = id, rows = {}, tabButtons = {}, currentView = DEFAULT_VIEW }
    activeInst  = inst
    rows        = inst.rows
    tabButtons  = inst.tabButtons
    currentView = inst.currentView
    local fname = (id == 1) and WINDOW_NAME or (WINDOW_NAME .. id)
frame = CreateFrame("Frame", fname, UIParent, "BackdropTemplate")
frame.instance = inst
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

-- Match the skinned meter's border EXACTLY (mirrors MeterSkin.lua's ApplyBorder): a separate frame
-- anchored 4px OUTSIDE the window so the heavy edge sits outside the 4px-inset title bar/rows, and it
-- carries the dark fill behind the (transparent) content -- same backdrop + colours the native
-- DamageMeter gets, so the two windows are identical. Adopts an active thin-border skinner
-- (ElvUI/EllesmereUI) as a 1px line in its colour, else the clean tooltip-style default border.
local function ApplyWindowBorder(f)
    local b = f.gseBorder
    if not b then
        b = CreateFrame("Frame", nil, f, "BackdropTemplate")
        b:SetPoint("TOPLEFT",     f, "TOPLEFT",     -4,  4)
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  4, -4)
        b:SetFrameStrata(f:GetFrameStrata())
        b:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))  -- behind the content
        f.gseBorder = b
    end
    if not b.SetBackdrop then return end
    local r, g, blue, thickness = (uiShared.GetSkinnerBorderStyle and uiShared.GetSkinnerBorderStyle())
    if r then
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = thickness or 1, tile = true, tileSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        b:SetBackdropBorderColor(r, g, blue, 1)
    else
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, tile = true, tileSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        b:SetBackdropBorderColor(0.60, 0.55, 0.42, 1)
    end
    b:SetBackdropColor(0, 0, 0, 0)  -- no flat fill; the body uses Blizzard's own meter background atlas
    -- Body background = the exact atlas the native meter uses ("damagemeters-background"), so our window
    -- reads identically to the stock meter. Alpha is driven later from the meter's backgroundAlpha.
    if not b.meterBG then
        b.meterBG = b:CreateTexture(nil, "BACKGROUND", nil, -1)
        b.meterBG:SetPoint("TOPLEFT",     b, "TOPLEFT",      4, -4)
        b.meterBG:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4,  4)
    end
    if b.meterBG.SetAtlas then pcall(b.meterBG.SetAtlas, b.meterBG, "damagemeters-background") end
end
ApplyWindowBorder(frame)
_G.GSETrackerDetails_ApplyBorder = function()
    for _, ins in pairs(instances) do if ins.frame then ApplyWindowBorder(ins.frame) end end
end
frame:SetAlpha(GetConfiguredOpacityAlpha())
frame:Hide()
RegisterSpecialFrame(WINDOW_NAME)

-- ─── Manual drag ─────────────────────────────────────────────────────────────
local function StartManualDrag()
    if not frame or frame.isDragging or frame.pinned then return end  -- pinned = locked in place
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition(); cx = cx / scale; cy = cy / scale
    frame.dragOffsetX = cx - (frame:GetLeft() or 0)
    frame.dragOffsetY = cy - (frame:GetBottom() or 0)
    frame.isDragging  = true
end

local function StopManualDrag()
    if frame then frame.isDragging = false; SaveGSETrackerDetailsWindowState() end
end

local function UpdateManualDrag()
    SetActive(inst)
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

local function RefreshMyTimerIfNeeded()
    if _G.MyTimer_RefreshAll then _G.MyTimer_RefreshAll()
    elseif _G.MyTimer_RefreshVisibility then _G.MyTimer_RefreshVisibility() end
end

local function ExpandWindowForViewRows(viewKey, rowCount)
    if not frame or not frame.isMinimized then return false end
    rowCount = tonumber(rowCount) or 0; if rowCount <= 0 then return false end
    StopManualDrag(); frame.suspendMinimizeSizeSync = true; frame.isMinimized = false
    SetSizePreserveTopLeft(
        Clamp(tonumber(frame.lastExpandedWidth) or DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH),
        CalculateWindowHeightForRows(rowCount))
    UpdateWindowButtonVisuals(); UpdateContentWidth(); UpdateScrollBounds()
    SaveGSETrackerDetailsWindowState(); RefreshMyTimerIfNeeded()
    C_Timer.After(0, function()
        if frame then frame.suspendMinimizeSizeSync = false end
        RefreshMyTimerIfNeeded()
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
            frame.expandAllButton.icon:SetRotation(allExpanded and 0 or math.pi)  -- collapsed = up
            frame.expandAllButton.icon:SetVertexColor(1, 1, 1, 1)
        else
            frame.expandAllButton.icon:SetRotation(math.pi)  -- collapsed = up
            frame.expandAllButton.icon:SetVertexColor(0.70, 0.70, 0.70, 0.70)
        end
    end
    if frame.resizeGrip then frame.resizeGrip:Show() end  -- resize always allowed (pinned locks position only)
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
    SaveGSETrackerDetailsWindowState()
    if wasMinimized and not frame.isMinimized and frame:IsShown() and RefreshDetails then RefreshDetails(true) end
    RefreshMyTimerIfNeeded()
    C_Timer.After(0, function()
        if frame then frame.suspendMinimizeSizeSync = false end
        RefreshMyTimerIfNeeded()
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
    if frame and frame:IsShown() and RefreshDetails then RefreshDetails(true) else SaveGSETrackerDetailsWindowState() end
end

-- ─── Frame scripts ────────────────────────────────────────────────────────────
frame:SetScript("OnHide", function()
    SetActive(inst)
    GameTooltip_Hide(); frame.isDragging = false
    frame.pendingDeferredRefresh = false
    local suppressDetailsOptionSync = frame.suppressDetailsOptionSync == true
    frame.suppressDetailsOptionSync = false
    if not suppressDetailsOptionSync and IsDetailsEnabled() then
        local db = GetWindowDB(activeInst and activeInst.id)
        db.wasShown = false
    end
    SaveGSETrackerDetailsWindowState()
end)

frame:SetScript("OnSizeChanged", function()
    SetActive(inst)
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
    UpdateContentWidth(); UpdateScrollBounds(); UpdateWindowButtonVisuals(); SaveGSETrackerDetailsWindowState()
end)

-- ─── Title bar ────────────────────────────────────────────────────────────────
frame.titleBar = CreateFrame("Frame", nil, frame)
frame.titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  4, -TITLE_BAR_TOP)
frame.titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -TITLE_BAR_TOP)
frame.titleBar:SetHeight(TITLE_BAR_HEIGHT); frame.titleBar:EnableMouse(true)
frame.titleBar:SetScript("OnMouseDown", function(_, btn) SetActive(inst); if btn == "LeftButton" then StartManualDrag() end end)
frame.titleBar:SetScript("OnMouseUp",   function(_, btn)
    SetActive(inst)
    if btn == "LeftButton" then StopManualDrag(); SaveGSETrackerDetailsWindowState() end
end)
frame.titleBar:SetScript("OnUpdate", UpdateManualDrag)

frame.titleBarBG   = frame.titleBar:CreateTexture(nil, "BACKGROUND")
frame.titleBarBG:SetAtlas("ui-damagemeters-header-bar")  -- match the stock meter's blue header
frame.titleBarBG:SetAllPoints()
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

-- Mouseover feedback for the title-bar icons: a small grow (the icon scales up from its centre) plus a
-- soft gold glow. Re-anchors the icon to CENTER so it can grow past the button bounds. HookScript so
-- it stacks with each button's existing OnEnter/OnLeave.
local function AddHoverGrowGlow(btn, noGlow)
    if not btn or not btn.icon then return end
    local w, h = btn:GetSize()
    if not (w and w > 0) then w, h = 18, 18 end
    btn._baseW, btn._baseH = w, h
    btn.icon:ClearAllPoints(); btn.icon:SetPoint("CENTER", btn, "CENTER", 0, 0); btn.icon:SetSize(w, h)
    if not noGlow then
        local g = btn:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")  -- soft square glow
        g:SetBlendMode("ADD"); g:SetVertexColor(1.0, 0.82, 0.0, 0.85)  -- gold
        g:SetPoint("CENTER", btn, "CENTER", 0, 0); g:SetSize(w * 1.9, h * 1.9); g:Hide()
        btn.hoverGlow = g
    end
    btn:HookScript("OnEnter", function(s)
        if s.icon then s.icon:SetSize(s._baseW * 1.22, s._baseH * 1.22) end
        if s.hoverGlow then s.hoverGlow:Show() end
        local title = s.ttTitle; if type(title) == "function" then title = title() end
        if title then
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(title, 1, 1, 1)
            local sub = s.ttSub; if type(sub) == "function" then sub = sub() end
            if sub then GameTooltip:AddLine(sub, 0.82, 0.82, 0.82, true) end
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function(s)
        if s.icon then s.icon:SetSize(s._baseW, s._baseH) end
        if s.hoverGlow then s.hoverGlow:Hide() end
        GameTooltip:Hide()
    end)
end

-- Pin button (sits where the close X was). Click to PIN the window open: a gold glow appears and the
-- window ignores the click-away auto-close. Click again to unpin (glow off, click-away resumes).
-- Pinned state is NEVER saved -- reloads always start unpinned (and closed, see startup).
frame.closeButton = MakeIconButton(frame.titleBar, 18)
frame.closeButton:SetPoint("TOPRIGHT", frame.titleBar, "TOPRIGHT", -3, -3)
frame.closeButton.icon:SetTexture("Interface\\AddOns\\GSE_Tracker\\media\\Details\\pin.png")
-- Pinned look = swap the icon to the gold-glow pin art (glow is baked into pingoldglow.png).
local function SetPinned(pinned)
    frame.pinned = pinned and true or false
    frame.closeButton.icon:SetTexture(frame.pinned
        and "Interface\\AddOns\\GSE_Tracker\\media\\Details\\pingoldglow.png"
        or  "Interface\\AddOns\\GSE_Tracker\\media\\Details\\pin.png")
    -- Pinned = locked in place: dragging is blocked, but the window can still be RESIZED.
    if frame.resizeGrip then frame.resizeGrip:Show() end
    st.applyEscClose()  -- pinned also ignores Esc

    -- Persist the pin so a pinned window survives /reload (see ApplyInitialWindowState).
    local db = GetWindowDB(activeInst and activeInst.id); db.pinned = frame.pinned; SaveGSETrackerDetailsWindowState()
end
frame.closeButton:SetScript("OnClick", function() SetActive(inst); SetPinned(not frame.pinned) end)
frame.closeButton.ttTitle = function() return frame.pinned and "Unpin" or "Pin" end
frame.closeButton.ttSub   = function()
    return frame.pinned and "Locked in place (still resizable) + stays open. Click to unlock and allow click-away close."
                        or  "Keep this window open and lock it in place (ignores click-away)."
end
AddHoverGrowGlow(frame.closeButton, true)  -- pin: grow on hover but NO gold glow (it has its own pinned art)

-- Reset Data button (loop) -- sits left of the pin. Asks for confirmation, then wipes the meter's
-- combat sessions (same as the native meter's "Reset Data") and refreshes the breakdown.
StaticPopupDialogs["GSETRACKERDETAILS_RESET"] = {
    text = "Reset the damage meter data?\n\nThis clears ALL recorded combat sessions.",
    button1 = YES, button2 = NO,
    OnAccept = function()
        if _G.Meters_ResetMeter then _G.Meters_ResetMeter()
        elseif C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
        if GSETrackerDetails_Refresh and frame and frame:IsShown() then GSETrackerDetails_Refresh() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}
frame.resetButton = MakeIconButton(frame.titleBar, 18)
frame.resetButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -4, 0)  -- vertically centered with the pin
frame.resetButton.icon:SetAtlas("ui-refreshbutton")  -- in-game refresh/reset asset
frame.resetButton:SetScript("OnClick", function() SetActive(inst); StaticPopup_Show("GSETRACKERDETAILS_RESET") end)
frame.resetButton.ttTitle = "Reset Data"
frame.resetButton.ttSub   = "Wipe the meter's recorded combat data (asks first)."
AddHoverGrowGlow(frame.resetButton)

frame.timerAnchor = CreateFrame("Frame", nil, frame.titleBar)
frame.timerAnchor:SetSize(76, TITLE_BUTTON_SIZE)
frame.timerAnchor:SetPoint("RIGHT", frame.resetButton, "LEFT", -2, 0)
frame.timerAnchor:EnableMouse(false)

UpdateWindowButtonVisuals(); UpdateTitleBarClassIcon()

-- ─── Tabs ────────────────────────────────────────────────────────────────────
-- Category icon -> dropdown of its meter-type views (Damage / Healing / Actions). Selecting a view
-- filters the breakdown. Replaces the old per-view tab buttons.
local function CreateTabButton(cat)
    local button = CreateFrame("Button", nil, frame.titleBar, "BackdropTemplate")
    button.cat = cat; button:SetSize(TAB_WIDTH, TAB_HEIGHT)
    button:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=8, edgeSize=10, insets={left=2,right=2,top=2,bottom=2},
    })
    button:SetBackdropColor(0,0,0,0)
    button.bg = button:CreateTexture(nil,"BACKGROUND"); button.bg:SetAllPoints(); button.bg:SetColorTexture(0,0,0,0)
    button.icon = button:CreateTexture(nil,"ARTWORK"); button.icon:SetAllPoints(button)
    button.icon:SetTexture(cat.icon); button.icon:SetTexCoord(0,1,0,1)

    button:SetScript("OnClick", function(self)
        SetActive(inst)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        st.suppressClickAway = true  -- the dropdown is outside our frame; don't let click-away close us
        -- Each icon opens straight to its own category's filter list (the "second level"), so the three
        -- icons aren't duplicates of one nested menu.
        local menu = MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(self.cat.label)
            for _, vk in ipairs(self.cat.views) do
                local info = VIEW_DATA[vk]
                if info then
                    root:CreateRadio(info.label, function() return currentView == vk end, function()
                        SetActive(inst)
                        currentView = vk; inst.currentView = vk
                        SaveGSETrackerDetailsWindowState(); UpdateTabVisuals()
                        if frame:IsShown() then RefreshDetails() end
                    end)
                end
            end
        end)
        -- Re-anchor the menu's TOP to the title bar's bottom (the gold line), under the clicked icon --
        -- MenuUtil opens it at the cursor by default, which lands over the icons.
        if menu and menu.ClearAllPoints and menu.SetPoint then
            local x = 4
            if self.GetLeft and self:GetLeft() and frame.titleBar.GetLeft and frame.titleBar:GetLeft() then
                x = self:GetLeft() - frame.titleBar:GetLeft()
            end
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", frame.titleBar, "BOTTOMLEFT", x, 4)  -- up 5 from the gold line
        end
    end)
    button:SetScript("OnEnter", function(s) s.bg:SetColorTexture(0,0,0,0); s:SetBackdropColor(0,0,0,0) end)
    button:SetScript("OnLeave", function(s) s.bg:SetColorTexture(0,0,0,0); s:SetBackdropColor(0,0,0,0); UpdateTabVisuals() end)
    button.ttTitle = cat.label
    button.ttSub   = "Click to pick a view"
    AddHoverGrowGlow(button)
    tabButtons[cat.id] = button
    return button
end

frame.damageTab  = CreateTabButton(st.categories[1])
frame.damageTab:SetPoint("TOPLEFT", frame.titleBar, "TOPLEFT", 4, -3)  -- top-anchored: clear the gold edge
frame.healingTab = CreateTabButton(st.categories[2])
frame.healingTab:SetPoint("LEFT", frame.damageTab, "RIGHT", TAB_GAP, 0)
frame.actionsTab = CreateTabButton(st.categories[3])
frame.actionsTab:SetPoint("LEFT", frame.healingTab, "RIGHT", TAB_GAP, 0)

frame.expandAllButton = CreateFrame("Button", nil, frame.titleBar)
frame.expandAllButton:SetSize(TAB_WIDTH, TAB_HEIGHT)
frame.expandAllButton:SetPoint("LEFT", frame.actionsTab, "RIGHT", TAB_GAP, 0)
frame.expandAllButton.icon = frame.expandAllButton:CreateTexture(nil, "ARTWORK")
frame.expandAllButton.icon:SetAllPoints(frame.expandAllButton)
frame.expandAllButton.icon:SetTexture(EXPAND_ALL_TEXTURE_PATH)
frame.expandAllButton.icon:SetTexCoord(0, 1, 0, 1)
frame.expandAllButton:SetScript("OnClick", function() SetActive(inst); ToggleAllPetGroupsForCurrentView() end)
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

-- Title-bar label: the currently-selected filter/view name (set by UpdateTitleBarText).
frame.titleText = frame.titleBar:CreateFontString(nil, "OVERLAY")
frame.titleText:SetPoint("LEFT", frame.expandAllButton, "RIGHT", 8, 0)
frame.titleText:SetJustifyH("LEFT")
frame.titleText:SetTextColor(1, 0.95, 0.6, 1)  -- soft gold
frame.titleText:SetShadowOffset(1, -1); frame.titleText:SetShadowColor(0, 0, 0, 1)
frame.titleText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", TITLE_TEXT_SIZE, "OUTLINE")

-- ─── Scroll frame + native scrollbar ────────────────────────────────────────────
-- The scrollbar is pinned to the window's right edge; the scroll frame ends at the bar's LEFT, so the
-- right (value/%) column always stops before the bar and is never covered by it. (Blizzard's
-- MinimalScrollBar via ScrollUtil handles thumb sizing, dragging, wheel and auto-hide; the frame keeps
-- its slot even when hidden, so the column width stays consistent.)
frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame)
frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
    SIDE_PADDING, -(TITLE_BAR_TOP + TITLE_BAR_HEIGHT + TITLE_BAR_GAP))
frame.content = CreateFrame("Frame", nil, frame.scrollFrame)
frame.content:SetSize(1, 1); frame.scrollFrame:SetScrollChild(frame.content)

local barReserved = false
do
    local okSB, sb = pcall(CreateFrame, "EventFrame", nil, frame, "MinimalScrollBar")
    if not (okSB and sb) then okSB, sb = pcall(CreateFrame, "Frame", nil, frame, "MinimalScrollBar") end
    if okSB and sb then
        frame.scrollBar = sb
        sb:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -(SIDE_PADDING + 12), -(TITLE_BAR_TOP + TITLE_BAR_HEIGHT + TITLE_BAR_GAP))
        sb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(SIDE_PADDING + 12),  EDGE_PADDING + BOTTOM_SAFE_PAD)
        frame.scrollFrame:SetPoint("BOTTOMRIGHT", sb, "BOTTOMLEFT", -4, 0)  -- content stops just left of the bar
        barReserved = true
        if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
            pcall(ScrollUtil.InitScrollFrameWithScrollBar, frame.scrollFrame, sb)
        end
        -- Always keep the bar visible (default WowScrollBar behavior): the thumb just fills the track
        -- when there's nothing to scroll, rather than the bar disappearing.
        if sb.SetHideIfUnscrollable then pcall(sb.SetHideIfUnscrollable, sb, false) end
    end
end
if not barReserved then  -- no scrollbar widget available: just inset to the frame edge
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
        -(SIDE_PADDING + RIGHT_SAFE_PAD), EDGE_PADDING + BOTTOM_SAFE_PAD)
end

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
frame.resizeGrip:SetScript("OnMouseDown", function() SetActive(inst); StopManualDrag(); frame:StartSizing("BOTTOMRIGHT") end)  -- resize allowed even when pinned (pinned locks position only)
frame.resizeGrip:SetScript("OnMouseUp",   function()
    SetActive(inst)
    frame:StopMovingOrSizing()
    -- If dragged taller than the data, snap the bottom back up to the last row (no empty space below);
    -- shorter is kept (the content scrolls). Height isn't remembered -- next open re-matches the window.
    local chrome = TITLE_BAR_TOP + TITLE_BAR_HEIGHT + TITLE_BAR_GAP + EDGE_PADDING + BOTTOM_SAFE_PAD
    local needH  = (frame.content:GetHeight() or 0) + chrome
    if (frame:GetHeight() or 0) > needH + 0.5 then
        SetSizePreserveTopLeft(frame:GetWidth() or DEFAULT_WIDTH, Clamp(needH, MIN_HEIGHT, MAX_HEIGHT))
    end
    StoreExpandedSize(); SaveGSETrackerDetailsWindowState()
    UpdateContentWidth()
    if RefreshDetails and frame:IsShown() then RefreshDetails(true) end  -- relayout columns for the new width
end)

frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", function(_, delta) SetActive(inst); ScrollBy(-delta * 32) end)

    inst.frame       = frame
    inst.rows        = rows
    inst.tabButtons  = tabButtons
    inst.currentView = currentView
    instances[id]    = inst
    return inst
end
BuildInstance(1)
SetActive(instances[1])

-- ─── Row layout helper ────────────────────────────────────────────────────────
local function ApplyRowIndent(row, indent, index)
    indent = tonumber(indent) or 0
    -- Row height + vertical position follow the (dynamic) ROW_HEIGHT/ROW_GAP, which mirror the meter's
    -- BarHeight and Padding settings. Re-applied each render since those can change live.
    row:SetHeight(ROW_HEIGHT)
    if index then
        local yOff = -((index - 1) * (ROW_HEIGHT + ROW_GAP))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  frame.content, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, yOff)
    end
    local expandIconWidth = 10
    -- Copy the native meter's bar: height + how far it sits above the row bottom come straight from the
    -- live meter (_spec). Text stays vertically CENTRED in the row -- so a full-height bar (Default/
    -- Bordered) sits behind the text, and a thin bottom bar (Thin) leaves the centred text above it,
    -- exactly like Blizzard. Falls back to the per-Style thickness only if the meter can't be read.
    local spec   = st.spec
    local style  = GetMeterStyle()
    local barH   = (spec and spec.barH) or StyleBarHeight(style)
    barH = math.max(2, math.min(barH, ROW_HEIGHT))
    local barOff = (spec and spec.bottom) or 0
    local iconSz = math.min((spec and spec.iconSize) or ICON_SIZE, ROW_HEIGHT)  -- copy Blizzard's icon scale
    -- Text rise: Thin = above the slim bottom bar (~7); Default/Bordered = ~centred on the full bar (~2).
    local tVc    = (spec and spec.textVc) or ((style == 1) and 7 or 2)
    local vR     = (spec and spec.valueRight) or 4       -- value's right inset
    -- FIXED value-column width. The columns are anchor-based (value pinned to row-right, % to value-left,
    -- name flexes between), so a fixed width reflows SMOOTHLY/live as the window is dragged -- name+bar
    -- grow, % stays snug to the amount (no snap, no growing gap).
    row.value:SetWidth(VALUE_WIDTH)
    row.iconBG:SetSize(iconSz, iconSz); row.icon:SetSize(iconSz, iconSz)
    row.iconBG:ClearAllPoints(); row.iconBG:SetPoint("LEFT", row, "LEFT", indent, 0)
    row.icon:ClearAllPoints();   row.icon:SetPoint("CENTER", row.iconBG, "CENTER", 0, 0)
    row.bar:SetHeight(barH)
    row.bar:ClearAllPoints()
    if spec and spec.barLeft and spec.barRight then  -- copy the meter's exact bar location
        row.bar:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  spec.barLeft + indent, barOff)
        row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -spec.barRight,        barOff)
    else
        row.bar:SetPoint("BOTTOMLEFT",  row.iconBG, "BOTTOMRIGHT", 0, barOff)
        row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, barOff)
    end
    -- Columns right->left: % (far right), then value/total, then name flex -- matches the native order
    -- "value (total)  %".
    if row.percent then
        row.percent:ClearAllPoints(); row.percent:SetPoint("RIGHT", row, "RIGHT", -vR, tVc)
        row.value:ClearAllPoints();   row.value:SetPoint("RIGHT", row.percent, "LEFT", -COLUMN_GAP, 0)
    else
        row.value:ClearAllPoints();   row.value:SetPoint("RIGHT", row, "RIGHT", -vR, tVc)
    end
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, tVc)  -- gap from the icon
    if row.isPetHeader then
        local reservedRight = VALUE_WIDTH + 4 + expandIconWidth
            + (row.percent and (PERCENT_WIDTH + COLUMN_GAP) or 12)
        local avail = math.max(1, (row:GetWidth() or 1) - indent - ICON_SIZE - 4 - reservedRight)
        local textW = (row.name.GetStringWidth and row.name:GetStringWidth()) or avail
        row.name:SetWidth(math.max(1, math.min(textW, avail)))
        row.expandIcon:ClearAllPoints(); row.expandIcon:SetPoint("LEFT", row.name, "RIGHT", 0, 0)
    else
        row.name:SetWidth(0)
        row.name:SetPoint("RIGHT", (row.value or row.percent), "LEFT", -COLUMN_GAP, 0)
        row.expandIcon:ClearAllPoints(); row.expandIcon:SetPoint("LEFT", row.icon, "RIGHT", 4, tVc)
    end
end

-- ─── Row factory ─────────────────────────────────────────────────────────────
local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame.content)
    row._inst = activeInst  -- which window this pooled row belongs to (set under the render's SetActive)
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
    row.bar:SetStatusBarTexture(GetSelectedBarTexture())
    row.bar:SetMinMaxValues(0,1); row.bar:SetValue(0)
    row.bar:SetStatusBarColor(classR,classG,classB,0.95); row.bar:SetHeight(BAR_HEIGHT)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT",  row.iconBG, "BOTTOMRIGHT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.barBG = row.bar:CreateTexture(nil,"BACKGROUND"); row.barBG:SetAllPoints()
    row.barBG:SetTexture(GetSelectedBarTexture())
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
        -- Re-tint to the focused combatant's class colour each render (bars are coloured once at creation,
        -- but the focus -- whose breakdown we show -- can change). Self = the player's own colour, as before.
        local r, g, b = GetFocusClassColor()
        if self.bar.SetStatusBarColor then self.bar:SetStatusBarColor(r, g, b, 0.95) end
        if self.barBG and self.barBG.SetVertexColor then self.barBG:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.45) end
    end

    row:SetScript("OnClick", function(self, button)
        SetActive(self._inst)
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
        ApplyRowIndent(row, 0, index); ApplyRowFonts(row); row:Show(); row:UpdateBar(frac)
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
            row.expandIcon:SetRotation(row.isExpanded and 0 or math.pi)  -- collapsed = up
            row.expandIcon:Show()
            row.name:SetText(tostring(entry.headerText or entry.displayName or entry.petName or "Pet"))
            if row.percent then row.percent:SetText(((st.cfg and st.cfg.numbers or 2) <= 0) and "" or FormatPercent(percentValue)) end
            row.value:SetText(st.fmtValue(rateAmount, totalAmount, viewInfo.showRate))
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
            if row.percent then row.percent:SetText(((st.cfg and st.cfg.numbers or 2) <= 0) and "" or FormatPercent(percentValue)) end
            row.value:SetText(st.fmtValue(rateAmount, totalAmount, viewInfo.showRate))
            row.bg:SetColorTexture(0,0,0,0)
        end
        ApplyRowIndent(row, indent, index); ApplyRowFonts(row); row:Show(); row:UpdateBar(percentFrac)
    end

    HideUnusedRows(visibleCount + 1)
    UpdateContentWidth(); frame.content:SetHeight(math.max(1, visibleCount * (ROW_HEIGHT + ROW_GAP)))
    ApplyAutoWindowHeight(visibleCount); UpdateContentWidth(); UpdateScrollBounds()
    if not skipDeferred then QueueDeferredRefresh() end
end

-- Enemy view = the EnemyDamageTaken meter type: enemies listed by total damage taken (your damage
-- when solo). Different shape from player-source views, so it has its own render. pcall-guarded for the
-- "secret value" protection; reads the meter's selected segment.
st.renderEnemies = function()
    local list = {}
    local CDM = C_DamageMeter
    local MT = Enum and Enum.DamageMeterType and Enum.DamageMeterType.EnemyDamageTaken
    if CDM and MT then
        pcall(function()
            local w = _G.DamageMeterSessionWindow1
            local sid = w and w.sessionID
            local info = sid and CDM.GetCombatSessionFromID and CDM.GetCombatSessionFromID(sid, MT)
            if not (type(info) == "table" and info.combatSources) and CDM.GetCombatSessionFromType then
                for _, t in ipairs({ SESSION_TYPE, 0, 2 }) do
                    local i = CDM.GetCombatSessionFromType(t, MT)
                    if type(i) == "table" and i.combatSources then info = i; break end
                end
            end
            if type(info) == "table" and type(info.combatSources) == "table" then
                for _, e in ipairs(info.combatSources) do
                    local okv, nm, tot = pcall(function() return tostring(e.name), (tonumber(e.totalAmount) or 0) + 0 end)
                    if okv and nm and tot and tot > 0 then list[#list + 1] = { name = nm, total = tot } end
                end
            end
        end)
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    st.lastEnemyCount = #list
    if #list == 0 then
        HideUnusedRows(1); UpdateContentWidth(); frame.content:SetHeight(1)
        ApplyAutoWindowHeight(0); UpdateContentWidth()
        frame.emptyText:SetText("-- No Targets --"); UpdateScrollBounds(); return
    end
    local top = list[1].total or 0
    local grand = 0; for _, t in ipairs(list) do grand = grand + t.total end
    frame.emptyText:SetText("")
    for index, t in ipairs(list) do
        local row = GetRow(index)
        local pct  = (grand > 0) and ((t.total / grand) * 100) or 0
        local frac = (top   > 0) and (t.total / top)          or 0
        row.isCustomTracker = false; row.customEntry = nil; row.isPetHeader = false; row.isExpanded = false
        row.spellID = nil; row.petName = nil; row.groupKey = nil; row.groupType = nil; row.viewKey = currentView
        row.totalAmount = t.total; row.rateAmount = 0; row.percentValue = pct; row.overkillAmount = 0
        row.headerText = t.name; row.castCount = nil; row.childCount = nil; row.parentPetName = nil
        row.icon:SetTexture(134400)  -- generic icon (enemies have no spell texture)
        row.expandIcon:Hide(); row.expandIcon:SetRotation(0)
        row.name:SetText(t.name)
        if row.percent then row.percent:SetText(((st.cfg and st.cfg.numbers or 2) <= 0) and "" or FormatPercent(pct)) end
        row.value:SetText(st.fmtValue(0, t.total, false))
        row.bg:SetColorTexture(0,0,0,0)
        ApplyRowIndent(row, 0, index); ApplyRowFonts(row); row:Show(); row:UpdateBar(frac)
    end
    HideUnusedRows(#list + 1)
    UpdateContentWidth(); frame.content:SetHeight(math.max(1, #list * (ROW_HEIGHT + ROW_GAP)))
    ApplyAutoWindowHeight(#list); UpdateContentWidth(); UpdateScrollBounds()
end

-- OPTIMISATION: invalidate the font path cache at the start of each pass so
-- ApplyRowFonts uses a single shared string rather than re-fetching per row.
RefreshDetails = function(skipDeferred)
    if not frame:IsShown() then return end
    InvalidateFontCache()
    RefreshNativeSpec()  -- copy the native bar's current size/shape before laying out rows
    st.refreshCfg()    -- mirror the meter's Edit Mode settings (BarHeight/Padding/etc.)
    -- BarHeight drives the row height; Padding drives the gap between rows (both follow the slider).
    ROW_HEIGHT = math.max(12, math.min((st.cfg and tonumber(st.cfg.barHeight)) or ROW_HEIGHT, 48))
    ROW_GAP    = math.max(0,  math.min((st.cfg and tonumber(st.cfg.padding))   or ROW_GAP,   12))
    local viewInfo = GetCurrentViewInfo()
    ApplyGSETrackerDetailsOpacity(); ApplyTitleBarFont()
    UpdateTitleBarText(); ApplyTitleBarClassColor()
    frame.emptyText:SetText(""); UpdateContentWidth()
    if currentView == "enemy" then
        st.renderEnemies(); UpdateWindowButtonVisuals(); return
    end
    if IsCustomView(currentView) then
        RenderCustomDetails(viewInfo); UpdateWindowButtonVisuals(); return
    end
    RenderStockDetails(viewInfo, skipDeferred)
    UpdateWindowButtonVisuals()
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function GSETrackerDetails_SetView(viewKey)
    currentView = NormalizeViewKey(viewKey)
    SaveGSETrackerDetailsWindowState(); UpdateTabVisuals()
    if frame:IsShown() then RefreshDetails() end
end

-- Show/Hide the CURRENTLY ACTIVE instance. OpenMine() selects a stock window's instance first; the
-- public wrappers below default to instance 1 (the primary window external callers mean).
local function ShowActiveInstance(viewKey)
    if not IsDetailsEnabled() then return end
    if not frame then return end
    local db = GetWindowDB(activeInst and activeInst.id)
    currentView = viewKey and NormalizeViewKey(viewKey) or NormalizeViewKey(db.viewKey)
    if activeInst then activeInst.currentView = currentView end
    if ShouldHideDetailsInCombat() and UnitAffectingCombat and UnitAffectingCombat("player") then
        db.wasShown = true
        GetGSETrackerDetailsDB().hideInCombat = true
        frame.hiddenForCombat = true
        frame.needsPostCombatRefresh = true
        SaveGSETrackerDetailsWindowState()
        return
    end
    ApplySavedWindowState(true); db.wasShown = true
    ApplyGSETrackerDetailsOpacity(); ApplyTitleBarFont(); UpdateTitleBarText()
    UpdateTitleBarClassIcon(); ApplyTitleBarClassColor()
    UpdateTabVisuals(); UpdateWindowButtonVisuals()
    frame.hiddenForCombat = false
    frame:Show(); frame:Raise()
    frame.needsPostCombatRefresh = true
    SaveGSETrackerDetailsWindowState(); RefreshDetails()
end
local function HideActiveInstance(syncDetailsOption)
    if not frame then return end
    local db = GetWindowDB(activeInst and activeInst.id); db.wasShown = false; SaveGSETrackerDetailsWindowState()
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

function GSETrackerDetails_Show(viewKey)
    SetActive(instances[1]); ShowActiveInstance(viewKey)
end

function GSETrackerDetails_Hide(syncDetailsOption)
    SetActive(instances[1]); HideActiveInstance(syncDetailsOption)
end

-- Close on focus-loss, like Blizzard's popups: a click anywhere that isn't the breakdown window (or
-- the meter, whose line-clicks drive it) closes it. Uses GLOBAL_MOUSE_DOWN, registered only while shown.
-- IMPORTANT: the DamageMeter is "secret"-protected -- calling meter:IsMouseOver() does a boolean test
-- on a secret value, which TAINTS the shared mouse-down dispatch and breaks Blizzard's own dropdowns.
-- So we detect "click is within X" by walking the mouse-focus frames by REFERENCE (==) only -- no
-- secret boolean tests, no taint.
st.focusWithin = function(root)
    if not root then return false end
    -- Walk a frame's parent chain looking for `root` by reference. Guard FORBIDDEN frames (e.g. the Shop/
    -- Store UI is protected -- calling :GetParent() on it from addon code throws "bad self") and pcall the
    -- GetParent call. A chain that can't be walked simply isn't our window, so treat it as "not within".
    local function chainHasRoot(cur)
        while cur do
            if cur == root then return true end
            if cur.IsForbidden and cur:IsForbidden() then return false end
            if not cur.GetParent then return false end
            local ok, parent = pcall(cur.GetParent, cur)
            if not ok then return false end
            cur = parent
        end
        return false
    end
    local foci = GetMouseFoci and GetMouseFoci()
    if type(foci) == "table" then
        for _, f in ipairs(foci) do
            if chainHasRoot(f) then return true end
        end
        return false
    end
    return chainHasRoot(GetMouseFocus and GetMouseFocus())
end
local clickAway = CreateFrame("Frame")
clickAway:SetScript("OnEvent", function()
    if st.suppressClickAway then st.suppressClickAway = false; return end  -- a category dropdown click
    if st.focusWithin(_G.DamageMeter) then return end  -- click on the meter (line-clicks drive us)
    -- Close any shown, unpinned window whose own frame (or its driving stock window) wasn't clicked.
    for _, ins in pairs(instances) do
        local f = ins.frame
        if f and f:IsShown() and not f.pinned
           and not st.focusWithin(f) and not st.focusWithin(ins.stockWindow) then
            SetActive(ins); HideActiveInstance(true)
        end
    end
end)
clickAway:RegisterEvent("GLOBAL_MOUSE_DOWN")  -- always on; the handler only acts on shown windows

function GSETrackerDetails_Refresh()
    for _, ins in pairs(instances) do if ins.frame and ins.frame:IsShown() then SetActive(ins); RefreshDetails() end end
end
function GSETrackerDetails_ApplyOpacity()  ApplyGSETrackerDetailsOpacity() end
function GSETrackerDetails_ToggleMinimized() ToggleMinimized()      end

local function ApplyCombatVisibilityActive()
    if not frame then return end
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    GetGSETrackerDetailsDB().hideInCombat = ShouldHideDetailsInCombat()
    local db = GetWindowDB(activeInst and activeInst.id)
    if inCombat then
        if ShouldHideDetailsInCombat() and IsDetailsEnabled() and frame:IsShown() then
            db.wasShown = true
            frame.hiddenForCombat = true
            frame.needsPostCombatRefresh = true
            frame.suppressDetailsOptionSync = true
            frame:Hide()
        elseif frame.hiddenForCombat and not ShouldHideDetailsInCombat() then
            frame.hiddenForCombat = false
            if IsDetailsEnabled() then ShowActiveInstance() end
        end
        return
    end
    if frame.hiddenForCombat then
        frame.hiddenForCombat = false
        if IsDetailsEnabled() then ShowActiveInstance() end
    end
end

function GSETrackerDetails_ApplyCombatVisibility()
    for _, ins in pairs(instances) do SetActive(ins); ApplyCombatVisibilityActive() end
end

-- ─── Click a stock-meter line -> open THIS breakdown instead of Blizzard's in-place drill-down ──────
-- The meter (DamageMeterSessionWindow1) stays fully visible. Clicking a line normally drills Window1
-- in place to Blizzard's spell breakdown; we REPLACE the line buttons' left-click so it opens our
-- window instead (right-click keeps Blizzard's original handler, e.g. its menu). Bars are pooled but
-- reused, so overriding the current set once persists; we re-scan to catch new ones. Out-of-combat
-- only (SetScript on a Blizzard frame is taint-safe there). Skipped under Details!.
-- Dock our window to the RIGHT side of the Blizzard meter so it follows the meter. Re-anchored on
-- each open; dragging our window detaches it until the next open.
local function AnchorToStockMeter(stockWin)
    local m = stockWin or _G.DamageMeter
    if type(m) ~= "table" or not m.IsShown or not m:IsShown() or not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", m, "TOPRIGHT", 2, 0)
    if frame.Raise then frame:Raise() end
end
-- Open the breakdown for stock meter window `stockId` (1..5): each gets its OWN window, built on first
-- use and anchored beside its own stock window.
local function OpenMine(stockId, focusGUID)
    if not st.isSkinnerMode() then return end  -- another source owns the breakdown
    stockId = tonumber(stockId) or 1
    local ins = instances[stockId] or BuildInstance(stockId)
    SetActive(ins)
    ins.focusGUID = focusGUID or nil  -- whose breakdown to show: a clicked combatant, or nil = the player
    local sw = _G["DamageMeterSessionWindow" .. stockId]
    ins.stockWindow = sw or _G.DamageMeter
    -- Open to the view matching the clicked window's meter type (DPS bar -> DPS view, HPS -> HPS, etc.).
    -- damageMeterType is a plain config field (not a "secret" value), so reading it is taint-safe.
    local mt = sw and (sw.damageMeterType or (sw.GetDamageMeterType and sw:GetDamageMeterType()))
    ShowActiveInstance(ViewKeyForMeterType(mt))
    -- Anchor ONCE (first ever open), beside this window's own stock window, then remember: subsequent
    -- opens restore the saved position (ShowActiveInstance) and we DON'T re-anchor, so wherever the user
    -- drags each window's breakdown sticks. Pinned windows are never re-anchored either.
    local wdb = GetWindowDB(stockId)
    if not frame.pinned and not wdb.placed then
        AnchorToStockMeter(ins.stockWindow)  -- position: anchor once, then remember the user's drag
        wdb.placed = true
    end
    -- Height: ALWAYS open at the clicked window's height (or LESS if our content is shorter); overflow
    -- scrolls. The height is never remembered -- every open re-matches the stock window. Only out of
    -- combat: a protected meter frame's geometry is a "secret" value mid-fight (arithmetic would taint),
    -- so during combat we leave the height alone.
    if not frame.pinned then
        local swH = sw and not (InCombatLockdown and InCombatLockdown()) and sw:GetHeight()
        if type(swH) == "number" and swH > 0 then
            local chrome = TITLE_BAR_TOP + TITLE_BAR_HEIGHT + TITLE_BAR_GAP + EDGE_PADDING + BOTTOM_SAFE_PAD
            frame:SetHeight(Clamp(math.min(swH, (frame.content:GetHeight() or 0) + chrome), MIN_HEIGHT, MAX_HEIGHT))
        end
    end
    SaveGSETrackerDetailsWindowState()
end

-- Blizzard re-assigns the line buttons' OnClick on every meter refresh, so a one-time override gets
-- wiped. Re-assert ours whenever Blizzard's is back: BOTH left- and right-click open OUR window (skipping
-- the stock in-place drill-down and its right-click menu). We only SetScript when the current handler
-- isn't ours, so it's not a per-tick churn. Skipped under Details!.
local _origClick = setmetatable({}, { __mode = "k" })
-- Pull the COMBATANT GUID off a clicked stock-meter row so the breakdown can focus that player. The
-- stock meter is a modern ScrollBox, so the data is most likely on the row's element data; we also try
-- direct fields the bar may stash. Returns nil if none resolve -> the breakdown harmlessly shows self.
-- NOTE: the exact field name is best-effort (verified visually, but the meter internals can shift between
-- builds); _G.GSETrackerDetails_LastClickedRow is left as a diagnostic handle to confirm/extend this.
local function ResolveRowGUID(b)
    if type(b) ~= "table" then return nil end
    local function fromData(d)
        if type(d) ~= "table" then return nil end
        local g = d.sourceGUID or d.guid or d.unitGUID or d.actorGUID or d.GUID
        if g then return g end
        if type(d.combatSource) == "table" then return d.combatSource.sourceGUID or d.combatSource.guid end
        if d.unit and UnitGUID then return UnitGUID(d.unit) end
        return nil
    end
    if b.GetElementData then
        local ok, d = pcall(b.GetElementData, b)
        if ok then local g = fromData(d); if g then return g end end
    end
    local g = b.sourceGUID or b.guid or b.unitGUID or b.actorGUID
    if g then return g end
    if type(b.combatSource) == "table" then g = b.combatSource.sourceGUID or b.combatSource.guid; if g then return g end end
    if type(b.data) == "table" then g = fromData(b.data); if g then return g end end
    if b.unit and UnitGUID then return UnitGUID(b.unit) end
    return nil
end
local function MyLineClick(self, button, down)
    -- BOTH left- and right-click open OUR breakdown focused on the clicked combatant, replacing the stock
    -- meter's in-place drill-down (left) AND its right-click drill/menu (user wants ours on right too).
    _G.GSETrackerDetails_LastClickedRow = self  -- diagnostic handle (confirm the source-GUID field in-game)
    -- Open the window tied to the stock meter window that was clicked, focused on the clicked combatant
    -- (their own row -> their GUID -> shows them; nil if unresolved -> shows the player, as before).
    OpenMine(self._gsetStockId or 1, ResolveRowGUID(self))
end
-- A real data ROW is a Button that contains a StatusBar (the bar fill). The title-bar controls
-- (Settings cog, minimize, the icon cluster) are Buttons WITHOUT a StatusBar -- never override those,
-- or clicking Settings/etc. would open+anchor our window.
local function IsBarRowButton(b)
    if not (b.GetObjectType and b:GetObjectType() == "Button" and b.GetChildren) then return false end
    for _, ch in ipairs({ b:GetChildren() }) do
        if ch.GetObjectType and ch:GetObjectType() == "StatusBar" then return true end
    end
    return false
end
local function AssertLineOverrides()
    if not st.isSkinnerMode() then return end  -- only hijack native line-clicks when OUR window is the source
    local function scan(f, d, stockId)
        if not f or d > 6 or not f.GetChildren then return end
        for _, c in ipairs({ f:GetChildren() }) do
            if c.GetScript and c.SetScript and IsBarRowButton(c) then
                c._gsetStockId = stockId  -- tag which stock window this row belongs to (routes the click)
                local cur = c:GetScript("OnClick")
                if cur ~= MyLineClick then
                    if cur then _origClick[c] = cur end  -- remember Blizzard's (kept, currently unused)
                    c:SetScript("OnClick", MyLineClick)
                    -- Ensure BOTH buttons reach our OnClick so right-click opens our breakdown too.
                    if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
                end
            end
            scan(c, d + 1, stockId)
        end
    end
    -- WoW can have several stock meter windows open at once (DamageMeterSessionWindow1/2/3...).
    -- Hook the rows in EVERY shown window, tagging each with its window id so clicks route to that
    -- window's own breakdown.
    for i = 1, 5 do
        local sw = _G["DamageMeterSessionWindow" .. i]
        if type(sw) == "table" and sw.GetChildren and sw.IsShown and sw:IsShown() then
            scan(sw, 0, i)
        end
    end
end
local _lineAccum = 0
local lineDriver = CreateFrame("Frame")
lineDriver:SetScript("OnUpdate", function(_, e)
    _lineAccum = _lineAccum + (e or 0)
    if _lineAccum < 0.2 then return end
    _lineAccum = 0
    AssertLineOverrides()
    -- Keep the copied native-bar geometry fresh, then refresh when the meter's selected segment
    -- changes (its window's sessionID flips) or its Edit Mode "Style" (which resizes the bar) changes.
    RefreshNativeSpec()
    local w = _G.DamageMeterSessionWindow1
    local sid = w and w.sessionID
    local style = GetMeterStyle()
    local barH = st.spec and st.spec.barH
    local fsz  = st.spec and st.spec.fontSize
    if sid ~= st.lastSession or style ~= st.lastStyle or barH ~= st.lastBarH or fsz ~= st.lastFont then
        st.lastSession = sid
        st.lastStyle = style
        st.lastBarH = barH
        st.lastFont = fsz
        for _, ins in pairs(instances) do
            if ins.frame and ins.frame:IsShown() then SetActive(ins); RefreshDetails() end
        end
    end
end)

-- Restore window state on login/reload: instance 1 always; plus any OTHER window that was PINNED last
-- session (pinned windows persist + reopen; unpinned ones start closed and rebuild on the next click).
local function RestoreAllWindows()
    SetActive(instances[1]); ApplyInitialWindowState()
    local db = GetGSETrackerDetailsDB()
    if type(db.windows) == "table" then
        for id, w in pairs(db.windows) do
            if id ~= 1 and w and w.pinned then
                local ins = instances[id] or BuildInstance(id)
                SetActive(ins); ApplyInitialWindowState()
            end
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
        GSETrackerDetails_ApplyCombatVisibility()
        for _, ins in pairs(instances) do SetActive(ins); TryPendingPostCombatRefresh(true) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        GSETrackerDetails_ApplyCombatVisibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        _detailsDB = nil   -- force re-init of DB cache
        RestoreAllWindows()
        GSETrackerDetails_ApplyCombatVisibility()
        for _, ins in pairs(instances) do
            if ins.frame and ins.frame:IsShown() and not ins.frame.isMinimized then SetActive(ins); QueueDeferredRefresh() end
        end
    elseif event == "PLAYER_CAMPING" then
        for _, ins in pairs(instances) do
            SetActive(ins)
            if frame:IsShown() then HideActiveInstance()
            else local db = GetWindowDB(ins.id); db.wasShown = false; SaveGSETrackerDetailsWindowState() end
        end
    elseif event == "PLAYER_LOGOUT" then
        for _, ins in pairs(instances) do SetActive(ins); SaveGSETrackerDetailsWindowState() end
    end
end)

if not USE_STOCK_SPECIAL_VIEWS then
    -- Midnight (12.0+) blocks addon registration for CLEU, so only keep the
    -- legacy custom tracker on older clients where the event is still allowed.
    local combatLogFrame = CreateFrame("Frame")
    combatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    combatLogFrame:SetScript("OnEvent", function()
        local changed = HandleCustomCombatLogEvent()
        if changed then
            for _, ins in pairs(instances) do
                if ins.frame and ins.frame:IsShown() and IsCustomView(ins.currentView) then
                    SetActive(ins); QueueDeferredRefresh()
                end
            end
        end
    end)
end

-- ─── Startup ─────────────────────────────────────────────────────────────────
InitGSETrackerDetailsDB()
RestoreAllWindows()
SetActive(instances[1])
ApplyGSETrackerDetailsOpacity()
ApplyTitleBarFont()
UpdateTitleBarText()
UpdateTitleBarClassIcon()
ApplyTitleBarClassColor()
UpdateTabVisuals()

if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
        if not frame then return end
        RestoreAllWindows()
    end)
end

SLASH_GSETRACKERDETAILS1 = "/gsetrackerdetails"
SlashCmdList.GSETRACKERDETAILS = function()
    GSETrackerDetails_Show(DEFAULT_VIEW)
end

--@do-not-package@
-- ── Dev-only diagnostics (NOT shipped) ───────────────────────────────────────
-- /getdefault, /getprd, /emz are maintainer debugging dumpers. The BigWigs packager strips everything
-- between @do-not-package@ / @end-do-not-package@ from the CurseForge build, so end users never get these
-- in their slash namespace -- but they stay in the repo and load/run in the dev client (run from source).
-- /getdefault -- dump the native Blizzard DamageMeter's real geometry (Edit Mode size settings + one
-- bar entry's height, icon/bar sizes and font sizes) so the breakdown rows can copy the exact default
-- sizes/shapes. Retail-only (needs C_DamageMeter's DamageMeter frame, meter must be enabled).
SLASH_GETDEFAULT1 = "/getdefault"
SlashCmdList.GETDEFAULT = function()
    local function p(...) print("|cff66ccff[GetDefault]|r", ...) end
    local function dims(o)
        return string.format("%.1fw x %.1fh", (o.GetWidth and o:GetWidth()) or 0, (o.GetHeight and o:GetHeight()) or 0)
    end
    local f = _G.DamageMeter
    if not f then p("DamageMeter frame not found -- enable the meter in Settings > Gameplay (Retail)."); return end

    -- 1) Edit Mode size settings (the "official" sizes).
    local E = Enum and Enum.EditModeDamageMeterSetting
    if E and f.GetSettingValue then
        for _, k in ipairs({ "Style", "BarHeight", "TextSize", "Padding", "FrameWidth", "FrameHeight", "ShowSpecIcon", "ShowClassColor" }) do
            if E[k] ~= nil then
                local ok, v = pcall(f.GetSettingValue, f, E[k])
                p("setting", k, "=", ok and tostring(v) or "?")
            end
        end
    end

    -- 2) Hunt the first StatusBar in the meter's descendant tree -- that's a bar row's fill. Its
    --    parent is the row; report the row + bar sizes, where the bar sits, the icon and the fonts.
    local win = _G.DamageMeterSessionWindow1
    if not win then p("no session window (DamageMeterSessionWindow1)."); return end
    local found
    local function walk(fr, d)
        if found or d > 6 or not fr.GetChildren then return end
        for _, c in ipairs({ fr:GetChildren() }) do
            if c.GetObjectType and c:GetObjectType() == "StatusBar" then found = c; return end
            walk(c, d + 1)
            if found then return end
        end
    end
    walk(win, 0)
    if not found then p("no StatusBar found -- need a populated segment (get into combat / pick a segment)."); return end

    local bar = found
    local row = bar:GetParent()
    -- L/R = left/right inset from the row edges; Vc = vertical-centre offset from the row centre.
    local function loc(o)
        if not (o.GetLeft and o:GetLeft() and row:GetLeft()) then return "" end
        return string.format("L=%.1f R=%.1f Vc=%.1f",
            o:GetLeft() - row:GetLeft(), row:GetRight() - o:GetRight(),
            ((o:GetTop() + o:GetBottom()) / 2) - ((row:GetTop() + row:GetBottom()) / 2))
    end
    p("ROW", row:GetObjectType(), dims(row))
    p("BAR", dims(bar), loc(bar), string.format("bottomGap=%.1f",
        (bar:GetBottom() or 0) - (row:GetBottom() or 0)))
    local function dumpRegions(obj, prefix)
        for _, r in ipairs({ obj:GetRegions() }) do
            local t, extra = r:GetObjectType(), ""
            if t == "FontString" and r.GetFont then
                local _, sz = r:GetFont()
                extra = "font=" .. tostring(sz) .. (r.GetText and (" '" .. tostring(r:GetText()) .. "'") or "")
            elseif t == "Texture" then
                extra = (r.GetAtlas and r:GetAtlas() and ("atlas=" .. r:GetAtlas())) or "tex"
            end
            p(prefix, t, dims(r), loc(r), extra)
        end
    end
    dumpRegions(row, "  rowregion")
    for _, s in ipairs({ row:GetChildren() }) do
        p("  rowchild", s:GetObjectType(), dims(s), loc(s))
        dumpRegions(s, "    sub")
    end
    -- The bar's own fill texture + its child regions: rounded end caps come from either the
    -- statusbar texture's atlas, a mask, or separate overlay cap textures on the bar.
    local sbt = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if sbt then
        p("  STATUSBARTEX",
            "atlas=" .. tostring((sbt.GetAtlas and sbt:GetAtlas()) or "-"),
            "tex=" .. tostring((sbt.GetTexture and sbt:GetTexture()) or "-"),
            "masks=" .. tostring((sbt.GetNumMaskTextures and sbt:GetNumMaskTextures()) or "?"))
    end
    dumpRegions(bar, "  barreg")
end

-- /getprd -- dump the Personal Resource Display's real frame + Edit Mode wiring so the PRD lock
-- (ui/personal_resource.lua) can be written against the actual protected frame, not a guess. Enable the
-- PRD first (Interface > Names > "Personal Resource Display", or set nameplateShowSelf 1) so it exists.
SLASH_GETPRD1 = "/getprd"
SlashCmdList.GETPRD = function()
    local function p(...) print("|cff66ccff[GetPRD]|r", ...) end
    p("cvar nameplateShowSelf =", tostring(GetCVar and GetCVar("nameplateShowSelf")))

    -- 1) The PRD nameplate (the player's own nameplate). Only exists while shown.
    local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
    if not np then
        p("no player nameplate -- enable the PRD and stand so it's visible, then rerun.")
    else
        p("nameplate", np:GetName() or "(anon)", string.format("%.0fx%.0f", np:GetWidth() or 0, np:GetHeight() or 0))
        local point, rel, relPoint, x, y = np:GetPoint(1)
        local relName = rel and (rel.GetName and rel:GetName()) or tostring(rel)
        p("  point", tostring(point), "->", tostring(relName), tostring(relPoint), string.format("%.1f,%.1f", x or 0, y or 0))
        p("  parent", (np:GetParent() and np:GetParent():GetName()) or "(anon)",
            "movable=" .. tostring(np.IsMovable and np:IsMovable()),
            "protected=" .. tostring(np.IsProtected and select(1, np:IsProtected())))
        local uf = np.UnitFrame
        if uf then p("  .UnitFrame", uf:GetName() or "(anon)", uf.GetObjectType and uf:GetObjectType() or "?") end
    end

    -- 1b) Anchor vs visible-bars delta: how far the PRD system frame's CENTER is from the cell anchor we
    -- pin it to, and from the visible bars (nameplate/UnitFrame). The vertical delta is the Y offset the
    -- lock needs so the BARS (not the frame centre) land on the grid cell.
    local prd = _G.PersonalResourceDisplayFrame
    if prd and prd.GetCenter then
        local fx, fy = prd:GetCenter()
        p(string.format("PRDFrame %.0fx%.0f centre=(%.0f,%.0f)", prd:GetWidth() or 0, prd:GetHeight() or 0, fx or 0, fy or 0))
        local bar = np and (np.UnitFrame or np)
        if bar and bar.GetCenter then
            local bx, by = bar:GetCenter()
            if fy and by then p(string.format("  bars centre=(%.0f,%.0f)  deltaY(bars-frame)=%.1f", bx or 0, by or 0, by - fy)) end
        end
        local cell = _G.GSETracker_PRDCell
        if cell and cell.GetCenter then
            local cx, cy = cell:GetCenter()
            if fy and cy then p(string.format("  cell centre=(%.0f,%.0f)  deltaY(cell-frame)=%.1f", cx or 0, cy or 0, cy - fy)) end
        end
    end

    -- 1c) Where is the Meters cluster the cell is supposed to hug? If the cell is far from MetersAnchor the
    -- cell offset is wrong; if MetersAnchor itself is at top-right the cluster moved, not the cell.
    local ma = _G.MetersAnchor
    if ma and ma.GetCenter then
        local mx, my = ma:GetCenter()
        p(string.format("MetersAnchor %.0fx%.0f centre=(%.0f,%.0f) shown=%s",
            ma:GetWidth() or 0, ma:GetHeight() or 0, mx or 0, my or 0, tostring(ma:IsShown())))
        local cell = _G.GSETracker_PRDCell
        if cell and cell.GetCenter then
            local cx, cy = cell:GetCenter()
            if mx and cx then p(string.format("  cell offset from anchor = (%.1f, %.1f)", cx - mx, cy - my)) end
        end
    end

    -- 1d) Hunt the green name. Walk the PRD frame's whole tree for FontStrings showing the player's name,
    -- and report each one's owner/parent + position -- that's the fontstring we'd hide to kill the double.
    local myName = UnitName and UnitName("player")
    local prdf = _G.PersonalResourceDisplayFrame
    if prdf and myName then
        local hits = 0
        local function walk(fr, depth)
            if not fr or depth > 6 then return end
            if fr.GetRegions then
                for _, r in ipairs({ fr:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "FontString" then
                        local t = r.GetText and r:GetText()
                        if t and tostring(t):find(myName, 1, true) then
                            hits = hits + 1
                            local owner = fr.GetName and fr:GetName() or "(anon)"
                            local cx, cy = r.GetCenter and r:GetCenter()
                            p(string.format("  NAME fontstring '%s' in %s @ (%.0f,%.0f) shown=%s", tostring(t), owner,
                                cx or 0, cy or 0, tostring(r.IsShown and r:IsShown())))
                        end
                    end
                end
            end
            if fr.GetChildren then for _, c in ipairs({ fr:GetChildren() }) do walk(c, depth + 1) end end
        end
        walk(prdf, 0)
        if hits == 0 then p("  no name fontstring found under PersonalResourceDisplayFrame (it's elsewhere)") end
    end

    -- 2) NamePlateDriverFrame + any global frame whose name mentions the PRD.
    local drv = _G.NamePlateDriverFrame
    p("NamePlateDriverFrame =", drv and (drv:GetName() or "(anon)") or "nil")
    for _, n in ipairs({ "NamePlatePlayerResourceFrame", "ClassNameplateBar", "NamePlateDriverFrame",
        "PersonalResourceDisplayFrame", "EditModeSystemSelectionPersonalResourceDisplay" }) do
        if _G[n] then p("  global", n, "exists", _G[n].GetObjectType and _G[n]:GetObjectType() or "?") end
    end

    -- 3) Edit Mode: is the PRD a registered system, and what enum/index is it?
    local mgr = _G.EditModeManagerFrame
    if not mgr or not mgr.registeredSystemFrames then
        p("EditModeManagerFrame.registeredSystemFrames not available.")
    else
        for _, f in ipairs(mgr.registeredSystemFrames) do
            local name = (f.GetName and f:GetName()) or "(anon)"
            if name:lower():find("resource") or name:lower():find("nameplate") or name:lower():find("prd") then
                p("  EMsystem", name, "system=" .. tostring(f.system), "index=" .. tostring(f.systemIndex))
            end
        end
        p("(scanned", #mgr.registeredSystemFrames, "Edit Mode systems for resource/nameplate)")
    end
    if Enum and Enum.EditModeSystem then
        for k, v in pairs(Enum.EditModeSystem) do
            if tostring(k):lower():find("resource") or tostring(k):lower():find("nameplate") then
                p("  Enum.EditModeSystem", k, "=", v)
            end
        end
    end
end

-- /emz -- dump EVERY registered Edit Mode system's selection overlay (strata/level/size/shown) so we can
-- see why the PRD + Encounter Bar selections don't restack with the others. Run while Edit Mode is open.
SLASH_EMZ1 = "/emz"
SlashCmdList.EMZ = function()
    local function p(...) print("|cff66ccff[EMZ]|r", ...) end
    local mgr = _G.EditModeManagerFrame
    if not (mgr and mgr.registeredSystemFrames) then p("no registeredSystemFrames"); return end
    for _, f in ipairs(mgr.registeredSystemFrames) do
        local nm = (f.GetName and f:GetName()) or "(anon)"
        local sysShown = f.IsShown and f:IsShown()
        local sel = f.Selection
        if sel and sel.GetFrameStrata then
            p(string.format("%s sys=%s shown=%s | Sel strata=%s lvl=%s size=%.0fx%.0f selShown=%s top=%s",
                nm, tostring(f.system), tostring(sysShown),
                tostring(sel:GetFrameStrata()), tostring(sel:GetFrameLevel()),
                sel:GetWidth() or 0, sel:GetHeight() or 0,
                tostring(sel.IsShown and sel:IsShown()), tostring(sel.IsToplevel and sel:IsToplevel())))
        else
            p(string.format("%s sys=%s shown=%s | NO .Selection (sel=%s)", nm, tostring(f.system), tostring(sysShown), tostring(sel)))
        end
    end
end

-- /gsetcdmgr -- TEMP: dump Blizzard's Cooldown Manager (C_CooldownViewer) categories + their spells, so we
-- can build the Retail cooldown picker straight from Blizzard's curated per-spec lists (Essential/Utility).
SLASH_GSETCDMGR1 = "/gsetcdmgr"
SlashCmdList.GSETCDMGR = function()
    local function p(...) print("|cff66ccff[CDMgr]|r", ...) end
    if not (C_CooldownViewer and Enum and Enum.CooldownViewerCategory) then
        p("C_CooldownViewer / Enum.CooldownViewerCategory not available (Retail only)"); return
    end
    local fns = {}
    for k in pairs(C_CooldownViewer) do fns[#fns + 1] = k end
    table.sort(fns)
    p("C_CooldownViewer fns: " .. table.concat(fns, ", "))
    for catName, catVal in pairs(Enum.CooldownViewerCategory) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, catVal)
        if ok and type(ids) == "table" then
            p(string.format("== %s (=%s): %d ==", tostring(catName), tostring(catVal), #ids))
            for _, cid in ipairs(ids) do
                local oki, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
                if oki and type(info) == "table" then
                    local sid = info.spellID or info.overrideSpellID
                    local nm = sid and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                    p(string.format("  cid=%s spellID=%s %s", tostring(cid), tostring(sid), tostring(nm or "?")))
                else
                    p(string.format("  cid=%s (no info)", tostring(cid)))
                end
            end
        else
            p(string.format("== %s (=%s): getter failed/empty ==", tostring(catName), tostring(catVal)))
        end
    end
end

-- /gsetcdlayout -- TEMP: dump the Cooldown viewer's Edit Mode LAYOUT settings (orientation / icon limit /
-- direction) + current values + which write methods the frame exposes, so we can drive wrap-at-7 and the
-- grow-from-edge behaviour taint-free.
SLASH_GSETCDLAYOUT1 = "/gsetcdlayout"
SlashCmdList.GSETCDLAYOUT = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local function p(...) print("|cff66ccff[CDLayout]|r", ...) end
    local f = _G.EssentialCooldownViewer
    if not f then p("EssentialCooldownViewer missing (Retail only)"); return end

    -- Dump the Orientation / IconDirection value enums so we can map L/R/U/D onto setting values.
    if Enum then
        for ename, etab in pairs(Enum) do
            if type(etab) == "table" and (ename:find("Orientation") or ename:find("IconDirection")
               or ename:find("CooldownViewer")) and not ename:find("EditMode") then
                local parts = {}
                for k, v in pairs(etab) do parts[#parts + 1] = k .. "=" .. tostring(v) end
                table.sort(parts)
                p(ename .. ": " .. table.concat(parts, ", "))
            end
        end
    end

    -- Edit Mode setting enum for cooldown viewers.
    local E = Enum and Enum.EditModeCooldownViewerSetting
    if E then
        local keys = {}
        for k in pairs(E) do keys[#keys + 1] = k end
        table.sort(keys)
        p("EditModeCooldownViewerSetting: " .. table.concat(keys, ", "))
        if f.GetSettingValue then
            for _, k in ipairs(keys) do
                local ok, v = pcall(f.GetSettingValue, f, E[k])
                p(string.format("  %s (=%s) = %s", k, tostring(E[k]), ok and tostring(v) or "?"))
            end
        else
            p("frame has NO GetSettingValue")
        end
    else
        p("Enum.EditModeCooldownViewerSetting NOT present")
    end

    -- Which methods can we use to change layout? Probe for the likely ones.
    local meths = { "SetSettingValue", "UpdateSystemSetting", "RefreshLayout", "Layout", "MarkDirty",
                    "GetOrientation", "SetOrientation", "GetNumItemsThatFit", "ApplySystemAnchor",
                    "UpdateSystemSettingOrientation", "UpdateSystemSettingIconLimit",
                    "UpdateSystemSettingIconDirection", "GetItemFrames", "GetItems" }
    local have = {}
    for _, m in ipairs(meths) do if type(f[m]) == "function" then have[#have + 1] = m end end
    p("frame methods present: " .. (#have > 0 and table.concat(have, ", ") or "(none of the probed set)"))

    -- Geometry + item count so we know what one icon costs and how many are live.
    p(string.format("viewer size = %.0f x %.0f  point=%s",
        f:GetWidth() or 0, f:GetHeight() or 0, tostring(select(1, f:GetPoint()))))
    if f.GetNumItems then local ok, n = pcall(f.GetNumItems, f); p("GetNumItems = " .. (ok and tostring(n) or "?")) end
    if f.GetItemFrames then local ok, t = pcall(f.GetItemFrames, f); p("GetItemFrames count = " .. (ok and type(t)=="table" and tostring(#t) or "?")) end

    -- Where does GetSettingValue read from? Dump the likely backing store.
    p("settingMap type = " .. type(f.settingMap))
    if E and type(f.settingMap) == "table" then
        local il = f.settingMap[E.IconLimit]
        p("settingMap[IconLimit] = " .. type(il) .. "  .value=" .. (type(il)=="table" and tostring(il.value) or "?"))
    end

    -- Edit Mode ANCHOR (the green emblem + "forced placement"). systemInfo.anchorInfo drives ApplySystemAnchor.
    p("--- anchor ---")
    p("systemInfo type = " .. type(f.systemInfo))
    local ai = type(f.systemInfo) == "table" and f.systemInfo.anchorInfo
    if type(ai) == "table" then
        p(string.format("anchorInfo: point=%s relTo=%s relPoint=%s x=%s y=%s",
            tostring(ai.point), tostring(ai.relativeTo), tostring(ai.relativePoint),
            tostring(ai.offsetX), tostring(ai.offsetY)))
    else
        p("anchorInfo = " .. tostring(ai))
    end
    -- Probe anchor-related methods + the selection/emblem object.
    local am = { "ApplySystemAnchor", "GetSettingsAnchorPoint", "SetupSettingsDialogAnchor", "BreakFromAnchoring",
                 "AnchorSelectionToParent", "ClearFrameSnap", "OnDragStart", "OnDragStop", "UpdateMagnetismRegistration" }
    local ah = {}
    for _, m in ipairs(am) do if type(f[m]) == "function" then ah[#ah + 1] = m end end
    p("anchor methods: " .. (#ah > 0 and table.concat(ah, ", ") or "(none probed)"))

    -- The green ⊕ nub is Blizzard's Edit Mode Selection. Dump it so we can find what positions the nub.
    p("--- selection (run in Edit Mode) ---")
    local sel = f.Selection
    p("Selection type = " .. type(sel))
    if type(sel) == "table" then
        if sel.GetNumPoints then
            for i = 1, (sel:GetNumPoints() or 0) do
                local pt, rel, relP, x, y = sel:GetPoint(i)
                p(string.format("  point %d: %s -> %s %s (%s, %s)", i, tostring(pt),
                    tostring(rel and rel.GetName and rel:GetName() or rel), tostring(relP), tostring(x), tostring(y)))
            end
        end
        -- named sub-objects (the nub/anchor texture/button live here)
        for k, v in pairs(sel) do
            if type(v) == "table" and v.GetObjectType then
                local oqk = pcall(function() return v:GetObjectType() end)
                local pt = v.GetPoint and select(1, v:GetPoint())
                p(string.format("  .%s = %s  point=%s shown=%s", tostring(k),
                    (oqk and v:GetObjectType()) or "?", tostring(pt), tostring(v.IsShown and v:IsShown())))
            end
        end
        -- CHILD FRAMES (the nub may be an unnamed child of the Selection)
        local function dumpKids(obj, tag)
            if not (obj and obj.GetChildren) then return end
            for _, c in ipairs({ obj:GetChildren() }) do
                local nm = c.GetName and c:GetName()
                local pt = c.GetPoint and select(1, c:GetPoint())
                p(string.format("  %s-child: %s type=%s point=%s w=%.0f shown=%s", tag, tostring(nm or "(anon)"),
                    c.GetObjectType and c:GetObjectType() or "?", tostring(pt),
                    (c.GetWidth and c:GetWidth()) or 0, tostring(c.IsShown and c:IsShown())))
            end
        end
        dumpKids(sel, "Sel")
    end
    -- Look for a TAINT-SAFE way to open the cooldown settings (NOT SelectSystem, which taints Edit Mode).
    p("--- settings openers ---")
    p("CooldownViewerSettings = " .. type(_G.CooldownViewerSettings))
    if type(_G.CooldownViewerSettings) == "table" then
        for _, m in ipairs({ "Show", "Open", "SetShown", "Toggle", "OpenSettings" }) do
            p("  CVS:" .. m .. " = " .. type(_G.CooldownViewerSettings[m]))
        end
    end
    p("Settings.OpenToCategory = " .. type(Settings and Settings.OpenToCategory))
    p("CooldownManagerSettings = " .. type(_G.CooldownManagerSettings))
    -- registered Settings categories whose name mentions cooldown
    if Settings and Settings.GetCategoryList then
        local ok, cats = pcall(Settings.GetCategoryList)
        if ok and type(cats) == "table" then
            for _, c in ipairs(cats) do
                local nm = c.GetName and c:GetName()
                if nm and nm:lower():find("cooldown") then
                    p(string.format("  Settings category: '%s' id=%s", nm, tostring(c.GetID and c:GetID())))
                end
            end
        end
    end

    -- The nub might be a child of the VIEWER, or Blizzard's shared magnetism indicator.
    p("EditModeMagnetismManager = " .. type(_G.EditModeMagnetismManager))
    if f.GetChildren then
        for _, c in ipairs({ f:GetChildren() }) do
            local nm = c.GetName and c:GetName()
            if not (nm and (nm:find("CooldownID") or nm:find("Item"))) then
                p(string.format("  Viewer-child: %s type=%s point=%s shown=%s", tostring(nm or "(anon)"),
                    c.GetObjectType and c:GetObjectType() or "?", tostring(c.GetPoint and select(1, c:GetPoint())),
                    tostring(c.IsShown and c:IsShown())))
            end
        end
    end

    -- "/gsetcdlayout set" -> LIVE write-test: force IconLimit to 5 via settingMap + the Update method, then
    -- report whether GetSettingValue + the rendered width actually changed. Dev-only; out of combat only.
    if msg == "set" and E and not InCombatLockdown() then
        local before = f:GetWidth()
        if type(f.settingMap) == "table" and f.settingMap[E.IconLimit] then
            f.settingMap[E.IconLimit].value = 5
        end
        if f.UpdateSystemSettingIconLimit then pcall(f.UpdateSystemSettingIconLimit, f) end
        if f.Layout then pcall(f.Layout, f) end
        local ok, after = pcall(f.GetSettingValue, f, E.IconLimit)
        p(string.format("WRITE TEST: IconLimit now=%s  width %.0f -> %.0f", ok and tostring(after) or "?", before, f:GetWidth()))
    end
end
--@end-do-not-package@
