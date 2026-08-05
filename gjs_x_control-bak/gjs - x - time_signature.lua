-- ============================================================
-- gjs - x - time_signature.lua
-- Version 01 - shared time-signature editor for all project tabs
-- ============================================================
--
-- Applies the selected time signature to:
--   tab 1  : main project
--   tabs 2-10: eight instrument projects plus live recording
--
-- The current tempo of every project is preserved.
-- ============================================================

local M = {}

local PROJECT_COUNT = 10
local POSITION_TOLERANCE = 0.000001

local selected_numerator = 4
local selected_denominator = 4

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

local function read_main_time_signature()
    local project = reaper.EnumProjects(0, "")
    if not project then
        return
    end

    local numerator, denominator =
        reaper.TimeMap_GetTimeSigAtTime(project, 0)

    selected_numerator = clamp(numerator, 1, 8, 4)
    selected_denominator = clamp(denominator, 1, 8, 4)
end

local function update_marker_at_project_start(
    project,
    numerator,
    denominator
)
    if not reaper.CountTempoTimeSigMarkers
        or not reaper.GetTempoTimeSigMarker
    then
        return false
    end

    local marker_count =
        reaper.CountTempoTimeSigMarkers(project)

    for marker_index = 0, marker_count - 1 do
        local ok,
            time_position,
            measure_position,
            beat_position,
            bpm,
            _,
            _,
            linear = reaper.GetTempoTimeSigMarker(
                project,
                marker_index
            )

        if ok
            and math.abs(time_position) <= POSITION_TOLERANCE
        then
            return reaper.SetTempoTimeSigMarker(
                project,
                marker_index,
                time_position,
                measure_position,
                beat_position,
                bpm,
                numerator,
                denominator,
                linear
            )
        end
    end

    -- No marker exists at project start yet. Create one while
    -- preserving the project's current tempo at time zero.
    local _, _, tempo =
        reaper.TimeMap_GetTimeSigAtTime(project, 0)

    return reaper.SetTempoTimeSigMarker(
        project,
        -1,
        0,
        -1,
        -1,
        tempo,
        numerator,
        denominator,
        false
    )
end

local function apply_to_project(
    project,
    numerator,
    denominator
)
    update_marker_at_project_start(
        project,
        numerator,
        denominator
    )
end

function M.apply(numerator, denominator)
    selected_numerator = clamp(numerator, 1, 8, 4)
    selected_denominator = clamp(denominator, 1, 8, 4)

    reaper.Undo_BeginBlock()

    for project_index = 0, PROJECT_COUNT - 1 do
        local project =
            reaper.EnumProjects(project_index, "")

        if project then
            apply_to_project(
                project,
                selected_numerator,
                selected_denominator
            )
        end
    end

    reaper.Undo_EndBlock(
        string.format(
            "Set all project tabs to %d/%d",
            selected_numerator,
            selected_denominator
        ),
        -1
    )

    reaper.UpdateTimeline()
end

function M.open()
    read_main_time_signature()
end

function M.draw(api, C, on_close)
    -- Numerator: top row, pads 1-8.
    api.drawstrip(
        8, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_time_signature_numerator",
            selected_row = 8,
            selected_col = selected_numerator,
            active_color = C.WHITE,
            on_press = function(pad)
                M.apply(pad.col, selected_denominator)
                api.redraw()
            end
        }
    )

    -- Denominator: row directly below, pads 1-8.
    api.drawstrip(
        7, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_time_signature_denominator",
            selected_row = 7,
            selected_col = selected_denominator,
            active_color = C.WHITE,
            on_press = function(pad)
                M.apply(selected_numerator, pad.col)
                api.redraw()
            end
        }
    )

    -- Pad 1,4 closes the time-signature editor.
    api.drawpad(
        1, 4,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                if on_close then
                    on_close()
                end
                api.redraw()
            end
        }
    )
end

function M.get_selected()
    return selected_numerator, selected_denominator
end

return M
