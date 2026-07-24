-- ============================================================
-- gjs - x - fx_engine.lua
-- Resolves TrackN against the Nth open subproject tab.
-- TrackN uses the same ordering as gjs_scan_all_track_fx.lua.
-- ============================================================

local M = {}

local main_project = reaper.EnumProjects(-1, "")

local function get_subproject_by_number(number)
    number = tonumber(number)
    if not number or number < 1 then
        return nil, "invalid Track number"
    end

    local found = 0
    local index = 0

    while true do
        local project = reaper.EnumProjects(index, "")
        if not project then
            break
        end

        if project ~= main_project then
            found = found + 1
            if found == number then
                return project
            end
        end

        index = index + 1
    end

    return nil, "subproject " .. tostring(number) .. " is not open"
end

local function get_target_track(mapping)
    local project, reason = get_subproject_by_number(mapping.track_number)
    if not project then
        return nil, nil, reason
    end

    if mapping.is_master then
        return project, reaper.GetMasterTrack(project)
    end

    if reaper.CountTracks(project) < 1 then
        return project, nil, "subproject has no first track"
    end

    return project, reaper.GetTrack(project, 0)
end

function M.resolve(mapping)
    if not mapping then
        return nil, "mapping is missing"
    end

    local project, track, reason = get_target_track(mapping)
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

    local parameter_index = tonumber(mapping.parameter_index)
    if not parameter_index then
        return nil, "parameter index is invalid"
    end

    local parameter_count = reaper.TrackFX_GetNumParams(track, fx_index)
    if parameter_index < 0 or parameter_index >= parameter_count then
        return nil, string.format(
            "parameter %d not found (FX has %d parameters)",
            parameter_index,
            parameter_count
        )
    end

    -- The scanner generated these numeric indices from the same project-tab
    -- ordering. Names are retained for diagnostics only; exact name matching
    -- is deliberately not used as a blocker because REAPER/plugin builds can
    -- expose slightly different display strings.
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
