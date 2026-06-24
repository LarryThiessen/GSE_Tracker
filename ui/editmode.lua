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

local function RefreshVerticalEditModeNames(UI)
    if UI and UI.RefreshVerticalEditModeNames then
        pcall(UI.RefreshVerticalEditModeNames, UI)
    elseif UI then
        if UI.UpdateIconNames then pcall(UI.UpdateIconNames, UI) end
        if UI._RefreshVerticalGSENameLabel then pcall(UI._RefreshVerticalGSENameLabel, UI) end
    end
end

local function ForceActionTrackerEditModeRender(UI)
    if not UI then return end
    if UI.BuildMainFrame then pcall(UI.BuildMainFrame, UI) end

    local ui = UI.ui
    if ui then
        -- Entering/leaving Edit Mode changes the desired row contents without a user-facing
        -- layout setting changing. Invalidate the cached render signatures so this first pass
        -- behaves like the layout swap that otherwise made the examples appear.
        ui._lastIconRebuildSig = nil
        ui._lastRenderPipelineSig = nil
    end

    if UI.RequestUIRebuild then
        pcall(UI.RequestUIRebuild, UI, "editMode")
    elseif UI.RebuildIcons then
        pcall(UI.RebuildIcons, UI, true)
    end

    if UI.ApplyEditModeIconPreview then pcall(UI.ApplyEditModeIconPreview, UI, true) end
    if UI.RefreshCombatOnlyElements and ui then
        pcall(UI.RefreshCombatOnlyElements, UI, ui._lastVisible ~= false, false)
    end
    -- FORCE the vertical per-icon spell names to populate now that the preview icons are placed (they
    -- show the "Spell Name" placeholder in Edit Mode) -- belt-and-suspenders after RefreshCombatOnlyElements.
    if UI.UpdateIconNames then pcall(UI.UpdateIconNames, UI) end
    RefreshVerticalEditModeNames(UI)
end

-- Re-apply visibility + drag/marker state on every GSE_Tracker HUD frame after the editing flag flips.
-- All are methods on the finalized addon (ns); each reads addon._editingOptions and updates itself. pcall-guarded so a
-- missing method on some flavor can never error the Edit Mode transition.
local function RefreshEditing()
    local UI = ns  -- finalized addon (ns:FinalizeAPI merges all modules); ns.UI alone lacks cross-module
                   -- methods like GetActionTrackerLayout (ns.Utils) -- driving off ns.UI made the vertical
                   -- name guard read nil and the Edit Mode name examples never built on open.
    if not UI then return end
    ForceActionTrackerEditModeRender(UI)
    if UI.ApplyVisibility               then pcall(UI.ApplyVisibility, UI) end             -- show/hide (honors editing preview)
    if UI.RefreshDragMouseState         then pcall(UI.RefreshDragMouseState, UI) end       -- Action Tracker drag
    if UI.ApplyEditModeIconPreview      then pcall(UI.ApplyEditModeIconPreview, UI, true) end
    if UI.UpdateActionTrackerMoveMarker then pcall(UI.UpdateActionTrackerMoveMarker, UI) end
    if UI.RefreshAssistedHighlight      then pcall(UI.RefreshAssistedHighlight, UI, true) end
    if UI.RefreshPressedIndicator       then pcall(UI.RefreshPressedIndicator, UI, true) end
    RefreshVerticalEditModeNames(UI)
    -- The synchronous preview apply above doesn't fully take on the same frame (the icon row isn't laid
    -- out yet). Defer a rebuild one tick -- and do it on BOTH enter AND exit (no editing guard): on ENTER
    -- it builds + shows the example icons; on EXIT it rebuilds to the LIVE row, clearing the examples.
    -- (RebuildIcons preserves _lastTextures, so example textures don't leak into the restore.)
    if C_Timer and C_Timer.After and UI.RebuildIcons then
        C_Timer.After(0, function() ForceActionTrackerEditModeRender(UI) end)
        C_Timer.After(0.05, function() ForceActionTrackerEditModeRender(UI) end)
        C_Timer.After(0.15, function() ForceActionTrackerEditModeRender(UI) end)
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
local editBoxes = {}  -- every selection box we create, so SelectBox can force keyboard off on all but one

-- Set true ONLY while our own box-click clears Blizzard's selection, so the ClearSelectedSystem hook
-- below doesn't close the panel we're in the middle of opening.
local suppressDeselectClose

-- Native Edit Mode behaviour: a system's settings panel is open ONLY while that system is the selected
-- one. Close our option pop-ups + drop our box's selected highlight whenever focus leaves it (selecting
-- another of our boxes, a Blizzard system, or an empty-space click that clears the selection).
local function CloseEditPanelsAndDeselect()
    if _G.GSETracker_SetEditModeOptions then pcall(_G.GSETracker_SetEditModeOptions, false) end
    if selectedBox then
        selectedBox.isSelected = false
        if selectedBox.ShowHighlighted then pcall(selectedBox.ShowHighlighted, selectedBox) end
        selectedBox:EnableKeyboard(false)
        selectedBox = nil
    end
