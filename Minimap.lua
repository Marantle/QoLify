local ADDON, QLF = ...

-- Minimap button. Left-click opens a small picker window listing the loaded
-- modules to open one (or the settings directly while no module is loaded).
-- Right-click always opens the settings. Goes through LibDBIcon so button
-- collector addons can manage it.

local broker = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, {
    type = "launcher",
    icon = "Interface\\Icons\\INV_Misc_Gift_01",
    OnClick = function(_, mouse)
        if mouse == "RightButton" then
            QLF.OpenSettings()
        else
            QLF.ToggleModulePicker()
        end
    end,
    OnTooltipShow = function(tt)
        tt:SetText(ADDON)
        tt:AddLine("Click: open a module.", 1, 1, 1)
        tt:AddLine("Right-click: open the settings.", 1, 1, 1)
    end,
})
-- The modules the picker offers: enabled and actually loaded this session.
-- "Active until reload" modules are left out. The user just disabled them.
local function LoadedModules()
    local out = {}
    for _, m in ipairs(QLF.moduleList) do
        if QLF.Modules_IsEnabled(m.name) and C_AddOns.IsAddOnLoaded(m.name) then
            out[#out + 1] = m
        end
    end
    return out
end

local function OpenModule(m)
    -- A module with a window opens it. The rest open their settings page
    -- (which also covers standby modules, whose page says so).
    local launch = QLF.moduleLaunchers[m.name]
    if launch then
        launch()
    else
        QLF.OpenModuleSettings(m.name)
    end
end

-- Module picker window, styled like the Decor Spendwatch panel (dark, flat,
-- gold accents). It opens at the cursor on the TOOLTIP strata so nothing can
-- cover it, and closes as soon as a module is picked.
local WHITE = "Interface/Buttons/WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local PAD = 12
local ROW_H = 26
local ROWS_TOP = 40

local picker

local function PickerButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(146, 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.16, 0.16, 0.2, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER", 0, -1)
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

local function BuildPicker()
    picker = CreateFrame("Frame", "QoLifyModulePicker", UIParent, "BackdropTemplate")
    picker:SetWidth(170)
    picker:SetFrameStrata("TOOLTIP")
    picker:SetClampedToScreen(true)
    picker:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    picker:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    picker:SetBackdropBorderColor(0, 0, 0, 1)
    picker:EnableMouse(true)
    table.insert(UISpecialFrames, "QoLifyModulePicker") -- close on Escape

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -10)
    title:SetText(ADDON)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    local divider = picker:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
    divider:SetPoint("TOPLEFT", PAD, -30)
    divider:SetPoint("TOPRIGHT", -PAD, -30)
    divider:SetHeight(1)

    picker.rows = {}
    picker.settingsRow = PickerButton(picker)
    picker.settingsRow.text:SetText("Settings")
    picker.settingsRow:SetScript("OnClick", function()
        picker:Hide()
        QLF.OpenSettings()
    end)
    picker:Hide()
end

function QLF.ToggleModulePicker()
    if picker and picker:IsShown() then
        picker:Hide()
        return
    end
    local modules = LoadedModules()
    if #modules == 0 then
        QLF.OpenSettings()
        return
    end
    if not picker then
        BuildPicker()
    end
    for i, m in ipairs(modules) do
        local row = picker.rows[i]
        if not row then
            row = PickerButton(picker)
            row:SetPoint("TOPLEFT", PAD, -(ROWS_TOP + (i - 1) * ROW_H))
            picker.rows[i] = row
        end
        row.text:SetText((m.title:gsub("^" .. ADDON .. ":%s*", "")))
        row:SetScript("OnClick", function()
            picker:Hide()
            OpenModule(m)
        end)
        row:Show()
    end
    for i = #modules + 1, #picker.rows do
        picker.rows[i]:Hide()
    end
    picker.settingsRow:ClearAllPoints()
    picker.settingsRow:SetPoint("TOPLEFT", PAD, -(ROWS_TOP + #modules * ROW_H + 6))
    picker:SetHeight(ROWS_TOP + #modules * ROW_H + 6 + ROW_H + PAD - 2)

    -- Anchored to the cursor rather than the button, so it lands in the right
    -- place even when a button bag addon has relocated the minimap button.
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 20, y / scale + 8)
    picker:Show()
end

-- Called by the bootstrap once QoLifyDB is merged.
function QLF.Minimap_Init()
    QoLifyDB.minimap = QoLifyDB.minimap or {}
    local db = QoLifyDB.minimap
    -- The pre-LibDBIcon button stored its spot in db.angle, same unit
    -- (degrees), so existing buttons keep their place.
    if db.angle then
        db.minimapPos = db.minimapPos or db.angle
        db.angle = nil
    end
    LibStub("LibDBIcon-1.0"):Register(ADDON, broker, db)
end
