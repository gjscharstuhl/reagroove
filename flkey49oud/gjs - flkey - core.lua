local API = {}

local Bridge = _G.GJS_FLKEY_BRIDGE
local Colors = _G.GJS_FLKEY_COLORS

local DEVICE_NAME = "F49,0,1"

local MODE_NONE      = 0
local MODE_HIGHLIGHT = 1
local MODE_RADIO     = 2
local MODE_TOGGLE    = 3

local state = {
    input_index = nil,
    controls = {},
    radio_groups = {},
    last_sequence = -1,
    running = true
}

local function key(status_type, number)
    return status_type .. ":" .. tostring(number)
end

local function find_midi_input(search_name)
    local wanted = search_name:lower()

    for index = 0, reaper.GetNumMIDIInputs() - 1 do
        local exists, name = reaper.GetMIDIInputName(index, "")
        if exists and name:lower():find(wanted, 1, true) then
            return index, name
        end
    end

    return nil, nil
end

local function set_led(control, active)
    local color = active and control.active_color or control.color
    Bridge.set_pad_rgb(
        control.note,
        color[1], color[2], color[3]
    )
end

local function register_pad(note, color, mode, options)
    options = options or {}

    local control = {
        type = "note",
        note = note,
        color = color or Colors.OFF,
        active_color = options.active_color or Colors.WHITE,
        mode = mode or MODE_NONE,
        group = options.group,
        active = options.active == true,
        on_press = options.on_press,
        on_release = options.on_release
    }

    state.controls[key("note", note)] = control

    if control.mode == MODE_RADIO and control.group and control.active then
        state.radio_groups[control.group] = control
    end

    set_led(control, control.active)
    return control
end

local function handle_press(control)
    if control.mode == MODE_HIGHLIGHT then
        set_led(control, true)

    elseif control.mode == MODE_TOGGLE then
        control.active = not control.active
        set_led(control, control.active)

    elseif control.mode == MODE_RADIO then
        if control.group then
            local previous = state.radio_groups[control.group]
            if previous and previous ~= control then
                previous.active = false
                set_led(previous, false)
            end
            state.radio_groups[control.group] = control
        end

        control.active = true
        set_led(control, true)
    end

    if control.on_press then
        control.on_press(control)
    end
end

local function handle_release(control)
    if control.mode == MODE_HIGHLIGHT then
        set_led(control, false)
    end

    if control.on_release then
        control.on_release(control)
    end
end

local function process_recent_midi()
    local newest_sequence = state.last_sequence
    local index = 0

    while true do
        local sequence, message, timestamp, device =
            reaper.MIDI_GetRecentInputEvent(index)

        if not sequence or sequence < 0 or not message then
            break
        end

        if sequence <= state.last_sequence then
            break
        end

        if sequence > newest_sequence then
            newest_sequence = sequence
        end

        if device == state.input_index and #message >= 3 then
            local status = message:byte(1)
            local data1 = message:byte(2)
            local data2 = message:byte(3)
            local message_type = status & 0xF0

            if message_type == 0x90 or message_type == 0x80 then
                local control = state.controls[key("note", data1)]
                if control then
                    local pressed = message_type == 0x90 and data2 > 0
                    if pressed then
                        handle_press(control)
                    else
                        handle_release(control)
                    end
                end
            end
        end

        index = index + 1
    end

    state.last_sequence = newest_sequence
end

local function shutdown()
    state.running = false

    for _, control in pairs(state.controls) do
        Bridge.set_pad_rgb(control.note, 0, 0, 0)
    end
end

function API.drawpad(note, color, mode, options)
    return register_pad(note, color, mode, options)
end

function API.start(screen_builder)
    local input_index, input_name = find_midi_input(DEVICE_NAME)

    if input_index == nil then
        reaper.ShowMessageBox(
            "Geen actieve MIDI-input gevonden met '" .. DEVICE_NAME .. "' in de naam.",
            "FLkey controller",
            0
        )
        return false
    end

    state.input_index = input_index

    if not Bridge.init() then
        reaper.ShowMessageBox(
            "De JSFX bridge is niet actief.\n\n" ..
            "Plaats 'GJS FLkey 49 Lua Bridge' op een track met een hardware send naar de FLkey DAW-poort.",
            "FLkey controller",
            0
        )
        return false
    end

    Bridge.daw_mode(true)
    Bridge.set_pad_layout(2)

    screen_builder(API)

    reaper.ShowConsoleMsg(
        "FLkey input: " .. input_name .. " (index " .. input_index .. ")\n"
    )

    reaper.atexit(shutdown)

    local function loop()
        if not state.running then return end
        process_recent_midi()
        reaper.defer(loop)
    end

    loop()
    return true
end

API.MODE_NONE = MODE_NONE
API.MODE_HIGHLIGHT = MODE_HIGHLIGHT
API.MODE_RADIO = MODE_RADIO
API.MODE_TOGGLE = MODE_TOGGLE
API.COLOR = Colors
API.SELECT_COLOR = Colors.WHITE
API.bridge = Bridge

return API
