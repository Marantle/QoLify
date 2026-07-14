local _, DSW = ...

-- A small self-contained settings window. Dark panel, gold accents, flat controls.
-- Built the first time it is opened so we never touch frames before login.
--
-- Copy of the standalone DecorSpendwatch Settings.lua, minus the
-- DecorSpendwatch_OnAddonCompartmentClick handler at the end: this module has
-- no addon-compartment entry, and defining the global here would clobber the
-- standalone's while this module stands by.

local WHITE = "Interface/Buttons/WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local DIM = { 0.66, 0.66, 0.7 }

local panel, capEdit, trackTick, warnTick, spendTick, overTick, spentText, overText
local editorPanel, warnEdit

local function checkbox(parent)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(18, 18)
    c:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    c:SetBackdropColor(0.1, 0.1, 0.13, 1)
    c:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    local tick = c:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(10, 10)
    tick:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
    c.tick = tick
    return c
end

local function flatButton(parent, label, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 90, 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.16, 0.16, 0.2, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER", 0, -1)
    t:SetText(label)
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

local function label(parent, text, color, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function refresh()
    if not panel then
        return
    end
    trackTick:SetShown(DSW.IsTracking())
    warnTick:SetShown(DSW.UsesCustomWarning())
    spendTick:SetShown(DSW.SpendMessagesOn())
    overTick:SetShown(DSW.OverCapMessagesOn())
    spentText:SetText(DSW.Money(DSW.GetSpent()))
    overText:SetText(tostring(DSW.GetOverCount()))
end
DSW.RefreshUI = refresh

local function commitCap()
    local copper = DSW.ParseGold(capEdit:GetText())
    if copper then
        DSW.SetCap(copper)
        capEdit:SetText(tostring(copper / 10000))
    end
    capEdit:ClearFocus()
end

local function build()
    panel = CreateFrame("Frame", "DecorSpendwatchSettings", UIParent, "BackdropTemplate")
    panel:SetSize(320, 348)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    panel:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    table.insert(UISpecialFrames, "DecorSpendwatchSettings") -- close on Escape

    local title = label(panel, "Decor Spendwatch", GOLD, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)

    local close = flatButton(panel, "X", 24)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function()
        panel:Hide()
    end)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
    divider:SetPoint("TOPLEFT", 18, -46)
    divider:SetPoint("TOPRIGHT", -18, -46)
    divider:SetHeight(1)

    local capLabel = label(panel, "Per-item gold cap", DIM)
    capLabel:SetPoint("TOPLEFT", 18, -62)

    capEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    capEdit:SetSize(120, 22)
    capEdit:SetPoint("TOPLEFT", 22, -82)
    capEdit:SetAutoFocus(false)
    capEdit:SetScript("OnEnterPressed", commitCap)
    capEdit:SetScript("OnEscapePressed", capEdit.ClearFocus)

    local setBtn = flatButton(panel, "Set", 56)
    setBtn:SetPoint("LEFT", capEdit, "RIGHT", 10, 0)
    setBtn:SetScript("OnClick", commitCap)

    -- tracking toggle
    local check = checkbox(panel)
    check:SetPoint("TOPLEFT", 22, -116)
    trackTick = check.tick
    check:SetScript("OnClick", function()
        DSW.SetTracking(not DSW.IsTracking())
    end)
    local checkLabel = label(panel, "Track decor spending", DIM)
    checkLabel:SetPoint("LEFT", check, "RIGHT", 10, 0)

    -- chat: running spend summary
    local spendCheck = checkbox(panel)
    spendCheck:SetPoint("TOPLEFT", 22, -146)
    spendTick = spendCheck.tick
    spendCheck:SetScript("OnClick", function()
        DSW.SetSpendMessages(not DSW.SpendMessagesOn())
    end)
    local spendLabel = label(panel, "Chat: decor spend summary", DIM)
    spendLabel:SetPoint("LEFT", spendCheck, "RIGHT", 10, 0)

    -- chat: per-purchase over-cap warning
    local overCheck = checkbox(panel)
    overCheck:SetPoint("TOPLEFT", 22, -176)
    overTick = overCheck.tick
    overCheck:SetScript("OnClick", function()
        DSW.SetOverCapMessages(not DSW.OverCapMessagesOn())
    end)
    local overMsgLabel = label(panel, "Chat: over-cap warning", DIM)
    overMsgLabel:SetPoint("LEFT", overCheck, "RIGHT", 10, 0)

    -- custom tooltip warning toggle. Turning it on opens the editor so there is
    -- always some text to edit. The Edit button reopens it afterwards.
    local warnCheck = checkbox(panel)
    warnCheck:SetPoint("TOPLEFT", 22, -206)
    warnTick = warnCheck.tick
    warnCheck:SetScript("OnClick", function()
        local on = not DSW.UsesCustomWarning()
        DSW.SetCustomWarning(on)
        if on then
            DSW.OpenWarningEditor()
        end
    end)
    local warnLabel = label(panel, "Use custom tooltip warning", DIM)
    warnLabel:SetPoint("LEFT", warnCheck, "RIGHT", 10, 0)

    local editBtn = flatButton(panel, "Edit", 56)
    editBtn:SetPoint("TOPRIGHT", -18, -203)
    editBtn:SetScript("OnClick", DSW.OpenWarningEditor)

    -- readouts
    local spentLabel = label(panel, "Spent on decor", DIM)
    spentLabel:SetPoint("TOPLEFT", 18, -248)
    spentText = label(panel, "", { 1, 1, 1 })
    spentText:SetPoint("TOPRIGHT", -18, -248)

    local overLabel = label(panel, "Times over budget", DIM)
    overLabel:SetPoint("TOPLEFT", 18, -272)
    overText = label(panel, "", { 1, 0.35, 0.35 })
    overText:SetPoint("TOPRIGHT", -18, -272)

    local resetBtn = flatButton(panel, "Reset totals", 110)
    resetBtn:SetPoint("TOPLEFT", overLabel, "BOTTOMLEFT", 0, -16)
    resetBtn:SetScript("OnClick", DSW.ResetTotals)

    -- CreateFrame yields a shown frame. Start hidden so the first toggle opens it.
    panel:Hide()
end

local function buildEditor()
    editorPanel = CreateFrame("Frame", "DecorSpendwatchWarningEditor", UIParent, "BackdropTemplate")
    editorPanel:SetSize(380, 230)
    editorPanel:SetPoint("CENTER", 0, -20)
    editorPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    editorPanel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    editorPanel:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    editorPanel:SetBackdropBorderColor(0, 0, 0, 1)
    editorPanel:EnableMouse(true)
    editorPanel:SetMovable(true)
    editorPanel:RegisterForDrag("LeftButton")
    editorPanel:SetScript("OnDragStart", editorPanel.StartMoving)
    editorPanel:SetScript("OnDragStop", editorPanel.StopMovingOrSizing)
    table.insert(UISpecialFrames, "DecorSpendwatchWarningEditor") -- close on Escape

    local title = label(editorPanel, "Tooltip warning text", GOLD, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)

    local hint = label(editorPanel, "Type {cap} where the gold cap should appear.", DIM)
    hint:SetPoint("TOPLEFT", 18, -44)

    -- bordered box that the scrolling edit box sits inside
    local box = CreateFrame("Frame", nil, editorPanel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 18, -66)
    box:SetPoint("TOPRIGHT", -18, -66)
    box:SetHeight(96)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(0.1, 0.1, 0.13, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    warnEdit = CreateFrame("EditBox", nil, scroll)
    warnEdit:SetMultiLine(true)
    warnEdit:SetFontObject("ChatFontNormal")
    warnEdit:SetAutoFocus(false)
    warnEdit:SetWidth(320)
    warnEdit:SetScript("OnEscapePressed", warnEdit.ClearFocus)
    scroll:SetScrollChild(warnEdit)
    -- clicking anywhere in the box focuses the edit box
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function()
        warnEdit:SetFocus()
    end)

    local saveBtn = flatButton(editorPanel, "Save", 80)
    saveBtn:SetPoint("BOTTOMRIGHT", -18, 16)
    saveBtn:SetScript("OnClick", function()
        DSW.SetWarningText(warnEdit:GetText())
        editorPanel:Hide()
    end)

    local cancelBtn = flatButton(editorPanel, "Cancel", 80)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function()
        editorPanel:Hide()
    end)

    local defaultBtn = flatButton(editorPanel, "Default", 80)
    defaultBtn:SetPoint("BOTTOMLEFT", 18, 16)
    defaultBtn:SetScript("OnClick", function()
        warnEdit:SetText(DSW.DEFAULT_WARNING)
    end)

    editorPanel:Hide()
end

function DSW.OpenWarningEditor()
    if not editorPanel then
        buildEditor()
    end
    warnEdit:SetText(DSW.GetWarningText())
    editorPanel:Show()
    warnEdit:SetCursorPosition(warnEdit:GetText():len())
end

function DSW.OpenSettings()
    if not panel then
        build()
    end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    local g = DSW.GetCap() / 10000
    capEdit:SetText(g > 0 and tostring(g) or "")
    refresh()
    panel:Show()
end
