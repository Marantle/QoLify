local _, DCR = ...

-- The cart's patch notes. One entry per release with something worth
-- showing, newest first, a sentence or two each. Internal fixes stay in the
-- changelog. The header button blinks until the newest entry is read, and
-- the version string remembered in the DB keeps it quiet from then on, so a
-- release without an entry relights nothing.

local NEWS = {
    {
        v = "2.5.0",
        text = "Cart missing works anywhere now. It counts against your storage,"
            .. " so you can fill the cart right at the vendor. Tick Count placed"
            .. " decor on a blueprint's page to count what already stands in your"
            .. " house as owned.",
    },
    {
        v = "2.4.0",
        text = "Pieces only the auction house sells now show a price estimate,"
            .. " marked ~ like the catalog ones. Auctionator answers from your own"
            .. " searches, Oribos Exchange from its packaged scans, whichever you"
            .. " run, and hovering the price names the source. Blueprints show"
            .. " what they cost now too, in the picker and on Blizzard's"
            .. " blueprint window.",
    },
}

local box

local function latestSeen()
    local cart = DCR.CartDB()
    return not cart or cart.newsSeen == NEWS[1].v
end

-- The reading box, over the middle of the cart. Parented to it, so it rides
-- along in the house editor and goes down with the window.
local function buildBox(parent)
    box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetWidth(330)
    box:SetPoint("CENTER")
    box:SetBackdrop({ bgFile = DCR.WHITE, edgeFile = DCR.WHITE, edgeSize = 1 })
    box:SetBackdropColor(0.08, 0.08, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    box:EnableMouse(true)
    box:SetFrameLevel(parent:GetFrameLevel() + 20)

    local title = DCR.Label(box, "Patch notes", DCR.COLOR_GOLD, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)

    local body = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 14, -40)
    body:SetWidth(302)
    body:SetJustifyH("LEFT")
    body:SetSpacing(2)
    local parts = {}
    for i, n in ipairs(NEWS) do
        parts[i] = "|cffffd100" .. n.v .. "|r  " .. n.text
    end
    body:SetText(table.concat(parts, "\n\n"))
    box:SetHeight(40 + body:GetStringHeight() + 46)

    local ok = DCR.FlatButton(box, "Got it", 70)
    ok:SetPoint("BOTTOM", 0, 12)
    ok:SetScript("OnClick", function()
        box:Hide()
    end)
end

-- The header button for CartWindow.lua. Reading the notes once records the
-- newest version and stops the blink for good.
function DCR.NewsButton(panel)
    local btn = DCR.FlatButton(panel, "Patch notes", 96)
    local pulse = btn:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.5)
    if not latestSeen() then
        pulse:Play()
    end
    btn:SetScript("OnClick", function()
        local cart = DCR.CartDB()
        if cart then
            cart.newsSeen = NEWS[1].v
        end
        pulse:Stop()
        if not box then
            buildBox(panel)
        elseif box:IsShown() then
            box:Hide()
            return
        end
        box:Show()
    end)
    return btn
end
