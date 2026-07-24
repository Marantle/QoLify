local ADDON, DCR = ...

-- Module-build host, listed only in QoLify_Decor.toc. Decides between
-- standby and taking over, claims the module slash keys and registers the
-- QoLify settings rows. The standalone build ships Host_Standalone.lua
-- instead, so neither build ever runs the other's host.

-- Standby: the standalone addon (folder DecorSpendwatch, now titled Decor
-- Tools) is installed and enabled, so it owns the windows, minimap button,
-- slash commands and DecorSpendwatchDB. This module stays completely inert:
-- db is never assigned, which no-ops the hooks in Merchant.lua and Cart.lua,
-- and declaring the SavedVariables in the .toc is what mirrors the data.
-- Remove or disable the standalone addon and this module takes over.
local function StandaloneActive()
    -- Enabled is not enough: an enabled standalone that failed to load (out
    -- of date with "load out of date" off, say) must not put us on standby,
    -- or nobody owns the slash commands. By PLAYER_LOGIN everything that is
    -- going to load has loaded, so the check does not race load order.
    if not C_AddOns.IsAddOnLoaded("DecorSpendwatch") then
        return false
    end
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
        DCR.standby = true
        DCR.Print(
            "the standalone Decor Tools addon is active, so this module is standing by."
                .. " Your settings are mirrored automatically. Remove the standalone addon"
                .. " and this module takes over with the same settings."
        )
        -- Make the standby state visible on the module's settings page.
        QoLify.RegisterModuleOptions(ADDON, {
            {
                type = "button",
                text = "Standing by",
                notes = "The standalone Decor Tools addon is active on this character and owns /dsw and /cart.",
                OnClick = function()
                    DCR.Print("standing by while the standalone Decor Tools addon is active.")
                end,
            },
        })
        return
    end

    DCR.InitCore()

    -- SLASH_QLFDSW, not SLASH_DSW: the keys must not collide with the
    -- standalone's, though the commands themselves are free whenever this
    -- runs (the standalone being active means standby, and standby never
    -- gets here).
    SLASH_QLFDSW1 = "/dsw"
    SlashCmdList["QLFDSW"] = DCR.HandleSlash
    SLASH_QLFCART1 = "/cart"
    SlashCmdList["QLFCART"] = DCR.HandleCartSlash

    -- No module minimap button: the QoLify core button opens settings, and
    -- the slash commands open the windows. (The standalone build keeps its
    -- own button.)
    QoLify.RegisterModuleOptions(ADDON, {
        {
            type = "button",
            text = "/cart for shopping list",
            notes = "Opens the shopping cart (drop decor in while decorating, buy it later).",
            OnClick = function()
                DCR.OpenCart()
            end,
        },
        {
            type = "button",
            text = "/dsw for spendwatcher",
            notes = "Opens the Decor Spendwatch window (gold cap, tracking and chat toggles, totals).",
            OnClick = function()
                DCR.OpenSettings()
            end,
        },
        {
            title = "Chat when a cart item is bought out",
            notes = "Prints a line when the last planned copy of a decor piece is bought.",
            IsEnabled = DCR.CartBuyMessagesOn,
            SetEnabled = DCR.SetCartBuyMessages,
        },
    })
    -- The minimap button's module picker gets a small menu asking which of
    -- the two windows to open. Not registered in standby: the picker then
    -- falls back to the settings page instead.
    QoLify.RegisterModuleLauncher(ADDON, function()
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(UIParent, function(_, root)
                root:CreateTitle("Decor")
                root:CreateButton("Shopping cart", DCR.OpenCart)
                root:CreateButton("Spend tracker", DCR.OpenSettings)
            end)
        else
            DCR.OpenCart()
        end
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
