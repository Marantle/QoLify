local ADDON, DSW = ... -- luacheck: no unused

-- Shared engine for both builds of Decor Spendwatch: the QoLify module
-- (QoLify_DecorSpendwatch.toc + Host_Module.lua) and the standalone addon
-- (DecorSpendwatch.toc + Host_Standalone.lua + Minimap.lua). Settings.lua and
-- Merchant.lua are shared too, only the hosts differ. Both builds use the
-- same DecorSpendwatchDB global, so settings follow the user between them.

DSW.VERSION = "1.1.0"

local GOLD = 10000 -- copper per gold

-- Default vendor tooltip warning. {cap} is swapped for the formatted gold cap.
local DEFAULT_WARNING = "Over your DecorSpendwatch cap of {cap}"
DSW.DEFAULT_WARNING = DEFAULT_WARNING

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
    print("|cff66ccffDecorSpendwatch|r: " .. text)
end
DSW.Print = msg

local function money(copper)
    return GetCoinTextureString(copper or 0)
end
DSW.Money = money

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
DSW.ParseGold = parseGold

-- Getters and setters used by the settings window and the minimap. They guard
-- against being called before init (and keep Merchant.lua inert while the
-- module build is in standby, db nil).
function DSW.GetCap()
    return db and db.capCopper or 0
end

function DSW.SetCap(copper)
    if db then
        db.capCopper = copper or 0
    end
    if DSW.RefreshUI then
        DSW.RefreshUI()
    end
end

function DSW.GetSpent()
    return db and db.spent or 0
end

function DSW.GetOverCount()
    return db and db.overCount or 0
end

function DSW.IsTracking()
    return db and db.trackEnabled and true or false
end

function DSW.SetTracking(on)
    if db then
        db.trackEnabled = not not on
    end
    if DSW.RefreshUI then
        DSW.RefreshUI()
    end
end

function DSW.UsesCustomWarning()
    return db and db.customWarning and true or false
end

function DSW.SetCustomWarning(on)
    if db then
        db.customWarning = not not on
    end
    if DSW.RefreshUI then
        DSW.RefreshUI()
    end
end

function DSW.GetWarningText()
    return (db and db.warningText) or DEFAULT_WARNING
end

function DSW.SetWarningText(text)
    if db then
        text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
        db.warningText = (text and text ~= "") and text or DEFAULT_WARNING
    end
end

-- The line shown on an over-cap decor tooltip. Uses the player's template when
-- custom warnings are on; {cap} is replaced with the formatted gold amount.
function DSW.WarningLine(capCopper)
    local template = DEFAULT_WARNING
    if db and db.customWarning and db.warningText and db.warningText ~= "" then
        template = db.warningText
    end
    return (template:gsub("{cap}", money(capCopper)))
end

function DSW.SpendMessagesOn()
    return db and db.spendMessages and true or false
end

function DSW.SetSpendMessages(on)
    if db then
        db.spendMessages = not not on
    end
    if DSW.RefreshUI then
        DSW.RefreshUI()
    end
end

function DSW.OverCapMessagesOn()
    return db and db.overCapMessages and true or false
end

function DSW.SetOverCapMessages(on)
    if db then
        db.overCapMessages = not not on
    end
    if DSW.RefreshUI then
        DSW.RefreshUI()
    end
end

function DSW.ResetTotals()
    if db then
        db.spent = 0
        db.overCount = 0
    end
    if DSW.RefreshUI then
        DSW.RefreshUI()
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
function DSW.RecordDecorPurchase(copper, name)
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
    if DSW.RefreshUI then
        DSW.RefreshUI()
    end
end

-- The slash command body, shared. The hosts only differ in which SLASH_ key
-- points here (the module must not claim the standalone's key).
function DSW.HandleSlash(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "version" then
        msg("v" .. DSW.VERSION)
    elseif DSW.OpenSettings then
        DSW.OpenSettings()
    end
end

-- DB seed. Called by the host once SavedVariables are ready (and, for the
-- module, standby ruled out). Everything above no-ops until db is assigned
-- here, which is what keeps a standing-by module inert.
function DSW.InitCore()
    DecorSpendwatchDB = DecorSpendwatchDB or {}
    for k, v in pairs(DEFAULTS) do
        if DecorSpendwatchDB[k] == nil then
            DecorSpendwatchDB[k] = v
        end
    end
    db = DecorSpendwatchDB
end
