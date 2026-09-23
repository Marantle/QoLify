-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local ADDON, CB = ...

-- The bar itself, the letters and ticks sliding past a center marker as
-- the player turns. The content is laid out in a line and slid by
-- arithmetic, and places from the map ride along. It only draws out in the
-- world, inside instances the facing is sealed and the bar stays hidden.

local Strip = {}
CB.Strip = Strip

local win, clip
local band -- the laid out content, made with the window
local lastRot -- the driver's last value, so a fresh layout starts at the facing
local blank = false

local MINOR = 5 -- degrees between the small ticks
local TWO_PI = 2 * math.pi

--#region Places

-- a bearing as an angle to the left or right of the facing, the value
-- being minus the facing
local function aside(bearing, rot)
    return (bearing - rot + math.pi) % TWO_PI - math.pi
end

-- a pool of icons with labels for the places, on the clip, styled on every
-- gather and put in its spot on every tick: as far left or right of the
-- marker as its bearing is from the facing, at the dial's spread, hidden
-- once it runs off the end, out of the same numbers that slide the content
local function makePool(build)
    local pool = { items = {}, used = 0 }

    local function slot(i)
        local e = pool.items[i]
        if not e then
            e = {}
            e.ring = clip:CreateTexture(nil, "OVERLAY", nil, -1)
            e.icon = clip:CreateTexture(nil, "OVERLAY")
            e.ring:SetPoint("CENTER", e.icon)
            e.label = clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            e.label:SetTextColor(1, 1, 1, 0.8)
            e.label:SetPoint("TOP", e.ring, "BOTTOM", 0, -1)
            pool.items[i] = e
        end
        return e
    end

    local function show(e, on)
        e.icon:SetShown(on)
        e.ring:SetShown(on and e.ringed)
        e.label:SetShown(on)
    end

    function pool.Lay(s)
        local n = 0
        for _, pt in ipairs(CB.Points.List()) do
            n = n + 1
            local e = slot(n)
            local size = s.markSize * (pt.size or 1)
            -- a ringed one is drawn the way the map draws it, the type
            -- icon small inside the ring
            e.ringed = pt.ring ~= nil
            e.ring:SetSize(size, size)
            if pt.ring then
                e.ring:SetAtlas(pt.ring)
                size = size * 0.62
            end
            e.icon:SetSize(size, size)
            if pt.atlas then
                e.icon:SetAtlas(pt.atlas)
            else
                e.icon:SetTexture(pt.texture)
            end
            local c = pt.color
            e.icon:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1)
            local text = pt.label or ""
            if s.points.distance then
                text = (text ~= "" and text .. " " or "") .. ("%d yd"):format(pt.dist)
            end
            e.label:SetText(text)
        end
        for i = n + 1, pool.used do
            show(pool.items[i], false)
        end
        pool.used = n
    end

    function pool.Place()
        local s = build.s
        local n = 0
        for _, pt in ipairs(CB.Points.List()) do
            n = n + 1
            local e = pool.items[n]
            if e then
                local x = aside(pt.bearing, build.rot or 0) * s.span / 2
                -- the tracked quest has no switch and so no range either
                local range = pt.src and s.range[pt.src] or 0
                local on = math.abs(x) <= s.width / 2 + s.markSize and (range == 0 or pt.dist <= range)
                if on then
                    e.icon:ClearAllPoints()
                    e.icon:SetPoint("CENTER", clip, "TOPLEFT", s.width / 2 + x, -s.iconRow)
                end
                show(e, on)
            end
        end
    end

    function pool.Hide()
        for i = 1, pool.used do
            show(pool.items[i], false)
        end
    end

    return pool
end

--#endregion

--#region Straight

