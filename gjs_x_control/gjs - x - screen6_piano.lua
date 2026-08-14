-- ============================================================
-- gjs - x - screen6_piano.lua
-- Piano keyboard UI for screen 6.
-- ============================================================

local M = {}

local NOTE_EMPTY_BLUE = { 0, 0, 10 }
local NOTE_SELECTED_BLUE = { 0, 0, 127 }
local OCTAVE_BLUE = { 0, 20, 55 }
local OCTAVE_SELECTED_BLUE = { 0, 65, 127 }
local LENGTH_GREEN = { 0, 10, 0 }
local LENGTH_SELECTED_GREEN = { 0, 127, 0 }
local TRANSPOSE_YELLOW = { 70, 48, 0 }
local TRANSPOSE_ACTIVE_YELLOW = { 127, 95, 0 }

M.PIANO_KEYS = {
    [51] = 0, [52] = 2, [53] = 4, [54] = 5,
    [55] = 7, [56] = 9, [57] = 11, [58] = 12,
    [62] = 1, [63] = 3, [65] = 6, [66] = 8, [67] = 10
}

M.NOTE_LENGTH_GATES = {
    [31] = 1,
    [32] = 2,
    [33] = 4,
    [34] = 8,
    [35] = 16
}

function M.draw(api, ctx)
    local state = ctx.state
    local C = api.COLOR
    local PIANO_KEYS = M.PIANO_KEYS
    state.sequencer_transpose_semi = math.max(-24, math.min(24,
        tonumber(state.sequencer_transpose_semi) or 0))

    local function transpose_pitch(pitch)
        return math.max(0, math.min(127, pitch + state.sequencer_transpose_semi))
    end

    local octave_col = (state.radio["screen6_octave"] or 44) % 10
    local key_note = state.radio["screen6_piano_key"] or 51
    state.radio["screen6_note"] = transpose_pitch(
        ((octave_col + 1) * 12) + (PIANO_KEYS[key_note] or 0)
    )

    for col = 1, 5 do
        api.drawpad(3, col, LENGTH_GREEN, api.MODE_RADIO, {
            group = "screen6_length",
            active_color = LENGTH_SELECTED_GREEN
        })
    end

    state.toggle[37] = state.sequencer_chord_mode
    api.drawpad(3, 7, C.DARK_YELLOW or C.YELLOW, api.MODE_TOGGLE, {
        active = state.sequencer_chord_mode,
        active_color = C.YELLOW,
        on_press = function(pad)
            ctx.stop_audition()
            state.sequencer_chord_mode = pad.active == true
            state.sequencer_chord = {}
            for note = 51, 68 do state.toggle[note] = nil end
            ctx.safe_redraw()
            reaper.defer(ctx.refresh_display)
        end
    })

    api.drawpad(3, 8, C.DARK_YELLOW or C.YELLOW, api.MODE_HIGHLIGHT, {
        active_color = C.YELLOW,
        on_press = function()
            state.sequencer_monitor_held = true
            if state.sequencer_chord_mode then
                ctx.audition_pitches(ctx.selected_chord_pitches())
            else
                local pitch = ctx.selected_pitch()
                ctx.audition_pitches(pitch and { pitch } or {})
            end
        end,
        on_release = function()
            state.sequencer_monitor_held = false
            ctx.stop_audition()
            return true
        end
    })

    for col = 1, 8 do
        api.drawpad(4, col, OCTAVE_BLUE, api.MODE_RADIO, {
            group = "screen6_octave",
            active_color = OCTAVE_SELECTED_BLUE,
            on_press = function(pad)
                state.radio["screen6_octave"] = 40 + pad.col
                local selected_key = state.radio["screen6_piano_key"] or 51
                local semitone = PIANO_KEYS[selected_key] or 0
                state.radio["screen6_note"] = transpose_pitch(((pad.col + 1) * 12) + semitone)
                ctx.stop_audition()
                ctx.safe_redraw()
                reaper.defer(ctx.refresh_display)
            end
        })
    end

    local function draw_piano_key(row, col)
        local pad_note = (row * 10) + col
        local pitch = transpose_pitch(((octave_col + 1) * 12) + PIANO_KEYS[pad_note])

        if state.sequencer_chord_mode then
            state.toggle[pad_note] = state.sequencer_chord[pitch] == true
            api.drawpad(row, col, NOTE_EMPTY_BLUE, api.MODE_TOGGLE, {
                active = state.sequencer_chord[pitch] == true,
                active_color = NOTE_SELECTED_BLUE,
                on_press = function(pad)
                    state.sequencer_chord[pitch] = pad.active or nil
                    state.radio["screen6_note"] = pitch
                    ctx.audition_pitches(ctx.selected_chord_pitches())
                    reaper.defer(ctx.refresh_display)
                end,
                on_release = function()
                    ctx.stop_audition()
                    return true
                end
            })
        else
            api.drawpad(row, col, NOTE_EMPTY_BLUE, api.MODE_RADIO, {
                group = "screen6_piano_key",
                active_color = NOTE_SELECTED_BLUE,
                on_press = function()
                    state.radio["screen6_piano_key"] = pad_note
                    state.radio["screen6_note"] = pitch
                    ctx.audition_pitches({ pitch })
                    reaper.defer(ctx.refresh_display)
                end,
                on_release = function()
                    ctx.stop_audition()
                    return true
                end
            })
        end
    end

    local function change_transpose(delta)
        local old = state.sequencer_transpose_semi
        local new_value = math.max(-24, math.min(24, old + delta))
        if new_value == old then return end
        local actual_delta = new_value - old
        state.sequencer_transpose_semi = new_value

        if state.sequencer_chord_mode and state.sequencer_chord then
            local shifted = {}
            for pitch, selected in pairs(state.sequencer_chord) do
                if selected then
                    shifted[math.max(0, math.min(127, pitch + actual_delta))] = true
                end
            end
            state.sequencer_chord = shifted
        end

        local selected_key = state.radio["screen6_piano_key"] or 51
        local semitone = PIANO_KEYS[selected_key] or 0
        state.radio["screen6_note"] = transpose_pitch(
            ((octave_col + 1) * 12) + semitone
        )
        ctx.stop_audition()
        ctx.safe_redraw()
        reaper.defer(ctx.refresh_display)
    end

    -- Unused corners of the black-key row: semitone transpose, matching
    -- Performance mode behavior. 61 = -1, 68 = +1.
    api.drawpad(6, 1, TRANSPOSE_YELLOW, api.MODE_HIGHLIGHT, {
        active_color = TRANSPOSE_ACTIVE_YELLOW,
        on_press = function() change_transpose(-1) end,
        on_release = function() return true end
    })
    api.drawpad(6, 8, TRANSPOSE_YELLOW, api.MODE_HIGHLIGHT, {
        active_color = TRANSPOSE_ACTIVE_YELLOW,
        on_press = function() change_transpose(1) end,
        on_release = function() return true end
    })

    for col = 1, 8 do draw_piano_key(5, col) end
    for _, col in ipairs({ 2, 3, 5, 6, 7 }) do draw_piano_key(6, col) end
end

return M
