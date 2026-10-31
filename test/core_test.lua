-- util, side, log, scheduler and events

dcs.start(fixture.mission())
loadBundle()

local util, side, scheduler, events = tarmac.util, tarmac.side, tarmac.scheduler, tarmac.events

test("bundle exposes the global tarmac with a version", function()
    expect.equal(type(tarmac), "table")
    expect.truthy(tarmac.version:match("^%d+%.%d+%.%d+$"))
end)

test("deepCopy copies nested tables", function()
    local source = { a = { b = { 1, 2 } } }
    local copy = util.deepCopy(source)
    copy.a.b[1] = 99
    expect.equal(source.a.b[1], 1)
    expect.same(util.deepCopy(source), source)
end)

test("merge keeps defaults and applies nested overrides", function()
    local merged = util.merge({ a = 1, nested = { b = 2, c = 3 } }, { nested = { c = 30 }, d = 4 })
    expect.same(merged, { a = 1, nested = { b = 2, c = 30 }, d = 4 })
end)

test("startsWith only matches at the beginning", function()
    expect.truthy(util.startsWith("HQ Red", "HQ"))
    expect.falsy(util.startsWith("RedHQ", "HQ"))
    expect.falsy(util.startsWith(nil, "HQ"))
end)

test("vec2 and vec3 convert between map and world coordinates", function()
    expect.same(util.vec2({ x = 1, y = 500, z = 2 }), { x = 1, y = 2 })
    expect.same(util.vec3({ x = 1, y = 2 }), { x = 1, y = 0, z = 2 })
end)

test("formatLatLon renders degrees and decimal minutes", function()
    expect.equal(util.formatLatLon(41.5, 41.25, 3), "N 41°30.000' E 041°15.000'")
    expect.equal(util.formatLatLon(-0.999999, -1.5, 1), "S 01°00.0' W 001°30.0'")
end)

test("side accepts names and ids", function()
    expect.equal(side.id("Blue"), 2)
    expect.equal(side.id(1), 1)
    expect.isNil(side.id(7))
    expect.equal(side.name(2), "blue")
    expect.equal(side.label("red"), "RED")
    expect.equal(side.enemy("red"), 2)
    expect.equal(side.enemy(0), 0)
end)

test("log.format survives nil, boolean and table arguments", function()
    expect.equal(tarmac.log.format("a %s b %s", nil, true), "a nil b true")
    expect.contains(tarmac.log.format("t=%s", {}), "table")
    expect.equal(tarmac.log.format("plain"), "plain")
end)

test("scheduler.after runs once with arguments", function()
    local calls = {}
    scheduler.after(5, function(a, b) calls[#calls + 1] = a + b end, 1, 2)
    dcs.advance(4)
    expect.equal(#calls, 0)
    dcs.advance(2)
    dcs.advance(10)
    expect.same(calls, { 3 })
end)

test("scheduler.every repeats, stops on false and can be cancelled", function()
    local runs = 0
    scheduler.every(10, function()
        runs = runs + 1
        return runs < 3
    end, { delay = 1 })
    dcs.advance(100)
    expect.equal(runs, 3)

    local ticks = 0
    local task = scheduler.every(10, function() ticks = ticks + 1 end)
    dcs.advance(25)
    task:cancel()
    dcs.advance(100)
    expect.equal(ticks, 2)
end)

test("scheduler keeps repeating after an error", function()
    local runs = 0
    scheduler.every(1, function()
        runs = runs + 1
        if runs == 1 then
            error("boom")
        end
    end, { delay = 0 })
    dcs.advance(3)
    expect.truthy(runs >= 3)
end)

test("events dispatch DCS and custom events and isolate errors", function()
    local seen = {}
    events.on("ENGINE_STARTUP", function() error("broken handler") end)
    local sub = events.on("S_EVENT_ENGINE_STARTUP", function(e) seen[#seen + 1] = e.initiator end)
    dcs.fire({ id = world.event.S_EVENT_ENGINE_STARTUP, initiator = "unit-1" })
    events.off(sub)
    dcs.fire({ id = world.event.S_EVENT_ENGINE_STARTUP, initiator = "unit-2" })
    expect.same(seen, { "unit-1" })

    local custom
    events.on("my.event", function(payload) custom = payload.value end)
    events.emit("my.event", { value = 42 })
    expect.equal(custom, 42)
    expect.equal(events.nameOf(world.event.S_EVENT_UNIT_LOST), "UNIT_LOST")
end)

test("a nil event does not break the handler", function()
    dcs.fire({ id = world.event.S_EVENT_BIRTH })
end)
