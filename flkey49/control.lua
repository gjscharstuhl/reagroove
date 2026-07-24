-- gjs - flkey - control.lua
--
-- Eerste echte modulaire FLkey-controller.
-- Deze demo toggelt CC37 t/m CC44 en hun eigen leds.

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
package.path = script_path .. "?.lua;" .. package.path

local constants = require("constants")
local colors = require("colors")
local api = require("api")
local controls = require("controls")
local core = require("core")

local states = {}

local function set_button_led(cc)
    if states[cc] then
        api.set_cc_rgb(cc, colors.ORANGE)
    else
        api.set_cc_rgb(cc, colors.OFF)
    end
end

for cc = constants.FIRST_FADER_BUTTON_CC,
         constants.LAST_FADER_BUTTON_CC do

    states[cc] = false

    controls.on_cc_press(cc, function(pressed_cc)
        states[pressed_cc] = not states[pressed_cc]
        set_button_led(pressed_cc)
    end)
end

local function initialize_controller()
    api.set_daw_mode(true)

    for cc = constants.FIRST_FADER_BUTTON_CC,
             constants.LAST_FADER_BUTTON_CC do
        set_button_led(cc)
    end
end

local function shutdown()
    for cc = constants.FIRST_FADER_BUTTON_CC,
             constants.LAST_FADER_BUTTON_CC do
        api.set_cc_rgb(cc, colors.OFF)
    end

    -- Geef de bridge nog kort gelegenheid om de uit-commando's
    -- te verzenden voordat het script definitief stopt.
    local function finish_when_ready()
        require("bridge").update()

        if require("bridge").is_busy() then
            reaper.defer(finish_when_ready)
        else
            core.stop()
        end
    end

    finish_when_ready()
end

reaper.atexit(shutdown)

if core.start() then
    initialize_controller()
end
