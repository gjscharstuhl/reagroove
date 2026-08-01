-- SCREEN3_PAGE_ROUTER_V2
-- ============================================================
-- gjs - x - screen3.lua
--
-- Screen 3 shows B1..B8 mapped FX parameters for the current
-- GJS_X/ActiveTrack. Each control is an independent horizontal
-- fader and uses only its own B mapping from fx_mapping.ini.
-- F1..F8 remain exclusively on screen 2, page 3.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local fx_mapping = dofile(script_dir .. "gjs - x - fx_mapping.lua")
local fx_engine = dofile(script_dir .. "gjs - x - fx_engine.lua")
local subproject_mixer = dofile(script_dir .. "gjs - x - subproject_mixer.lua")

local TRACK_RGB = {
    {127,   0,   0}, -- Track 1: red
    {127,  35,   0}, -- Track 2: orange
    {  0, 127,   0}, -- Track 3: green
    {127, 100,   0}, -- Track 4: yellow
    {127,   0,  70}, -- Track 5: magenta
    { 55,   0, 127}, -- Track 6: purple
    {127,  20,  90}, -- Track 7: pink
    {  0,  35, 127}  -- Track 8: blue
}

local runtime = {
    generation = 0,
    active_track = nil,
    mappings = {}
}

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function get_active_track()
    local value = tonumber(
        reaper.GetExtState("GJS_X", "ActiveTrack")
    ) or 1

    return math.max(1, math.min(8, math.floor(value)))
end

-- Convert a normalized FX value to the 19 positions supported by
-- the existing horizontal fader: 0, eight left steps, centre,
-- eight right steps, 1.
local function value_to_balance(value)
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

local function balance_to_value(balance)
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

local function same_balance(left, right)
    return left and right
       and left.position == right.position
       and left.step == right.step
       and left.centered == right.centered
end

local function load_track_mappings(active_track)
    local mapping_path = fx_mapping.default_path()

    if not mapping_path then
        reaper.ShowConsoleMsg(
            "Screen 3 FX mapping kon niet worden geladen: " ..
            "het huidige REAPER-project is nog niet opgeslagen.\n"
        )
        return {}
    end

    local mappings, error_message =
        fx_mapping.load(mapping_path, active_track)

    if not mappings then
        reaper.ShowConsoleMsg(
            "Screen 3 FX mapping kon niet worden geladen: " ..
            tostring(error_message) .. "\n"
        )
        return {}
    end

    return mappings
end

local function render_fx_page(api)
    runtime.generation = runtime.generation + 1
    local generation = runtime.generation

    local active_track = get_active_track()
    runtime.active_track = active_track
    runtime.mappings = load_track_mappings(active_track)

    local mappings = runtime.mappings
    local state = api.get_screen_state(3)
    local colour = TRACK_RGB[active_track]

    -- Read the current values before drawing the controls.
    for index = 1, 8 do
        local control = "B" .. index
        local group = "screen3_fx_balance_" .. index
        local mapping = mappings[control]

        if mapping then
            local value = fx_engine.get_value(mapping)
            state.balance[group] = value_to_balance(value or 0.5)
        else
            state.balance[group] = value_to_balance(0.5)
        end
    end

    for index = 1, 8 do
        local control = "B" .. index
        local group = "screen3_fx_balance_" .. index
        local physical_row = 9 - index

        api.draw_horizontal_fader(
            physical_row,
            colour,
            {
                group = group,

                on_press = function()
                    local mapping = mappings[control]
                    local balance = state.balance[group]

                    if not mapping or not balance then
                        return
                    end

                    fx_engine.set_value(
                        mapping,
                        balance_to_value(balance)
                    )
                end
            }
        )
    end

    -- Keep one B control per pass synchronized with changes made in
    -- REAPER or by another controller.
    local sync_index = 1
    local last_sync = 0
    local sync_interval = 0.03

    local function sync_next_balance()
        if generation ~= runtime.generation then
            return
        end

        if api.get_current_screen
        and api.get_current_screen() ~= 3 then
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
            reaper.defer(sync_next_balance)
            return
        end

        last_sync = now

        local control = "B" .. sync_index
        local group = "screen3_fx_balance_" .. sync_index
        local mapping = mappings[control]

        if mapping then
            local value = fx_engine.get_value(mapping)

            if value ~= nil then
                local wanted = value_to_balance(value)

                if not same_balance(state.balance[group], wanted) then
                    state.balance[group] = wanted
                    api.render_horizontal_fader(group)
                end
            end
        end

        sync_index = (sync_index % 8) + 1
        reaper.defer(sync_next_balance)
    end

    reaper.defer(sync_next_balance)
end

