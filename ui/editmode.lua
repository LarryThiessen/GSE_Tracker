-- ui/editmode.lua
-- Bridge Blizzard's Edit Mode to GSE_Tracker's "editing" state. Entering Edit Mode unlocks + shows the
-- HUD frames (Action Tracker, Assisted Highlight, Pressed Indicator, player tracker) so they can be
-- dragged into place; leaving it re-locks them (each frame's own drag handler saves its position on
-- drop). This simply drives `addon._editingOptions` -- the unlock/show infrastructure those frames
-- already honor -- so no per-frame plumbing is needed here.
--
-- Retail-only: Edit Mode (EventRegistry "EditMode.Enter"/"EditMode.Exit") doesn't exist on Classic, so
-- on those clients this module registers nothing and is a no-op.

local addonName, ns = ...
local addon = ns

-- Re-apply visibility + drag/marker state on every GSE_Tracker HUD frame after the editing flag flips.
-- All are UI methods (ns.UI); each reads addon._editingOptions and updates itself. pcall-guarded so a
-- missing method on some flavor can never error the Edit Mode transition.
local function RefreshEditing()
    local UI = ns.UI
    if not UI then return end
    if UI.ApplyVisibility               then pcall(UI.ApplyVisibility, UI) end             -- show/hide (honors editing preview)
    if UI.RefreshDragMouseState         then pcall(UI.RefreshDragMouseState, UI) end       -- Action Tracker drag
    if UI.ApplyEditModeIconPreview      then pcall(UI.ApplyEditModeIconPreview, UI, true) end
    if UI.UpdateActionTrackerMoveMarker then pcall(UI.UpdateActionTrackerMoveMarker, UI) end
    if UI.RefreshAssistedHighlight      then pcall(UI.RefreshAssistedHighlight, UI, true) end
    if UI.RefreshPressedIndicator       then pcall(UI.RefreshPressedIndicator, UI, true) end
    -- On Edit Mode ENTER, the icon row can be un-built (e.g. it was Locked), so the example icons don't
    -- appear until a layout change forces a rebuild. Do that rebuild ourselves (deferred a tick so
    -- visibility/size have settled) -- RebuildIcons re-applies the preview. Only while editing.
    if addon._editingOptions and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon._editingOptions and UI.RebuildIcons then pcall(UI.RebuildIcons, UI, true) end
        end)
    end
end

-- A Blizzard-style Edit Mode selection box (cyan outline + label) drawn around one of our frames while
-- Edit Mode is open, so our HUD elements look/feel like the default UI's editable frames. The box is a
-- child of the target, so it inherits the target's visibility automatically.
-- ── Native Edit Mode selection box ───────────────────────────────────────────
-- Use Blizzard's REAL Edit Mode selection widget (EditModeSystemSelectionTemplate) -- the exact box +
-- "Click to Edit" label the default UI draws around editable frames. Wired like LibEditMode: a .system
-- shim provides the label (required 11.2+), OnMouseDown selects + opens our options dialog, drag moves
-- the parent frame and saves via its own OnDragStop.
-- The EditModeSystemSelectionTemplate draws its system-name label as a FontString in its region/child
-- tree. Find it (the only one with non-empty text) so we can hide it and only show it on hover.
local function FindSelectionLabel(f)
    if not f then return nil end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText and (r:GetText() or "") ~= "" then
            return r
        end
    end
    for _, c in ipairs({ f:GetChildren() }) do
        local x = FindSelectionLabel(c); if x then return x end
    end
    return nil
end

-- ── Arrow-key nudging (mirrors Blizzard Edit Mode) ───────────────────────────
-- Each HUD element persists its position differently, so nudge through the element's OWN position API --
-- NOT the frame's OnDragStop (EndActionTrackerDrag requires an in-progress drag). 1px per arrow press.
local selectedBox  -- the box currently receiving arrow keys (only one at a time)

-- The Assisted Highlight is locked to the target portrait in "Target Portrait" mode (saved value kept as
-- "Target Nameplate"). It's auto-anchored there, so its box must NOT move (drag or arrow keys).
local function AHAnchoredToPortrait()
    return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
end
local function BoxMoveBlocked(box)
    return box and box._nudgeKind == "ah" and AHAnchoredToPortrait()
