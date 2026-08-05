-- ============================================================
-- gjs - x - fx_engine.lua
--
-- Natural visible-tab resolution:
--   Tab1 -> REAPER project index 0
--   Tab2 -> REAPER project index 1
--   ...
--   Tab8 -> REAPER project index 7
-- ============================================================

local M = {}
local subproject_track =
    include("gjs - x - subproject_track.lua")

local function get_project_by_tab_number(tab_number)
    tab_number = tonumber(tab_number)

    if not tab_number then
        return nil, "invalid Tab number"
    end

    tab_number = math.floor(tab_number)

    if tab_number < 1 or tab_number > 8 then
        return nil, "Tab number must be between 1 and 8"
    end

    local project =
        reaper.EnumProjects(tab_number - 1, "")

    if not project then
        return nil,
            "Tab" .. tostring(tab_number) .. " is not open"
    end

    return project
end

local function get_target_track(mapping)
    local project, reason =
        get_project_by_tab_number(mapping.tab_number)

    if not project then
        return nil, nil, reason
    end

    if mapping.is_master then
        return project, reaper.GetMasterTrack(project)
    end

    local track_number =
        tonumber(mapping.reaper_track_number)

    if track_number then
        track_number = math.floor(track_number)

        if track_number < 1 then
            return project, nil,
                "Track number must be at least 1"
        end

        local track =
            reaper.GetTrack(project, track_number - 1)

        if not track then
            return project, nil, string.format(
                "Track%d not found in Tab%d",
                track_number,
                mapping.tab_number
            )
        end

        return project, track
    end

    -- Compatibility with old mappings that targeted the selected
    -- top-level track instead of an explicit REAPER track number.
    if reaper.CountTracks(project) < 1 then
        return project, nil, "project has no tracks"
    end

    return project,
        subproject_track.get_selected_track(project)
end

function M.resolve(mapping)
    if not mapping then
        return nil, "mapping is missing"
    end

    local project, track, reason =
        get_target_track(mapping)

    if not track then
        return nil, reason or "target track not found"
    end

    local fx_index = tonumber(mapping.fx_index)

    if not fx_index then
        return nil, "FX index is invalid"
    end

    local fx_count = reaper.TrackFX_GetCount(track)

    if fx_index < 0 or fx_index >= fx_count then
        return nil, string.format(
            "FX%d not found (track has %d FX)",
            fx_index + 1,
            fx_count
        )
    end

    local parameter_index =
        tonumber(mapping.parameter_index)

    if not parameter_index then
        return nil, "parameter index is invalid"
    end

    local parameter_count =
        reaper.TrackFX_GetNumParams(track, fx_index)

    if parameter_index < 0
    or parameter_index >= parameter_count then
        return nil, string.format(
            "parameter %d not found (FX has %d parameters)",
            parameter_index,
            parameter_count
        )
    end

    return {
        project = project,
        track = track,
        fx_index = fx_index,
        parameter_index = parameter_index
    }
end

function M.get_value(mapping)
    local target, reason = M.resolve(mapping)

    if not target then
        return nil, reason
    end

    return reaper.TrackFX_GetParamNormalized(
        target.track,
        target.fx_index,
        target.parameter_index
    )
end

function M.set_value(mapping, value)
    local target, reason = M.resolve(mapping)

    if not target then
        return false, reason
    end

    value = tonumber(value)

    if not value then
        return false, "value is not numeric"
    end

    value = math.max(0, math.min(1, value))

    reaper.TrackFX_SetParamNormalized(
        target.track,
        target.fx_index,
        target.parameter_index,
        value
    )

    return true
end

return M
