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
-- Saved state used: MetersSavedVars.Details.wasShown (the Show/Hide-in-combat/Auto-reset toggles were removed)

local addonName, ns = ...

MetersSavedVars = MetersSavedVars or {}

local _hiddenForCombat = false  -- true while WE hid the window for "Hide in Combat"

local function InCombat()    return UnitAffectingCombat and UnitAffectingCombat("player") end
local function WantShown()   return true end   -- "Show Details" toggle removed: always available
local function HideInCombat() return false end -- "Hide Details in Combat" toggle removed
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

-- ── Meter source mode ────────────────────────────────────────────────────────────
-- The user picks WHICH meter shows the breakdown (Skinner panel, Edit Mode): the Details! addon,
-- our own GSE: Tracker Skinner window (Retail), or Blizzard's stock meter. Stored in
-- MetersSavedVars.meterMode = "details" | "skinner" | "blizzard". When unset we migrate to the old
-- auto-priority (Details! > Skinner > Blizzard), and we always clamp to what's actually available
-- (e.g. "details" with the addon missing, or "skinner" off Retail, falls back).
local function SkinnerAvailable()      return _G.GSETrackerDetails_Show ~= nil end
local function DetailsAddonAvailable() return _G.Details ~= nil end
function GSETracker_GetMeterMode()
    local m = MetersSavedVars and MetersSavedVars.meterMode
    if m ~= "details" and m ~= "skinner" and m ~= "blizzard" then
        if DetailsAddonAvailable() then m = "details"
        elseif SkinnerAvailable()  then m = "skinner"
        else m = "blizzard" end
    end
    if m == "details" and not DetailsAddonAvailable() then m = SkinnerAvailable() and "skinner" or "blizzard" end
    if m == "skinner" and not SkinnerAvailable() then m = "blizzard" end
    return m
end

-- ── Backend selection: routed by the chosen meterMode (falls back to the old priority if the chosen
-- backend isn't available). GSETrackerDetails (Retail-only) self-manages its own combat visibility,
-- so for that backend we just route Show/Hide to it.
local function GSETrackerDetailsActive()
    return SkinnerAvailable() and GSETracker_GetMeterMode() == "skinner"
end
local function WindowSetShown(show)
    local mode = GSETracker_GetMeterMode()
    if mode == "skinner" and SkinnerAvailable() then
        if show then _G.GSETrackerDetails_Show() else _G.GSETrackerDetails_Hide(false) end
        return true
    elseif mode == "details" and DetailsInstance() then
        return DetailsSetShown(show)
    elseif mode == "blizzard" then
        return BlizzSetShown(show)
    end
    -- chosen backend unavailable -> old priority
    if DetailsSetShown(show) then return true end
    if SkinnerAvailable() then
        if show then _G.GSETrackerDetails_Show() else _G.GSETrackerDetails_Hide(false) end
        return true
    end
    return BlizzSetShown(show)
end
local function WindowIsShown()
    local mode = GSETracker_GetMeterMode()
    if mode == "skinner" and SkinnerAvailable() and _G.GSETrackerDetailsFrame then
        return _G.GSETrackerDetailsFrame:IsShown() and true or false
    elseif mode == "details" and DetailsInstance() then
        return DetailsIsShown()
    elseif mode == "blizzard" and BlizzMeter() then
        return BlizzIsShown()
    end
    if DetailsInstance() then return DetailsIsShown() end
    if SkinnerAvailable() and _G.GSETrackerDetailsFrame then return _G.GSETrackerDetailsFrame:IsShown() and true or false end
    if BlizzMeter() then return BlizzIsShown() end
    return false
end

-- Switch meter source. Hides whichever BREAKDOWN WINDOW is no longer the choice (so we never leave the
-- Details! window and our Skinner window both up) and shows the newly-chosen one. The Blizzard stock
-- meter is the BASE meter (also what you click to open the Skinner breakdown), so we never force it
-- hidden here -- only "blizzard" mode owns its visibility via the Show Details toggle. Rejects
-- "details" when the addon isn't loaded.
function GSETracker_SetMeterMode(mode)
    if mode ~= "details" and mode ~= "skinner" and mode ~= "blizzard" then return end
    if mode == "details" and not DetailsAddonAvailable() then return end
    MetersSavedVars = MetersSavedVars or {}
    MetersSavedVars.meterMode = mode
    if mode ~= "skinner" and _G.GSETrackerDetails_Hide then pcall(_G.GSETrackerDetails_Hide, false) end
    if mode ~= "details" then DetailsSetShown(false) end
    if mode == "details" then DetailsSetShown(true) end   -- show Details! immediately on switch
end

-- ── Public API ──────────────────────────────────────────────────────────────────
function Details_Show()
    if GSETrackerDetailsActive() then MarkWasShown(true); _G.GSETrackerDetails_Show(); return end  -- self-handles in-combat
    _hiddenForCombat = false
    MarkWasShown(true)
    if HideInCombat() and InCombat() then
        _hiddenForCombat = true  -- defer; ApplyCombatVisibility re-shows after combat
        return
    end
    WindowSetShown(true)
end

function Details_Hide()
    if GSETrackerDetailsActive() then MarkWasShown(false); _G.GSETrackerDetails_Hide(false); return end
    _hiddenForCombat = false
    MarkWasShown(false)
    WindowSetShown(false)
end

function Details_ApplyCombatVisibility()
    if GSETrackerDetailsActive() then return end  -- GSETrackerDetails' own event frame manages its combat visibility
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

-- ── Combat events (show/restore around combat) ───────────────────────────────────
-- ("Auto Reset Details" option removed -- no auto-reset on combat start.)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    Details_ApplyCombatVisibility()
end)