-- Page 1 and 2: regular pan controls for the first eight direct
-- children of folder "tracks". Page 3 keeps the B1..B8 FX controls.
local function render_pan_page(api)
    local FOLDER_NAME = "tracks"

    local FADER_RGB = {
        {127,   0,   0},
        {127,  35,   0},
        {  0, 127,   0},
        {127, 100,   0},
        {127,   0,  70},
        { 55,   0, 127},
        {127,  20,  90},
        {  0,  35, 127}
    }

    local function normalized_name(name)
        return (name or ""):match("^%s*(.-)%s*$"):lower()
    end

    local function find_direct_children(folder_name, maximum)
        local wanted = normalized_name(folder_name)
        local folder_index = nil
        local folder_depth = nil

        for index = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local _, name = reaper.GetTrackName(track)

            if normalized_name(name) == wanted
            and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0 then
                folder_index = index
                folder_depth = reaper.GetTrackDepth(track)
                break
            end
        end

        if folder_index == nil then
            return {}
        end

        local children = {}

        for index = folder_index + 1, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local depth = reaper.GetTrackDepth(track)

            if depth <= folder_depth then
                break
            end

            if depth == folder_depth + 1 then
                children[#children + 1] = track
                if #children >= maximum then
                    break
                end
            end
        end

        return children
    end

    local function pan_to_balance(pan)
        local value = math.max(-1, math.min(1, pan or 0))
        local index = math.floor(((value + 1) * 9) + 0.5)

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

    local function balance_to_pan(balance)
        if not balance or balance.centered then
            return 0
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

        return (index / 9) - 1
    end

    local children = find_direct_children(FOLDER_NAME, 8)
    local state = api.get_screen_state(3)

    for row = 1, 8 do
        local track = children[row]
        local group = "mixer_pan_" .. row

        if track then
            local pan = reaper.GetMediaTrackInfo_Value(track, "D_PAN")
            state.balance[group] = pan_to_balance(pan)
        end
    end

    for row = 1, 8 do
        local track = children[row]
        local group = "mixer_pan_" .. row

        api.draw_horizontal_fader(
            9 - row,
            FADER_RGB[row],
            {
                group = group,
                on_press = function()
                    if not track then
                        return
                    end

                    local balance = state.balance[group]
                    reaper.CSurf_OnPanChange(
                        track,
                        balance_to_pan(balance),
                        false
                    )
                    reaper.TrackList_AdjustWindows(false)
                    reaper.UpdateArrange()
                end
            }
        )
    end
end

-- Page 4: pan submix for the first eight top-level tracks in the
-- currently active subproject. Child tracks are deliberately ignored.
local function render_subproject_pan_page(api)
    runtime.generation = runtime.generation + 1
    local generation = runtime.generation

    local active_track = get_active_track()
    local tracks = {}
    local subproject_number = active_track - 1
    local project = reaper.EnumProjects(subproject_number, "")

    if project then
        local depth = 0

        for index = 0, reaper.CountTracks(project) - 1 do
            local track = reaper.GetTrack(project, index)

            if track and depth == 0 then
                tracks[#tracks + 1] = track
                if #tracks >= 8 then break end
            end

            if track then
                depth = depth + math.floor(
                    reaper.GetMediaTrackInfo_Value(
                        track,
                        "I_FOLDERDEPTH"
                    )
                )
                if depth < 0 then depth = 0 end
            end
        end
    end

    local state = api.get_screen_state(3)

    for index = 1, 8 do
        local track = tracks[index]
        local group = "subproject_pan_" .. index

        if track then
            local pan = reaper.GetMediaTrackInfo_Value(track, "D_PAN")
            state.balance[group] = subproject_mixer.pan_to_balance(pan)
        else
            state.balance[group] = subproject_mixer.pan_to_balance(0)
        end
    end

    for index = 1, 8 do
        local track = tracks[index]
        local group = "subproject_pan_" .. index

        api.draw_horizontal_fader(
            9 - index,
            TRACK_RGB[index],
            {
                group = group,
                on_press = function()
                    if not track then return end
                    local balance = state.balance[group]
                    reaper.CSurf_OnPanChange(
                        track,
                        subproject_mixer.balance_to_pan(balance),
                        false
                    )
                    reaper.TrackList_AdjustWindows(false)
                    reaper.UpdateArrange()
                end
            }
        )
    end

    local sync_index = 1
    local last_sync = 0
    local sync_interval = 0.03

    local function sync_next_pan()
        if generation ~= runtime.generation then return end
        if api.get_current_screen and api.get_current_screen() ~= 3 then return end
        if api.get_page and api.get_page() ~= 4 then return end

        local current_active_track = get_active_track()
        local current_number = current_active_track - 1

        if current_number ~= subproject_number then
            runtime.generation = runtime.generation + 1
            api.redraw()
            return
        end

        local now = reaper.time_precise()
        if now - last_sync < sync_interval then
            reaper.defer(sync_next_pan)
            return
        end
        last_sync = now

        local track = tracks[sync_index]
        if track then
            local group = "subproject_pan_" .. sync_index
            local pan = reaper.GetMediaTrackInfo_Value(track, "D_PAN")
            local wanted = subproject_mixer.pan_to_balance(pan)

            if not subproject_mixer.same_balance(state.balance[group], wanted) then
                state.balance[group] = wanted
                api.render_horizontal_fader(group)
            end
        end

        sync_index = (sync_index % 8) + 1
        reaper.defer(sync_next_pan)
    end

    reaper.defer(sync_next_pan)
end


return function(api)
    local page = api.get_page and api.get_page() or 1

    if page == 3 then
        render_fx_page(api)
    elseif page == 4 then
        render_subproject_pan_page(api)
    else
        -- Pages 1 and 2 use the original main-project pan screen.
        runtime.generation = runtime.generation + 1
        render_pan_page(api)
    end
end
