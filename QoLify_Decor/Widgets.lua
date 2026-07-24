local _, DCR = ...

-- Building blocks shared by the module's windows: flat dark panels with gold
-- accents. Spendwatch.lua and CartWindow.lua compose their layouts from these
-- instead of each carrying its own copies.

local WHITE = "Interface/Buttons/WHITE8X8"

DCR.WHITE = WHITE
DCR.COLOR_GOLD = { 1, 0.82, 0 }
DCR.COLOR_DIM = { 0.66, 0.66, 0.7 }

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
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
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

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(DCR.COLOR_GOLD[1], DCR.COLOR_GOLD[2], DCR.COLOR_GOLD[3], 0.25)
    divider:SetPoint("TOPLEFT", 18, -46)
    divider:SetPoint("TOPRIGHT", -18, -46)
    divider:SetHeight(1)

    return panel
end
