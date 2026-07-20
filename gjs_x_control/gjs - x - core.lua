-- ============================================================
-- gjs - x - core.lua
-- Shared Launchpad X API, state, input, output and screen system
-- ============================================================
local Bridge = _G.GJS_X_BRIDGE
local Transport = _G.GJS_X_TRANSPORT
local Pattern = _G.GJS_X_PATTERN
local API = {}
local DEVICE_NAME = "X"

-- Interaction modes
local MODE_NONE      = 0
local MODE_HIGHLIGHT = 1
local MODE_RADIO     = 2
local MODE_TOGGLE    = 3
local MODE_FADER     = 4
local MODE_BALANCE   = 5

-- Launchpad palette values currently used by this project
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
    PINK         = 52,
    MAGENTA      = 53,
    PURPLE       = 69
}

local SELECT_COLOR = COLOR.RED

-- Screens 0, 1, 2, 3, 4, 5 and 7 use the 8x8 RGB matrix bridge.
-- Screen 6 continues to use its existing render path.
local PALETTE_RGB = {
    [COLOR.OFF]          = { 0,   0,   0   },
    [COLOR.GREY]         = { 32,  32,  32  },
    [COLOR.WHITE]        = { 127, 127, 127 },
    [COLOR.RED]          = { 127, 0,   0   },
    [COLOR.ORANGE]       = { 127, 40,  0   },
    [COLOR.YELLOW]       = { 127, 110, 0   },
    [COLOR.DARK_YELLOW]  = { 55,  38,  0   },
    [COLOR.GREEN]        = { 0,   127, 0   },
    [COLOR.LIGHT_BLUE]   = { 0,   70,  127 },
    [COLOR.LIGHT_PURPLE] = { 75,  25,  127 },
    [COLOR.BLUE]         = { 0,   0,   127 },
    [COLOR.PINK]         = { 127, 30,  90  },
    [COLOR.MAGENTA]      = { 127, 0,   80  },
    [COLOR.PURPLE]       = { 60,  0,   127 }
}

local RGB = {

    RED    = {127, 0, 0},
    GREEN  = {0, 127, 0},
    BLUE   = {0, 0, 127},

    ORANGE = {127, 40, 0},
    YELLOW = {127, 110, 0},

    PURPLE = {60, 0, 127},
    MAGENTA= {127, 0, 80},
    PINK   = {127, 30, 90},

    CYAN   = {0, 127, 127},
    WHITE  = {127,127,127},

    GREY   = {40,40,40},
    DARK_GREY = {15,15,15},

    OFF = {0,0,0}
}

function scale_rgb(color, factor)

    return {
        math.floor(color[1] * factor),
        math.floor(color[2] * factor),
        math.floor(color[3] * factor)
    }

end

-- Right sidebar, top to bottom: screen 0 through screen 7
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

local LP = {
    input_index = nil,
    output_index = nil,
    output_mode = nil,
    pads = {},
    radio_groups = {},
    current_screen = 0,
    current_page = 1,
    screen_state = {},
    last_sequence = 0,
    running = true,
    screens = {},
    framebuffer = nil,
    building_matrix = false,
    matrix_screen_active = false,
    loop_overview_signature = nil,
    loop_overview_last_update = 0,
    loop_overview_length = nil,
    loop_overview_current_bar = nil,
    loop_overview_background = nil
}

local function get_current_screen()
    return LP.current_screen
end

local function get_screen_state(screen)
    if not LP.screen_state[screen] then
        LP.screen_state[screen] = {
            radio = {},
            toggle = {},
            fader = {},
            balance = {}
        }
    end

    return LP.screen_state[screen]
end

local function get_page()
    return LP.current_page or 1
end

local function set_page(page)
    page = math.max(1, math.min(4, math.floor(tonumber(page) or 1)))
    LP.current_page = page

    -- Keep the screen-0 page radio state in sync.
    local state = get_screen_state(0)
    state.radio["page_selector"] = 44 + page

    -- Shared runtime value for future page-aware screens.
    reaper.SetExtState("GJS_X", "Page", tostring(page), false)
