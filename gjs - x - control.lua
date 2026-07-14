-- ============================================================
-- Launchpad X groovebox prototype
-- Schermen 0 t/m 7 via rechter sidebar
-- Bewaart radio- en toggle-state per scherm
-- ============================================================

local DEVICE_NAME = "X"


-- ============================================================
-- Interactiemodes
-- ============================================================

local MODE_NONE      = 0
local MODE_HIGHLIGHT = 1
local MODE_RADIO     = 2
local MODE_TOGGLE    = 3


-- ============================================================
-- Launchpad-kleuren
-- ============================================================

local COLOR = {
    OFF          = 0,
    GREY         = 1,
    WHITE        = 3,
    RED          = 5,

    ORANGE       = 9,
    YELLOW       = 13,
    DARK_YELLOW  = 126,

    GREEN        = 21,

    LIGHT_BLUE   = 42,
    LIGHT_PURPLE = 44,
    BLUE         = 45,

    PURPLE       = 69,
    PINK         = 52,
    MAGENTA      = 53,
}

local SELECT_COLOR = COLOR.RED


-- ============================================================
-- Sidebar CC-nummers
-- Van boven naar beneden: screen 0 t/m screen 7
-- ============================================================

local SCREEN_CC = {
    [0] = 89,
    [1] = 79,
    [2] = 69,
    [3] = 59,
    [4] = 49,
    [5] = 39,
    [6] = 29,
    [7] = 19
}


-- ============================================================
-- Globale state
-- ============================================================

local LP = {
    output_index = nil,
    output_mode  = nil,

    pads = {},
    radio_groups = {},

    current_screen = 0,

    -- Per scherm:
    -- screen_state[n].radio[group] = geselecteerde MIDI-noot
    -- screen_state[n].toggle[note] = true/false
    screen_state = {},

    last_sequence = 0,
    running = true
}


-- ============================================================
-- Schermstate
-- ============================================================

local function get_screen_state(screen)
    if not LP.screen_state[screen] then
        LP.screen_state[screen] = {
            radio = {},
            toggle = {}
        }
    end

    return LP.screen_state[screen]
end


local function save_pad_state(pad)
    local state = get_screen_state(LP.current_screen)

    if pad.mode == MODE_RADIO and pad.group then
        state.radio[pad.group] = pad.note

    elseif pad.mode == MODE_TOGGLE then
        state.toggle[pad.note] = pad.active
    end
end

local function set_screen0_track_and_region(track, region)
    local screen0_state = get_screen_state(0)

    -- Trackselector staat op rij 1 van screen0
    screen0_state.radio["tracks"] = 10 + track

    -- Regionselector staat op rij 6 van screen0
    screen0_state.radio["regions"] = 60 + region
end

-- ============================================================
-- MIDI-output zoeken
-- ============================================================

local function find_midi_output(search_name)
    local wanted = search_name:lower()

    for index = 0, reaper.GetNumMIDIOutputs() - 1 do
        local exists, name =
            reaper.GetMIDIOutputName(index, "")

        if exists
           and name:lower():find(wanted, 1, true) then

            return index, name
        end
    end

    return nil, nil
end


local function initialise_x()
    local output_index, output_name =
        find_midi_output(DEVICE_NAME)

    if output_index == nil then
        reaper.ShowMessageBox(
            "Geen MIDI-output gevonden met '" ..
            DEVICE_NAME .. "' in de naam.",
            "Launchpad X",
            0
        )

        return false
    end

    LP.output_index = output_index
    LP.output_mode = 16 + output_index

    reaper.ShowConsoleMsg(
        "Launchpad gevonden: " ..
        output_name .. "\n"
    )

    return true
end


-- ============================================================
-- MIDI-outputfuncties
-- ============================================================

local function send_pad_color(row, col, color)
    local note = row * 10 + col

    reaper.StuffMIDIMessage(
        LP.output_mode,
        0x90,
        note,
        color
    )
end


local function send_cc_color(cc, color)
    reaper.StuffMIDIMessage(
        LP.output_mode,
        0xB0,
        cc,
        color
    )
end


-- ============================================================
-- Programmer Mode
-- ============================================================

local function auto_program_mode()
    -- Hier komt later je bestaande SysEx/startuproutine.
    --
    -- F0 00 20 29 02 0D 0E 01 F7

    reaper.ShowConsoleMsg(
        "Launchpad-layout gestart.\n"
    )
end


-- ============================================================
-- Basisfuncties voor pads
-- ============================================================

local function valid_position(row, col)
    return row >= 1 and row <= 8
       and col >= 1 and col <= 8
end


