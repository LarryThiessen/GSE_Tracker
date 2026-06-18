local _, ns = ...
local addon = ns
local Utils = ns.Utils or {}
ns.Utils = Utils

local C = Utils.Constants or {}
Utils.Constants = C
addon.Constants = C

C.ADDON_VERSION = "1.2.0"
C.SCHEMA_VERSION = 3 -- NOTE: bump MAX_IMPLEMENTED_MIGRATION in savedvars.lua in sync with this value, and add the corresponding MigrateToVersion<N> function first
C.DB_NAME = "GSETrackerDB"
C.ADDON_DISPLAY_NAME = "|cFFFFFFFFGS|r|cFF00FFFFE:|r|cFFFFFF00 Tracker|r"

C.ANCHOR_CENTER = "CENTER"
C.ANCHOR_TOP = "TOP"
C.UI_PARENT_NAME = "UIParent"
C.DEFAULT_ACTION_TRACKER_POINT = { "CENTER", "UIParent", "CENTER", 0, 0 }
C.ACTION_TRACKER_POSITION_LIMIT = 3000

C.TEXTURE_WHITE8X8 = "Interface\\Buttons\\WHITE8x8"
C.MASK_CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

C.FONT_FRIZ = "Friz Quadrata TT"
C.FONT_ARIAL_NARROW = "Arial Narrow"
C.FONT_MORPHEUS = "Morpheus"
C.FONT_SKURRI = "Skurri"
C.FONT_PATH_FRIZ = "Fonts\\FRIZQT__.TTF"
C.FONT_PATH_ARIAL_NARROW = "Fonts\\ARIALN.TTF"
C.FONT_PATH_MORPHEUS = "Fonts\\MORPHEUS.TTF"
C.FONT_PATH_SKURRI = "Fonts\\SKURRI.TTF"

C.MODE_ALWAYS = "Always"
C.MODE_IN_COMBAT = "InCombat"
C.MODE_HAS_TARGET = "HasTarget"
C.MODE_NEVER = "Never"

C.DEFAULT_SCALE = 1.00
C.DEFAULT_ICON_COUNT = 4
C.MIN_ICON_COUNT = 4
C.MAX_ICON_COUNT = 8
C.DEFAULT_ICON_GAP = 3
C.DEFAULT_BORDER_THICKNESS = 1
C.DEFAULT_PRESSED_INDICATOR_SHAPE = "circle"
C.DEFAULT_PRESSED_INDICATOR_SIZE = 10
C.PRESSED_INDICATOR_MIN_SIZE = 10
C.PRESSED_INDICATOR_MAX_SIZE = 50
C.PRESSED_INDICATOR_ACTIVE_WINDOW = 0.20

C.CLASS_FALLBACK_R = 0.20
C.CLASS_FALLBACK_G = 0.60
C.CLASS_FALLBACK_B = 1.00

C.COLOR_RED_R = 1.00
C.COLOR_RED_G = 0.20
C.COLOR_RED_B = 0.20
C.COLOR_GREEN_R = 0.20
C.COLOR_GREEN_G = 1.00
C.COLOR_GREEN_B = 0.20
C.ALPHA_SOFT = 0.10
C.ALPHA_GLOW = 0.18
C.ALPHA_DIM = 0.60
C.ALPHA_DEFAULT = 0.90
C.ALPHA_STRONG = 0.95

C.ACTION_TRACKER_MARKER_BASE_SIZE = 48
C.ACTION_TRACKER_MARKER_MIN_SIZE = 8
C.ACTION_TRACKER_MARKER_GLOW_INSET = 6
C.ACTION_TRACKER_MARKER_CROSS_THICKNESS = 2
C.ACTION_TRACKER_MARKER_FRAME_LEVEL = 50
C.STRATA_MEDIUM = "MEDIUM"
C.STRATA_TOOLTIP = "TOOLTIP"
C.DEFAULT_COMBAT_TRACKER_STRATA = C.STRATA_MEDIUM
C.VALID_FRAME_STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

