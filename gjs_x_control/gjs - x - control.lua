-- ============================================================
-- gjs - x - control.lua
-- Main entry point
-- ============================================================

reaper.SetExtState("GJS_X", "Page", "1", true)

reaper.SetExtState("GJS_X", "ActiveTrack", "1", true)
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

-- External MIDI controller bridge. The MIDI-learn JSFX publishes learned
-- controller events to GJS_X_BRIDGE; this module consumes them every cycle.
local external_controller = include("gjs - x - external_controller.lua")
if not external_controller then return end
_G.GJS_X_EXTERNAL_CONTROLLER = external_controller

local core = include("gjs - x - core.lua")
if not core then return end
     
local trman = include("trackmanager.lua") 
                                                                                                                                                             
                                                                                                                                                                  
------------------------------------  ------------------------
-- Screens
------------------------------------------------------------

local screens = {}

-- Realtime row 7/8 overlays are autonomous in the single Bridge once enabled.
-- Turn the previous overlay off synchronously before drawing another top-level
-- screen. Screens that own an overlay (screen 4 / screen 6) enable their own
-- mode again while drawing.
local sequencer_display = include("gjs - x - sequencer_engine.lua")
if not sequencer_display then return end

for screen = 0, 7 do

    local module = include(
        string.format("gjs - x - screen%d.lua", screen)
    )

    if not module then
        return
    end

    if screen == 0 then
        screens[screen] = module
    else
        local screen_module = module
        screens[screen] = function(api)
            sequencer_display.disable_display()
            screen_module(api)
        end
    end

end

------------------------------------------------------------
-- Startup helpers
------------------------------------------------------------

local function startup_clear()

    local clear = include("gjs - x - clear.lua")
    if not clear then
        return
    end

    clear.clear_all_regions_all_projects({
        items = true,
        fx = true,
        track_mode = "all"
    })

end

-- Comment this line if you want to keep the current jam.
startup_clear()

------------------------------------------------------------
-- Start
------------------------------------------------------------

core.start(screens)

