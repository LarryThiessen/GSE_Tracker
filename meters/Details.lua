-- meters/Details.lua
-- Details WINDOW control.
--
-- The old custom (C_DamageMeter-backed) breakdown window was REMOVED -- it duplicated what real
-- damage meters already do. "Show Details Window" now just opens/closes an EXTERNAL meter window,
-- in priority order:
--   1. the Details! Damage Meter addon's own window, if installed (any flavor); else
--   2. Blizzard's built-in damage meter frame ("DamageMeter") on Retail -- the player must enable
--      it first in Settings > Gameplay Enhancements (otherwise the frame doesn't exist); else
--   3. nothing.
--
-- DPS/HPS NUMBER readouts are unrelated to this file (see DPS.lua / HPS.lua): Retail uses Blizzard's
-- real-time C_DamageMeter, Classic uses the Details! addon.
--
-- Public API kept for callers (MetersOptions, settings_panel, shared):
--   Details_Show / Details_Hide / Details_ApplyCombatVisibility / RefreshDetails
-- Saved state used: MetersSavedVars.showDetails, .hideDetailsInCombat, .Details.wasShown

local addonName, ns = ...

MetersSavedVars = MetersSavedVars or {}

local _hiddenForCombat = false  -- true while WE hid the window for "Hide in Combat"

local function InCombat()    return UnitAffectingCombat and UnitAffectingCombat("player") end
local function WantShown()   return MetersSavedVars.showDetails ~= false end
local function HideInCombat() return MetersSavedVars.hideDetailsInCombat == true end
local function MarkWasShown(v)
    MetersSavedVars.Details = MetersSavedVars.Details or {}
    MetersSavedVars.Details.wasShown = v and true or false
end

-- ── Backend 1: the Details! addon's own window ──────────────────────────────────
-- Proven API (MoP-verified): Details:GetInstance(1) -> :ShowWindow() / :HideWindow() / :IsEnabled().
-- All pcall-guarded so a Details! API change can never error us.
local function DetailsInstance()
    local D = _G.Details
    if type(D) ~= "table" or type(D.GetInstance) ~= "function" then return nil end
    local ok, inst = pcall(D.GetInstance, D, 1)
    return (ok and type(inst) == "table") and inst or nil
end
local function DetailsSetShown(show)
    local inst = DetailsInstance()
    if not inst then return false end
    local fn = show and inst.ShowWindow or inst.HideWindow
    if type(fn) == "function" then pcall(fn, inst) end
    return true
end
local function DetailsIsShown()
    local inst = DetailsInstance()
    if inst and type(inst.IsEnabled) == "function" then
        local ok, v = pcall(inst.IsEnabled, inst)
        if ok then return v and true or false end
    end
    return false
end

-- ── Backend 2: Blizzard's built-in damage meter (global frame "DamageMeter") ────
-- Toggle via alpha (Show/Hide can auto-re-enable in combat). EnableMouse only out of combat so we
-- never touch a Blizzard frame's mouse state during combat (taint-safe). The frame only exists when
-- the player has enabled the meter in Settings.
local function BlizzMeter()
    local f = _G.DamageMeter
    return (type(f) == "table" and f.SetAlpha) and f or nil
end
local function BlizzSetShown(show)
    local f = BlizzMeter()
    if not f then return false end
    f:SetAlpha(show and 1 or 0)
    if not (InCombatLockdown and InCombatLockdown()) and f.EnableMouse then
        f:EnableMouse(show and true or false)
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do
                if c and c.EnableMouse then c:EnableMouse(show and true or false) end
            end
        end
    end
    return true
end
local function BlizzIsShown()
    local f = BlizzMeter()
    return f ~= nil and (f:GetAlpha() or 0) > 0
end

-- ── Backend selection: Details! first, then Blizzard ────────────────────────────
local function WindowSetShown(show)
    if DetailsSetShown(show) then return true end
    return BlizzSetShown(show)
end
local function WindowIsShown()
    if DetailsInstance() then return DetailsIsShown() end
    if BlizzMeter() then return BlizzIsShown() end
    return false
end

-- ── Public API ──────────────────────────────────────────────────────────────────
function Details_Show()
    _hiddenForCombat = false
    MarkWasShown(true)
    if HideInCombat() and InCombat() then
        _hiddenForCombat = true  -- defer; ApplyCombatVisibility re-shows after combat
        return
    end
    WindowSetShown(true)
end

function Details_Hide()
    _hiddenForCombat = false
    MarkWasShown(false)
    WindowSetShown(false)
end

function Details_ApplyCombatVisibility()
    if InCombat() then
        -- Hide during combat only if WE'll be the one to bring it back (don't fight the user's
        -- manual state otherwise).
        if HideInCombat() and WantShown() and WindowIsShown() then
            _hiddenForCombat = true
            WindowSetShown(false)
        end
    elseif _hiddenForCombat then
        _hiddenForCombat = false
        if WantShown() then WindowSetShown(true) end
    end
end

-- Custom window removed; Details! / Blizzard render their own windows, so nothing to refresh here.
-- Kept as a no-op because callers (settings_panel, shared) invoke it after font/skin changes.
function RefreshDetails() end

-- ── Auto Reset ───────────────────────────────────────────────────────────────────
-- "Auto Reset Details" -> wipe the meter at the start of each combat so it shows only the current
-- fight. Resets BOTH backends that are present: the Details! addon's current segment (its window)
-- AND Blizzard's C_DamageMeter sessions (the source for the Retail DPS/HPS readouts). Returns true
-- if it reset something.
function Meters_ResetMeter()
    local did = false
    local D = _G.Details
    if type(D) == "table" and type(D.ResetSingleCombatData) == "function" then
        pcall(D.ResetSingleCombatData, D); did = true
    end
    local CDM = _G.C_DamageMeter
    if CDM and type(CDM.ResetAllCombatSessions) == "function" then
        pcall(CDM.ResetAllCombatSessions); did = true
    end
    return did
end

-- ── Combat events (hide/show around combat + optional auto-reset) ─────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_REGEN_DISABLED" and MetersSavedVars.autoResetDetails and Meters_ResetMeter then
        Meters_ResetMeter()
    end
    Details_ApplyCombatVisibility()
end)
