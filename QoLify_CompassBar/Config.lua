-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local ADDON, CB = ...

-- The settings window, one page. The bar on screen is its own preview,
-- every control writes the settings and runs CB.Apply.

local W, H = 700, 560
local PAD = 10
local COL_W = 630
local ROW_H = 26

local win

local function refresh()
    if win and win:IsShown() then
        win.Refresh()
    end
end
CB.RefreshConfig = refresh

local function yards(v)
    return v == 0 and "Always" or v .. " yd"
end

-- one kind of place: its switch, and beside it how far out it still shows
local function pointRow(parent, it)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(COL_W - 20, ROW_H)
    local key = it[1]

    local cb = CB.MakeCheck(row, it[2])
    cb:SetPoint("LEFT")
    cb.tip = it[3]

    local range = CB.MakeSlider(row, 240, "", CB.LIMITS.range[1], CB.LIMITS.range[2], 50, yards)
    range:SetPoint("LEFT", 200, 0)
    range.value:ClearAllPoints()
    range.value:SetPoint("LEFT", range, "RIGHT", 10, 0)
    range.tip = "Only within this many yards, or always."
    range.onChange = function(v)
        CB.db.range[key] = v
        CB.Apply()
    end

    cb.onChange = function(v)
        CB.db.points[key] = v
        range:SetAlpha(v and 1 or 0.45)
        CB.Apply()
    end

    function row.Refresh(s)
        cb:SetChecked(s.points[key])
        range:Set(s.range[key])
        range:SetAlpha(s.points[key] and 1 or 0.45)
    end
    return row
end

