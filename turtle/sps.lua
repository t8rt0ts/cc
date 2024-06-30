--Safe Positioning System
--Inspired by https://github.com/zyxkad/cc/blob/master/turtle/lps.lua

--zyxkad's system uses files to store the turtle position
--Which on world crashes, breaks because cc files are stored at different times than the world nbt
--This system uses computer labels to store the turtle position
--Computer labels modify the nbt of the block, meaning that the position on the label is saved at the same time as the turtles actual position
--This is also extremely useful for glitched duplicate id turtles, as they share files, but not computer ids as computer ids are specific to the block
--The main downside is that you cant use computer labels at the same time as this

--Use turtle.native instead of turtle to bypass the positioning



--First 2 bytes are magic numbers (to check if label valid)
--Next 4 bytes x coordinate (signed integer)
--Next 2 bytes y coordinate (signed short)
--Next 4 bytes z coordinate (signed integer)
--Next byte the rotatation (0-3)
--Next byte flags
--  bit 0[1]: is fuel level odd (true) or even (false)? [These two bits are used to determine turtles position if server crashed while the turtle was moving]
--  bit 1-2[2-3]: last move (0 for forward,1 for backwards,2 for up, 3 for down
--  bit 3-7[4-8]: unused

--First 2 chars are the magic numbers
--Next 8 chars are the x coordinate as signed integer (represented in hex)
--Next 4 chars are the y coordinate as signed short (represented in hex)
--Next 8 chars are the z coordinate as signed integer (represented in hex)
--Next char is the rotation (0-3)
--Next char is the flags as hex
--  bit 0: is fuel level odd (true) or even (false)? [Used to determine if the turtle moved during a crash]
--  bit 1-2: last move (0 for forward,1 for backwards,2 for up, 3 for down
--  bit 3: unused

--Override setComputerLabel to prevent people from modifying the position
local setComputerLabel = os.setComputerLabel
os.setComputerLabel = function(label,override)
    if override == true then
        return setComputerLabel(label)
    else
        error("It is dangerous to modify the computer label! Use `os.setComputerLabel("..tostring(label)..",true)` to override this error")
    end
end

--constants
local magicNumbers = string.char(167) .. "k"
local hex = "%x"
local regex = "^"..magicNumbers.."("..hex:rep(8)..")("..hex:rep(4)..")("..hex:rep(8)..")(%d)(%x)"
local completion = require("cc.completion")
local expect = require("cc.expect").expect
local facingTab = {
    [0] = "-z",
    [1] = "+x",
    [2] = "+z",
    [3] = "-x",
    ["-z"] = 0,
    ["+x"] = 1,
    ["+z"] = 2,
    ["-x"] = 3,
    north = 0,
    east = 1,
    south = 2,
    west = 3
} --For compat with zyxkad's system


local function numToStr(num,len)
    num = num + 2^(len*4 - 1)
    local str = hex:format(num)
    str = string.rep("0",len-#str) .. str
    return str
end
local function strToNum(str)
    return tonumber(str,16) - 2^(#str*4 - 1)
end

local function hasbit(x,p)
    return x%(p+p)>=p
end
local function setbit(x,p)
    return hasbit(x,p) and x or x+p
end

local function getLabel(pos)
    return magicNumbers ..numToStr(pos.x,8)..numToStr(pos.y,4)..numToStr(pos.z,8)..pos.rot .. hex:format(pos.flags)
end

local function promptRot()
    local rot = {north=0,east=1,south=2,west=3}
    term.clear()
    term.setCursorPos(1,1)
    print("Please input the starting rotation of the turtle (north,south,east,west)")
    local input = read(nil,nil,function(txt) return completion.choice(txt,{"north","south","east","west"}) end)
    if not rot[input] then error("Invalid starting rotation") end
    return rot[input]
end
local function movePre(pos,dir)
    pos.flags = bit.bor(bit.band(pos.flags,8),dir*2+turtle.getFuelLevel()%2) --update flags to show which direction you're going + fuel level
    setComputerLabel(getLabel(pos))
end
local function movePost(pos,dir)
    pos.flags = setbit(pos.flags,turtle.getFuelLevel()%2) --update flags to show new fuel level
    if dir <= 1 then --update the turtle position
        local rot = (pos.rot + dir*2)%4
        if rot == 0 then
            pos.z = pos.z - 1
        elseif rot == 1 then
            pos.x = pos.x + 1
        elseif rot == 2 then
            pos.z = pos.z + 1
        else
            pos.x = pos.x - 1
        end
    elseif dir == 2 then
        pos.y = pos.y + 1
    else
        pos.y = pos.y - 1
    end
    setComputerLabel(getLabel(pos))
end


local SPS = {}
pos = nil

function SPS.init(facing,x,y,z)
    if facing and not facingTab[facing] then error("Invalid facing, must be +/-x, +/-z, or north, south, east, or west") end
    pos = {
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        z = tonumber(z) or 0,
        rot = facing and facingTab[facing],
        flags = turtle.getFuelLevel()%2
    }
    local label = os.getComputerLabel()
    if label then
        local x,y,z,rot,flags = label:match(regex)
        if not x then
            local file = fs.open("label.txt","w+")
            file.write(label)
            file.close()
            -- pos.rot = promptRot()
            if not pos.rot then return false end
            setComputerLabel(getLabel(pos))
        else
            pos.x,pos.y,pos.z,pos.rot = strToNum(x),strToNum(y),strToNum(z),tonumber(rot)
            flags = tonumber(flags,16)
            if flags%2 ~= pos.flags%2 then --turtle fuel level is not consistent, means the turtle moved, but movePost was never called before the server went down.
                pos.flags = flags
                movePost(pos,math.floor(flags/2)%4)
            end
        end
    else
        -- pos.rot = promptRot()
        if not pos.rot then return false end --Changing from my prompt function to returning false if there is no facing provided, for compatibility with the old lps version
        setComputerLabel(getLabel(pos))
    end
    
    turtle.forward = function()
        movePre(pos,0)
        if turtle.native.forward() then
            movePost(pos,0)
            return true
        end
        return false
    end
    turtle.back = function()
        movePre(pos,1)
        if turtle.native.back() then
            movePost(pos,1)
            return true
        end
        return false
    end
    turtle.up = function()
        movePre(pos,2)
        if turtle.native.up() then
            movePost(pos,2)
            return true
        end
        return false
    end
    turtle.down = function()
        movePre(pos,3)
        if turtle.native.down() then
            movePost(pos,3)
            return true
        end
        return false
    end
    turtle.turnLeft = function()
        pos.rot = (pos.rot - 1)%4
        setComputerLabel(getLabel(pos))
        return turtle.native.turnLeft()
    end
    turtle.turnRight = function()
        pos.rot = (pos.rot + 1)%4
        setComputerLabel(getLabel(pos))
        return turtle.native.turnRight()
    end
    return true
end
function SPS.locate()
    return pos.x,pos.y,pos.z
end
function SPS.facing()
    return facingTab[pos.rot]
end
function SPS.version() --Exists only for compat, i dont plan on using this ever
    return 1,"This is deprecated for sps and only exists for compat!"
end
function SPS.updatePosition(x,y,z,rot)
    expect(1,x,"number")
    expect(2,y,"number")
    expect(3,z,"number")
    expect(4,rot,"number","nil")
    pos.x,pos.y,pos.z = x,y,z
    if rot then 
        pos.rot = math.floor(rot)%4
    end
    setComputerLabel(getLabel(pos))
end
return SPS