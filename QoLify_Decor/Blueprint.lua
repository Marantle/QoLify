local _, DCR = ...

-- Blueprint support for the cart (12.1): two buttons on Blizzard's blueprint
-- contents window, and the cart's own picker for browsing saved blueprints
-- and carting their pieces. In the contents payload decor rows carry their
-- catalog recordID and dye rows carry the consumabe's itemID (checked
-- against Blizzard's own entry code), so both map straight onto cart rows.
-- The Blizzard addon only exists on 12.1 clients, so on live the hook waits
-- for an ADDON_LOADED that never fires and the cart hides its blueprint
-- link.

local GOLD = DCR.COLOR_GOLD
local DIM = DCR.COLOR_DIM

-- Rooms and fixtures also show up in a blueprint, but those are unlocks, not
-- purchases, so only decor and dyes belong on a shopping list. invalid marks
-- content unusable no matter what (wrong faction exteriors and the like).
local function eachBuyable(contentInfo, missingOnly, fn)
    for _, group in ipairs(contentInfo.contentGroups) do
        local ctype = group.contentType
        if ctype == Enum.HousingBlueprintContentType.Decor or ctype == Enum.HousingBlueprintContentType.Dye then
            for _, entry in ipairs(group.entries) do
                local wanted = missingOnly and entry.numMissing or entry.total
                if wanted > 0 and not entry.invalid then
                    fn(ctype, entry, wanted)
                end
            end
        end
    end
end

-- What AddCartEntry wants to see for one blueprint row. The bp: key prefix
-- keeps these rows apart from hand-picked ones of the same item, baseID
-- keeps the real catalog id around for the cart's own catalog queries.
local function infoFor(ctype, entry)
    local info
    if ctype == Enum.HousingBlueprintContentType.Dye then
        info = DCR.DyeItemInfo(entry.recordID, entry.name)
    else
        info = C_HousingCatalog.GetCatalogEntryInfo({
            recordID = entry.recordID,
            entryType = Enum.HousingCatalogEntryType.Decor,
            entrySubtype = Enum.HousingCatalogEntrySubtype.Unowned,
            subtypeIdentifier = 0,
        })
        -- catalog data can be cold, the cart's rebuild retries the itemID
        -- and price later
        info = info or { recordID = entry.recordID, name = entry.name }
        info.baseID = info.recordID
    end
    info.recordID = "bp:" .. info.recordID
    info.bp = true
    return info
end

-- The first click tops rows up to the blueprint's counts. A click that has
-- nothing left to add went through the confirm popup instead, and stacks a
-- whole set on top (furnishing two houses from one blueprint is a real
-- thing).
local function applyAdds(contentInfo, missingOnly, stack, fromBtn)
    if not DCR.CartDB() then
        return
    end
    local added, flown = 0, {}
    eachBuyable(contentInfo, missingOnly, function(ctype, entry, wanted)
        local n, row
        if stack then
            row = DCR.AddCartEntry(infoFor(ctype, entry), wanted)
            n = row and wanted or 0
        else
            n, row = DCR.TopUpCartEntry(infoFor(ctype, entry), wanted)
        end
        added = added + n
        if n > 0 and row then
            flown[#flown + 1] = row
        end
    end)
    if added == 1 then
        DCR.Print("1 piece added to the shopping list.")
    elseif added > 1 then
        DCR.Print(added .. " pieces added to the shopping list.")
    end
    DCR.ShowCart()
    DCR.CartFlyBurst(flown, fromBtn)
end

local function cartPieces(contentInfo, missingOnly, fromBtn)
    if not (contentInfo and DCR.CartDB()) then
        return
    end
    local wouldAdd = false
    eachBuyable(contentInfo, missingOnly, function(ctype, entry, wanted)
        local row = DCR.CartItems()[infoFor(ctype, entry).recordID]
        if not (row and row.qty >= wanted) then
            wouldAdd = true
        end
    end)
    if wouldAdd then
        applyAdds(contentInfo, missingOnly, false, fromBtn)
    else
        local text = missingOnly and "Every missing piece is already on the shopping list. Add them all again on top?"
            or "Every piece of this blueprint is already on the shopping list. Add the full set again on top?"
        StaticPopup_Show(
            "DECOR_TOOLS_BLUEPRINT_ADD_AGAIN",
            text,
            nil,
            { contentInfo = contentInfo, missingOnly = missingOnly, fromBtn = fromBtn }
        )
    end
end

local function anyToCart(contentInfo, missingOnly)
    local any = false
    eachBuyable(contentInfo, missingOnly, function()
        any = true
    end)
    return any
end

local function setIcon(tex, info)
    if info.iconAtlas then
        tex:SetAtlas(info.iconAtlas)
    else
        tex:SetTexture(info.iconTexture or 134400)
    end
end

-- Buttons on Blizzard's blueprint contents window.

local function makeCartButton(listFrame, label, missingOnly, tipTitle, tipBody)
    local btn = DCR.FlatButton(listFrame, label, 96)
    -- above the window's fullscreen input blocker, like the catalog buttons
    btn:SetFrameLevel(listFrame:GetFrameLevel() + 10)
    btn:Hide()
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tipTitle)
        GameTooltip:AddLine(tipBody, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        cartPieces(listFrame.blueprintContentInfo, missingOnly, self)
    end)
    return btn
