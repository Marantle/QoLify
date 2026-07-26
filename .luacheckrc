std = "lua51"
max_line_length = false

-- Colon-defined module methods rarely touch `self`, and nested frame handlers
-- legitimately take their own `self`.
self = false
ignore = { "431/self", "432/self" }

-- Globals the addon writes to
globals = {
    "QoLify",
    "QoLifyDB",
    "SLASH_QOLIFY1",
    "SlashCmdList",
    -- QoLify_SoundScaper (shares the standalone addon's SavedVariables; the
    -- standalone host claims the classic slash keys)
    "SoundScaperDB",
    "SLASH_QLFSS1",
    "SLASH_QLFSS2",
    "SLASH_SS1",
    "SLASH_SS2",
    -- QoLify_Decor (same pattern, plus the standalone's addon compartment
    -- entry point; the SV global and standalone folder keep the old
    -- DecorSpendwatch name so nobody's data resets)
    "DecorSpendwatchDB",
    "SLASH_QLFDSW1",
    "SLASH_DSW1",
    "SLASH_QLFCART1",
    "SLASH_CART1",
    "DecorSpendwatch_OnAddonCompartmentClick",
    -- The Party Keys QoL feature registers its own popup dialog
    "StaticPopupDialogs",
}

-- WoW API globals we read but never assign to
read_globals = {
    -- Namespaced APIs
    "C_Timer",
    "C_Spell",
    "C_ChatInfo",
    "C_AddOns",
    "C_UI",
    "Settings",
    -- Frame creation
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    -- Font templates
    "GameFontNormal",
    "GameFontNormalSmall",
    -- Unit
    "UnitName",
    "UnitGUID",
    "UnitExists",
    "UnitIsUnit",
    -- Group
    "IsInGroup",
    "IsInRaid",
    "GetRaidRosterInfo",
    "LE_PARTY_CATEGORY_INSTANCE",
    -- Combat / encounter
    "IsEncounterInProgress",
    "InCombatLockdown",
    -- Static popups
    "StaticPopup_Hide",
    "StaticPopup_Show",
    "DELETE_ITEM_CONFIRM_STRING",
    -- Resurrection
    "AcceptResurrect",
    "UnitAffectingCombat",
    -- SoundScaper module
    "C_CVar",
    "GetCVar",
    "GetCVarBool",
    "GetRealmName",
    "GetInstanceInfo",
    "IsInInstance",
    "C_ChallengeMode",
    "issecretvalue",
    "IsLoggedIn",
    -- Misc
    "GetTime",
    "RAID_CLASS_COLORS",
    "CLASS_SORT_ORDER",
    "Minimap",
    "GetCursorPosition",
    "wipe",
    -- Party Keys feature (QoL)
    "C_MythicPlus",
    "C_LFGList",
    "Enum",
    "LibStub",
    "AstralKeys",
    "GetServerTime",
    "GetCurrentRegion",
    "Ambiguate",
    "bit",
    "hooksecurefunc",
    "LFGListFrame",
    "LFGListEntryCreation_Select",
    "LFGListEntryCreation_UpdateValidState",
    "UnitClass",
    "UnitFullName",
    "GetNormalizedRealmName",
    "GetNumGroupMembers",
    -- Decor module
    "GetCoinTextureString",
    "C_Item",
    "C_MerchantFrame",
    "GetMerchantItemLink",
    "GetMerchantNumItems",
    "GetMerchantItemCostInfo",
    "GetMerchantItemCostItem",
    "BuyMerchantItem",
    "GetMoney",
    "IsShiftKeyDown",
    "IsControlKeyDown",
    "MenuUtil",
    "MerchantFrame",
    "MERCHANDISE_ITEMS_PER_PAGE",
    "TooltipDataProcessor",
    "UISpecialFrames",
    "C_HousingCatalog",
    "C_HousingDecor",
    "C_CurrencyInfo",
    "GetCursorInfo",
    "ClearCursor",
    "ScrollUtil",
    "HouseEditorFrame",
    "HousingDashboardFrame",
    "ShowUIPanel",
}
