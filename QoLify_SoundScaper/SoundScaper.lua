local ADDON, SS = ...

-- Shared bootstrap core for both builds of SoundScaper: the QoLify module
-- (QoLify_SoundScaper.toc + Host_Module.lua) and the standalone addon
-- (SoundScaper.toc + Host_Standalone.lua + SoundScaper_Minimap.lua). The host
-- file owns events and slash key registration. This file holds everything the
-- builds share. Both use the same SoundScaperDB global, so settings follow
-- the user between them.

SS.VERSION = "1.3.0"

local PREFIX = "|cff66ccffSoundScaper|r"

function SS.Print(msg)
    print(PREFIX .. ": " .. msg)
end

local DEFAULTS = {
    enabled = true,
    announce = false,
    win = { x = 400, y = 300, visible = false },
    minimap = { angle = 220 },
}

-- Settings are per character, stored in one account-wide SavedVariables table
-- under chars["Name-Realm"]. A per-character SavedVariables file could not read
-- other characters' data, and the copy tab needs to. SS.db points at the current
-- character's entry from init onwards, and everything outside this file goes
-- through SS.db, never SoundScaperDB.

local function CharKey()
    local name = UnitName("player")
    return name .. "-" .. GetRealmName()
end

local function MergeDefaults(char)
    for k, v in pairs(DEFAULTS) do
        if type(v) == "table" then
            if type(char[k]) ~= "table" then
                char[k] = {}
            end
            for k2, v2 in pairs(v) do
                if char[k][k2] == nil then
                    char[k][k2] = v2
                end
            end
        elseif char[k] == nil then
            char[k] = v
        end
    end
end

-- Seed every context from the player's live sound settings on first run, so
-- installing the addon changes nothing until they actually edit a section.
local function EnsureProfiles(char)
    char.profiles = char.profiles or {}

    local snapshot = SS.Sound:Snapshot()
    for _, ctx in ipairs(SS.CONTEXTS) do
        local p = char.profiles[ctx.key]
        if type(p) ~= "table" then
            p = {}
            char.profiles[ctx.key] = p
        end
        for _, ch in ipairs(SS.CHANNELS) do
            if type(p[ch.key]) ~= "table" then
                p[ch.key] = { volume = snapshot[ch.key].volume, mute = snapshot[ch.key].mute }
            end
        end
        if type(p.numChannels) ~= "number" then
            p.numChannels = snapshot.numChannels
        end
        if p.override == nil then
            p.override = false
        end
    end
end

-- Sorted list of every character in the DB except the current one, for the
-- window's copy tab.
function SS.OtherChars()
    local out = {}
    for key in pairs(SoundScaperDB.chars) do
        if key ~= SS.charKey then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end

-- Replace this character's sound sections with deep copies of another
-- character's. Enabled/announce/window state stay untouched, only the sound
-- settings travel.
function SS.CopyFrom(key)
    local src = SoundScaperDB.chars[key]
    if not src or not src.profiles then
        return false
    end

    for ctxKey, profile in pairs(src.profiles) do
        local copy = {}
        for k, v in pairs(profile) do
            if type(v) == "table" then
                copy[k] = { volume = v.volume, mute = v.mute }
            else
                copy[k] = v -- the scalar fields: override, numChannels
            end
        end
        -- A character saved by a version without channel counts has none to
        -- copy, so this character keeps its own instead of losing the field.
        if copy.numChannels == nil and SS.db.profiles[ctxKey] then
            copy.numChannels = SS.db.profiles[ctxKey].numChannels
        end
        SS.db.profiles[ctxKey] = copy
    end

    if SS.db.enabled then
        SS.Context:Apply()
    end
    return true
end

function SS.SetEnabled(on)
    SS.db.enabled = on and true or false
    if SS.db.enabled then
        SS.Context:Apply()
    end
    -- Only the standalone build lists the minimap file, so the module build
    -- has no SS.Minimap.
    if SS.Minimap then
        SS.Minimap:RefreshLook()
    end
    SS.Window:Refresh()
    SS.Print(SS.db.enabled and "enabled" or "disabled")
end

-- The whole slash command ladder, shared. The hosts only differ in which
-- SLASH_ keys point here (the module must not claim the standalone's keys).
function SS.HandleSlash(msg)
    local cmd = msg and msg:match("^%s*(.-)%s*$"):lower() or ""

    if cmd == "on" then
        SS.SetEnabled(true)
    elseif cmd == "off" then
        SS.SetEnabled(false)
    elseif cmd == "status" or cmd == "s" then
        local live = SS.Context:Current()
        local used = SS.Context:Resolve(live)
        local liveCtx, usedCtx = SS.CONTEXT_BY_KEY[live], SS.CONTEXT_BY_KEY[used]
        print(PREFIX .. " " .. (SS.db.enabled and "|cff66ff66on|r" or "|cffff6666off|r") .. " (" .. SS.charKey .. ")")
        print(
            "  Context: "
                .. (liveCtx and liveCtx.label or live)
                .. (used ~= live and ("  (using " .. (usedCtx and usedCtx.label or used) .. ")") or "")
        )
        print("  " .. SS.Sound:Describe(SS.db.profiles[used]))
    elseif cmd == "announce" then
        SS.db.announce = not SS.db.announce
        SS.Print("context announcements " .. (SS.db.announce and "on" or "off"))
    elseif cmd == "version" or cmd == "v" then
        print(ADDON .. " v" .. SS.VERSION)
    elseif cmd == "help" or cmd == "?" then
        print(PREFIX .. " commands:")
        print("  /ss           - open the settings window")
        print("  /ss status    - show the current context and its sound settings")
        print("  /ss on | off  - enable or disable applying profiles")
        print("  /ss announce  - toggle a chat line on every context change")
        print("  /ss version   - show version")
    else
        SS.Window:Toggle()
    end
end

-- Full init: DB seed, the one-time migration, current character resolution
-- and engine start. Called by the host once SavedVariables are ready (and,
-- for the module, standby ruled out): the standalone calls it at
-- PLAYER_LOGIN, the module from whichever of PLAYER_LOGIN or mid-session
-- ADDON_LOADED arrives.
function SS.InitCore()
    SoundScaperDB = SoundScaperDB or {}
    SoundScaperDB.chars = SoundScaperDB.chars or {}

    local key = CharKey()
    local chars = SoundScaperDB.chars

    -- One-time migration from the pre-per-character shape, where everything
    -- sat at the top level. Whichever character logs in first inherits it.
    if SoundScaperDB.profiles and not chars[key] then
        chars[key] = {
            enabled = SoundScaperDB.enabled,
            announce = SoundScaperDB.announce,
            win = SoundScaperDB.win,
            minimap = SoundScaperDB.minimap,
            profiles = SoundScaperDB.profiles,
        }
    end
    SoundScaperDB.enabled, SoundScaperDB.announce = nil, nil
    SoundScaperDB.win, SoundScaperDB.minimap, SoundScaperDB.profiles = nil, nil, nil

    chars[key] = chars[key] or {}
    SS.charKey = key
    SS.db = chars[key]
    MergeDefaults(SS.db)
    EnsureProfiles(SS.db)

    SS.Context:Start() -- detects the current zone and applies its profile
    SS.Sound:StartSync() -- learns live sound changes into the active profile
    if SS.db.win.visible then
        SS.Window:Show()
    end
end
