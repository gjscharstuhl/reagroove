local scene_api = include("gjs - scene_api.lua")
local playlist_api = include("gjs - playlist_api.lua")

local MODE_LOAD = 1
local MODE_SAVE = 2
local MODE_COPY = 3

local operation = MODE_LOAD
local active_scene = 1
local selected_copy_scene = nil

local pending_scene = nil
local pending_targets = nil
local pending_generation = 0

local SCENE_EMPTY   = { 10, 3, 0 }
local SCENE_SAVED   = { 127, 35, 0 }
local SCENE_PENDING = { 50, 50, 127 }
local SCENE_ACTIVE  = { 127, 127, 127 }

local PLAYLIST_EMPTY  = { 0, 20, 0 }
local PLAYLIST_FILLED = { 0, 127, 0 }

local function pad_to_scene(row, col)
    return ((3 - row) * 8) + col
end

local function scene_to_pad(scene_nr)
    if scene_nr <= 8 then
        return 3, scene_nr
    end

    return 2, scene_nr - 8
end

local function pad_to_playlist_slot(row, col)
    return ((5 - row) * 8) + col
end

local function show_error(message)
    reaper.ShowConsoleMsg(
        "Screen 4: " .. tostring(message) .. "\n"
    )
end

local function pending_scene_has_arrived(api)
    if not pending_scene
    or type(pending_targets) ~= "table" then
        return false
    end

    if not api.pattern
    or type(api.pattern.get_visual_state) ~= "function" then
        return false
    end

    for track = 1, 8 do
        local region = pending_targets[track]

        if region then
            local visual_state =
                api.pattern.get_visual_state(
                    track,
                    region
                )

            if visual_state == "queued" then
                return false
            end
        end
    end

    return true
end

local function start_pending_watch(api)
    pending_generation = pending_generation + 1
    local generation = pending_generation
    local first_cycle = true

    local function watch()
        if generation ~= pending_generation then
            return
        end

        if not pending_scene then
            return
        end

        -- Geef Pattern.update eerst minstens één defer-cyclus om de
        -- aangevraagde regions als queued te registreren.
        if first_cycle then
            first_cycle = false
            reaper.defer(watch)
            return
        end

        if pending_scene_has_arrived(api) then
            active_scene = pending_scene
            pending_scene = nil
            pending_targets = nil

            if api.get_current_screen() == 4 then
                api.redraw()
            end

            return
        end

        reaper.defer(watch)
    end

    reaper.defer(watch)
end

local function show_pending_scene(api, scene_nr)
    local row, col = scene_to_pad(scene_nr)

    api.send_pad_rgb(
        row,
        col,
        SCENE_PENDING[1],
        SCENE_PENDING[2],
        SCENE_PENDING[3]
    )
end

local function load_scene(api, scene_nr)
    if not scene_api.LoadScene(scene_nr) then
        show_error(
            "scene " .. tostring(scene_nr) ..
            " is niet opgeslagen"
        )
        return false
    end

    local targets = {}

    for track = 1, 8 do
        local region = scene_api.get_pattern(track)

        if region then
            targets[track] = region

            api.set_track_and_region(track, region)
            api.pattern.select(track, region)
        end
    end

    pending_scene = scene_nr
    pending_targets = targets

    show_pending_scene(api, scene_nr)
    start_pending_watch(api)

    return true
end

local function save_scene(scene_nr)
    local success = scene_api.SaveScene(scene_nr)

    if success then
        pending_generation = pending_generation + 1
        pending_scene = nil
        pending_targets = nil
        active_scene = scene_nr
    end

    return success
end

local function select_scene_for_copy(scene_nr)
    if not scene_api.GetScene(scene_nr) then
        show_error(
            "scene " .. tostring(scene_nr) ..
            " is niet opgeslagen"
        )
        return false
    end

    selected_copy_scene = scene_nr
    return true
end

local function copy_selected_scene_to_slot(slot)
    if not selected_copy_scene then
        show_error("selecteer eerst een opgeslagen scene")
        return false
    end

    if not playlist_api.Set(slot, selected_copy_scene) then
        show_error(
            "playlist slot " .. tostring(slot) ..
            " kon niet worden opgeslagen"
        )
        return false
    end

    return true
end

local function press_scene(api, scene_nr)
    if operation == MODE_LOAD then
        return load_scene(api, scene_nr)
    elseif operation == MODE_SAVE then
        return save_scene(scene_nr)
    elseif operation == MODE_COPY then
        return select_scene_for_copy(scene_nr)
    end

    show_error(
        "onbekende operation mode " ..
        tostring(operation)
    )
    return false
end

local function drawscreen4(api)
    local C = api.COLOR

    api.drawblock(
        8, 1,
        7, 8,
        C.GREY,
        api.MODE_RADIO,
        {
            group = "scenes_patterns",
            selected_row = 8,
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "scenes_regions",
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    local function playlist_background_rgb(row, col)
        local slot = pad_to_playlist_slot(row, col)

        if playlist_api.IsFilled(slot) then
            return PLAYLIST_FILLED
        end

        return PLAYLIST_EMPTY
    end

    api.drawblock(
        5, 1,
        4, 8,
        C.OFF,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            background_rgb = playlist_background_rgb,

            on_press = function(pad)
                if operation ~= MODE_COPY then
                    return
                end

                local slot =
                    pad_to_playlist_slot(pad.row, pad.col)

                if copy_selected_scene_to_slot(slot) then
                    api.redraw()
                end
            end
        }
    )

    local displayed_scene = nil

    if operation == MODE_COPY then
        displayed_scene = selected_copy_scene
    else
        displayed_scene = active_scene
    end

    local active_row
    local active_col

    if displayed_scene then
        if displayed_scene <= 8 then
            active_row = 3
            active_col = displayed_scene
        else
            active_row = 2
            active_col = displayed_scene - 8
        end
    end

    local function scene_background_rgb(row, col)
        local scene_nr = pad_to_scene(row, col)

        if scene_nr == pending_scene then
            return SCENE_PENDING
        elseif operation == MODE_COPY then
            if scene_nr == selected_copy_scene then
                return SCENE_ACTIVE
            end
        elseif scene_nr == active_scene then
            return SCENE_ACTIVE
        elseif scene_api.GetScene(scene_nr) then
            return SCENE_SAVED
        end

        return SCENE_EMPTY
    end

    api.drawblock(
        3, 1,
        2, 8,
        C.OFF,
        api.MODE_RADIO,
        {
            group = "scene_selection",
            selected_row = active_row,
            selected_col = active_col,
            active_color = C.WHITE,
            background_rgb = scene_background_rgb,

            on_press = function(pad)
                local scene_nr =
                    pad_to_scene(pad.row, pad.col)

                if press_scene(api, scene_nr) then
                    if operation ~= MODE_LOAD then
                        api.redraw()
                    end
                end
            end
        }
    )

    if pending_scene then
        show_pending_scene(api, pending_scene)
    end

    api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "scenes_operations",
            selected_col = operation,
            active_color = C.WHITE,

            on_press = function(pad)
                operation = pad.col

                if operation == MODE_COPY then
                    selected_copy_scene = nil

                    local state = api.get_screen_state(4)
                    state.radio["scene_selection"] = nil
                end

                api.redraw()
            end
        }
    )
end

return drawscreen4
