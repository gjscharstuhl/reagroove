-- gjs - midi - monitor all inputs.lua
-- Logt elk nieuw MIDI-bericht van alle ingeschakelde MIDI-inputs.
-- Geen JSFX, geen gmem, geen MIDI-output.

reaper.ClearConsole()
reaper.ShowConsoleMsg("MIDI-monitor voor alle inputs gestart\n")
reaper.ShowConsoleMsg("Druk nu op een pad, knop, toets of draai aan een regelaar.\n\n")

local last_sequence = 0

local function bytes_to_hex(message)
    if not message or #message == 0 then
        return "(leeg)"
    end

    local bytes = {}

    for i = 1, #message do
        bytes[#bytes + 1] = string.format("%02X", message:byte(i))
    end

    return table.concat(bytes, " ")
end

local function describe(message)
    if not message or #message == 0 then
        return "leeg bericht"
    end

    local status = message:byte(1)
    local data1 = message:byte(2) or 0
    local data2 = message:byte(3) or 0

    local msg_type = status & 0xF0
    local channel = (status & 0x0F) + 1

    if msg_type == 0x80 then
        return string.format(
            "NOTE OFF ch=%d note=%d value=%d",
            channel, data1, data2
        )
    elseif msg_type == 0x90 then
        if data2 == 0 then
            return string.format(
                "NOTE OFF ch=%d note=%d value=0",
                channel, data1
            )
        end

        return string.format(
            "NOTE ON ch=%d note=%d value=%d",
            channel, data1, data2
        )
    elseif msg_type == 0xA0 then
        return string.format(
            "POLY AFTERTOUCH ch=%d note=%d value=%d",
            channel, data1, data2
        )
    elseif msg_type == 0xB0 then
        return string.format(
            "CC ch=%d cc=%d value=%d",
            channel, data1, data2
        )
    elseif msg_type == 0xC0 then
        return string.format(
            "PROGRAM CHANGE ch=%d program=%d",
            channel, data1
        )
    elseif msg_type == 0xD0 then
        return string.format(
            "CHANNEL PRESSURE ch=%d value=%d",
            channel, data1
        )
    elseif msg_type == 0xE0 then
        local value = data1 + data2 * 128
        return string.format(
            "PITCH BEND ch=%d value=%d",
            channel, value
        )
    end

    return string.format("status=%02X", status)
end

local function get_device_name(device_index)
    local ok, name = reaper.GetMIDIInputName(device_index, "")

    if ok and name then
        return name
    end

    return "onbekend"
end

local function loop()
    local sequence,
          message,
          timestamp,
          device_index =
        reaper.MIDI_GetRecentInputEvent(0)

    if sequence
    and sequence > 0
    and sequence ~= last_sequence then

        last_sequence = sequence

        reaper.ShowConsoleMsg(string.format(
            "device %d (%s) | %s | bytes: %s\n",
            tonumber(device_index) or -1,
            get_device_name(device_index),
            describe(message),
            bytes_to_hex(message)
        ))
    end

    reaper.defer(loop)
end

local sequence = reaper.MIDI_GetRecentInputEvent(0)

if sequence and sequence > 0 then
    last_sequence = sequence
end

loop()
