local ADDON, DSW = ...

-- Module-build host, listed only in QoLify_DecorSpendwatch.toc. Decides
-- between standby and taking over, claims the module slash key and registers
-- the QoLify settings rows. The standalone build ships Host_Standalone.lua
-- instead, so neither build ever runs the other's host.

-- Standby: the standalone DecorSpendwatch is installed and enabled, so it owns
-- the settings window, minimap button, slash command and DecorSpendwatchDB.
-- This module stays completely inert: db is never assigned, which no-ops the
-- merchant hooks in Merchant.lua, and declaring the SavedVariables in the .toc
-- is what mirrors the data. Remove or disable the standalone addon and this
-- module takes over.
local function StandaloneActive()
    -- Check for THIS character: the no-character form reports "enabled on
    -- some character", which would leave both addons inert on characters
    -- where the standalone is unchecked.
    local char = UnitName("player")
    local state = char and C_AddOns.GetAddOnEnableState("DecorSpendwatch", char)
        or C_AddOns.GetAddOnEnableState("DecorSpendwatch")
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
        DSW.standby = true
        DSW.Print(
            "standalone DecorSpendwatch is active, so this module is standing by."
                .. " Your settings are mirrored automatically. Remove the standalone addon"
                .. " and this module takes over with the same settings."
        )
        -- Make the standby state visible on the module's settings page.
        QoLify.RegisterModuleOptions(ADDON, {
            {
                type = "button",
                text = "Standing by",
                notes = "The standalone DecorSpendwatch addon is active on this character and owns /dsw.",
                OnClick = function()
                    DSW.Print("standing by while the standalone DecorSpendwatch addon is active.")
                end,
            },
        })
        return
    end

    DSW.InitCore()

    -- SLASH_QLFDSW, not SLASH_DSW: the key must not collide with the
    -- standalone's, though /dsw itself is free whenever this runs (the
    -- standalone being active means standby, and standby never gets here).
    SLASH_QLFDSW1 = "/dsw"
    SlashCmdList["QLFDSW"] = DSW.HandleSlash

    -- No module minimap button: the QoLify core button opens settings, and
    -- /dsw opens the window. (The standalone build keeps its own button.)
    QoLify.RegisterModuleOptions(ADDON, {
        {
            type = "button",
            text = "Use /dsw to open",
            notes = "Opens the Decor Spendwatch window (gold cap, tracking and chat toggles, totals).",
            OnClick = function()
                DSW.OpenSettings()
            end,
        },
    })
    -- The minimap button's module picker opens the window too. Not registered
    -- in standby: the picker then falls back to the settings page instead.
    QoLify.RegisterModuleLauncher(ADDON, function()
        DSW.OpenSettings()
    end)
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