local function drawpad(
    row,
    col,
    color,
    mode,
    options
)
    mode = mode or MODE_NONE
    options = options or {}

    if not valid_position(row, col) then
        reaper.ShowConsoleMsg(
            string.format(
                "Ongeldige padpositie: row=%s, col=%s\n",
                tostring(row),
                tostring(col)
            )
        )
        return
    end

    local note = row * 10 + col

    local pad = {
        row = row,
        col = col,
        note = note,

        color = color,
        mode = mode,

        active_color =
            options.active_color or SELECT_COLOR,

        group = options.group,
        active = false,

        on_press = options.on_press,
        on_release = options.on_release
    }

    local state = get_screen_state(LP.current_screen)

    if mode == MODE_RADIO and pad.group then
        local saved_note = state.radio[pad.group]

        if saved_note ~= nil then
            pad.active = saved_note == note
        else
            pad.active = options.active or false

            if pad.active then
                state.radio[pad.group] = note
            end
        end

    elseif mode == MODE_TOGGLE then
        local saved_toggle = state.toggle[note]

        if saved_toggle ~= nil then
            pad.active = saved_toggle
        else
            pad.active = options.active or false
            state.toggle[note] = pad.active
        end

    else
        pad.active = options.active or false
    end

    LP.pads[note] = pad

    if mode == MODE_RADIO
       and pad.group
       and pad.active then

        LP.radio_groups[pad.group] = note
    end

    local visible_color =
        pad.active and pad.active_color or pad.color

    send_pad_color(
        row,
        col,
        visible_color
    )
end


local function drawstrip(
    row,
    col_begin,
    col_end,
    color,
    mode,
    options
)
    col_begin = col_begin or 1
    col_end   = col_end or 8
    color     = color or COLOR.OFF
    mode      = mode or MODE_NONE
    options   = options or {}

    local group = options.group

    if mode == MODE_RADIO and group == nil then
        group =
            "radio_row_" ..
            row .. "_" ..
            col_begin .. "_" ..
            col_end
    end

    for col = col_begin, col_end do
        drawpad(
            row,
            col,
            color,
            mode,
            {
                active_color =
                    options.active_color,

                group = group,

                active =
                    options.selected_col == col,

                on_press =
                    options.on_press,

                on_release =
                    options.on_release
            }
        )
    end
end


local function drawblock(
    row_top,
    col_left,
    row_bottom,
    col_right,
    color,
    mode,
    options
)
    row_top    = row_top or 8
    col_left   = col_left or 1
    row_bottom = row_bottom or 1
    col_right  = col_right or 8
    color      = color or COLOR.OFF
    mode       = mode or MODE_NONE
    options    = options or {}

    local first_row =
        math.min(row_top, row_bottom)

    local last_row =
        math.max(row_top, row_bottom)

    local first_col =
        math.min(col_left, col_right)

    local last_col =
        math.max(col_left, col_right)

    local group = options.group

    if mode == MODE_RADIO and group == nil then
        group = string.format(
            "radio_block_%d_%d_%d_%d",
            first_row,
            first_col,
            last_row,
            last_col
        )
    end

    for row = first_row, last_row do
        for col = first_col, last_col do
            local selected =
                options.selected_row == row
                and options.selected_col == col

            drawpad(
                row,
                col,
                color,
                mode,
                {
                    active_color =
                        options.active_color,

                    group = group,
                    active = selected,

                    on_press =
                        options.on_press,

                    on_release =
                        options.on_release
                }
            )
        end
    end
end


local function clearscreen()
    LP.pads = {}
    LP.radio_groups = {}

    for row = 1, 8 do
        for col = 1, 8 do
            send_pad_color(
                row,
                col,
                COLOR.OFF
            )
        end
    end
end


-- ============================================================
-- Interactielogica
-- ============================================================

local function handle_pad_press(pad, velocity)
    if pad.mode == MODE_NONE then
        return
    end

    if pad.mode == MODE_HIGHLIGHT then
        send_pad_color(
            pad.row,
            pad.col,
            pad.active_color
        )

    elseif pad.mode == MODE_RADIO then
        local group = pad.group

        if group == nil then
            return
        end

        local previous_note =
            LP.radio_groups[group]

        if previous_note
           and LP.pads[previous_note] then

            local previous =
                LP.pads[previous_note]

            previous.active = false

            send_pad_color(
                previous.row,
                previous.col,
                previous.color
            )
        end

        pad.active = true
        LP.radio_groups[group] = pad.note

        save_pad_state(pad)

        send_pad_color(
            pad.row,
            pad.col,
            pad.active_color
        )

    elseif pad.mode == MODE_TOGGLE then
        pad.active = not pad.active

        save_pad_state(pad)

        send_pad_color(
            pad.row,
            pad.col,
            pad.active
                and pad.active_color
                or pad.color
        )
    end

    if pad.on_press then
        pad.on_press(pad, velocity)
    end
