local _, ns = ...
local addon = ns
local C = (ns.Utils and ns.Utils.Constants) or addon.Constants or {}
local uiShared = addon._ui or {}
addon._ui = uiShared

local function PixelSnap(v, frame)
  if uiShared.PixelSnap then
    return uiShared.PixelSnap(v, frame)
  end
  return tonumber(v) or 0
end

local function RoundNearest(v)
  if uiShared.RoundNearest then
    return uiShared.RoundNearest(v)
  end
  v = tonumber(v) or 0
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return math.ceil(v - 0.5)
end

local function GetPixelScale(parent)
  if uiShared.GetPixelScale then
    return uiShared.GetPixelScale(parent)
  end
  local scale = (parent and parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
  if not scale or scale <= 0 then return 1 end
  return scale
end

local function GetPositionLimit()
  return tonumber(C.ACTION_TRACKER_POSITION_LIMIT) or 3000
end

local function ClampToCanonicalLimit(value)
  local limit = GetPositionLimit()
  value = RoundNearest(value)
  if value < -limit then return -limit end
  if value > limit then return limit end
  return value
end

local function CanonicalPixelsToParentUnits(value, parent)
  return PixelSnap(ClampToCanonicalLimit(value) * GetPixelScale(parent), parent)
end

local function ParentUnitsToCanonicalPixels(value, parent)
  local scale = GetPixelScale(parent)
  if not scale or scale == 0 then scale = 1 end
  return ClampToCanonicalLimit((tonumber(value) or 0) / scale)
end

local function NormalizeCenteredOffset(x, y)
  return ClampToCanonicalLimit(x), ClampToCanonicalLimit(y)
end

local function ClampCenteredOffsetsToScreen(frame, parent, x, y)
  parent = parent or UIParent
  local nx, ny = NormalizeCenteredOffset(x, y)
  if not (frame and parent and frame.GetWidth and frame.GetHeight and parent.GetWidth and parent.GetHeight) then
    return nx, ny
  end

  local parentScale = GetPixelScale(parent)
  local frameScale = GetPixelScale(frame)
  local ratio = frameScale / parentScale

  local frameW = math.max(0, (frame:GetWidth() or 0) * ratio)
  local frameH = math.max(0, (frame:GetHeight() or 0) * ratio)
  local parentW = math.max(0, parent:GetWidth() or 0)
  local parentH = math.max(0, parent:GetHeight() or 0)

  local maxXUnits = math.max(0, (parentW - frameW) * 0.5)
  local maxYUnits = math.max(0, (parentH - frameH) * 0.5)
  local maxX = math.min(GetPositionLimit(), ParentUnitsToCanonicalPixels(maxXUnits, parent))
  local maxY = math.min(GetPositionLimit(), ParentUnitsToCanonicalPixels(maxYUnits, parent))

  if nx < -maxX then nx = -maxX elseif nx > maxX then nx = maxX end
  if ny < -maxY then ny = -maxY elseif ny > maxY then ny = maxY end
  return nx, ny
end

local function GetCenteredOffsets(frame, parent)
  parent = parent or UIParent
  if not frame then
    return ClampCenteredOffsetsToScreen(frame, parent, 0, 0)
  end

  if frame.GetPoint then
    local point, anchor, relativePoint, x, y = frame:GetPoint(1)
    if point == "CENTER" and relativePoint == "CENTER" and anchor == parent then
      -- Inverse of the frame-scale compensation in ApplyCenteredOffsets.
      local fs = (frame.GetScale and frame:GetScale()) or 1
      if not fs or fs == 0 then fs = 1 end
      return ClampCenteredOffsetsToScreen(frame, parent, ParentUnitsToCanonicalPixels(x, parent) * fs, ParentUnitsToCanonicalPixels(y, parent) * fs)
    end
  end

  if not (parent and frame.GetCenter and parent.GetCenter) then
    return ClampCenteredOffsetsToScreen(frame, parent, 0, 0)
  end

  local frameX, frameY = frame:GetCenter()
  local parentX, parentY = parent:GetCenter()
  if not (frameX and frameY and parentX and parentY) then
    return ClampCenteredOffsetsToScreen(frame, parent, 0, 0)
  end

  local x = ParentUnitsToCanonicalPixels(frameX - parentX, parent)
  local y = ParentUnitsToCanonicalPixels(frameY - parentY, parent)
  return ClampCenteredOffsetsToScreen(frame, parent, x, y)
end

local function ApplyCenteredOffsets(frame, parent, x, y)
  parent = parent or UIParent
  if not (frame and parent) then return 0, 0 end
  local nx, ny = ClampCenteredOffsetsToScreen(frame, parent, x, y)
  local px = CanonicalPixelsToParentUnits(nx, parent)
  local py = CanonicalPixelsToParentUnits(ny, parent)
  -- SetPoint offsets are measured in the frame's OWN scale, so divide by it to
  -- keep the on-screen position independent of the addon Scale -- the tracker
  -- then scales from its centre instead of drifting up/down.
  local fs = (frame.GetScale and frame:GetScale()) or 1
  if not fs or fs == 0 then fs = 1 end
  px = px / fs
  py = py / fs
  if uiShared.SetPointIfChanged then
    uiShared.SetPointIfChanged(frame, "CENTER", parent, "CENTER", px, py)
  else
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parent, "CENTER", px, py)
  end
  return nx, ny
end

uiShared.NormalizeCenteredOffset = NormalizeCenteredOffset
uiShared.ClampCenteredOffsetsToScreen = ClampCenteredOffsetsToScreen
uiShared.GetCenteredOffsets = GetCenteredOffsets
uiShared.ApplyCenteredOffsets = ApplyCenteredOffsets
uiShared.CanonicalPixelsToParentUnits = CanonicalPixelsToParentUnits
uiShared.ParentUnitsToCanonicalPixels = ParentUnitsToCanonicalPixels
