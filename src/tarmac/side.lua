--- Coalition ids and names. Accepts ids (1, 2) and names ("red", "blue")
-- wherever a coalition is expected.

local side = {
    NEUTRAL = 0,
    RED = 1,
    BLUE = 2,
    --- The two fighting coalitions, for loops.
    BOTH = { 1, 2 },
}

local names = { [0] = "neutral", [1] = "red", [2] = "blue" }
local ids = { neutral = 0, neutrals = 0, red = 1, blue = 2 }

--- Returns the coalition id for an id or a (case insensitive) name, or nil.
function side.id(value)
    if type(value) == "number" then
        return names[value] and value or nil
    end
    if type(value) == "string" then
        return ids[value:lower()]
    end
    return nil
end

--- Lower case name ("red"), or "unknown".
function side.name(value)
    return names[side.id(value)] or "unknown"
end

--- Upper case name ("RED") for messages.
function side.label(value)
    return side.name(value):upper()
end

--- The opposing coalition of red or blue; neutral for anything else.
function side.enemy(value)
    local id = side.id(value)
    if id == side.RED then
        return side.BLUE
    elseif id == side.BLUE then
        return side.RED
    end
    return side.NEUTRAL
end

return side
