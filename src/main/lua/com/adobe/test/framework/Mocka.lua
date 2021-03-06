--
-- Created by IntelliJ IDEA.
-- User: trifan
-- Date: 08/01/17
-- Time: 11:30
-- To change this template use File | Settings | File Templates.
--

-- save original require in order to alter it
oldRequire = require

-- object to that keeps the track of mocks for testing
local mocks = {}

-- spy objects
local spies = {}

local lazy_spies = {}

local mirror = {}

-- before each function rememberer
local beforeFn;

-- stats for the framework needed for outputing results
mockaStats = {
    suites = {},
    no = 0,
    noOK = 0,
    noNOK = 0,
    noIgnored = 0,
    time = 0
}

function resetStats()
    mockaStats = {
        suites = {},
        no = 0,
        noOK = 0,
        noNOK = 0,
        noIgnored = 0,
        time = 0
    }
end

---
-- @param t1 {object}
-- @param t2 {object}
-- This function compares two objects that can be dictionaries , arrays, strings anything. For dictionaries
-- it goes in depth making a recursive call. The most important thing is that the two parameters of the functions
-- are identical in type
---
local function _compare(t1, t2)
    local ty1 = type(t1)
    local ty2 = type(t2)
    if ty1 ~= ty2 then return false end
    -- non-table types can be directly compared
    if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
    -- as well as tables which have the metamethod __eq
    local mt = getmetatable(t1)
    if not ignore_mt and mt and mt.__eq then return t1 == t2 end
    for k1, v1 in pairs(t1) do
        local v2 = t2[k1]
        if v2 == nil or not _compare(v1, v2) then return false end
    end
    for k2, v2 in pairs(t2) do
        local v1 = t1[k2]
        if v1 == nil or not _compare(v1, v2) then return false end
    end
    return true
end

---
-- @param name {string} - name of the function that we want to make
-- @param classToMock {string} - name of the class we are making the function for
-- Internal function - not to be used. This function creates a function with all the needed internals: calls, latestCallWith
-- it also creates a real new function if specified. On call the function increments it's internals (calls) and saves
-- the latestCallWithArguments. Also if present and a doReturn has been declared by a user than that function will be called
-- with those parameters.
local function _makeFunction(name, classToMock)
    return function(self, ...)
        classToMock["__" .. name]['calls'] = classToMock["__" .. name]['calls'] + 1
        local callingArguments = { ... }
        table.insert(callingArguments, self)
        classToMock["__" .. name]['latestCallWith'] = callingArguments
        if name == 'new' and classToMock["__" .. name].doReturn == nil then
            local o = callingArguments or {}
            setmetatable(o, self)
            self.__index = self
            return o
        elseif classToMock["__" .. name].doReturn ~= nil then
            return classToMock["__" .. name].doReturn(self, ...)
        end
    end
end

---
-- Retrieves current run information
-- @return {currentSuiteNumber, currentSuiteInfo, currentTestNumber, currentTestInfo}
---
local function getCurrentRunInfo()
    local currentSuiteNumber = #mockaStats.suites;
    local currentSuiteInfo = mockaStats.suites[currentSuiteNumber];
    local currentTestNumber = #currentSuiteInfo.tests;
    local currentTestInfo = currentSuiteInfo.tests[currentTestNumber];
    return currentSuiteNumber, currentSuiteInfo, currentTestNumber, currentTestInfo
end


--- Makes a shallow copy
-- @param t object - the object to clone
--
local function _clone (t) -- shallow-copy
    if type(t) ~= "table" then return t end
    local meta = getmetatable(t)
    local target = {}
    for k, v in pairs(t) do target[k] = v end
    setmetatable(target, meta)
    return target
end

---
-- @param class - full fledged class as you see it in the require
-- Public function used only in before each - to spy on an object - (stub the replacement)
--
local function _makeDoReturnFunction(obj)
    return function(fn)
        obj.doReturn = fn
    end
end

