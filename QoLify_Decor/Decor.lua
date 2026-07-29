local ADDON, DCR = ... -- luacheck: no unused

-- Shared engine for both builds of the decor tools: the QoLify module
-- (QoLify_Decor.toc + Host_Module.lua) and the standalone addon
-- (DecorSpendwatch.toc + Host_Standalone.lua + Minimap.lua). Everything but
-- the hosts and the minimap button is shared. The standalone folder keeps its
-- old DecorSpendwatch name because the folder name keys the SavedVariables
-- file in WTF, and both builds use the same DecorSpendwatchDB global, so
-- settings follow the user between them.

DCR.VERSION = "2.2.0"

local GOLD = 10000 -- copper per gold

-- Default vendor tooltip warning. {cap} is swapped for the formatted gold cap.
local DEFAULT_WARNING = "Over your decor cap of {cap}"
DCR.DEFAULT_WARNING = DEFAULT_WARNING

local DEFAULTS = {
    capCopper = 0, -- per-item gold limit, 0 means no cap set yet
    spent = 0, -- running total spent on decor items
    overCount = 0, -- times an over-cap decor item was bought
    trackEnabled = true, -- record decor spending
    minimapAngle = 220, -- where the standalone build's minimap coin sits, in degrees
    customWarning = false, -- use the player's own tooltip warning text
    warningText = DEFAULT_WARNING, -- the player's custom warning template
    spendMessages = true, -- print the running decor-spend summary to chat
    overCapMessages = true, -- print the over-cap warning to chat per purchase
}

local db

local function msg(text)
    print("|cff66ccffDecor Tools|r: " .. text)
end
DCR.Print = msg

local function money(copper, iconHeight)
    return GetCoinTextureString(copper or 0, iconHeight)
end
DCR.Money = money

-- Turn "50000", "5g", "50k" or "1.5m" into copper. Returns nil if it can't be read.
local function parseGold(s)
    if not s then
        return nil
    end
    s = s:lower():gsub("%s+", "")
    local mult = 1
    if s:find("k$") then
        mult = 1e3
        s = s:gsub("k$", "")
    elseif s:find("m$") then
        mult = 1e6
        s = s:gsub("m$", "")
    elseif s:find("g$") then
        s = s:gsub("g$", "") -- plain gold, the trailing g is just decoration
    end
    local n = tonumber(s)
    if not n then
        return nil
    end
    return math.floor(n * mult * GOLD)
end
DCR.ParseGold = parseGold

-- Getters and setters used by the settings window and the minimap. They guard
-- against being called before init (and keep Merchant.lua inert while the
-- module build is in standby, db nil).
function DCR.GetCap()
    return db and db.capCopper or 0
end

function DCR.SetCap(copper)
    if db then
        db.capCopper = copper or 0
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

function DCR.GetSpent()
    return db and db.spent or 0
end

function DCR.GetOverCount()
    return db and db.overCount or 0
end

function DCR.IsTracking()
    return db and db.trackEnabled and true or false
end

function DCR.SetTracking(on)
    if db then
        db.trackEnabled = not not on
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

function DCR.UsesCustomWarning()
    return db and db.customWarning and true or false
end

function DCR.SetCustomWarning(on)
    if db then
        db.customWarning = not not on
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

function DCR.GetWarningText()
    return (db and db.warningText) or DEFAULT_WARNING
end

function DCR.SetWarningText(text)
    if db then
        text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
        db.warningText = (text and text ~= "") and text or DEFAULT_WARNING
    end
end

-- The line shown on an over-cap decor tooltip. Uses the player's template when
-- custom warnings are on; {cap} is replaced with the formatted gold amount.
function DCR.WarningLine(capCopper)
    local template = DEFAULT_WARNING
    if db and db.customWarning and db.warningText and db.warningText ~= "" then
        template = db.warningText
    end
    return (template:gsub("{cap}", money(capCopper)))
end

function DCR.SpendMessagesOn()
    return db and db.spendMessages and true or false
end

function DCR.SetSpendMessages(on)
    if db then
        db.spendMessages = not not on
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

function DCR.OverCapMessagesOn()
    return db and db.overCapMessages and true or false
end

