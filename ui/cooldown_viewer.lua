local _, ns = ...
local addon = ns

-- ── Native Cooldown Manager viewer lock ──────────────────────────────────────
-- Rides Blizzard's Cooldown Manager (Retail). When "Essential Cooldowns" / "Utility Cooldowns" is placed on
-- the Meters Layout Control grid, the matching native viewer (EssentialCooldownViewer / UtilityCooldownViewer)
-- is SHOWN and locked to that cell. Blizzard owns the icons, swipes, GCD filtering, charges/stacks AND the
-- (secret) cooldown values -- all engine-side -- so none of the taint/secret-value limits of our own widgets
-- apply. WHICH spells appear is configured in Blizzard's Cooldown Manager. Removing the element restores the
-- viewer to its own position + prior shown state.
--
-- Mechanism mirrors the PRD lock (ui/personal_resource.lua): SetPoint the viewer to the cell at safe moments
-- + a SetPoint hook to re-assert if Edit Mode / the engine moves it; restore on removal. All moves/shows are
-- out-of-combat gated (these frames are protected in combat).

local VIEWERS = {
  { frame = "EssentialCooldownViewer", cell = "GSETracker_EssentialCDCell", isSlotted = "GSETracker_IsEssentialCDsSlotted", slotKey = "EssentialCDs" },
  { frame = "UtilityCooldownViewer",   cell = "GSETracker_UtilityCDCell",   isSlotted = "GSETracker_IsUtilityCDsSlotted",   slotKey = "UtilityCDs" },
}

local DEFAULT_ICON_LIMIT = 5   -- fallback if the viewer's own iconLimit can't be read
local EDGE_GAP = 4   -- px gap from the cluster edge so the two selection-box borders don't visually overlap
local CD_SET = Enum and Enum.EditModeCooldownViewerSetting

