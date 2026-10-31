# DCS Tarmac
A scripting foundation for DCS World missions, written from scratch for the current DCS scripting API.

Tarmac keeps a copy of every group of the mission, so groups can be respawned exactly as they were placed in
the mission editor, tracks which units are alive, and wraps the DCS API in small, error-safe modules. It comes
with a build tool that bundles modular Lua sources into the single file a mission needs, and a test runner
with a DCS API mock, so scripts can be tested without starting DCS.

Status: **0.1 — experimental**, the API may still change.

## Use in a mission
Download `dist/tarmac.lua` and load it with a *DO SCRIPT FILE* action before your own scripts. It creates the
global `tarmac`. No changes to the DCS installation (`MissionScripting.lua`) are needed.

Scripts built with Tarmac (like [Industry Wars](https://github.com/behringer24/DCS-Industry)) contain their own
copy. If the mission loaded a compatible Tarmac before, they use that one instead, so a mission never runs two
copies side by side.

## Modules

| Module             | Purpose |
|--------------------|---------|
| `tarmac.db`        | Templates of all groups, units, statics and trigger zones read from `env.mission`; available after the objects died. Runtime spawns and unknown units (dynamic slots) are added. |
| `tarmac.tracker`   | Living units per group, driven by events. Raises `tarmac.groupDead` when the last unit of a group is lost; `isGone` tells whether DCS still has the group. |
| `tarmac.spawn`     | `respawn(name)` as placed in the editor, `clone(template, options)` under a new name, `add(category, country, data)`, waypoint script actions. |
| `tarmac.events`    | Event bus: `on("UNIT_LOST", fn)`, `off`, custom events with `emit`. Every handler runs protected. |
| `tarmac.scheduler` | `after(seconds, fn, ...)` and `every(seconds, fn, options)`; return `false` to stop, `task:cancel()`. Errors are logged with a traceback. |
| `tarmac.menu`      | F10 menus for player groups, built on birth, so dynamic slots get them too. |
| `tarmac.marks`     | F10 map marks with ids from a private range. |
| `tarmac.object`    | Safe accessors (`name`, `coalition`, `point`, `playerName`, ...) that return nil for vanished objects. |
| `tarmac.side`      | Coalition ids and names (`side.id("blue")`, `side.enemy(1)`). |
| `tarmac.util`      | Table helpers, Vec2/Vec3 conversion, latitude/longitude formatting. |
| `tarmac.log`       | Prefixed logging to `dcs.log` that never fails on nil arguments. |

```lua
local tarmac = tarmac -- or require("tarmac") inside a bundled script

tarmac.events.on("tarmac.groupDead", function(event)
    tarmac.scheduler.after(300, tarmac.spawn.respawn, event.groupName)
end)

tarmac.menu.forPlayers(function(player)
    local root = missionCommands.addSubMenuForGroup(player.groupId, "Hello")
    missionCommands.addCommandForGroup(player.groupId, "Wave", root, function()
        trigger.action.outTextForGroup(player.groupId, "Hello " .. tostring(player.playerName), 10)
    end)
    return root
end)
```

## Building your own script on Tarmac
Write your script as Lua modules (`src/myscript/init.lua`, `src/myscript/part.lua`, ...) that use
`require("mymodule")`. Reach Tarmac only through `require("tarmac")`, never through its submodules, so a
loaded Tarmac can be shared. Describe the project in a `tarmac.json`:

```json
{
  "entry": "myscript",
  "sources": ["src", "../DCS-Tarmac/src"],
  "output": "dist/myscript.lua",
  "banner": ["My script"],
  "test": {
    "dir": "test",
    "setup": ["../DCS-Tarmac/testing/dcs_mock.lua", "../DCS-Tarmac/testing/harness.lua",
              "../DCS-Tarmac/testing/fixture.lua"],
    "globals": ["myscript", "tarmac"]
  }
}
```

## The tarmac tool
Requires Go 1.23 or newer.

```bash
go install ./cmd/tarmac
tarmac build        # bundle all modules reachable from the entry into one file
tarmac check        # check every module for Lua 5.1 syntax (DCS has no goto or labels)
tarmac test [-v]    # build, then run test/*_test.lua
```

The bundle defines a private `require` and wraps every module in a function, so modules keep their locals
to themselves. Require cycles and missing modules are build errors.

### Tests
Tests run in an embedded Lua 5.1 VM ([gopher-lua](https://github.com/yuin/gopher-lua)). Before each test file
the runner loads `testing/dcs_mock.lua` (an in-memory DCS API), `testing/harness.lua` and
`testing/fixture.lua` (builders for mission tables). `loadBundle()` removes what DCS removes in
`MissionScripting.lua` (`os`, `io`, `lfs`, `require`, ...) and enables strict mode: creating or reading
undeclared globals fails the test.

```lua
local m = fixture.mission()
fixture.group(m, "red", country.id.RUSSIA, "vehicle", { name = "Tanks-1", units = { { type = "T-72B" } } })
dcs.start(m)
loadBundle()

test("a dead group can be respawned", function()
    dcs.kill("Tanks-1-1")
    expect.truthy(tarmac.tracker.isGone("Tanks-1"))
    expect.notNil(tarmac.spawn.respawn("Tanks-1"))
end)
```

The mock records messages, flags, marks, menus, smoke and spawned groups (`dcs.messages`, `dcs.flags`, ...)
and simulates time with `dcs.advance(seconds)`.

## License
GPL-3.0, see [LICENSE](LICENSE).
