local Bridge = {}

local GMEM_NAME = "GJS_X_BRIDGE"

local COMMAND_PROGRAMMER_MODE = 1
local COMMAND_LIVE_MODE       = 2
local COMMAND_SET_PAD_RGB     = 3
local COMMAND_SET_FADER_RGB   = 4


Bridge.sequence = 0


local function clamp(value, minimum, maximum)
    value = math.floor(tonumber(value) or 0)

    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end


local function send_command(command)
    Bridge.sequence = Bridge.sequence + 1

    reaper.gmem_write(1, command)
    reaper.gmem_write(0, Bridge.sequence)
end


function Bridge.init()
    reaper.gmem_attach(GMEM_NAME)

    Bridge.sequence =
        math.floor(reaper.gmem_read(0) or 0)

    return true
end


function Bridge.programmer_mode()
    send_command(COMMAND_PROGRAMMER_MODE)
end


function Bridge.live_mode()
    send_command(COMMAND_LIVE_MODE)
end


function Bridge.set_pad_rgb(note, red, green, blue)
    note  = clamp(note,  0, 127)
    red   = clamp(red,   0, 127)
    green = clamp(green, 0, 127)
    blue  = clamp(blue,  0, 127)

    reaper.gmem_write(3, note)
    reaper.gmem_write(4, red)
    reaper.gmem_write(5, green)
    reaper.gmem_write(6, blue)

    send_command(COMMAND_SET_PAD_RGB)
end


function Bridge.set_pad_rgb_at(row, col, red, green, blue)
    if row < 1 or row > 8 or col < 1 or col > 8 then
        return false
    end

    local note = row * 10 + col

    Bridge.set_pad_rgb(
        note,
        red,
        green,
        blue
    )

    return true
end


function Bridge.set_fader_rgb(col, colors)
    col = clamp(col, 1, 8)

    if type(colors) ~= "table" or #colors < 8 then
        return false
    end

    reaper.gmem_write(10, 8)

    for row = 1, 8 do
        local item = colors[row] or { 0, 0, 0 }
        local base = 11 + ((row - 1) * 4)
        local note = row * 10 + col

        reaper.gmem_write(base + 0, note)
        reaper.gmem_write(base + 1, clamp(item[1], 0, 127))
        reaper.gmem_write(base + 2, clamp(item[2], 0, 127))
        reaper.gmem_write(base + 3, clamp(item[3], 0, 127))
    end

    send_command(COMMAND_SET_FADER_RGB)

    return true
end


function Bridge.last_acknowledged_sequence()
    return math.floor(reaper.gmem_read(2) or -1)
end



return Bridge
