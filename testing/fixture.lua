-- Builders for mission tables in mission editor format, for tests.
--   local m = fixture.mission()
--   fixture.group(m, "red", country.id.RUSSIA, "vehicle", { name = "Tanks-1", units = { { type = "T-72B" } } })
--   dcs.start(m)

fixture = {}

local nextId = 1

local function id()
    nextId = nextId + 1
    return nextId
end

function fixture.mission()
    return {
        version = 21,
        theatre = "Caucasus",
        coalition = {
            red = { name = "red", country = {} },
            blue = { name = "blue", country = {} },
            neutrals = { name = "neutrals", country = {} },
        },
        triggers = { zones = {} },
    }
end

local function countryTable(mission, sideName, countryId)
    local list = mission.coalition[sideName].country
    for _, entry in ipairs(list) do
        if entry.id == countryId then
            return entry
        end
    end
    local entry = { id = countryId, name = "country " .. countryId }
    list[#list + 1] = entry
    return entry
end

local function addTo(mission, sideName, countryId, category, groupData)
    local entry = countryTable(mission, sideName, countryId)
    entry[category] = entry[category] or { group = {} }
    local groups = entry[category].group
    groups[#groups + 1] = groupData
    return groupData
end

-- Adds a group. spec: name, units = { { type, name?, x?, y?, skill? } },
-- x, y, route (list of points), lateActivation, uncontrolled.
function fixture.group(mission, sideName, countryId, category, spec)
    local x, y = spec.x or 0, spec.y or 0
    local units = {}
    for index, unitSpec in ipairs(spec.units or { { type = "T-72B" } }) do
        units[index] = {
            name = unitSpec.name or string.format("%s-%d", spec.name, index),
            type = unitSpec.type,
            unitId = id(),
            x = unitSpec.x or x + index * 10,
            y = unitSpec.y or y,
            alt = unitSpec.alt,
            heading = 0,
            skill = unitSpec.skill or "Average",
        }
    end
    local points = spec.route or { { x = x, y = y, type = "Turning Point", action = "Off Road", speed = 10 } }
    return addTo(mission, sideName, countryId, category, {
        name = spec.name,
        groupId = id(),
        x = x,
        y = y,
        units = units,
        route = { points = points },
        task = spec.task or "Ground Nothing",
        lateActivation = spec.lateActivation,
        uncontrolled = spec.uncontrolled,
        start_time = 0,
    })
end

-- Adds a client slot group (one unit with skill "Client").
function fixture.client(mission, sideName, countryId, category, spec)
    spec.units = spec.units or { { type = spec.type or "FA-18C_hornet", skill = "Client" } }
    for _, unitSpec in ipairs(spec.units) do
        unitSpec.skill = unitSpec.skill or "Client"
    end
    return fixture.group(mission, sideName, countryId, category, spec)
end

-- Adds a static object. The unit name is "<name>-1" like in the editor
-- unless spec.unitName is given.
function fixture.static(mission, sideName, countryId, spec)
    return addTo(mission, sideName, countryId, "static", {
        name = spec.name,
        groupId = id(),
        dead = spec.dead or false,
        x = spec.x or 0,
        y = spec.y or 0,
        units = {
            {
                name = spec.unitName or (spec.name .. "-1"),
                type = spec.type or "Workshop A",
                category = "Fortifications",
                unitId = id(),
                x = spec.x or 0,
                y = spec.y or 0,
                heading = 0,
            },
        },
    })
end

-- Adds a trigger zone. properties is a key/value map.
function fixture.zone(mission, spec)
    local properties = {}
    for key, value in pairs(spec.properties or {}) do
        properties[#properties + 1] = { key = key, value = value }
    end
    local zones = mission.triggers.zones
    zones[#zones + 1] = {
        name = spec.name,
        x = spec.x or 0,
        y = spec.y or 0,
        radius = spec.radius or 1000,
        type = 0,
        zoneId = id(),
        properties = properties,
    }
end
