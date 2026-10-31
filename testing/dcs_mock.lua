-- In-memory stand-in for the DCS World mission scripting API, loaded by
-- "tarmac test" before every test file. It implements the subset of the API
-- that Tarmac and scripts built on it use and follows the documented DCS
-- behaviour where tests depend on it (e.g. Object.destroy raises no events,
-- coalition.addGroup replaces a group with the same name).
--
-- The global "dcs" table controls the simulation from tests:
--   dcs.start(mission)        instantiate a mission (sets env.mission)
--   dcs.advance(seconds)      advance model time and run scheduled functions
--   dcs.fire(event)           dispatch an event to all event handlers
--   dcs.kill(name, opts)      destroy a unit or static and fire loss events
--   dcs.spawnPlayer(...)      let a player enter a client or dynamic slot
-- and records side effects: dcs.messages, dcs.flags, dcs.marks, dcs.logs, ...

local deepCopy

dcs = {
    time = 0,
    absStart = 43200,
    logs = {},
    messages = {},
    flags = {},
    marks = {},
    markErrors = {},
    smokes = {},
    explosions = {},
    menus = {},
    spawned = {},
    removedScenery = {},
    missionsLoaded = 0,
    surface = nil,
    typeAttributes = {
        ["M 818"] = { Trucks = true, ["Ground vehicles"] = true },
        ["KAMAZ Truck"] = { Trucks = true, ["Ground vehicles"] = true },
        ["Ural-375"] = { Trucks = true, ["Ground vehicles"] = true },
        ["HL_KORD"] = { Cars = true, ["Ground vehicles"] = true },
    },
}

local handlers = {}
local scheduled = {}
local nextScheduleId = 1
local groupsByName, unitsByName, staticsByName, airbasesByName = {}, {}, {}, {}
local sceneryObjects = {}
local countryCoalition = {}
local nextGroupId, nextUnitId = 5000, 5000

deepCopy = function(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[deepCopy(k, seen)] = deepCopy(v, seen)
    end
    return copy
end
dcs.deepCopy = deepCopy

local function log(level, text)
    dcs.logs[#dcs.logs + 1] = string.format("%8.1f %-5s %s", dcs.time, level, tostring(text))
end

---------------------------------------------------------------------------
-- enumerations
---------------------------------------------------------------------------

local eventNames = {
    [0] = "INVALID", "SHOT", "HIT", "TAKEOFF", "LAND", "CRASH", "EJECTION", "REFUELING", "DEAD",
    "PILOT_DEAD", "BASE_CAPTURED", "MISSION_START", "MISSION_END", "TOOK_CONTROL", "REFUELING_STOP",
    "BIRTH", "HUMAN_FAILURE", "DETAILED_FAILURE", "ENGINE_STARTUP", "ENGINE_SHUTDOWN",
    "PLAYER_ENTER_UNIT", "PLAYER_LEAVE_UNIT", "PLAYER_COMMENT", "SHOOTING_START", "SHOOTING_END",
    "MARK_ADDED", "MARK_CHANGE", "MARK_REMOVED", "KILL", "SCORE", "UNIT_LOST",
    "LANDING_AFTER_EJECTION", "PARATROOPER_LENDING", "DISCARD_CHAIR_AFTER_EJECTION", "WEAPON_ADD",
    "TRIGGER_ZONE", "LANDING_QUALITY_MARK", "BDA", "AI_ABORT_MISSION", "DAYNIGHT", "FLIGHT_TIME",
    "PLAYER_SELF_KILL_PILOT", "PLAYER_CAPTURE_AIRFIELD", "EMERGENCY_LANDING", "UNIT_CREATE_TASK",
    "UNIT_DELETE_TASK", "SIMULATION_START", "WEAPON_REARM", "WEAPON_DROP", "UNIT_TASK_COMPLETE",
    "UNIT_TASK_STAGE", "MAC_EXTRA_SCORE", "MISSION_RESTART", "MISSION_WINNER", "RUNWAY_TAKEOFF",
    "RUNWAY_TOUCH", "MAC_LMS_RESTART", "SIMULATION_FREEZE", "SIMULATION_UNFREEZE",
    "HUMAN_AIRCRAFT_REPAIR_START", "HUMAN_AIRCRAFT_REPAIR_FINISH", "MAX",
}

world = { event = {}, VolumeType = { SEGMENT = 0, BOX = 1, SPHERE = 2, PYRAMID = 3 } }
for id = 0, #eventNames do
    world.event["S_EVENT_" .. eventNames[id]] = id
end

coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }

country = {
    id = {
        RUSSIA = 0, UKRAINE = 1, USA = 2, TURKEY = 3, UK = 4, FRANCE = 5, GERMANY = 6,
        AGGRESSORS = 7, CANADA = 8, SPAIN = 9, GEORGIA = 16, INSURGENTS = 17,
        CJTF_BLUE = 80, CJTF_RED = 81, UN_PEACEKEEPERS = 82,
    },
}

local defaultCountryCoalition = {
    [0] = 1, [2] = 2, [4] = 2, [5] = 2, [6] = 2, [16] = 2, [17] = 1, [80] = 2, [81] = 1,
}

Object = { Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, CARGO = 6 } }
Unit = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2, SHIP = 3, STRUCTURE = 4 } }
Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 } }
StaticObject = {}
Airbase = { Category = { AIRDROME = 0, HELIPAD = 1, SHIP = 2 } }
SceneryObject = {}