end

local function NudgeElement(kind, dx, dy)
    if kind == "ah" and AHAnchoredToPortrait() then return end  -- locked to the portrait; no nudging
    if kind == "actiontracker" then
        if not (addon.GetActionTrackerPoint and addon.SetActionTrackerPoint) then return end
        local p, rel, rp, x, y = addon:GetActionTrackerPoint()
        addon:SetActionTrackerPoint(p or "CENTER", rel or "UIParent", rp or "CENTER",
            (tonumber(x) or 0) + dx, (tonumber(y) or 0) + dy)
        if addon.ApplyActionTrackerPosition then pcall(addon.ApplyActionTrackerPosition, addon)
        elseif addon.ApplyAllElementPositions then pcall(addon.ApplyAllElementPositions, addon) end
    elseif kind == "meters" then
        local sv = _G.MetersSavedVars
        local x = (sv and tonumber(sv.x)) or 0
        local y = (sv and tonumber(sv.y)) or -15
        if _G.Meter_SetPosition then _G.Meter_SetPosition(x + dx, y + dy) end
    elseif kind == "ah" then
        if not (addon.GetAssistedHighlightOffset and addon.SetAssistedHighlightOffset) then return end
        local x, y = addon:GetAssistedHighlightOffset()
        addon:SetAssistedHighlightOffset((tonumber(x) or 0) + dx, (tonumber(y) or 0) + dy)
        if addon.RefreshAssistedHighlight then pcall(addon.RefreshAssistedHighlight, addon, true) end
    end
end

-- Make `box` the keyboard-focused selection (deselecting any previous) so arrow keys nudge ITS element.
local function SelectBox(box)
    if selectedBox and selectedBox ~= box then
        selectedBox.isSelected = false
        if selectedBox.ShowHighlighted then pcall(selectedBox.ShowHighlighted, selectedBox) end
        selectedBox:EnableKeyboard(false)
    end
    selectedBox = box
    box.isSelected = true
    if box.ShowSelected then pcall(box.ShowSelected, box, true) end
    if box.parent and box.parent.SetMovable then box.parent:SetMovable(true) end
    box:EnableKeyboard(true)
    box:SetPropagateKeyboardInput(true)  -- only the arrow keys are consumed (in OnKeyDown)
end

local function EnsureBox(frame, label, tabIndex)
    if not frame then return nil end
    local box = frame._gsetEditBox
    if not box then
        local ok
        ok, box = pcall(CreateFrame, "Frame", nil, frame, "EditModeSystemSelectionTemplate")
        if not (ok and box) then return nil end
        box:SetAllPoints(frame)
        -- Strata: pin to HIGH -- the strata our HUD readouts actually draw at (Meters.lua/GCD.lua/AHLight.lua
        -- all SetFrameStrata("HIGH")). We can't just inherit the parent: MetersAnchor drops itself to LOW
        -- whenever its options are open (Meters.lua "optionsOpen and LOW or HIGH"), but the readout frames
        -- keep their explicit HIGH -- so an inheriting box sinks below the numbers when the dialog opens.
        -- HIGH sits above all that content yet still below the option dialogs (DIALOG), which is what we want.
        box:SetFrameStrata("HIGH")
        box:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 20)  -- above the element's own children (icons, numbers)
        box.parent = frame
        -- Native selection label text = "Click to Edit". The template draws it centered + always-on; we
        -- make it MOUSEOVER-ONLY by hiding it after ShowHighlighted (see ShowBoxes) and toggling it on
        -- hover here. (No extra FontString of our own -- that stacked a 2nd label over the native one.)
        box.system = { GetSystemName = function() return "Click to Edit" end }  -- 11.2+ template requirement
        box:HookScript("OnEnter", function(s) if s._nativeLabel then s._nativeLabel:Show() end end)
        box:HookScript("OnLeave", function(s) if s._nativeLabel then s._nativeLabel:Hide() end end)
        box:EnableMouse(true); box:RegisterForDrag("LeftButton")
        box:SetScript("OnMouseDown", function(s)
            if InCombatLockdown and InCombatLockdown() then return end
            local EMM = _G.EditModeManagerFrame  -- clear Blizzard's own selection so it doesn't fight ours
            if EMM and EMM.ClearSelectedSystem then pcall(EMM.ClearSelectedSystem, EMM) end
            SelectBox(s)  -- select + take keyboard focus for arrow-key nudging
            if s._tab and _G.GSETracker_EditModeShowTab then _G.GSETracker_EditModeShowTab(s._tab) end
        end)
        -- Arrow-key nudge, like Blizzard's Edit Mode: move the selected element 1px per press; let every
        -- other key pass through (SetPropagateKeyboardInput) so movement/chat/etc. are unaffected.
        box:EnableKeyboard(false)
        box:SetScript("OnKeyDown", function(s, key)
            local dx, dy = 0, 0
            if     key == "UP"    then dy =  1
            elseif key == "DOWN"  then dy = -1
            elseif key == "LEFT"  then dx = -1
            elseif key == "RIGHT" then dx =  1
            else s:SetPropagateKeyboardInput(true); return end
            s:SetPropagateKeyboardInput(false)
            -- Match Blizzard: 1px per arrow press, 10px with Shift held.
            local step = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
            if s._nudgeKind then NudgeElement(s._nudgeKind, dx * step, dy * step) end
        end)
        box:SetScript("OnDragStart", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if BoxMoveBlocked(box) then return end  -- AH locked to the target portrait: no dragging
            if frame.SetMovable then frame:SetMovable(true) end
            if frame.StartMoving then frame:StartMoving() end
        end)
        box:SetScript("OnDragStop", function()
            if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
            local h = frame.GetScript and frame:GetScript("OnDragStop")  -- the frame's own save-on-drop
            if h then pcall(h, frame) end
        end)
        box:Hide()
        frame._gsetEditBox = box
    end
    box._tab = tabIndex
    box._label = label or ""
    return box
