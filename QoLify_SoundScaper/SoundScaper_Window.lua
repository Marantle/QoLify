local _, SS = ...

local WIN_W = 530
local WIN_H = 390
local TITLE_H = 26
local PAD = 10
local TAB_W = 80
local TAB_H = 22
local TAB_GAP = 4
local ROW_H = 30
local SLIDER_W = 240

-- Y offsets shared between the context panel and the copy panel
local OVERRIDE_Y = TITLE_H + 8 + TAB_H + 52
local ROWS_TOP = OVERRIDE_Y + 28

local CHAR_ROW_H = 26
local MAX_CHAR_ROWS = 6

SS.Window = {}
local W = SS.Window

local frame
local tabs = {} -- one button per context, plus the copy tab
local rows = {} -- one row per audio channel
local ncRow -- the channel-count row below them
local charRows = {} -- one row per other character, built on demand
local selected = "world"
local updating = false -- guards OnValueChanged while we push values into widgets
local headerFS, descFS, statusFS, overrideCB, overrideFS, enableCB, applyBtn, copyBtn

-- Palette and widget factories: every color and repeated widget lives here once.

local COLORS = {
    accent = { 0.25, 0.6, 0.9 }, -- slider fill, addon identity color
    gold = { 1, 0.82, 0 }, -- normal labels
    white = { 1, 1, 1 },
    green = { 0.4, 1, 0.4 }, -- tab of the profile currently in force
    red = { 1, 0.4, 0.4 }, -- muted / addon off
    redDark = { 0.4, 0.2, 0.2 }, -- slider fill while muted
    dim = { 0.5, 0.5, 0.5 }, -- de-emphasized text
    disabled = { 0.4, 0.4, 0.4 }, -- non-editable rows
    grey = { 0.3, 0.3, 0.3 }, -- non-editable slider fill
}

local function Tint(region, c)
    if region.SetTextColor then
        region:SetTextColor(c[1], c[2], c[3])
    else
        region:SetVertexColor(c[1], c[2], c[3])
    end
end

