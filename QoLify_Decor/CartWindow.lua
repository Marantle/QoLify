local _, DCR = ...

-- The shopping cart window (/cart). A drop box up top that takes the decor
-- piece currently selected in the house editor (or a decor item dragged from
-- the bags), and the planned list below it. Built on first open.

local GOLD = DCR.COLOR_GOLD
local DIM = DCR.COLOR_DIM
local label, flatButton = DCR.Label, DCR.FlatButton

local ROW_H = 76
local ARM_SECS = 4 -- how long the Buy all confirm click stays armed

local panel, dropZone, dropIcon, dropText, listContent, countText, buyAllBtn
local catalogLink -- "or add from the catalog" line, opens the catalog
local bounce -- drop zone thump, played when an added icon lands in it
local rows = {}
local createRow
local pending -- catalog entry for the decor currently selected in the editor
local buyTicker
local lastKnownCost, lastCurrencyTotals -- what the footer currently sums, for its tooltip

local function setIcon(tex, entry)
    if entry.iconAtlas then
        tex:SetAtlas(entry.iconAtlas)
    else
        tex:SetTexture(entry.icon or 134400)
    end
end

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

-- Auto-buy: one carted item every half second while the vendor stays open.
local function stopBuying(msg)
    if buyTicker then
        buyTicker:Cancel()
        buyTicker = nil
    end
    if buyAllBtn then
        buyAllBtn.armed = nil
        buyAllBtn.text:SetText("Buy all")
    end
    if msg then
        DCR.Print(msg)
    end
end

local function affordable(rec)
    if not rec then
        return true -- price never seen, let the buy speak for itself
    end
    if rec.price and GetMoney() < rec.price then
        return false
    end
    if rec.costs then
        for _, c in ipairs(rec.costs) do
            if c.currencyID then
                local cur = C_CurrencyInfo.GetCurrencyInfo(c.currencyID)
                if cur and cur.quantity < c.amount then
                    return false
                end
            end
        end
    end
    return true
end

local function buyTick()
    local list = DCR.CartItems()
    local blocked = false
    if list then
        for recordID, entry in pairs(list) do
            if entry.qty > 0 then
                local slot = DCR.MerchantSlotFor(recordID)
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

-- Little flourish: the added decor's icon tumbles into the cart from a random
-- direction. A handful of pooled textures, running only while an add plays.
local fxPool = {}

local function takeFx()
    for _, fx in ipairs(fxPool) do
        if not fx.busy then
            return fx
        end
    end
    if #fxPool >= 6 then
        return nil -- adds faster than the animation? skip the flourish
    end
    local tex = panel:CreateTexture(nil, "OVERLAY", nil, 7)
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
    fx.tex:SetSize(56, 56)
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

-- The catalog variant: the icon takes off at the mouse and arcs over into
-- the cart, wherever the window happens to be.
local function playFly(entry)
    local fx = takeFx()
    if not fx then
        return
    end
    fx.busy = true
    setIcon(fx.tex, entry)
    fx.tex:SetSize(112, 112)
    local scale = dropZone:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local dzx, dzy = dropZone:GetCenter()
    local ox = cx / scale - dzx
    local oy = cy / scale - dzy
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

-- Catalog.lua plays the flourish too when its + button is used with the
-- window open.
function DCR.CartDropFX(entry)
    if panel and panel:IsShown() and entry then
        playFx(entry)
    end
end

