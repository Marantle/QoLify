local _, DCR = ...

-- Building blocks shared by the module's windows: flat dark panels with gold
-- accents. Spendwatch.lua and CartWindow.lua compose their layouts from these
-- instead of each carrying its own copies.

local WHITE = "Interface/Buttons/WHITE8X8"

DCR.WHITE = WHITE
DCR.COLOR_GOLD = { 1, 0.82, 0 }
DCR.COLOR_DIM = { 0.66, 0.66, 0.7 }

-- Icon for a cart entry or a catalog info, whichever field it carries.
function DCR.SetIcon(tex, t)
    if t.iconAtlas then
        tex:SetAtlas(t.iconAtlas)
    else
        tex:SetTexture(t.icon or t.iconTexture or 134400)
    end
end

function DCR.Label(parent, text, color, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

function DCR.Checkbox(parent)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(18, 18)
    c:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    c:SetBackdropColor(0.1, 0.1, 0.13, 1)
    c:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    local tick = c:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(10, 10)
    tick:SetColorTexture(DCR.COLOR_GOLD[1], DCR.COLOR_GOLD[2], DCR.COLOR_GOLD[3])
    c.tick = tick
    return c
end

function DCR.FlatButton(parent, label, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 90, 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.16, 0.16, 0.2, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER", 0, -1)
    t:SetText(label)
    b.text = t
    local function paint(self)
        if self.pressed then
            self:SetBackdropColor(0.1, 0.1, 0.13, 1)
        elseif self.hover then
            self:SetBackdropColor(0.25, 0.25, 0.31, 1)
        else
            self:SetBackdropColor(0.16, 0.16, 0.2, 1)
        end
        t:SetPoint("CENTER", 0, self.pressed and -2 or -1)
    end
    b:SetScript("OnEnter", function(self)
        self.hover = true
        paint(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        paint(self)
    end)
    b:SetScript("OnMouseDown", function(self)
        self.pressed = true
        paint(self)
    end)
    b:SetScript("OnMouseUp", function(self)
        self.pressed = false
        paint(self)
    end)
    return b
end

-- Bordered dark box with a scrolling content frame inside, the list body of
-- the cart and the paint catalog. Returns the box (anchor that), the content
-- (fill that) and the scroll frame, which only a VirtualList needs.
-- The content hangs from its top-left corner only,
-- because anchoring its right edge to the scroll frame makes rows vanish
-- once scrolled, so its width follows the scroll frame by hand instead,
-- which also covers window resizing.
function DCR.ScrollBox(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(0.08, 0.08, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    content:SetPoint("TOPLEFT")
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)
    content:SetWidth(scroll:GetWidth())

    return box, content, scroll
end

-- A long list that only builds the rows its box can show. Reset, then one
-- Add per row (with a Column call wherever the layout wraps), then Paint,
-- which puts rows on the placements falling inside the view. Rows come from
-- create() as they are first needed and are reused from there on, so bind()
-- has to fill in everything a row shows.
--
-- A frame per item stops working somewhere in the hundreds. The client keeps
-- answering the mouse long after it has given up drawing that many icons and
-- font strings, so the list goes blank while its tooltips still work.
function DCR.VirtualList(scroll, create, bind)
    local slots, runs, rows = {}, {}, {}
    local count, runCount = 0, 0
    local list = {}

    -- Paint searches a column top to bottom, so a layout that wraps has to
    -- say where one ends. Single column lists never call this.
    function list:Column()
        runCount = runCount + 1
        local run = runs[runCount]
        if not run then
            run = {}
            runs[runCount] = run
        end
        run.first, run.last = count + 1, count
    end

    function list:Reset()
        count, runCount = 0, 0
        self:Column()
    end

    function list:Add(data, x, y, w, h)
        count = count + 1
        local slot = slots[count]
        if not slot then
            slot = {}
            slots[count] = slot
        end
        slot.data, slot.x, slot.y, slot.w, slot.h = data, x, y, w, h
        runs[runCount].last = count
    end

    function list:Paint()
        local top = scroll:GetVerticalScroll()
        local bottom = top + scroll:GetHeight()
        local shown = 0
        for i = 1, runCount do
            local run = runs[i]
            -- the column's first row still hanging into the view
            local lo, hi = run.first, run.last
            while lo < hi do
                local mid = math.floor((lo + hi) / 2)
                if slots[mid].y + slots[mid].h <= top then
                    lo = mid + 1
                else
                    hi = mid
                end
            end
            for j = lo, run.last do
                local slot = slots[j]
                if slot.y >= bottom then
                    break
                end
                shown = shown + 1
                local row = rows[shown]
                if not row then
                    row = create()
                    rows[shown] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", slot.x, -slot.y)
                row:SetSize(slot.w, slot.h)
                bind(row, slot.data)
                row:Show()
            end
        end
        for i = shown + 1, #rows do
            rows[i]:Hide()
        end
    end

    local function repaint()
        list:Paint()
    end
    scroll:HookScript("OnVerticalScroll", repaint)
    scroll:HookScript("OnSizeChanged", repaint)
    list:Reset()
    return list
end

-- Shift and Ctrl turn one click into 5 or 10, shared by the catalog add
-- button and the cart's quantity buttons.
function DCR.ClickStep()
    if IsControlKeyDown() then
        return 10
    end
    if IsShiftKeyDown() then
        return 5
    end
    return 1
end

-- A movable dark panel with the standard header: gold title, X close button,
-- thin divider under them. Closes on Escape unless stayOpen is set: the game
-- closes every UISpecialFrames entry when the house editor opens, which
-- would kill the cart mid-decorating.
function DCR.Window(name, width, height, titleText, stayOpen)
    local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    -- Clicking any of our windows brings it in front of the others.
    panel:SetToplevel(true)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    panel:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)

    -- Wherever a window gets dragged (and for the resizable cart, its size
    -- too, saved by the resize grip) it comes back next session. Bottom-left
    -- coordinates, since StartMoving rewrites whatever anchor it finds.
    function panel:SaveRect()
        local store = DCR.WindowDB()
        if not store then
            return
        end
        local rect = store[name] or {}
        store[name] = rect
        rect.x, rect.y = self:GetLeft(), self:GetBottom()
        if self:IsResizable() then
            rect.w, rect.h = self:GetSize()
        end
    end
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SaveRect()
    end)
    local store = DCR.WindowDB()
    local saved = store and store[name]
    if saved and saved.x then
        if saved.w then
            panel:SetSize(saved.w, saved.h)
        end
        panel:ClearAllPoints()
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    end
    if stayOpen then
        -- Not in UISpecialFrames (the house editor closes that whole list
        -- when it opens), so Escape gets handled by hand. Propagation is
        -- protected in combat, hence the guards: in combat Escape may then
        -- also open the game menu, which beats not closing at all.
        panel:EnableKeyboard(true)
        panel:SetPropagateKeyboardInput(true)
        panel:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(false)
                end
                self:Hide()
            elseif not InCombatLockdown() then
                self:SetPropagateKeyboardInput(true)
            end
        end)
    else
        table.insert(UISpecialFrames, name) -- close on Escape
    end

    local title = DCR.Label(panel, titleText, DCR.COLOR_GOLD, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)

    local close = DCR.FlatButton(panel, "X", 24)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function()
        panel:Hide()
    end)

    -- The way back when a resize or drag lands the window somewhere
    -- hopeless. The glued side panels hide this and follow the cart.
    local reset = DCR.FlatButton(panel, "Reset", 56)
    reset:SetPoint("RIGHT", close, "LEFT", -6, 0)
    reset:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Back to the default size and spot")
        GameTooltip:Show()
    end)
    reset:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    function panel:ResetRect()
        local rects = DCR.WindowDB()
        if rects then
            rects[name] = nil
        end
        self:SetSize(width, height)
        self:ClearAllPoints()
        self:SetPoint("CENTER")
    end
    reset:SetScript("OnClick", function()
        panel:ResetRect()
    end)
    panel.resetBtn = reset

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(DCR.COLOR_GOLD[1], DCR.COLOR_GOLD[2], DCR.COLOR_GOLD[3], 0.25)
    divider:SetPoint("TOPLEFT", 18, -46)
    divider:SetPoint("TOPRIGHT", -18, -46)
    divider:SetHeight(1)

    return panel
end
