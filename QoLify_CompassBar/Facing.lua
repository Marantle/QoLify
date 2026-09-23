-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local _, CB = ...

-- Where the facing comes from: the character's facing, read as a plain
-- number. That only works out in the world. Inside instances the game
-- seals it, and since the 12.1 hotfix the minimap compass ring is closed
-- too, so the bar stands down there (Strip.Apply) and nothing here runs.

local Facing = {}
CB.Facing = Facing

local driver = CreateFrame("Frame")
driver:Hide()
local plain = false -- the character's facing read as a number this tick
local HZ = 30

-- a sealed value survives the call and only throws once math touches it,
-- so a reading counts as usable only when the math goes through. Some
-- builds hand out nil instead of a secret, that reads as unusable too
local function plainFacing()
    local ok, v = pcall(GetPlayerFacing)
    if not ok or type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then
        return
    end
    local okMath = pcall(function()
        return v + 0
    end)
    return okMath and v or nil
end

local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 / HZ then
        return
    end
    elapsed = 0
    local facing = plainFacing()
    plain = facing ~= nil
    -- the bar was built for minus the facing, the way the minimap ring
    -- turns
    CB.Strip.Spin(plain and -facing or nil)
end)

-- a hidden frame gets no OnUpdate, so the driver only runs while the bar
-- is up
function Facing.Want(on)
    driver:SetShown(on and true or false)
end

function Facing.Status()
    if not driver:IsShown() then
        return "facing: not needed right now"
    end
    if plain then
        return "facing: read straight from your character"
    end
    return "facing: the game keeps it from addons right now, so the bar is blank"
end
