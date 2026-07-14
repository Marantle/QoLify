local ADDON, QOL = ... -- luacheck: no unused

-- Adds a "Party Keys" dropdown to the Group Finder listing-creation panel that
-- lists the party's Mythic+ keystones and autofills the listing (dungeon, M+
-- activity, playstyle) from the selected key. Key data is aggregated from
-- whatever sources happen to be available: the player's own key (Blizzard
-- API), LibOpenRaid (ships in Details), LibKeystone (ships in BigWigs and
-- DBM), LibOpenKeystone (ships in EnhanceQoL), overheard Angry Keystones
-- party broadcasts, and AstralKeys. Each source is optional and
-- independently skipped when absent.
--
-- The listing title is out of addon reach entirely (10.2.7 anti-ad measure):
-- SetText and Insert on the box throw "illegal when disabled by security
-- settings", C_LFGList.SetEntryTitle is taint-protected, and the client
-- manages M+ titles itself, prebuilding "+N" when the selected activity
-- matches the player's OWN keystone and clearing it otherwise. So for another
-- player's key the title ends up empty and a chat line states the level to
-- type.

local KEY = "partyKeys"
local DUNGEON_CATEGORY = 2 -- C_LFGList category ID for Dungeons

local PS = Enum.LFGEntryGeneralPlaystyle or {}
local PLAYSTYLE_DEFAULT = PS.FunRelaxed or 2

-- Blizzard's own localized labels (Learning / Relaxed / Competitive / Carry
-- Offered), same globals its playstyle dropdown uses.
local PLAYSTYLE_CHOICES = {}
do
    local fallbacks = { "Learning", "Relaxed", "Competitive", "Carry Offered" }
    local values = { PS.Learning or 1, PS.FunRelaxed or 2, PS.FunSerious or 3, PS.Expert or 4 }
    for i = 1, 4 do
        PLAYSTYLE_CHOICES[i] = {
            text = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. i] or fallbacks[i],
            value = values[i],
        }
    end
end

-- Name helpers ---------------------------------------------------------------

-- shortName matches LibKeystone ("Name", realm only when cross-realm);
-- fullName matches AstralKeys ("Name-NormalizedRealm").
local function UnitNames(unit)
    local name, realm = UnitFullName(unit)
    if not name then
        return
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    local full = realm and (name .. "-" .. realm) or name
    return Ambiguate(full, "none"), full
end

-- AstralKeys stamps entries with a region week number. Older entries are keys
-- from previous resets that no longer exist.
local REGION_WEEK_EPOCH = { 1500390000, 1500505200, 1500447600, 1500505200, 1500505200 }
local function CurrentWeek()
    local epoch = REGION_WEEK_EPOCH[GetCurrentRegion() or 1] or REGION_WEEK_EPOCH[1]
    return math.floor((GetServerTime() - epoch) / 604800)
end

-- Key sources ----------------------------------------------------------------

-- LibKeystone pushes data through a callback, so it needs a tiny cache. The
-- other sources are queried directly at menu-open time.
local libKSToken = {}
local libKSCache = {} -- [playerName] = { level, mapID }
local libKSRegistered = false

local function EnsureLibKeystone()
    local lib = LibStub and LibStub:GetLibrary("LibKeystone", true)
    if lib and not libKSRegistered then
        libKSRegistered = true
        lib.Register(libKSToken, function(level, mapID, _, playerName)
            if not QOL.IsFeatureEnabled(KEY) then
                return
            end
            if level and level > 0 and mapID and mapID > 0 then
                libKSCache[playerName] = { level = level, mapID = mapID }
            end
        end)
    end
    return lib
end

-- Angry Keystones has no library and no readable table (its party-key store
-- is a file-local in its Schedule module), so the only way in is its wire
-- protocol: prefix "AngryKeystones", payload "Schedule|<mapID>:<level>" or
-- "Schedule|0" (no key), sent to PARTY on request and on key changes.
-- Listen-only by choice: we never send on its prefix (no requests, no
-- answers), so AK clients cannot tell we exist. The cache fills from the
-- traffic AK users already exchange among themselves -- answers to their own
-- clients' requests and post-run key-change broadcasts.
local AK_PREFIX = "AngryKeystones"
local akCache = {} -- [fullName] = { level, mapID }
local akRegistered = false

