-- ============================================================
-- gjs - x - screen6.lua
-- Drum/piano sequencer screen.
-- MIDI logic lives in sequencer_engine.lua.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local sequencer = dofile(script_dir .. "gjs - x - sequencer_engine.lua")

local ITEM_INACTIVE_GREEN = { 0, 10, 0 }
local NOTE_EMPTY_BLUE = { 0, 0, 10 }
local NOTE_SELECTED_BLUE = { 0, 0, 127 }
local OCTAVE_BLUE = { 0, 20, 55 }
local OCTAVE_SELECTED_BLUE = { 0, 65, 127 }
local LENGTH_GREEN = { 0, 10, 0 }
local LENGTH_SELECTED_GREEN = { 0, 127, 0 }

local display_generation = 0

-- Piano audition bridge for the companion JSFX.
local AUDITION_ENABLE_SLOT = 1100
local AUDITION_NOTES_BASE = 1120

local PIANO_KEYS = {
    -- White keys on row 5: C D E F G A B C
    [51] = 0, [52] = 2, [53] = 4, [54] = 5,
    [55] = 7, [56] = 9, [57] = 11, [58] = 12,
    -- Black keys on row 6: C# D# F# G# A#
    [62] = 1, [63] = 3, [65] = 6, [66] = 8, [67] = 10
}

local NOTE_LENGTH_GATES = {
    [31] = 1,   -- 1/16
    [32] = 2,   -- 1/8
    [33] = 4,   -- 1/4
    [34] = 8,   -- 1/2
    [35] = 16   -- 1/1
}

local function sequencer_step_from_pad(pad)
    if pad.row == 8 then return pad.col end
    if pad.row == 7 then return 8 + pad.col end
    return nil
end

local function report_error(message)
    reaper.ShowConsoleMsg("Screen 6: " .. tostring(message) .. "\n")
end

local function horizontal_fader_to_velocity(fader)
    if not fader then return 127 end
    local col = math.max(1, math.min(8, tonumber(fader.col) or 8))
    local step = math.max(1, math.min(4, tonumber(fader.step) or 4))
    local index = ((col - 1) * 4) + (step - 1)
    return math.floor((index * 127 / 31) + 0.5)
end

local function velocity_to_horizontal_fader(velocity)
    velocity = math.max(0, math.min(127, math.floor(tonumber(velocity) or 127)))
    local index = math.max(0, math.min(31, math.floor((velocity * 31 / 127) + 0.5)))
    return {
        col = math.floor(index / 4) + 1,
        step = (index % 4) + 1
    }
end

local function gate_to_length_pad(gate)
    gate = tonumber(gate) or 1
    local best_pad, best_distance = 31, math.huge
    for pad, candidate in pairs(NOTE_LENGTH_GATES) do
        local distance = math.abs(candidate - gate)
        if distance < best_distance then
            best_pad, best_distance = pad, distance
        end
    end
    return best_pad
end

local function balance_to_microtune(balance)
    if not balance or balance.centered then return 0 end
    local index
    if balance.position == 1 then index = 0
    elseif balance.position == 2 then index = 5 - balance.step
    elseif balance.position == 3 then index = 9 - balance.step
    elseif balance.position == 6 then index = 9 + balance.step
    elseif balance.position == 7 then index = 13 + balance.step
    elseif balance.position == 8 then index = 18
    else index = 9 end
    return ((index - 9) / 9) * 0.45
end

