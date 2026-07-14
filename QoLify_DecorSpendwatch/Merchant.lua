local _, DSW = ...

-- Vendor side: a red tooltip line on decor over the per-item cap, and recording
-- what you spend on decor. The game gives addons no way to truly block a purchase,
-- so the tooltip line is a heads-up, not a wall. Midnight moved merchant queries
-- onto C_MerchantFrame.
--
-- Verbatim copy of the standalone DecorSpendwatch Merchant.lua. The hooks
-- register at file scope even in standby, but stay inert there: db is never
-- assigned, so GetCap() is 0 and RecordDecorPurchase() returns immediately.

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

-- Runs after the client finishes building the tooltip, so the line we add sticks.
local function onItemTooltip(tooltip)
    if tooltip ~= GameTooltip then
        return
    end
    local cap = DSW.GetCap()
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
        tooltip:AddLine(DSW.WarningLine(cap), 1, 0.2, 0.2)
        tooltip:Show()
    end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
end

-- Record decor spend when an item is bought. The merchant UI buys through the
-- global BuyMerchantItem; C_MerchantFrame has no buy function to hook.
hooksecurefunc("BuyMerchantItem", function(index, quantity)
    local link = GetMerchantItemLink(index)
    if not isHousingDecor(link) then
        return
    end
    local price = merchantPrice(index) or 0
    DSW.RecordDecorPurchase(price * (quantity or 1), link)
end)