end

local function attach()
    local listFrame = HousingBlueprintContentListFrame
    if not listFrame or listFrame.cartButtons then
        return
    end
    -- Blizzard's close button sits centered along the bottom, these flank it
    local missingBtn = makeCartButton(
        listFrame,
        "Cart missing",
        true,
        "Add missing pieces to cart",
        "Everything the blueprint needs that you do not own, decor and dyes."
    )
    missingBtn:SetPoint("BOTTOMLEFT", 16, 12)
    local allBtn = makeCartButton(
        listFrame,
        "Cart all",
        false,
        "Add every piece to cart",
        "All decor and dyes the blueprint uses, owned or not."
    )
    allBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    listFrame.cartButtons = { missingBtn, allBtn }

    -- Without a target house the window is a plain read-only listing and
    -- numMissing means nothing, so the missing button only shows when
    -- something is actually missing. Blizzard re-runs ShowBlueprintContents
    -- on storage and layout changes, so both keep themselves in sync as
    -- purchases land.
    hooksecurefunc(listFrame, "ShowBlueprintContents", function()
        local contentInfo = listFrame.blueprintContentInfo
        local ok = contentInfo and DCR.CartDB()
        allBtn:SetShown(ok and anyToCart(contentInfo, false) or false)
        missingBtn:SetShown(ok and listFrame:HasTargetHouse() and anyToCart(contentInfo, true) or false)
    end)
end

-- The cart's own picker: saved blueprints on one page, one blueprint's
-- pieces on the other. Lives glued to the cart like the paint catalog.

local picker -- the window, built lazily
local collectionView, detailView
local statusOverlay, statusText -- dims the blueprint list while a request runs
local collectionContent, detailContent, detailTitle
local cartAllBtn, cartMissingBtn
local headerPool, bpRowPool, itemRowPool = {}, {}, {}
local shownContent -- contents currently on the detail page
local pendingCode, pendingTitle -- contents request in flight, and for whom

local LIST_W = 252 -- window 320 minus margins, inset and scrollbar

local function poolGet(pool, make)
    for _, w in ipairs(pool) do
        if not w.used then
            w.used = true
            return w
        end
    end
    local w = make()
    w.used = true
    pool[#pool + 1] = w
    return w
end

local function poolReset(pool)
    for _, w in ipairs(pool) do
        w.used = false
        w:Hide()
    end
end

local function makeHeader()
    return DCR.Label(collectionContent, "", GOLD)
end

local function setStatus(text)
    statusText:SetText(text)
    statusOverlay:Show()
end

local function makeBpRow()
    local row = CreateFrame("Button", nil, collectionContent, "BackdropTemplate")
    row:SetHeight(22)
    row:SetBackdrop({ bgFile = DCR.WHITE })
    row:SetBackdropColor(0, 0, 0, 0)
    row.text = DCR.Label(row, "", { 1, 1, 1 })
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.31, 0.6)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
    end)
    row:SetScript("OnClick", function(self)
        pendingCode, pendingTitle = self.code, self.bpName
        setStatus("Loading " .. self.bpName .. "...")
        C_HousingBlueprint.RequestBlueprintContents(self.code)
    end)
    return row
end

local function showView(view)
    collectionView:SetShown(view == collectionView)
    detailView:SetShown(view == detailView)
end

local function renderCollection(collection)
    poolReset(headerPool)
    poolReset(bpRowPool)
    local y = 0
    if collection then
        for _, group in ipairs(collection.groups) do
            if #group.entries > 0 then
                local header = poolGet(headerPool, makeHeader)
                header:SetText(group.name)
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", 0, -y)
                header:Show()
                y = y + 20
                for _, bp in ipairs(group.entries) do
                    local row = poolGet(bpRowPool, makeBpRow)
                    row.text:SetText(bp.isAutoSave and (bp.name .. " |cff8888aa(autosave)|r") or bp.name)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    row:SetWidth(LIST_W)
                    row:Show()
                    row.code, row.bpName = bp.shareCode, bp.name
                    y = y + 22
                end
                y = y + 6
            end
        end
    end
    if y == 0 then
        setStatus("No blueprints saved yet.")
    end
    collectionContent:SetHeight(math.max(1, y))
