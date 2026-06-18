-- Timer.lua (Optimized)

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

MetersSavedVars = MetersSavedVars or {}

local UPDATE_INTERVAL       = 0.10   -- text refresh rate
local STYLE_REFRESH_INTERVAL = 0.50  -- appearance / anchor re-check rate
local TITLE_TIMER_GAP       = 0

local inCombat      = false
local hasTimerValue = false
local combatStart   = 0
local combatDuration = 0
local timerElapsed  = 0
local styleElapsed  = 0
local isEmbedded    = false
local lastAnchorKey = nil
local lastAppearanceKey = nil

-- ─── Frame ────────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "TimerFrame", UIParent)
frame:SetSize(76, 24)
frame:SetFrameStrata("HIGH")
frame:SetFrameLevel(40)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

frame.bg = frame:CreateTexture(nil, "BACKGROUND")
frame.bg:SetAllPoints()
frame.bg:SetColorTexture(0, 0, 0, 0.20)

frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
frame.text:SetJustifyH("CENTER")
frame.text:SetJustifyV("MIDDLE")
frame.text:SetText("--:--")

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function Round(n)
    if not n then return 0 end
    return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end

local function GetNow()
    if GetTimePreciseSec then return GetTimePreciseSec() end
    return GetTime and GetTime() or 0
end

local function GetTimerDB()
    MetersSavedVars.Timer = MetersSavedVars.Timer or {}
    local db = MetersSavedVars.Timer
    if db.enabled      == nil then db.enabled      = true    end
    if db.point        == nil then db.point        = "CENTER" end
    if db.relativePoint == nil then db.relativePoint = "CENTER" end
    if db.x            == nil then db.x            = 0       end
    if db.y            == nil then db.y            = -60     end
    return db
end

local function IsLocked()
    return MetersSavedVars.locked ~= false
end

local function GetOpacity()
    local v = math.max(0, math.min(100, tonumber(MetersSavedVars.opacity) or 100))
    return v / 100
end

local function GetFontPath()
    local fontName = MetersSavedVars.fontType
    if LSM and fontName and LSM.IsValid and LSM:IsValid("font", fontName) then
        return LSM:Fetch("font", fontName)
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function GetFontSize()
    local db = GetTimerDB()
    local size = tonumber(db.fontSize) or tonumber(MetersSavedVars.fontSize) or 18
    return math.max(8, math.min(36, size))
end

local function HasLiveEnemyTarget()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

local function NormalizeShowWhen(value)
    if value == "Always"                         then return "Always"     end
    if value == "Has Target" or value == "HasTarget" then return "Has Target" end
    if value == "Combat"     or value == "In Combat" then return "Combat"     end
    if value == "Never"                          then return "Never"      end
    return "Always"
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function GetCombatDuration()
    if inCombat then return math.max(0, GetNow() - combatStart) end
    return math.max(0, combatDuration)
end

-- ─── Details frame helpers ────────────────────────────────────────────────────
local function GetDetailsFrame()
    if _G.Details_GetFrame then
        local ok, f = pcall(_G.Details_GetFrame)
        if ok and f then return f end
    end
    return _G.DetailsFrame
end

local function GetDetailsTimerAnchor()
    if _G.Details_GetTimerAnchor then
        local ok, a = pcall(_G.Details_GetTimerAnchor)
        if ok and a then return a end
    end
    local df = GetDetailsFrame()
    if df then
        return df.timerAnchor or df.minimizeButton or df.titleBar
    end
    return nil
end

-- ─── Position / appearance ────────────────────────────────────────────────────
local function GetFrameKey(targetFrame)
    if not targetFrame then
        return ""
    end
    if targetFrame.GetName then
        local name = targetFrame:GetName()
        if name then
            return name
        end
    end
    return tostring(targetFrame)
end

local function ApplyStandalonePosition()
    local db = GetTimerDB()
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
end

local function SavePosition(self)
    local db = GetTimerDB()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    db.point         = point        or "CENTER"
    db.relativePoint = relativePoint or "CENTER"
    db.x = Round(x or 0)
    db.y = Round(y or 0)
end

local function ApplyAnchorMode()
    local anchor = GetDetailsTimerAnchor()
    if anchor then
        local df = GetDetailsFrame()
        local anchorKey = table.concat({
            "embedded",
            GetFrameKey(anchor),
            GetFrameKey(df and df.minimizeButton),
            tostring(TITLE_TIMER_GAP),
        }, "\031")
        isEmbedded = true
        if lastAnchorKey == anchorKey then
            return
        end

        lastAnchorKey = anchorKey
        lastAppearanceKey = nil
        if frame:GetParent() ~= anchor then frame:SetParent(anchor) end
        frame:ClearAllPoints()
        if df and anchor == df.minimizeButton then
            frame:SetPoint("RIGHT", anchor, "LEFT", -4 + TITLE_TIMER_GAP, 0)
        else
            frame:SetPoint("CENTER", anchor, "CENTER", TITLE_TIMER_GAP, -2)
        end
        frame:SetClampedToScreen(false)
        frame:SetMovable(false)
        frame:SetFrameStrata(anchor:GetFrameStrata() or "HIGH")
        frame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 5)
        return
    end

    local db = GetTimerDB()
    local anchorKey = table.concat({
        "standalone",
        tostring(db.point or "CENTER"),
        tostring(db.relativePoint or "CENTER"),
        tostring(db.x or 0),
        tostring(db.y or 0),
    }, "\031")
    isEmbedded = false
    if lastAnchorKey == anchorKey then
        return
    end

    lastAnchorKey = anchorKey
    lastAppearanceKey = nil
    if frame:GetParent() ~= UIParent then frame:SetParent(UIParent) end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    ApplyStandalonePosition()
