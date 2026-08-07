-- ============================================================
-- gjs - x - screen6_midi_edit.lua
-- Measure-oriented MIDI edit surface for screen 6.
-- ============================================================

local M = {}

local SOURCE_DARK = { 5, 0, 10 }
local SOURCE_VALID = { 28, 0, 52 }
local TARGET_DARK = { 0, 3, 10 }
local TARGET_VALID = { 0, 15, 48 }
local ACTION_ORANGE = { 55, 14, 0 }
local ACTION_ACTIVE = { 127, 40, 0 }
local SWING_GREEN = { 0, 55, 0 }
local QUANTIZE_GREEN = { 0, 75, 0 }

local function bar_from_pad(row, col, upper)
    if upper then
        if row == 8 then return col end
        if row == 7 then return 8 + col end
    else
        if row == 6 then return col end
        if row == 5 then return 8 + col end
    end
    return nil
end

local function sorted_selection(selection)
    local result = {}
    for bar, selected in pairs(selection or {}) do
        if selected then result[#result + 1] = bar end
    end
    table.sort(result)
    return result
end

local function clear_measure_selections(state)
    state.midi_edit_source_bars = {}
    state.midi_edit_target_bars = {}
end

local function horizontal_fader_to_strength(fader)
    if not fader then return 1.0 end
    local col = math.max(1, math.min(8, tonumber(fader.col) or 8))
    local step = math.max(1, math.min(4, tonumber(fader.step) or 4))
    local index = ((col - 1) * 4) + (step - 1)
    return 0.20 + (index / 31) * 0.80
end

local function balance_to_signed(balance)
    if not balance or balance.centered then return 0 end
    local index
    if balance.position == 1 then index = 0
    elseif balance.position == 2 then index = 5 - balance.step
    elseif balance.position == 3 then index = 9 - balance.step
    elseif balance.position == 6 then index = 9 + balance.step
    elseif balance.position == 7 then index = 13 + balance.step
    elseif balance.position == 8 then index = 18
    else index = 9 end
    return (index - 9) / 9
end

local function report(message)
    if message then
        reaper.ShowConsoleMsg("MIDI edit: " .. tostring(message) .. "\n")
    end
end

function M.draw(api, context)
    local state = context.state
    local sequencer = context.sequencer
    local engine = context.engine
    local C = api.COLOR
    local bar_count = math.max(1, math.min(16, sequencer.get_bar_count()))

    state.midi_edit_source_bars = state.midi_edit_source_bars or {}
    state.midi_edit_target_bars = state.midi_edit_target_bars or {}
    state.horizontal_fader = state.horizontal_fader or {}
    state.balance = state.balance or {}

    local quantize_group = "screen6_midi_quantize"
    local swing_group = "screen6_midi_swing"
    state.horizontal_fader[quantize_group] = state.horizontal_fader[quantize_group] or {
        col = 8,
        step = 4
    }
    state.balance[swing_group] = state.balance[swing_group] or {
        position = 4,
        step = 4,
        centered = true
    }

    local function toggle_bar(selection, bar)
        if not bar or bar > bar_count then return end
        selection[bar] = not selection[bar] or nil
        api.redraw()
    end

    -- Rows 7/8: source measure selection, purple. Dark background, white select.
    for row = 7, 8 do
        for col = 1, 8 do
            local bar = bar_from_pad(row, col, true)
            local valid = bar and bar <= bar_count
            api.drawpad(row, col, valid and SOURCE_VALID or SOURCE_DARK, api.MODE_HIGHLIGHT, {
                active = valid and state.midi_edit_source_bars[bar] == true,
                active_color = C.WHITE,
                on_press = valid and function()
                    toggle_bar(state.midi_edit_source_bars, bar)
                end or nil,
                on_release = function() return true end
            })
        end
    end

    -- Rows 5/6: destination measure selection, blue.
    for row = 5, 6 do
        for col = 1, 8 do
            local bar = bar_from_pad(row, col, false)
            local valid = bar and bar <= bar_count
            api.drawpad(row, col, valid and TARGET_VALID or TARGET_DARK, api.MODE_HIGHLIGHT, {
                active = valid and state.midi_edit_target_bars[bar] == true,
                active_color = C.WHITE,
                on_press = valid and function()
                    toggle_bar(state.midi_edit_target_bars, bar)
                end or nil,
                on_release = function() return true end
            })
        end
    end

    -- Row 4: signed swing amount.
    api.draw_horizontal_fader(4, SWING_GREEN, {
        group = swing_group
    })

    -- Row 3: quantize strength 20..100%, using the same 32-step fader style
    -- as sequencer velocity.
    api.draw_horizontal_value_fader(3, QUANTIZE_GREEN, {
        group = quantize_group,
        default_col = 8,
        default_step = 4
    })

    local function selected_source()
        return sorted_selection(state.midi_edit_source_bars)
    end

    local function selected_target()
        return sorted_selection(state.midi_edit_target_bars)
    end

    local function finish_action(ok, message)
        if not ok then
            report(message)
            return
        end
        clear_measure_selections(state)
        api.redraw()
    end

    -- Row 1: orange action keys. 15/16 are reserved for future functions.
    for col = 1, 8 do
        local callback = nil

        if col == 1 then
            callback = function()
                local src, dst = selected_source(), selected_target()
                if #src ~= 1 or #dst < 1 then
                    report("Copy needs exactly one source bar and one or more destination bars.")
                    return
                end
                finish_action(engine.copy_bar_to_many(sequencer, src[1], dst))
            end
        elseif col == 2 then
            callback = function()
                finish_action(engine.clear_bars(sequencer, selected_source()))
            end
        elseif col == 3 then
            callback = function()
                local amount = balance_to_signed(state.balance[swing_group])
                finish_action(engine.swing_bars(sequencer, selected_source(), amount))
            end
        elseif col == 4 then
            callback = function()
                local strength = horizontal_fader_to_strength(
                    state.horizontal_fader[quantize_group]
                )
                finish_action(engine.quantize_bars(sequencer, selected_source(), strength))
            end
        elseif col == 7 then
            callback = function()
                local ok, message = engine.undo(sequencer)
                if not ok then report(message) end
                clear_measure_selections(state)
                api.redraw()
            end
        elseif col == 8 then
            callback = function()
                local ok, message = engine.redo(sequencer)
                if not ok then report(message) end
                clear_measure_selections(state)
                api.redraw()
            end
        end

        api.drawpad(1, col, ACTION_ORANGE, api.MODE_HIGHLIGHT, {
            active_color = ACTION_ACTIVE,
            on_press = callback,
            on_release = function() return true end
        })
    end
end

return M
