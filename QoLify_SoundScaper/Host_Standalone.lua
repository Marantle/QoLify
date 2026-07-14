local _, SS = ...

-- Standalone-build host, listed only in SoundScaper.toc (which is inert in a
-- QoLify install: WoW only reads the .toc matching the folder name). Plain
-- login init plus the classic slash keys. The minimap button is standalone
-- only too, built here.

local f = CreateFrame("Frame")
-- PLAYER_LOGIN is enough for a standalone addon: SavedVariables are loaded
-- before it fires, and there is no mid-session enable path (LoadOnDemand is
-- a module-build concern).
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    SS.InitCore()
    SS.Minimap:Build()
end)

SLASH_SS1 = "/ss"
SLASH_SS2 = "/soundscaper"
SlashCmdList["SS"] = SS.HandleSlash
