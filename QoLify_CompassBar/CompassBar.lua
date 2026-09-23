-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local _, CB = ...

-- The engine's front door, shared by the QoLify module build and the
-- standalone build. Each build's host file calls InitCore once the saved
-- variables are in and hands its slash commands to HandleSlash.

CB.VERSION = "0.1.0"

-- the eight directions clockwise from north, the order everything that
-- draws a direction walks
CB.SLOTS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local DEFAULTS = {
    on = true,
    width = 480,
    height = 60,
    span = 800, -- the wheel's size, how far apart the directions sit
    letters = true,
    ticks = true, -- a mark under each letter
    tickColor = { 1, 1, 1, 1 },
    markSize = 24,
    dim = 0.5,
    iconRow = 32, -- the middle of a place's icon, this far under the top edge
    -- what rides the bar out in the world, where places read
    points = {
        quests = true,
        worldQuests = false,
        offers = false,
        pin = true,
        group = true,
        units = true,
        entrances = false,
        flights = false,
        graveyards = false,
        pois = false,
        vignettes = true,
        distance = true,
    },
    -- how far out each kind still shows, in yards, 0 for no limit
    range = {
        quests = 0,
        worldQuests = 0,
        offers = 0,
        pin = 0,
        group = 0,
        units = 0,
        entrances = 0,
        flights = 0,
        graveyards = 0,
        pois = 0,
        vignettes = 0,
    },
    windows = {}, -- per window key: pos, locked
}

-- the number spans the sliders run
CB.LIMITS = {
    width = { 200, 1200 },
    height = { 30, 200 },
    span = { 400, 3000 },
    markSize = { 12, 64 },
    iconRow = { 10, 190 },
    range = { 0, 2000 },
}

local function chat(msg)
    print("|cff5ad2f0CompassBar|r: " .. msg)
end
CB.chat = chat

-- copy every missing key from the defaults, tables included, so a saved
-- file from an older build gains new fields without losing its own
local function fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function CB.InitCore()
    CompassBarDB = CompassBarDB or {}
    CB.db = fill(CompassBarDB, DEFAULTS)
    -- a minimap loan stranded by a crash is paid back before anything asks
    -- for it again
    CB.Facing.ReturnLends()
    CB.Apply()
end

-- every slash command, config edit and event edge ends up here, so the
-- screen always shows what the settings say right now
function CB.Apply()
    CB.Strip.Apply()
    CB.Facing.Want(CB.Strip.Drawing())
    CB.RefreshConfig()
end

function CB.SetOn(on)
    CB.db.on = on and true or false
    chat(CB.db.on and "on" or "off, /cbar on brings it back")
    CB.Apply()
end

local HELP = {
    "/cbar            - open the settings window",
    "/cbar on | off   - draw the bar or not",
    "/cbar lock       - lock or unlock the bar, so it can be dragged",
    "/cbar status     - what the bar is doing and where the facing comes from",
    "/cbar version",
}

function CB.HandleSlash(msg)
    local cmd = (msg or ""):match("^(%S*)"):lower()
    if cmd == "" then
        CB.ToggleConfig()
    elseif cmd == "on" then
        CB.SetOn(true)
    elseif cmd == "off" then
        CB.SetOn(false)
    elseif cmd == "lock" then
        local lock = not CB.GetWindowLock("strip")
        CB.SetWindowLock("strip", lock)
        chat(lock and "locked" or "unlocked, drag it where you want")
        CB.RefreshConfig()
    elseif cmd == "status" then
        chat(CB.Strip.Status())
        chat(CB.Facing.Status())
    elseif cmd == "version" then
        chat("v" .. CB.VERSION)
    else
        chat("commands:")
        for _, line in ipairs(HELP) do
            print("  " .. line)
        end
    end
end
