--- Safe accessors for DCS objects. Event initiators and targets may already
-- be gone when an event is handled; calling a method on such an object
-- raises an error in DCS. These helpers return nil instead.

local object = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

--- Calls obj:method(...) and returns its results, or nil if obj is missing,
-- has no such method or the call fails.
function object.call(obj, method, ...)
    if obj == nil then
        return nil
    end
    local ok, fn = pcall(function() return obj[method] end)
    if not ok or type(fn) ~= "function" then
        return nil
    end
    local results = pack(pcall(fn, obj, ...))
    if not results[1] then
        return nil
    end
    return unpack(results, 2, results.n)
end

function object.name(obj) return object.call(obj, "getName") end
function object.typeName(obj) return object.call(obj, "getTypeName") end
function object.coalition(obj) return object.call(obj, "getCoalition") end
function object.country(obj) return object.call(obj, "getCountry") end
function object.life(obj) return object.call(obj, "getLife") end
function object.desc(obj) return object.call(obj, "getDesc") end
function object.group(obj) return object.call(obj, "getGroup") end

--- Name of the player controlling the unit, or nil for AI.
function object.playerName(obj)
    local name = object.call(obj, "getPlayerName")
    if name == "" then
        return nil
    end
    return name
end

--- Unit category from the descriptor (Unit.Category.*), or nil.
function object.unitCategory(obj)
    local desc = object.desc(obj)
    return desc and desc.category
end

--- True for airplanes and helicopters.
function object.isAircraft(obj)
    local category = object.unitCategory(obj)
    return category == Unit.Category.AIRPLANE or category == Unit.Category.HELICOPTER
end

--- Name of the unit's group, or nil.
function object.groupName(obj)
    return object.name(object.group(obj))
end

--- Position as Vec3, or nil.
function object.point(obj)
    local point = object.call(obj, "getPoint")
    if point then
        return point
    end
    local position = object.call(obj, "getPosition")
    return position and position.p
end

--- True if the object still exists in the world.
function object.exists(obj)
    return object.call(obj, "isExist") == true
end

--- Destroys the object if it still exists. Returns true on success.
function object.destroy(obj)
    if not object.exists(obj) then
        return false
    end
    return pcall(obj.destroy, obj)
end

return object
