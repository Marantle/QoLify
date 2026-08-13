local _, DCR = ...

-- The shopping cart window (/cart). A drop box up top that takes the decor
-- piece currently selected in the house editor (or a decor item dragged from
-- the bags), and the planned list below it. Built on first open.

local GOLD = DCR.COLOR_GOLD
local DIM = DCR.COLOR_DIM
local label, flatButton = DCR.Label, DCR.FlatButton

-- What the purse covers and what it does not, in the footer sum and in its
-- tooltip (which needs the same two as plain colors).
local OK_HEX, SHORT_HEX = "|cff59d96a", "|cffff5959"
local OK_RGB, SHORT_RGB = { 0.35, 0.85, 0.42 }, { 1, 0.35, 0.35 }

local ROW_H = 66
local DYE_ROW_H = 46 -- dye rows carry a small icon and pack tighter
local ARM_SECS = 4 -- how long the Buy all confirm click stays armed
local COL_W = 332 -- the list width at the default 400 window, one column's cap
local COL_GAP = 12

local panel, dropZone, dropIcon, dropText, listContent, countText
local updateParent -- built with the window, re-homes it as the editor comes and goes
local fxLayer -- the flying icons draw here, above the windows they cross
local catalogLink, dyeLink, bpLink -- gold links under the drop text, alternatives to dropping
local bounce -- drop zone thump, played when an added icon lands in it
local rowList -- the item rows, built and reused by the list as it scrolls
local createRow
local pending -- catalog entry for the decor currently selected in the editor
local buyTicker, buyBtn, buyQueue -- the running section buy, whose button started it, and its rows
local lastKnownCost, lastCurrencyTotals, lastCount = 0, {}, 0 -- what the footer sums, for its tints and tooltip
local lastUnpriced -- whether part of the cart is still waiting for a price
local lastLayoutW -- list width at the last refresh, reflow only on real change

-- The list splits into these sections, each under its own collapsible header
-- that also carries the section's Buy all and AH search. Blueprint rows stay
-- together whether they are decor or dye, so the other two exclude bp.
local SECTIONS = {
    {
        key = "decor",
        title = "Decor",
        phrase = "the decor section",
        match = function(e)
            return not e.dye and not e.bp
        end,
    },
    {
        key = "dyes",
        title = "Dyes",
        phrase = "the dye section",
        match = function(e)
            return e.dye and not e.bp
        end,
    },
    {
        key = "bp",
        title = "From blueprints",
        phrase = "the blueprint section",
        match = function(e)
            return e.bp
        end,
    },
}

local setIcon = DCR.SetIcon

-- One item's cost as text: gold, currencies, or both joined with +.
local function costText(entry)
    local rec = DCR.PriceFor(entry.itemID)
    if not rec then
        return ""
    end
    local parts
    if rec.price then
        parts = { DCR.Money(rec.price, 16) }
    end
    if rec.costs then
        parts = parts or {}
        for _, c in ipairs(rec.costs) do
            if c.icon then
                table.insert(parts, c.amount .. " |T" .. c.icon .. ":16|t")
            else
                table.insert(parts, c.amount .. " " .. (c.label or "?"))
            end
        end
    end
    if not parts then
        return ""
    end
    -- the ~ marks catalog estimates: reputation discounts and the like only
    -- show in the real price, learned once a vendor is actually visited
    return (rec.estimated and "~" or "") .. table.concat(parts, " + ")
end

-- Whether a vendor ever put a number on the item, estimate or confirmed.
local function priced(rec)
    return rec ~= nil and (rec.price or rec.costs) ~= nil
end

-- Nothing sells it that we know of, so the auction house is what the row can
-- offer, and only while it is open.
local function needsAH(entry)
    return DCR.AuctionHouseOpen() and entry.itemID ~= nil and not priced(DCR.PriceFor(entry.itemID))
end

-- Costs key on their currency, and the barter kind on the item they charge,
-- so two rows paying with the same thing land on one tally.
local function costKey(c)
    return c.currencyID or c.link or c.label or "?"
end

-- How much of a cost's currency the player carries. Barter costs charge an
-- item instead, so those count the bags. A cost naming neither is unknown,
-- and unknown never holds a buy back.
local function heldFor(c)
    if c.currencyID then
        local cur = C_CurrencyInfo.GetCurrencyInfo(c.currencyID)
        return cur and cur.quantity
    end
    local itemID = c.link and (C_Item.GetItemInfoInstant(c.link))
    return itemID and C_Item.GetItemCount(itemID) or nil
end

local function tint(ok, text)
    return (ok and OK_HEX or SHORT_HEX) .. text .. "|r"
end

-- Auto-buy: one carted item at a time while the vendor stays open, scoped to
-- the section whose header button started it.
local function stopBuying(msg)
    if buyTicker then
        buyTicker:Cancel()
        buyTicker = nil
    end
    buyQueue = nil
    if buyBtn then
        buyBtn.armed = nil
        buyBtn.text:SetText("Buy all")
        buyBtn = nil
    end
    if msg then
        DCR.Print(msg)
    end
end
DCR.StopBuyAll = stopBuying -- Merchant.lua pulls the brake on failed buys

local function affordable(rec)
    if not rec then
        return true -- price never seen, let the buy speak for itself
    end
    if rec.price and GetMoney() < rec.price then
        return false
    end
    if rec.costs then
        for _, c in ipairs(rec.costs) do
            local held = heldFor(c)
            if held and held < c.amount then
                return false
            end
        end
    end
    return true
end

-- Rows sort by when they were added, both in the list and in a buy run.
local function byAge(a, b)
    if a.addedAt ~= b.addedAt then
        return (a.addedAt or 0) < (b.addedAt or 0)
    end
    -- dye keys are strings, decor keys numbers, so compare as text
    return tostring(a.recordID) < tostring(b.recordID)
end

