local ADDON, QOL = ... -- luacheck: no unused

-- Pre-fills the "type DELETE to confirm" popup so good items can be
-- deleted with one click.

local KEY = "quickDelete"

local function HookDialog(which)
    local dialog = StaticPopupDialogs and StaticPopupDialogs[which]
    if not dialog then
        return
    end
    local origOnShow = dialog.OnShow
    dialog.OnShow = function(self, ...)
        if origOnShow then
            origOnShow(self, ...)
        end
        if not QOL.IsFeatureEnabled(KEY) then
            return
        end
        local box = (self.GetEditBox and self:GetEditBox()) or self.editBox
        if box and DELETE_ITEM_CONFIRM_STRING then
            box:SetText(DELETE_ITEM_CONFIRM_STRING)
        end
    end
end

QOL.RegisterFeature({
    key = KEY,
    title = "Quick delete",
    notes = "Auto-fills the DELETE confirmation for rare or better items.",
    Init = function()
        HookDialog("DELETE_GOOD_ITEM")
        HookDialog("DELETE_GOOD_QUEST_ITEM")
    end,
})
