local ADDON, QLF = ...

-- Every discovered module gets its own settings subcategory page, registered
-- at login BEFORE any module loads (title/notes come from TOC metadata, so no
-- module code is needed). Each page carries the module's enable toggle. Its
-- option checkboxes populate from QLF.moduleOptions once the module loads.
-- Mid-session category registration never shows in the tree, which is why the
-- core registers all pages up front. The main page renders the QoL feature
-- options (QLF.qolOptions) above an overview row per module.

local ACCENT = "|cff99ccff"
local PAD = 16
local OPTION_H = 36
local OPTIONS_TOP = 104

-- Components ---------------------------------------------------------------

local function Label(parent, template, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", template)
    fs:SetJustifyH("LEFT")
    if text then
        fs:SetText(text)
    end
    return fs
end

local function CreateOptionRow(parent)
    local row = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    row:SetSize(24, 24)
    row.title = Label(row, "GameFontHighlight")
    row.title:SetPoint("LEFT", row, "RIGHT", 6, 6)
    row.notes = Label(row, "GameFontDisableSmall")
    row.notes:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row:SetScript("OnClick", function(self)
        self.option.SetEnabled(self:GetChecked() and true or false)
    end)
    return row
end

local function CreateButtonRow(parent)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(160, 22)
    btn.notes = Label(btn, "GameFontDisableSmall")
    btn.notes:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    btn:SetScript("OnClick", function(self)
        self.option.OnClick()
    end)
    return btn
end

local function CreateChoiceRow(parent)
    local row = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    row:SetSize(150, 24)
    row.title = Label(row, "GameFontHighlight")
    row.title:SetPoint("LEFT", row, "RIGHT", 8, 6)
    row.notes = Label(row, "GameFontDisableSmall")
    row.notes:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row:SetupMenu(function(_, rootDescription)
        local opt = row.option
        if not opt then
            return
        end
        for _, choice in ipairs(opt.choices) do
            rootDescription:CreateRadio(choice.text, function(value)
                return opt.Get() == value
            end, function(value)
                opt.Set(value)
            end, choice.value)
        end
    end)
    return row
end

local function CreateReloadButton(parent)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(100, 22)
    btn:SetPoint("TOPRIGHT", -PAD, -PAD)
    btn:SetText("Reload UI")
    btn:SetScript("OnClick", function()
        C_UI.Reload()
    end)
    btn:Hide()
    return btn
end

-- Lays out a mixed list of option rows (checkbox, button or choice) on
-- holder, one per OPTION_H, starting at -top. holder carries the row pools
-- (optionRows/buttonRows/choiceRows). Rows left over from a previous layout
-- are hidden. Shared by the module pages and the main page's QoL block.
local function LayoutOptions(holder, opts, top)
    local nCheck, nButton, nChoice = 0, 0, 0
    for i = 1, (opts and #opts or 0) do
        local opt = opts[i]
        local y = -(top + (i - 1) * OPTION_H)
        if opt.type == "button" then
            nButton = nButton + 1
            local row = holder.buttonRows[nButton] or CreateButtonRow(holder)
            holder.buttonRows[nButton] = row
            row.option = opt
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD + 8, y)
            row:SetText(opt.text or opt.title)
            row.notes:SetText(opt.notes or "")
            row:Show()
        elseif opt.type == "choice" then
            nChoice = nChoice + 1
            local row = holder.choiceRows[nChoice] or CreateChoiceRow(holder)
            holder.choiceRows[nChoice] = row
            row.option = opt
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD + 8, y)
            row.title:SetText(opt.title)
            row.notes:SetText(opt.notes or "")
            row:GenerateMenu()
            row:Show()
        else
            nCheck = nCheck + 1
            local row = holder.optionRows[nCheck] or CreateOptionRow(holder)
            holder.optionRows[nCheck] = row
            row.option = opt
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD + 8, y)
            row.title:SetText(opt.title)
            row.notes:SetText(opt.notes or "")
            row:SetChecked(opt.IsEnabled())
            row:Show()
        end
    end
    for i = nCheck + 1, #holder.optionRows do
        holder.optionRows[i]:Hide()
    end
    for i = nButton + 1, #holder.buttonRows do
        holder.buttonRows[i]:Hide()
    end
    for i = nChoice + 1, #holder.choiceRows do
        holder.choiceRows[i]:Hide()
    end
