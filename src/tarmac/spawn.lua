--- Spawning groups and statics from mission editor templates.
--   spawn.respawn("RedCAP-1")                      original group, original place
--   spawn.clone("TPL-SAR-Red", { name = "SAR #1", route = points })
--   spawn.add("vehicle", country.id.USA, groupData) any group table
-- Spawned groups are registered in tarmac.db and tarmac.tracker. Every
-- function returns the new Group (or StaticObject), or nil and a message.

local Log = require("tarmac.log")
local util = require("tarmac.util")
local db = require("tarmac.db")
local tracker = require("tarmac.tracker")

local log = Log.new("tarmac.spawn")

local spawn = {}

local groupCategories = {
    plane = Group.Category.AIRPLANE,
    helicopter = Group.Category.HELICOPTER,
    vehicle = Group.Category.GROUND,
    ship = Group.Category.SHIP,
}

local cloneCounter = 0

-- Prepares mission editor data for coalition.addGroup: the group appears
-- immediately and DCS assigns fresh ids.
local function prepare(data, options)
    data.lateActivation = false
    data.start_time = 0
    data.groupId = nil
    for _, unitData in ipairs(data.units or {}) do
        unitData.unitId = nil
    end
    if options.route then
        data.route = data.route or {}
        data.route.points = util.deepCopy(options.route)
    end
    if options.uncontrolled ~= nil then
        data.uncontrolled = options.uncontrolled
    end
    if options.modify then
        options.modify(data)
    end
    return data
end

local function addStatic(countryId, data, meta, register)
    local staticData = util.deepCopy(data.units and data.units[1] or data)
    staticData.dead = false
    staticData.unitId = nil
    if register then
        db.addGroup({ name = data.name or staticData.name, units = { util.deepCopy(staticData) } }, {
            category = "static",
            coalition = meta.coalition,
            countryId = countryId,
            source = "runtime",
        })
    end
    local ok, result = pcall(coalition.addStaticObject, countryId, staticData)
    if not ok or result == nil then
        return nil, "coalition.addStaticObject failed: " .. tostring(result)
    end
    return result
end

local function addGroup(category, countryId, data, coalitionId, register)
    local groupCategory = groupCategories[category]
    if groupCategory == nil then
        return nil, "unknown category " .. tostring(category)
    end
    -- register first: birth events may arrive while addGroup is running
    if register then
        db.addGroup(data, { category = category, coalition = coalitionId, countryId = countryId, source = "runtime" })
    end
    tracker.reset(data.name)
    local ok, group = pcall(coalition.addGroup, countryId, groupCategory, data)
    if not ok or group == nil then
        return nil, "coalition.addGroup failed: " .. tostring(group)
    end
    tracker.trackGroup(group)
    log:debug("spawned %s", data.name)
    return group
end

--- Spawns a group table (mission editor format). category is one of
-- "plane", "helicopter", "vehicle", "ship", "static". meta.coalition is
-- derived from the country when omitted.
function spawn.add(category, countryId, data, meta)
    meta = meta or {}
    local coalitionId = meta.coalition or coalition.getCountryCoalition(countryId)
    if category == "static" then
        return addStatic(countryId, data, { coalition = coalitionId }, true)
    end
    return addGroup(category, countryId, data, coalitionId, true)
end

--- Spawns a group again exactly as placed in the mission editor. A group
-- with the same name that still exists is replaced. The template itself
-- stays unchanged. Options: route, uncontrolled, modify(data).
function spawn.respawn(name, options)
    options = options or {}
    local record = db.group(name)
    if record == nil or record.source == "live" then
        return nil, "no template for group " .. tostring(name)
    end
    local data = prepare(util.deepCopy(record.data), options)
    if record.category == "static" then
        return addStatic(record.countryId, data, { coalition = record.coalition }, false)
    end
    return addGroup(record.category, record.countryId, data, record.coalition, false)
end

--- Spawns a copy of a template group under a new name. Options:
--   name        new group name (default "<template> #<n>")
--   unitName    function(groupName, index) for unit names (default "<group>-<index>")
--   route, uncontrolled, modify(data)   as for spawn.respawn
function spawn.clone(template, options)
    options = options or {}
    local record = db.group(template)
    if record == nil or record.source == "live" then
        return nil, "no template for group " .. tostring(template)
    end
    cloneCounter = cloneCounter + 1
    local data = prepare(util.deepCopy(record.data), options)
    data.name = options.name or string.format("%s #%d", template, cloneCounter)
    for index, unitData in ipairs(data.units or {}) do
        unitData.name = options.unitName and options.unitName(data.name, index)
            or string.format("%s-%d", data.name, index)
    end
    return spawn.add(record.category, record.countryId, data, { coalition = record.coalition })
end

--- Appends a "run script" action to a waypoint. The command string is
-- executed by DCS when the group reaches the waypoint.
function spawn.addWaypointScript(point, command)
    local task = point.task
    if task == nil or task.id ~= "ComboTask" then
        local tasks = {}
        if task ~= nil then
            tasks[1] = task
        end
        task = { id = "ComboTask", params = { tasks = tasks } }
        point.task = task
    end
    task.params = task.params or {}
    task.params.tasks = task.params.tasks or {}
    local tasks = task.params.tasks
    tasks[#tasks + 1] = {
        number = #tasks + 1,
        auto = false,
        id = "WrappedAction",
        enabled = true,
        params = { action = { id = "Script", params = { command = command } } },
    }
    return point
end

return spawn