end


local function handle_pad_release(pad)
    if pad.mode == MODE_HIGHLIGHT then
        send_pad_color(
            pad.row,
            pad.col,
            pad.color
        )
    end

    if pad.on_release then
        pad.on_release(pad)
    end
end


-- ============================================================
-- Screen 0
-- ============================================================

local function drawscreen0()
    drawblock(
        8, 1,
        7, 8,
        COLOR.GREY,
        MODE_RADIO,
        {
            group = "sequencer_patterns",
            selected_row = 8,
            selected_col = 1,
            active_color = SELECT_COLOR
        }
    )

    drawstrip(
        6, 1, 8,
        COLOR.LIGHT_BLUE,
        MODE_RADIO,
        {
            group = "regions",
            selected_col = 1,
            active_color = SELECT_COLOR
        }
    )

    drawpad(
        4, 1,
        COLOR.GREEN,
        MODE_HIGHLIGHT,
        {
            active_color = SELECT_COLOR
        }
    )

    drawpad(
        4, 2,
        COLOR.YELLOW,
        MODE_HIGHLIGHT,
        {
            active_color = SELECT_COLOR
        }
    )

    drawpad(
        4, 3,
        COLOR.GREY,
        MODE_HIGHLIGHT,
        {
            active_color = SELECT_COLOR
        }
    )

    drawstrip(
        4, 5, 8,
        COLOR.BLUE,
        MODE_RADIO,
        {
            group = "page_selector",
            selected_col = 5,
            active_color = SELECT_COLOR
        }
    )

    drawpad(
        3, 5,
        COLOR.PURPLE,
        MODE_HIGHLIGHT
    )

    drawpad(
        3, 6,
        COLOR.LIGHT_PURPLE,
        MODE_HIGHLIGHT
    )

    drawpad(
        3, 7,
        COLOR.LIGHT_PURPLE,
        MODE_HIGHLIGHT
    )

    drawpad(
        3, 8,
        COLOR.LIGHT_BLUE,
        MODE_HIGHLIGHT
    )

    drawstrip(
        2, 1, 8,
        COLOR.DARK_YELLOW,
        MODE_TOGGLE,
        {
            active_color = SELECT_COLOR
        }
    )

    drawstrip(
        1, 1, 8,
        COLOR.ORANGE,
        MODE_RADIO,
        {
            group = "tracks",
            selected_col = 1,
            active_color = SELECT_COLOR
        }
    )
end


-- ============================================================
-- Tijdelijke testschermen 1 t/m 7
-- ============================================================

local TEST_COLORS = {
    COLOR.RED,
    COLOR.ORANGE,
    COLOR.YELLOW,
    COLOR.GREEN,
    COLOR.LIGHT_BLUE,
    COLOR.BLUE,
    COLOR.LIGHT_PURPLE,
    COLOR.PURPLE
}


local function draw_test_screen(screen_number)
    for row = 1, 8 do
        local color_index =
            ((row + screen_number - 2) % 8) + 1

        local color =
            TEST_COLORS[color_index]

        drawstrip(
            row,
            1,
            8,
            color,
            MODE_HIGHLIGHT,
            {
                active_color = SELECT_COLOR
            }
        )
    end
end

local function drawscreen1()
    local function draw_pattern_track(row, track, color)
        drawstrip(
            row,
            1,
            8,
            color,
            MODE_RADIO,
            {
                group = "pattern_track_" .. track,
                selected_col = 1,
                active_color = COLOR.WHITE,

                on_press = function(pad)
                    local region = pad.col

                    set_screen0_track_and_region(
                        track,
                        region
                    )
                end
            }
        )
    end

    -- Bovenste rij = track 1
    draw_pattern_track(
        8,
        1,
        COLOR.RED
    )

    draw_pattern_track(
        7,
        2,
        COLOR.ORANGE
    )

    draw_pattern_track(
        6,
        3,
        COLOR.GREEN
    )

    draw_pattern_track(
        5,
        4,
        COLOR.YELLOW
    )

    draw_pattern_track(
        4,
        5,
        COLOR.MAGENTA
    )

    draw_pattern_track(
        3,
        6,
        COLOR.LIGHT_PURPLE
    )

    draw_pattern_track(
        2,
        7,
        COLOR.PINK
    )

    -- Onderste rij = track 8
    draw_pattern_track(
        1,
        8,
        COLOR.BLUE
    )
end