end

-- The Meters anchor is a fixed 320x120 container much larger than the visible readout cluster (and the
-- cluster shrank when the SBA % line moved out). Size the Meters box to the UNION of the visible readout
-- frames (icon/marker + GCD/DPS/HPS) plus a little padding, instead of the whole anchor. Falls back to
-- the full anchor if the children's screen rects aren't readable.
local function FitMetersBox(box, anchor)
    if not (box and anchor and anchor.GetLeft) then return end
    box:ClearAllPoints()
    -- The DPS/HPS readout geometry is a "secret" value (driven by C_DamageMeter); arithmetic/compares on
    -- it THROW while our (tainted) code runs. So do ALL the measurement inside pcall -- if it trips the
    -- secret-value guard, fall back to a fixed inset that approximates the cluster (NOT the full anchor).
    local ok = pcall(function()
        local aL, aR, aT, aB = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop(), anchor:GetBottom()
        if not (aL and aR and aT and aB) then error("noanchor") end
        local minL, maxR, maxT, minB
        local function add(c)
            if not (c and c.IsShown and c:IsShown() and c.GetLeft) then return end
            local w = c.GetWidth and c:GetWidth()
            if not w or w <= 1 then return end           -- (may throw on secret geometry -> pcall catches)
            local l, r, t, b = c:GetLeft(), c:GetRight(), c:GetTop(), c:GetBottom()
            if not (l and r and t and b) then return end
            minL = minL and math.min(minL, l) or l
            maxR = maxR and math.max(maxR, r) or r
            maxT = maxT and math.max(maxT, t) or t
            minB = minB and math.min(minB, b) or b
        end
        -- Measure the VISIBLE TEXT (tight to glyphs) + the centre icon, NOT the wide readout frames.
        add(_G.GCDFrame and _G.GCDFrame.gcdText)
        add(_G.DPSFrame and _G.DPSFrame.dpsText)
        add(_G.HPSFrame and _G.HPSFrame.hpsText)
        add(_G.AHLightFrame)   -- centre icon (Assisted Highlight mirror)
        add(_G.MarkerFrame)    -- centre icon (combat marker)
        if not minL then error("nokids") end
        local pad = 8
        -- Symmetric around the marker centre (= the anchor centre) on BOTH axes: centre->left == centre->
        -- right and centre->top == centre->bottom, for even padding. Use the larger half-extent each way
        -- so no content (numbers L/R, GCD above, icon below) is clipped.
        local centreX, centreY = (aL + aR) / 2, (aT + aB) / 2
        local halfW = math.max((maxR + pad) - centreX, centreX - (minL - pad))
        local halfH = math.max((maxT + pad) - centreY, centreY - (minB - pad))
        box:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     (centreX - halfW) - aL, (centreY + halfH) - aT)
        box:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", (centreX + halfW) - aR, (centreY - halfH) - aB)
    end)
    if not ok then
        -- Secret/unreadable geometry: a fixed inset that roughly hugs the readout cluster (the anchor is
        -- 320x120; the cluster is ~180x70 centred).
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT",     anchor, "TOPLEFT",      70, -25)
        box:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -70,  25)
    end
