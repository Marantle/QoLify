-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local _, CB = ...

-- Dragging and the padlock for the bar on screen, keyed into the windows
-- table of the saved settings.

local function entry(key)
    local w = CB.db.windows
    w[key] = w[key] or {}
    return w[key]
end

local function place(frame, key, defPoint, defX, defY)
    local pos = entry(key).pos
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint(defPoint, UIParent, defPoint, defX, defY)
    end
end

-- a line down the middle of the screen while the bar is dragged, and let
-- go near it the bar snaps its center onto it
local SNAP = 12
local guide

local function showGuide(on)
    if not guide then
        guide = CreateFrame("Frame", nil, UIParent)
        guide:SetFrameStrata("TOOLTIP")
        guide:SetPoint("TOP")
        guide:SetPoint("BOTTOM")
        guide:SetWidth(1)
        local t = guide:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetColorTexture(0.35, 0.82, 0.94, 0.6)
    end
    guide:SetShown(on)
end

function CB.MakeMovable(frame, key, defPoint, defX, defY)
    place(frame, key, defPoint, defX, defY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        showGuide(true)
        f:StartMoving()
    end)
    -- the spot is kept as a center offset, so the snap is a matter of
    -- zeroing the sideways part
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        showGuide(false)
        local fx, fy = f:GetCenter()
        local cx, cy = UIParent:GetCenter()
        local dx, dy = fx - cx, fy - cy
        if math.abs(dx) < SNAP then
            dx = 0
        end
        entry(key).pos = { point = "CENTER", relPoint = "CENTER", x = dx, y = dy }
        place(frame, key, defPoint, defX, defY)
    end)
end

--#region Locks

-- a small glyph in a window corner, the tip as a function so it can
-- follow a state
function CB.CornerButton(frame, corner, art, tip)
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(14, 14)
    btn:SetPoint(corner, corner == "TOPLEFT" and 3 or -3, -3)
    btn:SetNormalTexture(CB.Art.Path(art))
    btn:SetHighlightTexture(CB.Art.Path(art), "ADD")
    btn:GetNormalTexture():SetVertexColor(0.35, 0.82, 0.94)
    btn:SetScript("OnEnter", function()
        btn:SetAlpha(1)
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText(tip(), 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        btn:SetAlpha(btn.rest)
        GameTooltip:Hide()
    end)
    return btn
end

-- A locked window can't be dragged and lets clicks fall through. The
-- padlock itself keeps the mouse and hides until the cursor crosses it
local lockApply = {}

function CB.AttachLock(frame, key)
    local btn = CB.CornerButton(frame, "TOPRIGHT", "lock", function()
        return entry(key).locked and "Unlock, so it can be dragged" or "Lock in place"
    end)

    local function apply()
        local locked = entry(key).locked and true or false
        frame:EnableMouse(not locked)
        btn.rest = locked and 0 or 0.85
        btn:SetAlpha(btn.rest)
    end
    btn:SetScript("OnClick", function()
        entry(key).locked = not entry(key).locked or nil
        apply()
        btn:SetAlpha(1)
        CB.RefreshConfig()
    end)
    lockApply[key] = apply
    apply()
end

function CB.GetWindowLock(key)
    return entry(key).locked and true or false
end

function CB.SetWindowLock(key, v)
    entry(key).locked = v and true or nil
    if lockApply[key] then
        lockApply[key]()
    end
end

--#endregion
