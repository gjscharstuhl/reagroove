-- ============================================================
-- gjs - x - edit.lua
-- Version 04 - explicit region selection strip
-- ============================================================
--
-- Visual layout (top to bottom):
--
-- Row 8: values  1..8   (purple)
-- Row 7: values  9..16  (purple)
-- Row 6: region selection 1..8 (light blue)
-- Row 4: scope buttons, right aligned (green)
-- Row 2: track selection 1..8 (orange)
-- Row 1: action buttons (blue)
--
-- Scope buttons:
--   col 6 = selected region, selected track
--   col 7 = selected region, all tracks
--   col 8 = all regions, all tracks
--
-- Action buttons:
--   col 1 = resize
--   col 2 = clear
-- ============================================================

local source = debug.getinfo(1, "S").source
local script_path = source:match("^@(.+)$") or ""
local script_dir = script_path:match("^(.*[/\\])") or ""

local resize = dofile(script_dir .. "gjs - x - resize.lua")
local clear = dofile(script_dir .. "gjs - x - clear.lua")

local SCOPE_SELECTED_TRACK = 1
local SCOPE_ALL_TRACKS = 2
local SCOPE_ALL_REGIONS = 3

local ACTION_RESIZE_COL = 1
local ACTION_CLEAR_COL = 2

local selected_bars = 1
local selected_track = nil
local selected_region = nil
local selected_scope = SCOPE_SELECTED_TRACK

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
            1,
            8,
            1
        )
    end

    if not selected_region then
        selected_region = clamp(
            reaper.GetExtState("GJS_MULTI", "Region"),
            1,
            8,
            1
        )
    end
end

local function execute_resize()
    if selected_scope == SCOPE_SELECTED_TRACK then
        return resize.resize_selected_region_selected_project(
            selected_track,
            selected_region,
            selected_bars
        )
    elseif selected_scope == SCOPE_ALL_TRACKS then
        return resize.resize_selected_region_all_projects(
            selected_region,
            selected_bars
        )
    elseif selected_scope == SCOPE_ALL_REGIONS then
        return resize.resize_all_regions_all_projects(
            selected_bars
        )
    end

    return false
end

local function execute_clear()
    if selected_scope == SCOPE_SELECTED_TRACK then
        clear.clear_selected_region_selected_project(
            selected_track,
            selected_region
        )
        return true
    elseif selected_scope == SCOPE_ALL_TRACKS then
        clear.clear_selected_region_all_projects(
            selected_region
        )
        return true
    elseif selected_scope == SCOPE_ALL_REGIONS then
        clear.clear_all_regions_all_projects()
        return true
    end

    return false
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

    -- Clear the complete edit canvas first.
    api.drawblock(
        8, 1,
        1, 8,
        C.OFF,
        api.MODE_NONE
    )

    -- Values 1..8.
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

    -- Values 9..16.
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

    -- Local edit region selection on the third row from the top.
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

    -- Scope selection, right aligned on row 4.
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

    -- Local edit track selection. This deliberately does not change
    -- GJS_MULTI/ActiveTrack, so the live instrument stays untouched.
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

    -- Action buttons. They execute immediately, like the bottom row
    -- operations on screen 4.
    api.drawstrip(
        1, 1, 2,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,

            on_press = function(pad)
                if pad.col == ACTION_RESIZE_COL then
                    execute_resize()
                elseif pad.col == ACTION_CLEAR_COL then
                    execute_clear()
                end

                api.redraw()
            end
        }
    )
end