-- one turn of content: the letters, the small ticks between them and a
-- mark under each letter. Made once, placed again whenever the pixels per
-- radian change
local function makeTurn(parent)
    local turn = { marks = {}, ticks = {} }
    for deg = 0, 359, MINOR do
        local mark
        if deg % 45 == 0 then
            local k = deg / 45
            mark = parent:CreateFontString(nil, "OVERLAY", k % 2 == 0 and "GameFontNormalLarge" or "GameFontNormal")
            mark:SetText(CB.SLOTS[k + 1])
            mark:SetTextColor(1, 1, 1, 0.9)
            local tick = parent:CreateTexture(nil, "ARTWORK", nil, 1)
            tick:SetColorTexture(1, 1, 1, 1)
            tick:SetSize(4, 14)
            turn.ticks[k] = tick
        else
            -- every third one taller
            mark = parent:CreateTexture(nil, "ARTWORK")
            mark:SetColorTexture(1, 1, 1, deg % 15 == 0 and 0.7 or 0.45)
            mark:SetSize(2, deg % 15 == 0 and 14 or 7)
        end
        turn.marks[deg] = mark
    end
    -- letters off takes the small ticks with it
    function turn.Place(x0, ppr, s)
        for deg, mark in pairs(turn.marks) do
            local x = x0 + math.rad(deg) * ppr
            mark:ClearAllPoints()
            mark:SetPoint("TOP", parent, "TOPLEFT", x, -4)
            mark:SetShown(s.letters)
            local tick = turn.ticks[deg / 45]
            if tick then
                tick:ClearAllPoints()
                tick:SetPoint("TOP", parent, "TOPLEFT", x, -30)
                tick:SetVertexColor(unpack(s.tickColor))
                tick:SetShown(s.ticks)
            end
        end
    end
    return turn
end

local function buildFlat()
    local f = {}
    -- a wide frame under the clip, slid left by the facing in pixels
    local content = CreateFrame("Frame", nil, clip)
    -- three turns of content and the window starts a turn in, so whatever
    -- the facing there is a turn to either side of the one under it. A
    -- turn is always wider than the bar, the spread's floor sees to that
    f.turns = { makeTurn(content), makeTurn(content), makeTurn(content) }
    local pool = makePool(f)

    function f.Lay(s)
        f.s = s
        -- pixels per radian come from the spread alone, so a wider bar shows
        -- more rather than stretching
        local ppr = s.span / 2
        f.ppr, f.turn = ppr, TWO_PI * ppr
        content:SetSize(3 * f.turn + s.width, s.height)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", clip, "TOPLEFT", -f.turn, 0)
        for i, t in ipairs(f.turns) do
            t.Place(s.width / 2 + (i - 1) * f.turn, ppr, s)
        end
        f.LayPoints(s)
    end

    function f.LayPoints(s)
        pool.Lay(s)
        pool.Place()
    end

    -- the value is minus the facing, which read the other way round is the
    -- facing as a compass bearing, clockwise from north, the way the
    -- letters are laid out. Folded into one turn it stays in the content,
    -- and the content slides left by that much
    function f.Spin(rot)
        f.rot = rot
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", clip, "TOPLEFT", -(rot % TWO_PI) * f.ppr - f.turn, 0)
        CB.Points.Track()
        pool.Place()
    end

    function f.SetShown(on)
        content:SetShown(on)
        if not on then
            pool.Hide()
        end
    end

    return f
end

--#endregion

