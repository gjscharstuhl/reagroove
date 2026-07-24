-- gjs - flkey - minimal midi monitor.lua

reaper.ClearConsole()

local inputs = {}
local input_count = reaper.GetNumMIDIInputs()

for i = 0, input_count - 1 do
    local ok, name = reaper.GetMIDIInputName(i, "")
    if ok then
        inputs[#inputs + 1] = tostring(i) .. ": " .. tostring(name)
    end
end

local text = "Gevonden MIDI-inputs:\n\n" .. table.concat(inputs, "\n")

reaper.ShowMessageBox(
    text,
    "FLkey minimale MIDI-monitor",
    0
)

reaper.ShowConsoleMsg("FLkey minimale MIDI-monitor gestart\n")
reaper.ShowConsoleMsg(text .. "\n\n")
reaper.ShowConsoleMsg("Druk nu op een pad, knop, toets of draai aan een regelaar.\n\n")

local last_sequence = 0

local function bytes_to_text(message)
    local result = {}

    if not message then
        return "(geen data)"
    end

    for i = 1, #message do
        result[#result + 1] =
            string.format("%02X", message:byte(i))
    end

    return table.concat(result, " ")
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

        local _, device_name =
            reaper.GetMIDIInputName(device_index, "")

        reaper.ShowConsoleMsg(
            "device " .. tostring(device_index) ..
            " (" .. tostring(device_name) .. ")" ..
            "  bytes: " .. bytes_to_text(message) ..
            "\n"
        )
    end

    reaper.defer(loop)
end

local sequence = reaper.MIDI_GetRecentInputEvent(0)
if sequence and sequence > 0 then
    last_sequence = sequence
end

loop()


