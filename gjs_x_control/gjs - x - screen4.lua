local scene_api = include("gjs - scene_api.lua")

local MODE_LOAD = 1
local MODE_SAVE = 2
local MODE_COPY = 3

local operation = MODE_LOAD
local active_scene = 1

local SCENE_EMPTY  = { 10, 3, 0 }
local SCENE_SAVED  = { 127, 35, 0 }
local SCENE_ACTIVE = { 127, 127, 127 }

local function pad_to_scene(row, col)
    return ((3 - row) * 8) + col
end

local function show_error(message)
    reaper.ShowConsoleMsg(
        "Screen 4: " .. tostring(message) .. "\n"
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

    for track = 1, 8 do
        local region = scene_api.get_pattern(track)

        if region then
            api.set_track_and_region(track, region)
            api.pattern.select(track, region)
        end
    end

    return true
end

local function save_scene(scene_nr)
    return scene_api.SaveScene(scene_nr)
end

local function copy_scene_to_playlist(scene_nr)
    show_error(
        "copy-to-playlist is nog niet aangesloten " ..
        "(scene " .. tostring(scene_nr) .. ")"
    )
    return false
end

local function do_operation(api, scene_nr)
    if operation == MODE_LOAD then
        return load_scene(api, scene_nr)
    elseif operation == MODE_SAVE then
        return save_scene(scene_nr)
    elseif operation == MODE_COPY then
        return copy_scene_to_playlist(scene_nr)
    end

    show_error("onbekende operation mode " .. tostring(operation))
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

    api.drawblock(
        5, 1,
        4, 8,
        C.GREEN,
        api.MODE_TOGGLE,
        {
            active_color = C.WHITE
        }
    )

    local active_row
    local active_col

    if active_scene <= 8 then
        active_row = 3
        active_col = active_scene
    else
        active_row = 2
        active_col = active_scene - 8
    end

    local function scene_background_rgb(row, col)
        local scene_nr = pad_to_scene(row, col)

        if scene_nr == active_scene then
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

                if do_operation(api, scene_nr) then
                    active_scene = scene_nr
                end

                api.redraw()
            end
        }
    )

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
                api.redraw()
            end
        }
    )
end

return drawscreen4