end

local function RefreshAppearance()
    local alpha    = GetOpacity()
    local fontPath = GetFontPath()
    local fontSize = GetFontSize()
    ApplyAnchorMode()

    local appearanceKey = table.concat({
        isEmbedded and "1" or "0",
        tostring(alpha),
        tostring(fontPath),
        tostring(fontSize),
        inCombat and "1" or "0",
    }, "\031")
    if lastAppearanceKey == appearanceKey then
        return
    end

    lastAppearanceKey = appearanceKey
    if isEmbedded then
        local width  = math.max(56, math.min(76, math.floor((fontSize * 3.8) + 0.5)))
        local height = math.max(18, fontSize + 6)
        frame:SetSize(width, height)
        frame.text:ClearAllPoints()
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame.text:SetJustifyH("CENTER")
        frame.bg:SetAlpha(0)
    else
        frame:SetSize(math.max(120, fontSize * 6), fontSize + 8)
        frame.text:ClearAllPoints()
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame.text:SetJustifyH("CENTER")
        frame.bg:SetAlpha(math.min(alpha, 1) * 0.35)
    end
    frame.text:SetFont(fontPath, fontSize, "OUTLINE")
    frame.text:SetAlpha(alpha)
    frame.text:SetTextColor(inCombat and 1 or 0.80, inCombat and 0.82 or 0.80, inCombat and 0.25 or 0.80, 1)
end

local function RefreshText()
    frame.text:SetText(hasTimerValue and FormatTime(GetCombatDuration()) or "--:--")
end

local function RefreshMouse()
    frame:EnableMouse(not isEmbedded and not IsLocked())
end

local function ShouldShowEmbedded()
    local df = GetDetailsFrame()
    return df and df:IsShown()
end

local function RefreshVisibility()
    local db = GetTimerDB()
    if not db.enabled then frame:Hide(); return end
    if isEmbedded then
        frame:SetShown(ShouldShowEmbedded())
        return
    end
    local showWhen = NormalizeShowWhen(MetersSavedVars.showWhen)
    if showWhen == "Never"                                        then frame:Hide(); return end
    if showWhen == "Combat"     and not InCombatLockdown()        then frame:Hide(); return end
    if showWhen == "Has Target" and not HasLiveEnemyTarget()      then frame:Hide(); return end
    frame:Show()
end

local function RefreshAll()
    RefreshAppearance()
    RefreshMouse()
    RefreshText()
    RefreshVisibility()
end

local function StartCombatTimer()
    inCombat       = true
    hasTimerValue  = true
    combatDuration = 0
    combatStart    = GetNow()
    RefreshAppearance()
    RefreshText()
    RefreshVisibility()
end

local function StopCombatTimer()
    if inCombat then combatDuration = math.max(0, GetNow() - combatStart) end
    inCombat = false
    RefreshAppearance()
    RefreshText()
    RefreshVisibility()
end

-- ─── Drag ────────────────────────────────────────────────────────────────────
frame:SetScript("OnDragStart", function(self)
    if isEmbedded or IsLocked() or InCombatLockdown() then return end
    self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
    if isEmbedded then return end
    self:StopMovingOrSizing()
    SavePosition(self)
    lastAnchorKey = nil
    lastAppearanceKey = nil
    ApplyStandalonePosition()
end)

-- ─── OnUpdate ────────────────────────────────────────────────────────────────
-- OPTIMISATION: text update (every 0.1 s) is cheap; appearance (every 0.2 s)
-- is expensive (pcall, GetDetailsFrame, SetFont…).  Both share one OnUpdate
-- but trigger at their own independent intervals.
frame:SetScript("OnUpdate", function(_, elapsed)
    timerElapsed = timerElapsed + elapsed
    if timerElapsed >= UPDATE_INTERVAL then
        timerElapsed = 0
        if inCombat then RefreshText() end
    end

    styleElapsed = styleElapsed + elapsed
    if styleElapsed >= STYLE_REFRESH_INTERVAL then
        styleElapsed = 0
        RefreshAppearance()
        RefreshMouse()
        RefreshVisibility()
    end
end)

-- ─── Events ───────────────────────────────────────────────────────────────────
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if InCombatLockdown() then
            StartCombatTimer()
        else
            inCombat      = false
            hasTimerValue = false
            combatDuration = 0
            combatStart    = 0
            RefreshAll()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        StartCombatTimer()
    elseif event == "PLAYER_REGEN_ENABLED" then
        StopCombatTimer()
    elseif event == "PLAYER_TARGET_CHANGED" then
        RefreshVisibility()
    end
end)

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

-- ─── Public API ───────────────────────────────────────────────────────────────
_G.Timer_RefreshAll      = RefreshAll
_G.Timer_RefreshVisibility = RefreshVisibility
_G.Timer_ResetPosition   = function()
    local db      = GetTimerDB()
    hasTimerValue = false
    inCombat      = false
    combatDuration = 0
    combatStart    = 0
    db.point         = "CENTER"
    db.relativePoint = "CENTER"
    db.x = 0
    db.y = -60
    lastAnchorKey = nil
    lastAppearanceKey = nil
    if not isEmbedded then ApplyStandalonePosition() end
    RefreshAll()
end
