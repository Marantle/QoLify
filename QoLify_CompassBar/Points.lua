-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local _, CB = ...

-- Things with a place in the world, for the bar: the quest you are
-- tracking, the objectives of tracked quests on this map, your map pin,
-- group members, points of interest and the rares and treasures the map
-- shows. All of it reads plain out in the world, where the bar lives.
-- Gathered twice a second while the bar wants it.

local Points = {}
CB.Points = Points

local list = {}
local ticker

-- a sealed value survives the call and throws on math, so a position is
-- only used once the math went through
local function plain(v)
    return type(v) == "number"
        and not (issecretvalue and issecretvalue(v))
        and pcall(function()
            return v + 0
        end)
end

-- bearing clockwise from north and distance in yards from the player to a
-- spot in the world. UnitPosition's first axis points north and its second
-- west, and the world position of a map point comes back the same way
local function aim(entry, pa, pb)
    local north, west = entry.ta - pa, entry.tb - pb
    entry.bearing, entry.dist = math.atan2(-west, north), math.sqrt(north * north + west * west)
end

local function add(mapID, pa, pb, x, y, entry)
    if not (x and y and plain(x) and plain(y)) then
        return
    end
    local _, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not world then
        return
    end
    entry.ta, entry.tb = world:GetXY()
    aim(entry, pa, pb)
    list[#list + 1] = entry
end

local function playerPos()
    local ok, pa, pb = pcall(UnitPosition, "player")
    if ok and plain(pa) and plain(pb) then
        return pa, pb
    end
end

local function trackedQuest()
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    return id and id > 0 and id or nil
end

-- the next step toward the tracked quest, which may be a road or a portal
-- rather than the objective itself. Always along, whatever the switches say
local function gatherTracked(mapID, pa, pb)
    local tracked = trackedQuest()
    if tracked then
        local x, y = C_QuestLog.GetNextWaypointForMap(tracked, mapID)
        add(mapID, pa, pb, x, y, { kind = "quest", atlas = "Waypoint-MapPin-Tracked", size = 1.2 })
    end
end

local function gatherQuests(mapID, pa, pb)
    local tracked = trackedQuest()
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
        if q.questID ~= tracked then
            add(mapID, pa, pb, q.x, q.y, { kind = "quest", atlas = "QuestNormal" })
        end
    end
end

-- drawn the way the map draws them, the quest type's icon in a ring
local function gatherWorldQuests(mapID, pa, pb)
    for _, q in ipairs(C_TaskQuest.GetQuestsOnMap(mapID) or {}) do
        local tag = C_QuestLog.GetQuestTagInfo(q.questID)
        local atlas = tag and QuestUtil.GetWorldQuestAtlasInfo(q.questID, tag) or "Worldquest-icon"
        add(mapID, pa, pb, q.x, q.y, { kind = "worldquest", atlas = atlas, ring = "UI-QuestPoi-QuestNumber" })
    end
end

-- the quest givers the map shows, which it draws from the quest lines
-- available on it
local function gatherOffers(mapID, pa, pb)
    for _, q in ipairs(C_QuestLine.GetAvailableQuestLines(mapID) or {}) do
        if not q.isHidden then
            add(mapID, pa, pb, q.x, q.y, { kind = "offer", atlas = "QuestDaily" })
        end
    end
end

-- dungeons, raids and delves the map shows the door of
local function gatherEntrances(mapID, pa, pb)
    for _, e in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(mapID) or {}) do
        if e.position and e.atlasName then
            add(mapID, pa, pb, e.position.x, e.position.y, { kind = "entrance", atlas = e.atlasName, label = e.name })
        end
    end
    for _, id in ipairs(C_AreaPoiInfo.GetDelvesForMap(mapID) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
        if info and info.position and info.atlasName then
            add(
                mapID,
                pa,
                pb,
                info.position.x,
                info.position.y,
                { kind = "entrance", atlas = info.atlasName, label = info.name }
            )
        end
    end
end

-- the zone's flight points, the other faction's left out the way the map
-- leaves them out
local FACTION_NODE = { Horde = Enum.FlightPathFaction.Horde, Alliance = Enum.FlightPathFaction.Alliance }

local function gatherFlights(mapID, pa, pb)
    if not C_TaxiMap.ShouldMapShowTaxiNodes(mapID) then
        return
    end
    local mine = FACTION_NODE[UnitFactionGroup("player")]
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
        if node.position and (node.faction == Enum.FlightPathFaction.Neutral or node.faction == mine) then
            add(mapID, pa, pb, node.position.x, node.position.y, {
                kind = "flight",
                atlas = node.atlasName,
                label = node.name,
            })
        end
    end
end

local function gatherGraveyards(mapID, pa, pb)
    for _, g in ipairs(C_DeathInfo.GetGraveyardsForMap(mapID) or {}) do
        if g.position then
            add(mapID, pa, pb, g.position.x, g.position.y, { kind = "graveyard", atlas = "poi-graveyard-neutral" })
        end
    end
    local corpse = C_DeathInfo.GetCorpseMapPosition(mapID)
    if corpse then
        add(mapID, pa, pb, corpse.x, corpse.y, {
            kind = "corpse",
            atlas = "poi-graveyard-neutral",
            color = { 1, 0.4, 0.4, 1 },
            label = "Corpse",
        })
    end
end

-- the target and the focus, a dot in red for something you can attack and
-- green for a friend, straight from their world position
local function gatherUnits(_, pa, pb)
    for _, unit in ipairs({ "target", "focus" }) do
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local ok, ta, tb = pcall(UnitPosition, unit)
            if ok and plain(ta) and plain(tb) then
                local hostile = UnitCanAttack("player", unit)
                local entry = {
                    kind = unit,
                    unit = unit, -- it moves, so its spot is read again each tick
                    texture = CB.Art.Path("disc"),
                    color = hostile and { 1, 0.25, 0.2, 1 } or { 0.3, 0.9, 0.4, 1 },
                    size = 0.6,
                    label = UnitName(unit),
                    ta = ta,
                    tb = tb,
                }
                aim(entry, pa, pb)
                list[#list + 1] = entry
            end
        end
    end
end

local function gatherPin(mapID, pa, pb)
    local pos = C_Map.GetUserWaypointPositionForMap(mapID)
    if pos then
        add(mapID, pa, pb, pos.x, pos.y, { kind = "pin", atlas = "Waypoint-MapPin-Untracked", size = 1.2 })
    end
end

local function gatherGroup(mapID, pa, pb)
    local n = GetNumGroupMembers()
    if n == 0 then
        return
    end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, IsInRaid() and n or n - 1 do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local pos = C_Map.GetPlayerMapPosition(mapID, unit)
            if pos then
                -- a class colored dot. Their raid marker would be nicer,
                -- but the marker index comes back sealed and a texture
                -- path made from it is refused
                local _, class = UnitClass(unit)
                local color = class and RAID_CLASS_COLORS[class]
                add(mapID, pa, pb, pos.x, pos.y, {
                    kind = "group",
                    texture = CB.Art.Path("disc"),
                    color = color and { color.r, color.g, color.b, 1 } or nil,
                    size = 0.6,
                    label = UnitName(unit),
                })
            end
        end
    end
end

local function gatherPOIs(mapID, pa, pb)
    for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
        if info and info.position and info.atlasName then
            add(
                mapID,
                pa,
                pb,
                info.position.x,
                info.position.y,
                { kind = "poi", atlas = info.atlasName, label = info.name }
            )
        end
    end
end

local function gatherVignettes(mapID, pa, pb)
    for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        if info and info.atlasName and (info.onMinimap or info.onWorldMap) then
            local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
            if pos then
                add(mapID, pa, pb, pos.x, pos.y, { kind = "vignette", atlas = info.atlasName, label = info.name })
            end
        end
    end
end

-- the switches, in the order the settings window and the bar's own menu
-- list them: the key in the saved settings, the label, the tip
Points.KINDS = {
    {
        "quests",
        "Tracked quests",
        "The objectives of the quests you track on this map. The quest you super track always rides along.",
    },
    { "worldQuests", "World quests", "The world quests up on this map." },
    { "offers", "Quests on offer", "Quest givers with something for you." },
    { "pin", "Map pin", "Your own pin on the map." },
    { "group", "Group members", "Where the others in your party or raid are, a dot in their class color." },
    { "units", "Target and focus", "A red dot for something you can attack, green for a friend." },
    { "entrances", "Entrances", "Dungeons, raids and delves." },
    { "flights", "Flight points", "The flight masters of the zone." },
    { "graveyards", "Graveyards", "And your corpse while you are dead." },
    { "pois", "Points of interest", "The rest of what the map marks, races and events included." },
    { "vignettes", "Rares and treasures", "What the minimap marks with a star or a chest." },
}

local GATHER = {
    quests = gatherQuests,
    worldQuests = gatherWorldQuests,
    offers = gatherOffers,
    pin = gatherPin,
    group = gatherGroup,
    units = gatherUnits,
    entrances = gatherEntrances,
    flights = gatherFlights,
    graveyards = gatherGraveyards,
    pois = gatherPOIs,
    vignettes = gatherVignettes,
}

-- the whole list again from scratch, or empty wherever the player's own
-- position does not read. Each entry remembers the switch it came in
-- under, which is also where its range lives
local function gather()
    wipe(list)
    local s = CB.Strip.Applied()
    if not s then
        return
    end
    local want = s.points
    local mapID = C_Map.GetBestMapForUnit("player")
    local pa, pb = playerPos()
    if not mapID or not pa then
        return
    end
    gatherTracked(mapID, pa, pb)
    for _, kind in ipairs(Points.KINDS) do
        local key = kind[1]
        if want[key] then
            local from = #list + 1
            GATHER[key](mapID, pa, pb)
            for i = from, #list do
                list[i].src = key
            end
        end
    end
    CB.Strip.PointsChanged()
end

function Points.List()
    return list
end

-- every point aimed again from where the player stands now, and the units
-- from where they stand now. Cheap enough for every tick, which is what
-- keeps the icons gliding when the player moves sideways
function Points.Track()
    local pa, pb = playerPos()
    if not pa then
        return
    end
    for _, entry in ipairs(list) do
        if entry.unit then
            local ok, ta, tb = pcall(UnitPosition, entry.unit)
            if ok and plain(ta) and plain(tb) then
                entry.ta, entry.tb = ta, tb
            end
        end
        aim(entry, pa, pb)
    end
end

function Points.Want(on)
    if on and not ticker then
        gather()
        ticker = C_Timer.NewTicker(0.5, gather)
    elseif not on and ticker then
        ticker:Cancel()
        ticker = nil
        wipe(list)
    end
end
