local _, DCR = ...

-- Shopping cart data. The cart is a list of catalog decor entries keyed by
-- recordID, each with a planned quantity. Merchant.lua matches vendor items
-- against it by itemID, so a lookup table is kept alongside and rebuilt on
-- every change. No UI here, the window lives in CartWindow.lua.

local byItemID = {}
local hasItems = false
local unresolved = 0 -- entries with no known itemID

-- Arrivals are noticed by diffing carted item counts on BAG_UPDATE_DELAYED
-- against a session baseline, so mail, auction wins, crafts and trades all
-- tick the list off, not just vendor buys. Vendor purchases announce
-- themselves in `expected` first (see NoteVendorPurchase), so the same item
-- is never counted twice when it lands in the bags.
local baseline = {} -- [itemID] = last seen count
local expected = {} -- [itemID] = { n, t }, vendor buys on their way to the bags
local bagWatcher = CreateFrame("Frame")

-- Bags only. Banks are no help here: the warband tab counts as zero after a
-- reload until the bank is first opened (observed 120007), so including it
-- just makes the total jump around. Withdrawals are told apart by context
-- instead: with a bank window open, an increase is the player shuffling
-- their own storage, and nothing else (mail, crafting, trades) can hand you
-- items while one is open.
local function countOf(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

local bankOpen = false
local BANKER_TYPES = {}
for _, k in ipairs({ "Banker", "AccountBanker", "GuildBanker" }) do
    local t = Enum.PlayerInteractionType[k]
    if t then
        BANKER_TYPES[t] = true
    end
end

-- The cart's AH search buttons only make sense while the auction house is
-- open, tracked off the same interaction events the bank check uses. Like a
-- vendor stocking carted items, the AH brings the cart up by itself when
-- something on the list has no vendor price, and puts it away again.
local ahOpen = false
local ahAutoOpened = false

function DCR.AuctionHouseOpen()
    return ahOpen
end

local function anyUnpriced()
    local cart = DCR.CartDB()
    if not cart then
        return false
    end
    for _, entry in pairs(cart.items) do
        local rec = entry.itemID and cart.prices[entry.itemID]
        if entry.itemID and not (rec and (rec.price or rec.costs)) then
            return true
        end
    end
    return false
end

local function items()
    local cart = DCR.CartDB()
    return cart and cart.items
end

-- The catalog's sourceText lists each vendor's cost inline: gold as
-- "100|TInterface\MoneyFrame\UI-GoldIcon.blp:0|t", currencies as
-- "8|Hcurrency:3405|h|T<icon>:0|t|h" (verified by byte dump). Parsing the
-- first cost gives a usable price before any vendor was ever visited, and
-- the currency link even carries the id for a proper name and icon. A real
-- vendor scan later overwrites these estimates.
local function parseSourceCost(sourceText)
    if not sourceText then
        return nil
    end
    -- upper() keeps positions, so finds on it line up with the original
    local gPos = sourceText:upper():find("%d[%d%.,]*|T[^|]*MONEYFRAME")
    local cPos = sourceText:find("%d[%d%.,]*|[Hh]currency:%d+")
    local start = gPos and cPos and math.min(gPos, cPos) or gPos or cPos
    if not start then
        return nil
    end
    -- one vendor's cost sits on one |n line, and an item can charge gold
    -- and currencies at once, so the whole line gets parsed
    local stop = sourceText:find("|n", start, true)
    local line = sourceText:sub(start, stop and (stop - 1) or -1)
    local rec
    local gAmt = line:upper():match("(%d[%d%.,]*)|T[^|]*MONEYFRAME")
    if gAmt then
        local n = tonumber((gAmt:gsub("[,%.]", "")))
        if n and n > 0 then
            rec = { price = n * 10000, estimated = true }
        end
    end
    for amt, id in line:gmatch("(%d[%d%.,]*)|[Hh]currency:(%d+)") do
        local n = tonumber((amt:gsub("[,%.]", "")))
        if n and n > 0 then
            rec = rec or { estimated = true }
            rec.costs = rec.costs or {}
            id = tonumber(id)
            local cur = C_CurrencyInfo.GetCurrencyInfo(id)
            table.insert(rec.costs, {
                icon = cur and cur.iconFileID,
                label = cur and cur.name,
                amount = n,
                currencyID = id,
            })
        end
    end
    return rec
end

-- Wipes and refills rather than replacing, so Merchant.lua never holds a
-- stale reference. Entries missing their itemID get one more catalog query
-- here, since catalog data can be incomplete right after login.
local function noteShade(entry, dyeColorID)
    local shades = entry.shades
    if not shades then
        shades = {}
        entry.shades = shades
    end
    for _, id in ipairs(shades) do
        if id == dyeColorID then
            return
        end
    end
    shades[#shades + 1] = dyeColorID
end

-- Dye rows used to be keyed by color, from when a color was its own item.
-- Now the item keys them, so old rows move over and the ones landing on the
-- same item merge. so migrate for version
local function migrateDyes(list)
    local old
    for recordID in pairs(list) do
        if type(recordID) == "string" and recordID:match("^dye%d+$") then
            old = old or {}
            old[#old + 1] = recordID
        end
    end
    if not old then
        return
    end
    for _, recordID in ipairs(old) do
        local entry = list[recordID]
        local info = C_DyeColor.GetDyeColorInfo(tonumber(recordID:match("%d+")))
        -- a color the client no longer knows leaves its row alone
        if info and info.itemID then
            local key = "dyeitem" .. info.itemID
            local target = list[key]
            if target then
                target.qty = (target.qty or 1) + (entry.qty or 1)
            else
                entry.recordID = key
                entry.itemID = info.itemID
                entry.name = C_Item.GetItemNameByID(info.itemID) or entry.name
                entry.icon = C_Item.GetItemIconByID(info.itemID) or entry.icon
                list[key] = entry
                target = entry
            end
            noteShade(target, info.ID)
            list[recordID] = nil
        end
    end
end

function DCR.RebuildCartLookup()
    wipe(byItemID)
    hasItems = false
    unresolved = 0
    local list = items()
    if not list then
        return
    end
    migrateDyes(list)
    local priceDB = DCR.CartDB().prices
    for recordID, entry in pairs(list) do
        hasItems = true
        -- Dyes carted by early builds saved no dye flag, so it gets
        -- re-stamped from their "dye..." keys. Blueprint rows also key as
        -- strings ("bp:" prefix), hence the pattern and not a type check.
        if not entry.dye and type(recordID) == "string" and recordID:match("^dye") then
            entry.dye = true
        end
        -- the flag rides the bp: key now, so rows flagged before that go
        -- back to being hand rows
        if entry.bp and not tostring(recordID):find("^bp:") then
            entry.bp = nil
        end
        -- item names are cold for a moment after login, so a dye row picks
        -- its real one up on a later rebuild
        if entry.dye and entry.itemID then
            entry.name = C_Item.GetItemNameByID(entry.itemID) or entry.name
        end
        -- One catalog query covers the gaps: a missing itemID, a missing
        -- price, or a price that is still just an estimate (estimates get
        -- re-parsed so parser fixes reach old records, only vendor-confirmed
        -- prices are final). Data can be cold (nil), then this retries on
        -- the next rebuild.
        local rec = entry.itemID and priceDB[entry.itemID]
        if not entry.dye and (not entry.itemID or not rec or rec.estimated) then
            local info = C_HousingCatalog.GetCatalogEntryInfo({
                -- blueprint rows carry the catalog id apart from their key
                recordID = entry.baseID or recordID,
                entryType = Enum.HousingCatalogEntryType.Decor,
                entrySubtype = Enum.HousingCatalogEntrySubtype.Unowned,
                subtypeIdentifier = 0,
            })
            if info then
                if not entry.itemID then
                    entry.itemID = info.itemID
                    entry.icon = entry.icon or info.iconTexture
                    entry.iconAtlas = entry.iconAtlas or info.iconAtlas
                end
                if entry.itemID then
                    rec = priceDB[entry.itemID]
                    if not rec or rec.estimated then
                        priceDB[entry.itemID] = parseSourceCost(info.sourceText) or rec
                    end
                end
            end
        end
        if entry.itemID then
            -- an item can have two rows, hand-picked and blueprint. The
            -- hand-picked one goes first, purchases deplete it first.
            local itemRows = byItemID[entry.itemID]
            if not itemRows then
                itemRows = {}
                byItemID[entry.itemID] = itemRows
            end
            if entry.bp then
                itemRows[#itemRows + 1] = entry
            else
                table.insert(itemRows, 1, entry)
            end
            -- prices lived on the entries for a short while, move them over
            if entry.price or entry.costs then
                priceDB[entry.itemID] = priceDB[entry.itemID] or { price = entry.price, costs = entry.costs }
                entry.price, entry.costs = nil, nil
            end
        else
            unresolved = unresolved + 1
        end
    end
    -- Baselines follow the lookup: new itemIDs start at today's count, gone
    -- ones drop out, and so do pending AH deliveries nothing tracks anymore.
    for itemID in pairs(baseline) do
        if not byItemID[itemID] then
            baseline[itemID] = nil
        end
    end
    local pending = DCR.CartDB().pending
    if pending then
        for itemID in pairs(pending) do
            if not byItemID[itemID] then
                pending[itemID] = nil
            end
        end
    end
    for itemID in pairs(byItemID) do
        if baseline[itemID] == nil then
            baseline[itemID] = countOf(itemID)
        end
    end
    if next(byItemID) then
        bagWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
    else
        bagWatcher:UnregisterEvent("BAG_UPDATE_DELAYED")
    end
end

-- The learned price of an item, if any vendor selling it was ever visited.
function DCR.PriceFor(itemID)
    local cart = DCR.CartDB()
    return cart and itemID and cart.prices[itemID] or nil
end

-- Catalog data is loaded lazily and GetCatalogEntryInfo returns nil while it
-- is cold, which leaves older cart entries without a price estimate until
-- some catalog UI happens to be opened. A one-shot background search (the
-- same searcher Blizzard's catalog uses) warms the data at login, and the
-- results callback reruns the rebuild to fill the gaps.
local searcher

function DCR.WarmCatalog()
    local cart = DCR.CartDB()
    if not cart or searcher or not C_HousingCatalog.CreateCatalogSearcher then
        return
    end
    local needs = false
    for _, entry in pairs(cart.items) do
        if not (entry.itemID and cart.prices[entry.itemID]) then
            needs = true
            break
        end
    end
    if not needs then
        return
    end
    searcher = C_HousingCatalog.CreateCatalogSearcher()
    searcher:SetResultsUpdatedCallback(function()
        searcher = nil
        DCR.RebuildCartLookup()
        if DCR.RefreshCartUI then
            DCR.RefreshCartUI()
        end
    end)
    searcher:RunSearch()
end

function DCR.CartHasItems()
    return hasItems
end

-- itemInfo is an itemID or link. Returns the item's cart rows (hand-picked
-- first, then blueprint) or nil. Matching by itemID covers the common case,
-- but catalog entries do not always name their item, so a miss falls back
-- to resolving the item to its catalog recordID, which every entry has. A
-- hit patches the rows so the next match is a plain lookup again.
function DCR.CartRowsForItem(itemInfo)
    if not (hasItems and itemInfo) then
        return nil
    end
    local itemID = (C_Item.GetItemInfoInstant(itemInfo))
    local itemRows = itemID and byItemID[itemID]
    if itemRows or unresolved == 0 then
        return itemRows
    end
    local info = C_HousingCatalog.GetCatalogEntryInfoByItem(itemInfo)
    local list = items()
    if not (info and list) then
        return nil
    end
    local recordID = info.entryID.recordID
    local manual, bp = list[recordID], list["bp:" .. recordID]
    if itemID and ((manual and not manual.itemID) or (bp and not bp.itemID)) then
        if manual and not manual.itemID then
            manual.itemID = itemID
        end
        if bp and not bp.itemID then
            bp.itemID = itemID
        end
        DCR.RebuildCartLookup()
        return byItemID[itemID]
    end
    if manual or bp then
        return { manual or bp, manual and bp or nil }
    end
    return nil
end

function DCR.CartItems()
    return items()
end

local function changed()
    DCR.RebuildCartLookup()
    if DCR.RefreshCartUI then
        DCR.RefreshCartUI()
    end
end

-- info is a HousingCatalogEntryInfo (or the synthesized fallback from
-- ResolveDecor below). Adding the same decor again just bumps the count.
function DCR.AddCartEntry(info, count)
    local list = items()
    if not (list and info and info.recordID) then
        return nil
    end
    count = count or 1
    local entry = list[info.recordID]
    if entry then
        entry.qty = entry.qty + count
    else
        entry = {
            recordID = info.recordID,
            name = info.name,
            itemID = info.itemID,
            icon = info.iconTexture,
            iconAtlas = info.iconAtlas,
            dye = info.dye,
            qty = count,
            addedAt = GetServerTime(),
        }
        list[info.recordID] = entry
    end
    -- blueprint rows key with a bp: prefix and flag themselves, so the same
    -- item can sit in the blueprint section and a hand-picked one at once
    entry.bp = info.bp and true or entry.bp
    entry.baseID = info.baseID or entry.baseID
    -- The add already holds the full catalog info, so the estimate from its
    -- sourceText is free. changed() would only redo the catalog query.
    local cart = DCR.CartDB()
    if info.itemID then
        local rec = cart.prices[info.itemID]
        if not rec or rec.estimated then
            cart.prices[info.itemID] = parseSourceCost(info.sourceText) or rec
        end
    end
    changed()
    -- Adding while standing at a vendor picks the price up right away.
    DCR.ScanMerchantPrices()
    return entry
end

-- The cart row shape for a dye's consumable item. Blueprint.lua uses it too,
-- since blueprints hand dyes over as bare itemIDs.
function DCR.DyeItemInfo(itemID, name)
    return {
        recordID = "dyeitem" .. itemID,
        name = C_Item.GetItemNameByID(itemID) or name,
        itemID = itemID,
        iconTexture = C_Item.GetItemIconByID(itemID),
        dye = true,
    }
end

-- Dyes come from the customize mode picker as DyeColorDisplayInfo, not catalog
-- entries. The item keys the row (one thing to buy), and shades ride along so
-- multiple colors from one item don't create duplicate rows.
function DCR.AddDyeEntry(info, count)
    if not (info and info.itemID) then
        return nil
    end
    local entry = DCR.AddCartEntry(DCR.DyeItemInfo(info.itemID, info.name), count)
    if entry then
        noteShade(entry, info.ID)
    end
    return entry
end

-- Bulk adds from a blueprint must be idempotent, so a second click cannot
-- double an order. Raises an existing row to the wanted count instead of
-- stacking, and returns how many pieces that actually added plus the row.
function DCR.TopUpCartEntry(info, wanted)
    local list = items()
    if not (list and info and info.recordID) then
        return 0, nil
    end
    local entry = list[info.recordID]
    if not entry then
        entry = DCR.AddCartEntry(info, wanted)
        return entry and wanted or 0, entry
    end
    if entry.qty >= wanted then
        return 0, entry
    end
    local delta = wanted - entry.qty
    entry.qty = wanted
    changed()
    return delta, entry
end

function DCR.SetCartQty(recordID, qty)
    local list = items()
    local entry = list and list[recordID]
    if entry then
        entry.qty = math.max(1, qty or 1)
        changed()
    end
end

function DCR.RemoveCartEntry(recordID)
    local list = items()
    if list and list[recordID] then
        list[recordID] = nil
        changed()
    end
end

function DCR.ClearCart()
    local list = items()
    if list then
        wipe(list)
        changed()
    end
end

function DCR.CartBuyMessagesOn()
    local cart = DCR.CartDB()
    return cart and cart.buyMessages and true or false
end

function DCR.SetCartBuyMessages(on)
    local cart = DCR.CartDB()
    if cart then
        cart.buyMessages = not not on
    end
end

-- Ticks a carted item off, whether from a vendor buy or a bag arrival. The
-- hand-picked row depletes before the blueprint one, and a row drops off
-- the list once its planned quantity is covered, which also removes the
-- vendor tooltip line.
function DCR.RecordCartPurchase(itemInfo, count)
    local list = items()
    local itemRows = DCR.CartRowsForItem(itemInfo)
    if not (list and itemRows) then
        return
    end
    local left = count or 1
    local removed = false
    for _, entry in ipairs(itemRows) do
        if left <= 0 then
            break
        end
        local take = math.min(entry.qty, left)
        entry.qty = entry.qty - take
        left = left - take
        if entry.qty <= 0 then
            list[entry.recordID] = nil
            removed = true
            if DCR.CartBuyMessagesOn() then
                DCR.Print((entry.name or "an item") .. " crossed off the shopping list.")
            end
        end
    end
    -- plain decrements skip the full rebuild, Buy all fires these three
    -- times a second
    if removed then
        changed()
    elseif DCR.RefreshCartUI then
        DCR.RefreshCartUI()
    end
end

-- Merchant.lua routes vendor buys through here. The note lets the bag diff
-- recognize the incoming item as already handled, and it expires quietly
-- when a learn-on-buy piece never shows up in the bags at all.
function DCR.NoteVendorPurchase(itemInfo, count)
    local itemRows = DCR.CartRowsForItem(itemInfo)
    local itemID = itemRows and itemRows[1] and itemRows[1].itemID
    if itemID then
        local note = expected[itemID]
        if note then
            note.n = note.n + count
            note.t = GetTime()
        else
            expected[itemID] = { n = count, t = GetTime() }
        end
    end
    DCR.RecordCartPurchase(itemInfo, count)
end

-- The bag diff. An increase nobody announced is a fresh arrival (mail, an
-- auction win, crafting, a trade) and depletes the cart. Announced increases
-- and anything during a bank visit just re-sync the baseline, as do
-- decreases from placing or redeeming.
bagWatcher:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
bagWatcher:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
-- AH commodity buys tick at purchase. The confirm call carries the item and
-- count, the events tell whether the server went through with it (the
-- COMMODITY_PURCHASED event with a payload exists on paper but the shipped
-- AH addons all key off SUCCEEDED, so that is the trusted signal). The
-- pending ledger keeps the delivery from ticking the same purchase again
-- when it lands, however much later the mail gets collected. Auctionator
-- buys drive the same API, so the hook sees those too.
local ahBuy

hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
    ahBuy = { itemID = itemID, qty = quantity or 1 }
end)

bagWatcher:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
bagWatcher:RegisterEvent("COMMODITY_PURCHASE_FAILED")
bagWatcher:SetScript("OnEvent", function(_, event, arg)
    if event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local cart = DCR.CartDB()
        if ahBuy and cart and byItemID[ahBuy.itemID] then
            cart.pending[ahBuy.itemID] = (cart.pending[ahBuy.itemID] or 0) + ahBuy.qty
            DCR.RecordCartPurchase(ahBuy.itemID, ahBuy.qty)
        end
        ahBuy = nil
        return
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        ahBuy = nil
        return
    end
    if event ~= "BAG_UPDATE_DELAYED" then
        if BANKER_TYPES[arg] then
            bankOpen = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        elseif arg == Enum.PlayerInteractionType.Auctioneer then
            ahOpen = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
            if ahOpen then
                ahAutoOpened = anyUnpriced() and DCR.AutoShowCart and DCR.AutoShowCart() or false
            elseif ahAutoOpened then
                ahAutoOpened = false
                if DCR.HideCart then
                    DCR.HideCart()
                end
            end
            if DCR.RefreshCartUI then
                DCR.RefreshCartUI() -- toggles the AH search buttons
            end
        end
        return
    end
    local cart = DCR.CartDB()
    if not cart then
        return
    end
    local now = GetTime()
    for itemID, note in pairs(expected) do
        if now - note.t > 10 then
            expected[itemID] = nil
        end
    end
    local arrived
    for itemID in pairs(byItemID) do
        local count = countOf(itemID)
        local delta = count - (baseline[itemID] or 0)
        baseline[itemID] = count
        if delta > 0 and not bankOpen then
            -- an AH delivery landing was already ticked at purchase
            local pend = cart.pending[itemID]
            if pend then
                local take = math.min(delta, pend)
                delta = delta - take
                cart.pending[itemID] = take < pend and (pend - take) or nil
            end
            local note = expected[itemID]
            if note then
                local vendor = math.min(delta, note.n)
                delta = delta - vendor
                note.n = note.n - vendor
                if note.n == 0 then
                    expected[itemID] = nil
                end
            end
            if delta > 0 then
                arrived = arrived or {}
                arrived[itemID] = delta
            end
        end
    end
    -- applied after the loop, RecordCartPurchase rebuilds byItemID
    if arrived then
        for itemID, n in pairs(arrived) do
            DCR.RecordCartPurchase(itemID, n)
        end
    end
end)

-- Bridges a placed decor (HousingDecorInstanceInfo from the house editor) to
-- its catalog entry. decorID matching the catalog recordID is undocumented,
-- so the result is only trusted when the names agree, with the decor
-- hyperlink as the fallback route.
function DCR.ResolveDecor(info)
    if not (info and info.decorID) then
        return nil
    end
    local entry = C_HousingCatalog.GetCatalogEntryInfo({
        recordID = info.decorID,
        entryType = Enum.HousingCatalogEntryType.Decor,
        entrySubtype = Enum.HousingCatalogEntrySubtype.Unowned,
        subtypeIdentifier = 0,
    })
    if entry and (not info.name or entry.name == info.name) then
        return entry
    end
    local link = C_HousingDecor.GetDecorHyperlink(info.decorID)
    local byItem = link and C_HousingCatalog.GetCatalogEntryInfoByItem(link)
    if byItem then
        return byItem
    end
    -- No catalog match at all. Keep the decor anyway, the lookup rebuild
    -- retries the itemID later.
    return {
        recordID = info.decorID,
        name = info.name or C_HousingDecor.GetDecorName(info.decorID),
        iconTexture = C_HousingDecor.GetDecorIcon(info.decorID),
    }
end