local function NewCheck(parent, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetScript("OnClick", onClick)
    return cb
end

-- Hand-built slider: no template, so it cannot break when Blizzard reworks
-- OptionsSliderTemplate's parentKeys again.
local function NewSlider(parent, min, max, step)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(SLIDER_W, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(0, 0, -5, -5)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    track:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(6)
    fill:SetColorTexture(1, 1, 1, 1)
    Tint(fill, COLORS.accent)

    slider:SetThumbTexture("Interface/Buttons/UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(14, 20)

    return slider, fill
end

local function NewButton(parent, width, text, onClick, tooltipLines)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if tooltipLines then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            for _, line in ipairs(tooltipLines) do
                GameTooltip:AddLine(line, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    return b
end

-- data access

local function Profile(key)
    local db = SS.db
    return db and db.profiles and db.profiles[key or selected]
end

local function SavePos()
    if SS.db and SS.db.win and frame then
        SS.db.win.x = math.floor(frame:GetLeft() or 400)
        SS.db.win.y = math.floor(frame:GetBottom() or 300)
    end
end

-- Edits should be audible immediately when you are editing the profile that is
-- currently in force, so dragging a slider behaves like the Blizzard options.
local function PreviewIfLive()
    if not SS.db.enabled then
        return
    end
    if SS.Context:Resolve(SS.Context:Current()) ~= selected then
        return
    end
    SS.Sound:ApplyProfile(Profile(selected))
end

-- refresh

local function RefreshRow(i)
    local row = rows[i]
    local profile = Profile()
    local c = profile and profile[row.key]
    if not c then
        return
    end

    updating = true
    row.slider:SetValue(c.volume or 100)
    row.mute:SetChecked(c.mute and true or false)
    updating = false

    row.fill:SetWidth(math.max(1, SLIDER_W * ((c.volume or 100) / 100)))

    if c.mute then
        row.slider:Disable()
        row.value:SetText("Muted")
        Tint(row.value, COLORS.red)
        Tint(row.label, COLORS.dim)
        Tint(row.fill, COLORS.redDark)
    else
        row.slider:Enable()
        row.value:SetText((c.volume or 100) .. "%")
        Tint(row.value, COLORS.white)
        Tint(row.label, COLORS.gold)
        Tint(row.fill, COLORS.accent)
    end
end

local function RefreshNumChannelsRow()
    local profile = Profile()
    if not (ncRow and profile) then
        return
    end

    local nc = SS.NUM_CHANNELS
    local n = profile.numChannels or nc.default

    updating = true
    ncRow.slider:SetValue(n)
    updating = false

    ncRow.fill:SetWidth(math.max(1, SLIDER_W * ((n - nc.min) / (nc.max - nc.min))))
    ncRow.slider:Enable()
    ncRow.value:SetText(tostring(n))
    Tint(ncRow.value, COLORS.white)
    Tint(ncRow.label, COLORS.gold)
    Tint(ncRow.fill, COLORS.accent)
end

function W:RefreshStatus()
    if not statusFS then
        return
    end

    if not SS.db.enabled then
        statusFS:SetText("|cffff6666SoundScaper is off|r - nothing is being applied.")
    else
        local live = SS.Context:Current()
        local used = SS.Context:Resolve(live)
        local liveCtx, usedCtx = SS.CONTEXT_BY_KEY[live], SS.CONTEXT_BY_KEY[used]
        local text = "You are in: |cff66ccff" .. (liveCtx and liveCtx.label or live) .. "|r"
        if usedCtx and used ~= live then
            text = text .. "  (using |cff66ccff" .. usedCtx.label .. "|r settings)"
        end
        statusFS:SetText(text)
    end

    for _, tab in ipairs(tabs) do
        local fs = tab:GetFontString()
        if fs then
            local inForce = SS.db.enabled and tab.key == SS.Context:Resolve(SS.Context:Current())
            Tint(fs, inForce and COLORS.green or COLORS.gold)
        end
    end
end

-- Called by the sound module when a live CVar change was learned into a
-- profile, so an open window showing that section tracks the Blizzard panel.
function W:OnLiveLearn(key)
    if frame and frame:IsShown() and selected == key then
        W:Refresh()
    end
end

-- copy panel

local function EnsureCharRow(i)
    local row = charRows[i]
    if row then
        return row
    end

    local y = ROWS_TOP + (i - 1) * CHAR_ROW_H
    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(CHAR_ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)

    if i % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", row, "LEFT", 4, 0)
    name:SetJustifyH("LEFT")
    row.name = name

    local btn = NewButton(row, 70, "Copy", function()
        if SS.CopyFrom(row.charKey) then
            SS.Print("copied sound settings from " .. row.charKey)
            W:Refresh()
        end
    end, { "Replace every section on this character", "with this character's settings." })
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    charRows[i] = row
    return row
end

local function RefreshCopyPanel()
    headerFS:SetText("Copy from another character")

    local others = SS.OtherChars()
    if #others == 0 then
        descFS:SetText(
            "No other characters yet. Settings are saved per character, and each one shows up here after logging in once with the addon loaded."
        )
    elseif #others > MAX_CHAR_ROWS then
        descFS:SetText(
            "Copies every section from that character to "
                .. SS.charKey
                .. ". Showing "
                .. MAX_CHAR_ROWS
                .. " of "
                .. #others
                .. " characters."
        )
    else
        descFS:SetText("Copies every section from that character to " .. SS.charKey .. ".")
    end

    local shown = math.min(#others, MAX_CHAR_ROWS)
    for i = 1, shown do
        local row = EnsureCharRow(i)
        row.charKey = others[i]
        row.name:SetText(others[i])
        row:Show()
    end
    for i = shown + 1, #charRows do
        charRows[i]:Hide()
    end
end

function W:Refresh()
    if not frame then
        return
    end

    local isCopy = selected == "copy"

    for _, tab in ipairs(tabs) do
        if tab.key == selected then
            tab:LockHighlight()
        else
            tab:UnlockHighlight()
        end
    end

    for _, row in ipairs(rows) do
        row:SetShown(not isCopy)
    end
    ncRow:SetShown(not isCopy)
    applyBtn:SetShown(not isCopy)
    copyBtn:SetShown(not isCopy)

    if isCopy then
        overrideCB:Hide()
        overrideFS:SetText("")
        RefreshCopyPanel()
    else
        for i = 1, #charRows do
            charRows[i]:Hide()
        end

        local ctx = SS.CONTEXT_BY_KEY[selected]
        headerFS:SetText(ctx.label)
        descFS:SetText(ctx.desc)

        -- Only the two override contexts get a checkbox. The base three always apply.
        if ctx.parent then
            local parent = SS.CONTEXT_BY_KEY[ctx.parent]
            overrideCB:Show()
            overrideCB:SetChecked(Profile() and Profile().override or false)
            overrideFS:SetText("Use separate settings here (otherwise " .. parent.label .. " applies)")
            Tint(overrideFS, COLORS.white)
        else
            overrideCB:Hide()
            overrideFS:SetText("Always applied.")
            Tint(overrideFS, COLORS.dim)
        end

        -- Grey out the sliders when an override context is switched off: its values
        -- are not what will play, and pretending otherwise is just misleading.
        local editable = (not ctx.parent) or (Profile() and Profile().override)
        for i, row in ipairs(rows) do
            RefreshRow(i)
            if not editable then
                row.slider:Disable()
                row.mute:Disable()
                Tint(row.label, COLORS.disabled)
                Tint(row.value, COLORS.disabled)
                Tint(row.fill, COLORS.grey)
            else
                row.mute:Enable()
            end
        end

        RefreshNumChannelsRow()
        if not editable then
            ncRow.slider:Disable()
            Tint(ncRow.label, COLORS.disabled)
            Tint(ncRow.value, COLORS.disabled)
            Tint(ncRow.fill, COLORS.grey)
        end
    end

    enableCB:SetChecked(SS.db.enabled and true or false)
    W:RefreshStatus()
end

-- construction

local function BuildTabs()
    local entries = {}
    for i, ctx in ipairs(SS.CONTEXTS) do
        entries[i] = { key = ctx.key, label = ctx.label }
    end
    entries[#entries + 1] = { key = "copy", label = "Copy" }

    for i, entry in ipairs(entries) do
        local tab = NewButton(frame, TAB_W, entry.label, function()
            selected = entry.key
            W:Refresh()
        end)
        tab:SetHeight(TAB_H)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (TAB_W + TAB_GAP), -(TITLE_H + 8))
        tab.key = entry.key
        tabs[i] = tab
    end
end

local function BuildRow(i, ch, topOffset)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -topOffset)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -topOffset)
    row.key = ch.key

    if i % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWidth(62)
    label:SetJustifyH("LEFT")
    label:SetText(ch.label)
    row.label = label

    local slider, fill = NewSlider(row, 0, 100, 1)
    slider:SetPoint("LEFT", row, "LEFT", 66, 0)
    row.slider = slider
    row.fill = fill

    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    value:SetWidth(46)
    value:SetJustifyH("LEFT")
    row.value = value

    local mute = NewCheck(row, function(self)
        local c = Profile() and Profile()[ch.key]
        if not c then
            return
        end
        c.mute = self:GetChecked() and true or false
        RefreshRow(i)
        PreviewIfLive()
    end)
    mute:SetPoint("LEFT", value, "RIGHT", 4, 0)
    row.mute = mute

    local muteFS = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    muteFS:SetPoint("LEFT", mute, "RIGHT", 2, 0)
    muteFS:SetText("Mute")

    slider:SetScript("OnValueChanged", function(_, v)
        if updating then
            return
        end
        local c = Profile() and Profile()[ch.key]
        if not c then
            return
        end
        c.volume = math.floor(v + 0.5)
        RefreshRow(i)
        PreviewIfLive()
    end)

    rows[i] = row
end

-- The channel-count row sits below the five volume rows and drives
-- Sound_NumChannels, how many sounds the game will play at the same time.
local function BuildNumChannelsRow(topOffset)
    local nc = SS.NUM_CHANNELS

    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -topOffset)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -topOffset)

    -- Sixth row, so it keeps the even-row stripe going.
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.03)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWidth(62)
    label:SetJustifyH("LEFT")
    label:SetText("Channels")
    row.label = label

    local slider, fill = NewSlider(row, nc.min, nc.max, nc.step)
    slider:SetPoint("LEFT", row, "LEFT", 66, 0)
    row.slider = slider
    row.fill = fill

    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    value:SetWidth(46)
    value:SetJustifyH("LEFT")
    row.value = value

    local noteFS = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteFS:SetPoint("LEFT", value, "RIGHT", 4, 0)
    noteFS:SetText("sounds at once")

    slider:SetScript("OnValueChanged", function(_, v)
        if updating then
            return
        end
        local p = Profile()
        if not p then
            return
        end
        p.numChannels = math.floor(v + 0.5)
        RefreshNumChannelsRow()
        PreviewIfLive()
    end)

    ncRow = row
