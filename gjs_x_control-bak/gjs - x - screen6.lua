-- ============================================================
-- gjs - x - screen6.lua
-- Drum sequencer screen
-- Interface only; MIDI logic lives in sequencer_engine.lua.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local sequencer = dofile(
    script_dir .. "gjs - x - sequencer_engine.lua"
)

local MODE_BACKGROUND_GREEN = { 0, 10, 0 }
local ITEM_INACTIVE_GREEN = { 0, 10, 0 }
local NOTE_EMPTY_BLUE = { 0, 0, 10 }
local NOTE_SELECTED_BLUE = { 0, 0, 127 }

local display_generation = 0

local function sequencer_step_from_pad(pad)
    if pad.row == 8 then
        return pad.col
    end

    if pad.row == 7 then
        return 8 + pad.col
    end

    return nil
end

local function report_error(message)
    reaper.ShowConsoleMsg(
        "Screen 6: " .. tostring(message) .. "\n"
    )
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

    if state.radio["screen6_mode"] == nil then
        state.radio["screen6_mode"] = 58
    end

    if state.radio["screen6_note"] == nil then
        state.radio["screen6_note"] = 23
    end

    if state.sequencer_bar == nil then
        state.sequencer_bar = 1
    end

    if state.sequencer_velocity == nil then
        state.sequencer_velocity = 127
    end

    local velocity_group = "screen6_velocity"
    if state.horizontal_fader == nil then
        state.horizontal_fader = {}
    end

    if state.horizontal_fader[velocity_group] == nil then
        state.horizontal_fader[velocity_group] = {
            col = 8,
            step = 4
        }
    end

    if state.sequencer_microtune == nil then
        state.sequencer_microtune = 0
    end

    local microtune_group = "screen6_microtune"
    if state.balance[microtune_group] == nil then
        state.balance[microtune_group] = { position = 4, step = 4, centered = true }
    end

    state.sequencer_item_exists = sequencer.item_exists()

    local bar_count = sequencer.get_bar_count()
    state.sequencer_bar = math.max(
        1,
        math.min(bar_count, state.sequencer_bar)
    )

    local function refresh_display()
        sequencer.update_display({
            bar = state.sequencer_bar,
            pitch = state.radio["screen6_note"]
        })
    end

    display_generation = display_generation + 1
    local generation = display_generation
    local last_signature = nil
    local last_check = 0

    local function keep_display_synced()
        if generation ~= display_generation then return end

        if api.get_current_screen
        and api.get_current_screen() ~= 6 then
            sequencer.disable_display(1)
            return
        end

        local now = reaper.time_precise()
        if now - last_check >= 0.05 then
            last_check = now

            local context = sequencer.get_context()
            local signature = table.concat({
                tostring(state.sequencer_bar),
                tostring(state.radio["screen6_note"] or 0),
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

    ------------------------------------------------------------
    -- Physical Launchpad navigation buttons
    -- LEFT  = previous bar
    -- RIGHT = next bar
    ------------------------------------------------------------

    if api.set_navigation then
        api.set_navigation(
            state.sequencer_bar > 1 and function()
                state.sequencer_bar = state.sequencer_bar - 1
                api.redraw()
            end or nil,

            state.sequencer_bar < bar_count and function()
                state.sequencer_bar = state.sequencer_bar + 1
                api.redraw()
            end or nil
        )
    end

    ------------------------------------------------------------
    -- Bottom row: velocity for newly inserted notes.
    -- Default is maximum velocity (127).
    ------------------------------------------------------------

    api.draw_horizontal_value_fader(
        1,
        C.ORANGE,
        {
            group = velocity_group,
            default_col = 8,
            default_step = 4,
            on_press = function()
                state.sequencer_velocity =
                    horizontal_fader_to_velocity(
                        state.horizontal_fader[velocity_group]
                    )
            end
        }
    )

    ------------------------------------------------------------
    -- Row 2: microtune balance strip
    ------------------------------------------------------------

    api.draw_horizontal_fader(
        2,
        C.PURPLE,
        {
            group = microtune_group,
            on_press = function()
                state.sequencer_microtune =
                    balance_to_microtune(state.balance[microtune_group])
            end
        }
    )

    ------------------------------------------------------------
    -- Drum-note selection: MIDI notes 23 through 56.
    ------------------------------------------------------------

    api.drawblock(
        3, 3,
        6, 6,
        C.OFF,
        api.MODE_RADIO,
        {
            group = "screen6_note",
            background_rgb = NOTE_EMPTY_BLUE,
            active_color = NOTE_SELECTED_BLUE,
            on_press = function()
                reaper.defer(refresh_display)
            end
        }
    )

    ------------------------------------------------------------
    -- Pattern item controls
    ------------------------------------------------------------

    api.drawpad(
        4,
        1,
        C.RED,
        api.MODE_HIGHLIGHT,
        {
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
        }
    )

    api.drawpad(
        5,
        1,
        ITEM_INACTIVE_GREEN,
        api.MODE_HIGHLIGHT,
        {
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
                    state.sequencer_item_exists
                        and C.GREEN
                        or ITEM_INACTIVE_GREEN
                )
                return true
            end
        }
    )

    ------------------------------------------------------------
    -- Edit modes: microtune, delete note, insert note (38, 48, 58)
    ------------------------------------------------------------

    local mode_buttons = {
        { row = 3, col = 8 },
        { row = 4, col = 8 },
        { row = 5, col = 8 }
    }

    for _, button in ipairs(mode_buttons) do
        api.drawpad(
            button.row,
            button.col,
            MODE_BACKGROUND_GREEN,
            api.MODE_RADIO,
            {
                group = "screen6_mode",
                active_color = C.GREEN
            }
        )
    end

    ------------------------------------------------------------
    -- Sixteen drum steps. Row 8 = 1..8, row 7 = 9..16.
    ------------------------------------------------------------

    api.drawblock(
        7, 1,
        8, 8,
        C.GREY,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,

            on_press = function(pad)
                local active_mode = state.radio["screen6_mode"]

                local step = sequencer_step_from_pad(pad)
                local pitch = state.radio["screen6_note"]

                if not step or not pitch then
                    return
                end

                local success, result

                if active_mode == 58 then
                    success, result = sequencer.insert_note({
                        pitch = pitch,
                        step = step,
                        bar = state.sequencer_bar,
                        velocity = state.sequencer_velocity,
                        channel = 0,
                        gate = 0.5,
                        offset = state.sequencer_microtune
                    })

                elseif active_mode == 48 then
                    success, result = sequencer.delete_note({
                        pitch = pitch,
                        step = step,
                        bar = state.sequencer_bar
                    })

                elseif active_mode == 38 then
                    success, result = sequencer.microtune_note({
                        pitch = pitch,
                        step = step,
                        bar = state.sequencer_bar,
                        offset = state.sequencer_microtune
                    })
                else
                    return
                end

                if not success then
                    report_error(result)
                else
                    refresh_display()
                end
            end
        }
    )
end
