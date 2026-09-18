-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local ADDON, CB = ...

-- The art in Media and how a piece of it is put on a wheel. Every image is
-- white on transparent and gets its color in game.

local Art = {}
CB.Art = Art

-- the folder is not the same in the module and the standalone build, so
-- the path comes from the addon's own name. The extension is spelled out,
-- extensionless paths only try blp and tga
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

function Art.Path(name)
    return MEDIA .. name .. ".png"
end

-- The facing value is sealed, so nothing can add an offset to it and each
-- direction has to be the image itself turned before the spin goes on.
-- That turn is done in the texcoords: the sampled square is rotated about
-- its middle, so the image shows turned clockwise by the given degrees.
-- Every image keeps its art inside its inscribed circle and its edge
-- pixels clear, so whatever the turned square samples past the image
-- comes back clear under CLAMP
function Art.Turn(tex, degrees)
    local a = math.rad(degrees)
    local c, s = math.cos(a), math.sin(a)
    local function sample(x, y)
        return 0.5 + x * c + y * s, 0.5 - x * s + y * c
    end
    local ulx, uly = sample(-0.5, -0.5)
    local llx, lly = sample(-0.5, 0.5)
    local urx, ury = sample(0.5, -0.5)
    local lrx, lry = sample(0.5, 0.5)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- A small image put on a big quad: shown at the given size (a fraction of
-- the quad), at the given radius from the quad's middle (a fraction of
-- half the quad), at the given degrees clockwise from the top, and turned
-- by those degrees too so it reads upright once the quad has turned it to
-- the top. This is how a letter rides a wheel. Past the image the coords
-- run far out, and the texture's wrap has to clamp to clear out there
function Art.Place(tex, degrees, radius, size)
    local a = math.rad(degrees)
    local c, s = math.cos(a), math.sin(a)
    local cx, cy = 0.5 + 0.5 * radius * s, 0.5 - 0.5 * radius * c
    local function sample(x, y)
        local lx, ly = (x + 0.5 - cx) / size, (y + 0.5 - cy) / size
        return 0.5 + lx * c + ly * s, 0.5 - lx * s + ly * c
    end
    local ulx, uly = sample(-0.5, -0.5)
    local llx, lly = sample(-0.5, 0.5)
    local urx, ury = sample(0.5, -0.5)
    local lrx, lry = sample(0.5, 0.5)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end