local function EnsureAngryKeystones()
    if akRegistered then
        return
    end
    akRegistered = true
    -- Registration is client-local (no traffic). Without it the client drops
    -- the prefix before CHAT_MSG_ADDON fires. Duplicate registration when AK
    -- itself is installed is fine (returns 1, "duplicate").
    C_ChatInfo.RegisterAddonMessagePrefix(AK_PREFIX)
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
        if prefix ~= AK_PREFIX then
            return
        end
        if not QOL.IsFeatureEnabled(KEY) then
            return
        end
        local mapID, level = message:match("^Schedule|(%d+):(%d+)$")
        if mapID then
            akCache[sender] = { level = tonumber(level), mapID = tonumber(mapID) }
        elseif message == "Schedule|0" then
            akCache[sender] = nil -- the sender no longer holds a key
        end
    end)
end

-- Priority order: the first source with data wins per party member. Each Get
-- returns keyLevel, challengeMapID (or nothing), and label names the source
-- in the dropdown row.
local SOURCES = {
    { -- The player's own keystone, straight from Blizzard.
        label = "own key",
        Get = function(unit)
            if unit ~= "player" then
                return
            end
            return C_MythicPlus.GetOwnedKeystoneLevel(), C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        end,
    },
    { -- LibOpenRaid (Details): group members running Details auto-respond.
        label = "Details",
        Request = function()
            local lib = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
            if lib then
                lib.RequestKeystoneDataFromParty()
            end
        end,
        Get = function(unit)
            local lib = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
            local info = lib and lib.GetKeystoneInfo(unit)
            if info then
                return info.level, info.challengeMapID
            end
        end,
    },
    { -- LibKeystone (ships in BigWigs and DBM): those users auto-respond.
        label = "BigWigs/DBM",
        Request = function()
            local lib = EnsureLibKeystone()
            if lib then
                lib.Request("PARTY")
            end
        end,
        Get = function(_, shortName, fullName)
            local e = libKSCache[shortName] or libKSCache[fullName]
            if e then
                return e.level, e.mapID
            end
        end,
    },
    { -- LibOpenKeystone (ships in EnhanceQoL): reads LibOpenRaid's wire
        -- format too but broadcasts on its own prefix, so its users are
        -- invisible to the Details source above. Names follow the LibOpenRaid
        -- convention (short on same realm, Name-Realm across realms). The lib
        -- stays disabled until EnhanceQoL's key sharing is turned on, in
        -- which case both calls are quiet no-ops.
        label = "EnhanceQoL",
        Request = function()
            local lib = LibStub and LibStub:GetLibrary("LibOpenKeystone-1.0", true)
            if lib then
                lib.RequestKeystoneDataFromParty()
            end
        end,
        Get = function(_, shortName, fullName)
            local lib = LibStub and LibStub:GetLibrary("LibOpenKeystone-1.0", true)
            local data = lib and lib.GetAllKeystonesInfo()
            local e = data and (data[shortName] or data[fullName])
            if e then
                return e.level, e.challengeMapID
            end
        end,
    },
    { -- Angry Keystones: overheard party broadcasts. Listen-only, no Request.
        label = "AngryKeys",
        Get = function(_, _, fullName)
            local e = akCache[fullName]
            if e then
                return e.level, e.mapID
            end
        end,
    },
    { -- AstralKeys: covers party members who are guildies or friends.
        label = "AstralKeys",
        Get = function(_, _, fullName)
            local list = AstralKeys
            if type(list) ~= "table" then
                return
            end
            local week = CurrentWeek()
            for i = 1, #list do
                local e = list[i]
                if type(e) == "table" and e.unit == fullName and (e.week or 0) >= week then
                    return e.key_level, e.dungeon_id
                end
            end
        end,
    },
}

local lastRequest = 0
local function RequestKeys()
    local now = GetTime()
    if now - lastRequest < 3 then
        return
    end
    lastRequest = now
    for _, src in ipairs(SOURCES) do
        if src.Request then
            pcall(src.Request)
        end
    end
end

