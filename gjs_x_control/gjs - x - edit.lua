-- ============================================================
-- gjs - x - edit.lua
-- Version 07 - subproject track selector on action pad 5
-- ============================================================

local source = debug.getinfo(1, "S").source
local script_path = source:match("^@(.+)$") or ""
local script_dir = script_path:match("^(.*[/\\])") or ""

local resize = dofile(script_dir .. "gjs - x - resize.lua")
local clear = dofile(script_dir .. "gjs - x - clear.lua")
local merge = dofile(script_dir .. "gjs - x - merge.lua")
local time_signature = dofile(
    script_dir .. "gjs - x - time_signature.lua"
)
local subproject_track = dofile(
    script_dir .. "gjs - x - subproject_track.lua"
)

local SCOPE_SELECTED_TRACK = 1
local SCOPE_ALL_TRACKS = 2
local SCOPE_ALL_REGIONS = 3

local MERGE_SELECTED_PROJECT = 1
local MERGE_ALL_PROJECTS = 2

local ACTION_RESIZE_COL = 1
local ACTION_CLEAR_COL = 2
local ACTION_MERGE_COL = 3
local ACTION_TIME_SIGNATURE_COL = 4
local ACTION_TRACK_SELECT_COL = 5

local selected_bars = 1
local selected_track = nil
local selected_region = nil
local selected_scope = SCOPE_SELECTED_TRACK

local time_signature_mode = false
local track_select_mode = false
local clear_mode = false
local clear_items = false
local clear_fx = false

local merge_mode = false
local merge_scope = MERGE_SELECTED_PROJECT
local merge_sequence = {}
local MAX_MERGE_STEPS = 16

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value)

    if not value then
        return fallback
    end

    value = math.floor(value)

    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end

    return value
end

local function read_main_selection_once()
    if not selected_track then
        selected_track = clamp(
            reaper.GetExtState("GJS_MULTI", "ActiveTrack"),
            1, 8, 1
        )
    end

    if not selected_region then
        selected_region = clamp(
            reaper.GetExtState("GJS_MULTI", "Region"),
            1, 8, 1
        )
    end
end

local function execute_resize()
    if selected_scope == SCOPE_SELECTED_TRACK then
        return resize.resize_selected_region_selected_project(
            selected_track, selected_region, selected_bars
        )
    elseif selected_scope == SCOPE_ALL_TRACKS then
        return resize.resize_selected_region_all_projects(
            selected_region, selected_bars
        )
    elseif selected_scope == SCOPE_ALL_REGIONS then
        return resize.resize_all_regions_all_projects(selected_bars)
    end

    return false
end

local function execute_clear()
    if not clear_items and not clear_fx then
        return false
    end

    local options = {
        items = clear_items,
        fx = clear_fx
    }

    if selected_scope == SCOPE_SELECTED_TRACK then
        clear.clear_selected_region_selected_project(
            selected_track,
            selected_region,
            options
        )
        return true
    elseif selected_scope == SCOPE_ALL_TRACKS then
        clear.clear_selected_region_all_projects(
            selected_region,
            options
        )
        return true
    elseif selected_scope == SCOPE_ALL_REGIONS then
        clear.clear_all_regions_all_projects(options)
        return true
    end

    return false
end

local function draw_clear_mode(api, C)
    local off_items = { 30, 20, 0 }
    local off_fx = { 24, 0, 30 }

    -- Items toggle.
    api.drawpad(
        8,
        1,
        clear_items and C.YELLOW or off_items,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                clear_items = not clear_items
                api.redraw()
            end
        }
    )

    -- FX/automation toggle.
    api.drawpad(
        8,
        2,
        clear_fx and C.PURPLE or off_fx,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                clear_fx = not clear_fx
                api.redraw()
            end
        }
    )

    -- Keep scope, region and project visible/editable in this subscreen.
    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_clear_region",
            selected_row = 6,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        4, 6, 8,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_clear_scope",
            selected_col = 5 + selected_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_scope = pad.col - 5
                api.redraw()
            end
        }
    )

    api.drawstrip(
        2, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_clear_track",
            selected_col = selected_track,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_track = pad.col
                api.redraw()
            end
        }
    )

    -- Pad 2 confirms; pad 5 closes without clearing.
    api.drawpad(
        1,
        ACTION_CLEAR_COL,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                if execute_clear() then
                    clear_mode = false
                end
                api.redraw()
            end
        }
    )

    api.drawpad(
        1,
        ACTION_TRACK_SELECT_COL,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                clear_mode = false
                api.redraw()
            end
        }
    )
end

local function execute_merge()
    if #merge_sequence == 0 then
        return false
    end

    local ok, error_message

    if merge_scope == MERGE_SELECTED_PROJECT then
        ok, error_message = merge.merge_selected_project(
            selected_track,
            merge_sequence,
            selected_region
        )
    else
        ok, error_message = merge.merge_all_projects(
            merge_sequence,
            selected_region
        )
    end

    if not ok and error_message then
        reaper.ShowConsoleMsg(
            "Pattern merge failed: " .. tostring(error_message) .. "\n"
        )
    end

    return ok