C.COMBAT_MARKER_MIN_SIZE = 16
C.COMBAT_MARKER_MAX_SIZE = 128
C.COMBAT_MARKER_DEFAULT_SIZE = 40
C.COMBAT_MARKER_DEFAULT_ALPHA = 0.85
C.ASSISTED_HIGHLIGHT_DEFAULT_ALPHA = 1.00
C.COMBAT_MARKER_DEFAULT_SYMBOL = "x"

-- Image symbols for the center marker. These live in their OWN media subfolder
-- (media/marker-images/) so the social/branding logos in media/ are NOT offered as
-- marker symbols. They render as full-colour textures (no class/custom tint) and
-- resize with the Scale slider; procedural symbols (x/plus/diamond/square/circle) are
-- handled separately.
C.COMBAT_MARKER_MEDIA_PATH = "Interface\\AddOns\\GSE_Tracker\\media\\marker-images\\"

-- DISCOVERY: WoW gives addons no directory-listing API, so arbitrary filenames can't be
-- seen at runtime. Two sources are merged (see DiscoverCombatMarkerImages): the generated
-- manifest (any filename, via tools/gen_marker_manifest.sh) and a live probe of the
-- CrosshairsNNN.png sequence via GetTextureFileID. So a numbered file dropped into
-- media\marker-images\ is picked up automatically on load; an arbitrarily-named file
-- appears after re-running the manifest script.
local MARKER_IMAGE_PREFIX = "Crosshairs"  -- file base name; full name = prefix .. "%03d.png"
local MARKER_IMAGE_MAX    = 60            -- highest index probed each load (cheap: SetTexture)
local MARKER_IMAGE_TINT   = true          -- crosshair art is white/greyscale -> Class/Custom tintable

local function MarkerImageFileExists(probeTex, path)
  if not (probeTex and probeTex.GetTextureFileID) then return false end
  probeTex:SetTexture(nil)
  probeTex:SetTexture(path)
  local id = probeTex:GetTextureFileID()  -- nil when the path resolves to no real file
  probeTex:SetTexture(nil)
  return id ~= nil
end

-- `tint = true` means the image is white/greyscale and follows the Class/Custom Color.
-- These tables are populated IN PLACE by DiscoverCombatMarkerImages() so references taken
-- by the options UI stay valid across a re-scan.
C.COMBAT_MARKER_IMAGE_SYMBOLS = {}
C.COMBAT_MARKER_IMAGE_VALID = {}
C.COMBAT_MARKER_IMAGE_PATHS = {}
C.COMBAT_MARKER_IMAGE_TINT = {}

-- A readable label from a filename: "Crosshairs003.png" -> "Crosshair 3"; anything else
-- drops the extension and turns underscores into spaces (e.g. "My_Marker.png" -> "My Marker").
local function MarkerLabelForFile(file)
  local base = tostring(file):gsub("%.[Pp][Nn][Gg]$", ""):gsub("%.[Tt][Gg][Aa]$", "")
  local n = base:match("^Crosshairs(%d+)$")
  if n then return "Crosshair " .. tonumber(n) end
  return (base:gsub("_", " "))
end

