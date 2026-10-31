--- Small helpers for tables, strings and coordinates.

local util = {}

--- Recursive copy of a table (shared sub-tables stay shared in the copy).
function util.deepCopy(value, seen)
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
        copy[util.deepCopy(k, seen)] = util.deepCopy(v, seen)
    end
    return setmetatable(copy, getmetatable(value))
end

--- Returns a new table with the values of overrides merged into a copy of
-- defaults. Nested tables are merged recursively.
function util.merge(defaults, overrides)
    local result = util.deepCopy(defaults or {})
    for k, v in pairs(overrides or {}) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = util.merge(result[k], v)
        else
            result[k] = util.deepCopy(v)
        end
    end
    return result
end

--- Sorted list of the keys of a table.
function util.keys(t)
    local list = {}
    for k in pairs(t) do
        list[#list + 1] = k
    end
    table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
    return list
end

function util.count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

function util.startsWith(text, prefix)
    return type(text) == "string" and type(prefix) == "string" and prefix ~= ""
        and text:sub(1, #prefix) == prefix
end

--- Rounds to the given number of decimals (0 by default).
function util.round(value, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(value * factor + 0.5) / factor
end

--- Converts a point to Vec2 {x, y}. Accepts Vec3 {x, y = altitude, z} and Vec2.
function util.vec2(point)
    if point.z ~= nil then
        return { x = point.x, y = point.z }
    end
    return { x = point.x, y = point.y }
end

--- Converts a point to Vec3 {x, y = altitude, z}. A Vec2 gets the terrain
-- height (plus the optional altitude above ground).
function util.vec3(point, altitude)
    if point.z ~= nil then
        return { x = point.x, y = point.y, z = point.z }
    end
    local height = land.getHeight({ x = point.x, y = point.y })
    return { x = point.x, y = height + (altitude or 0), z = point.y }
end

--- Horizontal distance between two points (Vec2 or Vec3).
function util.distance2D(a, b)
    local p, q = util.vec2(a), util.vec2(b)
    local dx, dy = p.x - q.x, p.y - q.y
    return math.sqrt(dx * dx + dy * dy)
end

local function splitDegrees(value, decimals)
    local degrees = math.floor(value)
    local minutes = util.round((value - degrees) * 60, decimals)
    if minutes >= 60 then
        degrees = degrees + 1
        minutes = minutes - 60
    end
    return degrees, minutes
end

--- Formats latitude/longitude as degrees and decimal minutes, e.g.
-- "N 41°49.123' E 041°47.456'".
function util.formatLatLon(lat, lon, decimals)
    decimals = decimals or 3
    local latDeg, latMin = splitDegrees(math.abs(lat), decimals)
    local lonDeg, lonMin = splitDegrees(math.abs(lon), decimals)
    local minuteFormat = "%0" .. (decimals > 0 and decimals + 3 or 2) .. "." .. decimals .. "f"
    return string.format("%s %02d°" .. minuteFormat .. "' %s %03d°" .. minuteFormat .. "'",
        lat >= 0 and "N" or "S", latDeg, latMin, lon >= 0 and "E" or "W", lonDeg, lonMin)
end

--- Formats a map point (Vec2 or Vec3) as latitude/longitude.
function util.formatPoint(point, decimals)
    local lat, lon = coord.LOtoLL(util.vec3(point))
    return util.formatLatLon(lat, lon, decimals)
end

return util
