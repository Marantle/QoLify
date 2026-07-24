local ADDON, QLF = ...

QLF.VERSION = "1.0.0"

-- Public handle for module sub-addons (RegisterModuleOptions etc.)
QoLify = QLF

local DEFAULTS = {
    modules = {}, -- [moduleFolderName] = true when the module is enabled
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        QoLifyDB = QoLifyDB or {}
        for k, v in pairs(DEFAULTS) do
            if QoLifyDB[k] == nil then
                QoLifyDB[k] = type(v) == "table" and {} or v
            end
        end
        -- QoL features registered at file scope initialize here, now that the
        -- DB exists (SavedVariables are not loaded at file scope).
        QLF.QoL_Init()
        QLF.Minimap_Init()
        -- The Decor Spendwatch module became QoLify_Decor in 2.0. Carry the
        -- enable flag over before the prune below drops the old key.
        if QoLifyDB.modules["QoLify_DecorSpendwatch"] and QoLifyDB.modules["QoLify_Decor"] == nil then
            QoLifyDB.modules["QoLify_Decor"] = true
        end
        QLF.Modules_Scan()
        QLF.Modules_PruneStale()
        -- Pages must exist before any module loads and before the settings UI
        -- is ever opened, or they never appear in the category tree.
        QLF.Settings_RegisterModulePages()
        -- Load here (not PLAYER_LOGIN) so modules enabled at login still
        -- receive PLAYER_LOGIN themselves.
        QLF.Modules_LoadEnabled()
    end
end)

SLASH_QOLIFY1 = "/qolify"
SlashCmdList["QOLIFY"] = function(msg)
    if msg == "version" then
        print(ADDON .. " v" .. QLF.VERSION)
    else
        QLF.OpenSettings()
    end
end
