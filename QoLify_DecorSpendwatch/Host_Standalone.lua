local ADDON, DSW = ...

-- Standalone-build host, listed only in DecorSpendwatch.toc (which is inert
-- in a QoLify install: WoW only reads the .toc matching the folder name).
-- Plain init plus the classic slash key. The minimap button is standalone
-- only too, from its own Minimap.lua.

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        DSW.InitCore()
    end
end)

SLASH_DSW1 = "/dsw"
SlashCmdList["DSW"] = DSW.HandleSlash

-- The AddOn compartment entry (## AddonCompartmentFunc in the .toc). Lives
-- here rather than in the shared Settings.lua so the module build never
-- defines the global, which would clobber the standalone's while standing by.
function DecorSpendwatch_OnAddonCompartmentClick()
    DSW.OpenSettings()
end