local function GetPartyKeys()
    local keys = {}
    local members = (IsInGroup() and not IsInRaid()) and GetNumGroupMembers() or 1
    for i = 0, math.min(members - 1, 4) do
        local unit = (i == 0) and "player" or ("party" .. i)
        if UnitExists(unit) then
            local shortName, fullName = UnitNames(unit)
            if shortName then
                for _, src in ipairs(SOURCES) do
                    local ok, level, mapID = pcall(src.Get, unit, shortName, fullName)
                    if ok and level and level > 0 and mapID and mapID > 0 then
                        local _, classFile = UnitClass(unit)
                        keys[#keys + 1] = {
                            unit = unit,
                            name = shortName,
                            classFile = classFile,
                            level = level,
                            mapID = mapID,
                            source = src.label,
                        }
                        break
                    end
                end
            end
        end
    end
    return keys
end

-- Keystone -> Group Finder activity ------------------------------------------

-- Blizzard only exposes the conversion for the player's own key, so other
-- keys are matched by dungeon name against the current season's M+
-- activities. Built once, on first use.
local activityByMap

local function BuildActivityMap()
    activityByMap = {}
    local mapNames = {}
    for _, mapID in ipairs(C_ChallengeMode.GetMapTable() or {}) do
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            mapNames[name] = mapID
        end
    end
    local filters = bit.bor(Enum.LFGListFilter.CurrentSeason, Enum.LFGListFilter.PvE)
    for _, actID in ipairs(C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY, nil, filters) or {}) do
        local info = C_LFGList.GetActivityInfoTable(actID)
        if info and info.isMythicPlusActivity then
            local mapID = mapNames[info.fullName] or mapNames[info.shortName]
            if not mapID and info.fullName then
                for name, id in pairs(mapNames) do
                    if info.fullName:find(name, 1, true) then
                        mapID = id
                        break
                    end
                end
            end
            if mapID and not activityByMap[mapID] then
                activityByMap[mapID] = { activityID = actID, groupID = info.groupFinderActivityGroupID }
            end
        end
    end
end

local function ResolveActivity(key)
    if key.unit == "player" then
        local ok, activityID, groupID = pcall(C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel)
        if ok and activityID then
            return activityID, groupID
        end
    end
    if not activityByMap and not pcall(BuildActivityMap) then
        activityByMap = nil
        return
    end
    local hit = activityByMap and activityByMap[key.mapID]
    if hit then
        return hit.activityID, hit.groupID
    end
end

-- Autofill --------------------------------------------------------------------

local function PlaystyleLabel(value)
    for _, choice in ipairs(PLAYSTYLE_CHOICES) do
        if choice.value == value then
            return choice.text
        end
    end
end

