--- Keeps track of the living units of every group, driven by events.
-- DCS removes dead objects quickly and Object.destroy raises no events at
-- all, so asking the world "is this group dead?" is unreliable at the
-- moment a unit dies. The tracker answers it from its own bookkeeping:
--   tracker.aliveCount("RedCAP-1")
-- and raises the custom event "tarmac.groupDead" ({ groupName = ... }) once
-- when the last tracked unit of a group is lost.

local Log = require("tarmac.log")
local db = require("tarmac.db")
local events = require("tarmac.events")
local object = require("tarmac.object")

local log = Log.new("tarmac.tracker")

local tracker = {}

local alive = {}   -- [groupName] = { [unitName] = true }
local counts = {}  -- [groupName] = number of living units
local groupOf = {} -- [unitName] = groupName

--- Records a living unit.
function tracker.unitAlive(unitName, groupName)
    if groupOf[unitName] == groupName and alive[groupName] and alive[groupName][unitName] then
        return
    end
    if groupOf[unitName] and groupOf[unitName] ~= groupName then
        tracker.unitLost(unitName, true)
    end
    alive[groupName] = alive[groupName] or {}
    alive[groupName][unitName] = true
    counts[groupName] = (counts[groupName] or 0) + 1
    groupOf[unitName] = groupName
end

--- Records the loss of a unit. Returns the group name and the number of
-- units left. Repeated reports for the same unit are ignored.
function tracker.unitLost(unitName, silent)
    local groupName = groupOf[unitName]
    if groupName == nil or not (alive[groupName] and alive[groupName][unitName]) then
        return groupName, groupName and counts[groupName] or 0
    end
    alive[groupName][unitName] = nil
    counts[groupName] = counts[groupName] - 1
    local left = counts[groupName]
    if left == 0 and not silent then
        log:debug("group %s has no living units left", groupName)
        events.emit("tarmac.groupDead", { groupName = groupName, lastUnit = unitName })
    end
    return groupName, left
end

--- Forgets all units of a group, e.g. right before it is respawned.
function tracker.reset(groupName)
    for unitName in pairs(alive[groupName] or {}) do
        groupOf[unitName] = nil
    end
    alive[groupName] = nil
    counts[groupName] = 0
end

--- Number of living units of a group.
function tracker.aliveCount(groupName)
    return counts[groupName] or 0
end

--- Names of the living units of a group, sorted.
function tracker.aliveUnits(groupName)
    local list = {}
    for unitName in pairs(alive[groupName] or {}) do
        list[#list + 1] = unitName
    end
    table.sort(list)
    return list
end

--- True when the group is gone from the world (or has no units left
-- there). Wrecks still falling from the sky count as present.
function tracker.isGone(groupName)
    local group = Group.getByName(groupName)
    if group == nil or not object.exists(group) then
        return true
    end
    local size = object.call(group, "getSize")
    return size == nil or size == 0
end

--- Records all units of a live group object (after spawning or seeding).
function tracker.trackGroup(group)
    local groupName = object.name(group)
    if groupName == nil then
        return
    end
    for _, unit in ipairs(object.call(group, "getUnits") or {}) do
        local unitName = object.name(unit)
        if unitName then
            tracker.unitAlive(unitName, groupName)
        end
    end
end

--- Destroys a unit and records its loss, because Object.destroy raises no
-- events in DCS.
function tracker.destroyUnit(unit)
    local unitName = object.name(unit)
    object.destroy(unit)
    if unitName then
        tracker.unitLost(unitName)
    end
end

--- Destroys a whole group and records the loss of all its units.
function tracker.destroyGroup(groupName)
    local group = Group.getByName(groupName)
    if group then
        object.destroy(group)
    end
    for _, unitName in ipairs(tracker.aliveUnits(groupName)) do
        tracker.unitLost(unitName)
    end
end

local function registerUnknown(unit, unitName)
    local group = object.group(unit)
    local groupName = object.name(group)
    if groupName == nil then
        return nil
    end
    local categoryKeys = {
        [Unit.Category.AIRPLANE] = "plane",
        [Unit.Category.HELICOPTER] = "helicopter",
        [Unit.Category.GROUND_UNIT] = "vehicle",
        [Unit.Category.SHIP] = "ship",
    }
    return db.addLiveUnit({
        name = unitName,
        groupName = groupName,
        type = object.typeName(unit),
        coalition = object.coalition(unit),
        countryId = object.country(unit),
        category = categoryKeys[object.unitCategory(unit)],
    })
end

local function onBirth(event)
    local unit = event.initiator
    local unitName = object.name(unit)
    -- only units belong to groups; statics, weapons and scenery do not
    if unitName == nil or object.group(unit) == nil then
        return
    end
    local record = db.unit(unitName) or registerUnknown(unit, unitName)
    if record and record.category ~= "static" then
        tracker.unitAlive(unitName, record.groupName)
    end
end

local function onLoss(event)
    local unitName = object.name(event.initiator)
    if unitName and groupOf[unitName] then
        tracker.unitLost(unitName)
    end
end

-- Units that already exist when Tarmac is loaded (no birth events seen).
local function seed()
    for _, record in ipairs(db.findGroups({ source = "mission" })) do
        if record.category ~= "static" then
            local group = Group.getByName(record.name)
            if group then
                tracker.trackGroup(group)
            end
        end
    end
end

events.on("BIRTH", onBirth)
events.on("UNIT_LOST", onLoss)
events.on("DEAD", onLoss)
events.on("CRASH", onLoss)
events.on("PILOT_DEAD", onLoss)
seed()

return tracker