end

local function makeItemRow()
    local row = CreateFrame("Frame", nil, detailContent)
    row:SetHeight(26)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.add = DCR.FlatButton(row, "+", 18)
    row.add:SetHeight(18)
    row.add:SetPoint("RIGHT", -2, 0)
    row.add:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add to cart")
        if row.wantMissing ~= row.wantAll then
            GameTooltip:AddLine(
                "Adds the missing x" .. row.wantMissing .. ". Ctrl: the blueprint's full x" .. row.wantAll .. ".",
                0.8,
                0.8,
                0.8
            )
        else
            GameTooltip:AddLine("Adds the blueprint's count of this piece (x" .. row.wantAll .. ").", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    row.add:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.add:SetScript("OnClick", function()
        local n = IsControlKeyDown() and row.wantAll or row.wantMissing
        DCR.CartFlyFX(DCR.AddCartEntry(infoFor(row.ctype, row.entry), n), n)
    end)
    -- Same icon hover as the cart rows: the item tooltip, or just the name
    -- while the catalog has not named the item yet.
    local iconHover = CreateFrame("Button", nil, row)
    iconHover:SetAllPoints(row.icon)
    iconHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local itemID = row.ctype == Enum.HousingBlueprintContentType.Dye and row.entry.recordID or row.itemID
        if itemID then
            GameTooltip:SetItemByID(itemID)
        else
            GameTooltip:SetText(row.entry.name)
        end
        GameTooltip:Show()
    end)
    iconHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.count = DCR.Label(row, "", DIM, "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", row.add, "LEFT", -8, 0)
    row.name = DCR.Label(row, "", { 1, 1, 1 })
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    -- the count's width varies with the missing note, the name ends where
    -- it starts
    row.name:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

local function renderDetail(contentInfo, title)
    shownContent = contentInfo
    detailTitle:SetText(title or "Blueprint")
    poolReset(itemRowPool)
    local y = 0
    local hasHouse = contentInfo.targetHouseGUID ~= nil
    eachBuyable(contentInfo, false, function(ctype, entry, wanted)
        local row = poolGet(itemRowPool, makeItemRow)
        row.ctype, row.entry = ctype, entry
        -- plain click adds what is missing, ctrl the full count. With
        -- nothing missing (or no house to compare) both add the full count.
        row.wantAll = wanted
        row.wantMissing = (hasHouse and entry.numMissing > 0) and entry.numMissing or wanted
        local info = infoFor(ctype, entry)
        row.itemID = info.itemID
        setIcon(row.icon, info)
        row.name:SetText(info.name or entry.name)
        local count = "x" .. wanted
        if hasHouse and entry.numMissing > 0 then
            count = count .. " |cffff6060" .. entry.numMissing .. " missing|r"
        end
        row.count:SetText(count)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(LIST_W)
        row:Show()
        y = y + 26
    end)
    detailContent:SetHeight(math.max(1, y))
    cartAllBtn:SetShown(anyToCart(contentInfo, false))
    cartMissingBtn:SetShown(hasHouse and anyToCart(contentInfo, true))
    showView(detailView)
end

