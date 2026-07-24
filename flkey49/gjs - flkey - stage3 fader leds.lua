-- gjs - flkey - stage3 fader leds.lua
-- CC37 t/m CC44 toggelen hun eigen FLkey faderknop-led.
-- Lua -> gmem -> JSFX.
--
-- Geen queue, geen controller-framework.

local GMEM_NAME = "GJS_FLKEY_STAGE3"
local DEVICE_NAME = "hw:F49,0,1"

local FIRST_CC = 37
local LAST_CC = 44

local input_index = nil
local last_sequence = 0
local request_id = 0
local running = true

local states = {}

for cc = FIRST_CC, LAST_CC do
    states[cc] = false
end

local function find_exact_input()
    for index = 0, reaper.GetNumMIDIInputs() - 1 do
        local ok, name = reaper.GetMIDIInputName(index, "")
        if ok and name == DEVICE_NAME then
            return index
        end
    end
    return nil
end

local function write_cc_led(cc, on)
    request_id = request_id + 1

    -- Data eerst, requestnummer als laatste.
    reaper.gmem_write(1, cc)

    if on then
        reaper.gmem_write(2, 127) -- R
        reaper.gmem_write(3, 64)  -- G
        reaper.gmem_write(4, 0)   -- B
    else
        reaper.gmem_write(2, 0)
        reaper.gmem_write(3, 0)
        reaper.gmem_write(4, 0)
    end

    reaper.gmem_write(0, request_id)
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

    for i = #events, 1, -1 do
        local message = events[i]

        if message and #message >= 3 then
            local status = message:byte(1)
            local data1 = message:byte(2)
            local data2 = message:byte(3)

            local message_type = status & 0xF0
            local channel = (status & 0x0F) + 1

            if message_type == 0xB0
            and channel == 16
            and data1 >= FIRST_CC
            and data1 <= LAST_CC
            and data2 > 0 then
                states[data1] = not states[data1]
                write_cc_led(data1, states[data1])
            end
        end
    end
end

local function stop()
    running = false

    -- Alle acht leds uitzetten bij stoppen.
    for cc = FIRST_CC, LAST_CC do
        states[cc] = false
        write_cc_led(cc, false)
    end
end

local function loop()
    if not running then
        return
    end

    process_input()
    reaper.defer(loop)
end

reaper.gmem_attach(GMEM_NAME)

input_index = find_exact_input()

if not input_index then
    reaper.ShowMessageBox(
        "MIDI-input niet gevonden:\n" .. DEVICE_NAME,
        "FLkey stage 3",
        0
    )
    return
end

discard_existing_events()

-- Start schoon.
for cc = FIRST_CC, LAST_CC do
    write_cc_led(cc, false)
end

reaper.atexit(stop)
loop()