end

local function save_pad_state(pad)
    local state = get_screen_state(LP.current_screen)

    if pad.mode == MODE_RADIO and pad.group then
        state.radio[pad.group] = pad.note
    elseif pad.mode == MODE_TOGGLE then
        state.toggle[pad.note] = pad.active
    end
end

local function set_screen1_track_and_region(track, region)
    local state = get_screen_state(1)
    local row = 9 - track
    state.radio["pattern_track_" .. track] = row * 10 + region
end

local function set_screen0_track_and_region(track, region)
    local state = get_screen_state(0)
    state.radio["tracks"] = 10 + track
    state.radio["regions"] = 60 + region

    -- Keep screen 1 on the same track/region combination.
    set_screen1_track_and_region(track, region)
end

local function find_midi_input(search_name)
    local wanted = search_name:lower()

    for index = 0, reaper.GetNumMIDIInputs() - 1 do
        local exists, name =
            reaper.GetMIDIInputName(index, "")

        if exists
        and name:lower():find(wanted, 1, true) then
            return index, name
        end
    end

    return nil, nil
end

local function find_midi_output(search_name)
    local wanted = search_name:lower()

    for index = 0, reaper.GetNumMIDIOutputs() - 1 do
        local exists, name = reaper.GetMIDIOutputName(index, "")

        if exists and name:lower():find(wanted, 1, true) then
            return index, name
        end
    end

    return nil, nil
end

local function initialise_x()
    local input_index, input_name =
        find_midi_input(DEVICE_NAME)

    if input_index == nil then
        reaper.ShowMessageBox(
            "Geen MIDI-input gevonden met '" ..
            DEVICE_NAME ..
            "' in de naam.",
            "Launchpad X",
            0
        )
        return false
    end

    local output_index, output_name =
        find_midi_output(DEVICE_NAME)

    if output_index == nil then
        reaper.ShowMessageBox(
            "Geen MIDI-output gevonden met '" ..
            DEVICE_NAME ..
            "' in de naam.",
            "Launchpad X",
            0
        )
        return false
    end

    LP.input_index = input_index
    LP.output_index = output_index
    LP.output_mode = 16 + output_index

    reaper.ShowConsoleMsg(
        string.format(
            "Launchpad input: %s (index %d)\n" ..
            "Launchpad output: %s (index %d)\n",
            input_name,
            input_index,
            output_name,
            output_index
        )
    )

    return true
end

local BRIDGE_TRACK_NAME = "DIRTT Launchpad Bridge"

local function connect_bridge_track()
    if LP.output_index == nil then
        return false
    end

    local bridge_track = nil

    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)

        if name == BRIDGE_TRACK_NAME then
            bridge_track = track
            break
        end
    end

    if not bridge_track then
        reaper.ShowMessageBox(
            "Track '" .. BRIDGE_TRACK_NAME .. "' niet gevonden.",
            "Launchpad bridge",
            0
        )
        return false
    end

    -- I_MIDIHWOUT:
    -- bits 0–4  = kanaal, 0 betekent alle kanalen
    -- bits 5–9  = MIDI-outputindex
    local midi_hw_out = LP.output_index << 5

    reaper.SetMediaTrackInfo_Value(
        bridge_track,
        "I_MIDIHWOUT",
        midi_hw_out
    )

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    reaper.ShowConsoleMsg(
        "Bridge gekoppeld aan MIDI-outputindex " ..
        LP.output_index .. "\n"
    )

    return true
end

local function palette_to_rgb(color)
    local rgb = PALETTE_RGB[color] or PALETTE_RGB[COLOR.OFF]
    return rgb[1], rgb[2], rgb[3]
end

