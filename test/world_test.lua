-- db, tracker, spawn, marks and menus

local m = fixture.mission()
fixture.group(m, "red", country.id.RUSSIA, "vehicle", {
    name = "Tanks-1", x = 1000, y = 2000,
    units = { { type = "T-72B" }, { type = "T-72B" } },
    route = {
        { x = 1000, y = 2000, action = "Off Road" },
        { x = 5000, y = 6000, action = "On Road" },
    },
})
fixture.group(m, "blue", country.id.USA, "helicopter", {
    name = "TPL-SAR-Blue", lateActivation = true, uncontrolled = true,
    units = { { type = "UH-1H" } },
})
fixture.group(m, "blue", country.id.USA, "plane", { name = "BlueCAP-1", units = { { type = "F-16C_50" }, { type = "F-16C_50" } } })
fixture.client(m, "blue", country.id.USA, "plane", { name = "BlueStrike-1" })
fixture.static(m, "red", country.id.RUSSIA, { name = "FactoryRed-1", x = 300, y = 400 })
fixture.zone(m, { name = "Depot-1", x = 10, y = 20, radius = 500, properties = { ROLE = "depot" } })
dcs.start(m)
loadBundle()

local db, tracker, spawn = tarmac.db, tarmac.tracker, tarmac.spawn

test("db reads groups, units, statics and zones of the mission", function()
    local tanks = db.group("Tanks-1")
    expect.equal(tanks.category, "vehicle")
    expect.equal(tanks.coalition, 1)
    expect.equal(tanks.countryId, country.id.RUSSIA)
    expect.equal(tanks.source, "mission")
    expect.equal(db.unit("Tanks-1-2").groupName, "Tanks-1")
    expect.equal(db.unit("FactoryRed-1-1").groupName, "FactoryRed-1")
    expect.equal(db.group("FactoryRed-1").category, "static")
    expect.truthy(db.isClientUnit("BlueStrike-1-1"))
    local zone = db.zone("Depot-1")
    expect.same(zone.point, { x = 10, y = 0, z = 20 })
    expect.equal(zone.properties.ROLE, "depot")
end)