local function __makeSpy(path)
    if path and not mirror[path] then
        return
    end

    if path then
        for method, impl in pairs(mirror[path]) do
            --- put all but not privates line __index
            -- TODO: maybe in the future I can index private methods
            if impl ~= nil and type(impl) == 'function'
                    and not string.find(method, "__") then
                spies[path]["__" .. method] = {
                    calls = 0,
                    name = path .. "." .. method,
                    latestCallWith = nil,
                    doReturn = impl
                }
                spies[path][method] = _makeFunction(method, spies[path])
            end
        end
    end

    if not path then
        for k, v in pairs(mirror) do
            if type(v) == 'table' then
                for method, impl in pairs(v) do
                    --- put all but not privates line __index
                    -- TODO: maybe in the future I can index private methods
                    if impl ~= nil and type(impl) == 'function'
                            and not string.find(method, "__") then
                        spies[k]["__" .. method] = {
                            calls = 0,
                            name = k .. "." .. method,
                            latestCallWith = nil,
                            doReturn = impl
                        }
                        spies[k][method] = _makeFunction(method, spies[k])
                    end
                end
            end
        end
    end
end

--- Converts a table to a string
-- @param v table
local function valToString(v)
    local vType = type(v)
    if vType == 'table' then
        return table.tostring(v)
    end
    return tostring(v)
end

---
-- Spy utility method that creates a spy. Also returns the spy object when available
-- @param class - the path as passed to require
-- @param method - the method for stub
-- @param fn - the callback to execute - the actual stub
--
function spy(class, method, fn)
    -- if it isn't alredy required and not yet set for lazy
    if not mirror[class] then
        if not lazy_spies[class] then
            lazy_spies[class] = {}
        end
        lazy_spies[class][method] = {
            ["class"] = class,
            ["method"] = method,
            ["fn"] = fn
        }
        return
    end


    local mapObj = {}

    for method, method_real in pairs(mirror[class]) do
        -- don't index private methods
        -- TODO: maybe in the future I can index private methods
        if not string.find(method, "__") and type(method_real) == 'function' then
            mapObj[method] = spies[class]["__" .. method]
            mapObj[method]["stub"] = _makeDoReturnFunction(spies[class]["__" .. method])
        end
    end

    if method and fn then
        mapObj[method].doReturn = fn
    end

    return mapObj
end


---
-- @param path {string} - path to require
-- Alters the real require to server either mock or real lua file - has same signature like lua require
-- we force the reload of the package due to the beforeEach and the nature of mocking which gives us
-- the possibility to make a function do something else for each test
---
require = function(path)
    --some people require os | string | table  -> natural functions(globals)
    if path == 'os' then
        return os
    elseif path == 'string' then
        return string
    elseif path == 'table' then
        return table
    elseif path == "ffi" then
        return oldRequire("ffi")
    end

    --wanna force reload the package
    package.loaded[path] = nil
    if (mocks[path] ~= nil) then
        return mocks[path]
    else
        if spies[path] then
            return spies[path]
        end

        spies[path] = oldRequire(path)
        mirror[path] = _clone(spies[path])
        -- this means that the require has been done and now it's the time to init any lazy spy
        if lazy_spies[path] then
            __makeSpy(path)
            for method, info in pairs(lazy_spies[path]) do
                spy(info.class, info.method, info.fn)
            end
            lazy_spies[path] = nil
        end
        return spies[path]
    end
end


---
-- @param fn {function} - the function to be ran beforeEach Test
-- Saves the function in a variable in order to call it before each test for a suite
---
function beforeEach(fn)
    beforeFn = fn
end

