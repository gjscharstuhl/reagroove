-- ============================================================
-- gjs - x - control.lua
-- Main entry point
-- ============================================================

reaper.SetExtState("GJS_X", "Page", "1", true)

------------------------------------------------------------
-- Global include()
------------------------------------------------------------

_G.__modules = {}
_G.__include_cache = {}
_G.include = function(file)

    if __include_cache[file] then
        return __include_cache[file]
    end

    local caller = debug.getinfo(2, "S").source:sub(2)
    local dir = caller:match("(.*[\\/])") or ""
    local path = dir .. file

    local ok, module = pcall(dofile, path)

    if not ok then
        reaper.ShowMessageBox(
            "Error loading:\n\n" ..
            path ..
            "\n\n" ..
            tostring(module),
            "Launchpad X",
            0
        )
        return nil
    end

    __include_cache[file] = module

    return module

end

------------------------------------------------------------
-- Modules
------------------------------------------------------------

local bridge = include("gjs - x - bridge.lua")
if not bridge then return end
bridge.init()

_G.GJS_X_BRIDGE = bridge

local transport = include("gjs - x - transport.lua")
if not transport then return end
_G.GJS_X_TRANSPORT = transport

local pattern = include("gjs - x - pattern.lua")
if not pattern then return end
_G.GJS_X_PATTERN = pattern

local core = include("gjs - x - core.lua")
if not core then return end

------------------------------------------------------------
-- Screens
------------------------------------------------------------

local screens = {}

for screen = 0, 7 do

    local module = include(
        string.format("gjs - x - screen%d.lua", screen)
    )

    if not module then
        return
    end

    screens[screen] = module

end

------------------------------------------------------------
-- Start
------------------------------------------------------------

core.start(screens)