-- ── Skin the native CD icons by the SAME rules as the rest of the UI ──────────
-- uiShared (addon._ui) resolves whether the player's UI is "native" (Blizzard / Force Native / no skinner) or
-- skinned (Masque/ABE/ElvUI), and exposes the adopted border art + icon mask. Native -> leave Blizzard's own
-- cooldown icons exactly as they are (they ARE native). Skinned -> adopt the skinner's border + icon mask onto
-- each viewer icon so they match the bars. Re-applied each relayout (idempotent; reuses cached textures).
local uiSkin = addon._ui
local function SkinCDMIcon(item)
  if not item then return end
  local iconTex = item.Icon or item.icon
  if not iconTex then return end
  local w = (item.GetWidth and item:GetWidth()) or 0
  local h = (item.GetHeight and item:GetHeight()) or 0
  if w <= 0 or h <= 0 then return end
  local native = (not uiSkin) or (uiSkin.IsResolvedNativeSkin and uiSkin.IsResolvedNativeSkin())
  if native then                                   -- Blizzard icons are already native -> strip any adopted skin
    if item._gseSkinBorder then item._gseSkinBorder:Hide() end
    if item._gseIconMask then pcall(iconTex.RemoveMaskTexture, iconTex, item._gseIconMask); item._gseIconMask = nil end
    return
  end
  -- Adopted action-bar border/frame art (atlas or file + size ratios), per the skin rules.
  local sb = uiSkin.GetActionButtonBorder and uiSkin.GetActionButtonBorder()
  if sb and (sb.atlas or sb.file) then
    local b = item._gseSkinBorder
    if not b then b = item:CreateTexture(nil, "OVERLAY", nil, 7); item._gseSkinBorder = b end
    if sb.atlas then b:SetAtlas(sb.atlas, false)
    else b:SetTexture(sb.file); if sb.coords then b:SetTexCoord(unpack(sb.coords)) end end
    b:ClearAllPoints(); b:SetSize(w * (sb.wRatio or 1), h * (sb.hRatio or 1))
    b:SetPoint("CENTER", item, "CENTER", 0, 0); b:SetVertexColor(1, 1, 1); b:Show()
  elseif item._gseSkinBorder then
    item._gseSkinBorder:Hide()
  end
  -- Adopted rounded-icon mask (skinner shape), sized by the mask:icon ratio + centred, per the skin rules.
  local mAtlas, mFile, mRatio
  if uiSkin.GetActiveActionIconMask then mAtlas, mFile, mRatio = uiSkin.GetActiveActionIconMask() end
  if mAtlas or mFile then
    local m = item._gseIconMask
    if not m then m = item:CreateMaskTexture(); pcall(iconTex.AddMaskTexture, iconTex, m); item._gseIconMask = m end
    if mAtlas then m:SetAtlas(mAtlas, false)
    else m:SetTexture(mFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
    m:ClearAllPoints(); m:SetSize(w * (mRatio or 1), h * (mRatio or 1)); m:SetPoint("CENTER", iconTex, "CENTER", 0, 0)
  elseif item._gseIconMask then                    -- skinner with no mask (square icons) -> drop ours
    pcall(iconTex.RemoveMaskTexture, iconTex, item._gseIconMask); item._gseIconMask = nil
  end
end

local applying, savedPoint, savedShown, hooked, centering = {}, {}, {}, {}, {}
local growthAnchor = {}   -- frame -> screen SIDE (rotation key)
local growthCell  = {}   -- frame -> its grid cell frame (so CenterViewer can re-pin with the outward offset)

local function Slotted(v) local fn = _G[v.isSlotted]; return fn and fn() end

-- Read a Cooldown viewer Edit Mode setting from its settingMap (read-only -- we never WRITE these; writing
-- them taints Blizzard's secure Edit Mode passes). Returns nil if absent.
local function GetSet(f, setting)
  return setting and type(f.settingMap) == "table" and f.settingMap[setting] and f.settingMap[setting].value or nil
end

-- The icons-per-line wrap = whatever the player set in Blizzard's Cooldown Manager panel (we don't override it).
local function ViewerIconLimit(f)
  local lim = tonumber(f.iconLimit) or (CD_SET and tonumber(GetSet(f, CD_SET.IconLimit)))
  if not lim or lim < 1 then return DEFAULT_ICON_LIMIT end
  return math.floor(lim)
end

-- ── Centered, rotating icon layout ───────────────────────────────────────────
-- The native viewer's IconDirection is only Left/Right (no Center), so to centre the icons -- including a
-- partial line -- we reposition each child ourselves AFTER Blizzard lays them out (Blizzard still decides WHICH
-- icons exist via GetItemFrames; we only move them). The block is CENTRED on the cell and its icon order
-- ROTATES 90 by screen side (clock-like, never a 180 flip) so the first icon lands at the wanted corner:
--   BOTTOM: fill right, stack down  -> icon 1 top-left
--   RIGHT : fill up,    stack right -> icon 1 bottom-left
--   TOP   : fill left,  stack up    -> icon 1 bottom-right
--   LEFT  : fill down,  stack left  -> icon 1 top-right
-- `fdx/fdy` = within-line (fill) step, `sdx/sdy` = line-to-line (stack) step (unit signs * icon pitch). The
-- stack direction also points OUTWARD (away from centre): we keep the viewer pinned by its CENTRE (so Blizzard's
-- nub stays centred on the block) but offset that centre outward by half the block, so the inner edge lands on
-- the cell instead of straddling it.
local SIDE_DIR = {
  BOTTOM = { fdx = 1,  fdy = 0,  sdx = 0,  sdy = -1, vertical = false },
  TOP    = { fdx = -1, fdy = 0,  sdx = 0,  sdy = 1,  vertical = false },
  RIGHT  = { fdx = 0,  fdy = 1,  sdx = 1,  sdy = 0,  vertical = true  },
  LEFT   = { fdx = 0,  fdy = -1, sdx = -1, sdy = 0,  vertical = true  },
}

local function CollectChildren(f)
  local out = {}
  local kids = (f.GetItemFrames and f:GetItemFrames()) or {}
  for _, c in ipairs(kids) do
    if c and c.IsShown and c:IsShown() and (c.Icon or c.icon) and c.layoutIndex then out[#out + 1] = c end
  end
  table.sort(out, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)
  return out
end

local function CenterViewer(f)
  if not (f and f.GetItemFrames) or centering[f] then return end
  if EditModeManagerFrame and EditModeManagerFrame.layoutApplyInProgress then return end
  local kids = CollectChildren(f)
  local n = #kids
  if n == 0 then return end
  local w, h = kids[1]:GetWidth(), kids[1]:GetHeight()
  if not w or w == 0 or not h or h == 0 then return end
  centering[f] = true
  local d = SIDE_DIR[growthAnchor[f] or "BOTTOM"] or SIDE_DIR.BOTTOM
  local limit = ViewerIconLimit(f)                           -- the player's chosen icons-per-line wrap
  local stepX, stepY = w + (f.childXPadding or 0), h + (f.childYPadding or 0)
  -- chunk into lines of `limit` (rows for top/bottom, columns for left/right)
  local lines = {}
  for i = 1, n do
    local li = math.floor((i - 1) / limit) + 1
    lines[li] = lines[li] or {}
    lines[li][#lines[li] + 1] = kids[i]
  end
  local nLines = #lines
  -- Each icon relative to the viewer CENTRE: `fc` is its centred position within the line (so a partial line
  -- centres), `sc` its centred line index (so the block centres on the cell). The side's fill/stack signs
  -- rotate the whole block. fill & stack are perpendicular, so the cross terms below are always 0.
  for li, line in ipairs(lines) do
    local cnt = #line
    for i, icon in ipairs(line) do
      local fc = (i - 1) - (cnt - 1) / 2
      local sc = (li - 1) - (nLines - 1) / 2
      local x = (fc * d.fdx + sc * d.sdx) * stepX
      local y = (fc * d.fdy + sc * d.sdy) * stepY
      pcall(function() icon:ClearAllPoints(); icon:SetPoint("CENTER", f, "CENTER", x, y) end)
      pcall(SkinCDMIcon, icon)   -- adopt the UI skin (border + mask) per the same rules as the rest of the UI
    end
  end
  -- Size the viewer to the block (so the Edit Mode box stays in sync) AND pin it against the meters cluster:
  -- anchor the block CENTRE to MetersAnchor CENTRE, offset outward by (cluster half-extent + half the block)
  -- so the block's INNER edge butts the cluster edge while the viewer CENTRE (Blizzard's nub) stays at the
  -- block's centre. SetSize + viewer SetPoint are protected -> out of combat only.
  if not InCombatLockdown() then
    local across = math.min(limit, n)
    local bw = (d.vertical and nLines or across) * stepX - (f.childXPadding or 0)
    local bh = (d.vertical and across or nLines) * stepY - (f.childYPadding or 0)
    pcall(f.SetSize, f, bw, bh)
    local cluster = growthCell[f]
    if cluster then
      local halfW, halfH = 90, 35
      if _G.GSETracker_MetersClusterHalfExtents then halfW, halfH = _G.GSETracker_MetersClusterHalfExtents() end
      local off = EDGE_GAP + (d.vertical and (halfW + bw / 2) or (halfH + bh / 2))
      pcall(function()
        f:ClearAllPoints()
        f:SetPoint("CENTER", cluster, "CENTER", d.sdx * off, d.sdy * off)
      end)
    end
  end
  centering[f] = false
end

local function ApplyOne(v)
  if applying[v.frame] then return end
  if not Slotted(v) then return end
  if InCombatLockdown() then return end
  -- Never run while Blizzard is mid-apply on its Edit Mode layout -- doing so taints its secure passes.
  if EditModeManagerFrame and EditModeManagerFrame.layoutApplyInProgress then return end
  local f, cluster = _G[v.frame], _G.MetersAnchor   -- anchor to the meters cluster, not the grid cell
  if not (f and cluster and f.SetPoint) then return end
  applying[v.frame] = true
  if savedPoint[v.frame] == nil then            -- snapshot the player's own position + shown state once
    local pts, n = {}, (f.GetNumPoints and f:GetNumPoints()) or 0
    for i = 1, n do pts[i] = { f:GetPoint(i) } end
    savedPoint[v.frame] = pts
    savedShown[v.frame] = (f.IsShown and f:IsShown()) and true or false
  end
  local side = (_G.GSETracker_CDViewerGrowth and _G.GSETracker_CDViewerGrowth(v.slotKey)) or "BOTTOM"
  growthAnchor[f] = side                           -- which screen side -> icon fill/stack rotation
  growthCell[f] = cluster                          -- CenterViewer re-pins against the cluster edge
  pcall(function()
    if f.SetShown then f:SetShown(true) end        -- placing the element shows the viewer
    f:ClearAllPoints()
    f:SetPoint("CENTER", cluster, "CENTER", 0, 0)  -- basic centre pin; CenterViewer offsets it to the cluster edge
  end)
  CenterViewer(f)                                  -- lay the icons out + butt against the cluster, rotated for this side
  applying[v.frame] = false
end

local function RestoreOne(v)
  local f = _G[v.frame]
  if not (f and savedPoint[v.frame]) then return end
  if InCombatLockdown() then return end
  applying[v.frame] = true
  pcall(function()
    growthAnchor[f], growthCell[f] = nil, nil
    f:ClearAllPoints()
    for _, p in ipairs(savedPoint[v.frame]) do f:SetPoint(unpack(p)) end
    if f.SetShown then f:SetShown(savedShown[v.frame]) end
  end)
  applying[v.frame] = false
  savedPoint[v.frame], savedShown[v.frame] = nil, nil
end

local function EnsureHook(v)
  if hooked[v.frame] then return end
  local f = _G[v.frame]
  if not (f and f.SetPoint and hooksecurefunc) then return end
  hooked[v.frame] = true
  -- Re-assert our pin if Blizzard/Edit Mode moves the viewer -- but DEFER to the next frame so this never runs
  -- synchronously inside Blizzard's secure Edit Mode SetPoint pass (running there taints its secret-value math).
  hooksecurefunc(f, "SetPoint", function()
    if applying[v.frame] or centering[f] then return end   -- ignore our own pin/offset re-asserts
    if C_Timer then C_Timer.After(0, function() ApplyOne(v) end) else ApplyOne(v) end
  end)
  -- Re-centre the icons right after Blizzard lays them out (RefreshLayout fires on cooldown active/inactive,
  -- spec change, etc.). SYNCHRONOUS so our positions win immediately -- deferring a frame lets Blizzard's raw
  -- layout show through in Edit Mode. CenterViewer bails while layoutApplyInProgress, so it never runs inside
  -- Blizzard's secure apply pass (cold-load centring comes from the EDIT_MODE_LAYOUTS_UPDATED event instead).
  if f.RefreshLayout then
    hooksecurefunc(f, "RefreshLayout", function() if Slotted(v) then CenterViewer(f) end end)
  end
end

-- Called by Meters SetupFrames (after the cells are parked) + on safe-moment events.
function GSETracker_LockCooldownViewers()
  for _, v in ipairs(VIEWERS) do
    EnsureHook(v)
    if Slotted(v) then ApplyOne(v) else RestoreOne(v) end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")        -- re-assert / apply a deferred move after combat
-- EDIT_MODE_LAYOUTS_UPDATED is Retail-only (Edit Mode); pcall so Classic doesn't error on the unknown event.
pcall(ev.RegisterEvent, ev, "EDIT_MODE_LAYOUTS_UPDATED")  -- Blizzard FINISHED applying a layout
ev:SetScript("OnEvent", function()
  GSETracker_LockCooldownViewers()
  -- On load Blizzard applies its layout with layoutApplyInProgress=true, so the centering pass bails (it won't
  -- fight a layout-in-progress). Re-assert a couple of frames later, once the apply has settled, so it centres
  -- without needing the player to open Edit Mode.
  if C_Timer then C_Timer.After(0.1, GSETracker_LockCooldownViewers) end
end)