end

-- Main page -----------------------------------------------------------------

local main = CreateFrame("Frame")
main.name = ADDON
main.optionRows = {}
main.buttonRows = {}
main.choiceRows = {}

Label(main, "GameFontNormalLarge", ACCENT .. ADDON .. "|r"):SetPoint("TOPLEFT", PAD, -PAD)
local mainSub = Label(
    main,
    "GameFontDisableSmall",
    "Small quality-of-life tweaks below, plus bigger modules with their own pages\n"
        .. "on the left. A module's code is only loaded once you enable it on its page."
)
mainSub:SetPoint("TOPLEFT", PAD, -44)

local qolHeader = Label(main, "GameFontNormal", "Quality of Life")
qolHeader:SetPoint("TOPLEFT", PAD, -80)
local modulesHeader = Label(main, "GameFontNormal", "Modules")

local category = Settings.RegisterCanvasLayoutCategory(main, ADDON)
Settings.RegisterAddOnCategory(category)

-- Status shared by the main page overview and the module pages. Reflects the
-- QoLify enable flag, whether code is loaded, and WoW's own AddOn list.
local function ModuleStatusText(name)
    if not QLF.Modules_IsAllowed(name) then
        return "|cffff4444disabled in WoW's AddOn list|r"
    end
    local enabled = QLF.Modules_IsEnabled(name)
    local loaded = C_AddOns.IsAddOnLoaded(name)
    if loaded and not enabled then
        return "|cffff9933active until reload|r"
    elseif enabled then
        return "|cff44ff44enabled|r"
    end
    return "|cff888888disabled|r"
end

-- The QoL feature options followed by one descriptive row per discovered
-- module. The QoL list is fixed after load, so the module block's offset is
-- stable and the rows keep their creation-time anchors.
local mainRows = {}
local function Main_Refresh()
    LayoutOptions(main, QLF.qolOptions, OPTIONS_TOP)
    local modulesTop = OPTIONS_TOP + #QLF.qolOptions * OPTION_H + 8
    modulesHeader:ClearAllPoints()
    modulesHeader:SetPoint("TOPLEFT", PAD, -modulesTop)
    for i, m in ipairs(QLF.moduleList) do
        local row = mainRows[i]
        if not row then
            row = {
                title = Label(main, "GameFontHighlight"),
                notes = Label(main, "GameFontDisableSmall"),
                status = Label(main, "GameFontDisableSmall"),
            }
            row.title:SetPoint("TOPLEFT", PAD + 8, -(modulesTop + 28 + (i - 1) * 44))
            row.notes:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
            row.status:SetPoint("LEFT", row.title, "RIGHT", 8, 0)
            mainRows[i] = row
        end
        row.title:SetText(m.title:gsub("^" .. ADDON .. ":%s*", ""))
        row.notes:SetText(m.notes or "")
        row.status:SetText(ModuleStatusText(m.name))
    end
end

main:SetScript("OnShow", Main_Refresh)
-- Created shown: without this the first display never fires OnShow (see
-- CreatePage for the same fix).
main:Hide()

-- Module pages ----------------------------------------------------------------