end

-- The Assisted Highlight is locked to the target portrait in "Target Portrait" mode (saved value kept as
-- "Target Nameplate"). It's auto-anchored there, so its box must NOT move (drag or arrow keys).
local function AHAnchoredToPortrait()
    return addon.GetAssistedHighlightAnchorTarget and addon:GetAssistedHighlightAnchorTarget() == "Target Nameplate"
end
local function BoxMoveBlocked(box)
    return box and box._nudgeKind == "ah" and AHAnchoredToPortrait()
end

local function NudgeElement(kind, dx, dy)
    if InCombatLockdown and InCombatLockdown() then return end  -- combat-lock safety (Edit Mode open in combat)
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
        -- Must APPLY the new offset to the frame (RefreshAssistedHighlight only handles show/hide+render,
        -- so the saved offset never moved the icon -- that's why arrow nudging did nothing). Mirrors how
        -- the other elements call their Apply*Position. force=true so it re-anchors immediately.
        if addon.ApplyAssistedHighlightLayout then pcall(addon.ApplyAssistedHighlightLayout, addon, true)
        elseif addon.ApplyAssistedHighlightPosition then pcall(addon.ApplyAssistedHighlightPosition, addon, true) end
        if addon.RefreshAssistedHighlight then pcall(addon.RefreshAssistedHighlight, addon, true) end
    elseif kind == "pressedindicator" then
        if not (addon.GetElementLayout and addon.SetElementOffset) then return end
        local cfg = addon:GetElementLayout("pressedIndicator")
        local x = (type(cfg) == "table" and tonumber(cfg.x)) or 0
        local y = (type(cfg) == "table" and tonumber(cfg.y)) or 0
        addon:SetElementOffset("pressedIndicator", x + dx, y + dy)  -- SetElementOffset re-applies the position
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
    -- Exclusive keyboard: disable EVERY other box's keyboard so only this one receives arrows. The
    -- Pressed Indicator box is at DIALOG strata (top of the stack); if its keyboard were left on it would
    -- intercept all arrow keys no matter which box is selected (that was the "only PI moves" bug).
    for _, b in ipairs(editBoxes) do
        if b ~= box and b.EnableKeyboard then b:EnableKeyboard(false) end
    end
    box:EnableKeyboard(true)
    box:SetPropagateKeyboardInput(true)  -- only the arrow keys are consumed (in OnKeyDown)
end

-- Recolour the selection outline on OUR boxes (cFF00FFFF = cyan). Applied ONLY to GSE: Tracker boxes --
-- EnsureBox is the only place we create EditModeSystemSelectionTemplate frames, so Blizzard's own Edit Mode
-- systems are never touched. Tints every texture region (the outline art); the "Click to Edit" label is a
-- FontString, so it's unaffected. Re-applied via hooks because ShowHighlighted/ShowSelected reset the colour.
local BOX_BORDER_R, BOX_BORDER_G, BOX_BORDER_B = 0, 1, 1
local function TintGSEBox(box)
    if not box then return end
    local function walk(fr)
        if fr.GetRegions then
            for _, r in ipairs({ fr:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "Texture" and r.SetVertexColor then
                    r:SetVertexColor(BOX_BORDER_R, BOX_BORDER_G, BOX_BORDER_B)
                end
            end
        end
        if fr.GetChildren then
            for _, c in ipairs({ fr:GetChildren() }) do walk(c) end
        end
    end
    walk(box)
end

local function EnsureBox(frame, label, tabIndex, saveDrag)
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
        editBoxes[#editBoxes + 1] = box  -- register for SelectBox's exclusive-keyboard sweep
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
            suppressDeselectClose = true  -- our own deselect of Blizzard -- the hook must NOT close us here
            if EMM and EMM.ClearSelectedSystem then pcall(EMM.ClearSelectedSystem, EMM) end
            suppressDeselectClose = false
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
            if box._saveDrag then
                pcall(box._saveDrag)  -- per-target save (e.g. the Pressed Indicator stores an element offset)
            else
                local h = frame.GetScript and frame:GetScript("OnDragStop")  -- the frame's own save-on-drop
                if h then pcall(h, frame) end
            end
        end)
        -- Recolour the selection outline to cyan (cFF00FFFF). Re-apply on highlight/select (they reset it).
        TintGSEBox(box)
        if _G.hooksecurefunc then
            if box.ShowHighlighted then _G.hooksecurefunc(box, "ShowHighlighted", TintGSEBox) end
            if box.ShowSelected    then _G.hooksecurefunc(box, "ShowSelected",    TintGSEBox) end
        end
        box:Hide()
        frame._gsetEditBox = box
    end
    box._tab = tabIndex
    box._label = label or ""
    box._saveDrag = saveDrag
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
        -- +20 to the half-height -> the box grows 20px UP and 20px DOWN (40 taller overall), for headroom
        -- around the top/bottom readouts now that elements can sit in the corner cells.
        local halfH = math.max((maxT + pad) - centreY, centreY - (minB - pad)) + 20
        box:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     (centreX - halfW) - aL, (centreY + halfH) - aT)
        box:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", (centreX + halfW) - aR, (centreY - halfH) - aB)
    end)
    if not ok then
        -- Secret/unreadable geometry: a fixed inset that roughly hugs the readout cluster (the anchor is
        -- 320x120; the cluster is ~180x70 centred). Insets reduced 20 top/bottom to match the +40 height.
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT",     anchor, "TOPLEFT",      70, -5)
        box:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -70,  5)
    end