---
-- @param description  {string}
-- @param ... {optional}
-- This method is used to ignore a test and records that a test has been ignored for the final report
---
function xtest(description, ...)
    table.insert(mockaStats.suites[#mockaStats.suites].tests, {
        assertions = 0,
        name = description:gsub("\"", "&quot;"),
        className = mockaStats.suites[#mockaStats.suites].name,
        time = 0,
        failureMessage = nil,
        skipped = true,
        failureTrace = nil
    });
    local sn, si, tn, ti = getCurrentRunInfo()
    si.noIgnored = si.noIgnored + 1
    mockaStats.noIgnored = mockaStats.noIgnored + 1
    si.no = si.no + 1
    mockaStats.no = mockaStats.no + 1;
    print("\t\t " .. description .. " -- IGNORED")
end

---
-- @param description {string} - description of the test
-- @param fn {function} - actual function that describes the test (logic of the test)
-- @param assertFail {boolean} - specifing that I expect this test to fail - ussualy used for methods that throw errors
-- This is the method used to specify to the framework that we want to run a test. Resets
-- the mocks to the original state - no calls no return no latestCall, executes the beforeEach function if any
-- than runs the test logic and counts if the test has failed or succeeded + duration.
---
function test(description, fn, assertFail)
    table.insert(mockaStats.suites[#mockaStats.suites].tests, {
        assertions = 0,
        name = description:gsub("\"", "&quot;"),
        className = mockaStats.suites[#mockaStats.suites].name,
        time = 0,
        failureMessage = nil,
        skipped = false,
        failureTrace = nil
    });

    for k, v in pairs(mocks) do
        for method, impl in pairs(v) do
            if impl ~= nil and type(impl) == 'table' and impl.calls then
                impl.calls = 0
                impl.latestCallWith = nil
                impl.doReturn = nil
            end
        end
    end

    __makeSpy()

    if (beforeFn ~= nil) then
        pcall(beforeFn)
    end

    local sn, si, tn, ti = getCurrentRunInfo()

    local startTime = os.clock()
    local status, result = pcall(fn)
    local elapsed = os.clock() - startTime

    ti.time = elapsed

    if not status and not assertFail then
        print("\t\t " .. description .. " ----- FAIL ")
        local callingFunction = debug.getinfo(2)
        print(string.format("%s in %s : %s", result, callingFunction.short_src,
            callingFunction.currentline))
        mockaStats.noNOK = mockaStats.noNOK + 1;
        si.noNOK = si.noNOK + 1
    else
        print("\t\t " .. description .. " ----- SUCCESS ")
        mockaStats.noOK = mockaStats.noOK + 1;
        si.noOK = si.noOK + 1
    end
    mockaStats.no = mockaStats.no + 1;
    si.no = si.no + 1
end

---
-- @param class {string} name of the path to mock - this is the actual string that you give to require
-- @param model {array} - an array of strings specifying which are the methods that we want to mock
-- This function creates a mock class with the functions you provide in the model. Each of the functions have an
-- internal representation like so: doSomething is mapped to __doSomething. By default a function does not do anything
-- it just records the calls and the latest call arguments.
-- The internal representation contain info about the number of calls the real name of the function, latestCallArguments
-- and has a doReturn function. The doReturn function is normally used if you want a mocked function to do something.
-- Example:
-- local classToMock = mock("class", {"doSomething"})
-- classToMock.__doSomething.doReturn = function()
--      return 23
-- end
function mock(class, model)
    local newThing = {}
    model = model or {}
    if table.maxn(model) == 0 then
        local status, clsToMock = pcall(oldRequire, class)
        if status then
            for k, v in pairs(clsToMock) do
                table.insert(model, k)
            end
        end
    end

    for i, method in ipairs(model or {}) do
        newThing["__" .. method] = {
            calls = 0,
            name = class .. "." .. method,
            latestCallWith = nil,
            doReturn = nil
        }
        newThing[method] = _makeFunction(method, newThing)
    end


    mocks[class] = newThing
    return newThing
end

---
-- @param mockClass - the mock object
-- Public function that decorates mock objects with the call that is needed
--
function when(mockClass)
    local mapObj = {}
    for k, v in pairs(mockClass) do
        if string.sub(k, 1, 2) == "__" then
            local replacement, number = string.gsub(k, "__", "", 1)
            mapObj[replacement] = v
            mapObj[replacement]["fake"] = _makeDoReturnFunction(mockClass[k])
        end
    end
    return mapObj
end


---
-- @param method {function} - the actual internal representation class.__internalMethod
-- @param times {number} - the number of times a function was invoked
-- @param ... {array} [optional] - array of arguments. There is a numbering problem always start with the second argument,
-- for example if we call a function with a, b, c than the arguments would be b, c, a (always the first argument becomes
-- last.
-- This method verifies that a method has been called a number of times with some arguments if present
--
function calls(method, times, ...)
    local errorMessage
    local sn, si, tn, ti = getCurrentRunInfo()
    ti.assertions = ti.assertions + 1

    if (method.calls ~= times) then
        errorMessage = method.name .. " wanted " .. times .. " but invoked " .. method.calls
        ti.failureMessage = errorMessage
        error(errorMessage)
    end

    local arguments = { ... }

    for k, v in pairs(arguments) do
        if k ~= 'n' then
            if not _compare(method.latestCallWith[k], v) then
                errorMessage = method.name .. " wanted with some arguments but invoked with other "
                ti.failureMessage = errorMessage
                error(errorMessage)
            end
        end
    end
end


-- utility functions
-- http://lua-users.org/wiki/TableUtils

function table.val_to_str(v)
    if "string" == type(v) then
        v = string.gsub(v, "\n", "\\n")
        if string.match(string.gsub(v, "[^'\"]", ""), '^"+$') then
            return "'" .. v .. "'"
        end
        return '"' .. string.gsub(v, '"', '\\"') .. '"'
    else
        return "table" == type(v) and table.tostring(v) or
                tostring(v)
    end
end

function table.key_to_str(k)
    if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
        return k
    else
        return "[" .. table.val_to_str(k) .. "]"
    end
end

function table.tostring(tbl)
    local result, done = {}, {}
    for k, v in ipairs(tbl) do
        table.insert(result, table.val_to_str(v))
        done[k] = true
    end
    for k, v in pairs(tbl) do
        if not done[k] then
            table.insert(result,
                table.key_to_str(k) .. "=" .. table.val_to_str(v))
        end
    end
    return "{" .. table.concat(result, ",") .. "}"
end


-- assertions

function assertEquals(t1, t2)
    local errorMessage = "assertEquals failed: expected [%s], was [%s]"
    local sn, si, tn, ti = getCurrentRunInfo()
    ti.assertions = ti.assertions + 1
    if not _compare(t1, t2) then
        ti.failureMessage = string.format(errorMessage, valToString(t2), valToString(t1))
        error(ti.failureMessage)
    end
end

function assertNil(t1)
    local errorMessage = "assertNil failed: expected nil, was [%s]"
    local sn, si, tn, ti = getCurrentRunInfo()
    ti.assertions = ti.assertions + 1
    if t1 ~= nil then
        ti.failureMessage = string.format(errorMessage, valToString(t1))
        error(ti.failureMessage)
    end
end

function assertNotNil(t1)
    local errorMessage = "assertNotNil failed";
    local sn, si, tn, ti = getCurrentRunInfo()
    ti.assertions = ti.assertions + 1
    if t1 == nil then
        ti.failureMessage = errorMessage
        error(errorMessage)
    end
end

function assertNotEquals(t1, t2)
    local errorMessage = "assertNotEquals failed"
    local sn, si, tn, ti = getCurrentRunInfo()
    ti.assertions = ti.assertions + 1
    if _compare(t1, t2) then
        ti.failureMessage = errorMessage
        error(errorMessage)
    end
end

--- should be here because of using global mocka definitions
local default_mocks = require("mocka.default_mocks")

function mockNgx(conf)
    if not conf then
        ngx = default_mocks.makeNgxMock()
    else
        ngx =  conf
    end
end

function clearMocks(inNgx)
    mocks = {}
    if not inNgx then
        ngx = default_mocks.makeNgxMock()
    end
end
