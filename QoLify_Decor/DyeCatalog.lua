local _, DCR = ...

-- The game's dye picker only exists while customizing a piece at your
-- house, so the cart carries its own paint catalog: every purchasable dye,
-- one click to cart from anywhere. Everything builds lazily on first open,
-- the dye list is static data.

local GOLD = DCR.COLOR_GOLD

local SWATCH = 24
local GAP = 6
-- window width 320, minus the 18 side margins, the 6 scroll inset and the
-- 26 the scrollbar takes
local LIST_W = 252

local panel
local headers = {}

local function swatchEnter(self)
    self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    local info = C_DyeColor.GetDyeColorInfo(self.dyeColorID)
    if not info then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(info.name, 1, 1, 1)
    local buy = self.buyItemID and C_Item.GetItemNameByID(self.buyItemID)
    if buy then
        GameTooltip:AddLine("Made from " .. buy, 1, 1, 1)
    end
    if info.numOwned and info.numOwned > 0 then
        GameTooltip:AddLine("You have " .. info.numOwned, 1, 1, 1)
    end
    GameTooltip:AddLine("Add to cart. Shift: add 5, Ctrl: add 10", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function swatchClick(self)
    local info = C_DyeColor.GetDyeColorInfo(self.dyeColorID)
    local count = DCR.ClickStep()
    DCR.CartFlyFX(info and DCR.AddDyeEntry(info, count), count)
end

local function makeSwatch(parent, info, shared)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SWATCH, SWATCH)
    b:SetBackdrop({ bgFile = DCR.WHITE, edgeFile = DCR.WHITE, edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 0)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    b.dyeColorID = info.ID
    -- set only for colors sharing their item with others
    b.buyItemID = shared and info.itemID or nil
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexture(DCR.WHITE)
    local s, e = info.swatchColorStart, info.swatchColorEnd
    tex:SetGradient("HORIZONTAL", CreateColor(s.r, s.g, s.b, 1), CreateColor(e.r, e.g, e.b, 1))
    b:SetScript("OnEnter", swatchEnter)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", swatchClick)
    return b
end

local function colsIn(width)
    return math.max(1, math.floor((width + GAP) / (SWATCH + GAP)))
end

-- Swatches left to right, wrapping at the panel edge. Height used comes back.
local function gridOf(content, dyes, y, shared)
    local cols = colsIn(LIST_W)
    for i, info in ipairs(dyes) do
        local swatch = makeSwatch(content, info, shared)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        swatch:SetPoint("TOPLEFT", col * (SWATCH + GAP), -(y + row * (SWATCH + GAP)))
    end
    return math.ceil(#dyes / cols) * (SWATCH + GAP)
end

-- Colors grouped by the item that buys them.
local function families()
    local byItem, order = {}, {}
    for _, id in ipairs(C_DyeColor.GetAllDyeColors()) do
        local info = C_DyeColor.GetDyeColorInfo(id)
        -- no item means nothing to buy, the picker-only entries stay out
        if info and info.itemID then
            local fam = byItem[info.itemID]
            if not fam then
                fam = { itemID = info.itemID }
                byItem[info.itemID] = fam
                order[#order + 1] = fam
            end
            fam[#fam + 1] = info
        end
    end
    for _, fam in ipairs(order) do
        table.sort(fam, function(a, b)
            return a.sortOrder < b.sortOrder
        end)
    end
    table.sort(order, function(a, b)
        return a[1].sortOrder < b[1].sortOrder
    end)
    return order
end

-- Item names and icons are cold for a while after login, so a header takes
-- the leading color's name until the real one turns up and tries again on
-- every open.
local function refreshHeaders()
    for _, h in ipairs(headers) do
        local name = C_Item.GetItemNameByID(h.itemID)
        if name then
            h.text:SetText(name)
        end
        h.icon:SetTexture(C_Item.GetItemIconByID(h.itemID))
    end
end

local function itemHeader(content, fam, y)
    local icon = content:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", 0, -y)
    local text = DCR.Label(content, fam[1].name, GOLD)
    text:SetPoint("TOPLEFT", 22, -(y + 1))
    headers[#headers + 1] = { itemID = fam.itemID, icon = icon, text = text }
    return 20
end

local function byItem(content, fams)
    local y = 0
    for _, fam in ipairs(fams) do
        y = y + itemHeader(content, fam, y)
        y = y + gridOf(content, fam, y, #fam > 1) + 8
    end
    return y
end

local function byCategory(content)
    local cats = C_DyeColor.GetAllDyeColorCategories()
    table.sort(cats)
    local y = 0
    for _, catID in ipairs(cats) do
        local dyes = {}
        for _, id in ipairs(C_DyeColor.GetDyeColorsInCategory(catID)) do
            local info = C_DyeColor.GetDyeColorInfo(id)
            if info and info.itemID then
                table.insert(dyes, info)
            end
        end
        if #dyes > 0 then
            table.sort(dyes, function(a, b)
                return a.sortOrder < b.sortOrder
            end)
            local cat = C_DyeColor.GetDyeColorCategoryInfo(catID)
            local header = DCR.Label(content, cat and cat.name or "Dyes", GOLD)
            header:SetPoint("TOPLEFT", 0, -y)
            y = y + 20
            y = y + gridOf(content, dyes, y) + 8
        end
    end
    return y
end

local function fillList(content)
    local fams = families()
    local shared = false
    for _, fam in ipairs(fams) do
        if #fam > 1 then
            shared = true
            break
        end
    end
    local y = shared and byItem(content, fams) or byCategory(content)
    content:SetHeight(math.max(1, y))
end

local function build(cart)
    -- stayOpen for the same reason as the cart: opening the house editor
    -- would close it through UISpecialFrames otherwise
    panel = DCR.Window("DecorDyeCatalog", 320, 520, "Paint Catalog", true)

    -- Glued to the cart's right edge as a side menu: it follows the cart
    -- around, matches its height, and being a child it always draws above
    -- instead of opening behind. Not draggable or clamped on its own, the
    -- cart decides where the pair sits. Still closes by itself through the
    -- X or Escape.
    panel:SetParent(cart)
    panel:SetClampedToScreen(false)
    panel:RegisterForDrag()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", cart, "TOPRIGHT")
    panel:SetPoint("BOTTOMLEFT", cart, "BOTTOMRIGHT")

    local box, content = DCR.ScrollBox(panel)
    box:SetPoint("TOPLEFT", 18, -56)
    box:SetPoint("BOTTOMRIGHT", -18, 16)

    fillList(content)
end

function DCR.ToggleDyeCatalog(cart)
    if panel and panel:IsShown() then
        panel:Hide()
        return
    end
    if not panel then
        build(cart)
    end
    refreshHeaders()
    panel:Show()
end