end

-- Fit the Action Tracker box (VERTICAL layout) around the ACTUAL rendered content + 5px on every side:
-- the icon column PLUS the per-icon spell-name labels (which hang well past the narrow frame), the GSE
-- name above, and MODKEYS below. The frame alone is only as wide as the icons, so SetAllPoints clipped
-- the side labels. All these are children of the tracker (same scale), so GetLeft/Right/Top/Bottom are
-- directly comparable. (No "secret" geometry here -- it's not C_DamageMeter sourced.)
local function FitActionTrackerBox(box, frame)
    if not (box and frame and frame.GetLeft) then return end
    local UI = ns  -- finalized addon (ns:FinalizeAPI merges all modules); ns.UI alone lacks cross-module
                   -- methods like GetActionTrackerLayout (ns.Utils) -- driving off ns.UI made the vertical
                   -- name guard read nil and the Edit Mode name examples never built on open.
    local ui = UI and UI.ui
    RefreshVerticalEditModeNames(UI)
    local aL, aR, aT, aB = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (aL and aR and aT and aB) then box:SetAllPoints(frame); return end
    local minL, maxR, maxT, minB = aL, aR, aT, aB
    local function add(c)
        if not (c and c.IsShown and c:IsShown() and c.GetLeft) then return end
        local l, r, t, b = c:GetLeft(), c:GetRight(), c:GetTop(), c:GetBottom()
        if not (l and r and t and b) then return end
        minL = math.min(minL, l); maxR = math.max(maxR, r); maxT = math.max(maxT, t); minB = math.min(minB, b)
    end
    if ui then
        add(ui.nameText2)                          -- GSE name (top)
        add(ui.nameText); add(ui.sequenceTextFrame) -- Spell name (above the column)
        add(ui.modifiersFrame); add(ui.modShift)   -- MODKEYS (below the column)
    end
    local pad = 5
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT",     frame, "TOPLEFT",     (minL - pad) - aL, (maxT + pad) - aT)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", (maxR + pad) - aR, (minB - pad) - aB)
end

