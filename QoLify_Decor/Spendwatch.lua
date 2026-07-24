local _, DCR = ...

-- The spend tracker window (/dsw). Dark panel, gold accents, flat controls,
-- composed from the Widgets.lua pieces. Built the first time it is opened so
-- we never touch frames before login.

local DIM = DCR.COLOR_DIM
local label, flatButton, checkbox = DCR.Label, DCR.FlatButton, DCR.Checkbox

local panel, capEdit, trackTick, warnTick, spendTick, overTick, spentText, overText
local editorPanel, warnEdit

local function refresh()
    if not panel then
        return
    end
    trackTick:SetShown(DCR.IsTracking())
    warnTick:SetShown(DCR.UsesCustomWarning())
    spendTick:SetShown(DCR.SpendMessagesOn())
    overTick:SetShown(DCR.OverCapMessagesOn())
    spentText:SetText(DCR.Money(DCR.GetSpent()))
    overText:SetText(tostring(DCR.GetOverCount()))
end
DCR.RefreshUI = refresh

local function commitCap()
    local copper = DCR.ParseGold(capEdit:GetText())
    if copper then
        DCR.SetCap(copper)
        capEdit:SetText(tostring(copper / 10000))
    end
    capEdit:ClearFocus()
end

local function build()
    panel = DCR.Window("DecorSpendwatchSettings", 320, 348, "Decor Spendwatch")

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
        DCR.SetTracking(not DCR.IsTracking())
    end)
    local checkLabel = label(panel, "Track decor spending", DIM)
    checkLabel:SetPoint("LEFT", check, "RIGHT", 10, 0)

    -- chat: running spend summary
    local spendCheck = checkbox(panel)
    spendCheck:SetPoint("TOPLEFT", 22, -146)
    spendTick = spendCheck.tick
    spendCheck:SetScript("OnClick", function()
        DCR.SetSpendMessages(not DCR.SpendMessagesOn())
    end)
    local spendLabel = label(panel, "Chat: decor spend summary", DIM)
    spendLabel:SetPoint("LEFT", spendCheck, "RIGHT", 10, 0)

    -- chat: per-purchase over-cap warning
    local overCheck = checkbox(panel)
    overCheck:SetPoint("TOPLEFT", 22, -176)
    overTick = overCheck.tick
    overCheck:SetScript("OnClick", function()
        DCR.SetOverCapMessages(not DCR.OverCapMessagesOn())
    end)
    local overMsgLabel = label(panel, "Chat: over-cap warning", DIM)
    overMsgLabel:SetPoint("LEFT", overCheck, "RIGHT", 10, 0)

    -- custom tooltip warning toggle. Turning it on opens the editor so there is
    -- always some text to edit. The Edit button reopens it afterwards.
    local warnCheck = checkbox(panel)
    warnCheck:SetPoint("TOPLEFT", 22, -206)
    warnTick = warnCheck.tick
    warnCheck:SetScript("OnClick", function()
        local on = not DCR.UsesCustomWarning()
        DCR.SetCustomWarning(on)
        if on then
            DCR.OpenWarningEditor()
        end
    end)
    local warnLabel = label(panel, "Use custom tooltip warning", DIM)
    warnLabel:SetPoint("LEFT", warnCheck, "RIGHT", 10, 0)

    local editBtn = flatButton(panel, "Edit", 56)
    editBtn:SetPoint("TOPRIGHT", -18, -203)
    editBtn:SetScript("OnClick", DCR.OpenWarningEditor)

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
    resetBtn:SetScript("OnClick", DCR.ResetTotals)

    -- CreateFrame yields a shown frame. Start hidden so the first toggle opens it.
    panel:Hide()
end

local function buildEditor()
    editorPanel = DCR.Window("DecorSpendwatchWarningEditor", 380, 230, "Tooltip warning text")
    editorPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    editorPanel:SetPoint("CENTER", 0, -20)

    local hint = label(editorPanel, "Type {cap} where the gold cap should appear.", DIM)
    hint:SetPoint("TOPLEFT", 18, -54)

    -- bordered box that the scrolling edit box sits inside
    local box = CreateFrame("Frame", nil, editorPanel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 18, -76)
    box:SetPoint("TOPRIGHT", -18, -76)
    box:SetHeight(86)
    box:SetBackdrop({ bgFile = DCR.WHITE, edgeFile = DCR.WHITE, edgeSize = 1 })
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
        DCR.SetWarningText(warnEdit:GetText())
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
        warnEdit:SetText(DCR.DEFAULT_WARNING)
    end)

    editorPanel:Hide()
end

function DCR.OpenWarningEditor()
    if not editorPanel then
        buildEditor()
    end
    warnEdit:SetText(DCR.GetWarningText())
    editorPanel:Show()
    warnEdit:SetCursorPosition(warnEdit:GetText():len())
end

function DCR.OpenSettings()
    if not panel then
        build()
    end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    local g = DCR.GetCap() / 10000
    capEdit:SetText(g > 0 and tostring(g) or "")
    refresh()
    panel:Show()
end
