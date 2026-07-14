local ADDON, SS = ...

-- Module-build host, listed only in QoLify_SoundScaper.toc. Decides between
-- standby and taking over, claims the module slash keys and registers the
-- QoLify settings rows. The standalone build ships Host_Standalone.lua
-- instead, so neither build ever runs the other's host.

-- Standby: the standalone SoundScaper is installed and enabled, so it owns the
-- window, minimap button, slash commands and SoundScaperDB. This module stays
-- completely inert (declaring the SavedVariables in the .toc is what mirrors
-- the data). Remove or disable the standalone addon and this module takes over.
local function StandaloneActive()
    -- Check for THIS character: the no-character form reports "enabled on
    -- some character", which would leave both addons inert on characters
    -- where the standalone is unchecked.
    local char = UnitName("player")
    local state = char and C_AddOns.GetAddOnEnableState("SoundScaper", char)
        or C_AddOns.GetAddOnEnableState("SoundScaper")
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
        SS.standby = true
        SS.Print(
            "standalone SoundScaper is active, so this module is standing by."
                .. " Your settings are mirrored automatically. Remove the standalone addon"
                .. " and this module takes over with the same settings."
        )
        -- Make the standby state visible on the module's settings page.
        QoLify.RegisterModuleOptions(ADDON, {
            {
                type = "button",
                text = "Standing by",
                notes = "The standalone SoundScaper addon is active on this character and owns /ss.",
                OnClick = function()
                    SS.Print("standing by while the standalone SoundScaper addon is active.")
                end,
            },
        })
        return
    end

    -- SLASH_QLFSS, not SLASH_SS: the key must not collide with the
    -- standalone's, though /ss itself is free whenever this runs (the
    -- standalone being active means standby, and standby never gets here).
    SLASH_QLFSS1 = "/ss"
    SLASH_QLFSS2 = "/soundscaper"
    SlashCmdList["QLFSS"] = SS.HandleSlash

    SS.InitCore()

    -- No module minimap button: the QoLify core button opens settings, and
    -- /ss opens the window. (The standalone build keeps its own button.)
    QoLify.RegisterModuleOptions(ADDON, {
        {
            type = "button",
            text = "Use /ss to open",
            notes = "Opens the SoundScaper window (also on the minimap button).",
            OnClick = function()
                SS.Window:Toggle()
            end,
        },
    })
    -- The minimap button's module picker opens the window too. Not registered
    -- in standby: the picker then falls back to the settings page instead.
    QoLify.RegisterModuleLauncher(ADDON, function()
        SS.Window:Toggle()
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
