local constants = require("constants")

local M = {}

local queue = {}
local next_request_id = 0
local waiting_request_id = nil
local attached = false

local function clamp7(value)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return 0 end
    if value > 127 then return 127 end
    return value
end

local function attach()
    if attached then return end
    reaper.gmem_attach(constants.GMEM_NAME)
    attached = true
end

local function enqueue(command, a, b, c, d)
    queue[#queue + 1] = {
        command = command,
        a = a or 0,
        b = b or 0,
        c = c or 0,
        d = d or 0
    }
end

function M.init()
    attach()
    waiting_request_id = nil
end

function M.update()
    attach()

    if waiting_request_id then
        local ack = math.floor(reaper.gmem_read(10) or 0)
        if ack == waiting_request_id then
            waiting_request_id = nil
        else
            return
        end
    end

    if #queue == 0 then
        return
    end

    local item = table.remove(queue, 1)

    next_request_id = next_request_id + 1
    if next_request_id > 2147483000 then
        next_request_id = 1
    end

    reaper.gmem_write(1, item.command)
    reaper.gmem_write(2, item.a)
    reaper.gmem_write(3, item.b)
    reaper.gmem_write(4, item.c)
    reaper.gmem_write(5, item.d)

    -- Requestnummer altijd als laatste schrijven.
    reaper.gmem_write(0, next_request_id)
    waiting_request_id = next_request_id
end

function M.clear_queue()
    queue = {}
end

function M.is_busy()
    return waiting_request_id ~= nil or #queue > 0
end

function M.set_pad_rgb(note, r, g, b)
    enqueue(
        constants.CMD.PAD_RGB,
        clamp7(note),
        clamp7(r),
        clamp7(g),
        clamp7(b)
    )
end

function M.set_cc_rgb(cc, r, g, b)
    enqueue(
        constants.CMD.CC_RGB,
        clamp7(cc),
        clamp7(r),
        clamp7(g),
        clamp7(b)
    )
end

function M.set_daw_mode(enabled)
    enqueue(constants.CMD.DAW_MODE, enabled and 1 or 0)
end

function M.set_layout(layout)
    enqueue(constants.CMD.LAYOUT, clamp7(layout))
end

function M.clear_display()
    enqueue(constants.CMD.CLEAR_DISPLAY)
end

function M.set_parameter_name(text)
    -- Tekstcommando's worden in een volgende versie toegevoegd.
    -- Voorlopig bewust niet via losse bytes verstuurd.
end

function M.set_parameter_value(text)
end

function M.show_message(text)
end

function M.set_tempo(bpm)
    enqueue(constants.CMD.TEMPO, math.max(0, math.floor(tonumber(bpm) or 0)))
end

return M
