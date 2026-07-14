local ADDON, QOL = ... -- luacheck: no unused

-- Feature registry for the small QoL tweaks. QOL is the core addon table, so
-- features land on the same namespace as everything else. Each feature file
-- calls QOL.RegisterFeature at file scope, which only collects: core files
-- execute before ADDON_LOADED, so SavedVariables are not loaded yet. The
-- core's ADDON_LOADED handler calls QOL.QoL_Init right after the DB merge,
-- which seeds QoLifyDB.qol and runs every feature's Init.
--
-- Init runs once regardless of the feature's flag. Hooks must check
-- QOL.IsFeatureEnabled at runtime so features toggle live, both ways, without
-- a reload. Flags default to off.

QOL.features = {}

-- Option rows rendered in the "Quality of Life" block on the main settings
-- page (any option type Settings.lua supports, checkboxes from the features
-- themselves plus their extraOptions).
QOL.qolOptions = {}

function QOL.IsFeatureEnabled(key)
    return QoLifyDB and QoLifyDB.qol and QoLifyDB.qol[key] == true
end

function QOL.RegisterFeature(feature)
    table.insert(QOL.features, feature)
    table.insert(QOL.qolOptions, {
        title = feature.title,
        notes = feature.notes,
        IsEnabled = function()
            return QOL.IsFeatureEnabled(feature.key)
        end,
        SetEnabled = function(enabled)
            QoLifyDB.qol[feature.key] = enabled or nil
        end,
    })
    -- Extra settings rows beyond the enable checkbox.
    for _, extra in ipairs(feature.extraOptions or {}) do
        table.insert(QOL.qolOptions, extra)
    end
end

function QOL.QoL_Init()
    QoLifyDB.qol = QoLifyDB.qol or {}
    for _, feature in ipairs(QOL.features) do
        if feature.Init then
            feature.Init()
        end
    end
end