-- No clipboard API exists, so offer the suggested title in a popup editbox,
-- preselected: Ctrl+C there, Ctrl+V into the title. Paste works on
-- authenticated accounts, it is only addon SetText that is locked.
StaticPopupDialogs["QOLIFY_PARTY_KEYS_TITLE"] = {
    text = "Ctrl+C to copy, then paste into the listing title:",
    button1 = "Close",
    hasEditBox = 1,
    editBoxWidth = 260,
    OnShow = function(self)
        local box = (self.GetEditBox and self:GetEditBox()) or self.editBox
        if box and self.data then
            box:SetText(self.data)
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local function ApplyKey(key)
    local panel = LFGListFrame and LFGListFrame.EntryCreation
    if not panel or not panel:IsShown() then
        return
    end
    local activityID, groupID = ResolveActivity(key)
    if not activityID then
        print("|cff99ccffQoLify|r: no Group Finder activity matches that keystone.")
        return
    end

    pcall(LFGListEntryCreation_Select, panel, panel.selectedFilters, DUNGEON_CATEGORY, groupID, activityID)

    -- Not LFGListEntryCreation_OnPlayStyleSelectedInternal: it re-runs the
    -- taint-protected SetEntryTitle, which is blocked (and logged) for addon
    -- callers. Setting the field and revalidating is all it otherwise does.
    local playstyle = QoLifyDB.qol.partyKeysPlaystyle or PLAYSTYLE_DEFAULT
    panel.generalPlaystyle = playstyle
    pcall(LFGListEntryCreation_UpdateValidState, panel)
    if panel.PlayStyleDropdown then
        panel.PlayStyleDropdown:GenerateMenu()
    end

    -- The client fills a "+N" title for the player's own key. For anyone
    -- else's the title stays empty and addons cannot write it, so offer the
    -- suggested title for copy-paste instead.
    if key.unit ~= "player" then
        local dungeon = C_ChallengeMode.GetMapUIInfo(key.mapID)
        print(
            string.format(
                "|cff99ccffQoLify|r: filled listing from %s's +%d %s."
                    .. " Addons can't set the listing title. Copy it from the popup.",
                key.name,
                key.level,
                dungeon or "?"
            )
        )
        local suggested = string.format("+%d %s", key.level, PlaystyleLabel(playstyle) or "")
        StaticPopup_Show("QOLIFY_PARTY_KEYS_TITLE", nil, nil, (suggested:gsub("%s+$", "")))
    end
end

-- Dropdown UI ------------------------------------------------------------------

local dropdown

local function KeyText(key)
    local name = key.name
    local color = key.classFile and RAID_CLASS_COLORS[key.classFile]
    if color and color.colorStr then
        name = "|c" .. color.colorStr .. name .. "|r"
    end
    local dungeon = C_ChallengeMode.GetMapUIInfo(key.mapID)
    local source = key.source and (" |cff888888(" .. key.source .. ")|r") or ""
    return string.format("%s: +%d %s%s", name, key.level, dungeon or ("#" .. key.mapID), source)
end

local function UpdateDropdown(panel)
    if dropdown then
        dropdown:SetShown(
            QOL.IsFeatureEnabled(KEY) and panel.selectedCategory == DUNGEON_CATEGORY and not panel.editMode
        )
    end
end

local function EnsureDropdown(panel)
    if dropdown then
        return
    end
    dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    -- The panel spans the whole PVEFrame, so its own corners sit behind the
    -- frame chrome. Anchor just above the inset instead, in the heading row.
    if panel.Inset then
        dropdown:SetPoint("BOTTOMLEFT", panel.Inset, "TOPLEFT", 2, 2)
    else
        dropdown:SetPoint("TOPLEFT", 19, -6)
    end
    dropdown:SetWidth(100) -- narrow enough to clear the centered heading
    dropdown:SetDefaultText("Party Keys")
    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetTag("MENU_QOLIFY_PARTY_KEYS")
        RequestKeys()
        local keys = GetPartyKeys()
        if #keys == 0 then
            rootDescription:CreateTitle("No party keys found")
        end
        for _, key in ipairs(keys) do
            rootDescription:CreateButton(KeyText(key), ApplyKey, key)
        end
    end)
end

-- Wiring -----------------------------------------------------------------------

local function OnEntryCreationShow(panel)
    if not QOL.IsFeatureEnabled(KEY) then
        if dropdown then
            dropdown:Hide()
        end
        return
    end
    EnsureDropdown(panel)
    UpdateDropdown(panel)
    if dropdown:IsShown() then
        RequestKeys()
    end
end

local hooked = false
local function TryHook()
    if hooked then
        return true
    end
    local panel = LFGListFrame and LFGListFrame.EntryCreation
    if not panel then
        return false
    end
    hooked = true
    -- OnShow is XML-bound, so the script holds a direct function reference
    -- and hooksecurefunc on the global would never fire. Hook the frame
    -- script instead. Select/SetEditMode are called by name from Blizzard
    -- Lua, so hooksecurefunc works for them.
    panel:HookScript("OnShow", OnEntryCreationShow)
    hooksecurefunc("LFGListEntryCreation_Select", UpdateDropdown)
    hooksecurefunc("LFGListEntryCreation_SetEditMode", UpdateDropdown)
    return true
end

QOL.RegisterFeature({
    key = KEY,
    title = "Party Keys in Group Finder",
    notes = "Dropdown on the listing panel that fills the listing from a party member's keystone.",
    Init = function()
        EnsureLibKeystone()
        EnsureAngryKeystones()
        if not TryHook() then
            local f = CreateFrame("Frame")
            f:RegisterEvent("ADDON_LOADED")
            f:SetScript("OnEvent", function(self, _, name)
                if name == "Blizzard_GroupFinder" and TryHook() then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end)
        end
    end,
    extraOptions = {
        {
            type = "choice",
            title = "Default playstyle",
            notes = "Auto-selected when you pick a key.",
            choices = PLAYSTYLE_CHOICES,
            Get = function()
                return QoLifyDB.qol.partyKeysPlaystyle or PLAYSTYLE_DEFAULT
            end,
            Set = function(value)
                QoLifyDB.qol.partyKeysPlaystyle = value
            end,
        },
    },
})