-- Re-fit the Meters selection box to the cluster after the readouts/Marker are rearranged from the edit
-- panel (Meters.lua's Meter_SetElementSlot / Meter_ResetSlots call this). Only acts while the box is shown
-- (Edit Mode). Deferred a tick so the just-moved child frame rects are final before we measure them.
function _G.GSETracker_RefitMetersBox()
    local anchor = _G.MetersAnchor
    local box = anchor and anchor._gsetEditBox
    if not (box and box.IsShown and box:IsShown()) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function() if box:IsShown() then FitMetersBox(box, anchor) end end)
    else
        FitMetersBox(box, anchor)
    end
end

local function ShowBoxes(show)
    local UI = ns  -- finalized addon (ns:FinalizeAPI merges all modules); ns.UI alone lacks cross-module
                   -- methods like GetActionTrackerLayout (ns.Utils) -- driving off ns.UI made the vertical
                   -- name guard read nil and the Edit Mode name examples never built on open.
    local targets = {
        -- tab => opens that EDITMODE_TABS options pop-up on click (Meters=1, Action Tracker=2,
        -- Assisted Highlight=3). fit="meters" => shrink the box to the visible readout cluster.
        -- nudge => which element the arrow keys move when this box is selected.
        -- padVHorizontal: in HORIZONTAL layout the Sequence/Spell name rows sit above & below the icon
        -- row, outside the frame bounds, so SetAllPoints clipped them -- grow the box 10px top & bottom.
        { frame = _G.GSE_TrackerFrame or (UI and UI.ui), label = "Action Tracker",     tab = 2, nudge = "actiontracker", padVHorizontal = 20 },
        { frame = _G.MetersAnchor,                       label = "Meters",             tab = 1, fit = "meters", nudge = "meters" },
        { frame = addon.assistedHighlightFrame,          label = "Assisted Highlight", tab = 3, nudge = "ah" },
        -- Pressed Indicator: its own element now (tab 4). The box drag saves an ELEMENT offset (saveDrag),
        -- since the indicator is positioned relative to the Action Tracker, not by its own OnDragStop.
        -- The indicator frame is tiny (the symbol is only a few px) and it sits OVER the Action Tracker
        -- box, so its selection box was too small to grab AND was buried under the tracker's box. minBox =
        -- a comfortable minimum hit area centred on it; raise = lift it above the other (HIGH) boxes so an
        -- overlapping box can't swallow its clicks/mouseover.
        { frame = (UI and UI.ui and UI.ui.pressedIndicator), label = "Pressed Indicator", tab = 4, nudge = "pressedindicator",
          minBox = 48, raise = true,
          saveDrag = function()
            if addon.StorePressedIndicatorDragOffset_Internal then addon:StorePressedIndicatorDragOffset_Internal() end
            if addon.ApplyElementPosition then addon:ApplyElementPosition("pressedIndicator") end
          end },
    }
    for _, t in ipairs(targets) do
        local box = EnsureBox(t.frame, t.label, t.tab, t.saveDrag)
        if box then
            box._nudgeKind = t.nudge
            if show then
                box:Show()
                -- Start every non-selected box with keyboard OFF so no stray box (esp. the DIALOG-strata
                -- Pressed Indicator box) holds arrow-key focus before the user clicks one.
                if box ~= selectedBox and box.EnableKeyboard then box:EnableKeyboard(false) end
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
                -- Grow the box vertically in HORIZONTAL layout so the name rows above/below the icon row
                -- (which sit outside the frame bounds) are enclosed. Vertical layout puts the names in
                -- side columns, so it keeps the plain SetAllPoints fit.
                if t.padVHorizontal then
                    local horizontal = (addon.GetActionTrackerLayout and addon:GetActionTrackerLayout() or "HORIZONTAL") ~= "VERTICAL"
                    box:ClearAllPoints()
                    if horizontal then
                        box:SetPoint("TOPLEFT",     t.frame, "TOPLEFT",      0,  t.padVHorizontal)
                        box:SetPoint("BOTTOMRIGHT", t.frame, "BOTTOMRIGHT",  0, -t.padVHorizontal)
                    else
                        -- VERTICAL: the per-icon name labels hang past the narrow frame, so fit the box to
                        -- the ACTUAL content (icons + GSE name + per-icon names + MODKEYS) + 5px. Deferred a
                        -- tick so the labels are laid out before we measure; SetAllPoints in the meantime.
                        box:SetAllPoints(t.frame)
                        local f = t.frame
                        if C_Timer and C_Timer.After then
                            C_Timer.After(0.05, function() if box:IsShown() then FitActionTrackerBox(box, f) end end)
                        else
                            FitActionTrackerBox(box, f)
                        end
                    end
                end
                -- Minimum hit area: a small element (e.g. the Pressed Indicator) gives a near-unclickable
                -- box. Re-anchor centred on the frame at >= minBox so it's easy to mouse over/grab; the box
                -- still follows the frame on drag (OnDragStart moves the frame, the box is anchored to it).
                if t.minBox then
                    local f = t.frame
                    local mw = math.max((f.GetWidth and f:GetWidth()) or 0, t.minBox)
                    local mh = math.max((f.GetHeight and f:GetHeight()) or 0, t.minBox)
                    box:ClearAllPoints()
                    box:SetPoint("CENTER", f, "CENTER", 0, 0)
                    box:SetSize(mw, mh)
                end
                -- Raise above overlapping selection boxes -- including BLIZZARD'S own edit-mode systems
                -- (e.g. the Possess Bar the indicator may sit over), which park their selections above
                -- HIGH. DIALOG wins that, but we keep the level (150) BELOW our own option pop-up window
                -- (GSETrackerEditWin, DIALOG level 200) so clicking the box still opens the panel on top.
                if t.raise then
                    box:SetFrameStrata("DIALOG")
                    box:SetFrameLevel(150)
                end
            else
                box:Hide(); box.isSelected = false
                box:EnableKeyboard(false)  -- release arrow-key capture when Edit Mode closes
            end
        end
    end
    if not show then selectedBox = nil end

    -- While Edit Mode is open, silence the Pressed Indicator's GLOBAL key monitor (ui/indicator.lua's
    -- addon._inputMonitor: EnableKeyboard(true) + propagating). Otherwise it competes for arrow-key focus
    -- with the selection boxes -- the Pressed Indicator box (raised to DIALOG/150) won the arrows so ONLY
    -- it nudged, while it also lit up on every keypress. Disabling the monitor lets arrows reach whichever
    -- box is selected. Restored on exit (only out of combat -- the EnableKeyboard call is combat-sensitive).
    local mon = addon._inputMonitor
    if mon and mon.EnableKeyboard then
        if show then
            mon:EnableKeyboard(false)
        elseif not (InCombatLockdown and InCombatLockdown()) then
            mon:EnableKeyboard(true)
        end
    end
