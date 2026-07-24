local constants = require("constants")
local bridge = require("bridge")
local controls = require("controls")

local M = {}

local input_index = nil
local last_sequence = 0
local running = false

local function find_exact_input()
    for index = 0, reaper.GetNumMIDIInputs() - 1 do
        local ok, name = reaper.GetMIDIInputName(index, "")
        if ok and name == constants.DEVICE_NAME then
            return index
        end
    end

    return nil
end

local function discard_existing_events()
    local sequence = reaper.MIDI_GetRecentInputEvent(0)
    if sequence and sequence > 0 then
        last_sequence = sequence
    end
end

local function process_input()
    local events = {}
    local newest_sequence = nil

    for i = 0, 255 do
        local sequence, message, timestamp, device_index =
            reaper.MIDI_GetRecentInputEvent(i)

        if not sequence or sequence == 0 then
            break
        end

        if newest_sequence == nil then
            newest_sequence = sequence
        end

        if sequence == last_sequence then
            break
        end

        if device_index == input_index then
            events[#events + 1] = message
        end
    end

    if newest_sequence == nil or newest_sequence == last_sequence then
        return
    end

    last_sequence = newest_sequence

    -- Nieuwste event staat vooraan, dus achterstevoren verwerken.
    for i = #events, 1, -1 do
        local message = events[i]

        if message and #message >= 3 then
            local status = message:byte(1)
            local data1 = message:byte(2)
            local data2 = message:byte(3)

            local message_type = status & 0xF0
            local channel = (status & 0x0F) + 1

            if channel == constants.MIDI_CHANNEL then
                if message_type == 0xB0 then
                    controls.dispatch_cc(data1, data2)

                elseif message_type == 0x90 then
                    controls.dispatch_note(data1, data2)

                elseif message_type == 0x80 then
                    controls.dispatch_note(data1, 0)
                end
            end
        end
    end
end

local function loop()
    if not running then return end

    process_input()
    bridge.update()

    reaper.defer(loop)
end

function M.start()
    if running then return true end

    input_index = find_exact_input()

    if not input_index then
        reaper.ShowMessageBox(
            "MIDI-input niet gevonden:\n" .. constants.DEVICE_NAME,
            "GJS FLkey",
            0
        )
        return false
    end

    bridge.init()
    discard_existing_events()

    running = true
    loop()

    return true
end

function M.stop()
    running = false
    bridge.clear_queue()
end

return M