local function drawscreen1oud()
    drawstrip(
        8, 1, 8,
        COLOR.RED,
        MODE_RADIO,
        {
            group = "pattern_track_1",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        7, 1, 8,
        COLOR.ORANGE,
        MODE_RADIO,
        {
            group = "pattern_track_2",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        6, 1, 8,
        COLOR.GREEN,
        MODE_RADIO,
        {
            group = "pattern_track_3",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        5, 1, 8,
        COLOR.YELLOW,
        MODE_RADIO,
        {
            group = "pattern_track_4",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        4, 1, 8,
        COLOR.PURPLE,
        MODE_RADIO,
        {
            group = "pattern_track_5",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        3, 1, 8,
        COLOR.LIGHT_PURPLE,
        MODE_RADIO,
        {
            group = "pattern_track_6",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        2, 1, 8,
        COLOR.PINK,
        MODE_RADIO,
        {
            group = "pattern_track_7",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )

    drawstrip(
        1, 1, 8,
        COLOR.BLUE,
        MODE_RADIO,
        {
            group = "pattern_track_8",
            selected_col = 1,
            active_color = COLOR.WHITE
        }
    )
end

local function drawscreen2()
    draw_test_screen(2)
end

local function drawscreen3()
    draw_test_screen(3)
end

local function drawscreen4()
    draw_test_screen(4)
end

local function drawscreen5()
    draw_test_screen(5)
end

local function drawscreen6()
    draw_test_screen(6)
end

local function drawscreen7()
    draw_test_screen(7)
end


-- ============================================================
-- Sidebar
-- ============================================================

local function draw_sidebar()
    for screen = 0, 7 do
        local color

        if screen == LP.current_screen then
            color = SELECT_COLOR
        else
            color = COLOR.GREY
        end

        send_cc_color(
            SCREEN_CC[screen],
            color
        )
    end
end


-- ============================================================
-- Schermen tekenen en selecteren
-- ============================================================

local function draw_current_screen()
    clearscreen()

    if LP.current_screen == 0 then
        drawscreen0()

    elseif LP.current_screen == 1 then
        drawscreen1()

    elseif LP.current_screen == 2 then
        drawscreen2()

    elseif LP.current_screen == 3 then
        drawscreen3()

    elseif LP.current_screen == 4 then
        drawscreen4()

    elseif LP.current_screen == 5 then
        drawscreen5()

    elseif LP.current_screen == 6 then
        drawscreen6()

    elseif LP.current_screen == 7 then
        drawscreen7()
    end

    draw_sidebar()
end


local function screen_from_cc(cc)
    for screen = 0, 7 do
        if SCREEN_CC[screen] == cc then
            return screen
        end
    end

    return nil
end


local function select_screen(screen)
    if screen < 0 or screen > 7 then
        return
    end

    if screen == LP.current_screen then
        return
    end

    LP.current_screen = screen
    draw_current_screen()

    reaper.ShowConsoleMsg(
        "Screen " .. screen .. "\n"
    )
end


-- ============================================================
-- MIDI-input
-- ============================================================

local function process_midi_input()
    local sequence, message =
        reaper.MIDI_GetRecentInputEvent(0)

    if sequence == 0
       or sequence == LP.last_sequence then

        return
    end

    LP.last_sequence = sequence

    if #message < 3 then
        return
    end

    local status   = message:byte(1)
    local data1    = message:byte(2)
    local data2    = message:byte(3)
    local msg_type = status & 0xF0

    if msg_type == 0x90
       or msg_type == 0x80 then

        local pad = LP.pads[data1]

        if not pad then
            return
        end

        local note_on =
            msg_type == 0x90
            and data2 > 0

        local note_off =
            msg_type == 0x80
            or (
                msg_type == 0x90
                and data2 == 0
            )

        if note_on then
            handle_pad_press(
                pad,
                data2
            )

        elseif note_off then
            handle_pad_release(pad)
        end

    elseif msg_type == 0xB0 then
        if data2 == 0 then
            return
        end

        local new_screen =
            screen_from_cc(data1)

        if new_screen ~= nil then
            select_screen(new_screen)
        end
    end
end


-- ============================================================
-- Main loop
-- ============================================================

local function mainloop()
    if not LP.running then
        return
    end

    process_midi_input()
    reaper.defer(mainloop)
end


local function cleanup()
    LP.running = false

    reaper.ShowConsoleMsg(
        "Launchpad-script gestopt.\n"
    )
end


local function main()
    if not initialise_x() then
        return
    end

    auto_program_mode()

    LP.current_screen = 0
    draw_current_screen()

    reaper.atexit(cleanup)
    mainloop()
end


main()
