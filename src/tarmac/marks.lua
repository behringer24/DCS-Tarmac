--- F10 map marks with collision free ids. Mark ids are global in DCS and
-- shared with marks placed by players and other scripts, so Tarmac hands
-- out ids from its own range.

local marks = {}

--- First id used by Tarmac. Change before creating marks if it collides
-- with another script.
marks.firstId = 1500000

local lastId = nil

function marks.nextId()
    lastId = (lastId or (marks.firstId - 1)) + 1
    return lastId
end

-- Optional arguments are left out instead of passing nil, the DCS functions
-- are implemented in C and check the types of the arguments they get.

--- Mark visible to one coalition. Options: readOnly (default true), message.
function marks.toCoalition(coalitionId, text, point, options)
    options = options or {}
    local id = marks.nextId()
    if options.message then
        trigger.action.markToCoalition(id, text, point, coalitionId, options.readOnly ~= false, options.message)
    else
        trigger.action.markToCoalition(id, text, point, coalitionId, options.readOnly ~= false)
    end
    return id
end

--- Mark visible to everyone. Options: readOnly (default true), message.
function marks.toAll(text, point, options)
    options = options or {}
    local id = marks.nextId()
    if options.message then
        trigger.action.markToAll(id, text, point, options.readOnly ~= false, options.message)
    else
        trigger.action.markToAll(id, text, point, options.readOnly ~= false)
    end
    return id
end

function marks.remove(id)
    if id ~= nil then
        trigger.action.removeMark(id)
    end
end

return marks