local function build()
    local f = CreateFrame("Frame", ADDON .. "Config", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    CB.SkinWindow(f, "Settings")
    CB.MakeCloseX(f)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = UIParent:GetCenter()
        local fx, fy = self:GetCenter()
        CB.db.windows.config = { x = fx - cx, y = fy - cy }
    end)
    local pos = CB.db.windows.config
    f:SetPoint("CENTER", UIParent, "CENTER", pos and pos.x or 0, pos and pos.y or 0)
    table.insert(UISpecialFrames, ADDON .. "Config")

    local scroll, page = CB.MakeScroll(f)
    scroll:SetPoint("TOPLEFT", PAD, -40)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 12, 30)
    page:SetWidth(COL_W)

    local on = CB.MakeCheck(page, "Draw the bar")
    on:SetPoint("TOPLEFT", 4, -6)
    on.onChange = function(v)
        CB.db.on = v
        CB.Apply()
    end

    local blurb = CB.MakeLabel(
        page,
        "GameFontHighlightSmall",
        "The direction letters slide past the marker as you turn, the way a game compass bar does. "
            .. "It can also carry places from the map. Inside dungeons, raids and delves the game keeps your "
            .. "facing from addons, so the bar hides there and comes back when you leave."
    )
    blurb:SetPoint("TOPLEFT", 4, -30)
    blurb:SetWidth(600)
    blurb:SetTextColor(CB.RGBA(CB.COLORS.muted, 1))

    local function slider(label, key, step, x, y, tip)
        local s = CB.MakeSlider(page, 300, label, CB.LIMITS[key][1], CB.LIMITS[key][2], step)
        s:SetPoint("TOPLEFT", x, y)
        s.tip = tip
        s.onChange = function(v)
            CB.db[key] = v
            CB.Apply()
        end
        return s
    end
    local width = slider("Width", "width", 10, 4, -110, "How wide the bar is.")
    local height = slider("Height", "height", 2, 4, -154, "How tall the bar is.")
    local span = slider(
        "Spread",
        "span",
        20,
        4,
        -198,
        "How far apart the directions sit. Bigger puts fewer of them in view, width decides how much of the compass shows."
    )
    local iconRow = slider(
        "Place icons",
        "iconRow",
        2,
        4,
        -242,
        "How far under the top edge the icons of quests and the like sit. A taller bar has room to put them lower."
    )

    local letters = CB.MakeCheck(page, "Direction letters")
    letters:SetPoint("TOPLEFT", 340, -110)
    letters.onChange = function(v)
        CB.db.letters = v
        CB.Apply()
    end
    local ticks = CB.MakeCheck(page, "Marks under them")
    ticks:SetPoint("LEFT", letters.label, "RIGHT", 24, 0)
    ticks.onChange = function(v)
        CB.db.ticks = v
        CB.Apply()
    end
    local tickColor = CB.MakeSwatch(page, 18, function()
        return CB.db.tickColor
    end, function(c)
        CB.db.tickColor = c
        CB.Apply()
    end)
    tickColor:SetPoint("LEFT", ticks.label, "RIGHT", 10, 0)
    tickColor.tip = "The color of the marks."

    local dim = CB.MakeSlider(page, 200, "Floor", 0, 100, 5, function(v)
        return v .. "%"
    end)
    dim:SetPoint("TOPLEFT", 340, -160)
    dim.tip = "How dark the bar's background is."
    dim.onChange = function(v)
        CB.db.dim = v / 100
        CB.Apply()
    end
    local markSize = CB.MakeSlider(page, 200, "Icon size", CB.LIMITS.markSize[1], CB.LIMITS.markSize[2], 2)
    markSize:SetPoint("TOPLEFT", 340, -204)
    markSize.tip = "The icons of places riding the bar. A taller bar fits bigger ones."
    markSize.onChange = function(v)
        CB.db.markSize = v
        CB.Apply()
    end
    local lock = CB.MakeCheck(page, "Locked in place")
    lock:SetPoint("TOPLEFT", 340, -236)
    lock.onChange = function(v)
        CB.SetWindowLock("strip", v)
    end

    local worldHead = CB.MakeHeader(page, "Out in the world")
    worldHead:SetPoint("TOPLEFT", 4, -290)
    local distance = CB.MakeCheck(page, "Distances")
    distance:SetPoint("TOPLEFT", 4, -312)
    distance.tip = "How far each one is, in yards, under its icon."
    distance.onChange = function(v)
        CB.db.points.distance = v
        CB.Apply()
    end
    local rows = {}
    for i, it in ipairs(CB.Points.KINDS) do
        local row = pointRow(page, it)
        row:SetPoint("TOPLEFT", 4, -344 - (i - 1) * ROW_H)
        rows[i] = row
    end
    page:SetHeight(344 + #rows * ROW_H + 10)

    local foot = CB.MakeLabel(f, "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", PAD, 10)
    foot:SetTextColor(CB.RGBA(CB.COLORS.dim, 1))
    local ver = CB.MakeLabel(f, "GameFontHighlightSmall", "v" .. CB.VERSION)
    ver:SetPoint("BOTTOMRIGHT", -PAD, 10)
    ver:SetTextColor(CB.RGBA(CB.COLORS.dim, 1))

    function f.Refresh()
        local s = CB.db
        on:SetChecked(s.on)
        width:Set(s.width)
        height:Set(s.height)
        span:Set(s.span)
        iconRow:Set(s.iconRow)
        letters:SetChecked(s.letters)
        ticks:SetChecked(s.ticks)
        tickColor.Paint()
        dim:Set(math.floor(s.dim * 100 + 0.5))
        markSize:Set(s.markSize)
        lock:SetChecked(CB.GetWindowLock("strip"))
        distance:SetChecked(s.points.distance)
        for _, row in ipairs(rows) do
            row.Refresh(s)
        end
        foot:SetText(CB.Facing.Status())
    end
    win = f
end

function CB.OpenConfig()
    if InCombatLockdown() then
        CB.chat("the settings window can't open in combat")
        return
    end
    if not win then
        build()
    end
    win:Show()
    refresh()
end

function CB.ToggleConfig()
    if win and win:IsShown() then
        win:Hide()
    else
        CB.OpenConfig()
    end
end
