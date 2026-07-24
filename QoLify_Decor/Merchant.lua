local _, DCR = ...

-- Vendor side for both features: a red tooltip line on decor over the
-- per-item cap, a gold "buy N" line on items from the shopping cart, and the
-- purchase hook feeding the spend total and the cart. The game gives addons
-- no way to truly block a purchase, so the cap line is a heads-up, not a
-- wall. Midnight moved merchant queries onto C_MerchantFrame.
--
-- The hooks register at file scope even in standby, but stay inert there: db
-- is never assigned, so GetCap() is 0, the cart lookup is empty and
-- RecordDecorPurchase() returns immediately.

local function merchantPrice(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    return info and info.price
end

local function isHousingDecor(link)
    if not link then
        return false
    end
    local _, itemType, itemSubType = C_Item.GetItemInfoInstant(link)
    return itemType == "Housing Decor" or itemSubType == "Housing Decor" or itemSubType == "Decor"
end

-- Map an open tooltip back to its merchant slot. GetID() reports 0 for these
-- buttons in Midnight, so read the slot from the button name instead.
local function merchantIndexForTooltip(tooltip)
    if not MerchantFrame or not MerchantFrame:IsShown() then
        return nil
    end
    if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
        return nil -- buyback tab has no buy price to cap
    end
    local owner = tooltip:GetOwner()
    local name = owner and owner.GetName and owner:GetName()
    local slot = name and tonumber(name:match("^MerchantItem(%d+)ItemButton$"))
    if not slot then
        return nil
    end
    return ((MerchantFrame.page or 1) - 1) * (MERCHANDISE_ITEMS_PER_PAGE or 10) + slot
end

-- The shopping list reminder, on any item tooltip (vendor, bags, chat
-- links). data.id carries the itemID for most item tooltips, and merchant
-- slots get resolved by button name as the fallback.
local function cartLine(tooltip, data)
    if not DCR.CartHasItems() then
        return
    end
    local itemInfo = data and data.id
    if not itemInfo then
        local index = merchantIndexForTooltip(tooltip)
        itemInfo = index and GetMerchantItemLink(index)
    end
    local entry = DCR.CartEntryForItem(itemInfo)
    if entry then
        tooltip:AddLine(("Shopping cart: buy %d"):format(entry.qty), 1, 0.82, 0)
        tooltip:Show()
    end
end

-- The over-cap warning, merchant slots only (needs a price).
local function capLine(tooltip)
    local cap = DCR.GetCap()
    if cap <= 0 then
        return
    end
    local index = merchantIndexForTooltip(tooltip)
    if not index then
        return
    end
    if not isHousingDecor(GetMerchantItemLink(index)) then
        return -- only decor counts against the cap
    end
    local price = merchantPrice(index)
    if price and price > cap then
        tooltip:AddLine(DCR.WarningLine(cap), 1, 0.2, 0.2)
        tooltip:Show()
    end
end

-- Runs after the client finishes building the tooltip, so the lines we add stick.
local function onItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip then
        return
    end
    cartLine(tooltip, data)
    capLine(tooltip)
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
end

-- Currency costs go through the old extended-cost globals, gold through
-- C_MerchantFrame, and an item can charge both at once.
local function slotCosts(index)
    local n = GetMerchantItemCostInfo(index) or 0
    if n == 0 then
        return nil
    end
    local costs = {}
    for j = 1, n do
        local icon, amount, link, name = GetMerchantItemCostItem(index, j)
        costs[#costs + 1] = {
            icon = icon,
            amount = amount,
            label = name or link,
            currencyID = link and tonumber(link:match("currency:(%d+)")),
            -- barter items (no currencyID) keep their link for the tooltip
            link = link,
        }
    end
    return costs
end

-- Prices for decor only exist at a vendor that sells it, so every decor
-- item on an open vendor goes into the price book, carted or not. Whatever
-- lands in the cart later is then often already priced. Open state comes
-- from the events, not MerchantFrame:IsShown(): at MERCHANT_SHOW the frame
-- may not be shown yet depending on handler order.
local merchantOpen = false
local slotByRecordID = {} -- carted items this merchant sells, for the Buy buttons
local autoOpened = false -- the cart popup was ours, put it away on leave
local autoChecked = false

function DCR.ScanMerchantPrices()
    local cart = DCR.CartDB()
    if not (merchantOpen and cart) then
        return
    end
    wipe(slotByRecordID)
    for i = 1, GetMerchantNumItems() or 0 do
        local link = GetMerchantItemLink(i)
        if isHousingDecor(link) then
            local itemID = C_Item.GetItemInfoInstant(link)
            if itemID then
                local rec = cart.prices[itemID]
                if not rec then
                    rec = {}
                    cart.prices[itemID] = rec
                end
                local price = merchantPrice(i)
                if price and price > 0 then
                    rec.price = price
                end
                rec.costs = slotCosts(i)
                rec.estimated = nil -- live vendor data beats the sourceText estimate
            end
            local entry = DCR.CartEntryForItem(link)
            if entry then
                slotByRecordID[entry.recordID] = i
            end
        end
    end
    -- A vendor stocking carted items brings the cart up by itself, decided
    -- once per visit so closing it again is respected through rescans.
    if not autoChecked and next(slotByRecordID) then
        autoChecked = true
        autoOpened = DCR.AutoShowCart()
    end
    if DCR.RefreshCartUI then
        DCR.RefreshCartUI()
    end
end

-- The cart's per-row Buy button asks here whether the open vendor sells it.
function DCR.MerchantSlotFor(recordID)
    return merchantOpen and slotByRecordID[recordID] or nil
end

local priceWatcher = CreateFrame("Frame")
-- Vendor visits are rare enough to leave these registered. Item links can
-- lag MERCHANT_SHOW by a moment and MERCHANT_UPDATE is not guaranteed to
-- follow, so a delayed rescan covers the gap.
priceWatcher:RegisterEvent("MERCHANT_SHOW")
priceWatcher:RegisterEvent("MERCHANT_UPDATE")
priceWatcher:RegisterEvent("MERCHANT_CLOSED")
priceWatcher:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
        merchantOpen = false
        wipe(slotByRecordID)
        if autoOpened then
            DCR.HideCart()
        end
        autoOpened, autoChecked = false, false
        if DCR.RefreshCartUI then
            DCR.RefreshCartUI() -- retires the Buy buttons
        end
        return
    end
    merchantOpen = true
    DCR.ScanMerchantPrices()
    if event == "MERCHANT_SHOW" then
        C_Timer.After(0.5, DCR.ScanMerchantPrices)
    end
end)

-- Record decor spend and tick off the shopping list when an item is bought.
-- The merchant UI buys through the global BuyMerchantItem; C_MerchantFrame
-- has no buy function to hook.
hooksecurefunc("BuyMerchantItem", function(index, quantity)
    local link = GetMerchantItemLink(index)
    if not link then
        return
    end
    DCR.RecordCartPurchase(link, quantity or 1)
    if not isHousingDecor(link) then
        return
    end
    local price = merchantPrice(index) or 0
    DCR.RecordDecorPurchase(price * (quantity or 1), link)
end)
