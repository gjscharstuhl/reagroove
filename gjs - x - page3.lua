-- PAGE3_ACTIVE_TRACK_F_ONLY_V5
-- ============================================================
-- gjs - x - page3.lua
--
-- Page 3 toont F1..F8 voor de huidige GJS_X/ActiveTrack.
-- Track 1 = rood, Track 2 = oranje, Track 3 = groen, enz.
-- Elke actieve track laadt uitsluitend zijn eigen TrackN mappings.
-- B1..B8 horen bij screen3 en worden hier volledig genegeerd.
-- ============================================================

local M = {}

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local fx_mapping = dofile(script_dir .. "gjs - x - fx_mapping.lua")
local fx_engine = dofile(script_dir .. "gjs - x - fx_engine.lua")
local mapping_path = fx_mapping.default_path()

local TRACK_RGB = {
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
    generation = 0,
    active_track = nil,
    mappings = {}
}

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function value_to_fader(value)
    local position = math.floor(clamp01(value) * 31 + 0.5)
    return {
        row = math.floor(position / 4) + 1,
        step = (position % 4) + 1
    }
end

local function fader_to_value(fader)
    if not fader then
        return 0
    end

    local position = ((fader.row - 1) * 4) + (fader.step - 1)
    return clamp01(position / 31)
end

local function same_fader(left, right)
    return left and right
       and left.row == right.row
       and left.step == right.step
end

local function get_active_track()
    local value = tonumber(
        reaper.GetExtState("GJS_X", "ActiveTrack")
    ) or 1

    return math.max(1, math.min(8, math.floor(value)))
end

local function load_track_mappings(active_track)
    local mappings, error_message =
        fx_mapping.load(mapping_path, active_track)

    if not mappings then
        reaper.ShowConsoleMsg(
            "Page 3 mapping kon niet worden geladen: " ..
            tostring(error_message) .. "\n"
        )
        return {}
    end

    return mappings
end

local function initialise_state(api, state, mappings)
    for col = 1, 8 do
        local group = "mixer_page_3_fader_" .. col
        local mapping = mappings["F" .. col]

        if mapping then
            local value = fx_engine.get_value(mapping)
            if value ~= nil then
                state.fader[group] = value_to_fader(value)
            else
                state.fader[group] = { row = 1, step = 1 }
            end
        else
            state.fader[group] = { row = 1, step = 1 }
        end
    end
end

function M.render(api, requested_track)
    runtime.generation = runtime.generation + 1
    local generation = runtime.generation

    local active_track = tonumber(requested_track) or get_active_track()
    active_track = math.max(1, math.min(8, math.floor(active_track)))

    runtime.active_track = active_track
    runtime.mappings = load_track_mappings(active_track)

    local mappings = runtime.mappings
    local state = api.get_screen_state(2)
    local colour = TRACK_RGB[active_track]

    initialise_state(api, state, mappings)

    for col = 1, 8 do
        local control = "F" .. col
        local group = "mixer_page_3_fader_" .. col

        api.draw_vertical_fader(col, colour, {
            group = group,
            default_row = 1,
            default_step = 1,

            on_press = function()
                local mapping = mappings[control]
                local fader = state.fader[group]

                if not mapping or not fader then
                    return
                end

                fx_engine.set_value(
                    mapping,
                    fader_to_value(fader)
                )
            end
        })
    end

    local sync_col = 1
    local last_sync = 0
    local sync_interval = 0.03

    local function sync_next_fader()
        if generation ~= runtime.generation then
            return
        end

        if api.get_current_screen
        and api.get_current_screen() ~= 2 then
            return
        end

        if api.get_page
        and api.get_page() ~= 3 then
            return
        end

        local current_active_track = get_active_track()
        if current_active_track ~= active_track then
            runtime.generation = runtime.generation + 1
            api.redraw()
            return
        end

        local now = reaper.time_precise()
        if now - last_sync < sync_interval then
            reaper.defer(sync_next_fader)
            return
        end
        last_sync = now

        local control = "F" .. sync_col
        local group = "mixer_page_3_fader_" .. sync_col
        local mapping = mappings[control]

        if mapping then
            local value = fx_engine.get_value(mapping)
            if value ~= nil then
                local wanted = value_to_fader(value)
                if not same_fader(state.fader[group], wanted) then
                    state.fader[group] = wanted
                    api.render_fader(group)
                end
            end
        end

        sync_col = (sync_col % 8) + 1
        reaper.defer(sync_next_fader)
    end

    reaper.ShowConsoleMsg(
        string.format(
            "PAGE3_ACTIVE_TRACK_F_ONLY_V5 geladen; ActiveTrack=%d\n",
            active_track
        )
    )

    reaper.defer(sync_next_fader)
end

return M
