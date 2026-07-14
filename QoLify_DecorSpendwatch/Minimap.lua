local _, DSW = ...

-- Coin button on the minimap. Click opens the settings window, drag moves it
-- around the rim. The position is stored as an angle in DecorSpendwatchDB, the same
-- trick LibDBIcon uses.

local btn = CreateFrame("Button", "DecorSpendwatchMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

local icon = btn:CreateTexture(nil, "BACKGROUND")
-- The tracking-border ring is off-center in its own 53x53 texture, so a 19x19
-- icon at TOPLEFT (7, -6) lands dead-center in the ring on a 31x31 button.
icon:SetSize(19, 19)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexture("Interface/Icons/INV_Misc_Coin_01")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")

local function applyPosition()
    local angle = math.rad((DecorSpendwatchDB and DecorSpendwatchDB.minimapAngle) or 220)
    -- Radius off the live minimap size so the button hugs the edge whatever scale
    -- the player runs their minimap at.
    local rx = (Minimap:GetWidth() / 2) + 5
    local ry = (Minimap:GetHeight() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * rx, math.sin(angle) * ry)
end

local function updateDrag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    DecorSpendwatchDB.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    applyPosition()
end

btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", updateDrag)
end)
btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

btn:SetScript("OnClick", function()
    DSW.OpenSettings()
end)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("DecorSpendwatch", 1, 0.82, 0)
    GameTooltip:AddLine("Click: open settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move the button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- DecorSpendwatchDB is not populated until ADDON_LOADED, so place on login.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", applyPosition)
