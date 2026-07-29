local _, DCR = ...

-- The game's dye picker only exists while customizing a piece at your
-- house, so the cart carries its own paint catalog: every purchasable dye,
-- in the picker's categories, one click to cart from anywhere. Everything
-- builds lazily on first open, the dye list is static data.

local GOLD = DCR.COLOR_GOLD

local SWATCH = 24
local GAP = 6
-- window width 320, minus the 18 side margins, the 6 scroll inset and the
-- 26 the scrollbar takes
local LIST_W = 252

local panel

local function swatchEnter(self)
    self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    local info = C_DyeColor.GetDyeColorInfo(self.dyeColorID)
    if not info then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(info.name)
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

local function makeSwatch(parent, info)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SWATCH, SWATCH)
    b:SetBackdrop({ bgFile = DCR.WHITE, edgeFile = DCR.WHITE, edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 0)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    b.dyeColorID = info.ID
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

local function fillList(content)
    local cols = math.floor((LIST_W + GAP) / (SWATCH + GAP))
    local cats = C_DyeColor.GetAllDyeColorCategories()
    table.sort(cats)
    local y = 0
    for _, catID in ipairs(cats) do
        local dyes = {}
        for _, id in ipairs(C_DyeColor.GetDyeColorsInCategory(catID)) do
            local info = C_DyeColor.GetDyeColorInfo(id)
            -- no item means nothing to buy, the picker-only entries stay out
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
            for i, info in ipairs(dyes) do
                local swatch = makeSwatch(content, info)
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                swatch:SetPoint("TOPLEFT", col * (SWATCH + GAP), -(y + row * (SWATCH + GAP)))
            end
            y = y + math.ceil(#dyes / cols) * (SWATCH + GAP) + 8
        end
    end
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
    panel:Show()
end
