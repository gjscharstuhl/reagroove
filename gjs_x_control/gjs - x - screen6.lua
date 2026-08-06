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

    local function set_audition_enabled(enabled)
        reaper.gmem_attach("GJS_X_BRIDGE")
        reaper.gmem_write(AUDITION_ENABLE_SLOT, enabled and 1 or 0)
        if not enabled then
            for pitch = 0, 127 do
                reaper.gmem_write(AUDITION_NOTES_BASE + pitch, 0)
            end
        end
    end

    local function set_audition_note(pitch, velocity)
        pitch = math.max(0, math.min(127, math.floor(tonumber(pitch) or 0)))
        velocity = math.max(0, math.min(127, math.floor(tonumber(velocity) or 0)))
        reaper.gmem_attach("GJS_X_BRIDGE")
        reaper.gmem_write(AUDITION_NOTES_BASE + pitch, velocity)
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
        sequencer.update_display({
            bar = state.sequencer_bar,
            pitch = selected_pitch()
        })
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

    refresh_display()
    reaper.defer(keep_display_synced)

    -- LEFT/RIGHT select the previous/next bar.
    -- UP/DOWN switch between the drum and piano layouts.
    if api.set_navigation then
        api.set_navigation(
            state.sequencer_bar > 1 and function()
                state.sequencer_bar = state.sequencer_bar - 1
                api.redraw()
            end or nil,
            state.sequencer_bar < bar_count and function()
                state.sequencer_bar = state.sequencer_bar + 1
                api.redraw()
            end or nil,
            state.sequencer_layout == "piano" and function()
                state.sequencer_layout = "drum"
                api.redraw()
            end or nil,
            state.sequencer_layout == "drum" and function()
                state.sequencer_layout = "piano"
                api.redraw()
            end or nil
        )
    end

    set_audition_enabled(state.sequencer_layout == "piano")

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

        -- Row 4: octave selection, default pad 4 = C4.
        for col = 1, 8 do
            api.drawpad(4, col, OCTAVE_BLUE, api.MODE_RADIO, {
                group = "screen6_octave",
                active_color = OCTAVE_SELECTED_BLUE,
                on_press = function(pad)
                    local key_note = state.radio["screen6_piano_key"]
                    local semitone = key_note and PIANO_KEYS[key_note]
                    if semitone then
                        state.radio["screen6_note"] = ((pad.col + 1) * 12) + semitone
                        reaper.defer(refresh_display)
                    end
                end
            })
        end

        local function draw_piano_key(row, col)
            local pad_note = (row * 10) + col
            api.drawpad(row, col, NOTE_EMPTY_BLUE, api.MODE_RADIO, {
                group = "screen6_piano_key",
                active_color = NOTE_SELECTED_BLUE,
                on_press = function(_, velocity)
                    local octave_col = (state.radio["screen6_octave"] or 44) % 10
                    local pitch = ((octave_col + 1) * 12) + PIANO_KEYS[pad_note]
                    state.radio["screen6_note"] = pitch
                    set_audition_note(pitch, velocity or state.sequencer_velocity)
                    reaper.defer(refresh_display)
                end,
                on_release = function()
                    local octave_col = (state.radio["screen6_octave"] or 44) % 10
                    local pitch = ((octave_col + 1) * 12) + PIANO_KEYS[pad_note]
                    set_audition_note(pitch, 0)
                end
            })
        end

        for col = 1, 8 do draw_piano_key(5, col) end
        for _, col in ipairs({ 2, 3, 5, 6, 7 }) do draw_piano_key(6, col) end

    end

    -- Rows 7 and 8: sixteen sequencer steps. Pressing an occupied step
    -- deletes it; pressing an empty step inserts it with current settings.
    api.drawblock(7, 1, 8, 8, C.GREY, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function(pad)
            local step = sequencer_step_from_pad(pad)
            local pitch = selected_pitch()
            if not step or not pitch then return end

            local success, result = sequencer.delete_note({
                pitch = pitch,
                step = step,
                bar = state.sequencer_bar
            })

            if success and result == "not_found" then
                local gate = 1
                if state.sequencer_layout == "piano" then
                    gate = NOTE_LENGTH_GATES[state.radio["screen6_length"]] or 1
                end
                success, result = sequencer.insert_note({
                    pitch = pitch,
                    step = step,
                    bar = state.sequencer_bar,
                    velocity = state.sequencer_velocity,
                    channel = 0,
                    gate = gate,
                    offset = state.sequencer_microtune
                })
            end

            if not success then report_error(result) else refresh_display() end
        end
    })
end