-- A 5 or 10 add sends a staggered convoy instead of one icon, capped at
-- what the pool can keep in the air. Each launch reads the mouse fresh, so
-- the convoy trails the cursor if it moves.
function DCR.CartFlyFX(entry, count)
    if not (panel and panel:IsShown() and entry) then
        return
    end
    playFly(entry)
    for i = 2, math.min(count or 1, 5) do
        C_Timer.After(0.1 * (i - 1), function()
            if panel:IsShown() then
                playFly(entry)
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
    else
        dropZone:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        dropIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        dropText:SetPoint("LEFT", dropIcon, "RIGHT", 12, 9)
        dropText:SetPoint("RIGHT", -10, 9)
        dropText:SetText("Drop decor here in edit mode,")
        dropText:SetTextColor(DIM[1], DIM[2], DIM[3])
        catalogLink:Show()
    end
end

local function refresh()
    if not panel then
        return
    end
    local list = DCR.CartItems()
    local order = {}
    if list then
        for _, entry in pairs(list) do
            table.insert(order, entry)
        end
    end
    table.sort(order, function(a, b)
        if a.addedAt ~= b.addedAt then
            return (a.addedAt or 0) < (b.addedAt or 0)
        end
        return a.recordID < b.recordID
    end)
    local total = 0
    local knownCost = 0
    local currencyTotals
    local unpriced = false
    local anyBuyable = false
    for i, entry in ipairs(order) do
        local row = rows[i]
        if not row then
            row = createRow(i)
            rows[i] = row
        end
        row.recordID = entry.recordID
        setIcon(row.icon, entry)
        row.name:SetText(entry.name or ("decor " .. entry.recordID))
        -- No itemID means no vendor to buy it from (yet), shown dimmed.
        if entry.itemID then
            row.name:SetTextColor(1, 1, 1)
        else
            row.name:SetTextColor(DIM[1], DIM[2], DIM[3])
        end
        row.qty:SetText("x" .. entry.qty)
        row.cost:SetText(costText(entry))
        local buyable = DCR.MerchantSlotFor(entry.recordID) ~= nil
        anyBuyable = anyBuyable or buyable
        row.buy:SetShown(buyable)
        row:Show()
        total = total + entry.qty
        local rec = DCR.PriceFor(entry.itemID)
        if rec and rec.price then
            knownCost = knownCost + rec.price * entry.qty
        end
        if rec and rec.costs then
            for _, c in ipairs(rec.costs) do
                currencyTotals = currencyTotals or {}
                local key = c.label or c.icon or "?"
                local t = currencyTotals[key]
                if not t then
                    t = { amount = 0, icon = c.icon, label = c.label }
                    currencyTotals[key] = t
                end
                t.amount = t.amount + c.amount * entry.qty
            end
        end
        if not (rec and (rec.price or rec.costs)) then
            unpriced = true
        end
    end
    for i = #order + 1, #rows do
        rows[i]:Hide()
    end
    listContent:SetHeight(math.max(1, #order * ROW_H))
    -- Prices get learned at vendors, so the sum is marked partial until
    -- every item has been seen at one.
    local parts = {}
    if knownCost > 0 then
        table.insert(parts, DCR.Money(knownCost, 16))
    end
    if currencyTotals then
        local names = {}
        for name in pairs(currencyTotals) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local t = currencyTotals[name]
            if t.icon then
                table.insert(parts, t.amount .. " |T" .. t.icon .. ":16|t")
            else
                table.insert(parts, t.amount .. " " .. name)
            end
        end
    end
    local text = total == 1 and "1 item planned" or (total .. " items planned")
    if #parts > 0 then
        text = text .. ", " .. table.concat(parts, " + ") .. (unpriced and " so far" or "")
    end
    countText:SetText(text)
    lastKnownCost, lastCurrencyTotals = knownCost, currencyTotals
    if buyAllBtn and not buyTicker then
        buyAllBtn:SetShown(anyBuyable)
    end
end
DCR.RefreshCartUI = refresh

local function rowEntry(row)
    local list = DCR.CartItems()
    return list and row.recordID and list[row.recordID]
end

function createRow(i)
    local row = CreateFrame("Frame", nil, listContent)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    row:SetHeight(ROW_H)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(70, 70)
    row.icon:SetPoint("LEFT", 2, 0)

    local remove = flatButton(row, "x", 18)
    remove:SetHeight(18)
    remove:SetPoint("TOPRIGHT", -2, -10)
    remove:SetScript("OnClick", function()
        DCR.RemoveCartEntry(row.recordID)
    end)

    -- shown only while a vendor selling this item is open
    row.buy = flatButton(row, "Buy 1", 56)
    row.buy:SetHeight(20)
    row.buy:SetPoint("BOTTOMRIGHT", -2, 6)
    row.buy:Hide()
    row.buy:SetScript("OnClick", function()
        local slot = DCR.MerchantSlotFor(row.recordID)
        if slot then
            BuyMerchantItem(slot, 1)
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

local function addFromCursor()
    local kind, _, cursorLink = GetCursorInfo()
    if kind ~= "item" then
        return false
    end
    local entry = cursorLink and C_HousingCatalog.GetCatalogEntryInfoByItem(cursorLink)
    if entry then
        addResolved(entry)
        ClearCursor()
    else
        -- Leave the item on the cursor so it can go back to the bags.
        DCR.Print("that item is not housing decor.")
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

local function build()
    -- stayOpen: the cart has to survive entering the house editor.
    panel = DCR.Window("DecorShoppingCart", 400, 620, "Shopping Cart", true)

    -- resizable from the corner, everything inside follows its anchors
    panel:SetResizable(true)
    panel:SetResizeBounds(340, 420)
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
    end)

    dropZone = CreateFrame("Button", nil, panel, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT", 18, -56)
    dropZone:SetPoint("TOPRIGHT", -18, -56)
    dropZone:SetHeight(64)
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

    catalogLink = CreateFrame("Button", nil, dropZone)
    local linkText = catalogLink:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linkText:SetPoint("TOPLEFT")
    linkText:SetText("or add from the catalog")
    linkText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    catalogLink:SetPoint("TOPLEFT", dropText, "BOTTOMLEFT", 0, -3)
    catalogLink:SetSize(linkText:GetStringWidth() + 2, 14)
    catalogLink:SetScript("OnEnter", function()
        linkText:SetTextColor(1, 1, 1)
    end)
    catalogLink:SetScript("OnLeave", function()
        linkText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    end)
    catalogLink:SetScript("OnClick", openCatalog)

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

    -- bordered box holding the scrolling list
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 18, -132)
    box:SetPoint("BOTTOMRIGHT", -18, 46)
    box:SetBackdrop({ bgFile = DCR.WHITE, edgeFile = DCR.WHITE, edgeSize = 1 })
    box:SetBackdropColor(0.08, 0.08, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    listContent = CreateFrame("Frame", nil, scroll)
    listContent:SetSize(1, 1)
    scroll:SetScrollChild(listContent)
    listContent:SetPoint("TOPLEFT")
    -- A scroll child may only hang from one corner, anchoring its right edge
    -- to the scroll frame makes the rows vanish once scrolled. Width follows
    -- the scroll frame by hand instead (also covers window resizing).
    scroll:SetScript("OnSizeChanged", function(_, width)
        listContent:SetWidth(width)
    end)
    listContent:SetWidth(scroll:GetWidth())

    local clearBtn = flatButton(panel, "Clear all", 90)
    clearBtn:SetPoint("BOTTOMRIGHT", -18, 16)

    -- buys one carted item three times a second from the open vendor,
    -- two-click confirm, turns into Stop while running
    buyAllBtn = flatButton(panel, "Buy all", 90)
    buyAllBtn:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
    buyAllBtn:Hide()

    -- While the confirm is armed, a gold line runs clockwise around the
    -- border, showing how long the second click has before it lapses.
    local function armEdge(point, vertical)
        local t = buyAllBtn:CreateTexture(nil, "OVERLAY")
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
    local edgeTop = armEdge("TOPLEFT")
    local edgeRight = armEdge("TOPRIGHT", true)
    local edgeBottom = armEdge("BOTTOMRIGHT")
    local edgeLeft = armEdge("BOTTOMLEFT", true)

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
    local function armSweep(self)
        local p = (GetTime() - self.armedAt) / ARM_SECS
        if not self.armed or p >= 1 then
            self:SetScript("OnUpdate", nil)
            edgeTop:Hide()
            edgeRight:Hide()
            edgeBottom:Hide()
            edgeLeft:Hide()
            return
        end
        local w, h = self:GetWidth(), self:GetHeight()
        local run = p * 2 * (w + h)
        seg(edgeTop, math.min(run, w))
        seg(edgeRight, math.min(run - w, h), true)
        seg(edgeBottom, math.min(run - w - h, w))
        seg(edgeLeft, math.min(run - 2 * w - h, h), true)
    end

    buyAllBtn:SetScript("OnClick", function(self)
        if buyTicker then
            stopBuying("stopped.")
            return
        end
        if not self.armed then
            self.armed = true
            self.armedAt = GetTime()
            self.text:SetText("Really?")
            self:SetScript("OnUpdate", armSweep)
            local units = 0
            local list = DCR.CartItems()
            if list then
                for recordID, entry in pairs(list) do
                    if DCR.MerchantSlotFor(recordID) then
                        units = units + entry.qty
                    end
                end
            end
            DCR.Print(("this vendor covers %d planned buys, click again to get them at 3 a second."):format(units))
            C_Timer.After(ARM_SECS, function()
                if self.armed then
                    self.armed = nil
                    self.text:SetText("Buy all")
                end
            end)
            return
        end
        self.armed = nil
        self.text:SetText("Stop")
        buyTicker = C_Timer.NewTicker(1 / 3, buyTick)
        buyTick()
    end)

    countText = label(panel, "", DIM)
    countText:SetPoint("BOTTOMLEFT", 18, 20)
    countText:SetPoint("RIGHT", buyAllBtn, "LEFT", -8, 0)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)

    -- hovering the total names the currencies behind the icons
    local totalsHover = CreateFrame("Frame", nil, panel)
    totalsHover:SetAllPoints(countText)
    totalsHover:EnableMouse(true)
    totalsHover:SetScript("OnEnter", function(self)
        if not lastCurrencyTotals and (not lastKnownCost or lastKnownCost == 0) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Planned total", GOLD[1], GOLD[2], GOLD[3])
        if lastKnownCost and lastKnownCost > 0 then
            GameTooltip:AddLine(DCR.Money(lastKnownCost), 1, 1, 1)
        end
        if lastCurrencyTotals then
            for _, t in pairs(lastCurrencyTotals) do
                GameTooltip:AddLine(t.amount .. " " .. (t.label or "Unknown currency"), 1, 1, 1)
            end
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
    local function updateParent()
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
    modeWatcher:SetScript("OnEvent", updateParent)
    updateParent()

    -- Selection watching only runs while the window is open. Outside the
    -- house editor the event never fires, so no further gating needed.
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function()
        local info = C_HousingDecor.GetSelectedDecorInfo()
        pending = info and DCR.ResolveDecor(info) or nil
        paintDropZone()
    end)
    panel:SetScript("OnShow", function()
        watcher:RegisterEvent("HOUSING_DECOR_SELECT_RESPONSE")
        local info = C_HousingDecor.GetSelectedDecorInfo()
        pending = info and DCR.ResolveDecor(info) or nil
        paintDropZone()
        -- retries missing itemIDs and price estimates while data is warm
        DCR.RebuildCartLookup()
        refresh()
    end)
    panel:SetScript("OnHide", function()
        watcher:UnregisterEvent("HOUSING_DECOR_SELECT_RESPONSE")
        pending = nil
        paintDropZone()
        stopBuying() -- closing the window should not keep purchases running
    end)

    paintDropZone()
    panel:Hide()
end

function DCR.OpenCart()
    if not panel then
        build()
    end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    panel:Show() -- OnShow refreshes
end

-- Show without toggling, for the catalog + buttons: an add should bring the
-- cart up so the item is seen landing in it.
function DCR.ShowCart()
    if not panel then
        build()
    end
    if not panel:IsShown() then
        panel:Show()
    end
end

-- For Merchant.lua's vendor auto-open. Says whether it actually opened the
-- window, so a cart the player already had up is not closed again on leave.
function DCR.AutoShowCart()
    if panel and panel:IsShown() then
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
