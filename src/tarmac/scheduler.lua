--- Error-safe wrapper around timer.scheduleFunction.
--   scheduler.after(5, fn, a, b)        run fn(a, b) once in 5 seconds
--   local task = scheduler.every(60, fn) run fn every 60 seconds
--   task:cancel()
-- A repeating function stops when it returns false. Errors are logged with
-- a traceback and do not stop a repeating task.

local Log = require("tarmac.log")

local log = Log.new("tarmac.scheduler")

local scheduler = {}

local Task = {}
Task.__index = Task

function Task:cancel()
    self.cancelled = true
    if self.id then
        pcall(timer.removeFunction, self.id)
        self.id = nil
    end
end

local function run(task)
    local ok, result = xpcall(function()
        return task.fn(unpack(task.args, 1, task.args.n))
    end, function(err)
        return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
    end)
    if not ok then
        log:error("task '%s' failed: %s", task.name, result)
    end
    return ok, result
end

local function newTask(fn, name, ...)
    return setmetatable({ fn = fn, name = name or tostring(fn), args = { n = select("#", ...), ... } }, Task)
end

--- Runs fn(...) once after delay seconds. Returns a task that can be cancelled.
function scheduler.after(delay, fn, ...)
    local task = newTask(fn, nil, ...)
    task.id = timer.scheduleFunction(function()
        task.id = nil
        if not task.cancelled then
            run(task)
        end
        return nil
    end, nil, timer.getTime() + math.max(delay, 0))
    return task
end

--- Runs fn() every interval seconds. Options:
--   delay  seconds until the first run (default: interval)
--   name   used in error messages
function scheduler.every(interval, fn, options)
    options = options or {}
    local task = newTask(fn, options.name)
    task.interval = interval
    task.id = timer.scheduleFunction(function(_, time)
        if task.cancelled then
            return nil
        end
        local ok, result = run(task)
        if task.cancelled or (ok and result == false) then
            task.id = nil
            return nil
        end
        return time + task.interval
    end, nil, timer.getTime() + math.max(options.delay or interval, 0))
    return task
end

return scheduler
