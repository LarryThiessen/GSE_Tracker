-- Modules/Meters/AHLightUsage.lua
--
-- The SBAssist % readout was moved out of GSE_Tracker into the standalone SLG-SBA Monitor addon. This
-- frame stays CREATED (so the meter font/layout plumbing that references AHLightUsageFrame / its text is
-- unaffected) but never displays. The old combat-counting / CLEU-matching / fade / polling machinery was
-- removed; the public API below is kept as thin stubs the Meters engine + options panel still call.

MetersSavedVars = MetersSavedVars or {}

-- ─── Frame (created, never shown) ─────────────────────────────────────────────
local frame = CreateFrame("Frame", "AHLightUsageFrame", UIParent)
frame:SetSize(220, 28)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:Hide()

frame.ahLightUsageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.ahLightUsageText:SetAllPoints()
frame.ahLightUsageText:SetJustifyH("CENTER")
frame.ahLightUsageText:SetJustifyV("MIDDLE")
frame.ahLightUsageText:SetText("")

-- Bulletproof kill switch: whatever path tries to Show this frame, snap it back hidden.
frame:HookScript("OnShow", function(self) self:Hide() end)

local function ClearText() frame.ahLightUsageText:SetText("") end

-- ─── Public API (stubs -- the live readout now lives in SLG-SBA Monitor) ───────
function AHLightUsage_Clear()            ClearText() end
function AHLightUsage_Refresh()          ClearText() end
function AHLightUsage_ShouldShow()       return false end
function AHLightUsage_SetPreview(_)      ClearText(); frame:Hide() end
function AHLightUsage_ApplyRefreshRate(_) end
function AHLightUsage_ControllerEvent()  end
function AHLightUsage_ApplyFont(font, size, flags)
    if frame.ahLightUsageText and font then
        frame.ahLightUsageText:SetFont(font, size, flags or "OUTLINE")
    end
end