local function Refresh(page)
    local m = page.module
    local enabled = QLF.Modules_IsEnabled(m.name)
    local loaded = C_AddOns.IsAddOnLoaded(m.name)
    page.enable:SetChecked(enabled)
    -- The checkbox already conveys enabled/disabled. The status label only
    -- carries the states the checkbox can't express.
    if not QLF.Modules_IsAllowed(m.name) then
        page.status:SetText("|cffff4444disabled in WoW's AddOn list|r")
    elseif loaded and not enabled then
        page.status:SetText("|cffff9933active until reload|r")
    else
        page.status:SetText("")
    end
    page.reload:SetShown(loaded and not enabled)

    LayoutOptions(page, enabled and QLF.moduleOptions[m.name] or nil, OPTIONS_TOP)
end

local function Page_OnEnableClick(check)
    local page = check.page
    local m = page.module
    if check:GetChecked() then
        if QLF.Modules_SetEnabled(m.name, true) then
            print(ACCENT .. ADDON .. "|r: " .. m.title .. " loaded.")
        else
            QLF.Modules_SetEnabled(m.name, false)
            check:SetChecked(false)
        end
    else
        -- Loaded code cannot be unloaded, so a disabled module keeps working
        -- until reload. Say so, or the checkbox looks like it did nothing.
        if QLF.Modules_SetEnabled(m.name, false) then
            print(ACCENT .. ADDON .. "|r: " .. m.title .. " disabled. It stays active until you reload the UI.")
        end
    end
    Refresh(page)
end

local function CreatePage(m)
    local page = CreateFrame("Frame")
    page.module = m
    page.optionRows = {}
    page.buttonRows = {}
    page.choiceRows = {}

    Label(page, "GameFontNormalLarge", ACCENT .. m.title .. "|r"):SetPoint("TOPLEFT", PAD, -PAD)
    local notes = Label(page, "GameFontDisableSmall", m.notes)
    notes:SetPoint("TOPLEFT", PAD, -44)

    page.enable = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.enable:SetSize(26, 26)
    page.enable:SetPoint("TOPLEFT", PAD, -(OPTIONS_TOP - 38))
    page.enable.page = page
    page.enable:SetScript("OnClick", Page_OnEnableClick)
    local enableLabel = Label(page, "GameFontHighlight", "Enable this module")
    enableLabel:SetPoint("LEFT", page.enable, "RIGHT", 6, 0)
    page.status = Label(page, "GameFontDisableSmall", "")
    page.status:SetPoint("LEFT", enableLabel, "RIGHT", 8, 0)

    page.reload = CreateReloadButton(page)

    page:SetScript("OnShow", function()
        Refresh(page)
    end)
    -- Frames are created shown. Without this the page's first display after
    -- login has no Hide->Show transition, OnShow never fires, and the page
    -- renders stale (unchecked box, no option rows) until navigated away and
    -- back.
    page:Hide()
    return page
end

-- Called by the bootstrap right after the module scan, before enabled modules
-- load, so every page exists in the category tree from the start.
local subcategories = {}

function QLF.Settings_RegisterModulePages()
    for _, m in ipairs(QLF.moduleList) do
        -- No page for modules unticked in WoW's AddOn list: they cannot load
        -- this session, and re-ticking them needs a reload anyway, at which
        -- point the page returns. The main page still lists them with a red
        -- status so they don't vanish unexplained.
        if QLF.Modules_IsAllowed(m.name) then
            local shortName = m.title:gsub("^" .. ADDON .. ":%s*", "")
            subcategories[m.name] = Settings.RegisterCanvasLayoutSubcategory(category, CreatePage(m), shortName)
        end
    end
end

local function OpenCategory(cat)
    if InCombatLockdown() then
        print(ACCENT .. ADDON .. "|r: settings cannot be opened during combat.")
        return
    end
    -- 12.x requires the auto-assigned numeric ID. String IDs crash OpenSettingsPanel
    Settings.OpenToCategory(cat:GetID())
end

function QLF.OpenSettings()
    OpenCategory(category)
end

-- The minimap module picker's fallback for modules without a launcher.
function QLF.OpenModuleSettings(name)
    OpenCategory(subcategories[name] or category)
end