local function new_black_matrix()
    local matrix = {}

    for row = 1, 8 do
        matrix[row] = {}

        for col = 1, 8 do
            matrix[row][col] = { 0, 0, 0 }
        end
    end

    return matrix
end

local function send_pad_color(row, col, color)
    local red, green, blue = palette_to_rgb(color)

    -- While a matrix screen is being drawn, collect all pad colours first.
    if LP.building_matrix and LP.framebuffer then
        LP.framebuffer[row][col] = { red, green, blue }
        return true
    end

    -- Keep the in-memory matrix in sync with live pad changes. This lets
    -- dynamic overlays (such as the loop overview) safely resend a complete
    -- frame without restoring stale colours elsewhere on the screen.
    if LP.matrix_screen_active and LP.framebuffer then
        LP.framebuffer[row][col] = { red, green, blue }
    end

    -- Outside the one-time matrix build, keep live LED updates on the
    -- existing MIDI path. This prevents a later bridge command from
    -- overwriting command 5 in gmem before the JSFX has processed it.
    local note = row * 10 + col
    reaper.StuffMIDIMessage(LP.output_mode, 0x90, note, color)
    return true
end

local function send_pad_rgb(
    row,
    col,
    red,
    green,
    blue
)
    if not Bridge then
        reaper.ShowConsoleMsg(
            "RGB mislukt: SysEx bridge niet geladen.\n"
        )
        return false
    end

    return Bridge.set_pad_rgb_at(
        row,
        col,
        red,
        green,
        blue
    )
end

local function send_cc_color(cc, color)
    reaper.StuffMIDIMessage(LP.output_mode, 0xB0, cc, color)
end

local function auto_program_mode()
    if not Bridge then
        reaper.ShowConsoleMsg(
            "SysEx bridge module ontbreekt.\n"
        )
        return false
    end

    Bridge.programmer_mode()

    reaper.ShowConsoleMsg(
        "Programmer Mode-opdracht naar JSFX bridge gestuurd.\n"
    )

    return true
end

local function valid_position(row, col)
    return row >= 1 and row <= 8 and col >= 1 and col <= 8
end

local function drawpad(row, col, color, mode, options)
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

		fader_group = options.fader_group,
		balance_group = options.balance_group,
		rgb = options.rgb,

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

local function drawstrip(row, col_begin, col_end, color, mode, options)
    col_begin = col_begin or 1
    col_end = col_end or 8
    color = color or COLOR.OFF
    mode = mode or MODE_NONE
    options = options or {}

    local group = options.group

    if mode == MODE_RADIO and group == nil then
        group = string.format(
            "radio_row_%d_%d_%d",
            row,
            col_begin,
            col_end
        )
    end

    for col = col_begin, col_end do
        drawpad(row, col, color, mode, {
            active_color = options.active_color,
            group = group,
            active = options.selected_col == col,
            on_press = options.on_press,
            on_release = options.on_release
        })
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
    row_top = row_top or 8
    col_left = col_left or 1
    row_bottom = row_bottom or 1
    col_right = col_right or 8
    color = color or COLOR.OFF
    mode = mode or MODE_NONE
    options = options or {}

    local first_row = math.min(row_top, row_bottom)
    local last_row = math.max(row_top, row_bottom)
    local first_col = math.min(col_left, col_right)
    local last_col = math.max(col_left, col_right)
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
                options.selected_row == row and
                options.selected_col == col

            drawpad(row, col, color, mode, {
                active_color = options.active_color,
                group = group,
                active = selected,
                on_press = options.on_press,
                on_release = options.on_release
            })
        end
    end
end

local function clearscreen()
    LP.pads = {}
    LP.radio_groups = {}

    for row = 1, 8 do
        for col = 1, 8 do
            send_pad_color(row, col, COLOR.OFF)
        end
    end
end

local function get_fader_state(group)
    local state = get_screen_state(LP.current_screen)

    if not state.fader[group] then
        state.fader[group] = {
            row = 1,
            step = 4
        }
    end

    return state.fader[group]
