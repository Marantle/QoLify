local ADDON, CB = ...

-- Module-build host, listed only in QoLify_CompassBar.toc. Decides between
-- standby and taking over, claims the module slash keys and registers the
-- QoLify settings rows. The standalone build ships Host_Standalone.lua
-- instead, so neither build ever runs the other's host.

-- Standby: the standalone CompassBar is installed and enabled, so it owns
-- the bar, the slash commands and CompassBarDB. This module stays
-- completely inert (declaring the SavedVariables in the .toc is what
-- mirrors the data). Remove or disable the standalone addon and this module
-- takes over.
local function StandaloneActive()
    -- Check for THIS character: the no-character form reports "enabled on
    -- some character", which would leave both addons inert on characters
    -- where the standalone is unchecked.
    local char = UnitName("player")
    local state = char and C_AddOns.GetAddOnEnableState("CompassBar", char)
        or C_AddOns.GetAddOnEnableState("CompassBar")
    return (state or 0) > 0
end

-- The standby decision needs the current character (see StandaloneActive),
-- which is not reliably known at ADDON_LOADED during the login load screen,
-- so everything waits for PLAYER_LOGIN, or runs immediately when the module
-- is enabled mid-session from the QoLify settings page.
local initialized = false

local function TakeOverOrStandby()
    if initialized then
        return
    end
    initialized = true
    if StandaloneActive() then
        CB.chat(
            "standalone CompassBar is active, so this module is standing by."
                .. " Your settings are mirrored automatically. Remove the standalone addon"
                .. " and this module takes over with the same settings."
        )
        QoLify.RegisterModuleOptions(ADDON, {
            {
                type = "button",
                text = "Standing by",
                notes = "The standalone CompassBar addon is active on this character and owns /cbar.",
                OnClick = function()
                    CB.chat("standing by while the standalone CompassBar addon is active.")
                end,
            },
        })
        return
    end

    -- SLASH_QLFCBAR, not SLASH_CBAR: the key must not collide with the
    -- standalone's, though /cbar itself is free whenever this runs
    SLASH_QLFCBAR1 = "/cbar"
    SLASH_QLFCBAR2 = "/compassbar"
    SlashCmdList["QLFCBAR"] = CB.HandleSlash

    CB.InitCore()

    QoLify.RegisterModuleOptions(ADDON, {
        {
            title = "Draw the bar",
            notes = "The bar across the screen. /cbar on and off do the same.",
            IsEnabled = function()
                return CB.db.on
            end,
            SetEnabled = CB.SetOn,
        },
        {
            type = "button",
            text = "Open the settings",
            notes = "Size, spread, what rides the bar out in the world. /cbar opens it too.",
            OnClick = CB.ToggleConfig,
        },
    })
    -- the minimap button's module picker opens the settings window
    QoLify.RegisterModuleLauncher(ADDON, CB.ToggleConfig)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
-- Registered from file scope, not from ADDON_LOADED: when the core
-- LoadAddOn()s this module during its own ADDON_LOADED at login, the module's
-- ADDON_LOADED event does not reliably arrive (observed 120007). PLAYER_LOGIN
-- always fires after every load (including reloads) with SavedVariables
-- ready, so it is the login-time hook; ADDON_LOADED covers mid-session
-- enabling, when PLAYER_LOGIN has already come and gone.
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        if IsLoggedIn() then
            TakeOverOrStandby() -- enabled mid-session from the settings page
        end
    elseif event == "PLAYER_LOGIN" then
        TakeOverOrStandby()
    end
end)
