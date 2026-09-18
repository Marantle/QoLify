local _, CB = ...

-- Standalone-build host, listed only in CompassBar.toc (which is inert in a
-- QoLify install: WoW only reads the .toc matching the folder name). Plain
-- login init plus the classic slash keys and the addon compartment entry.

local f = CreateFrame("Frame")
-- PLAYER_LOGIN is enough for a standalone addon: SavedVariables are loaded
-- before it fires, and there is no mid-session enable path (LoadOnDemand is
-- a module-build concern).
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    CB.InitCore()
end)

SLASH_CBAR1 = "/cbar"
SLASH_CBAR2 = "/compassbar"
SlashCmdList["CBAR"] = CB.HandleSlash

function CompassBar_OnCompartment()
    CB.ToggleConfig()
end