-- The rows a Buy all works through: the section's carted items this vendor
-- actually stocks, in the order the window lists them.
local function buyableRows(s)
    local stocked = {}
    local list = DCR.CartItems()
    if list then
        for recordID, entry in pairs(list) do
            if entry.qty > 0 and s.match(entry) and DCR.MerchantSlotFor(recordID) then
                stocked[#stocked + 1] = entry
            end
        end
    end
    table.sort(stocked, byAge)
    return stocked
end

-- A dry run of that walk, for the warning the Buy all button raises: how
-- many of the planned buys the purse covers here, and what buying the lot
-- would need on top of what the player carries. Funds only ever drop during
-- a run, so a row that cannot be paid for now stays skipped, which is where
-- the ticker ends up too.
local function buyPlan(s)
    local plan = { total = 0, afford = 0, gold = 0, shortGold = 0, short = {} }
    local purse = GetMoney()
    local left = {} -- what is left of each currency as the run spends it, false when unknown
    local need, order = {}, {}
    for _, entry in ipairs(buyableRows(s)) do
        local rec = DCR.PriceFor(entry.itemID)
        local price = rec and rec.price or 0
        local costs = rec and rec.costs
        plan.total = plan.total + entry.qty
        plan.gold = plan.gold + price * entry.qty
        if costs then
            for _, c in ipairs(costs) do
                local key = costKey(c)
                local t = need[key]
                if not t then
                    t = { amount = 0, label = c.label, icon = c.icon, held = heldFor(c) or false }
                    need[key] = t
                    order[#order + 1] = t
                    left[key] = t.held
                end
                t.amount = t.amount + c.amount * entry.qty
            end
        end
        local bought = 0
        while bought < entry.qty and purse >= price do
            local pays = true
            if costs then
                for _, c in ipairs(costs) do
                    local have = left[costKey(c)]
                    if have and have < c.amount then
                        pays = false
                    end
                end
            end
            if not pays then
                break
            end
            purse = purse - price
            if costs then
                for _, c in ipairs(costs) do
                    local key = costKey(c)
                    if left[key] then
                        left[key] = left[key] - c.amount
                    end
                end
            end
            bought = bought + 1
        end
        plan.afford = plan.afford + bought
    end
    plan.shortGold = math.max(0, plan.gold - GetMoney())
    plan.needs = order
    for _, t in ipairs(order) do
        if t.held and t.amount > t.held then
            plan.short[#plan.short + 1] = { amount = t.amount - t.held, label = t.label }
        end
    end
    return plan
end

-- One "this is the bill, this is your purse" tooltip line, tinted by whether
-- it is covered. Held goes in nil when teh amount could not be read at all,
-- and the line stays plain then.
local function costLine(need, held, ok)
    if not held then
        GameTooltip:AddLine(need, 1, 1, 1)
        return
    end
    local c = ok and OK_RGB or SHORT_RGB
    GameTooltip:AddDoubleLine(need, "you have " .. held, 1, 1, 1, c[1], c[2], c[3])
end

local function buyTick()
    local list = DCR.CartItems()
    local blocked = false
    if list and buyQueue then
        for _, entry in ipairs(buyQueue) do
            -- a row the player pulls off the list mid-run drops out here
            if entry.qty > 0 and list[entry.recordID] == entry then
                local slot = DCR.MerchantSlotFor(entry.recordID)
                if slot then
                    if affordable(DCR.PriceFor(entry.itemID)) then
                        BuyMerchantItem(slot, 1)
                        return
                    end
                    blocked = true
                end
            end
        end
    end
    stopBuying(blocked and "stopped, the rest is not affordable right now." or "shopping list done at this vendor.")
end

local function startBuying(s, btn)
    btn.armed = nil
    btn.text:SetText("Stop")
    buyBtn = btn
    buyQueue = buyableRows(s)
    buyTicker = C_Timer.NewTicker(1 / 3, buyTick)
    buyTick()
end

-- Little flourish: the added decor's icon tumbles into the cart from a random
-- direction. A handful of pooled textures, running only while an add plays.
local fxPool = {}

local function takeFx()
    for _, fx in ipairs(fxPool) do
        if not fx.busy then
            return fx
        end
    end
    if #fxPool >= 10 then
        return nil -- adds faster than the animation? skip the flourish
    end
    local tex = fxLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:Hide()
    local group = tex:CreateAnimationGroup()
    local move = group:CreateAnimation("Translation")
    move:SetDuration(0.45)
    move:SetSmoothing("IN")
    local spin = group:CreateAnimation("Rotation")
    spin:SetDuration(0.45)
    spin:SetOrigin("CENTER", 0, 0)
    -- an up-then-down pair on top of the straight move bends it into an arc,
    -- used by the fly-from-cursor variant (the plain drop leaves them at 0)
    local liftUp = group:CreateAnimation("Translation")
    liftUp:SetDuration(0.225)
    liftUp:SetSmoothing("OUT")
    local liftDown = group:CreateAnimation("Translation")
    liftDown:SetStartDelay(0.225)
    liftDown:SetDuration(0.225)
    liftDown:SetSmoothing("IN")
    local shrink = group:CreateAnimation("Scale")
    shrink:SetDuration(0.45)
    shrink:SetOrigin("CENTER", 0, 0)
    shrink:SetScaleFrom(1, 1)
    shrink:SetScaleTo(0.4, 0.4)
    local fade = group:CreateAnimation("Alpha")
    fade:SetStartDelay(0.3)
    fade:SetDuration(0.15)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    local fx = { tex = tex, group = group, move = move, spin = spin, liftUp = liftUp, liftDown = liftDown }
    group:SetScript("OnFinished", function()
        tex:Hide()
        fx.busy = false
        bounce:Restart()
    end)
    table.insert(fxPool, fx)
    return fx
end

local function playFx(entry)
    local fx = takeFx()
    if not fx then
        return
    end
    fx.busy = true
    setIcon(fx.tex, entry)
    local s = entry.dye and 28 or 56
    fx.tex:SetSize(s, s)
    local dx = math.random(-70, 70)
    fx.tex:ClearAllPoints()
    fx.tex:SetPoint("CENTER", dropZone, "CENTER", dx, 80)
    fx.move:SetOffset(-dx * 0.9, -84)
    fx.liftUp:SetOffset(0, 0)
    fx.liftDown:SetOffset(0, 0)
    fx.spin:SetDegrees(math.random(-200, 200))
    fx.tex:Show()
    fx.group:Restart()
end

-- The catalog variant: the icon takes off at the mouse (or at an origin
-- frame, when the launch point should not follow the cursor) and arcs over
-- into the cart, wherever the window happens to be.
local function playFly(entry, scatter, origin)
    local fx = takeFx()
    if not fx then
        return
    end
    fx.busy = true
    setIcon(fx.tex, entry)
    local s = entry.dye and 56 or 112
    fx.tex:SetSize(s, s)
    local scale = dropZone:GetEffectiveScale()
    local px, py
    if origin then
        local os = origin:GetEffectiveScale()
        local x, y = origin:GetCenter()
        px, py = x * os, y * os
    else
        px, py = GetCursorPosition()
    end
    local dzx, dzy = dropZone:GetCenter()
    local ox = px / scale - dzx
    local oy = py / scale - dzy
    if scatter then
        ox = ox + math.random(-45, 45)
        oy = oy + math.random(-35, 35)
    end
    fx.tex:ClearAllPoints()
    fx.tex:SetPoint("CENTER", dropZone, "CENTER", ox, oy)
    fx.move:SetOffset(-ox, -oy)
    local lift = 60 + math.abs(ox) * 0.2
    fx.liftUp:SetOffset(0, lift)
    fx.liftDown:SetOffset(0, -lift)
    fx.spin:SetDegrees(math.random(-240, 240))
    fx.tex:Show()
    fx.group:Restart()
end

-- An add from a + button or swatch pops the cart up and flies the icon in.
-- A 5 or 10 add sends a staggered convoy instead of one icon. The stagger
-- keeps only a handful airborne at once, so even the full 10 fits the fx
-- pool. Each launch reads the mouse fresh, so the convoy trails the cursor
-- if it moves. Passing nil (a failed add) is fine, nothing plays.
function DCR.CartFlyFX(entry, count)
    if not entry then
        return
    end
    DCR.ShowCart()
    playFly(entry)
    for i = 2, math.min(count or 1, 10) do
        C_Timer.After(0.1 * (i - 1), function()
            if panel:IsShown() then
                playFly(entry)
            end
        end)
    end
end

-- The blueprint buttons send a loose clump instead of a convoy: up to ten of
-- the added pieces take off around the clicked button within a blink of each
-- other, each from its own spot. The blueprint window is a plain text list
-- with nothing to throw, so the button stands in as the launch pad. Random
-- picks, because a big blueprint carts far more rows than fit in the air at
-- once. The pool cap above is sized for this worst case.
function DCR.CartFlyBurst(entries, origin)
    if #entries == 0 then
        return
    end
    DCR.ShowCart()
    for i = #entries, 2, -1 do
        local j = math.random(i)
        entries[i], entries[j] = entries[j], entries[i]
    end
    playFly(entries[1], true, origin)
    for i = 2, math.min(#entries, 10) do
        local entry = entries[i]
        C_Timer.After(math.random() * 0.3, function()
            if panel:IsShown() then
                playFly(entry, true, origin)
            end
        end)
    end
end

-- The dashboard is load-on-demand, and its catalog tab is where the + buttons
-- live outside the house editor.
local function openCatalog()
    if not HousingDashboardFrame then
        C_AddOns.LoadAddOn("Blizzard_HousingDashboard")
    end
    if not HousingDashboardFrame then
        return
    end
    ShowUIPanel(HousingDashboardFrame)
    if HousingDashboardFrame.catalogTab then
        HousingDashboardFrame:SetTab(HousingDashboardFrame.catalogTab)
    end
end

local function paintDropZone()
    dropText:ClearAllPoints()
    if pending then
        dropZone:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
        setIcon(dropIcon, pending)
        dropText:SetPoint("LEFT", dropIcon, "RIGHT", 12, 0)
        dropText:SetPoint("RIGHT", -10, 0)
        dropText:SetText("Add: " .. (pending.name or "selected decor"))
        dropText:SetTextColor(1, 1, 1)
        catalogLink:Hide()
        dyeLink:Hide()
        bpLink:Hide()
    else
        dropZone:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        dropIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        dropText:SetPoint("LEFT", dropIcon, "RIGHT", 12, 15)
        dropText:SetPoint("RIGHT", -10, 15)
        dropText:SetText("Drop decor here in edit mode,")
        dropText:SetTextColor(DIM[1], DIM[2], DIM[3])
        catalogLink:Show()
        dyeLink:Show()
        -- blueprints only exist on 12.1 clients
        bpLink:SetShown(C_HousingBlueprint ~= nil)
    end
end

-- The item name reaches the AH search, with the entry name (for dyes the
-- color) as the looser fallback while the item is not cached. Searches go
-- through Auctionator's shopping tab when it is installed, its non-exact
-- mode so a color name still matches the dye item. The stock browse only
-- takes one term, which is enough for a row's own button.
local function ahName(entry)
    return entry.itemID and (C_Item.GetItemNameByID(entry.itemID) or entry.name) or nil
end

local ahApi = function()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.MultiSearchAdvanced and api or nil
end

-- Without Auctionator the browse results would still need a click to reach
-- the item's purchase screen, so this watcher makes that click: when the
-- results of our query land it selects the searched item, the same
-- SelectBrowseResult call a row click makes (Auctionator does it from addon
-- code too). The planned amount goes through the frame's quantity callback
-- rather than the input box, because the commodity list rebroadcasts its own
-- stored count once its results load and would put a plain write back to 1.
local ahJump = CreateFrame("Frame")

-- The preset amount is addon-written state, and Blizzard's buy flow reading
-- it makes the server answer with the internal auction house error even
-- though the purchase goes through fine (observed 120007). While a preset
-- is live, that one error gets filtered: the AH frame's error event moves
-- over to this frame, which forwards everything else through the same call
-- Blizzard makes. The stock wiring comes back when the AH closes.
local errFilter = CreateFrame("Frame")

local function errFilterStop()
    errFilter:UnregisterAllEvents()
    if AuctionHouseFrame then
        AuctionHouseFrame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
    end
end

local function errFilterStart()
    AuctionHouseFrame:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
    errFilter:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
    errFilter:RegisterEvent("AUCTION_HOUSE_CLOSED")
end

errFilter:SetScript("OnEvent", function(_, event, err)
    if event == "AUCTION_HOUSE_CLOSED" then
        errFilterStop()
    elseif err ~= Enum.AuctionHouseError.DatabaseError then
        UIErrorsFrame:AddExternalErrorMessage(AuctionHouseUtil.GetErrorText(err))
    end
end)

local function ahJumpStop()
    ahJump.target = nil
    ahJump.result = nil
    ahJump:UnregisterAllEvents()
end

local function ahJumpSelect(result)
    local info = C_AuctionHouse.GetItemKeyInfo(result.itemKey)
    if not info then
        -- key info not cached yet, retried when the received event fires
        ahJump.result = result
        ahJump:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
        return
    end
    local qty = ahJump.target.qty
    ahJumpStop()
    AuctionHouseFrame:SelectBrowseResult(result)
    if info.isCommodity and qty > 1 then
        AuctionHouseFrame:TriggerEvent(AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged, qty)
        errFilterStart()
    end
end

ahJump:SetScript("OnEvent", function(self, event, arg)
    if event == "AUCTION_HOUSE_CLOSED" or not self.target then
        ahJumpStop()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        for _, result in ipairs(C_AuctionHouse.GetBrowseResults()) do
            if result.itemKey.itemID == self.target.itemID then
                ahJumpSelect(result)
                return
            end
        end
        -- not listed, the browse list itself is the answer then
        ahJumpStop()
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" and arg == self.target.itemID then
        ahJumpSelect(self.result)
    end
end)

local function ahJumpArm(itemID, qty)
    ahJump.target = { itemID = itemID, qty = qty or 1 }
    ahJump.result = nil
    ahJump:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    ahJump:RegisterEvent("AUCTION_HOUSE_CLOSED")
end

-- terms are { searchString, quantity } pairs, the advanced search carries
-- the planned count into Auctionator's shopping list like its own crafting
-- searches do. A term may also carry the itemID, which the fallback path
-- uses to jump from the results to the item's purchase screen.
local function ahSearch(terms)
    if #terms == 0 then
        return
    end
    local api = ahApi()
    if api then
        api.MultiSearchAdvanced("QoLify Decor Tools", terms)
        return
    end
    -- No Auctionator: a raw browse query, the shape its scans use (every
    -- field present, empty tables included, nil filters match nothing), and
    -- the jump watcher carries the results on into the purchase screen. The
    -- search box stays empty on purpose: writing to it taints the results
    -- and buying those throws an internal auction house error (observed
    -- 120007), while results from a raw query never pass through
    -- addon-touched UI state.
    C_AuctionHouse.SendBrowseQuery({
        searchString = terms[1].searchString,
        sorts = {},
        filters = {},
        itemClassFilters = {},
    })
    if terms[1].itemID then
        ahJumpArm(terms[1].itemID, terms[1].quantity)
    end
    -- flip back from an item's details to the browse list, the same call
    -- Blizzard's search path makes right after its own query
    if AuctionHouseFrame and AuctionHouseFrameDisplayMode and AuctionHouseFrame.SetDisplayMode then
        AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    end
end

-- Dye rows are shorter than decor rows, so a row reused across the two kinds
-- resizes its icon and slides its buttons up. The list handles where it sits
-- and how big it is.
local function shapeRow(row, entry)
    local icon = entry.dye and 35 or 60
    row.icon:SetSize(icon, icon)
    row.remove:ClearAllPoints()
    row.remove:SetPoint("TOPRIGHT", -2, entry.dye and -4 or -10)
    -- buy and ah share the slot, a merchant and the AH cannot both be open
    row.buy:ClearAllPoints()
    row.buy:SetPoint("BOTTOMRIGHT", -2, entry.dye and 4 or 6)
    row.ah:ClearAllPoints()
    row.ah:SetPoint("BOTTOMRIGHT", -2, entry.dye and 4 or 6)
end

-- The footer line: the item count, then every cost tinted by whether the
-- purse covers it. Prices get learned at vendors, so the sum stays marked
-- partial until every item has been seen at one. Kept apart from the refresh
-- because money and currencies move without the cart changing.
local function paintTotals()
    if not countText then
        return
    end
    local parts = {}
    if lastKnownCost > 0 then
        parts[1] = tint(GetMoney() >= lastKnownCost, DCR.Money(lastKnownCost, 16))
    end
    for _, t in ipairs(lastCurrencyTotals) do
        local held = heldFor(t)
        local text = t.icon and (t.amount .. " |T" .. t.icon .. ":16|t") or (t.amount .. " " .. (t.label or "?"))
        parts[#parts + 1] = held and tint(held >= t.amount, text) or text
    end
    local text = lastCount == 1 and "1 item planned" or (lastCount .. " items planned")
    if #parts > 0 then
        text = text .. ", " .. table.concat(parts, " + ") .. (lastUnpriced and " so far" or "")
    end
    countText:SetText(text)
end

local function bindRow(row, entry)
    row.recordID = entry.recordID
    setIcon(row.icon, entry)
    shapeRow(row, entry)
    row.name:SetText(entry.name or ("decor " .. entry.recordID))
    -- No itemID means no vendor to buy it from (yet), shown dimmed.
    if entry.itemID then
        row.name:SetTextColor(1, 1, 1)
    else
        row.name:SetTextColor(DIM[1], DIM[2], DIM[3])
    end
    row.qty:SetText("x" .. entry.qty)
    row.cost:SetText(costText(entry))
    row.buy:SetShown(DCR.MerchantSlotFor(entry.recordID) ~= nil)
    row.ah:SetShown(needsAH(entry))
end

local function refresh()
    if not panel then
        return
    end
    local list = DCR.CartItems()
    for _, s in ipairs(SECTIONS) do
        s.entries = s.entries or {}
        wipe(s.entries)
    end
    if list then
        for _, entry in pairs(list) do
            for _, s in ipairs(SECTIONS) do
                if s.match(entry) then
                    table.insert(s.entries, entry)
                    break
                end
            end
        end
    end
    -- A wide window keeps the sections stacked but flows each section's own
    -- rows into columns, one more per default-window's worth of width, so a
    -- lone section spreads out too. Headers span the whole width.
    local contentW = listContent:GetWidth()
    lastLayoutW = contentW
    local cols = math.max(1, math.floor((contentW + COL_GAP) / (COL_W + COL_GAP)))
    local colW = cols == 1 and contentW or math.floor((contentW - (cols - 1) * COL_GAP) / cols)
    local total = 0
    local knownCost = 0
    local currencies, currencyOrder = {}, {}
    local unpriced = false
    local y = 0
    rowList:Reset()
    local cart = DCR.CartDB()
    local collapsed = cart and cart.collapsed or {}
    for _, s in ipairs(SECTIONS) do
        local h = s.header
        if #s.entries == 0 then
            h:Hide()
        else
            table.sort(s.entries, byAge)
            local closed = collapsed[s.key]
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -y)
            h:SetWidth(contentW)
            h.title:SetText((closed and "+ " or "- ") .. s.title .. " (" .. #s.entries .. ")")
            h:Show()
            y = y + 24
            -- rows fill a column until it holds its share of the section's
            -- height, then spill into the next
            local totalH = 0
            if not closed then
                for _, entry in ipairs(s.entries) do
                    totalH = totalH + (entry.dye and DYE_ROW_H or ROW_H)
                end
            end
            local target = math.ceil(totalH / cols)
            local cx, cy, tallest = 0, 0, 0
            local remH = totalH
            local secBuyable, secAH = false, false
            rowList:Column()
            for _, entry in ipairs(s.entries) do
                -- the footer always sums the whole cart, collapsed or not
                total = total + entry.qty
                local rec = DCR.PriceFor(entry.itemID)
                if rec and rec.price then
                    knownCost = knownCost + rec.price * entry.qty
                end
                if rec and rec.costs then
                    for _, c in ipairs(rec.costs) do
                        local key = costKey(c)
                        local t = currencies[key]
                        if not t then
                            t = {
                                amount = 0,
                                icon = c.icon,
                                label = c.label,
                                currencyID = c.currencyID,
                                link = c.link,
                            }
                            currencies[key] = t
                            currencyOrder[#currencyOrder + 1] = t
                        end
                        t.amount = t.amount + c.amount * entry.qty
                    end
                end
                unpriced = unpriced or not priced(rec)
                secBuyable = secBuyable or DCR.MerchantSlotFor(entry.recordID) ~= nil
                secAH = secAH or needsAH(entry)
                if not closed then
                    local rowH = entry.dye and DYE_ROW_H or ROW_H
                    rowList:Add(entry, cx * (colW + COL_GAP), y + cy, colW, rowH)
                    cy = cy + rowH
                    tallest = math.max(tallest, cy)
                    -- spill once a column holds its share of what was left
                    -- when it started, so leftovers land in the front
                    -- columns and the tail never runs longest
                    remH = remH - rowH
                    if cy >= target and cx < cols - 1 then
                        cx = cx + 1
                        cy = 0
                        target = math.ceil(remH / (cols - cx))
                        rowList:Column()
                    end
                end
            end
            -- A vendor and the AH cannot both be open, so the two header
            -- buttons share their slot. The batch search needs Auctionator.
            h.buy:SetShown(secBuyable)
            h.ah:SetShown(secAH and ahApi() ~= nil)
            y = y + tallest
        end
    end
    listContent:SetHeight(math.max(1, y))
    table.sort(currencyOrder, function(a, b)
        return (a.label or "") < (b.label or "")
    end)
    lastKnownCost, lastCurrencyTotals, lastCount = knownCost, currencyOrder, total
    lastUnpriced = unpriced
    paintTotals()
    rowList:Paint()
end
DCR.RefreshCartUI = refresh

-- The two-click confirm's countdown, shared by the section buy buttons:
-- while armed, a gold line runs clockwise around the button's border,
-- showing how long the second click has before it lapses.
local function addArmSweep(btn)
    local function edge(point, vertical)
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
        t:SetPoint(point)
        if vertical then
            t:SetWidth(1)
        else
            t:SetHeight(1)
        end
        t:Hide()
        return t
    end
    local top = edge("TOPLEFT")
    local right = edge("TOPRIGHT", true)
    local bottom = edge("BOTTOMRIGHT")
    local left = edge("BOTTOMLEFT", true)

    local function seg(t, len, vertical)
        if len > 0 then
            t:Show()
            if vertical then
                t:SetHeight(len)
            else
                t:SetWidth(len)
            end
        else
            t:Hide()
        end
    end

    -- OnUpdate only while armed, takes itself down when the window lapses
    btn.armSweep = function(self)
        local p = (GetTime() - self.armedAt) / ARM_SECS
        if not self.armed or p >= 1 then
            self:SetScript("OnUpdate", nil)
            top:Hide()
            right:Hide()
            bottom:Hide()
            left:Hide()
            return
        end
        local w, h = self:GetWidth(), self:GetHeight()
        local run = p * 2 * (w + h)
        seg(top, math.min(run, w))
        seg(right, math.min(run - w, h), true)
        seg(bottom, math.min(run - w - h, w))
        seg(left, math.min(run - 2 * w - h, h), true)
    end
end

local POPUP_SHORT = "DECOR_TOOLS_CART_BUY_SHORT"
local POPUP_NONE = "DECOR_TOOLS_CART_BUY_NONE"

local function joinAnd(parts)
    if #parts < 2 then
        return parts[1] or ""
    end
    return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

local function stockLine(s, plan)
    return ("This vendor stocks %d planned %s in %s."):format(
        plan.total,
        plan.total == 1 and "item" or "items",
        s.phrase
    )
end

-- What the warning popup says when the purse cannot cover the whole section.
local function planText(s, plan)
    local missing = {}
    if plan.shortGold > 0 then
        missing[1] = DCR.Money(plan.shortGold)
    end
    for _, t in ipairs(plan.short) do
        missing[#missing + 1] = t.amount .. " " .. (t.label or "unknown currency")
    end
    if plan.afford == 0 then
        return stockLine(s, plan) .. "\n\nYou are short " .. joinAnd(missing) .. ", so none of them can be bought yet."
    end
    return stockLine(s, plan)
        .. "\n\nBuying them all needs another "
        .. joinAnd(missing)
        .. ", so only "
        .. plan.afford
        .. " of them will go through. Buy those now?"
end

-- Registered when the window is first built, so a standing-by module never
-- writes into the global dialog list.
local function registerPopups()
    StaticPopupDialogs[POPUP_SHORT] = {
        text = "%s",
        button1 = "Buy",
        button2 = CANCEL,
        OnAccept = function(_, data)
            startBuying(data.section, data.btn)
        end,
        timeout = 0,
        hideOnEscape = true,
    }
    StaticPopupDialogs[POPUP_NONE] = {
        text = "%s",
        button1 = OKAY,
        timeout = 0,
        hideOnEscape = true,
    }
end

-- Hovering a section's Buy all prices up this vendor's share of it, tinted
-- the way the footer sum is.
local function onSectionBuyEnter(self)
    local s = self.section
    local plan = buyPlan(s)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Buy all")
    GameTooltip:AddLine(stockLine(s, plan), 1, 1, 1, true)
    if plan.gold > 0 then
        local money = GetMoney()
        costLine(DCR.Money(plan.gold), DCR.Money(money), money >= plan.gold)
    end
    for _, t in ipairs(plan.needs) do
        costLine(
            t.amount .. " " .. (t.label or "Unknown currency"),
            t.held and tostring(t.held),
            t.held and t.held >= t.amount
        )
    end
    if plan.afford < plan.total then
        local line = plan.afford == 0 and "Not enough for any of them."
            or ("Enough for %d of them."):format(plan.afford)
        GameTooltip:AddLine(line, SHORT_RGB[1], SHORT_RGB[2], SHORT_RGB[3])
    end
    GameTooltip:Show()
end

local function onSectionBuy(self)
    if buyTicker then
        stopBuying("stopped.")
        return
    end
    local s = self.section
    local plan = buyPlan(s)
    -- Short somewhere, so the popup does the confirming instead of the two
    -- click arm and says how far the money goes.
    if plan.afford < plan.total then
        self.armed = nil
        self.text:SetText("Buy all")
        StaticPopup_Show(
            plan.afford > 0 and POPUP_SHORT or POPUP_NONE,
            planText(s, plan),
            nil,
            { section = s, btn = self }
        )
        return
    end
    if not self.armed then
        self.armed = true
        self.armedAt = GetTime()
        self.text:SetText("Really?")
        self:SetScript("OnUpdate", self.armSweep)
        DCR.Print(
            ("this vendor covers %d planned buys in %s, click again to get them at 3 a second."):format(
                plan.total,
                s.phrase
            )
        )
        C_Timer.After(ARM_SECS, function()
            if self.armed then
                self.armed = nil
                self.text:SetText("Buy all")
            end
        end)
        return
    end
    startBuying(s, self)
end

local function onSectionAh(self)
    local s = self.section
    local list = DCR.CartItems()
    local terms = {}
    if list then
        for _, entry in pairs(list) do
            if s.match(entry) and needsAH(entry) then
                local name = ahName(entry)
                if name then
                    table.insert(terms, { searchString = name, quantity = entry.qty })
                end
            end
        end
    end
    ahSearch(terms)
end

-- One collapsible header per section. The title row toggles the rows below
-- it, the right edge carries the section's own buy and AH search buttons.
local function makeSectionHeader(s)
    local h = CreateFrame("Button", nil, listContent)
    h:SetHeight(24)
    h.title = label(h, "", GOLD)
    h.title:SetPoint("LEFT", 2, 0)
    h:SetScript("OnClick", function()
        local cart = DCR.CartDB()
        if cart then
            cart.collapsed[s.key] = not cart.collapsed[s.key] or nil
            refresh()
        end
    end)
    h.buy = flatButton(h, "Buy all", 60)
    h.buy:SetHeight(18)
    h.buy:SetPoint("RIGHT", -2, 0)
    h.buy.section = s
    addArmSweep(h.buy)
    h.buy:SetScript("OnClick", onSectionBuy)
    h.buy:HookScript("OnEnter", onSectionBuyEnter)
    h.buy:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    h.ah = flatButton(h, "AH", 34)
    h.ah:SetHeight(18)
    h.ah:SetPoint("RIGHT", -2, 0)
    h.ah.section = s
    h.ah:SetScript("OnClick", onSectionAh)
    h.ah:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Search the auction house for this section's unpriced items")
        GameTooltip:Show()
    end)
    h.ah:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    h:Hide()
    return h
end

local function rowEntry(row)
    local list = DCR.CartItems()
    return list and row.recordID and list[row.recordID]
end

-- Position and size come from the list on every paint, since a reused
-- row can switch between the decor and dye shapes.
function createRow()
    local row = CreateFrame("Frame", nil, listContent)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 2, 0)

    local remove = flatButton(row, "x", 18)
    remove:SetHeight(18)
    row.remove = remove
    remove:SetScript("OnClick", function()
        DCR.RemoveCartEntry(row.recordID)
    end)

    -- shown only while a vendor selling this item is open
    row.buy = flatButton(row, "Buy 1", 56)
    row.buy:SetHeight(20)
    row.buy:Hide()
    row.buy:SetScript("OnClick", function()
        local slot = DCR.MerchantSlotFor(row.recordID)
        if slot then
            BuyMerchantItem(slot, 1)
        end
    end)

    -- shown at the auction house for items no vendor has priced
    row.ah = flatButton(row, "AH", 34)
    row.ah:SetHeight(20)
    row.ah:Hide()
    row.ah:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Search the auction house")
        if not ahApi() then
            GameTooltip:AddLine("Opens the item's purchase page, amount preset.", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    row.ah:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.ah:SetScript("OnClick", function()
        local entry = rowEntry(row)
        local name = entry and ahName(entry)
        if name then
            ahSearch({ { searchString = name, quantity = entry.qty, itemID = entry.itemID } })
        end
    end)

    local function stepTooltip(btn, action)
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(action)
            GameTooltip:AddLine("Shift: 5 at a time, Ctrl: 10", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local plus = flatButton(row, "+", 18)
    plus:SetHeight(18)
    plus:SetPoint("RIGHT", remove, "LEFT", -6, 0)
    stepTooltip(plus, "Plan more")
    plus:SetScript("OnClick", function()
        local entry = rowEntry(row)
        if entry then
            DCR.SetCartQty(row.recordID, entry.qty + DCR.ClickStep())
        end
    end)

    local minus = flatButton(row, "-", 18)
    minus:SetHeight(18)
    minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    stepTooltip(minus, "Plan fewer")
    minus:SetScript("OnClick", function()
        local entry = rowEntry(row)
        if entry and entry.qty > 1 then
            DCR.SetCartQty(row.recordID, entry.qty - DCR.ClickStep())
        end
    end)

    row.qty = label(row, "", { 1, 1, 1 }, "GameFontNormalSmall")
    row.qty:SetPoint("RIGHT", minus, "LEFT", -8, 0)

    row.name = label(row, "", { 1, 1, 1 }, "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 9)
    row.name:SetPoint("RIGHT", row, "RIGHT", -100, 9)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.cost = label(row, "", DIM, "GameFontNormal")
    row.cost:SetPoint("LEFT", row.icon, "RIGHT", 10, -12)
    row.cost:SetPoint("RIGHT", row, "RIGHT", -100, -12)
    row.cost:SetJustifyH("LEFT")
    row.cost:SetWordWrap(false)

    -- hovering the icon shows the item's own tooltip, when the entry has
    -- resolved to an item at all
    local iconHover = CreateFrame("Frame", nil, row)
    iconHover:SetAllPoints(row.icon)
    iconHover:EnableMouse(true)
    iconHover:SetScript("OnEnter", function(self)
        local entry = rowEntry(row)
        if not (entry and entry.itemID) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(entry.itemID)
        -- one item, several colors: say which ones this row was built from
        local shades = entry.shades
        if shades and #shades > 1 then
            local names = {}
            for _, id in ipairs(shades) do
                local dye = C_DyeColor.GetDyeColorInfo(id)
                names[#names + 1] = dye and dye.name
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Carted for " .. table.concat(names, ", "), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    iconHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- hovering the cost line names the currency (with the full currency
    -- tooltip when there is exactly one)
    local costHover = CreateFrame("Frame", nil, row)
    costHover:SetAllPoints(row.cost)
    costHover:EnableMouse(true)
    costHover:SetScript("OnEnter", function(self)
        local entry = rowEntry(row)
        local rec = entry and DCR.PriceFor(entry.itemID)
        local costs = rec and rec.costs
        if not costs or #costs == 0 then
            return
        end
        -- barter costs sometimes deliver the item link in place of a name,
        -- so a linkish label is as good as a stored link
        local function costLink(c)
            if c.link then
                return c.link
            end
            if c.label and c.label:find("|H", 1, true) then
                return c.label
            end
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = #costs == 1 and costLink(costs[1])
        if #costs == 1 and costs[1].currencyID then
            GameTooltip:SetCurrencyByID(costs[1].currencyID)
        elseif link then
            GameTooltip:SetHyperlink(link)
        else
            for _, c in ipairs(costs) do
                GameTooltip:AddLine((c.label or "Unknown currency") .. ": " .. c.amount, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    costHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function addResolved(entry)
    local added = DCR.AddCartEntry(entry)
    if added then
        playFx(added)
    end
    return added
end

-- 12.1 swaps GetDyeColorForItem for GetDyeColorsForItem, which returns the
-- item's whole dye list (a dozen since the consolidation). Any of them keys
-- the same cart entry, so the first will do. Drop the fallback once 12.1 is
-- the only client left.
local function dyeForItem(link)
    if C_DyeColor.GetDyeColorsForItem then
        local ids = C_DyeColor.GetDyeColorsForItem(link)
        return ids and ids[1]
    end
    return C_DyeColor.GetDyeColorForItem(link)
end

local function addFromCursor()
    local kind, _, cursorLink = GetCursorInfo()
    if kind ~= "item" then
        return false
    end
    local entry = cursorLink and C_HousingCatalog.GetCatalogEntryInfoByItem(cursorLink)
    if entry then
        addResolved(entry)
        ClearCursor()
        return true
    end
    local dyeColorID = cursorLink and dyeForItem(cursorLink)
    local added = dyeColorID and DCR.AddDyeEntry(C_DyeColor.GetDyeColorInfo(dyeColorID))
    if added then
        playFx(added)
        ClearCursor()
    else
        -- Leave the item on the cursor so it can go back to the bags.
        DCR.Print("that item is not housing decor or dye.")
    end
    return true
end

local function onDropZoneClick()
    if addFromCursor() then
        return
    end
    -- Read the selection fresh, the cached pending is just for the display.
    local info = C_HousingDecor.GetSelectedDecorInfo()
    local entry = info and DCR.ResolveDecor(info) or pending
    if entry then
        addResolved(entry)
    else
        DCR.Print("select a decor piece in your house, or drag a decor item here.")
    end
end

local WIN_NAME = "DecorShoppingCart"

local function build()
    registerPopups()
    -- stayOpen: the cart has to survive entering the house editor.
    panel = DCR.Window(WIN_NAME, 400, 620, "Shopping Cart", true)

    -- resizable from the corner, everything inside follows its anchors. The
    -- caps: enough width for five columns (68 is the window chrome around
    -- the list) and seven tenths of the screen tall.
    panel:SetResizable(true)
    panel:SetResizeBounds(340, 420, 5 * COL_W + 4 * COL_GAP + 68, UIParent:GetHeight() * 0.7)
    -- a saved size from before these caps existed restores unbounded, so
    -- rein it in here rather than waiting for the next grip drag
    local minW, minH, maxW, maxH = panel:GetResizeBounds()
    local w, h = panel:GetSize()
    panel:SetSize(math.min(math.max(w, minW), maxW), math.min(math.max(h, minH), maxH))
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        panel:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        panel:SaveRect()
    end)

    -- Parented to the cart so it shares its scale and lifetime, but on a
    -- higher strata: the icons fly across window edges, and both the cart's
    -- own children and a raised paint catalog would otherwise cover them.
    fxLayer = CreateFrame("Frame", nil, panel)
    fxLayer:SetFrameStrata("FULLSCREEN_DIALOG")
    fxLayer:SetSize(1, 1)
    fxLayer:SetPoint("CENTER")

    dropZone = CreateFrame("Button", nil, panel, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT", 18, -56)
    dropZone:SetPoint("TOPRIGHT", -18, -56)
    dropZone:SetHeight(76)
    dropZone:SetBackdrop({ bgFile = DCR.WHITE, edgeFile = DCR.WHITE, edgeSize = 1 })
    dropZone:SetBackdropColor(0.1, 0.1, 0.13, 1)
    dropZone:SetScript("OnClick", onDropZoneClick)
    dropZone:SetScript("OnReceiveDrag", addFromCursor)

    dropIcon = dropZone:CreateTexture(nil, "ARTWORK")
    dropIcon:SetSize(32, 32)
    dropIcon:SetPoint("LEFT", 14, 0)

    dropText = label(dropZone, "", DIM)
    dropText:SetPoint("LEFT", dropIcon, "RIGHT", 12, 0)
    dropText:SetPoint("RIGHT", -10, 0)
    dropText:SetJustifyH("LEFT")
    dropText:SetWordWrap(false)

    local function goldLink(text, onClick)
        local btn = CreateFrame("Button", nil, dropZone)
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT")
        t:SetText(text)
        t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        btn:SetSize(t:GetStringWidth() + 2, 14)
        btn:SetScript("OnEnter", function()
            t:SetTextColor(1, 1, 1)
        end)
        btn:SetScript("OnLeave", function()
            t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    catalogLink = goldLink("or add from the catalog", openCatalog)
    catalogLink:SetPoint("TOPLEFT", dropText, "BOTTOMLEFT", 0, -3)

    dyeLink = goldLink("or pick a dye", function()
        if DCR.HideBlueprintPicker then
            DCR.HideBlueprintPicker() -- shares the cart's right edge
        end
        DCR.ToggleDyeCatalog(panel)
    end)
    dyeLink:SetPoint("LEFT", catalogLink, "RIGHT", 10, 0)

    bpLink = goldLink("or add from a blueprint", function()
        DCR.ToggleBlueprintPicker(panel)
    end)
    bpLink:SetPoint("TOPLEFT", catalogLink, "BOTTOMLEFT", 0, -3)

    bounce = dropZone:CreateAnimationGroup()
    local dip = bounce:CreateAnimation("Translation")
    dip:SetDuration(0.07)
    dip:SetOffset(0, -4)
    dip:SetSmoothing("OUT")
    local rise = bounce:CreateAnimation("Translation")
    rise:SetStartDelay(0.07)
    rise:SetDuration(0.12)
    rise:SetOffset(0, 4)
    rise:SetSmoothing("OUT")

    local box, scroll
    box, listContent, scroll = DCR.ScrollBox(panel)
    box:SetPoint("TOPLEFT", 18, -144)
    box:SetPoint("BOTTOMRIGHT", -18, 46)
    rowList = DCR.VirtualList(scroll, createRow, bindRow)
    -- reflow the columns while the window is dragged wider or narrower, but
    -- not when refresh itself sets the content height
    listContent:SetScript("OnSizeChanged", function(self)
        if math.abs(self:GetWidth() - (lastLayoutW or 0)) > 0.5 then
            refresh()
        end
    end)

    for _, s in ipairs(SECTIONS) do
        s.header = makeSectionHeader(s)
    end

    local clearBtn = flatButton(panel, "Clear all", 90)
    clearBtn:SetPoint("BOTTOMRIGHT", -18, 16)

    countText = label(panel, "", DIM)
    countText:SetPoint("BOTTOMLEFT", 18, 20)
    countText:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)

    -- hovering the total names the currencies behind the icons
    local totalsHover = CreateFrame("Frame", nil, panel)
    totalsHover:SetAllPoints(countText)
    totalsHover:EnableMouse(true)
    totalsHover:SetScript("OnEnter", function(self)
        if lastKnownCost == 0 and #lastCurrencyTotals == 0 then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Planned total", GOLD[1], GOLD[2], GOLD[3])
        if lastKnownCost > 0 then
            local money = GetMoney()
            costLine(DCR.Money(lastKnownCost), DCR.Money(money), money >= lastKnownCost)
        end
        for _, t in ipairs(lastCurrencyTotals) do
            local held = heldFor(t)
            costLine(
                t.amount .. " " .. (t.label or "Unknown currency"),
                held and tostring(held),
                held and held >= t.amount
            )
        end
        GameTooltip:Show()
    end)
    totalsHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    clearBtn:SetScript("OnClick", function(self)
        -- second click within a few seconds actually clears
        if self.armed then
            self.armed = nil
            self.text:SetText("Clear all")
            DCR.ClearCart()
            return
        end
        self.armed = true
        self.text:SetText("Really?")
        C_Timer.After(3, function()
            if self.armed then
                self.armed = nil
                self.text:SetText("Clear all")
            end
        end)
    end)

    -- The editor hides the normal UI layer, so the window rides on
    -- HouseEditorFrame while that is shown and moves back to UIParent when
    -- it closes. Anchors stay on UIParent either way, so it keeps its spot.
    function updateParent()
        local editor = HouseEditorFrame
        if editor and editor:IsShown() then
            if panel:GetParent() ~= editor then
                panel:SetParent(editor)
                panel:SetFrameStrata("FULLSCREEN_DIALOG")
            end
        elseif panel:GetParent() ~= UIParent then
            panel:SetParent(UIParent)
            panel:SetFrameStrata("DIALOG")
        end
    end
    local modeWatcher = CreateFrame("Frame")
    modeWatcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    -- Leaving the house takes the editor down without a mode change, and the
    -- cart would sit invisible under a hidden parent until the next one.
    modeWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    modeWatcher:SetScript("OnEvent", updateParent)
    updateParent()

    -- Selection watching only runs while the window is open. Outside the
    -- house editor the event never fires, so no further gating needed.
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, event)
        if event ~= "HOUSING_DECOR_SELECT_RESPONSE" then
            paintTotals() -- the purse moved, so the tints do too
            return
        end
        local info = C_HousingDecor.GetSelectedDecorInfo()
        pending = info and DCR.ResolveDecor(info) or nil
        paintDropZone()
    end)
    panel:SetScript("OnShow", function()
        watcher:RegisterEvent("HOUSING_DECOR_SELECT_RESPONSE")
        watcher:RegisterEvent("PLAYER_MONEY")
        watcher:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        local info = C_HousingDecor.GetSelectedDecorInfo()
        pending = info and DCR.ResolveDecor(info) or nil
        paintDropZone()
        -- retries missing itemIDs and price estimates while data is warm
        DCR.RebuildCartLookup()
        refresh()
    end)
    panel:SetScript("OnHide", function()
        watcher:UnregisterAllEvents()
        pending = nil
        paintDropZone()
        stopBuying() -- closing the window should not keep purchases running
    end)

    paintDropZone()
    panel:Hide()
end

-- /cart reset also works before the window was ever opened, then only the
-- saved rect needs clearing
function DCR.ResetCart()
    if panel then
        panel:ResetRect()
        return
    end
    local rects = DCR.WindowDB()
    if rects then
        rects[WIN_NAME] = nil
    end
end

-- Shown but not visible means the parent went down under it, so every way in
-- re-homes the window first and reads visibility rather than the shown flag.
-- Otherwise a hidden parent leaves the toggle flipping a flag nobody sees.
function DCR.OpenCart()
    if not panel then
        build()
    end
    if panel:IsVisible() then
        panel:Hide()
        return
    end
    updateParent()
    panel:Show() -- OnShow refreshes
end

-- Show without toggling, for the catalog + buttons: an add should bring the
-- cart up so the item is seen landing in it.
function DCR.ShowCart()
    if not panel then
        build()
    end
    updateParent()
    panel:Show()
end

-- For Merchant.lua's vendor auto-open. Says whether it actually opened the
-- window, so a cart the player already had up is not closed again on leave.
function DCR.AutoShowCart()
    if panel and panel:IsVisible() then
        return false
    end
    DCR.ShowCart()
    return true
end

function DCR.HideCart()
    if panel then
        panel:Hide()
    end
end
