local _, ns = ...
local addon = ns

-- ── Personal Resource Display (PRD) lock ────────────────────────────────────────
-- Locks Blizzard's Personal Resource Display to the "Personal Resource Bar" cell on the Meters Layout
-- Control grid. The PRD is the Edit Mode system Enum.EditModeSystem.PersonalResourceDisplay (== 21), frame
-- _G.PersonalResourceDisplayFrame -- but it's backed by a PROTECTED nameplate, so it can only be moved OUT
-- of combat (a combat-time move is blocked by the engine). We re-anchor it to the cell at safe moments
-- (login, leaving combat, the PRD nameplate (re)appearing, and on any grid change), so if Edit Mode or the
-- user drags it away it snaps back next safe moment -- that re-assertion IS the "lock".
--
-- Requirements for it to actually move: the PRD must be ENABLED (CVar nameplateShowSelf = 1) and set to a
-- FIXED position in Edit Mode (not world-following), otherwise the nameplate driver re-anchors it to your
-- character every frame and our SetPoint can't hold.
--
-- ponytail: runtime re-assert on events, no Edit Mode save calls (avoids Edit Mode taint). Add a throttled
-- OnUpdate backstop only if the driver is seen to fight it between events.

local PRD_NAME = "PersonalResourceDisplayFrame"

local applying, hooked, savedAnchor

-- Remember the PRD's own anchor the first time we move it, so we can put it back exactly where the player
-- had it (outside the tracker) when they remove it from the grid. Captured once per lock session; an empty
-- table means the engine positions it without persistent points (restore then just clears our anchor).
local function CaptureOriginalAnchor(f)
    if savedAnchor ~= nil then return end
    local pts, n = {}, (f.GetNumPoints and f:GetNumPoints()) or 0
    for i = 1, n do pts[i] = { f:GetPoint(i) } end
    savedAnchor = pts
end

local function ApplyLock()
    if applying then return end                                            -- guard against re-entry
    if not (_G.GSETracker_IsPRDSlotted and _G.GSETracker_IsPRDSlotted()) then return end
    if InCombatLockdown() then return end                                  -- can't touch a protected frame in combat
    local f    = _G[PRD_NAME]
    local cell = _G.GSETracker_PRDCell
    if not (f and cell and f.SetPoint) then return end
    applying = true
    CaptureOriginalAnchor(f)   -- snapshot the player's own position before we override it
    -- Anchor the PRD system frame directly to the cell anchor so it tracks the exact grid position.
    pcall(function()
        f:ClearAllPoints()
        f:SetPoint("CENTER", cell, "CENTER", 0, 0)
    end)
    applying = false
end
_G.GSETracker_LockPersonalResource = ApplyLock

-- Put the PRD back where the player had it before it was slotted (so it isn't left stuck at the tracker cell
-- for normal, outside-the-tracker use). Combat-guarded: the caller (SetEnabled) defers if in combat.
local function RestoreOriginalAnchor()
    local f = _G[PRD_NAME]
    if not (f and savedAnchor) then return end
    if InCombatLockdown() then return end
    applying = true
    pcall(function()
        f:ClearAllPoints()
        for _, p in ipairs(savedAnchor) do f:SetPoint(unpack(p)) end   -- empty -> left unanchored for the engine
    end)
    applying = false
    savedAnchor = nil
end

-- Mirror the Meters HUD's visibility onto the PRD while it's slotted there. We use SetAlpha (not Hide):
-- the PRD is a protected nameplate frame, so Hide/Show is blocked IN combat -- but Meters' "Combat" mode
-- shows/hides exactly on the combat transition, so alpha is the only lever that works for both. When the
-- PRD isn't in the HUD we restore full alpha and leave Blizzard to manage it. Called from
-- Meter_UpdateVisibility (every visibility recompute) and our own events.
local function MetersHudVisible()
    local a = _G.MetersAnchor
    return (a and a.IsShown and a:IsShown()) and true or false
end
local function SyncVisibility()
    local f = _G[PRD_NAME]
    if not f then return end
    local slotted = _G.GSETracker_IsPRDSlotted and _G.GSETracker_IsPRDSlotted()
    local a = (not slotted) and 1 or (MetersHudVisible() and 1 or 0)
    pcall(f.SetAlpha, f, a)
    local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
    if np then pcall(np.SetAlpha, np, a) end
end
_G.GSETracker_SyncPRDVisibility = SyncVisibility

-- Adding/removing the PRD grid element toggles Blizzard's PRD on/off (CVar nameplateShowSelf): clearing it
-- from the Layout Control hides the bar entirely; adding it shows it. The CVar is combat-protected, so defer
-- to PLAYER_REGEN_ENABLED if we're in combat. Only forced on explicit add/remove (and on login while
-- slotted) -- never while the element is absent, so a player who doesn't use it keeps their own setting.
local pendingEnable
local function SetEnabled(on)
    if InCombatLockdown() then pendingEnable = on and true or false; return end
    pendingEnable = nil
    pcall(SetCVar, "nameplateShowSelf", on and "1" or "0")
    if not on then RestoreOriginalAnchor() end   -- removed from the grid -> hand the PRD back to the player's spot
end
_G.GSETracker_SetPRDEnabled = SetEnabled

-- Re-assert our anchor whenever ANYTHING else repositions the PRD -- Edit Mode re-applying the system's
-- saved layout on load (the "reset to default" we were losing to), the nameplate driver, etc. The `applying`
-- guard stops our own SetPoint from recursing. Out-of-combat + slotted gating lives in ApplyLock.
-- ponytail: a SetPoint hook catches every reposition exactly when it happens -- no polling, no event race.
local function EnsureHook()
    if hooked then return end
    local f = _G[PRD_NAME]
    if not (f and f.SetPoint and hooksecurefunc) then return end
    hooked = true
    hooksecurefunc(f, "SetPoint", function() if not applying then ApplyLock() end end)
end

-- Re-assert at safe moments too. NAME_PLATE_UNIT_ADDED fires when the PRD nameplate (re)appears; the others
-- cover login/reload and the combat-time grid change we deferred above. Each also installs the hook once.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:SetScript("OnEvent", function(_, e, unit)
    if e == "NAME_PLATE_UNIT_ADDED" and unit ~= "player" then return end
    EnsureHook()
    if e == "PLAYER_ENTERING_WORLD" and _G.GSETracker_IsPRDSlotted and _G.GSETracker_IsPRDSlotted() then
        SetEnabled(true)                       -- keep Blizzard's PRD on while it's slotted in the HUD
    elseif e == "PLAYER_REGEN_ENABLED" and pendingEnable ~= nil then
        SetEnabled(pendingEnable)              -- apply a toggle that was deferred out of combat
    end
    ApplyLock()
    SyncVisibility()
end)