function DCR.SetOverCapMessages(on)
    if db then
        db.overCapMessages = not not on
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

function DCR.ResetTotals()
    if db then
        db.spent = 0
        db.overCount = 0
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

-- Buying several decor items in a row should not spam chat. Each purchase resets a
-- short timer, and the spend summary prints once you stop buying.
local batchCopper, batchCount, batchTimer

local function flushBatch()
    batchTimer = nil
    if not batchCount or batchCount == 0 then
        return
    end
    if not (db and db.spendMessages) then
        batchCopper, batchCount = 0, 0
        return
    end
    if batchCount == 1 then
        msg(("spent %s on decor. Total decor spend: %s."):format(money(batchCopper), money(db.spent)))
    else
        msg(
            ("spent %s on %d decor items. Total decor spend: %s."):format(
                money(batchCopper),
                batchCount,
                money(db.spent)
            )
        )
    end
    batchCopper, batchCount = 0, 0
end

-- Called from Merchant.lua when a housing decor item is bought. name is the item
-- link so it prints as the coloured, clickable name.
function DCR.RecordDecorPurchase(copper, name)
    if not db or not copper or copper <= 0 then
        return
    end
    -- An over-cap purchase is a cap breach, counted and warned no matter what.
    if db.capCopper > 0 and copper > db.capCopper then
        db.overCount = db.overCount + 1
        if db.overCapMessages then
            msg(
                ("|cffff4040OVER CAP|r. %s cost %s, past your %s per-item limit."):format(
                    name or "that item",
                    money(copper),
                    money(db.capCopper)
                )
            )
        end
    end
    -- The running total only moves when spend tracking is on.
    if db.trackEnabled then
        db.spent = db.spent + copper
        batchCopper = (batchCopper or 0) + copper
        batchCount = (batchCount or 0) + 1
        if batchTimer then
            batchTimer:Cancel()
        end
        batchTimer = C_Timer.NewTimer(10, flushBatch)
    end
    if DCR.RefreshUI then
        DCR.RefreshUI()
    end
end

-- The slash command bodies, shared. The hosts only differ in which SLASH_
-- keys point here (the module must not claim the standalone's keys). /dsw is
-- the spend tracker, /cart is the shopping cart.
function DCR.HandleSlash(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "version" then
        msg("v" .. DCR.VERSION)
    elseif DCR.OpenSettings then
        DCR.OpenSettings()
    end
end

function DCR.HandleCartSlash(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "version" then
        msg("v" .. DCR.VERSION)
    elseif DCR.OpenCart then
        DCR.OpenCart()
    end
end

-- The shopping cart's slice of the DB. Nil until InitCore, which keeps
-- Cart.lua inert in standby the same way db does for the tracker.
function DCR.CartDB()
    return db and db.cart
end

-- Saved window positions, keyed by window name. Nil until InitCore.
function DCR.WindowDB()
    return db and db.windows
end

-- DB seed. Called by the host once SavedVariables are ready (and, for the
-- module, standby ruled out). Everything above no-ops until db is assigned
-- here, which is what keeps a standing-by module inert.
function DCR.InitCore()
    DecorSpendwatchDB = DecorSpendwatchDB or {}
    for k, v in pairs(DEFAULTS) do
        if DecorSpendwatchDB[k] == nil then
            DecorSpendwatchDB[k] = v
        end
    end
    -- The shallow merge above cannot seed nested tables, so the cart gets
    -- its keys by hand.
    local cart = DecorSpendwatchDB.cart or {}
    DecorSpendwatchDB.cart = cart
    cart.items = cart.items or {}
    cart.prices = cart.prices or {} -- [itemID] = { price, costs }, learned at vendors
    cart.pending = cart.pending or {} -- [itemID] = n, AH buys ticked off, delivery not landed yet
    if cart.buyMessages == nil then
        cart.buyMessages = true
    end
    DecorSpendwatchDB.windows = DecorSpendwatchDB.windows or {}
    db = DecorSpendwatchDB
    -- Arms the vendor tooltip right away, no need to open the cart first.
    DCR.RebuildCartLookup()
    DCR.WarmCatalog()
    DCR.CatalogInit()
end
