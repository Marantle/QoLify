local _, DCR = ...

-- Puts a small + button on decor entries in the catalog lists, so pieces can
-- go straight onto the shopping list while browsing. Also hooks the dye
-- picker in customize mode, where a swatch is too small for a button and
-- ctrl-click carts the dye instead. Everything here lives in load-on-demand
-- Blizzard addons, so the hooks wait for them. Every step is guarded: if
-- Blizzard moves the frames around, the button simply never appears.

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

-- No widget script and no handler method ever fires on the swatch frames
-- themselves (observed 120007, HookScript and hooksecurefunc both stay
-- silent, and Blizzard's own OnEnter tooltip never shows either). The one
-- thing the client does route is the click, straight into the popout's
-- OnSwatchClicked with the swatch attached, so ctrl-click rides that.
-- Blizzard's handler runs first, meaning a ctrl-click also previews the dye
-- on the decor, which is harmless.

-- shift-click is the game's own dye tracking, so ctrl adds exactly one
local function onSwatchClick(swatch)
    if not IsControlKeyDown() or IsShiftKeyDown() then
        return
    end
    local added = DCR.AddDyeEntry(swatch.dyeColorInfo, 1)
    if added then
        DCR.ShowCart()
        DCR.CartFlyFX(added, 1)
    end
end

-- A small + like the catalog entries get, sized for a swatch. Since the
-- swatches produce no hover events at all, a light ticker runs while the
-- popout is shown and moves the button to whatever swatch the mouse is on.
-- Polling is the last resort, but here there is provably nothing to listen
-- to, and the ticker lives only as long as the picker is open.
local hoverBtn, hoverTicker

local function trackHover()
    if not DyeSelectionPopout:IsShown() then
        hoverTicker:Cancel()
        hoverTicker = nil
        if hoverBtn then
            hoverBtn:Hide()
            hoverBtn = nil
        end
        return
    end
    local focus = GetMouseFoci and GetMouseFoci()[1]
    local btn
    if focus then
        if focus.cartSwatch then
            btn = focus -- the mouse is on the + itself
        else
            local info = focus.cartAddButton and focus.dyeColorInfo
            if info and info.itemID then
                btn = focus.cartAddButton
            end
        end
    end
    if btn ~= hoverBtn then
        if hoverBtn then
            hoverBtn:Hide()
        end
        hoverBtn = btn
        if btn then
            btn:Show()
        end
    end
end

local function attachSwatchButton(swatch)
    local btn = DCR.FlatButton(swatch, "+", 16)
    btn:SetHeight(16)
    btn:SetPoint("BOTTOMRIGHT", -1, 1)
    btn:SetFrameLevel(swatch:GetFrameLevel() + 10)
    btn:Hide()
    btn.cartSwatch = swatch
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add to cart")
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        local added = DCR.AddDyeEntry(swatch.dyeColorInfo, 1)
        if added then
            DCR.ShowCart()
            DCR.CartFlyFX(added, 1)
        end
    end)
    swatch.cartAddButton = btn
end

local function hookPool(pool)
    if not pool then
        return
    end
    for swatch in pool:EnumerateActive() do
        if not swatch.cartHooked then
            swatch.cartHooked = true
            attachSwatchButton(swatch)
        end
    end
end

local dyeHooked = false
local function hookDyeSwatches()
    if dyeHooked or not DyeSelectionPopout then
        return
    end
    dyeHooked = true
    if DyeSelectionPopout.OnSwatchClicked then
        hooksecurefunc(DyeSelectionPopout, "OnSwatchClicked", function(_, swatch)
            onSwatchClick(swatch)
        end)
    end
    if DyeSelectionPopout.SetDyeSlotInfo then
        hooksecurefunc(DyeSelectionPopout, "SetDyeSlotInfo", function(self)
            hookPool(self.dyeSwatchPool)
            hookPool(self.recentSwatchPool)
            if not hoverTicker then
                hoverTicker = C_Timer.NewTicker(0.1, trackHover)
            end
        end)
    end
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, _, name)
    if HOSTS[name] then
        hookScrollBox(HOSTS[name]())
    end
    if name == "Blizzard_HouseEditor" then
        hookDyeSwatches()
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
    if C_AddOns.IsAddOnLoaded("Blizzard_HouseEditor") then
        hookDyeSwatches()
    end
end