end

local function get_balance_state(group)
    local state = get_screen_state(LP.current_screen)

    if not state.balance[group] then
        state.balance[group] = {
            position = 4,
            step = 4,
            centered = true
        }
    end

    return state.balance[group]
end

local function render_fader(group)
    local fader = get_fader_state(group)

    local brightness = {
        0.25,
        0.50,
        0.75,
        1.00
    }

    local fader_col = nil
    local base_rgb = nil

    for _, pad in pairs(LP.pads) do
        if pad.mode == MODE_FADER
           and pad.fader_group == group then

            fader_col = pad.col
            base_rgb = pad.rgb
            break
        end
    end

    if not fader_col or not base_rgb then
        return
    end

    local colors = {}

    for row = 1, 8 do
        if row < fader.row then
            colors[row] = {
                base_rgb[1],
                base_rgb[2],
                base_rgb[3]
            }

        elseif row == fader.row then
            local factor = brightness[fader.step]

            colors[row] = {
                math.floor(base_rgb[1] * factor),
                math.floor(base_rgb[2] * factor),
                math.floor(base_rgb[3] * factor)
            }

        else
            colors[row] = { 0, 0, 0 }
        end
    end

    if LP.building_matrix and LP.framebuffer then
        for row = 1, 8 do
            LP.framebuffer[row][fader_col] = colors[row]
        end
        return
    end

    if Bridge and Bridge.set_fader_rgb then
        Bridge.set_fader_rgb(
            fader_col,
            colors
        )
    end
end

local function render_horizontal_fader(group)
    local balance = get_balance_state(group)

    local brightness = {
        0.25,
        0.50,
        0.75,
        1.00
    }

    local fader_row = nil
    local base_rgb = nil

    for _, pad in pairs(LP.pads) do
        if pad.mode == MODE_BALANCE
           and pad.balance_group == group then

            fader_row = pad.row
            base_rgb = pad.rgb
            break
        end
    end

    if not fader_row or not base_rgb then
        return
    end

    local colors = {}

    for col = 1, 8 do
        colors[col] = { 0, 0, 0 }
    end

    if balance.centered then
        -- Middenstand: pads 4 en 5 volledig aan
        colors[4] = {
            base_rgb[1],
            base_rgb[2],
            base_rgb[3]
        }

        colors[5] = {
            base_rgb[1],
            base_rgb[2],
            base_rgb[3]
        }

    elseif balance.position <= 4 then
        -- Linkerkant: geselecteerde pad t/m pad 4
        for col = balance.position, 4 do
            colors[col] = {
                base_rgb[1],
                base_rgb[2],
                base_rgb[3]
            }
        end

        -- Pads 2 en 3 gebruiken de vier fijnstappen.
        -- Pad 1 is altijd volledig aan.
        if balance.position > 1 then
            local factor =
                brightness[balance.step] or 1.0

            colors[balance.position] = {
                math.floor(base_rgb[1] * factor),
                math.floor(base_rgb[2] * factor),
                math.floor(base_rgb[3] * factor)
            }
        end

    else
        -- Rechterkant: pad 5 t/m geselecteerde pad
        for col = 5, balance.position do
            colors[col] = {
                base_rgb[1],
                base_rgb[2],
                base_rgb[3]
            }
        end

        -- Pads 6 en 7 gebruiken de vier fijnstappen.
        -- Pad 8 is altijd volledig aan.
        if balance.position < 8 then
            local factor =
                brightness[balance.step] or 1.0

            colors[balance.position] = {
                math.floor(base_rgb[1] * factor),
                math.floor(base_rgb[2] * factor),
                math.floor(base_rgb[3] * factor)
            }
        end
    end

    if LP.building_matrix and LP.framebuffer then
        for col = 1, 8 do
            LP.framebuffer[fader_row][col] = colors[col]
        end
        return
    end

    if Bridge and Bridge.set_row_rgb then
        Bridge.set_row_rgb(
            fader_row,
            colors
        )
    end