local function build(cart)
    -- glued to the cart's right edge like the paint catalog, and for the
    -- same reasons (see DyeCatalog.lua)
    picker = DCR.Window("DecorBlueprintPicker", 320, 520, "Blueprints", true)
    picker:SetParent(cart)
    picker:SetClampedToScreen(false)
    picker:RegisterForDrag()
    picker.resetBtn:Hide()
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", cart, "TOPRIGHT")
    picker:SetPoint("BOTTOMLEFT", cart, "BOTTOMRIGHT")

    collectionView = CreateFrame("Frame", nil, picker)
    collectionView:SetPoint("TOPLEFT", 18, -56)
    collectionView:SetPoint("BOTTOMRIGHT", -18, 16)
    local box
    box, collectionContent = DCR.ScrollBox(collectionView)
    box:SetAllPoints(collectionView)

    -- Sits over the whole list while a request runs (or it failed), both as
    -- feedback and to keep the rows from taking more clicks. A click on it
    -- dismisses, so an error never traps the list.
    statusOverlay = CreateFrame("Frame", nil, collectionView, "BackdropTemplate")
    statusOverlay:SetAllPoints(collectionView)
    statusOverlay:SetBackdrop({ bgFile = DCR.WHITE })
    statusOverlay:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
    statusOverlay:SetFrameLevel(collectionView:GetFrameLevel() + 20)
    statusOverlay:EnableMouse(true)
    statusOverlay:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)
    statusOverlay:Hide()
    statusText = DCR.Label(statusOverlay, "", DIM)
    statusText:SetPoint("CENTER")
    statusText:SetWidth(LIST_W - 20)
    statusText:SetJustifyH("CENTER")
    statusText:SetWordWrap(true)

    detailView = CreateFrame("Frame", nil, picker)
    detailView:SetPoint("TOPLEFT", 18, -56)
    detailView:SetPoint("BOTTOMRIGHT", -18, 16)
    detailView:Hide()
    local back = DCR.FlatButton(detailView, "< Back", 60)
    back:SetHeight(20)
    back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function()
        shownContent = nil
        showView(collectionView)
    end)
    detailTitle = DCR.Label(detailView, "", GOLD)
    detailTitle:SetPoint("LEFT", back, "RIGHT", 8, 0)
    detailTitle:SetPoint("RIGHT", 0, 0)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetWordWrap(false)
    box, detailContent = DCR.ScrollBox(detailView)
    box:SetPoint("TOPLEFT", 0, -26)
    box:SetPoint("BOTTOMRIGHT", 0, 34)
    cartMissingBtn = DCR.FlatButton(detailView, "Cart missing", 96)
    cartMissingBtn:SetPoint("BOTTOMLEFT", 0, 0)
    cartMissingBtn:SetScript("OnClick", function(self)
        cartPieces(shownContent, true, self)
    end)
    cartAllBtn = DCR.FlatButton(detailView, "Cart all", 96)
    cartAllBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    cartAllBtn:SetScript("OnClick", function(self)
        cartPieces(shownContent, false, self)
    end)

    -- Only listening while open. Both requests are async, and ours can
    -- cancel a request Blizzard's own blueprint UI has in flight. That is
    -- the price of sharing the endpoint, and the two are rarely open at
    -- the same time.
    picker:SetScript("OnShow", function(self)
        self:RegisterEvent("HOUSING_BLUEPRINT_COLLECTION_RECEIVED")
        self:RegisterEvent("HOUSING_BLUEPRINT_COLLECTION_FAILURE")
        self:RegisterEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED")
        self:RegisterEvent("HOUSING_BLUEPRINT_CONTENTS_FAILURE")
        shownContent = nil
        showView(collectionView)
        renderCollection(nil)
        setStatus("Loading blueprints...")
        C_HousingBlueprint.RequestBlueprintCollection()
    end)
    picker:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        pendingCode = nil
    end)
    picker:Hide() -- born shown, and OnShow must fire on the first real Show()

    picker:SetScript("OnEvent", function(_, event, arg1)
        if event == "HOUSING_BLUEPRINT_COLLECTION_RECEIVED" then
            statusOverlay:Hide()
            renderCollection(arg1)
        elseif event == "HOUSING_BLUEPRINT_COLLECTION_FAILURE" then
            setStatus("Could not load blueprints.")
        elseif event == "HOUSING_BLUEPRINT_CONTENTS_RECEIVED" then
            if pendingCode and arg1 and arg1.shareCode == pendingCode then
                pendingCode = nil
                statusOverlay:Hide()
                renderDetail(arg1, pendingTitle)
            end
        elseif event == "HOUSING_BLUEPRINT_CONTENTS_FAILURE" then
            if pendingCode and arg1 == pendingCode then
                pendingCode = nil
                setStatus("Could not load that blueprint.")
            end
        end
    end)
end

function DCR.HideBlueprintPicker()
    if picker then
        picker:Hide()
    end
end

function DCR.ToggleBlueprintPicker(cart)
    if picker and picker:IsShown() then
        picker:Hide()
        return
    end
    if DCR.HideDyeCatalog then
        DCR.HideDyeCatalog() -- the two share the cart's right edge
    end
    if not picker then
        build(cart)
    end
    picker:Show()
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_HousingBlueprint" then
        attach()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Called from InitCore, so a standing-by module never installs anything. The
-- Blizzard addon can already be loaded when the module is enabled
-- mid-session.
function DCR.BlueprintInit()
    StaticPopupDialogs["DECOR_TOOLS_BLUEPRINT_ADD_AGAIN"] = {
        text = "%s",
        button1 = YES,
        button2 = CANCEL,
        OnAccept = function(_, data)
            applyAdds(data.contentInfo, data.missingOnly, true, data.fromBtn)
        end,
        timeout = 0,
        hideOnEscape = true,
    }
    if C_AddOns.IsAddOnLoaded("Blizzard_HousingBlueprint") then
        attach()
    else
        f:RegisterEvent("ADDON_LOADED")
    end
end
