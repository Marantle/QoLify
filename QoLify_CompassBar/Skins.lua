-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local _, CB = ...

-- The house skin. Every function takes a parent and hands back a widget,
-- and the windows do the anchoring. Nothing is borrowed from Blizzard
-- templates beyond the scroll frame, so a template rework cannot break it.

CB.COLORS = {
    accent = { 0.35, 0.82, 0.94 },
    frame = { 0.22, 0.50, 0.62 },
    border = { 0.24, 0.34, 0.42 },
    text = { 0.92, 0.94, 0.96 },
    muted = { 0.68, 0.72, 0.78 },
    dim = { 0.46, 0.50, 0.56 },
}

CB.BACKDROP = {
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
}

function CB.RGBA(c, a)
    return c[1], c[2], c[3], a
end

function CB.Hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- a widget with a .tip shows it on hover. Not GameTooltip.Hide straight as
-- the handler, a handler's self is the widget and that Hide would take the
-- widget with it
local function tipScripts(f)
    f:HookScript("OnEnter", function(self)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    f:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

--#region Windows

-- the settings window: thin edge, vertical gradient, a tinted header strip
-- with the title in it. The frame must be made with BackdropTemplate
function CB.SkinWindow(f, title)
    f:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropBorderColor(CB.RGBA(CB.COLORS.frame, 0.9))

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(1, 1, 1, 1)
    bg:SetGradient("VERTICAL", CreateColor(0.05, 0.06, 0.08, 0.97), CreateColor(0.09, 0.12, 0.15, 0.97))

    local header = f:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(28)
    header:SetColorTexture(1, 1, 1, 1)
    header:SetGradient("HORIZONTAL", CreateColor(0.12, 0.34, 0.44, 0.6), CreateColor(0.08, 0.10, 0.14, 0.05))

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 1, -29)
    line:SetPoint("TOPRIGHT", -1, -29)
    line:SetColorTexture(CB.RGBA(CB.COLORS.frame, 0.8))

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f, "TOPLEFT", 12, -15)
    f.title:SetText(CB.Hex(CB.COLORS.accent) .. "CompassBar|r  " .. title)
    return f
end

-- the bar on screen: an edge and a floor the settings dim. The alpha goes
-- into the gradient's own colors, a gradient texture pays no attention to
-- SetAlpha
function CB.SkinFloat(f)
    f:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropBorderColor(CB.RGBA(CB.COLORS.frame, 0.6))
    local floor = f:CreateTexture(nil, "BACKGROUND")
    floor:SetPoint("TOPLEFT", 1, -1)
    floor:SetPoint("BOTTOMRIGHT", -1, 1)
    floor:SetColorTexture(1, 1, 1, 1)
    function f.SetFloor(a)
        floor:SetGradient("VERTICAL", CreateColor(0.04, 0.05, 0.07, a), CreateColor(0.08, 0.10, 0.13, a))
        f:SetBackdropBorderColor(CB.RGBA(CB.COLORS.frame, 0.6 * a))
    end
    f.SetFloor(1)
    return f
end

function CB.MakeLabel(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

function CB.MakeHeader(parent, text)
    local fs = CB.MakeLabel(parent, "GameFontNormal", text)
    fs:SetTextColor(CB.RGBA(CB.COLORS.accent, 1))
    return fs
end

--#endregion

--#region Buttons

local BTN = {
    fill = { 0.09, 0.11, 0.15, 0.95 },
    fillHover = { 0.14, 0.20, 0.26, 0.95 },
    fillDown = { 0.04, 0.05, 0.07, 1 },
    edge = { 0.24, 0.34, 0.42, 0.9 },
    edgeHover = { 0.35, 0.82, 0.94, 1 },
}

-- flat dark button, cyan edge on hover. The label is pinned inside so long
-- text truncates instead of spilling
function CB.MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h or 22)
    b:SetBackdrop(CB.BACKDROP)
    b:SetBackdropColor(unpack(BTN.fill))
    b:SetBackdropBorderColor(unpack(BTN.edge))
    -- a button only grows a font string once it has had text, and the
    -- dropdowns start blank, so it gets one up front
    local fs = b:CreateFontString(nil, "OVERLAY")
    b:SetFontString(fs)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetText(text)
    fs:SetWordWrap(false)
    fs:SetPoint("LEFT", 6, 0)
    fs:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(BTN.fillHover))
        self:SetBackdropBorderColor(unpack(BTN.edgeHover))
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(BTN.fill))
        self:SetBackdropBorderColor(unpack(BTN.edge))
    end)
    b:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(unpack(BTN.fillDown))
    end)
    b:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(unpack(BTN.fillHover))
    end)
    tipScripts(b)
    return b
end

-- a small x that hides its parent
function CB.MakeCloseX(parent)
    local x = CreateFrame("Button", nil, parent)
    x:SetSize(20, 20)
    x:SetPoint("TOPRIGHT", -5, -5)
    local fs = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(CB.Hex(CB.COLORS.accent) .. "x|r")
    x:SetScript("OnEnter", function()
        fs:SetText("|cffffffffx|r")
    end)
    x:SetScript("OnLeave", function()
        fs:SetText(CB.Hex(CB.COLORS.accent) .. "x|r")
    end)
    x:SetScript("OnClick", function()
        parent:Hide()
    end)
    return x
end

--#endregion

--#region Controls

