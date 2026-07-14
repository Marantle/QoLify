local ADDON, QOL = ... -- luacheck: no unused

-- Auto-accepts resurrection offers, but leaves combat res offers (boss
-- encounter in progress, or the player/caster in combat) for the player to
-- decide. Deliberately combat-state only: identifying the res SPELL (brez vs
-- normal) is not possible on 12.x since party cast payloads are secret even
-- out of combat, so an out-of-combat brez auto-accepts like any other res.

local KEY = "autoRes"

local function IsCombatRes(offerer)
    if IsEncounterInProgress() or UnitAffectingCombat("player") then
        return true
    end
    -- Unit functions accept group member names. Unknown offerers resolve false
    return offerer ~= nil and UnitAffectingCombat(offerer)
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, _, offerer)
    if not QOL.IsFeatureEnabled(KEY) then
        return
    end
    if IsCombatRes(offerer) then
        return
    end
    AcceptResurrect()
    StaticPopup_Hide("RESURRECT")
    StaticPopup_Hide("RESURRECT_NO_SICKNESS")
    StaticPopup_Hide("RESURRECT_NO_TIMER")
end)

QOL.RegisterFeature({
    key = KEY,
    title = "Auto-accept resurrection",
    notes = "Accepts resurrections automatically, except combat res.",
    Init = function()
        f:RegisterEvent("RESURRECT_REQUEST")
    end,
})