end

local function draw_vertical_fader(
    col,
    rgb,
    options
)
    options = options or {}

    local group =
        options.group or "fader_" .. col

    local state = get_screen_state(LP.current_screen)

    if not state.fader[group] then
        state.fader[group] = {
            row = options.default_row or 1,
            step = options.default_step or 4
        }
    end

    for row = 1, 8 do
        drawpad(
            row,
            col,
            COLOR.OFF,
            MODE_FADER,
            {
                fader_group = group,
                rgb = rgb,

                on_press = options.on_press,
                on_release = options.on_release
            }
        )
    end

    -- Iedere fader weer direct tekenen
    render_fader(group)
end

local function draw_horizontal_fader(
    row,
    rgb,
    options
)
    options = options or {}

    local group =
        options.group or "balance_" .. row

    local state = get_screen_state(LP.current_screen)

    if not state.balance[group] then
        state.balance[group] = {
            position = 4,
            step = 4,
            centered = true
        }
    end

    for col = 1, 8 do
        drawpad(
            row,
            col,
            COLOR.OFF,
            MODE_BALANCE,
            {
                balance_group = group,
                rgb = rgb,

                on_press = options.on_press,
                on_release = options.on_release
            }
        )
    end

    render_horizontal_fader(group)
end

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

    elseif pad.mode == MODE_FADER then
        local group = pad.fader_group
        local fader = get_fader_state(group)

        if pad.row == fader.row then
            -- Zelfde hoogte opnieuw:
            -- 1 -> 2 -> 3 -> 4 -> 1
            fader.step = (fader.step % 4) + 1
        else
            -- Nieuwe hoogte begint bij stap 1
            fader.row = pad.row
            fader.step = 1
        end

        render_fader(group)

    elseif pad.mode == MODE_BALANCE then
        local group = pad.balance_group
        local balance = get_balance_state(group)
        local position = pad.col

        if position == 4 or position == 5 then
            -- Pads 4 en 5 vormen samen de middenstand.
            balance.centered = true
            balance.position = position
            balance.step = 4

        elseif position == 1 or position == 8 then
            -- Vol links/rechts: direct volledig aan,
            -- zonder fijnstappen.
            balance.centered = false
            balance.position = position
            balance.step = 4

        elseif not balance.centered
           and position == balance.position then

            -- Zelfde pad opnieuw:
            -- 1 -> 2 -> 3 -> 4 -> 1
            balance.step = (balance.step % 4) + 1

        else
            -- Nieuwe balanspositie begint bij stap 1.
            balance.centered = false
            balance.position = position
            balance.step = 1
        end

        render_horizontal_fader(group)
    end

    if pad.on_press then
        pad.on_press(pad, velocity)
    end
end

local function handle_pad_release(pad)
    if pad.mode == MODE_HIGHLIGHT then
        send_pad_color(pad.row, pad.col, pad.color)
    end

    if pad.on_release then
        pad.on_release(pad)
    end
end

local LOOP_OVERVIEW_UPDATE_INTERVAL = 0.01
local LOOP_LENGTH_RGB = { 83, 20, 20 } -- halfway between grey and red
local LOOP_CURRENT_RGB = { 127, 0, 0 }

