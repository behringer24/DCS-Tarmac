--- Event bus on top of world.addEventHandler.
--   events.on("UNIT_LOST", function(event) ... end)
--   events.on(world.event.S_EVENT_BIRTH, fn)
-- Names without the S_EVENT_ prefix are accepted. Names that are not DCS
-- events are custom events, raised with events.emit(name, payload).
-- Every handler runs protected: an error is logged and the other handlers
-- still receive the event.

local Log = require("tarmac.log")

local log = Log.new("tarmac.events")

local events = {}

local subscribers = {}
local registered = false

local function resolve(name)
    if type(name) == "number" then
        return name
    end
    if type(name) ~= "string" then
        error("event name expected, got " .. type(name), 3)
    end
    return world.event[name] or world.event["S_EVENT_" .. name] or name
end

local function dispatch(key, payload)
    local list = subscribers[key]
    if list == nil then
        return
    end
    -- iterate over a snapshot, handlers may subscribe or unsubscribe
    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end
    for i = 1, #snapshot do
        local subscription = snapshot[i]
        if not subscription.removed then
            local ok, err = xpcall(function()
                subscription.fn(payload)
            end, function(e)
                return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
            end)
            if not ok then
                local name = type(key) == "number" and events.nameOf(key) or tostring(key)
                log:error("handler for event %s failed: %s", name, err)
            end
        end
    end
end

local handler = {}

function handler:onEvent(event)
    if event ~= nil and event.id ~= nil then
        dispatch(event.id, event)
    end
end

--- Subscribes fn to an event. Returns a subscription for events.off.
function events.on(name, fn)
    local key = resolve(name)
    if type(key) == "number" and not registered then
        world.addEventHandler(handler)
        registered = true
    end
    local subscription = { key = key, fn = fn }
    subscribers[key] = subscribers[key] or {}
    table.insert(subscribers[key], subscription)
    return subscription
end

function events.off(subscription)
    local list = subscribers[subscription.key]
    if list == nil then
        return
    end
    subscription.removed = true
    for i = #list, 1, -1 do
        if list[i] == subscription then
            table.remove(list, i)
        end
    end
end

--- Raises a custom event (or replays a DCS event) to all subscribers.
function events.emit(name, payload)
    dispatch(resolve(name), payload)
end

--- Name of a DCS event id ("UNIT_LOST"), for logging.
function events.nameOf(id)
    for name, value in pairs(world.event) do
        if value == id then
            return (name:gsub("^S_EVENT_", ""))
        end
    end
    return tostring(id)
end

return events