land = { SurfaceType = { LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 } }

local unitCategoryOfGroup = {
    [Group.Category.AIRPLANE] = Unit.Category.AIRPLANE,
    [Group.Category.HELICOPTER] = Unit.Category.HELICOPTER,
    [Group.Category.GROUND] = Unit.Category.GROUND_UNIT,
    [Group.Category.SHIP] = Unit.Category.SHIP,
    [Group.Category.TRAIN] = Unit.Category.GROUND_UNIT,
}

local groupCategoryOfKey = {
    plane = Group.Category.AIRPLANE,
    helicopter = Group.Category.HELICOPTER,
    vehicle = Group.Category.GROUND,
    ship = Group.Category.SHIP,
}

---------------------------------------------------------------------------
-- env, timer, net, coord
---------------------------------------------------------------------------

env = {
    mission = nil,
    info = function(text) log("INFO", text) end,
    warning = function(text) log("WARN", text) end,
    error = function(text) log("ERROR", text) end,
    getValueDictByKey = function(key) return key end,
}

timer = {}

function timer.getTime()
    return dcs.time
end

function timer.getAbsTime()
    return dcs.absStart + dcs.time
end

function timer.getTime0()
    return dcs.absStart
end

function timer.scheduleFunction(fn, argument, time)
    local id = nextScheduleId
    nextScheduleId = nextScheduleId + 1
    scheduled[id] = { fn = fn, argument = argument, time = time }
    return id
end

function timer.removeFunction(id)
    scheduled[id] = nil
end

function timer.setFunctionTime(id, time)
    if scheduled[id] then
        scheduled[id].time = time
    end
end

-- Advances model time, running scheduled functions in time order. A
-- function returning a number is rescheduled to that time, like in DCS.
function dcs.advance(seconds)
    local target = dcs.time + seconds
    while true do
        local nextId, nextEntry
        for id, entry in pairs(scheduled) do
            if entry.time <= target and (nextEntry == nil or entry.time < nextEntry.time
                    or (entry.time == nextEntry.time and id < nextId)) then
                nextId, nextEntry = id, entry
            end
        end
        if nextEntry == nil then
            break
        end
        if nextEntry.time > dcs.time then
            dcs.time = nextEntry.time
        end
        scheduled[nextId] = nil
        local again = nextEntry.fn(nextEntry.argument, dcs.time)
        if type(again) == "number" then
            scheduled[nextId] = { fn = nextEntry.fn, argument = nextEntry.argument, time = again }
        end
    end
    dcs.time = target
end

function dcs.scheduledCount()
    local n = 0
    for _ in pairs(scheduled) do
        n = n + 1
    end
    return n
end

net = {}

function net.load_next_mission()
    dcs.missionsLoaded = dcs.missionsLoaded + 1
    return true
end

coord = {}

-- Not a real projection, but stable and invertible, which is all tests need.
function coord.LOtoLL(point)
    return 42 + point.x / 111000, 41 + point.z / 83000, point.y or 0
end

