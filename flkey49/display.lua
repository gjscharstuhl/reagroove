local api = require("api")

local M = {}

function M.clear()
    api.clear_display()
end

function M.parameter(name, value)
    api.set_parameter_name(name or "")
    api.set_parameter_value(value or "")
end

function M.message(text)
    api.show_message(text or "")
end

function M.tempo(bpm)
    api.set_tempo(bpm)
end

return M