-- (Re)build the image-symbol tables by MERGING two sources (WoW can't enumerate a folder
-- at runtime, so neither alone is complete):
--   1) the generated manifest (_G.GSETracker_MarkerImageFiles, from
--      tools/gen_marker_manifest.sh) -- covers files of ANY name, but only as of the last
--      time the script was run; and
--   2) a live probe of the CrosshairsNNN.png sequence via GetTextureFileID -- AUTO-detects
--      newly-dropped numbered files on load with no manifest regen.
-- So: drop CrosshairsNNN.png -> appears automatically next load; drop an arbitrarily-named
-- file -> appears after re-running gen_marker_manifest.sh. Falls back to a base set so the
-- dropdowns are never empty. Idempotent; safe to call repeatedly.
function C.DiscoverCombatMarkerImages()
  local found, seen = {}, {}
  local function add(file, label)
    if type(file) ~= "string" or file == "" or seen[file] then return end
    seen[file] = true
    found[#found + 1] = { value = file, text = label or MarkerLabelForFile(file), tint = MARKER_IMAGE_TINT }
  end

  -- 1) Manifest: any filename, as captured by the generator script.
  local manifest = _G.GSETracker_MarkerImageFiles
  if type(manifest) == "table" then
    for i = 1, #manifest do add(manifest[i]) end
  end

  -- 2) Live probe: pick up CrosshairsNNN.png added since the manifest was generated.
  local probeFrame = CreateFrame and CreateFrame("Frame")
  local probeTex = probeFrame and probeFrame.CreateTexture and probeFrame:CreateTexture()
  if probeTex and probeTex.GetTextureFileID then
    for i = 1, MARKER_IMAGE_MAX do
      local file = string.format("%s%03d.png", MARKER_IMAGE_PREFIX, i)
      if not seen[file] and MarkerImageFileExists(probeTex, C.COMBAT_MARKER_MEDIA_PATH .. file) then
        add(file, "Crosshair " .. i)
      end
    end
  end

  -- 3) Never leave the list empty: expose the known base set so the dropdowns still work.
  if #found == 0 then
    for i = 1, 8 do add(string.format("%s%03d.png", MARKER_IMAGE_PREFIX, i), "Crosshair " .. i) end
  end
  -- Repopulate the SAME tables in place.
  local clear = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
  clear(C.COMBAT_MARKER_IMAGE_SYMBOLS)
  clear(C.COMBAT_MARKER_IMAGE_VALID)
  clear(C.COMBAT_MARKER_IMAGE_PATHS)
  clear(C.COMBAT_MARKER_IMAGE_TINT)
  for i = 1, #found do
    local e = found[i]
    C.COMBAT_MARKER_IMAGE_SYMBOLS[i] = e
    C.COMBAT_MARKER_IMAGE_VALID[e.value] = true
    C.COMBAT_MARKER_IMAGE_PATHS[e.value] = C.COMBAT_MARKER_MEDIA_PATH .. e.value
    C.COMBAT_MARKER_IMAGE_TINT[e.value]  = e.tint and true or false
  end
  return C.COMBAT_MARKER_IMAGE_SYMBOLS
end

C.DiscoverCombatMarkerImages()  -- best-effort at load; re-run from the options panel (post-login)
-- "Dynamic" marker symbols that resolve their texture per-player at draw time
-- (Class icon, Specialization icon). They render in the combat-marker frame and follow
-- the SAME single display rule as every other marker. (Bullseye is now a media image,
-- see the manifest above.)
C.MARKER_CLASS_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
C.COMBAT_MARKER_DYNAMIC_VALID = { Class = true, Specialization = true }

-- Center on the character (screen centre). 0,0 lands at exact UIParent centre, which
-- avoids the parent-scale offset math entirely so all markers sit dead-centre.
C.COMBAT_MARKER_DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, 0 }
C.COMBAT_MARKER_DEFAULT_SHOW_WHEN = C.MODE_IN_COMBAT
C.COMBAT_MARKER_DEFAULT_THICKNESS = 4
C.COMBAT_MARKER_MIN_THICKNESS = 1
C.COMBAT_MARKER_MAX_THICKNESS = 12
C.COMBAT_MARKER_DEFAULT_BORDER_SIZE = 2
C.COMBAT_MARKER_MIN_BORDER_SIZE = 0
C.COMBAT_MARKER_MAX_BORDER_SIZE = 8
C.COMBAT_MARKER_POSITION_LIMIT = C.ACTION_TRACKER_POSITION_LIMIT
C.COMBAT_MARKER_VALID_ANCHORS = {
  CENTER = true,
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
}

function C:CopyDefaultActionTrackerPoint()
  local p = self.DEFAULT_ACTION_TRACKER_POINT
  return { p[1], p[2], p[3], p[4], p[5] }
end
