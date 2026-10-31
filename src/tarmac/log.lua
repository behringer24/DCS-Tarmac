--- Prefixed logging to dcs.log.
-- Usage:
--   local log = Log.new("industry.economy")
--   log:info("added %d tons for %s", tons, name)
-- Arguments are converted defensively, so a nil value never breaks a log
-- call (string.format in Lua 5.1 rejects nil for %s).

local Log = {}
Log.__index = Log

local levels = { debug = 1, info = 2, warn = 3, error = 4 }

--- Minimum level written by all loggers ("debug", "info", "warn", "error").
Log.level = "info"

function Log.new(prefix)
    return setmetatable({ prefix = prefix }, Log)
end

local function safeArgs(...)
    local args = { n = select("#", ...), ... }
    for i = 1, args.n do
        local kind = type(args[i])
        if kind ~= "number" and kind ~= "string" then
            args[i] = tostring(args[i])
        end
    end
    return args
end

--- Formats like string.format but never raises an error.
function Log.format(fmt, ...)
    if select("#", ...) == 0 then
        return tostring(fmt)
    end
    local args = safeArgs(...)
    local ok, text = pcall(string.format, tostring(fmt), unpack(args, 1, args.n))
    if ok then
        return text
    end
    local parts = {}
    for i = 1, args.n do
        parts[i] = tostring(args[i])
    end
    return tostring(fmt) .. " [" .. table.concat(parts, ", ") .. "]"
end

function Log:write(level, fmt, ...)
    if levels[level] < (levels[Log.level] or 2) then
        return
    end
    local text = "[" .. self.prefix .. "] " .. Log.format(fmt, ...)
    if level == "error" then
        env.error(text, false)
    elseif level == "warn" then
        env.warning(text, false)
    else
        env.info(text, false)
    end
end

function Log:debug(fmt, ...) self:write("debug", fmt, ...) end
function Log:info(fmt, ...) self:write("info", fmt, ...) end
function Log:warn(fmt, ...) self:write("warn", fmt, ...) end
function Log:error(fmt, ...) self:write("error", fmt, ...) end

return Log