end

function W:Build()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "SoundScaperWindow", UIParent, "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    -- Title bar (drag handle)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(TITLE_H - 2)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePos()
    end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.14, 0.14, 0.14, 1)

    local titleFS = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    titleFS:SetText("SoundScaper")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 0)
    closeBtn:SetScript("OnClick", function()
        W:Hide()
    end)

    BuildTabs()

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + 8 + TAB_H + 8))
    sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_H + 8 + TAB_H + 8))
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    headerFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + 8 + TAB_H + 16))

    descFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + 8 + TAB_H + 34))
    descFS:SetWidth(WIN_W - PAD * 2)
    descFS:SetJustifyH("LEFT")

    -- Override row: checkbox for Mythic+ / Raid Boss, dim note for the rest.
    overrideCB = NewCheck(frame, function(self)
        local p = Profile()
        if p then
            p.override = self:GetChecked() and true or false
        end
        W:Refresh()
        if SS.db.enabled then
            SS.Context:Apply()
        end
    end)
    overrideCB:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 3, -OVERRIDE_Y)

    overrideFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overrideFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 22, -(OVERRIDE_Y + 5))
    overrideFS:SetWidth(WIN_W - PAD * 2 - 22)
    overrideFS:SetJustifyH("LEFT")

    for i, ch in ipairs(SS.CHANNELS) do
        BuildRow(i, ch, ROWS_TOP + (i - 1) * ROW_H)
    end
    BuildNumChannelsRow(ROWS_TOP + #SS.CHANNELS * ROW_H)

    statusFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(ROWS_TOP + (#SS.CHANNELS + 1) * ROW_H + 8))
    statusFS:SetWidth(WIN_W - PAD * 2)
    statusFS:SetJustifyH("LEFT")

    -- Bottom bar
    enableCB = NewCheck(frame, function(self)
        SS.SetEnabled(self:GetChecked() and true or false)
    end)
    enableCB:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD - 3, PAD)

    local enableFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    enableFS:SetPoint("LEFT", enableCB, "RIGHT", 2, 0)
    enableFS:SetText("Enabled")

    applyBtn = NewButton(frame, 80, "Apply Now", function()
        SS.Sound:ApplyProfile(Profile())
    end, { "Apply this section's settings right now,", "without waiting to zone into it." })
    applyBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

    copyBtn = NewButton(frame, 120, "Copy Live Sound", function()
        local snapshot = SS.Sound:Snapshot()
        local p = Profile()
        if not p then
            return
        end
        for _, ch in ipairs(SS.CHANNELS) do
            p[ch.key].volume = snapshot[ch.key].volume
            p[ch.key].mute = snapshot[ch.key].mute
        end
        p.numChannels = snapshot.numChannels
        W:Refresh()
    end, { "Copy the game's current sound settings", "into this section." })
    copyBtn:SetPoint("RIGHT", applyBtn, "LEFT", -6, 0)

    frame:Hide()
    W.frame = frame
end

-- public API

function W:Show()
    if not frame then
        W:Build()
    end

    frame:ClearAllPoints()
    local win = SS.db and SS.db.win
    if win and win.x then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", win.x, win.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    -- Open on whatever context you are actually standing in.
    selected = SS.Context:Current() or "world"
    W:Refresh()
    frame:Show()

    if win then
        win.visible = true
    end
end

function W:Hide()
    if frame then
        frame:Hide()
    end
    if SS.db and SS.db.win then
        SS.db.win.visible = false
    end
end

function W:Toggle()
    if frame and frame:IsShown() then
        W:Hide()
    else
        W:Show()
    end
end
