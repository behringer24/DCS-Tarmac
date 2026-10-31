--- F10 radio menus for player groups, including dynamic slots. Menus are
-- built when a player unit is born, so groups that do not exist at mission
-- start get them too.
--   menu.forPlayers(function(player)
--       local root = missionCommands.addSubMenuForGroup(player.groupId, "Industry")
--       missionCommands.addCommandForGroup(player.groupId, "Statistics", root, show, player.groupId)
--       return root
--   end)
-- The builder receives { groupId, groupName, unitName, coalition, playerName }
-- and returns the root path it created; the menu is rebuilt (old one removed)
-- on every birth in the group, so menus never show up twice.

local Log = require("tarmac.log")
local events = require("tarmac.events")
local object = require("tarmac.object")

local log = Log.new("tarmac.menu")

local menu = {}

local builders = {}

local function build(entry, unit)
    local group = object.group(unit)
    local groupId = object.call(group, "getID")
    if groupId == nil then
        return
    end
    local player = {
        groupId = groupId,
        groupName = object.name(group),
        unitName = object.name(unit),
        coalition = object.coalition(unit),
        playerName = object.playerName(unit),
    }
    local previous = entry.paths[groupId]
    if previous then
        missionCommands.removeItemForGroup(groupId, previous)
    end
    local ok, path = pcall(entry.builder, player)
    if not ok then
        log:error("menu builder failed for group %s: %s", player.groupName, path)
        return
    end
    entry.paths[groupId] = path
end

--- Registers a menu builder for all player groups (present and future).
function menu.forPlayers(builder)
    local entry = { builder = builder, paths = {} }
    builders[#builders + 1] = entry
    for _, coalitionId in ipairs({ 0, 1, 2 }) do
        for _, unit in ipairs(coalition.getPlayers(coalitionId) or {}) do
            build(entry, unit)
        end
    end
    return entry
end

events.on("BIRTH", function(event)
    local unit = event.initiator
    if object.playerName(unit) == nil then
        return
    end
    for _, entry in ipairs(builders) do
        build(entry, unit)
    end
end)

return menu