function coord.LLtoLO(lat, lon, alt)
    return { x = (lat - 42) * 111000, y = alt or 0, z = (lon - 41) * 83000 }
end

function land.getSurfaceType(point)
    return dcs.surface or land.SurfaceType.LAND
end

function land.getHeight(point)
    return 0
end

---------------------------------------------------------------------------
-- objects
---------------------------------------------------------------------------

local function point3(x, z, y)
    return { x = x or 0, y = y or 0, z = z or 0 }
end

local function checkAlive(object)
    if object.invalid then
        error(object.name .. " does not exist", 3)
    end
end

-- Units ---------------------------------------------------------------------

Unit.__index = Unit

function Unit.getByName(name)
    local unit = unitsByName[name]
    if unit and unit.exists then
        return unit
    end
    return nil
end

function Unit:getName() checkAlive(self) return self.name end
function Unit:getTypeName() checkAlive(self) return self.type end
function Unit:getCategory() return Object.Category.UNIT end
function Unit:getLife() checkAlive(self) return self.life end
function Unit:getLife0() return self.life0 end
function Unit:getCoalition() checkAlive(self) return self.coalition end
function Unit:getCountry() checkAlive(self) return self.country end
function Unit:getGroup() checkAlive(self) return self.group end
function Unit:getPlayerName() checkAlive(self) return self.playerName end
function Unit:getID() return self.id end
function Unit:getNumber() return self.index end
function Unit:isExist() return self.exists end
function Unit:isActive() return self.exists and self.group.active end
function Unit:inAir() return self.airborne == true end
function Unit:getVelocity() checkAlive(self) return self.velocity or point3(0, 0, 0) end
function Unit:hasAttribute(name) return self.attributes[name] == true end

function Unit:getDesc()
    checkAlive(self)
    return { category = self.unitCategory, typeName = self.type, displayName = self.type, life = self.life0 }
end

function Unit:getPoint()
    checkAlive(self)
    return point3(self.point.x, self.point.z, self.point.y)
end

function Unit:getPosition()
    checkAlive(self)
    return { p = self:getPoint(), x = point3(1, 0, 0), y = point3(0, 0, 1), z = point3(0, 1, 0) }
end

function Unit:destroy()
    dcs.removeUnit(self)
end

-- Controller ----------------------------------------------------------------

local Controller = {}
Controller.__index = Controller