end

local function ShowBoxes(show)
    local UI = ns.UI
    local targets = {
        -- tab => opens that EDITMODE_TABS options pop-up on click (Meters=1, Action Tracker=2,
        -- Assisted Highlight=3). fit="meters" => shrink the box to the visible readout cluster.
        -- nudge => which element the arrow keys move when this box is selected.
        { frame = _G.GSE_TrackerFrame or (UI and UI.ui), label = "Action Tracker",     tab = 2, nudge = "actiontracker" },
        { frame = _G.MetersAnchor,                       label = "Meters",             tab = 1, fit = "meters", nudge = "meters" },
        { frame = addon.assistedHighlightFrame,          label = "Assisted Highlight", tab = 3, nudge = "ah" },
    }
    for _, t in ipairs(targets) do
        local box = EnsureBox(t.frame, t.label, t.tab)
        if box then
            box._nudgeKind = t.nudge
            if show then
                box:Show()
                if box.ShowHighlighted then pcall(box.ShowHighlighted, box) end  -- native highlight state
                -- The template's "Click to Edit" label is always-on; cache + hide it so it only shows on hover.
                box._nativeLabel = box._nativeLabel or FindSelectionLabel(box)
                if box._nativeLabel then box._nativeLabel:Hide() end
                -- Meters: shrink the box to the readout cluster. Deferred a tick so the preview layout
                -- (examples shown when unlocked) has settled and the child rects are final.
                if t.fit == "meters" and C_Timer and C_Timer.After then
                    local f = t.frame
                    C_Timer.After(0.05, function() if box:IsShown() then FitMetersBox(box, f) end end)
                end
            else
                box:Hide(); box.isSelected = false
                box:EnableKeyboard(false)  -- release arrow-key capture when Edit Mode closes
            end
        end
    end
    if not show then selectedBox = nil end
end

local function SetEditing(on)
    on = on and true or false
    if (addon._editingOptions and true or false) == on then return end
    addon._editingOptions = on
    RefreshEditing()
    -- Lock state follows Edit Mode: UNLOCKED while editing, LOCKED on exit. The HUD frames honor
    -- _editingOptions for dragging; the Meters readout cluster has its own lock, so flip it too.
    if _G.Meter_SetLocked then pcall(_G.Meter_SetLocked, not on) end
    ShowBoxes(on)
    -- The options dialog opens on a "Click To Edit" box click (GSETracker_EditModeShowTab); on exit we
    -- just hide it.
    if not on and _G.GSETracker_SetEditModeOptions then _G.GSETracker_SetEditModeOptions(false) end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local ER = _G.EventRegistry
    if not (ER and ER.RegisterCallback) then return end  -- Classic / no Edit Mode: nothing to bridge
    ER:RegisterCallback("EditMode.Enter", function() SetEditing(true)  end, addon)
    ER:RegisterCallback("EditMode.Exit",  function() SetEditing(false) end, addon)

    -- NOTE: do NOT hook EditModeManagerFrame:RevertAllChanges to factory-reset GSE_Tracker. Blizzard
    -- calls RevertAllChanges INTERNALLY (entering/leaving Edit Mode, layout changes), so the hook fired
    -- on its own and WIPED the user's SavedVariables. Removed -- data-loss bug (2026-06-22).

    -- If we log in while Edit Mode is already open (rare), sync immediately.
    local EMM = _G.EditModeManagerFrame
    if EMM and EMM.IsEditModeActive and EMM:IsEditModeActive() then SetEditing(true) end
end)
