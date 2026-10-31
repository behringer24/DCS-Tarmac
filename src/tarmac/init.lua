--- DCS Tarmac - a scripting foundation for DCS World missions.
--
-- Loaded on its own (dist/tarmac.lua) it creates the global "tarmac".
-- Bundled into another script it first looks for an already loaded,
-- compatible Tarmac and reuses it, so a mission never runs two copies side
-- by side. Scripts that bundle Tarmac should therefore only ever
-- require("tarmac") and reach the parts through the returned table.

local VERSION = "0.1.0"

local function parseVersion(version)
    local major, minor, patch = tostring(version):match("^(%d+)%.(%d+)%.(%d+)")
    return tonumber(major), tonumber(minor), tonumber(patch)
end

-- An instance can replace this one if it has the same major version (and
-- the same minor version while in 0.x) and is at least as new.
local function compatible(version)
    local major, minor, patch = parseVersion(version)
    local wantMajor, wantMinor, wantPatch = parseVersion(VERSION)
    if major == nil or major ~= wantMajor then
        return false
    end
    if major == 0 and minor ~= wantMinor then
        return false
    end
    if minor ~= wantMinor then
        return minor > wantMinor
    end
    return patch >= wantPatch
end

local existing = rawget(_G, "tarmac")
if type(existing) == "table" and compatible(existing.version) then
    return existing
end
if existing ~= nil then
    env.warning(string.format("[tarmac] loaded Tarmac %s is not compatible with %s, using a private copy",
        tostring(type(existing) == "table" and existing.version), VERSION), false)
end

local tarmac = {
    version = VERSION,
    log = require("tarmac.log"),
    util = require("tarmac.util"),
    side = require("tarmac.side"),
    object = require("tarmac.object"),
    scheduler = require("tarmac.scheduler"),
    events = require("tarmac.events"),
    db = require("tarmac.db"),
    tracker = require("tarmac.tracker"),
    spawn = require("tarmac.spawn"),
    marks = require("tarmac.marks"),
    menu = require("tarmac.menu"),
}

if existing == nil then
    _G.tarmac = tarmac
end

env.info("[tarmac] Tarmac " .. VERSION .. " loaded", false)

return tarmac