-- a check in the house style, a button with a filled square for the tick.
-- Reads like a CheckButton where callers care: SetChecked, GetChecked and
-- an onChange callback
function CB.MakeCheck(parent, label)
    local cb = CreateFrame("Button", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    cb:SetBackdrop(CB.BACKDROP)
    cb:SetBackdropColor(0, 0, 0, 0.55)
    cb:SetBackdropBorderColor(CB.RGBA(CB.COLORS.border, 0.9))
    cb.tick = cb:CreateTexture(nil, "OVERLAY")
    cb.tick:SetPoint("CENTER")
    cb.tick:SetSize(8, 8)
    cb.tick:SetColorTexture(CB.RGBA(CB.COLORS.accent, 1))
    cb.tick:Hide()
    cb.label = CB.MakeLabel(cb, "GameFontHighlightSmall", label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    -- the label is part of the target since a 16 px square is a mean thing to aim at
    cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 8), 0, 0)
    function cb:SetChecked(on)
        self.checked = on and true or false
        self.tick:SetShown(self.checked)
    end
    function cb:GetChecked()
        return self.checked
    end
    cb:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onChange then
            self.onChange(self.checked)
        end
    end)
    cb:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(CB.RGBA(CB.COLORS.accent, 1))
    end)
    cb:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(CB.RGBA(CB.COLORS.border, 0.9))
    end)
    tipScripts(cb)
    return cb
end

-- Hand built slider. Label above on the left, the live value above on the
-- right, accent fill up to the thumb. Set puts a value in without firing
-- onChange, so a refresh never writes back into the settings. An optional
-- fmt turns the number into words
function CB.MakeSlider(parent, w, label, lo, hi, step, fmt)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(w, 14)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetHitRectInsets(0, 0, -6, -6)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(0, 0, 0, 0.55)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("LEFT")
    s.fill:SetHeight(4)
    s.fill:SetColorTexture(CB.RGBA(CB.COLORS.frame, 1))
    s:SetThumbTexture("Interface/Buttons/WHITE8X8")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(8, 14)
    thumb:SetVertexColor(CB.RGBA(CB.COLORS.accent, 1))
    s.label = CB.MakeLabel(s, "GameFontNormalSmall", label)
    s.label:SetTextColor(CB.RGBA(CB.COLORS.muted, 1))
    s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    s.value = CB.MakeLabel(s, "GameFontHighlightSmall")
    s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)
    local quiet = false
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        self.value:SetText(fmt and fmt(v) or v)
        self.fill:SetWidth(math.max((v - lo) / (hi - lo) * w, 1))
        if not quiet and self.onChange then
            self.onChange(v)
        end
    end)
    function s:Set(v)
        quiet = true
        self:SetValue(v)
        quiet = false
    end
    tipScripts(s)
    return s
end

-- the game's color picker over a color table {r, g, b, a}. Every change,
-- the cancel included, comes back through onDone with a fresh table
local function pickColor(color, onDone)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    -- cancel gets the picker's own copy of the starting color, alpha under a
    local function done(restore)
        if restore then
            onDone({ restore.r, restore.g, restore.b, restore.a })
        else
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            onDone({ nr, ng, nb, ColorPickerFrame:GetColorAlpha() })
        end
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = done,
        opacityFunc = done,
        cancelFunc = done,
        hasOpacity = true,
        opacity = a,
        r = r,
        g = g,
        b = b,
    })
end

-- a color square that opens the picker. Paint re-reads the getter, and
-- nothing reads it at build time since the settings may not be in yet
function CB.MakeSwatch(parent, size, get, set)
    local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
    sw:SetSize(size, size)
    sw:SetBackdrop(CB.BACKDROP)
    sw:SetBackdropBorderColor(CB.RGBA(CB.COLORS.border, 0.9))
    -- a checker under the color so the alpha shows
    local under = sw:CreateTexture(nil, "BACKGROUND")
    under:SetPoint("TOPLEFT", 1, -1)
    under:SetPoint("BOTTOMRIGHT", -1, 1)
    under:SetColorTexture(0.5, 0.5, 0.5, 1)
    local tex = sw:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    function sw.Paint()
        local c = get()
        tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    sw:SetScript("OnClick", function()
        pickColor(get(), function(c)
            set(c)
            sw.Paint()
        end)
    end)
    sw:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(CB.RGBA(CB.COLORS.accent, 1))
    end)
    sw:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(CB.RGBA(CB.COLORS.border, 0.9))
    end)
    tipScripts(sw)
    return sw
end

--#endregion

--#region Lists

-- slim scrollbar over the template's arrows, tucked outside the frame
local function skinScrollBar(scroll)
    local bar = scroll.ScrollBar
    if not bar then
        return
    end
    for _, b in ipairs({ bar.ScrollUpButton, bar.ScrollDownButton }) do
        if b then
            b:SetAlpha(0)
            b:EnableMouse(false)
        end
    end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -1)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 1)
    bar:SetWidth(5)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.45)
    local thumb = bar:GetThumbTexture()
    thumb:SetTexture("Interface/Buttons/WHITE8X8")
    thumb:SetVertexColor(CB.RGBA(CB.COLORS.frame, 0.8))
    thumb:SetSize(5, 36)
end

-- a scroll frame and its child, the child's width following the frame
function CB.MakeScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    skinScrollBar(scroll)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(_, w)
        child:SetWidth(w)
    end)
    return scroll, child
end

--#endregion