function Controller:setTask(task) self.group.tasks[#self.group.tasks + 1] = deepCopy(task) end
function Controller:pushTask(task) self:setTask(task) end
function Controller:resetTask() end
function Controller:setCommand(command) self.group.commands[#self.group.commands + 1] = deepCopy(command) end
function Controller:setOption(id, value) self.group.options[id] = value end
function Controller:setOnOff(value) self.group.options.onOff = value end

-- Groups ------------------------------------------------------------------

Group.__index = Group

function Group.getByName(name)
    local group = groupsByName[name]
    if group and group.exists then
        return group
    end
    return nil
end

function Group:getName() return self.name end
function Group:getID() return self.id end
function Group:getCoalition() return self.coalition end
function Group:getCategory() return self.category end
function Group:isExist() return self.exists end
function Group:getInitialSize() return #self.allUnits end
function Group:getController() return self.controller end

function Group:getUnits()
    local alive = {}
    for _, unit in ipairs(self.allUnits) do
        if unit.exists then
            alive[#alive + 1] = unit
        end
    end
    return alive
end

function Group:getSize()
    return #self:getUnits()
end

function Group:getUnit(index)
    return self:getUnits()[index]
end

function Group:activate()
    if not self.active then
        self.active = true
        for _, unit in ipairs(self:getUnits()) do
            dcs.fire({ id = world.event.S_EVENT_BIRTH, initiator = unit })
        end
    end
end

function Group:destroy()
    dcs.removeGroup(self)
end

-- Static objects ------------------------------------------------------------

StaticObject.__index = StaticObject

function StaticObject.getByName(name)
    local static = staticsByName[name]
    if static and static.exists then
        return static
    end
    return nil
end

function StaticObject:getName() checkAlive(self) return self.name end
function StaticObject:getTypeName() return self.type end
function StaticObject:getCategory() return Object.Category.STATIC end
function StaticObject:getCoalition() return self.coalition end
function StaticObject:getCountry() return self.country end
function StaticObject:getLife() return self.life end
function StaticObject:isExist() return self.exists end
function StaticObject:getDesc() return { category = Unit.Category.STRUCTURE, typeName = self.type, life = self.life0 } end
function StaticObject:getPoint() return point3(self.point.x, self.point.z, self.point.y) end
function StaticObject:getPosition() return { p = self:getPoint() } end

function StaticObject:destroy()
    self.exists = false
    staticsByName[self.name] = nil
end

-- Airbases ------------------------------------------------------------------

Airbase.__index = Airbase

function Airbase.getByName(name)
    return airbasesByName[name]
end

function Airbase:getName() return self.name end
function Airbase:getCoalition() return self.coalition end
function Airbase:getCategory() return Object.Category.BASE end
function Airbase:getPoint() return point3(self.point.x, self.point.z, self.point.y) end
function Airbase:getDesc() return { category = self.airbaseCategory, typeName = self.name } end
function Airbase:isExist() return true end

function dcs.addAirbase(name, coalitionId, x, z)
    local airbase = setmetatable({
        name = name, coalition = coalitionId, point = point3(x, z), airbaseCategory = Airbase.Category.AIRDROME,
    }, Airbase)
    airbasesByName[name] = airbase
    return airbase
end

-- Tests set the spots: airbase.parking = { { Term_Index = 5, Term_Type = 40,
-- vTerminalPos = { x = 0, y = 0, z = 0 }, occupied = true }, ... }
function Airbase:getParking(available)
    local spots = {}
    for _, spot in ipairs(self.parking or {}) do
        if not (available and spot.occupied) then
            spots[#spots + 1] = deepCopy(spot)
        end
    end
    return spots
end

function world.getAirbases()
    local list = {}
    for _, airbase in pairs(airbasesByName) do
        list[#list + 1] = airbase
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Scenery -------------------------------------------------------------------

SceneryObject.__index = SceneryObject

function SceneryObject:getName() return self.name end
function SceneryObject:getPoint() return point3(self.point.x, self.point.z, self.point.y) end
function SceneryObject:getCategory() return Object.Category.SCENERY end
function SceneryObject:isExist() return self.exists end

function SceneryObject:destroy()
    self.exists = false
    dcs.removedScenery[#dcs.removedScenery + 1] = self.name
end

function dcs.addScenery(name, x, z)
    local object = setmetatable({ name = name, point = point3(x, z), exists = true }, SceneryObject)
    sceneryObjects[#sceneryObjects + 1] = object
    return object
end

---------------------------------------------------------------------------
-- creating and removing objects
---------------------------------------------------------------------------

function dcs.countryCoalition(countryId)
    return countryCoalition[countryId] or defaultCountryCoalition[countryId] or 0
end

local function newUnit(group, data, index)
    nextUnitId = nextUnitId + 1
    local attributes = {}
    for name in pairs(dcs.typeAttributes[data.type] or {}) do
        attributes[name] = true
    end
    local unit = setmetatable({
        id = data.unitId or nextUnitId,
        name = data.name,
        type = data.type,
        index = index,
        group = group,
        coalition = group.coalition,
        country = group.country,
        unitCategory = unitCategoryOfGroup[group.category],
        life = data.life or 3,
        life0 = data.life or 3,
        point = point3(data.x, data.y, data.alt),
        skill = data.skill,
        attributes = attributes,
        exists = true,
        airborne = false,
    }, Unit)
    local previous = unitsByName[data.name]
    if previous and previous.exists then
        dcs.removeUnit(previous)
    end
    unitsByName[data.name] = unit
    return unit
end

local function newGroup(countryId, category, data, active)
    nextGroupId = nextGroupId + 1
    local group = setmetatable({
        id = data.groupId or nextGroupId,
        name = data.name,
        coalition = dcs.countryCoalition(countryId),
        country = countryId,
        category = category,
        data = deepCopy(data),
        allUnits = {},
        tasks = {},
        commands = {},
        options = {},
        exists = true,
        active = active,
    }, Group)
    group.controller = setmetatable({ group = group }, Controller)
    return group
end

-- Removes a unit without events, like Object.destroy in DCS.
function dcs.removeUnit(unit)
    unit.exists = false
    local group = unit.group
    if group and group.exists and #group:getUnits() == 0 then
        group.exists = false
        if groupsByName[group.name] == group then
            groupsByName[group.name] = nil
        end
    end
end

function dcs.removeGroup(group)
    for _, unit in ipairs(group.allUnits) do
        unit.exists = false
    end
    group.exists = false
    if groupsByName[group.name] == group then
        groupsByName[group.name] = nil
    end
end

local function createGroup(countryId, category, data, options)
    options = options or {}
    local previous = groupsByName[data.name]
    if previous then
        dcs.removeGroup(previous)
    end
    local active = not data.lateActivation
    local group = newGroup(countryId, category, data, active)
    for index, unitData in ipairs(data.units or {}) do
        local isClient = unitData.skill == "Client" or unitData.skill == "Player"
        if not isClient or options.player then
            local unit = newUnit(group, unitData, index)
            if isClient then
                unit.playerName = options.player
            end
            group.allUnits[#group.allUnits + 1] = unit
        end
    end
    if #group.allUnits == 0 then
        return nil
    end
    groupsByName[data.name] = group
    if options.birth ~= false and active then
        for _, unit in ipairs(group.allUnits) do
            dcs.fire({ id = world.event.S_EVENT_BIRTH, initiator = unit })
        end
    end
    return group
end

local function createStatic(countryId, data)
    local previous = staticsByName[data.name]
    if previous then
        previous:destroy()
    end
    local static = setmetatable({
        name = data.name,
        type = data.type,
        coalition = dcs.countryCoalition(countryId),
        country = countryId,
        life = data.dead and 0 or (data.life or 10),
        life0 = data.life or 10,
        point = point3(data.x, data.y),
        exists = true,
    }, StaticObject)
    staticsByName[data.name] = static
    return static
end

function coalition.addGroup(countryId, category, data)
    dcs.spawned[#dcs.spawned + 1] = { country = countryId, category = category, data = deepCopy(data) }
    return createGroup(countryId, category, data)
end

function coalition.addStaticObject(countryId, data)
    dcs.spawned[#dcs.spawned + 1] = { country = countryId, static = true, data = deepCopy(data) }
    return createStatic(countryId, data)
end

function coalition.getCountryCoalition(countryId)
    return dcs.countryCoalition(countryId)
end

function coalition.getStaticObjects(side)
    local list = {}
    for _, static in pairs(staticsByName) do
        if static.exists and static.coalition == side then
            list[#list + 1] = static
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function coalition.getGroups(side, category)
    local list = {}
    for _, group in pairs(groupsByName) do
        if group.exists and group.coalition == side and (category == nil or group.category == category) then
            list[#list + 1] = group
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function coalition.getPlayers(side)
    local list = {}
    for _, unit in pairs(unitsByName) do
        if unit.exists and unit.playerName and unit.coalition == side then
            list[#list + 1] = unit
        end
    end
    return list
end

function coalition.getAirbases(side)
    local list = {}
    for _, airbase in pairs(airbasesByName) do
        if airbase.coalition == side then
            list[#list + 1] = airbase
        end
    end
    return list
end

-- Instantiates a mission table like DCS does at mission start: all groups
-- without late activation and all statics exist, client slots stay empty.
-- No birth events are fired because scripts are loaded afterwards.
function dcs.start(mission)
    env.mission = mission
    local sides = { red = 1, blue = 2, neutrals = 0 }
    for sideName, sideData in pairs(mission.coalition or {}) do
        for _, countryData in pairs(sideData.country or {}) do
            countryCoalition[countryData.id] = sides[sideName]
        end
    end
    for _, sideData in pairs(mission.coalition or {}) do
        for _, countryData in pairs(sideData.country or {}) do
            for key, categoryData in pairs(countryData) do
                if type(categoryData) == "table" and categoryData.group then
                    for _, groupData in pairs(categoryData.group) do
                        if key == "static" then
                            local unitData = deepCopy(groupData.units[1])
                            unitData.dead = groupData.dead
                            createStatic(countryData.id, unitData)
                        elseif groupCategoryOfKey[key] then
                            createGroup(countryData.id, groupCategoryOfKey[key], groupData, { birth = false })
                        end
                    end
                end
            end
        end
    end
end

-- Puts a player into a client slot of the mission (or a dynamic slot when
-- groupData is given) and fires the birth event.
function dcs.spawnPlayer(unitName, playerName, groupData, countryId)
    if groupData then
        return createGroup(countryId, groupCategoryOfKey[groupData.category or "plane"], groupData, { player = playerName })
    end
    for _, sideData in pairs(env.mission.coalition) do
        for _, countryData in pairs(sideData.country or {}) do
            for key, categoryData in pairs(countryData) do
                if type(categoryData) == "table" and categoryData.group and groupCategoryOfKey[key] then
                    for _, data in pairs(categoryData.group) do
                        for _, unitData in ipairs(data.units or {}) do
                            if unitData.name == unitName then
                                local single = deepCopy(data)
                                single.units = { deepCopy(unitData) }
                                return createGroup(countryData.id, groupCategoryOfKey[key], single, { player = playerName })
                            end
                        end
                    end
                end
            end
        end
    end
    error("no client slot named " .. tostring(unitName))
end

-- Destroys a unit or static and fires the events DCS would fire. Options:
--   events = { "UNIT_LOST", "DEAD" }  event names to fire (this is the default)
--   keep = true                      keep the object in the world (falling wreck)
--   killer = unit                    also fire S_EVENT_KILL with this initiator
function dcs.kill(name, options)
    options = options or {}
    local object = unitsByName[name] or staticsByName[name]
    if object == nil then
        error("dcs.kill: no unit or static named " .. tostring(name))
    end
    object.life = 0
    if options.killer then
        dcs.fire({ id = world.event.S_EVENT_KILL, initiator = options.killer, target = object })
    end
    for _, eventName in ipairs(options.events or { "UNIT_LOST", "DEAD" }) do
        dcs.fire({ id = world.event["S_EVENT_" .. eventName], initiator = object })
    end
    if not options.keep then
        if getmetatable(object) == Unit then
            dcs.removeUnit(object)
        end
    end
    return object
end

-- Marks an object as invalid: method calls raise errors like in DCS when an
-- object has been removed while scripts still hold a reference.
function dcs.invalidate(object)
    object.invalid = true
end

function dcs.unit(name)
    return unitsByName[name]
end

function dcs.group(name)
    return groupsByName[name]
end

function dcs.static(name)
    return staticsByName[name]
end

---------------------------------------------------------------------------
-- world
---------------------------------------------------------------------------

function world.addEventHandler(handler)
    handlers[#handlers + 1] = handler
end

function world.removeEventHandler(handler)
    for i = #handlers, 1, -1 do
        if handlers[i] == handler then
            table.remove(handlers, i)
        end
    end
end

function world.searchObjects(category, volume, callback, data)
    if category ~= Object.Category.SCENERY or volume.id ~= world.VolumeType.SPHERE then
        return 0
    end
    local p, radius, found = volume.params.point, volume.params.radius, 0
    if p.z == nil then
        error("world.searchObjects: sphere point must be a Vec3")
    end
    for _, object in ipairs(sceneryObjects) do
        if object.exists then
            local dx, dz = object.point.x - p.x, object.point.z - p.z
            if dx * dx + dz * dz <= radius * radius then
                found = found + 1
                if callback(object, data) == false then
                    break
                end
            end
        end
    end
    return found
end

-- Dispatches an event synchronously to every registered handler.
function dcs.fire(event)
    event.time = event.time or dcs.time
    local list = {}
    for i, handler in ipairs(handlers) do
        list[i] = handler
    end
    for _, handler in ipairs(list) do
        handler:onEvent(event)
    end
end

function dcs.handlerCount()
    return #handlers
end

---------------------------------------------------------------------------
-- trigger and missionCommands
---------------------------------------------------------------------------

trigger = { action = {}, misc = {}, smokeColor = { Green = 0, Red = 1, White = 2, Orange = 3, Blue = 4 } }

local function message(audience, target, text, duration)
    dcs.messages[#dcs.messages + 1] = { to = audience, target = target, text = text, duration = duration }
end

function trigger.action.outText(text, duration) message("all", nil, text, duration) end
function trigger.action.outTextForCoalition(side, text, duration) message("coalition", side, text, duration) end
function trigger.action.outTextForCountry(id, text, duration) message("country", id, text, duration) end
function trigger.action.outTextForGroup(id, text, duration) message("group", id, text, duration) end
function trigger.action.outTextForUnit(id, text, duration) message("unit", id, text, duration) end

function trigger.action.setUserFlag(name, value)
    if value == true then
        value = 1
    elseif value == false or value == nil then
        value = 0
    end
    dcs.flags[tostring(name)] = value
end

function trigger.misc.getUserFlag(name)
    return dcs.flags[tostring(name)] or 0
end

local function addMark(id, entry)
    if dcs.marks[id] then
        dcs.markErrors[#dcs.markErrors + 1] = "duplicate mark id " .. tostring(id)
        return
    end
    dcs.marks[id] = entry
end

function trigger.action.markToAll(id, text, point, readOnly, msg)
    addMark(id, { to = "all", text = text, point = point, readOnly = readOnly })
end

function trigger.action.markToCoalition(id, text, point, side, readOnly, msg)
    addMark(id, { to = "coalition", coalition = side, text = text, point = point, readOnly = readOnly })
end

function trigger.action.markToGroup(id, text, point, groupId, readOnly, msg)
    addMark(id, { to = "group", group = groupId, text = text, point = point, readOnly = readOnly })
end

function trigger.action.removeMark(id)
    dcs.marks[id] = nil
end

function trigger.action.effectSmokeBig(point, preset, density, name)
    dcs.smokes[#dcs.smokes + 1] = { point = point, preset = preset, density = density }
end

function trigger.action.explosion(point, power)
    dcs.explosions[#dcs.explosions + 1] = { point = point, power = power }
end

missionCommands = {}

local function menuKey(path)
    return table.concat(path or {}, "/")
end

local function addMenuItem(scope, target, name, path, fn, argument)
    local full = {}
    for i, part in ipairs(path or {}) do
        full[i] = part
    end
    full[#full + 1] = name
    dcs.menus[#dcs.menus + 1] = {
        scope = scope, target = target, path = menuKey(full), fn = fn, argument = argument, removed = false,
    }
    return full
end

function missionCommands.addSubMenuForGroup(id, name, path) return addMenuItem("group", id, name, path) end
function missionCommands.addCommandForGroup(id, name, path, fn, arg) return addMenuItem("group", id, name, path, fn, arg) end
function missionCommands.addSubMenuForCoalition(side, name, path) return addMenuItem("coalition", side, name, path) end
function missionCommands.addCommandForCoalition(side, name, path, fn, arg) return addMenuItem("coalition", side, name, path, fn, arg) end
function missionCommands.addSubMenu(name, path) return addMenuItem("all", nil, name, path) end
function missionCommands.addCommand(name, path, fn, arg) return addMenuItem("all", nil, name, path, fn, arg) end

local function removeMenu(scope, target, path)
    local prefix = menuKey(path)
    for _, item in ipairs(dcs.menus) do
        if item.scope == scope and item.target == target and not item.removed
                and (item.path == prefix or item.path:sub(1, #prefix + 1) == prefix .. "/") then
            item.removed = true
        end
    end
end

function missionCommands.removeItemForGroup(id, path) removeMenu("group", id, path) end
function missionCommands.removeItemForCoalition(side, path) removeMenu("coalition", side, path) end
function missionCommands.removeItem(path) removeMenu("all", nil, path) end

-- Returns the active menu entries of a scope target as a list of paths.
function dcs.menuPaths(scope, target)
    local paths = {}
    for _, item in ipairs(dcs.menus) do
        if item.scope == scope and item.target == target and not item.removed then
            paths[#paths + 1] = item.path
        end
    end
    return paths
end

-- Runs an F10 command like a player selecting it.
function dcs.selectMenu(scope, target, path)
    for _, item in ipairs(dcs.menus) do
        if item.scope == scope and item.target == target and item.path == path and not item.removed and item.fn then
            return item.fn(item.argument)
        end
    end
    error("no menu command " .. path)
end

-- Returns the messages whose text contains the given fragment.
function dcs.findMessages(fragment)
    local found = {}
    for _, entry in ipairs(dcs.messages) do
        if entry.text:find(fragment, 1, true) then
            found[#found + 1] = entry
        end
    end
    return found
end
