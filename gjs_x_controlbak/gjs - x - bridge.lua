local Bridge = {}

local GMEM_NAME = "GJS_X_BRIDGE"

local COMMAND_PROGRAMMER_MODE = 1
local COMMAND_LIVE_MODE       = 2
local COMMAND_SET_PAD_RGB     = 3
local COMMAND_SET_FADER_RGB   = 4
local COMMAND_SET_MATRIX_RGB  = 5

local RESEND_INTERVAL = 0.25

Bridge.sequence = 0
Bridge.queue = {}
Bridge.in_flight = nil
Bridge.running = false
Bridge.pump_scheduled = false

local function clamp(value, minimum, maximum)
    value = math.floor(tonumber(value) or 0)

    if value < minimum then return minimum end
    if value > maximum then return maximum end

    return value
end

local function copy_entries(entries)
    local result = {}

    for i, entry in ipairs(entries or {}) do
        result[i] = {
            clamp(entry[1], 0, 127),
            clamp(entry[2], 0, 127),
            clamp(entry[3], 0, 127),
            clamp(entry[4], 0, 127)
        }
    end

    return result
end

local function write_packet(packet)
    if packet.command == COMMAND_SET_PAD_RGB then
        reaper.gmem_write(3, packet.note)
        reaper.gmem_write(4, packet.red)
        reaper.gmem_write(5, packet.green)
        reaper.gmem_write(6, packet.blue)

    elseif packet.command == COMMAND_SET_FADER_RGB
        or packet.command == COMMAND_SET_MATRIX_RGB then

        local entries = packet.entries or {}
        reaper.gmem_write(10, #entries)

        for index, entry in ipairs(entries) do
            local base = 11 + ((index - 1) * 4)

            reaper.gmem_write(base + 0, entry[1])
            reaper.gmem_write(base + 1, entry[2])
            reaper.gmem_write(base + 2, entry[3])
            reaper.gmem_write(base + 3, entry[4])
        end
    end

    -- Commit last. The JSFX sees a new sequence only after the complete
    -- payload and command have been written.
    reaper.gmem_write(1, packet.command)
    reaper.gmem_write(0, packet.sequence)

    packet.sent_at = reaper.time_precise()
end

local function pump()
    Bridge.pump_scheduled = false

    if not Bridge.running then
        return
    end

    if Bridge.in_flight then
        local acknowledged = math.floor(reaper.gmem_read(2) or -1)

        if acknowledged == Bridge.in_flight.sequence then
            Bridge.in_flight = nil
        elseif reaper.time_precise() - Bridge.in_flight.sent_at >= RESEND_INTERVAL then
            -- Re-send the same sequence after a JSFX restart or delayed block.
            write_packet(Bridge.in_flight)
        end
    end

    if not Bridge.in_flight and #Bridge.queue > 0 then
        local packet = table.remove(Bridge.queue, 1)

        Bridge.sequence = Bridge.sequence + 1
        packet.sequence = Bridge.sequence
        Bridge.in_flight = packet

        write_packet(packet)
    end

    Bridge.pump_scheduled = true
    reaper.defer(pump)
end

local function ensure_pump()
    if Bridge.running and not Bridge.pump_scheduled then
        Bridge.pump_scheduled = true
        reaper.defer(pump)
    end
end

local function enqueue(packet)
    Bridge.queue[#Bridge.queue + 1] = packet
    ensure_pump()
    return true
end

function Bridge.init()
    reaper.gmem_attach(GMEM_NAME)

    local written = math.floor(reaper.gmem_read(0) or 0)
    local acknowledged = math.floor(reaper.gmem_read(2) or 0)

    Bridge.sequence = math.max(written, acknowledged, 0)
    Bridge.queue = {}
    Bridge.in_flight = nil
    Bridge.running = true

    ensure_pump()
    return true
end

function Bridge.shutdown()
    Bridge.running = false
    Bridge.queue = {}
    Bridge.in_flight = nil
end

function Bridge.programmer_mode()
    return enqueue({ command = COMMAND_PROGRAMMER_MODE })
end

function Bridge.live_mode()
    return enqueue({ command = COMMAND_LIVE_MODE })
end

function Bridge.set_pad_rgb(note, red, green, blue)
    return enqueue({
        command = COMMAND_SET_PAD_RGB,
        note = clamp(note, 0, 127),
        red = clamp(red, 0, 127),
        green = clamp(green, 0, 127),
        blue = clamp(blue, 0, 127)
    })
end

function Bridge.set_pad_rgb_at(row, col, red, green, blue)
    row = math.floor(tonumber(row) or 0)
    col = math.floor(tonumber(col) or 0)

    if row < 1 or row > 8 or col < 1 or col > 8 then
        return false
    end

    return Bridge.set_pad_rgb(row * 10 + col, red, green, blue)
end

function Bridge.set_fader_rgb(col, colors)
    col = clamp(col, 1, 8)

    if type(colors) ~= "table" or #colors < 8 then
        return false
    end

    local entries = {}

    for row = 1, 8 do
        local color = colors[row] or { 0, 0, 0 }
        entries[row] = {
            row * 10 + col,
            color[1], color[2], color[3]
        }
    end

    return enqueue({
        command = COMMAND_SET_FADER_RGB,
        entries = copy_entries(entries)
    })
end

function Bridge.set_row_rgb(row, colors)
    row = clamp(row, 1, 8)

    if type(colors) ~= "table" or #colors < 8 then
        return false
    end

    local entries = {}

    for col = 1, 8 do
        local color = colors[col] or { 0, 0, 0 }
        entries[col] = {
            row * 10 + col,
            color[1], color[2], color[3]
        }
    end

    return enqueue({
        command = COMMAND_SET_FADER_RGB,
        entries = copy_entries(entries)
    })
end

function Bridge.set_matrix_rgb(matrix)
    if type(matrix) ~= "table" then
        return false
    end

    local entries = {}

    for row = 1, 8 do
        local row_colors = matrix[row]
        if type(row_colors) ~= "table" then row_colors = {} end

        for col = 1, 8 do
            local color = row_colors[col]
            if type(color) ~= "table" then color = { 0, 0, 0 } end

            entries[#entries + 1] = {
                row * 10 + col,
                color[1], color[2], color[3]
            }
        end
    end

    return enqueue({
        command = COMMAND_SET_MATRIX_RGB,
        entries = copy_entries(entries)
    })
end

function Bridge.last_acknowledged_sequence()
    return math.floor(reaper.gmem_read(2) or -1)
end

return Bridge
