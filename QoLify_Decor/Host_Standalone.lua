local ADDON, DCR = ...

-- Standalone-build host, listed only in DecorSpendwatch.toc (which is inert
-- in a QoLify install: WoW only reads the .toc matching the folder name).
-- Plain init plus the classic slash key. The minimap button is standalone
-- only too, from its own Minimap.lua.

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        DCR.InitCore()
    end
end)

SLASH_DSW1 = "/dsw"
SlashCmdList["DSW"] = DCR.HandleSlash
SLASH_CART1 = "/cart"
SlashCmdList["CART"] = DCR.HandleCartSlash

-- The AddOn compartment entry (## AddonCompartmentFunc in the .toc). Lives
-- here rather than in a shared file so the module build never defines the
-- global, which would clobber the standalone's while standing by. Opens the
-- cart, the spend tracker stays on /dsw and the minimap right-click.
function DecorSpendwatch_OnAddonCompartmentClick()
    DCR.OpenCart()
end