end

-- Lock/unlock ALL GSE_Tracker frames at once (was the removed "Lock All" option). Lock state is now
-- driven purely by Edit Mode: unlocked while editing, locked otherwise.
local function SetAllLocked(locked)
    locked = locked and true or false
    if addon.SetLocked then pcall(addon.SetLocked, addon, locked) end
    if addon.SetCombatMarkerLocked then pcall(addon.SetCombatMarkerLocked, addon, locked) end
    if addon.SetAssistedHighlightLocked then pcall(addon.SetAssistedHighlightLocked, addon, locked) end
    if _G.MetersSavedVars then _G.MetersSavedVars.locked = locked end
    if _G.Meter_SetLocked then pcall(_G.Meter_SetLocked, locked) end
end

-- ESC-to-exit for the standalone (Settings-button) edit overlay. A hidden, UISpecialFrames-registered
-- frame: pressing Escape hides it -> OnHide exits our edit overlay, exactly like ESC leaves native Edit Mode.
local escCatcher
local function EnsureEscCatcher()
    if escCatcher then return escCatcher end
    escCatcher = CreateFrame("Frame", "GSETrackerEditModeEscapeCatcher", UIParent)
    escCatcher:Hide()
    escCatcher:SetScript("OnHide", function()
        if addon._editingOptions then SetEditing(false) end  -- ESC pressed while editing -> leave
    end)
    if type(_G.UISpecialFrames) == "table" then
        tinsert(_G.UISpecialFrames, "GSETrackerEditModeEscapeCatcher")
    end
    return escCatcher
