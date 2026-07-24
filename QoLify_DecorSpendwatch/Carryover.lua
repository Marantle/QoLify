local ADDON = ...

-- The .toc does the real work: declaring the old folder's SavedVariables makes
-- WoW load the pre-2.0 WTF file, which is the whole carryover. The catch is
-- load order. This stub loads after the standalone Decor Tools addon, so our
-- possibly stale file would overwrite the global the standalone just filled.
-- Lua files run before SavedVariables load, so grab the live value here and
-- put it back once our own file has loaded over it. Only when the standalone
-- is actually running though: otherwise the global holds the module's mirror,
-- and this stub's file is the one carrying the old data.
local live = DecorSpendwatchDB

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    if live ~= nil and C_AddOns.IsAddOnLoaded("DecorSpendwatch") then
        DecorSpendwatchDB = live
    end
end)
