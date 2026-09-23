-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local ADDON, CB = ...

-- The art in Media. Every image is white on transparent and gets its color
-- in game.

local Art = {}
CB.Art = Art

-- the folder is not the same in the module and the standalone build, so
-- the path comes from the addon's own name. The extension is spelled out,
-- extensionless paths only try blp and tga
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

function Art.Path(name)
    return MEDIA .. name .. ".png"
end
