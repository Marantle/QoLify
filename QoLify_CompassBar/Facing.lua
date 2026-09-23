-- CompassBar, copyright 2026 Rothirr, all rights reserved.

local _, CB = ...

-- Where the facing comes from. Out in the world the character's facing
-- reads as a plain number and drives the bar directly, minimap left
-- alone. In instances every facing read is sealed, and what remains is the
-- minimap compass ring: it turns with the player while the minimap
-- rotates, and while its rotation reads back sealed too, SetRotation
-- renders sealed values, so the raw ring value goes straight into every
-- turning texture. Nothing here ever does math on a sealed value.

local Facing = {}
CB.Facing = Facing

--#region Lends

-- The ring only turns while the rotation CVar is on and the ring texture is
-- visible, every ancestor included. Minimap skins hide the texture or a
-- parent and some write the CVar back off on every reapply, so both lends
-- are reasserted every tick and handed back when nothing draws
local lent = {} -- region -> the alpha it had

-- SexyMap swaps the texture's Show for Hide, so lent regions are shown
-- through the real method off the frame metatable, which no addon can shadow
local function realShow(r)
    local mt = getmetatable(r)
    local real = mt and type(mt.__index) == "table" and mt.__index.Show or r.Show
    real(r)
end

local function lendRing()
    local r = MinimapCompassTexture
    while r and r ~= UIParent do
        if not r:IsShown() then
            if lent[r] == nil then
                lent[r] = r:GetAlpha()
                r:SetAlpha(0)
            end
            realShow(r)
        end
        r = r:GetParent()
    end
end

-- GetCVarBool rather than GetCVar since the string return would drip
-- garbage at thirty reads a second
local function lendRotation()
    if not C_CVar.GetCVarBool("rotateMinimap") then
        C_CVar.SetCVar("rotateMinimap", "1")
        CB.db.rotateLent = true
    end
end

-- rotateLent rides the saved variables so a crash or a reload still puts the
-- player's minimap back
function Facing.ReturnLends()
    for r, alpha in pairs(lent) do
        r:Hide()
        r:SetAlpha(alpha)
    end
    wipe(lent)
    if CB.db.rotateLent then
        CB.db.rotateLent = nil
        C_CVar.SetCVar("rotateMinimap", "0")
    end
end

--#endregion

--#region Driver

local driver = CreateFrame("Frame")
driver:Hide()
-- the sink probe. A build could close SetRotation to sealed values, so the
-- first write each tick goes to a texture nobody sees and a refusal blanks
-- the bar instead of erroring on every piece
local probe = driver:CreateTexture()
local refused = false
local plain = false -- the character's facing read as a number this tick
local HZ = 30

-- The 12.1 hotfix made GetRotation on the ring a Lua error in instances
-- ("forbidden aspect 'QueryRotation'"). Once it refuses, the ring path is
-- done for the session: lends go back, the bar blanks where facing is
-- sealed and still turns out in the world
local sealed = false
local SEALED = "the game no longer lets addons read the minimap compass in instances,"
    .. " so the bar stays blank there. Out in the world it turns as before."

local function readRing()
    local ring = MinimapCompassTexture
    if not ring then
        return
    end
    local ok, v = pcall(ring.GetRotation, ring)
    if ok then
        return v
    end
    sealed = true
    Facing.ReturnLends()
    CB.chat(SEALED)
end

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
    local rot
    local facing = plainFacing()
    plain = facing ~= nil
    if plain then
        -- the ring turns by minus the facing, and everything downstream
        -- was built for the ring's sense
        rot = -facing
        Facing.ReturnLends()
    elseif not sealed then
        lendRotation()
        lendRing()
        rot = readRing()
    end
    refused = false
    if rot ~= nil and not pcall(probe.SetRotation, probe, rot) then
        rot = nil
        refused = true
    end
    CB.Strip.Spin(rot)
end)

-- a hidden frame gets no OnUpdate, so the driver only runs while the bar
-- is up. The loan waits for the first tick, which knows whether it is needed
function Facing.Want(on)
    driver:SetShown(on and true or false)
    if not on then
        Facing.ReturnLends()
    end
end

-- whether the character's facing read as a number on the last tick
function Facing.Plain()
    return plain
end

function Facing.Status()
    if not driver:IsShown() then
        return "facing: not needed right now"
    end
    if plain then
        return "facing: read straight from your character, minimap untouched"
    end
    if sealed then
        return "compass ring: " .. SEALED
    end
    if not MinimapCompassTexture then
        return "compass ring: missing, another addon may have removed it, nothing can turn"
    end
    if refused then
        return "compass ring: the game refused its value so the bar is blank"
    end
    local cvar = CB.db.rotateLent and "minimap rotation on loan" or "your own minimap rotation"
    local skin = next(lent) and ", ring borrowed from under a minimap skin" or ""
    return ("compass ring: turning, %s%s"):format(cvar, skin)
end

--#endregion
