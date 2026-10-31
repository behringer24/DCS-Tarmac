--- Template database: every group, unit, static and trigger zone of the
-- mission, read once from env.mission when Tarmac loads. Records stay
-- available after the objects have died, which makes them the source for
-- respawning groups exactly as they were placed in the mission editor.
-- Groups spawned at runtime through tarmac.spawn are registered as well;
-- units that appear without a record (dynamic slots, other scripts) are
-- added from their live object by the tracker.
--
-- Group record: { name, category = "plane"|"helicopter"|"vehicle"|"ship"|"static",
--                 coalition, countryId, source = "mission"|"runtime"|"live", data }
-- Unit record:  { name, groupName, type, skill, coalition, category, countryId, index }
-- Zone record:  { name, point = Vec3, radius, vertices, properties }

local Log = require("tarmac.log")
local util = require("tarmac.util")

local log = Log.new("tarmac.db")

local db = {}

local groups, units, zones = {}, {}, {}

local categoryKeys = { "plane", "helicopter", "vehicle", "ship", "static" }
local coalitionKeys = { red = 1, blue = 2, neutrals = 0, neutral = 0 }

-- Old mission formats store names as dictionary keys.
local function text(value)
    if type(value) == "string" and value:find("^DictKey_") and env.getValueDictByKey then
        return env.getValueDictByKey(value)
    end
    return value
end

--- Adds (or replaces) a group record. data is the group table in mission
-- editor format; it is copied.
function db.addGroup(data, meta)
    local name = text(data.name)
    local record = {
        name = name,
        category = meta.category,
        coalition = meta.coalition,
        countryId = meta.countryId,
        source = meta.source or "runtime",
        data = util.deepCopy(data),
    }
    record.data.name = name
    local previous = groups[name]
    if previous then
        for _, unitData in ipairs(previous.data.units or {}) do
            if units[unitData.name] and units[unitData.name].groupName == name then
                units[unitData.name] = nil
            end
        end
    end
    groups[name] = record
    for index, unitData in ipairs(record.data.units or {}) do
        unitData.name = text(unitData.name)
        units[unitData.name] = {
            name = unitData.name,
            groupName = name,
            type = unitData.type,
            skill = unitData.skill,
            coalition = record.coalition,
            category = record.category,
            countryId = record.countryId,
            index = index,
        }
    end
    return record
end

--- Registers a unit seen in the world without a record (e.g. a dynamic
-- slot). Returns its unit record.
function db.addLiveUnit(info)
    local record = units[info.name]
    if record then
        return record
    end
    local group = groups[info.groupName]
    if group == nil then
        group = {
            name = info.groupName,
            category = info.category,
            coalition = info.coalition,
            countryId = info.countryId,
            source = "live",
            data = { name = info.groupName, units = {} },
        }
        groups[info.groupName] = group
    end
    local units_ = group.data.units
    units_[#units_ + 1] = { name = info.name, type = info.type }
    record = {
        name = info.name,
        groupName = info.groupName,
        type = info.type,
        coalition = info.coalition,
        category = info.category,
        countryId = info.countryId,
        index = #units_,
    }
    units[info.name] = record
    return record
end

local function loadZones(mission)
    local list = mission.triggers and mission.triggers.zones or {}
    for _, zoneData in pairs(list) do
        local properties = {}
        for _, property in pairs(zoneData.properties or {}) do
            if property.key then
                properties[property.key] = property.value
            end
        end
        local name = text(zoneData.name)
        zones[name] = {
            name = name,
            point = { x = zoneData.x, y = 0, z = zoneData.y },
            radius = zoneData.radius,
            vertices = zoneData.verticies,
            properties = properties,
        }
    end
end

--- Reads a mission table (env.mission). Called automatically on load.
function db.load(mission)
    groups, units, zones = {}, {}, {}
    if mission == nil then
        log:warn("no mission data available")
        return
    end
    local count = 0
    for coalitionKey, coalitionData in pairs(mission.coalition or {}) do
        local coalitionId = coalitionKeys[coalitionKey]
        for _, countryData in pairs(coalitionData.country or {}) do
            for _, category in ipairs(categoryKeys) do
                local categoryData = countryData[category]
                for _, groupData in pairs(categoryData and categoryData.group or {}) do
                    db.addGroup(groupData, {
                        category = category,
                        coalition = coalitionId,
                        countryId = countryData.id,
                        source = "mission",
                    })
                    count = count + 1
                end
            end
        end
    end
    loadZones(mission)
    log:info("loaded %d groups, %d units and %d zones", count, util.count(units), util.count(zones))
end

--- Group record by name, or nil. Do not modify the returned record.
function db.group(name)
    return groups[name]
end

--- Unit record by unit name, or nil.
function db.unit(name)
    return units[name]
end

--- Zone record by name, or nil.
function db.zone(name)
    return zones[name]
end

--- Copy of a group's mission editor data, ready to be modified and spawned.
function db.groupData(name)
    local record = groups[name]
    return record and util.deepCopy(record.data)
end

--- Copy of a group's route points, or nil.
function db.route(name)
    local record = groups[name]
    local route = record and record.data.route
    return route and route.points and util.deepCopy(route.points)
end

--- Group records matching a filter, sorted by name. Filter fields (all
-- optional): prefix, category, coalition, source.
function db.findGroups(filter)
    filter = filter or {}
    local list = {}
    for name, record in pairs(groups) do
        if (filter.prefix == nil or util.startsWith(name, filter.prefix))
                and (filter.category == nil or record.category == filter.category)
                and (filter.coalition == nil or record.coalition == filter.coalition)
                and (filter.source == nil or record.source == filter.source) then
            list[#list + 1] = record
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

--- True if the unit is a client or player slot.
function db.isClientUnit(name)
    local record = units[name]
    return record ~= nil and (record.skill == "Client" or record.skill == "Player")
end

db.load(env.mission)

return db
