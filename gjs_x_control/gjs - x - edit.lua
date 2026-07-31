-- ============================================================
-- gjs - x - edit.lua
-- Version 06 - time-signature mode on action pad 4
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

local SCOPE_SELECTED_TRACK = 1
local SCOPE_ALL_TRACKS = 2
local SCOPE_ALL_REGIONS = 3

local MERGE_SELECTED_PROJECT = 1
local MERGE_ALL_PROJECTS = 2

local ACTION_RESIZE_COL = 1
local ACTION_CLEAR_COL = 2
local ACTION_MERGE_COL = 3
local ACTION_TIME_SIGNATURE_COL = 4

local selected_bars = 1
local selected_track = nil
local selected_region = nil
local selected_scope = SCOPE_SELECTED_TRACK

local time_signature_mode = false

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
    if selected_scope == SCOPE_SELECTED_TRACK then
        clear.clear_selected_region_selected_project(
            selected_track, selected_region
        )
        return true
    elseif selected_scope == SCOPE_ALL_TRACKS then
        clear.clear_selected_region_all_projects(selected_region)
        return true
    elseif selected_scope == SCOPE_ALL_REGIONS then
        clear.clear_all_regions_all_projects()
        return true
    end

    return false
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
    -- All sixteen pads are sequence feedback. Their column also acts
    -- as the source-region number, so repeatedly pressing the upper
    -- left pad appends region 1 repeatedly.
    for row = 8, 7, -1 do
        for col = 1, 8 do
            local sequence_index = (8 - row) * 8 + col
            local source_region = merge_sequence[sequence_index]
            local colour = source_region
                and region_colour(C, source_region)
                or C.OFF

            api.drawpad(
                row,
                col,
                colour,
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

    -- Target region.
    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_merge_target_region",
            selected_row = 6,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    -- Merge scope: selected project or all eight subprojects.
    api.drawstrip(
        4, 1, 2,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_merge_scope",
            selected_col = merge_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                merge_scope = pad.col
                api.redraw()
            end
        }
    )

    -- Project/track selection. This never changes the live instrument.
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

    -- Pad 3 confirms. Pad 2 removes the last entered step.
    api.drawstrip(
        1, 2, 3,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function(pad)
                if pad.col == ACTION_CLEAR_COL then
                    merge_sequence[#merge_sequence] = nil
                elseif pad.col == ACTION_MERGE_COL then
                    if execute_merge() then
                        merge_mode = false
                        merge_sequence = {}
                    end
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
        1, 1, 4,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function(pad)
                if pad.col == ACTION_RESIZE_COL then
                    execute_resize()
                elseif pad.col == ACTION_CLEAR_COL then
                    execute_clear()
                elseif pad.col == ACTION_MERGE_COL then
                    merge_mode = true
                    merge_sequence = {}
                elseif pad.col == ACTION_TIME_SIGNATURE_COL then
                    time_signature.open()
                    time_signature_mode = true
                end

                api.redraw()
            end
        }
    )
end
