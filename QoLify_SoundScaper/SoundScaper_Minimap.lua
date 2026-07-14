local _, SS = ...

SS.Minimap = {}
local MM = SS.Minimap

local btn

local function ApplyPosition()
    local angle = math.rad((SS.db and SS.db.minimap and SS.db.minimap.angle) or 220)
    -- Radius from the minimap's actual size so the button sits on the edge
    -- regardless of how large the player's minimap is (matches LibDBIcon).
    local rx = (Minimap:GetWidth() / 2) + 5
    local ry = (Minimap:GetHeight() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * rx, math.sin(angle) * ry)
end

local function UpdateDrag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    if SS.db and SS.db.minimap then
        SS.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
    end
    ApplyPosition()
end

function MM:Build()
    if btn then
        return
    end

    btn = CreateFrame("Button", "SoundScaperMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

    -- The tracking-border ring is not centered within its own 53x53 texture, so a
    -- CENTER anchor drops the icon up and to the left where it clips the rim.
    -- TOPLEFT (7, -6) at 19x19 lands it dead-center in the ring. These are the
    -- measured values LibDBIcon uses for a 31x31 button with this border.
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface/Icons/INV_Misc_Bell_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    MM.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", UpdateDrag)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            SS.SetEnabled(not SS.db.enabled)
        else
            SS.Window:Toggle()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        local ctx = SS.CONTEXT_BY_KEY[SS.Context:Current()]
        local used = SS.CONTEXT_BY_KEY[SS.Context:Resolve(SS.Context:Current())]

        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SoundScaper", 0.4, 0.8, 1)
        if SS.db.enabled then
            GameTooltip:AddLine("Context: " .. (ctx and ctx.label or "?"), 1, 1, 1)
            if used and ctx and used.key ~= ctx.key then
                GameTooltip:AddLine("Using " .. used.label .. " settings", 0.6, 0.6, 0.6)
            end
        else
            GameTooltip:AddLine("Disabled", 1, 0.4, 0.4)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: open settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: enable/disable", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    ApplyPosition()
    MM:RefreshLook()
    MM.btn = btn
end

-- Desaturate the icon while the addon is switched off, so the minimap shows the
-- on/off state without opening anything.
function MM:RefreshLook()
    if not btn then
        return
    end
    MM.icon:SetDesaturated(not (SS.db and SS.db.enabled))
end
