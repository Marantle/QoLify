local _, DCR = ...

-- Puts a small + button on decor entries in the catalog lists, so pieces can
-- go straight onto the shopping list while browsing. The catalog shows up in
-- the house editor's storage panel and in the housing dashboard, both
-- load-on-demand, so the hooks wait for their addons. Every step is guarded:
-- if Blizzard moves the frames around, the button simply never appears.

local function entryFromFrame(frame)
    -- Entry frames keep their catalog id from Init. Headers and market
    -- bundles have no entryVariantID and are skipped.
    local variantID = frame.entryVariantID
    if not variantID or variantID.entryType ~= Enum.HousingCatalogEntryType.Decor then
        return nil
    end
    return frame.entryInfo or C_HousingCatalog.GetCatalogEntryInfo(variantID)
end

local function attachButton(frame)
    if frame.cartAddButton then
        return
    end
    local btn = DCR.FlatButton(frame, "+", 22)
    btn:SetHeight(22)
    btn:SetPoint("BOTTOMRIGHT", -4, 4)
    btn:SetFrameLevel(frame:GetFrameLevel() + 10)
    btn:Hide()
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add to cart")
        GameTooltip:AddLine("Shift: add 5, Ctrl: add 10", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnClick", function()
        local entry = entryFromFrame(frame)
        if entry then
            local count = DCR.ClickStep()
            local added = DCR.AddCartEntry(entry, count)
            if added then
                DCR.ShowCart()
                DCR.CartFlyFX(added, count)
            end
        end
    end)
    -- Shown only while the mouse is over the entry (or the button itself,
    -- since leaving the entry onto the button fires the entry's OnLeave).
    frame:HookScript("OnEnter", function()
        if entryFromFrame(frame) then
            btn:Show()
        end
    end)
    frame:HookScript("OnLeave", function()
        if not btn:IsMouseOver() then
            btn:Hide()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.hover = false
        self:SetBackdropColor(0.16, 0.16, 0.2, 1)
        self:Hide()
    end)
    frame.cartAddButton = btn
end

-- ScrollUtil's two call paths disagree: iterateExisting calls back with
-- (frame, elementData), the acquired event with (ownerHandle, frame, ...)
-- where a nil owner becomes a numeric handle. Take whichever arg is the
-- frame.
local function onAcquired(a, b)
    local frame = (type(a) == "table" and a.GetObjectType) and a or b
    if type(frame) == "table" and frame.GetObjectType then
        attachButton(frame)
    end
end

local function hookScrollBox(scrollBox)
    if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) then
        return
    end
    if scrollBox.cartHooked then
        return
    end
    scrollBox.cartHooked = true
    ScrollUtil.AddAcquiredFrameCallback(scrollBox, onAcquired, nil, true)
end

-- The same catalog list appears in two places: the storage panel inside the
-- house editor, and the dashboard's catalog tab outside it. Each lives in
-- its own load-on-demand Blizzard addon.
local function boxIn(root, panelKey)
    local panel = root and root[panelKey]
    local container = panel and panel.OptionsContainer
    return container and container.ScrollBox
end

local HOSTS = {
    Blizzard_HouseEditor = function()
        return boxIn(HouseEditorFrame, "StoragePanel")
    end,
    Blizzard_HousingDashboard = function()
        return boxIn(HousingDashboardFrame, "CatalogContent")
    end,
}

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, _, name)
    if HOSTS[name] then
        hookScrollBox(HOSTS[name]())
    end
end)

-- Called from InitCore, so a standing-by module never installs the hooks
-- (the active standalone build does it instead). Either host can already be
-- loaded when the module is enabled mid-session.
function DCR.CatalogInit()
    f:RegisterEvent("ADDON_LOADED")
    for name, box in pairs(HOSTS) do
        if C_AddOns.IsAddOnLoaded(name) then
            hookScrollBox(box())
        end
    end
end
