local _, SS = ...

-- Audio channels. Each channel has a volume CVar (0.0 to 1.0) and an on/off CVar.
-- The Master channel's "off" switch is Sound_EnableAllSound, which silences the
-- whole game. That is what muting Master means.
SS.CHANNELS = {
    { key = "master", label = "Master", volCVar = "Sound_MasterVolume", enableCVar = "Sound_EnableAllSound" },
    { key = "sfx", label = "Effects", volCVar = "Sound_SFXVolume", enableCVar = "Sound_EnableSFX" },
    { key = "music", label = "Music", volCVar = "Sound_MusicVolume", enableCVar = "Sound_EnableMusic" },
    { key = "ambience", label = "Ambience", volCVar = "Sound_AmbienceVolume", enableCVar = "Sound_EnableAmbience" },
    { key = "dialog", label = "Dialog", volCVar = "Sound_DialogVolume", enableCVar = "Sound_EnableDialog" },
}

-- The game's channel count ("Sound Channels" in the Blizzard panel): how many
-- sounds can play at the same time. One integer per profile. The range matches
-- Blizzard's own slider, defined as 20 to 128 step 1 in the client's
-- Blizzard_SettingsDefinitions_Shared/Audio.lua.
SS.NUM_CHANNELS = { cvar = "Sound_NumChannels", min = 20, max = 128, step = 1, default = 64 }

SS.Sound = {}
local Sound = SS.Sound

-- True while ApplyProfile is writing CVars. Each write fires CVAR_UPDATE
-- synchronously, and without this flag the sync listener below would learn the
-- addon's own writes back into the profile it just read them from.
local applying = false

local function Clamp100(v)
    v = tonumber(v) or 100
    if v < 0 then
        return 0
    end
    if v > 100 then
        return 100
    end
    return v
end

local function ClampNumChannels(v)
    local nc = SS.NUM_CHANNELS
    v = math.floor(tonumber(v) or nc.default)
    if v < nc.min then
        return nc.min
    end
    if v > nc.max then
        return nc.max
    end
    return v
end

-- Read the game's live sound settings into a profile table.
function Sound:Snapshot()
    local profile = {}
    for _, ch in ipairs(SS.CHANNELS) do
        local vol = tonumber(GetCVar(ch.volCVar)) or 1
        profile[ch.key] = {
            volume = math.floor(vol * 100 + 0.5),
            mute = not GetCVarBool(ch.enableCVar),
        }
    end
    profile.numChannels = ClampNumChannels(GetCVar(SS.NUM_CHANNELS.cvar))
    return profile
end

-- Write a profile to the game's sound CVars.
--
-- Sound CVars are not protected. This is called from ENCOUNTER_START, meaning in
-- combat inside a raid, and the writes go through (verified on a Naxxramas boss
-- pull), so there is no pcall or combat deferral here. If Blizzard ever protects
-- these CVars the failure will be a visible Lua error, not a silent one.
function Sound:ApplyProfile(profile)
    if not profile then
        return
    end

    applying = true
    for _, ch in ipairs(SS.CHANNELS) do
        local c = profile[ch.key]
        if c then
            C_CVar.SetCVar(ch.volCVar, tostring(Clamp100(c.volume) / 100))
            C_CVar.SetCVar(ch.enableCVar, c.mute and "0" or "1")
        end
    end
    if profile.numChannels then
        C_CVar.SetCVar(SS.NUM_CHANNELS.cvar, tostring(ClampNumChannels(profile.numChannels)))
    end
    applying = false
end

-- Live changes flow back in. A sound CVar written by anything other than
-- ApplyProfile (the Blizzard options panel, a macro, another addon) is learned
-- into the profile currently in force, so the game's own audio settings and
-- the addon window edit the same profile. Learning targets the resolved
-- context, which is what is audibly playing: with the Mythic+ override off, a
-- change made during a key edits the Dungeon profile, same as the window.
-- Nothing is re-applied here, the CVar already holds the new value, so there
-- is no feedback loop.
local WATCHED = {}
for _, ch in ipairs(SS.CHANNELS) do
    WATCHED[ch.volCVar:lower()] = { channel = ch.key, isVolume = true }
    WATCHED[ch.enableCVar:lower()] = { channel = ch.key, isVolume = false }
end
WATCHED[string.lower(SS.NUM_CHANNELS.cvar)] = { numChannels = true }

function Sound:StartSync()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CVAR_UPDATE")
    f:SetScript("OnEvent", function(_, _, name, value)
        if applying then
            return
        end
        if not (SS.db and SS.db.enabled and SS.db.profiles) then
            return
        end

        local w = name and WATCHED[name:lower()]
        if not w then
            return
        end

        local key = SS.Context:Resolve(SS.Context:Current())
        local profile = SS.db.profiles[key]
        if not profile then
            return
        end

        if w.numChannels then
            profile.numChannels = ClampNumChannels(value)
        else
            local c = profile[w.channel]
            if not c then
                return
            end
            if w.isVolume then
                c.volume = Clamp100(math.floor((tonumber(value) or 1) * 100 + 0.5))
            else
                c.mute = value == "0"
            end
        end

        SS.Window:OnLiveLearn(key)
    end)
end

function Sound:Describe(profile)
    if not profile then
        return "-"
    end
    local parts = {}
    for _, ch in ipairs(SS.CHANNELS) do
        local c = profile[ch.key]
        if c then
            parts[#parts + 1] = ch.label .. " " .. (c.mute and "muted" or (Clamp100(c.volume) .. "%"))
        end
    end
    if profile.numChannels then
        parts[#parts + 1] = profile.numChannels .. " channels"
    end
    return table.concat(parts, ", ")
end
