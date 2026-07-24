-- gjs - flkey - stage2 gmem toggle.lua
-- Minimale gecombineerde test:
-- FLkey DAW-input CC37 -> Lua -> gmem -> JSFX -> pad 96 LED.
--
-- Geen queue, geen messagebox en geen controller-framework.

local GMEM_NAME = "GJS_FLKEY_STAGE2"
local DEVICE_NAME = "hw:F49,0,1"

local INPUT_CC = 37
local OUTPUT_PAD = 96

local input_index = nil
local last_sequence = 0
local request_id = 0
local led_on = false
local running = true

local function find_exact_input()
    for index = 0, reaper.GetNumMIDIInputs() - 1 do
        local ok, name = reaper.GetMIDIInputName(index, "")
        if ok and name == DEVICE_NAME then
            return index
        end
    end
    return nil
end

local function write_led(on)
    request_id = request_id + 1

    -- Schrijf eerst alle data en als laatste het requestnummer.
    reaper.gmem_write(1, OUTPUT_PAD)

    if on then
        reaper.gmem_write(2, 0)    -- R
        reaper.gmem_write(3, 127)  -- G
        reaper.gmem_write(4, 0)    -- B
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

    -- MIDI_GetRecentInputEvent geeft nieuwste eerst terug.
    -- Verwerk daarom achterstevoren.
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
            and data1 == INPUT_CC
            and data2 > 0 then
                led_on = not led_on
                write_led(led_on)
            end
        end
    end
end

local function stop()
    running = false
    led_on = false
    write_led(false)
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
        "FLkey stage 2",
        0
    )
    return
end

discard_existing_events()

-- Begin altijd met de LED uit.
write_led(false)

reaper.atexit(stop)
loop()