return function(api)
    local C = api.COLOR
    local state = api.get_screen_state(6)

    state.sequencer_layout = state.sequencer_layout or "drum"
    state.radio["screen6_note"] = state.radio["screen6_note"] or 23
    state.radio["screen6_octave"] = state.radio["screen6_octave"] or 44
    state.radio["screen6_piano_key"] = state.radio["screen6_piano_key"] or 51
    state.radio["screen6_length"] = state.radio["screen6_length"] or 31
    state.sequencer_bar = state.sequencer_bar or 1
    state.sequencer_velocity = state.sequencer_velocity or 127
    state.sequencer_microtune = state.sequencer_microtune or 0
    state.sequencer_chord = state.sequencer_chord or {}
    state.sequencer_chord_mode = state.sequencer_chord_mode or false

    local function set_audition_enabled(enabled)
        reaper.gmem_attach("GJS_X_BRIDGE")
        reaper.gmem_write(AUDITION_ENABLE_SLOT, enabled and 1 or 0)
        if not enabled then
            for pitch = 0, 127 do
                reaper.gmem_write(AUDITION_NOTES_BASE + pitch, 0)
            end
        end
    end

    local function clear_audition_notes()
        reaper.gmem_attach("GJS_X_BRIDGE")
        for pitch = 0, 127 do
            reaper.gmem_write(AUDITION_NOTES_BASE + pitch, 0)
        end
    end

    local function set_audition_note(pitch, velocity)
        pitch = math.max(0, math.min(127, math.floor(tonumber(pitch) or 0)))
        velocity = math.max(0, math.min(127, math.floor(tonumber(velocity) or 0)))
        reaper.gmem_attach("GJS_X_BRIDGE")
        reaper.gmem_write(AUDITION_NOTES_BASE + pitch, velocity)
    end

    local function audition_pitches(pitches)
        clear_audition_notes()
        if state.sequencer_layout ~= "piano" then return end
        for _, pitch in ipairs(pitches or {}) do
            set_audition_note(pitch, state.sequencer_velocity)
        end
    end

    local function stop_audition()
        clear_audition_notes()
    end

    local function selected_chord_pitches()
        local pitches = {}
        for pitch, selected in pairs(state.sequencer_chord) do
            if selected then pitches[#pitches + 1] = pitch end
        end
        table.sort(pitches)
        return pitches
    end

    local velocity_group = "screen6_velocity"
    state.horizontal_fader = state.horizontal_fader or {}
    state.horizontal_fader[velocity_group] = state.horizontal_fader[velocity_group] or {
        col = 8,
        step = 4
    }

    local microtune_group = "screen6_microtune"
    state.balance[microtune_group] = state.balance[microtune_group] or {
        position = 4,
        step = 4,
        centered = true
    }

    state.sequencer_item_exists = sequencer.item_exists()

    local bar_count = sequencer.get_bar_count()
    state.sequencer_bar = math.max(1, math.min(bar_count, state.sequencer_bar))

    local function selected_pitch()
        return state.radio["screen6_note"]
    end

    local function refresh_display()
        local options = {
            bar = state.sequencer_bar,
            pitch = selected_pitch()
        }

        if state.sequencer_layout == "piano"
        and state.sequencer_chord_mode then
            options.pitches = selected_chord_pitches()
            options.exact_pitches = true
        end

        sequencer.update_display(options)
    end

    local function safe_redraw()
        -- Never send a full matrix in the same defer cycle in which the
        -- sequencer-display JSFX is disabled.  Give the JSFX one cycle to
        -- stop writing rows 7/8 first; this prevents all-white matrix frames.
        sequencer.disable_display(1)
        if state.sequencer_redraw_pending then return end
        state.sequencer_redraw_pending = true
        reaper.defer(function()
            state.sequencer_redraw_pending = false
            if not api.get_current_screen or api.get_current_screen() == 6 then
                api.redraw()
            end
        end)
    end

    display_generation = display_generation + 1
    local generation = display_generation
    local last_signature = nil
    local last_check = 0

    local function keep_display_synced()
        if generation ~= display_generation then return end
        if api.get_current_screen and api.get_current_screen() ~= 6 then
            sequencer.disable_display(1)
            return
        end

        local now = reaper.time_precise()
        if now - last_check >= 0.05 then
            last_check = now
            local context = sequencer.get_context()
            local signature = table.concat({
                tostring(state.sequencer_bar),
                tostring(selected_pitch() or 0),
                tostring(context.item),
                tostring(context.take),
                tostring(context.item and reaper.GetMediaItemInfo_Value(context.item, "D_POSITION") or 0),
                tostring(context.item and reaper.GetMediaItemInfo_Value(context.item, "D_LENGTH") or 0)
            }, ":")

            if signature ~= last_signature then
                last_signature = signature
                refresh_display()
            end
        end
        reaper.defer(keep_display_synced)
    end

    -- Publish the sequencer rows only after the complete matrix frame has
    -- been sent by core.lua. This avoids competing SysEx writes.
    reaper.defer(refresh_display)
    reaper.defer(keep_display_synced)

    -- LEFT/RIGHT select the previous/next bar. A bar change only affects
    -- sequencer rows 7 and 8. Never redraw the complete 8x8 RGB matrix here:
    -- sending a full matrix frame while the display JSFX is updating those
    -- rows can make the Launchpad interpret a broken frame as all-white.
    local function select_bar(bar)
        stop_audition()
        local new_bar = math.max(1, math.min(bar_count, bar))
        if new_bar == state.sequencer_bar then return end
        state.sequencer_bar = new_bar
        refresh_display()
    end

    -- Keep LEFT/RIGHT callbacks installed at the end bars as well. The
    -- selector clamps the value, so navigation never requires a full redraw
    -- merely to enable or disable an arrow LED.
    -- UP/DOWN switch between the drum and piano layouts.
    if api.set_navigation then
        api.set_navigation(
            function() select_bar(state.sequencer_bar - 1) end,
            function() select_bar(state.sequencer_bar + 1) end,
            state.sequencer_layout == "piano" and function()
                state.sequencer_layout = "drum"
                safe_redraw()
            end or nil,
            state.sequencer_layout == "drum" and function()
                state.sequencer_layout = "piano"
                safe_redraw()
            end or nil
        )
    end

    set_audition_enabled(state.sequencer_layout == "piano")
    if state.sequencer_layout ~= "piano" then
        stop_audition()
    end

    -- Row 1: velocity for newly inserted notes.
    api.draw_horizontal_value_fader(1, C.ORANGE, {
        group = velocity_group,
        default_col = 8,
        default_step = 4,
        on_press = function()
            state.sequencer_velocity = horizontal_fader_to_velocity(
                state.horizontal_fader[velocity_group]
            )
        end
    })

    -- Row 2: microtuning for newly inserted notes.
    api.draw_horizontal_fader(2, C.PURPLE, {
        group = microtune_group,
        on_press = function()
            state.sequencer_microtune = balance_to_microtune(
                state.balance[microtune_group]
            )
        end
    })

    if state.sequencer_layout == "drum" then
        -- Existing 4x4 drum-note selector.
        api.drawblock(3, 3, 6, 6, C.OFF, api.MODE_RADIO, {
            group = "screen6_note",
            background_rgb = NOTE_EMPTY_BLUE,
            active_color = NOTE_SELECTED_BLUE,
            on_press = function()
                reaper.defer(refresh_display)
            end
        })

        -- MIDI item controls: retained in the drum layout only.
        api.drawpad(4, 1, C.RED, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = function()
                local success, result = sequencer.delete_item()
                if not success then
                    report_error(result)
                    return
                end

                state.sequencer_item_exists = false
                api.send_pad_rgb(5, 1, ITEM_INACTIVE_GREEN)
                refresh_display()
            end
        })

        api.drawpad(5, 1, ITEM_INACTIVE_GREEN, api.MODE_HIGHLIGHT, {
            active = state.sequencer_item_exists,
            active_color = C.GREEN,
            on_press = function()
                local success, result = sequencer.create_item()
                if not success then
                    report_error(result)
                    return
                end

                state.sequencer_item_exists = true
                api.send_pad_rgb(5, 1, C.GREEN)
                refresh_display()
            end,
            on_release = function()
                api.send_pad_rgb(
                    5,
                    1,
                    state.sequencer_item_exists and C.GREEN or ITEM_INACTIVE_GREEN
                )
                return true
            end
        })
    else
        local octave_col = (state.radio["screen6_octave"] or 44) % 10
        local key_note = state.radio["screen6_piano_key"] or 51
        state.radio["screen6_note"] =
            ((octave_col + 1) * 12) + (PIANO_KEYS[key_note] or 0)

        -- Row 3: note length, default 1/16.
        for col = 1, 5 do
            api.drawpad(3, col, LENGTH_GREEN, api.MODE_RADIO, {
                group = "screen6_length",
                active_color = LENGTH_SELECTED_GREEN
            })
        end

        -- Pad 37: toggle between single-note and chord-entry mode.
        -- Switching mode starts from a clean, predictable selection.
        state.toggle[37] = state.sequencer_chord_mode
        api.drawpad(3, 7, C.DARK_YELLOW or C.YELLOW, api.MODE_TOGGLE, {
            active = state.sequencer_chord_mode,
            active_color = C.YELLOW,
            on_press = function(pad)
                stop_audition()
                state.sequencer_chord_mode = pad.active == true
                state.sequencer_chord = {}
                for note = 51, 68 do
                    state.toggle[note] = nil
                end
                safe_redraw()
                reaper.defer(refresh_display)
            end
        })

        -- Pad 38: momentary monitor only. It never changes the mode or
        -- selection; it simply plays the current note/chord while held.
        api.drawpad(3, 8, C.DARK_YELLOW or C.YELLOW, api.MODE_HIGHLIGHT, {
            active_color = C.YELLOW,
            on_press = function()
                state.sequencer_monitor_held = true
                if state.sequencer_chord_mode then
                    audition_pitches(selected_chord_pitches())
                else
                    local pitch = selected_pitch()
                    audition_pitches(pitch and { pitch } or {})
                end
            end,
            on_release = function()
                state.sequencer_monitor_held = false
                stop_audition()
                return true
            end
        })

        -- Row 4: octave selection, default pad 4 = C4.
        for col = 1, 8 do
            api.drawpad(4, col, OCTAVE_BLUE, api.MODE_RADIO, {
                group = "screen6_octave",
                active_color = OCTAVE_SELECTED_BLUE,
                on_press = function(pad)
                    -- Store the octave explicitly and redraw immediately so all
                    -- piano-key callbacks are rebuilt for the newly selected range.
                    state.radio["screen6_octave"] = 40 + pad.col
                    local key_note = state.radio["screen6_piano_key"] or 51
                    local semitone = PIANO_KEYS[key_note] or 0
                    state.radio["screen6_note"] = ((pad.col + 1) * 12) + semitone
                    stop_audition()
                    safe_redraw()
                    reaper.defer(refresh_display)
                end
            })
        end

        local function draw_piano_key(row, col)
            local pad_note = (row * 10) + col
            local pitch = ((octave_col + 1) * 12) + PIANO_KEYS[pad_note]

            if state.sequencer_chord_mode then
                -- MODE_TOGGLE normally restores its generic saved state. Keep
                -- that state explicitly synchronized with the absolute-pitch
                -- chord table so old notes cannot reappear unexpectedly.
                state.toggle[pad_note] = state.sequencer_chord[pitch] == true
                api.drawpad(row, col, NOTE_EMPTY_BLUE, api.MODE_TOGGLE, {
                    active = state.sequencer_chord[pitch] == true,
                    active_color = NOTE_SELECTED_BLUE,
                    on_press = function(pad)
                        state.sequencer_chord[pitch] = pad.active or nil
                        state.radio["screen6_note"] = pitch
                        audition_pitches(selected_chord_pitches())
                        reaper.defer(refresh_display)
                    end,
                    on_release = function()
                        stop_audition()
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
                        audition_pitches({ pitch })
                        reaper.defer(refresh_display)
                    end,
                    on_release = function()
                        stop_audition()
                        return true
                    end
                })
            end
        end

        for col = 1, 8 do draw_piano_key(5, col) end
        for _, col in ipairs({ 2, 3, 5, 6, 7 }) do draw_piano_key(6, col) end

    end

    -- Rows 7 and 8: sixteen sequencer steps. Pressing an occupied step
    -- deletes it; pressing an empty step inserts it with current settings.
    api.drawblock(7, 1, 8, 8, C.GREY, api.MODE_HIGHLIGHT, {
        active_color = C.RED,
        on_press = function(pad)
            local step = sequencer_step_from_pad(pad)
            if not step then return end

            -- Pad 38 acts as a shift key: while it is held, pressing a
            -- sequencer step recalls every MIDI note that starts on that step
            -- into the piano chord selection instead of editing the item.
            if state.sequencer_layout == "piano"
            and state.sequencer_monitor_held then
                local recalled_data = sequencer.get_step_note_data({
                    step = step,
                    bar = state.sequencer_bar
                })
                local recalled = recalled_data.pitches or {}

                if #recalled > 0 then
                    state.sequencer_chord_mode = true
                    state.toggle[37] = true
                    state.sequencer_chord = {}
                    for _, pitch in ipairs(recalled) do
                        state.sequencer_chord[pitch] = true
                    end

                    -- Recall the editable note properties as well. The lowest
                    -- note is the reference when imported MIDI contains mixed
                    -- velocities or lengths inside one chord.
                    if recalled_data.velocity ~= nil then
                        state.sequencer_velocity = recalled_data.velocity
                        state.horizontal_fader[velocity_group] =
                            velocity_to_horizontal_fader(recalled_data.velocity)
                    end
                    if recalled_data.gate ~= nil then
                        state.radio["screen6_length"] =
                            gate_to_length_pad(recalled_data.gate)
                    end

                    -- Jump the visible keyboard to the octave of the lowest
                    -- recalled note. Notes in other octaves stay selected and
                    -- appear when that octave is chosen.
                    local lowest = recalled[1]
                    local octave_col = math.max(1, math.min(8, math.floor(lowest / 12) - 1))
                    state.radio["screen6_octave"] = 40 + octave_col
                    state.radio["screen6_note"] = lowest
                    audition_pitches(recalled)
                    safe_redraw()
                    reaper.defer(refresh_display)
                end
                return
            end

            local pitches
            if state.sequencer_layout == "piano" and state.sequencer_chord_mode then
                pitches = selected_chord_pitches()
            else
                local pitch = selected_pitch()
                pitches = pitch and { pitch } or {}
            end
            if #pitches == 0 then return end

            local gate = 1
            if state.sequencer_layout == "piano" then
                gate = NOTE_LENGTH_GATES[state.radio["screen6_length"]] or 1
            end

            -- Treat a chord as one unit. First remove every selected pitch. If
            -- none existed at this step, insert the complete set. This prevents
            -- partially deleted/partially inserted chords.
            local success, result = true, nil
            local found_existing = false
            for _, pitch in ipairs(pitches) do
                success, result = sequencer.delete_note({
                    pitch = pitch,
                    step = step,
                    bar = state.sequencer_bar
                })
                if not success then break end
                if result ~= "not_found" then found_existing = true end
            end

            if success and not found_existing then
                for _, pitch in ipairs(pitches) do
                    success, result = sequencer.insert_note({
                        pitch = pitch,
                        step = step,
                        bar = state.sequencer_bar,
                        velocity = state.sequencer_velocity,
                        channel = 0,
                        gate = gate,
                        offset = state.sequencer_microtune
                    })
                    if not success then break end
                end
            end

            if not success then report_error(result) else refresh_display() end
        end,
        on_release = function()
            -- Let the sequencer display restore its normal red/velocity state
            -- instead of leaving the temporary pressed color visible.
            reaper.defer(refresh_display)
            return true
        end
    })
end
