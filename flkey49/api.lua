local bridge = require("bridge")

local M = {}

local function unpack_color(color_or_r, g, b)
    if type(color_or_r) == "table" then
        return color_or_r[1] or 0, color_or_r[2] or 0, color_or_r[3] or 0
    end

    return color_or_r or 0, g or 0, b or 0
end

function M.set_pad_rgb(note, color_or_r, g, b)
    local r, gg, bb = unpack_color(color_or_r, g, b)
    bridge.set_pad_rgb(note, r, gg, bb)
end

function M.set_cc_rgb(cc, color_or_r, g, b)
    local r, gg, bb = unpack_color(color_or_r, g, b)
    bridge.set_cc_rgb(cc, r, gg, bb)
end

function M.set_daw_mode(enabled)
    bridge.set_daw_mode(enabled)
end

function M.set_layout(layout)
    bridge.set_layout(layout)
end

function M.clear_display()
    bridge.clear_display()
end

function M.set_parameter_name(text)
    bridge.set_parameter_name(text)
end

function M.set_parameter_value(text)
    bridge.set_parameter_value(text)
end

function M.show_message(text)
    bridge.show_message(text)
end

function M.set_tempo(bpm)
    bridge.set_tempo(bpm)
end

function M.redraw()
    -- De gebruiker kan deze functie vervangen of uitbreiden.
end

return M