local function get_loop_overview_values()
    local active_track = tonumber(
        reaper.GetExtState("GJS_X", "ActiveTrack")
    )

    if not active_track then
        return 0, nil
    end

    local project = reaper.EnumProjects(active_track)
    if not project then
        return 0, nil
    end

    -- Follow the region that is currently under the play cursor. When stopped,
    -- use the edit cursor so the overview remains visible instead of going dark.
    local play_state = reaper.GetPlayStateEx(project)
    local position

    if (play_state & 1) == 1 then
        position = reaper.GetPlayPositionEx(project)
    else
        position = reaper.GetCursorPositionEx(project)
    end

    local _, marker_count, region_count =
        reaper.CountProjectMarkers(project)

    local region_start = nil
    local region_end = nil

    for index = 0, marker_count + region_count - 1 do
        local _, is_region, start_pos, end_pos =
            reaper.EnumProjectMarkers2(project, index)

        if is_region
        and position >= start_pos
        and position < end_pos then
            region_start = start_pos
            region_end = end_pos
            break
        end
    end

    if not region_start
    or not region_end
    or region_end <= region_start then
        return 0, nil
    end

    local _, start_measure =
        reaper.TimeMap2_timeToBeats(project, region_start)

    local _, end_measure =
        reaper.TimeMap2_timeToBeats(project, region_end)

    local _, current_measure =
        reaper.TimeMap2_timeToBeats(project, position)

    local length =
        math.floor((end_measure - start_measure) + 0.5)

    length = math.max(0, math.min(16, length))

    local current_bar =
        math.floor(current_measure - start_measure) + 1

    if current_bar < 1 or current_bar > length then
        current_bar = nil
    end

    return length, current_bar
end

local function loop_pad_position(index)
    if index <= 8 then
        return 8, index
    end

    return 7, index - 8
end

local function copy_rgb(color)
    color = color or { 0, 0, 0 }
    return { color[1] or 0, color[2] or 0, color[3] or 0 }
end

local function remember_loop_background()
    LP.loop_overview_background = {}

    for index = 1, 16 do
        local row, col = loop_pad_position(index)
        LP.loop_overview_background[index] =
            copy_rgb(LP.framebuffer[row][col])
    end
end

local function loop_display_color(index, length, current_bar)
    if index == current_bar then
        return LOOP_CURRENT_RGB
    end

    if index <= length then
        return LOOP_LENGTH_RGB
    end

    if LP.loop_overview_background then
        return LP.loop_overview_background[index] or { 0, 0, 0 }
    end

    return { 0, 0, 0 }
end

local function paint_loop_overview(length, current_bar)
    if not LP.framebuffer then
        return
    end

    for index = 1, 16 do
        local row, col = loop_pad_position(index)
        LP.framebuffer[row][col] =
            copy_rgb(loop_display_color(index, length, current_bar))
    end
end

