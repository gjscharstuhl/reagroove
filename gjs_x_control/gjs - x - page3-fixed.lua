-- ============================================================
-- gjs - x - page3.lua
-- Page 3: mapped FX parameters in open subprojects.
--
-- Target resolution is delegated completely to fx_engine.lua:
--   Track1 -> open subproject 1
--   Track2 -> open subproject 2
--   etc.
-- Each mapping addresses either the first track or the master track.
-- ============================================================

local M = {}

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local fx_mapping = dofile(script_dir .. "gjs - x - fx_mapping.lua")
local fx_engine = dofile(script_dir .. "gjs - x - fx_engine.lua")
local mapping_path = fx_mapping.default_path()

local CONTROL_RGB = {
    {127,   0,   0},
    {127,  35,   0},
    {  0, 127,   0},
    {127, 100,   0},
    {127,   0,  70},
    { 55,   0, 127},
    {127,  20,  90},
    {  0,  35, 127}
}

local runtime = {
    mappings = {},
    signature = nil,
    generation = 0,
    last_mapping_check = 0,
    last_reported_signature = false
}

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function read_file_signature(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end

    local contents = file:read("*a") or ""
    file:close()

    -- Comparing the full contents is more portable than relying on a file
    -- timestamp, which standard Lua does not expose.
    return contents
end

local function reload_mapping(force)
    local signature = read_file_signature(mapping_path)

    if not force and signature == runtime.signature then
        return false
    end

    local mappings, error_message = fx_mapping.load(mapping_path)
    if not mappings then
        reaper.ShowConsoleMsg(
            "Page 3 mapping kon niet worden geladen: " ..
            tostring(error_message) .. "\n"
        )
        return false
    end

    runtime.mappings = mappings
    runtime.signature = signature

    local mapping_count = 0
    for _ in pairs(mappings) do
        mapping_count = mapping_count + 1
    end

    if mapping_count == 0 and runtime.last_reported_signature ~= signature then
        runtime.last_reported_signature = signature
        reaper.ShowConsoleMsg(
            "Page 3: mappingbestand geladen, maar geen F1..F8/B1..B8 toewijzingen gevonden.\n"
        )
    elseif mapping_count > 0 then
        runtime.last_reported_signature = false
    end

    return true
end

local function value_to_vertical(value)
    local index = math.floor(clamp01(value) * 31 + 0.5)
    return {
        row = math.floor(index / 4) + 1,
        step = (index % 4) + 1
    }
end

local function vertical_to_value(fader)
    if not fader then
        return 0
    end

    local index = ((fader.row - 1) * 4) + (fader.step - 1)
    return clamp01(index / 31)
end

local function value_to_horizontal(value)
    local index = math.floor(clamp01(value) * 18 + 0.5)

    if index == 0 then
        return { position = 1, step = 4, centered = false }
    elseif index <= 4 then
        return { position = 2, step = 5 - index, centered = false }
    elseif index <= 8 then
        return { position = 3, step = 9 - index, centered = false }
    elseif index == 9 then
        return { position = 4, step = 4, centered = true }
    elseif index <= 13 then
        return { position = 6, step = index - 9, centered = false }
    elseif index <= 17 then
        return { position = 7, step = index - 13, centered = false }
    end

    return { position = 8, step = 4, centered = false }
end

local function horizontal_to_value(balance)
    if not balance or balance.centered then
        return 0.5
    end

    local index

    if balance.position == 1 then
        index = 0
    elseif balance.position == 2 then
        index = 5 - balance.step
    elseif balance.position == 3 then
        index = 9 - balance.step
    elseif balance.position == 6 then
        index = 9 + balance.step
    elseif balance.position == 7 then
        index = 13 + balance.step
    elseif balance.position == 8 then
        index = 18
    else
        index = 9
    end

    return clamp01(index / 18)
end

local function same_vertical(left, right)
    return left and right
       and left.row == right.row
       and left.step == right.step
end

local function same_horizontal(left, right)
    return left and right
       and left.position == right.position
       and left.step == right.step
       and left.centered == right.centered
end

local function set_initial_states(api, state)
    for index = 1, 8 do
        local f_control = "F" .. index
        local f_mapping = runtime.mappings[f_control]

        if f_mapping then
            local value = fx_engine.get_value(f_mapping)
            if value ~= nil then
                state.fader["page3_" .. f_control] = value_to_vertical(value)
            end
        end

        local b_control = "B" .. index
        local b_mapping = runtime.mappings[b_control]

        if b_mapping then
            local value = fx_engine.get_value(b_mapping)
            if value ~= nil then
                state.balance["page3_" .. b_control] = value_to_horizontal(value)
            end
        end
    end
end

local function draw_controls(api, state)
    -- Vertical controls are registered first. A mapped B row is registered
    -- afterwards and therefore owns that complete row. This is an unavoidable
    -- limitation of placing both control types on the same 8x8 matrix.
    for index = 1, 8 do
        local control = "F" .. index
        local mapping = runtime.mappings[control]

        if mapping then
            local group = "page3_" .. control

            api.draw_vertical_fader(index, CONTROL_RGB[index], {
                group = group,
                default_row = 1,
                default_step = 1,
                on_press = function()
                    local current_mapping = runtime.mappings[control]
                    if current_mapping then
                        fx_engine.set_value(
                            current_mapping,
                            vertical_to_value(state.fader[group])
                        )
                    end
                end
            })
        end
    end

    for index = 1, 8 do
        local control = "B" .. index
        local mapping = runtime.mappings[control]

        if mapping then
            local group = "page3_" .. control

            api.draw_horizontal_fader(index, CONTROL_RGB[index], {
                group = group,
                on_press = function()
                    local current_mapping = runtime.mappings[control]
                    if current_mapping then
                        fx_engine.set_value(
                            current_mapping,
                            horizontal_to_value(state.balance[group])
                        )
                    end
                end
            })
        end
    end
end

local function start_sync(api, state, generation)
    local control_index = 1
    local sync_interval = 0.03
    local mapping_check_interval = 1.0
    local last_sync = 0

    local function sync_next()
        if generation ~= runtime.generation then
            return
        end

        if api.get_current_screen and api.get_current_screen() ~= 2 then
            return
        end

        if api.get_page and api.get_page() ~= 3 then
            return
        end

        local now = reaper.time_precise()

        if now - runtime.last_mapping_check >= mapping_check_interval then
            runtime.last_mapping_check = now

            if reload_mapping(false) then
                -- Rebuild pad registrations too, because controls may have
                -- been added to or removed from the mapping file.
                api.redraw()
                return
            end
        end

        if now - last_sync < sync_interval then
            reaper.defer(sync_next)
            return
        end

        last_sync = now

        local prefix = control_index <= 8 and "F" or "B"
        local index = control_index <= 8 and control_index or control_index - 8
        local control = prefix .. index
        local mapping = runtime.mappings[control]

        if mapping then
            local value = fx_engine.get_value(mapping)

            if value ~= nil then
                local group = "page3_" .. control

                if prefix == "F" then
                    local wanted = value_to_vertical(value)
                    if not same_vertical(state.fader[group], wanted) then
                        state.fader[group] = wanted
                        api.render_fader(group)
                    end
                else
                    local wanted = value_to_horizontal(value)
                    if not same_horizontal(state.balance[group], wanted) then
                        state.balance[group] = wanted
                        api.render_horizontal_fader(group)
                    end
                end
            end
        end

        control_index = (control_index % 16) + 1
        reaper.defer(sync_next)
    end

    reaper.defer(sync_next)
end

function M.render(api)
    runtime.generation = runtime.generation + 1
    local generation = runtime.generation

    reload_mapping(runtime.signature == nil)

    local state = api.get_screen_state(2)
    set_initial_states(api, state)
    draw_controls(api, state)
    start_sync(api, state, generation)
end

return M