end

local function region_colour(C, region_number)
    local colours = {
        C.RED,
        C.ORANGE,
        C.YELLOW,
        C.GREEN,
        C.LIGHT_BLUE,
        C.BLUE,
        C.PURPLE,
        C.MAGENTA
    }

    return colours[region_number] or C.WHITE
end

local function append_merge_region(region_number)
    if #merge_sequence >= MAX_MERGE_STEPS then
        return
    end

    merge_sequence[#merge_sequence + 1] = region_number
end

local function draw_merge_sequence(api, C)
    -- Top two rows are display-only.
    for row = 8, 7, -1 do
        for col = 1, 8 do
            local sequence_index = (8 - row) * 8 + col
            local source_region = merge_sequence[sequence_index]
            local colour = source_region
                and region_colour(C, source_region)
                or C.OFF

            api.drawpad(row, col, colour, api.MODE_NONE)
        end
    end
end

local function draw_merge_source_selection(api, C)
    -- Rows 6 and 5 are source-region selectors.
    for row = 6, 5, -1 do
        for col = 1, 8 do
            api.drawpad(
                row,
                col,
                region_colour(C, col),
                api.MODE_HIGHLIGHT,
                {
                    active_color = C.WHITE,
                    on_press = function(pad)
                        append_merge_region(pad.col)
                        api.redraw()
                    end
                }
            )
        end
    end
end

local function draw_merge_mode(api, C)
    draw_merge_sequence(api, C)
    draw_merge_source_selection(api, C)

    api.drawstrip(
        4, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_merge_target_region",
            selected_row = 4,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        3, 1, 2,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_merge_scope",
            selected_row = 3,
            selected_col = merge_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                merge_scope = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        2, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_track",
            selected_row = 2,
            selected_col = selected_track,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_track = pad.col
                api.redraw()
            end
        }
    )

    api.drawpad(
        1,
        ACTION_CLEAR_COL,
        C.RED,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                merge_sequence[#merge_sequence] = nil
                api.redraw()
            end
        }
    )

    api.drawpad(
        1,
        ACTION_MERGE_COL,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                if execute_merge() then
                    merge_mode = false
                    merge_sequence = {}
                end

                api.redraw()
            end
        }
    )
end

return function(api, navigation)
    local C = api.COLOR

    read_main_selection_once()

    if api.set_screen0_main_active then
        api.set_screen0_main_active(false)
    end

    if api.set_navigation then
        api.set_navigation(
            navigation and navigation.open_main or nil,
            nil
        )
    end

    api.drawblock(8, 1, 1, 8, C.OFF, api.MODE_NONE)

    if time_signature_mode then
        time_signature.draw(
            api,
            C,
            function()
                time_signature_mode = false
            end
        )
        return
    end

    if track_select_mode then
        subproject_track.draw(
            api, C, selected_track,
            function() track_select_mode = false end
        )
        return
    end

    if clear_mode then
        draw_clear_mode(api, C)
        return
    end

    if merge_mode then
        draw_merge_mode(api, C)
        return
    end

    api.drawstrip(
        8, 1, 8,
        C.PURPLE,
        api.MODE_RADIO,
        {
            group = "edit_value_1_16",
            selected_row = selected_bars <= 8 and 8 or 7,
            selected_col = selected_bars <= 8
                and selected_bars
                or selected_bars - 8,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_bars = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        7, 1, 8,
        C.PURPLE,
        api.MODE_RADIO,
        {
            group = "edit_value_1_16",
            selected_row = selected_bars <= 8 and 8 or 7,
            selected_col = selected_bars <= 8
                and selected_bars
                or selected_bars - 8,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_bars = 8 + pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_region",
            selected_row = 6,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        4, 6, 8,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_scope",
            selected_col = 5 + selected_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_scope = pad.col - 5
                api.redraw()
            end
        }
    )

    api.drawstrip(
        2, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_track",
            selected_col = selected_track,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_track = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        1, 1, 5,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function(pad)
                if pad.col == ACTION_RESIZE_COL then
                    execute_resize()
                elseif pad.col == ACTION_CLEAR_COL then
                    -- Start every Clear session with both actions disabled.
                    clear_items = false
                    clear_fx = false
                    clear_mode = true
                elseif pad.col == ACTION_MERGE_COL then
                    merge_mode = true
                    merge_sequence = {}
                elseif pad.col == ACTION_TIME_SIGNATURE_COL then
                    time_signature.open()
                    time_signature_mode = true
                elseif pad.col == ACTION_TRACK_SELECT_COL then
                    track_select_mode = true
                end

                api.redraw()
            end
        }
    )
end
