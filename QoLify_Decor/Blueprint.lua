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
        if not info then
            info = { recordID = entry.recordID, name = entry.name, cold = true }
        end
        info.baseID = info.recordID
    end
    info.recordID = "bp:" .. info.recordID
    info.bp = true
    return info
end

-- Prices a blueprint's buyable pieces the way carting them would: the same
-- rows, a vendor record or auction estimate per piece, one tally out. cold
-- says catalog data was missing, so the numbers are not worth keeping yet.
local function contentsTally(contentInfo, missingOnly)
    local tally = DCR.CostTally()
    local cold = false
    eachBuyable(contentInfo, missingOnly, function(ctype, entry, wanted)
        local info = infoFor(ctype, entry)
        cold = cold or info.cold
        tally:Add(info.itemID, wanted, info.sourceText)
    end)
    return tally, cold
end

-- A tally's cost parts in the cart footer's shapes: gold, then the auction
-- share marked ~, then each currency. The tooltip gives each its own line,
-- the total lines under the picker's list join them with +.
local function tallyParts(tally)
    local parts = {}
    if tally.gold > 0 then
        parts[#parts + 1] = DCR.Money(tally.gold, 16)
    end
    if tally.ah > 0 then
        parts[#parts + 1] = "~" .. DCR.Money(tally.ah, 16) .. " (AH)"
    end
    for _, t in ipairs(tally.order) do
        parts[#parts + 1] = t.icon and (t.amount .. " |T" .. t.icon .. ":16|t") or (t.amount .. " " .. (t.label or "?"))
    end
    return parts
end

local function tallyText(tally)
    local parts = tallyParts(tally)
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " + ") .. (tally.unpriced and " so far" or "")
end

-- Tooltip lines for a tally, tinted like the cart tooltip's purse lines. The
-- auction share is held against what the gold leaves over.
local function addTallyLines(tally)
    local money = GetMoney()
    if tally.gold > 0 then
        DCR.CostLine(DCR.Money(tally.gold), DCR.Money(money), money >= tally.gold)
    end
    if tally.ah > 0 then
        DCR.CostLine("~" .. DCR.Money(tally.ah) .. " at auction", DCR.Money(money), money >= tally.gold + tally.ah)
    end
    for _, c in ipairs(tally.order) do
        local held = DCR.HeldFor(c)
        DCR.CostLine(
            c.amount .. " " .. (c.label or "Unknown currency"),
            held and tostring(held),
            held and held >= c.amount
        )
    end
    if tally.unpriced then
        GameTooltip:AddLine("Some pieces have no price yet.", 0.8, 0.8, 0.8)
    end
end

-- a widget carrying a .tally gets its costs listed under the text
local function tip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body then
            GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        end
        if self.tally then
            addTallyLines(self.tally)
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- The squeeze for tight spots: one gold figure with vendor and auction
-- lumped together, always ~ since totals stay estimates until every vendor
-- was visited, and a trailing + when currencies or unpriced pieces sit
-- outside the number.
local function shortCost(tally)
    local copper = tally.gold + tally.ah
    if copper == 0 then
        return nil
    end
    local s
    if copper >= 10000 then
        s = BreakUpLargeNumbers(math.floor(copper / 10000)) .. "g"
    else
        s = DCR.Money(copper, 12)
    end
    if tally.unpriced or #tally.order > 0 then
        s = s .. " +"
    end
    return "~" .. s
end

-- Which blueprint a share code names. The contents payload carries no name
-- (checked against the 12.1 documentation), only the collection does, so
-- every collection response that passes, the picker's own or the one
-- Blizzard's blueprint UI requests, drops its names here. Carted pieces
-- wear the name so the cart can title their section with it.
local namesByCode = {}

-- The first click tops rows up to the blueprint's counts. A click that has
-- nothing left to add went through the confirm popup instead, and stacks a
-- whole set on top (furnishing two houses from one blueprint is a real
-- thing).
local function applyAdds(contentInfo, missingOnly, stack, fromBtn)
    if not DCR.CartDB() then
        return
    end
    local bpName = namesByCode[contentInfo.shareCode]
    local added, flown = 0, {}
    DCR.CartBatch(function()
        eachBuyable(contentInfo, missingOnly, function(ctype, entry, wanted)
            local n, row
            local info = infoFor(ctype, entry)
            info.bpName = bpName
            if stack then
                row = DCR.AddCartEntry(info, wanted)
                n = row and wanted or 0
            else
                n, row = DCR.TopUpCartEntry(info, wanted)
            end
            added = added + n
            if n > 0 and row then
                flown[#flown + 1] = row
            end
        end)
    end)
    if added == 1 then
        DCR.Print("1 piece added to the shopping list.")
    elseif added > 1 then
        DCR.Print(added .. " pieces added to the shopping list.")
    end
    DCR.ShowCart()
    DCR.CartFlyBurst(flown, fromBtn)
end

-- Past this many pieces the add is worth asking about first. The list itself
-- handles them fine, but a shopping list that long is rarely what someone
-- reaching for "Cart missing" had in mind.
local BIG_ADD = 5000

-- How many pieces the button would put on the list, which for a top up is
-- only the shortfall on each row.
local function addCount(contentInfo, missingOnly, stack)
    local n = 0
    eachBuyable(contentInfo, missingOnly, function(ctype, entry, wanted)
        if stack then
            n = n + wanted
        else
            local row = DCR.CartItems()[infoFor(ctype, entry).recordID]
            n = n + math.max(0, wanted - (row and row.qty or 0))
        end
    end)
    return n
end

-- Both ways into a bulk add come through here, so the size warning covers
-- the plain click and the add-again confirm alike. Returns how many pieces
-- the add came to, which is nothing when the list already holds them all.
local function confirmAdds(contentInfo, missingOnly, stack, fromBtn)
    local n = addCount(contentInfo, missingOnly, stack)
    if n == 0 then
        return 0
    end
    if n <= BIG_ADD then
        applyAdds(contentInfo, missingOnly, stack, fromBtn)
    else
        StaticPopup_Show(
            "DECOR_TOOLS_BLUEPRINT_BIG_ADD",
            ("This puts %d pieces on the shopping list, and filling it may take a moment. Go ahead?"):format(n),
            nil,
            { contentInfo = contentInfo, missingOnly = missingOnly, stack = stack, fromBtn = fromBtn }
        )
    end
    return n
end

local function cartPieces(contentInfo, missingOnly, fromBtn)
    if not (contentInfo and DCR.CartDB()) then
        return
    end
    if confirmAdds(contentInfo, missingOnly, false, fromBtn) > 0 then
        return
    end
    local text = missingOnly and "Every missing piece is already on the shopping list. Add them all again on top?"
        or "Every piece of this blueprint is already on the shopping list. Add the full set again on top?"
    StaticPopup_Show(
        "DECOR_TOOLS_BLUEPRINT_ADD_AGAIN",
        text,
        nil,
        { contentInfo = contentInfo, missingOnly = missingOnly, fromBtn = fromBtn }
    )
end

local function anyToCart(contentInfo, missingOnly)
    local any = false
    eachBuyable(contentInfo, missingOnly, function()
        any = true
    end)
    return any
end

local renderGen = 0 -- a late catalog warm only redraws the page it belongs to

-- A dye's icon comes out of the item cache, which is empty for anything the
-- player is not carrying until the client fetches it. That is where the row
-- of question marks after a loading screen comes from, so the row draws the
-- placeholder and repaints itself when the item lands. Rows get recycled as
-- the list scrolls, so a load that took its time checks the row's itemID
-- before painting over whatever is on it now.
local function setIcon(row, info)
    local tex = row.icon
    if info.iconAtlas then
        tex:SetAtlas(info.iconAtlas)
        return
    end
    if info.iconTexture then
        tex:SetTexture(info.iconTexture)
        return
    end
    tex:SetTexture(134400)
    local itemID = info.itemID
    if not itemID then
        return
    end
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if row.itemID == itemID then
            tex:SetTexture(C_Item.GetItemIconByID(itemID))
        end
    end)
end

-- Buttons on Blizzard's blueprint contents window.

local function makeCartButton(listFrame, label, missingOnly, tipTitle, tipBody)
    local btn = DCR.FlatButton(listFrame, label, 96)
    -- above the window's fullscreen input blocker, like the catalog buttons
    btn:SetFrameLevel(listFrame:GetFrameLevel() + 10)
    btn:Hide()
    -- what the button's share of the blueprint costs, riding above it
    btn.cost = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.cost:SetPoint("BOTTOM", btn, "TOP", 0, 4)
    btn.cost:SetTextColor(DIM[1], DIM[2], DIM[3])
    tip(btn, tipTitle, tipBody)
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

    -- Prices a shown button's share of the blueprint: the compact figure
    -- above it, the full line in its tooltip.
    local function priceUp(btn, contentInfo, missingOnly)
        btn.tally = nil
        btn.cost:SetText("")
        if btn:IsShown() then
            btn.tally = contentsTally(contentInfo, missingOnly)
            btn.cost:SetText(shortCost(btn.tally) or "")
        end
    end

    -- Without a target house the window turns into a read-only listing and
    -- hides its own missing marks, but the payload still carries numMissing,
    -- counted against storage alone (see requestContents), so the missing
    -- button works out there too. With a target the counts are Blizzard's,
    -- placed pieces included, matching what the window shows. Blizzard
    -- re-runs ShowBlueprintContents on storage and layout changes, so both
    -- keep themselves in sync as purchases land.
    hooksecurefunc(listFrame, "ShowBlueprintContents", function()
        local contentInfo = listFrame.blueprintContentInfo
        local ok = contentInfo and DCR.CartDB()
        allBtn:SetShown(ok and anyToCart(contentInfo, false) or false)
        missingBtn:SetShown(ok and anyToCart(contentInfo, true) or false)
        priceUp(allBtn, contentInfo, false)
        priceUp(missingBtn, contentInfo, true)
    end)
end

-- The cart's own picker: saved blueprints on one page, one blueprint's
-- pieces on the other. Lives glued to the cart like the paint catalog.

local picker -- the window, built lazily
local collectionView, detailView
local statusOverlay, statusText -- dims the blueprint list while a request runs
local collectionContent, detailContent, detailTitle
local detailFull, detailMissing -- the contents page's two total lines
local cartAllBtn, cartMissingBtn
local headerPool, bpRowPool = {}, {}
local detailList -- the contents page, whose rows are built as they scroll into view
local priceBtn -- under the blueprint list, starts and stops the costs run
local shownContent, shownTitle -- contents currently on the detail page
local pendingCode, pendingTitle -- contents request in flight, and for whom
local pendingTarget -- the house its reply has to name, see requestContents
local houses, houseIdx -- the player's own houses, fetched once placed decor gets counted
local placedCheck, houseBtn
local shownCollection -- the listing as last received, for cost repaints
local totalsCache = {} -- [shareCode] = full-set tally, kept for the session
local fetchQueue, fetching = {}, nil -- the background contents requests behind the listing costs

local LIST_W = 252 -- window 320 minus margins, inset and scrollbar
local ITEM_ROW_H = 26

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

-- opaque house GUIDs change every session, neighborhood plus plot does not
local function houseKey(house)
    return house.neighborhoodGUID .. ":" .. house.plotID
end

-- The house list only matters with placed decor counted, so that is the
-- only time it gets asked for, once a session.
local function wantHouses()
    if DCR.CartDB().bpCountPlaced and not houses then
        C_Housing.GetPlayerOwnedHouses()
    end
end

-- With the tick off a house is ruled out and the server counts against
-- storage, the same from anywhere. With it on the count takes a house. The
-- plain request picks the one you stand in, and away from home one of your
-- own gets named, which the server answers from outside too (probed on
-- 12.1.0.69814). Hands back the GUID the reply has to name when one was
-- named, since a second request does not cancel the first and a stale reply
-- can land ahead of the one that counts.
local function requestContents(code)
    local guid
    if DCR.CartDB().bpCountPlaced then
        if C_Housing.IsInsideHouse() then
            C_HousingBlueprint.RequestBlueprintContents(code)
            return
        end
        local house = houses and houses[houseIdx]
        guid = house and house.houseGUID
    end
    C_HousingBlueprint.RequestBlueprintContentsForContext(code, guid)
    return guid
end

local function requestDetail(code, title)
    -- this outranks the background costs run, whose in-flight request the
    -- shared endpoint may cancel, so that goes back in line
    if fetching then
        table.insert(fetchQueue, 1, fetching)
        fetching = nil
    end
    pendingCode, pendingTitle = code, title
    setStatus("Loading " .. title .. "...")
    pendingTarget = requestContents(code)
end

-- A room import adds a room and leaves placed decor where it stands, so the
-- server counts a room blueprint against storage with or without a house,
-- the same numMissing all three ways in the probe. The tick has nothing to
-- change there, so the whole row stays away.
local function refreshOptions()
    local room = C_HousingBlueprint.GetBlueprintTypeForCode(shownContent.shareCode) == Enum.HousingBlueprintType.Room
    local on = not room and DCR.CartDB().bpCountPlaced or false
    placedCheck:SetShown(not room)
    placedCheck.tick:SetShown(on)
    local pick = on and houses and #houses > 1 and not C_Housing.IsInsideHouse() or false
    houseBtn:SetShown(pick)
    if pick then
        houseBtn.text:SetText(houses[houseIdx].houseName)
    end
end

local function makeBpRow()
    local row = CreateFrame("Button", nil, collectionContent, "BackdropTemplate")
    row:SetHeight(22)
    row:SetBackdrop({ bgFile = DCR.WHITE })
    row:SetBackdropColor(0, 0, 0, 0)
    row.cost = DCR.Label(row, "", DIM, "GameFontNormalSmall")
    row.cost:SetPoint("RIGHT", -6, 0)
    row.text = DCR.Label(row, "", { 1, 1, 1 })
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", row.cost, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.31, 0.6)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
    end)
    row:SetScript("OnClick", function(self)
        requestDetail(self.code, self.bpName)
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
    local unpriced = 0
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
                    local t = totalsCache[bp.shareCode]
                    row.cost:SetText(t and shortCost(t) or "")
                    if not t then
                        unpriced = unpriced + 1
                    end
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
    priceBtn:SetShown(unpriced > 0)
    local running = fetching or #fetchQueue > 0
    priceBtn.text:SetText(running and ("Pricing, " .. unpriced .. " left (stop)") or "Price all blueprints")
end

-- The listing's costs need each blueprint's contents once, which only the
-- server can hand over. The run fetches them one at a time with a breather
-- in betwen, only while the picker is up, skipping whatever the session
-- already priced. The button under the list starts it and nothing else does,
-- since the requests share the endpoint a click uses and an opened blueprint
-- would sit waiting behind them.
local function fetchNext()
    if fetching or pendingCode or not picker:IsShown() then
        return
    end
    fetching = table.remove(fetchQueue, 1)
    if fetching then
        C_HousingBlueprint.RequestBlueprintContents(fetching)
    end
end

local function queueTotals()
    wipe(fetchQueue)
    for _, group in ipairs(shownCollection.groups) do
        for _, bp in ipairs(group.entries) do
            if not totalsCache[bp.shareCode] then
                fetchQueue[#fetchQueue + 1] = bp.shareCode
            end
        end
    end
    -- the totals read the catalog, so it warms up first
    DCR.WarmCatalog(fetchNext)
end

-- Turns arrived contents into a listing price, whether the background run
-- or a click into the detail page fetched them. Cold-catalog results stay
-- out of the cache so a later open can do better.
local function noteTotals(contentInfo)
    local tally, cold = contentsTally(contentInfo, false)
    if not cold then
        totalsCache[contentInfo.shareCode] = tally
    end
    if shownCollection then
        renderCollection(shownCollection)
    end
end

local function makeItemRow()
    local row = CreateFrame("Frame", nil, detailContent)
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
        local info = infoFor(row.ctype, row.entry)
        info.bpName = shownContent and namesByCode[shownContent.shareCode]
        DCR.CartFlyFX(DCR.AddCartEntry(info, n), n)
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

local function bindItemRow(row, piece)
    row.ctype, row.entry = piece.ctype, piece.entry
    row.wantAll, row.wantMissing = piece.wantAll, piece.wantMissing
    row.itemID = piece.info.itemID
    setIcon(row, piece.info)
    row.name:SetText(piece.info.name or piece.entry.name)
    row.count:SetText(piece.count)
end

local function renderDetail(contentInfo, title, redrawn)
    shownContent, shownTitle = contentInfo, title
    renderGen = renderGen + 1
    local gen = renderGen
    detailTitle:SetText(title or "Blueprint")
    detailList:Reset()
    local cold = false
    local n = 0
    -- the totals ride the same walk the rows come from, missing counted
    -- alongside the full set
    local fullTally, missTally = DCR.CostTally(), DCR.CostTally()
    eachBuyable(contentInfo, false, function(ctype, entry, wanted)
        local info = infoFor(ctype, entry)
        cold = cold or info.cold
        fullTally:Add(info.itemID, wanted, info.sourceText)
        local count = "x" .. wanted
        if entry.numMissing > 0 then
            missTally:Add(info.itemID, entry.numMissing, info.sourceText)
            count = count .. " |cffff6060" .. entry.numMissing .. " missing|r"
        end
        local piece = {
            ctype = ctype,
            entry = entry,
            info = info,
            count = count,
            -- plain click adds what is missing, ctrl the full count. With
            -- nothing missing both add the full count.
            wantAll = wanted,
            wantMissing = entry.numMissing > 0 and entry.numMissing or wanted,
        }
        detailList:Add(piece, 0, n * ITEM_ROW_H, LIST_W, ITEM_ROW_H)
        n = n + 1
    end)
    detailContent:SetHeight(math.max(1, n * ITEM_ROW_H))
    detailList:Paint()
    detailFull.text:SetText("Full set: " .. (tallyText(fullTally) or "no prices known yet"))
    detailFull.tally, detailMissing.tally = fullTally, missTally
    local showMiss = anyToCart(contentInfo, true)
    if showMiss then
        detailMissing.text:SetText("Missing: " .. (tallyText(missTally) or "no prices known yet"))
    end
    detailMissing:SetShown(showMiss)
    cartAllBtn:SetShown(anyToCart(contentInfo, false))
    cartMissingBtn:SetShown(showMiss)
    refreshOptions()
    showView(detailView)
    -- A cold catalog answers every decor query with nil, which is the whole
    -- page blank when the picker is opened straight off a loading screen. One
    -- search fills it in and the page is drawn once more, whatever comes
    -- back, so a piece the catalog simply does not carry cannot loop this.
    if cold and not redrawn then
        DCR.WarmCatalog(function()
            if gen == renderGen and shownContent == contentInfo then
                renderDetail(contentInfo, title, true)
            end
        end)
    end
end

-- One of the two total lines under the contents list. The text is a single
-- line that cuts off once currencies pile up, so hovering spells the tally
-- out the way the cart's footer does.
local function makeTotalLine(y, title)
    local line = CreateFrame("Frame", nil, detailView)
    line:SetHeight(14)
    line:SetPoint("BOTTOMLEFT", 2, y)
    line:SetPoint("BOTTOMRIGHT", -2, y)
    line:EnableMouse(true)
    line.text = DCR.Label(line, "", DIM, "GameFontNormalSmall")
    line.text:SetAllPoints()
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    tip(line, title)
    return line
end

-- The row between the totals and the cart buttons. It holds the placed decor
-- tick and, for players with more than one house, the button picking which
-- one it reads.
local function buildOptions()
    placedCheck = DCR.Checkbox(detailView)
    placedCheck:SetPoint("BOTTOMLEFT", 0, 30)
    placedCheck:SetScript("OnClick", function()
        local cart = DCR.CartDB()
        cart.bpCountPlaced = not cart.bpCountPlaced
        refreshOptions()
        wantHouses()
        requestDetail(shownContent.shareCode, shownTitle)
    end)
    tip(
        placedCheck,
        "Count placed decor",
        "Counts pieces already placed in your house as owned, so only what the house still lacks shows as missing.\n"
            .. "Leave it off to count your storage alone. It starts off."
    )
    -- the tick's own child, so it goes wherever the tick goes
    local text = DCR.Label(placedCheck, "Count placed decor", DIM, "GameFontNormalSmall")
    text:SetPoint("LEFT", placedCheck, "RIGHT", 6, 0)

    houseBtn = DCR.FlatButton(detailView, "", 140)
    houseBtn:SetHeight(18)
    houseBtn:SetPoint("BOTTOMRIGHT", 0, 30)
    houseBtn.text:SetFontObject("GameFontHighlightSmall")
    houseBtn.text:SetWidth(132)
    houseBtn.text:SetWordWrap(false)
    houseBtn:SetScript("OnClick", function()
        houseIdx = houseIdx % #houses + 1
        DCR.CartDB().bpHouse = houseKey(houses[houseIdx])
        refreshOptions()
        requestDetail(shownContent.shareCode, shownTitle)
    end)
    tip(
        houseBtn,
        "House for placed decor",
        "Away from home, placed decor counts from this house. Click to switch to another of your houses."
    )
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
    box:SetPoint("TOPLEFT")
    box:SetPoint("BOTTOMRIGHT", 0, 30)
    priceBtn = DCR.FlatButton(collectionView, "", 100)
    priceBtn:SetPoint("BOTTOMLEFT")
    priceBtn:SetPoint("BOTTOMRIGHT")
    priceBtn:SetScript("OnClick", function()
        if fetching or #fetchQueue > 0 then
            -- the one in flight still lands and gets its price
            wipe(fetchQueue)
        else
            queueTotals()
        end
        renderCollection(shownCollection)
    end)
    tip(
        priceBtn,
        "Price all blueprints",
        "Shows what each blueprint's full set costs next to its name.\n"
            .. "Takes a while with many blueprints, click again to stop.\n"
            .. "Opening a blueprint prices that one either way."
    )

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
    local detailScroll
    box, detailContent, detailScroll = DCR.ScrollBox(detailView)
    box:SetPoint("TOPLEFT", 0, -26)
    box:SetPoint("BOTTOMRIGHT", 0, 84)
    detailList = DCR.VirtualList(detailScroll, makeItemRow, bindItemRow)
    detailFull = makeTotalLine(68, "Full set")
    detailMissing = makeTotalLine(54, "Missing pieces")
    buildOptions()
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
        self:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
        shownContent = nil
        shownCollection = nil
        showView(collectionView)
        renderCollection(nil)
        setStatus("Loading blueprints...")
        C_HousingBlueprint.RequestBlueprintCollection()
        wantHouses()
    end)
    picker:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        pendingCode = nil
        fetching = nil
        wipe(fetchQueue)
    end)
    picker:Hide() -- born shown, and OnShow must fire on the first real Show()

    picker:SetScript("OnEvent", function(_, event, arg1)
        if event == "HOUSING_BLUEPRINT_COLLECTION_RECEIVED" then
            statusOverlay:Hide()
            shownCollection = arg1
            renderCollection(arg1)
        elseif event == "HOUSING_BLUEPRINT_COLLECTION_FAILURE" then
            setStatus("Could not load blueprints.")
        elseif event == "HOUSING_BLUEPRINT_CONTENTS_RECEIVED" then
            local code = arg1 and arg1.shareCode
            local stale = code and pendingTarget and arg1.targetHouseGUID ~= pendingTarget
            if pendingCode and code == pendingCode and not stale then
                pendingCode = nil
                statusOverlay:Hide()
                renderDetail(arg1, pendingTitle)
                noteTotals(arg1) -- the click's contents price the listing too
                C_Timer.After(0.3, fetchNext)
            elseif code and code == fetching then
                fetching = nil
                noteTotals(arg1)
                C_Timer.After(0.3, fetchNext)
            end
        elseif event == "HOUSING_BLUEPRINT_CONTENTS_FAILURE" then
            if pendingCode and arg1 == pendingCode then
                pendingCode = nil
                -- the status sits over the listing, and a toggle on the
                -- contents page can be what failed
                showView(collectionView)
                setStatus("Could not load that blueprint.")
                C_Timer.After(0.3, fetchNext)
            elseif arg1 and arg1 == fetching then
                -- dropped for this open, no retry loop on a flaky one
                fetching = nil
                renderCollection(shownCollection) -- the button's count
                C_Timer.After(0.3, fetchNext)
            end
        elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
            houses, houseIdx = arg1, 1
            local saved = DCR.CartDB().bpHouse
            for i, house in ipairs(houses) do
                if houseKey(house) == saved then
                    houseIdx = i
                end
            end
            -- contents asked for before the list got here went out bare
            local bare = pendingCode or (shownContent and not shownContent.targetHouseGUID and shownContent.shareCode)
            if bare and houses[1] and DCR.CartDB().bpCountPlaced and not C_Housing.IsInsideHouse() then
                requestDetail(bare, pendingCode and pendingTitle or shownTitle)
            elseif shownContent then
                refreshOptions()
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
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "HOUSING_BLUEPRINT_COLLECTION_RECEIVED" then
        for _, group in ipairs(arg1.groups) do
            for _, bp in ipairs(group.entries) do
                namesByCode[bp.shareCode] = bp.name
            end
        end
    elseif arg1 == "Blizzard_HousingBlueprint" then
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
            confirmAdds(data.contentInfo, data.missingOnly, true, data.fromBtn)
        end,
        timeout = 0,
        hideOnEscape = true,
    }
    StaticPopupDialogs["DECOR_TOOLS_BLUEPRINT_BIG_ADD"] = {
        text = "%s",
        button1 = YES,
        button2 = CANCEL,
        OnAccept = function(_, data)
            applyAdds(data.contentInfo, data.missingOnly, data.stack, data.fromBtn)
        end,
        timeout = 0,
        hideOnEscape = true,
    }
    f:RegisterEvent("HOUSING_BLUEPRINT_COLLECTION_RECEIVED")
    if C_AddOns.IsAddOnLoaded("Blizzard_HousingBlueprint") then
        attach()
    else
        f:RegisterEvent("ADDON_LOADED")
    end
end
