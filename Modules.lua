local ADDON, QLF = ...

-- Modules are separate LoadOnDemand addons flagged with "## X-QoLify-Module: 1"
-- in their .toc. None of a module's code is loaded until it is enabled here.

QLF.moduleList = {}

-- Modules call this after load to surface per-feature checkboxes inline in the
-- settings panel, indented under their module row.
-- options: array of { title, notes, IsEnabled = fn() -> bool, SetEnabled = fn(bool) }
QLF.moduleOptions = {}

function QLF.RegisterModuleOptions(name, options)
    QLF.moduleOptions[name] = options
end

-- A module with its own window registers how to open it here. The minimap
-- button's module picker calls it. Modules without one (or standing by) fall
-- back to their settings page.
QLF.moduleLaunchers = {}

function QLF.RegisterModuleLauncher(name, fn)
    QLF.moduleLaunchers[name] = fn
end

local function Chat(msg)
    print("|cff99ccff" .. ADDON .. "|r: " .. msg)
end

function QLF.Modules_Scan()
    wipe(QLF.moduleList)
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if C_AddOns.GetAddOnMetadata(name, "X-QoLify-Module") then
            table.insert(QLF.moduleList, {
                name = name,
                title = C_AddOns.GetAddOnMetadata(name, "Title") or name,
                notes = C_AddOns.GetAddOnMetadata(name, "Notes") or "",
            })
        end
    end
    table.sort(QLF.moduleList, function(a, b)
        return a.title < b.title
    end)
end

function QLF.Modules_IsEnabled(name)
    return QoLifyDB.modules[name] == true
end

-- Drop enable flags for module folders that no longer exist (renamed or
-- removed modules would otherwise leave dead keys in SavedVariables forever).
-- Run after Modules_Scan. A module that is merely uninstalled loses its flag
-- too and must be re-enabled if reinstalled.
function QLF.Modules_PruneStale()
    local known = {}
    for _, m in ipairs(QLF.moduleList) do
        known[m.name] = true
    end
    for name in pairs(QoLifyDB.modules) do
        if not known[name] then
            QoLifyDB.modules[name] = nil
        end
    end
end

function QLF.Modules_Load(name)
    -- A module that forks a standalone addon declares the shared SavedVariables
    -- global via "## X-QoLify-SharedSV:". Loading the module assigns that
    -- global from the module's own (possibly stale) SavedVariables file, so
    -- when the standalone addon already populated it this session, restore the
    -- live value afterwards.
    local sharedSV = C_AddOns.GetAddOnMetadata(name, "X-QoLify-SharedSV")
    local live = sharedSV and _G[sharedSV] or nil

    -- LoadAddOn fails on addons unchecked in the character addon list
    C_AddOns.EnableAddOn(name)
    local loaded, reason = C_AddOns.LoadAddOn(name)
    if not loaded then
        Chat("failed to load " .. name .. " (" .. tostring(reason) .. ")")
    end

    if live ~= nil then
        _G[sharedSV] = live
    end
    return loaded and true or false
end

-- WoW's own AddOn list is the outer switch: a module the user unticked there
-- (for this character) is not loaded at login, and settings show that state.
-- The explicit enable click still works. Modules_Load re-enables the addon
-- in the list, which is the user's deliberate override.
function QLF.Modules_IsAllowed(name)
    local char = UnitName("player")
    local state = char and C_AddOns.GetAddOnEnableState(name, char) or C_AddOns.GetAddOnEnableState(name)
    return (state or 0) > 0
end

function QLF.Modules_LoadEnabled()
    for _, m in ipairs(QLF.moduleList) do
        if QoLifyDB.modules[m.name] and QLF.Modules_IsAllowed(m.name) then
            QLF.Modules_Load(m.name)
        end
    end
end

-- Returns whether the module is active right now. Disabling a loaded module
-- only takes effect after a UI reload (loaded code cannot be unloaded).
function QLF.Modules_SetEnabled(name, enabled)
    QoLifyDB.modules[name] = enabled and true or nil
    if enabled then
        return QLF.Modules_Load(name)
    end
    return C_AddOns.IsAddOnLoaded(name)
end