test("db.findGroups filters by prefix, category and coalition", function()
    local found = db.findGroups({ prefix = "TPL-SAR", coalition = 2, category = "helicopter" })
    expect.equal(#found, 1)
    expect.equal(found[1].name, "TPL-SAR-Blue")
    expect.equal(#db.findGroups({ prefix = "Nope" }), 0)
end)

test("db.route returns an independent copy", function()
    local route = db.route("Tanks-1")
    route[1].x = -1
    expect.equal(db.route("Tanks-1")[1].x, 1000)
end)

test("tracker knows the units that existed before Tarmac loaded", function()
    expect.equal(tracker.aliveCount("Tanks-1"), 2)
    expect.equal(tracker.aliveCount("BlueCAP-1"), 2)
    expect.equal(tracker.aliveCount("BlueStrike-1"), 0)
end)

test("tracker raises groupDead once when the last unit is lost", function()
    local dead = {}
    local sub = tarmac.events.on("tarmac.groupDead", function(e) dead[#dead + 1] = e.groupName end)
    dcs.kill("BlueCAP-1-1")
    expect.equal(#dead, 0)
    -- a falling wreck: lost, but still in the world
    dcs.kill("BlueCAP-1-2", { keep = true, events = { "UNIT_LOST", "CRASH", "DEAD" } })
    expect.same(dead, { "BlueCAP-1" })
    expect.equal(tracker.aliveCount("BlueCAP-1"), 0)
    expect.falsy(tracker.isGone("BlueCAP-1"))
    dcs.removeUnit(dcs.unit("BlueCAP-1-2"))
    expect.truthy(tracker.isGone("BlueCAP-1"))
    tarmac.events.off(sub)
end)

test("spawn.respawn brings a group back as placed and keeps the template", function()
    dcs.kill("Tanks-1-1")
    dcs.kill("Tanks-1-2")
    expect.truthy(tracker.isGone("Tanks-1"))
    local group = spawn.respawn("Tanks-1")
    expect.notNil(group)
    expect.equal(group:getSize(), 2)
    expect.equal(tracker.aliveCount("Tanks-1"), 2)
    local spawned = dcs.spawned[#dcs.spawned].data
    expect.equal(spawned.name, "Tanks-1")
    expect.isNil(spawned.groupId)
    expect.equal(spawned.lateActivation, false)
    expect.equal(db.group("Tanks-1").source, "mission")
end)

test("spawn.respawn replaces a group that still exists", function()
    local before = Group.getByName("Tanks-1")
    local group = spawn.respawn("Tanks-1")
    expect.falsy(before:isExist())
    expect.truthy(group:isExist())
    expect.equal(tracker.aliveCount("Tanks-1"), 2)
end)

test("spawn.clone creates new names, an active group and a db record", function()
    local route = db.route("TPL-SAR-Blue")
    route[#route + 1] = { x = 1, y = 2 }
    local group = spawn.clone("TPL-SAR-Blue", { name = "SAR Blue #1", route = route })
    expect.notNil(group)
    expect.equal(group:getName(), "SAR Blue #1")
    expect.equal(group:getUnit(1):getName(), "SAR Blue #1-1")
    expect.equal(group:getCoalition(), 2)
    expect.equal(db.group("SAR Blue #1").source, "runtime")
    expect.equal(db.unit("SAR Blue #1-1").groupName, "SAR Blue #1")
    expect.equal(#dcs.spawned[#dcs.spawned].data.route.points, #route)
    expect.equal(dcs.spawned[#dcs.spawned].data.uncontrolled, true)
    local default = spawn.clone("TPL-SAR-Blue")
    expect.truthy(default:getName():find("^TPL%-SAR%-Blue #%d+$"))
end)

test("spawn reports unknown templates", function()
    local group, err = spawn.respawn("Missing")
    expect.isNil(group)
    expect.contains(err, "Missing")
end)

test("spawn.addWaypointScript appends to existing tasks", function()
    local point = { task = { id = "ComboTask", params = { tasks = { { id = "Hold", number = 1 } } } } }
    spawn.addWaypointScript(point, "x = 1")
    local tasks = point.task.params.tasks
    expect.equal(#tasks, 2)
    expect.equal(tasks[2].number, 2)
    expect.equal(tasks[2].params.action.params.command, "x = 1")
    local bare = spawn.addWaypointScript({}, "y = 2")
    expect.equal(bare.task.params.tasks[1].id, "WrappedAction")
end)

test("units of unknown groups are registered on birth", function()
    dcs.spawnPlayer(nil, "Viper", {
        name = "Dynamic F-16 #1", category = "plane",
        units = { { name = "Dynamic F-16 #1-1", type = "F-16C_50", skill = "Client", x = 0, y = 0 } },
    }, country.id.USA)
    local record = db.unit("Dynamic F-16 #1-1")
    expect.notNil(record)
    expect.equal(record.groupName, "Dynamic F-16 #1")
    expect.equal(record.coalition, 2)
    expect.equal(record.category, "plane")
    expect.equal(tracker.aliveCount("Dynamic F-16 #1"), 1)
end)

test("tracker.destroyUnit records the loss although DCS raises no event", function()
    local unit = Unit.getByName("Dynamic F-16 #1-1")
    tracker.destroyUnit(unit)
    expect.falsy(unit:isExist())
    expect.equal(tracker.aliveCount("Dynamic F-16 #1"), 0)
end)

test("marks get unique ids from the Tarmac range", function()
    local a = tarmac.marks.toCoalition(1, "a", { x = 0, y = 0, z = 0 })
    local b = tarmac.marks.toAll("b", { x = 0, y = 0, z = 0 })
    expect.truthy(b > a)
    expect.truthy(a >= tarmac.marks.firstId)
    expect.equal(#dcs.markErrors, 0)
    tarmac.marks.remove(a)
    expect.isNil(dcs.marks[a])
end)

test("player menus are built on birth and rebuilt without duplicates", function()
    local built = 0
    tarmac.menu.forPlayers(function(player)
        built = built + 1
        local root = missionCommands.addSubMenuForGroup(player.groupId, "Tools")
        missionCommands.addCommandForGroup(player.groupId, "Hello", root, function() end)
        return root
    end)
    local group = dcs.spawnPlayer("BlueStrike-1-1", "Hornet")
    expect.equal(built, 1)
    dcs.fire({ id = world.event.S_EVENT_BIRTH, initiator = group:getUnit(1) })
    expect.equal(built, 2)
    expect.same(dcs.menuPaths("group", group:getID()), { "Tools", "Tools/Hello" })
end)

test("AI births do not build player menus", function()
    local built = 0
    tarmac.menu.forPlayers(function() built = built + 1 end)
    expect.equal(built, 1, "built once for the player already in the mission")
    spawn.respawn("Tanks-1")
    expect.equal(built, 1)
end)

test("event objects that vanished do not raise errors", function()
    local unit = dcs.unit("Tanks-1-1")
    dcs.invalidate(unit)
    expect.isNil(tarmac.object.name(unit))
    expect.isNil(tarmac.object.point(unit))
    dcs.fire({ id = world.event.S_EVENT_UNIT_LOST, initiator = unit })
end)
