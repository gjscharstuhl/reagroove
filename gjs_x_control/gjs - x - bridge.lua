local Bridge = {}

local GMEM_NAME = "GJS_X_BRIDGE"

local COMMAND_PROGRAMMER_MODE = 1

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


local function write_packet(packet)
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

function Bridge.last_acknowledged_sequence()
    return math.floor(reaper.gmem_read(2) or -1)
end

return Bridge
