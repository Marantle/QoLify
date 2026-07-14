local _, SS = ...

-- Contexts, most specific last. `parent` is the context whose settings are used
-- when this one has no override enabled, so a player who only cares about
-- Outdoors/Dungeon/Raid never has to touch the Mythic+ or Raid Boss sections.
SS.CONTEXTS = {
    { key = "world", label = "Outdoors", desc = "Open world, cities, anything outside an instance." },
    { key = "dungeon", label = "Dungeon", desc = "Any 5-player dungeon (normal, heroic, mythic)." },
    {
        key = "mythicplus",
        label = "Mythic+",
        desc = "A keystone dungeon. Falls back to Dungeon unless overridden.",
        parent = "dungeon",
    },
    { key = "raid", label = "Raid", desc = "Inside a raid instance, between pulls." },
    {
        key = "raidEncounter",
        label = "Raid Boss",
        desc = "A raid boss encounter is in progress. Falls back to Raid unless overridden.",
        parent = "raid",
    },
}

SS.CONTEXT_BY_KEY = {}
for _, ctx in ipairs(SS.CONTEXTS) do
    SS.CONTEXT_BY_KEY[ctx.key] = ctx
end

SS.Context = {}
local CTX = SS.Context

local MYTHIC_KEYSTONE_DIFFICULTY = 8

local base = "world" -- what zone we are standing in
local encounter = false -- ENCOUNTER_START seen, no ENCOUNTER_END yet
local current -- last effective context we applied
local debounce

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- The keystone difficulty is set the moment you zone in, before the timer
-- starts, which is what we want: the dungeon is a key run either way.
local function InKeystone()
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    if ok and active == true then
        return true
    end

    local ok2, _, _, difficultyID = pcall(GetInstanceInfo)
    if ok2 and not IsSecret(difficultyID) and difficultyID == MYTHIC_KEYSTONE_DIFFICULTY then
        return true
    end

    return false
end

-- Map/instance APIs return secret values while map restrictions are active, so
-- every read is guarded and we keep the last known zone rather than guessing.
local function DetectBase()
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or IsSecret(inInstance) or IsSecret(instanceType) then
        return base
    end

    if not inInstance then
        return "world"
    end

    if instanceType == "party" then
        return InKeystone() and "mythicplus" or "dungeon"
    elseif instanceType == "raid" then
        return "raid"
    end

    -- Battlegrounds, arenas and scenarios use the Outdoors profile.
    return "world"
end

local function Effective()
    if base == "raid" and encounter then
        return "raidEncounter"
    end
    return base
end

-- Resolve a context to the profile that should actually be applied: an override
-- context with its checkbox off defers to its parent.
function CTX:Resolve(key)
    local db = SS.db
    if not db or not db.profiles then
        return key
    end

    local ctx = SS.CONTEXT_BY_KEY[key]
    while ctx and ctx.parent do
        local profile = db.profiles[ctx.key]
        if profile and profile.override then
            break
        end
        ctx = SS.CONTEXT_BY_KEY[ctx.parent]
    end

    return ctx and ctx.key or key
end

function CTX:Current()
    return current or Effective()
end

function CTX:Apply()
    local key = CTX:Resolve(CTX:Current())
    local profile = SS.db and SS.db.profiles and SS.db.profiles[key]
    SS.Sound:ApplyProfile(profile)
end

-- Settle on an effective context and apply it. Does not touch instance APIs.
-- `base` is only ever refreshed by ReadZone(), which runs on zone events.
local function Settle(force)
    local eff = Effective()
    if eff == current and not force then
        return
    end
    current = eff

    if SS.db and SS.db.enabled then
        CTX:Apply()
    end

    if SS.db and SS.db.announce then
        local ctx = SS.CONTEXT_BY_KEY[eff]
        SS.Print(ctx and ctx.label or eff)
    end

    SS.Window:RefreshStatus()
end

-- The only path that reads instance APIs. Boss pulls no longer route through
-- here, but zoning still can happen mid-encounter (running back after a death),
-- which is why DetectBase() keeps its secret-value guard.
local function ReadZone(force)
    base = DetectBase()
    Settle(force)
end

-- ZONE_CHANGED_NEW_AREA and the challenge-mode events fire several times around
-- a zone-in, so collapse the burst into one read.
local function ReadZoneSoon()
    if debounce then
        debounce:Cancel()
    end
    debounce = C_Timer.NewTimer(0.5, function()
        debounce = nil
        ReadZone()
    end)
end

local f = CreateFrame("Frame")

f:SetScript("OnEvent", function(_, event)
    -- Encounter events only flip a flag: a boss pull does not change the zone,
    -- so there is nothing to re-detect. Applied immediately, with no debounce,
    -- because the pull already happened and a delayed boss profile is audible.
    if event == "ENCOUNTER_START" then
        encounter = true
        Settle()
    elseif event == "ENCOUNTER_END" then
        encounter = false
        Settle()
    elseif event == "PLAYER_ENTERING_WORLD" then
        encounter = false -- zoning always clears any in-progress encounter
        ReadZoneSoon()
    else
        ReadZoneSoon()
    end
end)

function CTX:Start()
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("CHALLENGE_MODE_RESET")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("ENCOUNTER_END")

    encounter = IsEncounterInProgress() and true or false
    ReadZone(true)
end
