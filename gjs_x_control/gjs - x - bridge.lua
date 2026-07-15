-- GJS Launchpad X bridge client
-- Shared-memory protocol used by "GJS - X - SysEx Bridge" JSFX.

local Bridge = {}

local GMEM_NAME = "GJS_X_BRIDGE"
local sequence = 0

local COMMAND_PROGRAMMER_MODE = 1
local COMMAND_LIVE_MODE       = 2

local function next_sequence()
    sequence = sequence + 1
    if sequence > 2147483646 then
        sequence = 1
    end
    return sequence
end

function Bridge.init()
    reaper.gmem_attach(GMEM_NAME)
    sequence = math.floor(reaper.gmem_read(0) or 0)
    return true
end

local function send_command(command)
    local seq = next_sequence()

    -- Write payload first and sequence last. The JSFX treats the sequence
    -- change as the signal that a complete command is ready.
    reaper.gmem_write(1, command)
    reaper.gmem_write(0, seq)

    return seq
end

function Bridge.programmer_mode()
    return send_command(COMMAND_PROGRAMMER_MODE)
end

function Bridge.live_mode()
    return send_command(COMMAND_LIVE_MODE)
end

function Bridge.last_acknowledged_sequence()
    return math.floor(reaper.gmem_read(2) or 0)
end

return Bridge