local function send_loop_pad_updates(indices, length, current_bar)
    if not Bridge or not LP.framebuffer or #indices == 0 then
        return false
    end

    -- Command 4 accepts an arbitrary list of RGB pads in one SysEx packet.
    -- Using a single bridge command prevents command overwrites and avoids
    -- resending the complete 8x8 matrix for every moving bar cursor.
    reaper.gmem_write(10, #indices)

    for item_index, index in ipairs(indices) do
        local row, col = loop_pad_position(index)
        local color = copy_rgb(loop_display_color(index, length, current_bar))
        local base = 11 + ((item_index - 1) * 4)

        LP.framebuffer[row][col] = color

        reaper.gmem_write(base + 0, row * 10 + col)
        reaper.gmem_write(base + 1, color[1])
        reaper.gmem_write(base + 2, color[2])
        reaper.gmem_write(base + 3, color[3])
    end

    Bridge.sequence = (Bridge.sequence or 0) + 1
    reaper.gmem_write(1, 4)
    reaper.gmem_write(0, Bridge.sequence)
    return true
end

local function draw_loop_overview()
    -- Capture the original two-row colours once during the matrix build.
    -- They remain the background whenever a pad falls outside the loop.
    remember_loop_background()

    local length, current_bar = get_loop_overview_values()
    paint_loop_overview(length, current_bar)

    LP.loop_overview_length = length
    LP.loop_overview_current_bar = current_bar
    LP.loop_overview_signature =
        tostring(length) .. ":" .. tostring(current_bar or 0)
end

local function update_loop_overview()
    if LP.current_screen ~= 0
       or not LP.matrix_screen_active
       or not LP.framebuffer
       or not Bridge then
        return
    end

    local now = reaper.time_precise()
    if now - LP.loop_overview_last_update < LOOP_OVERVIEW_UPDATE_INTERVAL then
        return
    end

    LP.loop_overview_last_update = now

    local length, current_bar = get_loop_overview_values()
    local old_length = LP.loop_overview_length
    local old_current = LP.loop_overview_current_bar

    if length == old_length and current_bar == old_current then
        return
    end

    if length ~= old_length then
        -- Loop length changes are rare. Repaint the complete overlay so pads
        -- that leave the loop correctly recover their original background.
        paint_loop_overview(length, current_bar)
        if Bridge.set_matrix_rgb then
            Bridge.set_matrix_rgb(LP.framebuffer)
        end
    else
        -- Normal playback update: restore only the previous cursor pad and
        -- light only the new cursor pad, both inside one compact SysEx packet.
        local indices = {}

        if old_current then
            indices[#indices + 1] = old_current
        end

        if current_bar and current_bar ~= old_current then
            indices[#indices + 1] = current_bar
        end

        send_loop_pad_updates(indices, length, current_bar)
    end

    LP.loop_overview_length = length
    LP.loop_overview_current_bar = current_bar
    LP.loop_overview_signature =
        tostring(length) .. ":" .. tostring(current_bar or 0)
end

local function draw_sidebar()
    for screen = 0, 7 do
        local color = COLOR.GREY

        if screen == LP.current_screen then
            color = SELECT_COLOR
        end

        send_cc_color(SCREEN_CC[screen], color)
    end
end

local function draw_current_screen()
    LP.loop_overview_signature = nil

    local draw_screen = LP.screens[LP.current_screen]

    local matrix_screen =
        LP.current_screen == 0 or
        LP.current_screen == 1 or
        LP.current_screen == 2 or
        LP.current_screen == 3 or
        LP.current_screen == 4 or
        LP.current_screen == 5 or
        LP.current_screen == 7

    if matrix_screen then
        -- Build the complete screen in memory and then send one matrix.
        LP.pads = {}
        LP.radio_groups = {}
        LP.framebuffer = new_black_matrix()
        LP.building_matrix = true

        if draw_screen then
            draw_screen(API)
        end

        LP.building_matrix = false

        if Bridge and Bridge.set_matrix_rgb then
            Bridge.set_matrix_rgb(LP.framebuffer)
            LP.matrix_screen_active = true
        else
            reaper.ShowConsoleMsg(
                "Matrix tekenen mislukt: Bridge.set_matrix_rgb ontbreekt.\n"
            )
        end
    else
        -- Clear any persistent RGB matrix before returning to legacy screens.
        if LP.matrix_screen_active
           and Bridge
           and Bridge.set_matrix_rgb then

            Bridge.set_matrix_rgb(new_black_matrix())
            LP.matrix_screen_active = false
        end

        clearscreen()

        if draw_screen then
            draw_screen(API)
        end
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
    if screen < 0 or screen > 7 then return end
    if screen == LP.current_screen then return end

    LP.current_screen = screen
    draw_current_screen()
    reaper.ShowConsoleMsg("Screen " .. screen .. "\n")
end

local function process_midi_message(message)
    if not message or #message < 3 then
        return
    end

    local status = message:byte(1)
    local data1 = message:byte(2)
    local data2 = message:byte(3)
    local msg_type = status & 0xF0

    if msg_type == 0x90 or msg_type == 0x80 then
        local pad = LP.pads[data1]

        if not pad then
            return
        end

        local note_on =
            msg_type == 0x90 and data2 > 0

        local note_off =
            msg_type == 0x80 or
            (msg_type == 0x90 and data2 == 0)

        if note_on then
            handle_pad_press(pad, data2)
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

local function process_midi_input()
    local events = {}
    local newest_sequence = nil

    -- Lees alle nieuwe recente events, niet alleen het allerlaatste event.
    -- Anders kan een drukke Circuit Tracks-input de Launchpad-events verdringen.
    for index = 0, 255 do
        local sequence,
              message,
              timestamp,
              device_index =
            reaper.MIDI_GetRecentInputEvent(index)

        if sequence == 0 then
            break
        end

        if newest_sequence == nil then
            newest_sequence = sequence
        end

        if sequence == LP.last_sequence then
            break
        end

        if device_index == LP.input_index then
            events[#events + 1] = message
        end
    end

    if newest_sequence == nil
    or newest_sequence == LP.last_sequence then
        return
    end

    -- Markeer de nieuwste globale sequence als verwerkt.
    LP.last_sequence = newest_sequence

    -- MIDI_GetRecentInputEvent(0) is het nieuwste event.
    -- Verwerk daarom achterstevoren zodat presses/releases in tijdsvolgorde blijven.
    for index = #events, 1, -1 do
        process_midi_message(events[index])
    end
end

local previous_play_state =
    reaper.GetPlayState()

local function mainloop()
    if not LP.running then
        return
    end

    process_midi_input()

    local play_state =
        reaper.GetPlayState()

    local was_playing =
        (previous_play_state & 1) == 1

    local is_playing =
        (play_state & 1) == 1

    if is_playing and not was_playing then
        draw_current_screen()
    end

    previous_play_state = play_state

    if Transport and Transport.update then
        Transport.update(API)
    end

    if Pattern and Pattern.update then
        Pattern.update(API)
    end

    update_loop_overview()

    reaper.defer(mainloop)
end


function start(screens)
    if not initialise_x() then
        return
    end

    if not connect_bridge_track() then
        return
    end

    LP.screens = screens
    LP.current_screen = 0
    set_page(tonumber(reaper.GetExtState("GJS_X", "Page")) or 1)

    local attempts = 0
    local max_attempts = 3
    local last_send_time = 0

    local function initialise_launchpad()
        local now = reaper.time_precise()

        if attempts < max_attempts then
            if attempts == 0 or now - last_send_time >= 0.25 then
                attempts = attempts + 1
                last_send_time = now

                auto_program_mode()

                reaper.ShowConsoleMsg(
                    "Programmer Mode poging " ..
                    attempts .. "/" .. max_attempts .. "\n"
                )
            end

            reaper.defer(initialise_launchpad)
            return
        end

        if now - last_send_time < 0.35 then
            reaper.defer(initialise_launchpad)
            return
        end

        draw_current_screen()

        reaper.atexit(cleanup)
        mainloop()
    end

    initialise_launchpad()
end


-- Public API for screen files
API.COLOR = COLOR
API.SELECT_COLOR = SELECT_COLOR
API.MODE_NONE = MODE_NONE
API.MODE_HIGHLIGHT = MODE_HIGHLIGHT
API.MODE_RADIO = MODE_RADIO
API.MODE_TOGGLE = MODE_TOGGLE
API.MODE_FADER = MODE_FADER

API.drawpad = drawpad
API.drawstrip = drawstrip
API.drawblock = drawblock
API.draw_loop_overview = draw_loop_overview
API.draw_vertical_fader = draw_vertical_fader
API.get_screen_state = get_screen_state
API.set_screen0_track_and_region = set_screen0_track_and_region
API.set_screen1_track_and_region = set_screen1_track_and_region
API.send_pad_color = send_pad_color
API.select_screen = select_screen
API.redraw = draw_current_screen
API.start = start
API.send_pad_rgb = send_pad_rgb
API.render_fader = render_fader
API.draw_horizontal_fader = draw_horizontal_fader
API.render_horizontal_fader = render_horizontal_fader
API.transport = Transport
API.get_current_screen = get_current_screen
API.get_page = get_page
API.set_page = set_page
API.pattern = Pattern
return API