end

function SetEditing(on)
    on = on and true or false
    if (addon._editingOptions and true or false) == on then return end
    addon._editingOptions = on
    -- Lock state follows Edit Mode: UNLOCKED while editing, LOCKED on exit (every GSE_Tracker frame).
    SetAllLocked(not on)
    RefreshEditing()
    ShowBoxes(on)
    -- The options dialog opens on a "Click To Edit" box click (GSETracker_EditModeShowTab); on exit we
    -- just hide it.
    if not on and _G.GSETracker_SetEditModeOptions then _G.GSETracker_SetEditModeOptions(false) end
    -- Drop the ESC catcher when leaving (any exit path: ESC, Blizzard Edit Mode exit, our toggle).
    if not on and escCatcher and escCatcher:IsShown() then escCatcher:Hide() end
end

-- Taint-free entry for the Settings "Edit Mode" button. We deliberately do NOT call Blizzard's
-- EditModeManagerFrame:EnterEditMode(): from addon (tainted) code it reaches the PROTECTED TargetUnit()
-- in RefreshTargetAndFocus and throws ADDON_ACTION_FORBIDDEN. Instead we drive OUR own edit overlay --
-- the selection boxes, element option panels and placement preview -- which touch no protected APIs.
function _G.GSETracker_EnterEditMode()
    if InCombatLockdown and InCombatLockdown() then return end
    EnsureEscCatcher()
    SetEditing(true)
    if escCatcher then escCatcher:Show() end  -- arm ESC-to-exit
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local ER = _G.EventRegistry
    if not (ER and ER.RegisterCallback) then return end  -- Classic / no Edit Mode: nothing to bridge
    ER:RegisterCallback("EditMode.Enter", function() SetEditing(true)  end, addon)
    ER:RegisterCallback("EditMode.Exit",  function() SetEditing(false) end, addon)

    -- Native Edit Mode behaviour: close our element option pop-ups the instant selection leaves our box --
    -- Blizzard selecting one of its OWN systems (SelectSystem) or an empty-space click that clears the
    -- selection (ClearSelectedSystem). Our own box clicks call ClearSelectedSystem too, so that path is
    -- guarded by suppressDeselectClose. Switching directly between our boxes is handled in ShowTab (it hides
    -- the other panels), so only genuine focus-loss reaches here.
    local EMMsel = _G.EditModeManagerFrame
    if EMMsel and _G.hooksecurefunc then
        if EMMsel.ClearSelectedSystem and not EMMsel._gsetDeselectHooked then
            EMMsel._gsetDeselectHooked = true
            hooksecurefunc(EMMsel, "ClearSelectedSystem", function()
                if suppressDeselectClose then return end
                CloseEditPanelsAndDeselect()
            end)
        end
        if EMMsel.SelectSystem and not EMMsel._gsetSelectHooked then
            EMMsel._gsetSelectHooked = true
            hooksecurefunc(EMMsel, "SelectSystem", function()
                CloseEditPanelsAndDeselect()  -- a Blizzard system took focus -> our panel is no longer focused
            end)
        end
    end

    -- NOTE: do NOT hook EditModeManagerFrame:RevertAllChanges to factory-reset GSE_Tracker. Blizzard
    -- calls RevertAllChanges INTERNALLY (entering/leaving Edit Mode, layout changes), so the hook fired
    -- on its own and WIPED the user's SavedVariables. Removed -- data-loss bug (2026-06-22).

    -- Lock follows Edit Mode now (the manual "Lock All" option was removed). On login: if Edit Mode is
    -- already open (rare) sync to unlocked; otherwise force everything LOCKED so it never logs in draggable.
    local EMM = _G.EditModeManagerFrame
    if EMM and EMM.IsEditModeActive and EMM:IsEditModeActive() then
        SetEditing(true)
    else
        addon._editingOptions = false
        SetAllLocked(true)
    end
end)