local function build()
    win = CreateFrame("Frame", ADDON .. "Strip", UIParent, "BackdropTemplate")
    CB.MakeMovable(win, "strip", "TOP", 0, -40)
    CB.SkinFloat(win)

    clip = CreateFrame("Frame", nil, win)
    clip:SetPoint("TOPLEFT", 4, -4)
    clip:SetPoint("BOTTOMRIGHT", -4, 4)
    clip:SetClipsChildren(true)

    -- the ends fade into the floor, as dark as the floor is. Overlays rather
    -- than a mask, since the letters are font strings and those take no mask
    local fades = {}
    for _, side in ipairs({ { "LEFT", 1, 0 }, { "RIGHT", 0, 1 } }) do
        local t = win:CreateTexture(nil, "OVERLAY")
        t:SetPoint("TOP" .. side[1], clip, "TOP" .. side[1])
        t:SetPoint("BOTTOM" .. side[1], clip, "BOTTOM" .. side[1])
        t:SetWidth(60)
        t:SetColorTexture(1, 1, 1, 1)
        fades[#fades + 1] = { tex = t, from = side[2], to = side[3] }
    end
    function win.SetDim(a)
        win.SetFloor(a)
        for _, f in ipairs(fades) do
            f.tex:SetGradient(
                "HORIZONTAL",
                CreateColor(0.05, 0.06, 0.08, f.from * a),
                CreateColor(0.05, 0.06, 0.08, f.to * a)
            )
        end
    end

    local marker = win:CreateTexture(nil, "OVERLAY")
    marker:SetTexture(CB.Art.Path("strip_marker"))
    marker:SetSize(14, 14)
    marker:SetPoint("TOP", clip, "TOP", 0, 0)
    marker:SetVertexColor(0.35, 0.82, 0.94)

    CB.AttachLock(win, "strip")

    -- two buttons in the corner: the settings window, and the place
    -- switches as a menu
    local gear = CB.CornerButton(win, "TOPLEFT", "gear", function()
        return "Settings"
    end)
    gear.rest = 0.6
    gear:SetAlpha(gear.rest)
    gear:SetScript("OnClick", CB.ToggleConfig)

    local list = CB.CornerButton(win, "TOPLEFT", "list", function()
        return "What the bar shows"
    end)
    list:ClearAllPoints()
    list:SetPoint("LEFT", gear, "RIGHT", 4, 0)
    list.rest = 0.6
    list:SetAlpha(list.rest)
    local function flip(key)
        return function()
            return CB.db.points[key]
        end, function()
            CB.db.points[key] = not CB.db.points[key]
            CB.Apply()
        end
    end
    list:SetScript("OnClick", function()
        MenuUtil.CreateContextMenu(list, function(_, root)
            root:CreateTitle("On the bar")
            for _, kind in ipairs(CB.Points.KINDS) do
                root:CreateCheckbox(kind[2], flip(kind[1]))
            end
            root:CreateDivider()
            root:CreateCheckbox("Distances", flip("distance"))
        end)
    end)

    band = buildFlat()
end

function Strip.Apply()
    local s = CB.db
    if not s.on or IsInInstance() then
        if win then
            win:Hide()
        end
        CB.Points.Want(false)
        return
    end
    if not win then
        build()
    end
    win:SetSize(s.width + 8, s.height + 8)
    win.SetDim(s.dim)
    -- shown first, the gather Points starts asks whether the bar is up
    win:Show()
    band.Lay(s)
    -- laid out it sits at north, and a tick is long enough to see that
    if lastRot then
        band.Spin(lastRot)
    end
    band.SetShown(not blank)
    CB.Points.Want(true)
end

function Strip.Drawing()
    return win ~= nil and win:IsShown()
end

-- the settings the bar is drawing, for whoever gathers on its behalf
function Strip.Applied()
    return Strip.Drawing() and CB.db or nil
end

-- for /cbar status
function Strip.Status()
    if not CB.db.on then
        return "bar: off"
    end
    if IsInInstance() then
        return "bar: hidden, the game keeps your facing from addons inside instances"
    end
    return "bar: on"
end

-- Points gathered a fresh list
function Strip.PointsChanged()
    if Strip.Drawing() then
        band.LayPoints(CB.db)
    end
end

function Strip.Spin(rot)
    if not Strip.Drawing() then
        return
    end
    lastRot = rot
    if rot == nil then
        if not blank then
            blank = true
            band.SetShown(false)
        end
        return
    end
    band.Spin(rot)
    if blank then
        blank = false
        CB.Apply()
    end
end
