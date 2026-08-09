-- ============================================================
-- gjs - x - screen6.lua
-- Drum/piano sequencer screen.
-- MIDI logic lives in sequencer_engine.lua.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local sequencer = dofile(script_dir .. "gjs - x - sequencer_engine.lua")
local piano = dofile(script_dir .. "gjs - x - screen6_piano.lua")
local midi_edit_screen = dofile(script_dir .. "gjs - x - screen6_midi_edit.lua")
local midi_edit_engine = dofile(script_dir .. "gjs - x - midi_edit_engine.lua")

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

local PIANO_KEYS = piano.PIANO_KEYS
local NOTE_LENGTH_GATES = piano.NOTE_LENGTH_GATES

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
                                                                                if state.sequencer_layout == "midi_edit" then
                                                                                    sequencer.disable_display()
                                                                                    return
                                                                                    end

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
                                                                                                if state.sequencer_layout == "midi_edit" then
                                                                                                    sequencer.disable_display()
                                                                                                    return
                                                                                                    end
                                                                                                    if api.get_current_screen and api.get_current_screen() ~= 6 then
                                                                                                        sequencer.disable_display(1)
                                                                                                        return
                                                                                                        end

                                                                                                        local now = reaper.time_precise()
                                                                                                        if now - last_check >= 0.05 then
                                                                                                            last_check = now
                                                                                                            local context = sequencer.get_context()
                                                                                                            local chord_signature = ""
                                                                                                            if state.sequencer_layout == "piano" and state.sequencer_chord_mode then
                                                                                                                chord_signature = table.concat(selected_chord_pitches(), ",")
                                                                                                                end

                                                                                                                local signature = table.concat({
                                                                                                                    tostring(state.sequencer_bar),
                                                                                                                                               tostring(selected_pitch() or 0),
                                                                                                                                               tostring(state.sequencer_layout),
                                                                                                                                               tostring(state.sequencer_chord_mode == true),
                                                                                                                                               chord_signature,
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

                                                                                                                    -- Drum/piano reserve rows 7/8 for the display JSFX. MIDI edit owns the
                                                                                                                    -- complete matrix itself, so the display stays disabled there.
                                                                                                                    if state.sequencer_layout == "midi_edit" then
                                                                                                                        sequencer.disable_display(1)
                                                                                                                        else
                                                                                                                            reaper.defer(refresh_display)
                                                                                                                            reaper.defer(keep_display_synced)
                                                                                                                            end

                                                                                                                            -- LEFT/RIGHT select bars in drum/piano. DOWN walks drum -> piano ->
                                                                                                                            -- MIDI edit; UP walks back.
                                                                                                                            local function select_bar(bar)
                                                                                                                            stop_audition()
                                                                                                                            local new_bar = math.max(1, math.min(bar_count, bar))
                                                                                                                            if new_bar == state.sequencer_bar then return end
                                                                                                                                state.sequencer_bar = new_bar
                                                                                                                                refresh_display()
                                                                                                                                end

                                                                                                                                local function set_layout(layout)
                                                                                                                                stop_audition()
                                                                                                                                state.sequencer_monitor_held = false
                                                                                                                                state.sequencer_layout = layout
                                                                                                                                if layout == "midi_edit" then sequencer.disable_display(1) end
                                                                                                                                    safe_redraw()
                                                                                                                                    end

                                                                                                                                    if api.set_navigation then
                                                                                                                                        if state.sequencer_layout == "drum" then
                                                                                                                                            api.set_navigation(
                                                                                                                                                function() select_bar(state.sequencer_bar - 1) end,
                                                                                                                                                               function() select_bar(state.sequencer_bar + 1) end,
                                                                                                                                                               nil,
                                                                                                                                                               function() set_layout("piano") end
                                                                                                                                            )
                                                                                                                                            elseif state.sequencer_layout == "piano" then
                                                                                                                                                api.set_navigation(
                                                                                                                                                    function() select_bar(state.sequencer_bar - 1) end,
                                                                                                                                                                   function() select_bar(state.sequencer_bar + 1) end,
                                                                                                                                                                   function() set_layout("drum") end,
                                                                                                                                                                   function() set_layout("midi_edit") end
                                                                                                                                                )
                                                                                                                                                else
                                                                                                                                                    api.set_navigation(nil, nil, function() set_layout("piano") end, nil)
                                                                                                                                                    end
                                                                                                                                                    end

                                                                                                                                                    set_audition_enabled(state.sequencer_layout == "piano")
                                                                                                                                                    if state.sequencer_layout ~= "piano" then
                                                                                                                                                        stop_audition()
                                                                                                                                                        end

                                                                                                                                                        if state.sequencer_layout ~= "midi_edit" then
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

                                                                                                                                                            end

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
                                                                                                                                                                elseif state.sequencer_layout == "piano" then
                                                                                                                                                                    piano.draw(api, {
                                                                                                                                                                        state = state,
                                                                                                                                                                        safe_redraw = safe_redraw,
                                                                                                                                                                        refresh_display = refresh_display,
                                                                                                                                                                        audition_pitches = audition_pitches,
                                                                                                                                                                        stop_audition = stop_audition,
                                                                                                                                                                        selected_chord_pitches = selected_chord_pitches,
                                                                                                                                                                        selected_pitch = selected_pitch
                                                                                                                                                                    })
                                                                                                                                                                    else
                                                                                                                                                                        midi_edit_screen.draw(api, {
                                                                                                                                                                            state = state,
                                                                                                                                                                            sequencer = sequencer,
                                                                                                                                                                            engine = midi_edit_engine
                                                                                                                                                                        })
                                                                                                                                                                        end

                                                                                                                                                                        if state.sequencer_layout ~= "midi_edit" then
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
                                                                                                                                                                            end
