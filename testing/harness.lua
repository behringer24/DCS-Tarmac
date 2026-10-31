-- Minimal test harness for "tarmac test". It runs inside the Go test runner
-- (gopher-lua, Lua 5.1), never inside DCS.
--
-- A test file registers cases with test(name, fn), usually after preparing
-- a mission with dcs.start() and loading the bundle with loadBundle().

local config = __TARMAC
local dofile, print, xpcall, pairs, ipairs = dofile, print, xpcall, pairs, ipairs
local tostring, type, error, select = tostring, type, error, select
local traceback = debug.traceback

local cases = {}

function test(name, fn)
    cases[#cases + 1] = { name = name, fn = fn }
end

local function describe(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

local function deepEqual(a, b, seen)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    seen = seen or {}
    if seen[a] == b then
        return true
    end
    seen[a] = b
    for k, v in pairs(a) do
        if not deepEqual(v, b[k], seen) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function fail(message, default)
    error(message and (message .. ": " .. default) or default, 3)
end

expect = {}

function expect.equal(actual, expected, message)
    if actual ~= expected then
        fail(message, "expected " .. describe(expected) .. ", got " .. describe(actual))
    end
end

function expect.same(actual, expected, message)
    if not deepEqual(actual, expected) then
        fail(message, "tables differ")
    end
end

function expect.truthy(value, message)
    if not value then
        fail(message, "expected a truthy value, got " .. describe(value))
    end
end

function expect.falsy(value, message)
    if value then
        fail(message, "expected a falsy value, got " .. describe(value))
    end
end

function expect.isNil(value, message)
    if value ~= nil then
        fail(message, "expected nil, got " .. describe(value))
    end
end

function expect.notNil(value, message)
    if value == nil then
        fail(message, "expected a value, got nil")
    end
end

function expect.contains(haystack, needle, message)
    if type(haystack) == "string" then
        if not haystack:find(needle, 1, true) then
            fail(message, describe(haystack) .. " does not contain " .. describe(needle))
        end
        return
    end
    for _, v in pairs(haystack) do
        if v == needle then
            return
        end
    end
    fail(message, "table does not contain " .. describe(needle))
end

function expect.fails(fn, pattern, message)
    local ok, err = pcall(fn)
    if ok then
        fail(message, "expected an error")
    end
    if pattern and not tostring(err):find(pattern) then
        fail(message, "error " .. describe(tostring(err)) .. " does not match " .. describe(pattern))
    end
end

-- Remove what DCS removes in MissionScripting.lua, then forbid the creation
-- of unexpected globals so that leaking variables are caught by the tests.
local function sanitizeAndProtect()
    os, io, lfs, require, package, loadlib = nil, nil, nil, nil, nil, nil

    local allowed = {}
    for _, name in ipairs(config.globals or {}) do
        allowed[name] = true
    end
    setmetatable(_G, {
        __newindex = function(t, key, value)
            if not allowed[key] then
                error("assignment to undeclared global '" .. tostring(key) .. "'", 2)
            end
            rawset(t, key, value)
        end,
        __index = function(_, key)
            error("read of undeclared global '" .. tostring(key) .. "'", 2)
        end,
    })
end

local bundleLoaded = false

-- Loads the bundle like a DCS "DO SCRIPT FILE" action would.
function loadBundle()
    if bundleLoaded then
        error("loadBundle() called twice", 2)
    end
    bundleLoaded = true
    sanitizeAndProtect()
    dofile(config.bundle)
end

-- Called by the Go runner after the test file has been executed.
function __tarmac_run()
    local passed, failed = 0, 0
    for _, case in ipairs(cases) do
        local logStart = #dcs.logs + 1
        local ok, err = xpcall(case.fn, function(e)
            return traceback(tostring(e), 2)
        end)
        if ok then
            passed = passed + 1
            print("  ok   " .. case.name)
        else
            failed = failed + 1
            print("  FAIL " .. case.name)
            print("       " .. tostring(err):gsub("\n", "\n       "))
        end
        if config.verbose or not ok then
            for i = logStart, #dcs.logs do
                print("       | " .. dcs.logs[i])
            end
        end
    end
    return passed, failed
end
