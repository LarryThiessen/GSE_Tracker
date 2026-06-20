local _, ns = ...
local Utils = ns.Utils or {}
ns.Utils = Utils
local C = Utils.Constants or ns.Constants or {}

local PREFIX = C.ADDON_DISPLAY_NAME or "|cFFFFFFFFGS|r|cFF00FFFFE:|r|cFFFFFF00 Tracker|r"

-- Slash-command module. (The old debug-mode toggle was removed -- GSE provides its own
-- debug tooling, and this addon only ever emitted two trivial debug lines.)
local DebugModule = Utils.DebugModule or {}
Utils.DebugModule = DebugModule

local function PrintChat(message)
  if not message or message == "" then
    return
  end

  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. message)
  elseif print then
    print("GSE Tracker", message)
  end
end

function DebugModule:HandleSlashCommand(msg)
  msg = type(msg) == "string" and msg:lower():match("^%s*(.-)%s*$") or ""

  if msg == "minimap" then
    if ns.SetMinimapHidden then
      ns:SetMinimapHidden(false)
    end
    if ns.UI and ns.UI.RefreshMinimapButton then
      ns.UI:RefreshMinimapButton()
    end
    PrintChat("Minimap button shown.")
    return
  end

  if msg == "reset" or msg == "resetpressed" or msg == "reset pressed" then
    -- Recover the Pressed Indicator if it was dragged off-screen / lost: re-center it on
    -- the icon row, ensure it's enabled, then flash it (mark input) so it's visible now.
    if ns.SetElementOffset then ns:SetElementOffset("pressedIndicator", 0, 0) end
    if ns.SetElementEnabled then ns:SetElementEnabled("pressedIndicator", true) end
    ns._lastInputTime = (_G.GetTime and _G.GetTime()) or 0
    if ns.RefreshPressedIndicator then ns:RefreshPressedIndicator(true) end
    PrintChat("Pressed Indicator re-centered on the tracker and enabled. Press any key to see it blink.")
    return
  end

  if msg == "f1off" or msg == "f1 off" or msg == "ah off" or msg == "assist off" then
    -- Turn OFF the Assisted Highlight (the "F1" keybind highlight) and hide it now.
    if ns.SetAssistedHighlightMirrorEnabled then ns:SetAssistedHighlightMirrorEnabled(false) end
    if ns.RefreshAssistedHighlight then ns:RefreshAssistedHighlight(true) end
    PrintChat("Assisted Highlight (the F1 keybind highlight) turned OFF.")
    return
  end

  if ns.ToggleSettingsWindow then
    ns:ToggleSettingsWindow()
  end
end

function DebugModule:RegisterSlashCommands()
  if self._slashRegistered then
    return
  end

  SLASH_GSETRACKER1 = "/gsetracker"
  SlashCmdList.GSETRACKER = function(msg)
    self:HandleSlashCommand(msg)
  end

  -- Convenience reload alias (restored). Note: /reload and /reloadui are Blizzard built-ins;
  -- /rl is not, so addons provide it. Last addon to register /rl wins if several do.
  SLASH_GSETRACKERRELOAD1 = "/rl"
  SlashCmdList.GSETRACKERRELOAD = function()
    if _G.ReloadUI then _G.ReloadUI() end
  end

  self._slashRegistered = true
end

function DebugModule:Init()
  self:RegisterSlashCommands()
end
