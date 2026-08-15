-- ============================================================
-- Screen 0 resize engine
-- Version 03 - always reselect resized region after operation
-- ============================================================
--
-- Page 2: resize all 8 regions in all subprojects
-- Page 3: resize selected region in all subprojects
-- Page 4: resize selected region in selected subproject
--
-- Project 0 is the main project. Projects 1 through 7 are subprojects.
-- The chosen bar count is applied to subprojects only. Afterwards the
-- matching main-project region is resized to the scene length: the
-- longest matching region found across projects 1 through 7.
-- ============================================================

local M = {}

local TOLERANCE = 0.000001
local REGION_COUNT = 8
local LAST_SUBPROJECT_INDEX = 7

local function almost_equal(a, b)
    return math.abs(a - b) <= TOLERANCE
end

local function get_all_regions(proj)
    local regions = {}
    local _, marker_count, region_count =
        reaper.CountProjectMarkers(proj)

    local total = marker_count + region_count

    for index = 0, total - 1 do
        local ok, is_region, start_pos, end_pos, name, id =
            reaper.EnumProjectMarkers2(proj, index)

        if ok and is_region then
            regions[#regions + 1] = {
                id = id,
                start_pos = start_pos,
                end_pos = end_pos,
                name = name or ""
            }
        end
    end

    table.sort(regions, function(a, b)
        return a.start_pos < b.start_pos
    end)

    return regions
end


local function select_region(track_number, region_number)
    track_number = tonumber(track_number) or 1
    region_number = tonumber(region_number) or 1

    local project_index = math.floor(track_number) - 1
    local proj = reaper.EnumProjects(project_index, "")
    if not proj then
        return false
    end

    local region = get_all_regions(proj)[region_number]
    if not region then
        return false
    end

    reaper.GetSet_LoopTimeRange2(
        proj,
        true,
        false,
        region.start_pos,
        region.end_pos,
        false
    )

    reaper.SetEditCurPos2(
        proj,
        region.start_pos,
        false,
        false
    )

    reaper.SetExtState(
        "GJS_MULTI",
        "Region",
        tostring(region_number),
        false
    )

    reaper.SetExtState(
        "GJS_X",
        "Region",
        tostring(region_number),
        false
    )

    return true
end

local function get_qn_per_bar_at_time(proj, time)
    local numerator, denominator =
        reaper.TimeMap_GetTimeSigAtTime(proj, time)

    if not numerator or numerator < 1 then
        numerator = 4
    end

    if not denominator or denominator < 1 then
        denominator = 4
    end

    return numerator * (4 / denominator)
end

local function bars_to_time_from(proj, start_time, bars)
    local start_qn =
        reaper.TimeMap2_timeToQN(proj, start_time)

    local end_qn =
        start_qn
        + bars * get_qn_per_bar_at_time(proj, start_time)

    return reaper.TimeMap2_QNToTime(proj, end_qn)
end

local function region_length_in_bars(proj, region)
    if not region then
        return nil
    end

    local start_qn =
        reaper.TimeMap2_timeToQN(proj, region.start_pos)

    local end_qn =
        reaper.TimeMap2_timeToQN(proj, region.end_pos)

    local qn_per_bar =
        get_qn_per_bar_at_time(proj, region.start_pos)

    if qn_per_bar <= 0 then
        return nil
    end

    return (end_qn - start_qn) / qn_per_bar
end

local function shift_regions_after(
    proj,
    region_index,
    shift_amount,
    regions
)
    for index = #regions, region_index + 1, -1 do
        local region = regions[index]

        reaper.SetProjectMarker2(
            proj,
            region.id,
            true,
            region.start_pos + shift_amount,
            region.end_pos + shift_amount,
            region.name
        )
    end
end

local function shift_items_from(proj, time_pos, shift_amount)
    for index = reaper.CountMediaItems(proj) - 1, 0, -1 do
        local item = reaper.GetMediaItem(proj, index)
        local position =
            reaper.GetMediaItemInfo_Value(item, "D_POSITION")

        if position >= time_pos - TOLERANCE then
            reaper.SetMediaItemInfo_Value(
                item,
                "D_POSITION",
                position + shift_amount
            )
        end
    end
end

local function trim_items_to_new_region(
    proj,
    old_start,
    old_end,
    new_start,
    new_end
)
    for index = reaper.CountMediaItems(proj) - 1, 0, -1 do
        local item = reaper.GetMediaItem(proj, index)

        local item_start =
            reaper.GetMediaItemInfo_Value(item, "D_POSITION")

        local item_length =
            reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

        local item_end = item_start + item_length

        local was_in_old_region =
            item_end > old_start + TOLERANCE
            and item_start < old_end - TOLERANCE

        if was_in_old_region then
            local new_item_start =
                math.max(item_start, new_start)

            local new_item_end =
                math.min(item_end, new_end)

            local new_item_length =
                new_item_end - new_item_start

            if new_item_length <= TOLERANCE then
                reaper.DeleteTrackMediaItem(
                    reaper.GetMediaItem_Track(item),
                    item
                )
            else
                local trim_left =
                    new_item_start - item_start

                if trim_left > TOLERANCE then
                    for take_index = 0,
                        reaper.CountTakes(item) - 1
                    do
                        local take =
                            reaper.GetTake(item, take_index)

                        if take then
                            local start_offset =
                                reaper.GetMediaItemTakeInfo_Value(
                                    take,
                                    "D_STARTOFFS"
                                )

                            local playrate =
                                reaper.GetMediaItemTakeInfo_Value(
                                    take,
                                    "D_PLAYRATE"
                                )

                            reaper.SetMediaItemTakeInfo_Value(
                                take,
                                "D_STARTOFFS",
                                start_offset
                                + trim_left * playrate
                            )
                        end
                    end
                end

                reaper.SetMediaItemInfo_Value(
                    item,
                    "D_POSITION",
                    new_item_start
                )

                reaper.SetMediaItemInfo_Value(
                    item,
                    "D_LENGTH",
                    new_item_length
                )
            end
        end
    end
end

local function resize_region_to_bars(
    proj,
    region_number,
    bars,
    trim_items
)
    local regions = get_all_regions(proj)
    local region = regions[region_number]

    if not region then
        return false
    end

    local old_start = region.start_pos
    local old_end = region.end_pos
    local new_end =
        bars_to_time_from(proj, old_start, bars)

    local delta = new_end - old_end

    if almost_equal(delta, 0) then
        return false
    end

    if trim_items then
        trim_items_to_new_region(
            proj,
            old_start,
            old_end,
            old_start,
            new_end
        )

        shift_items_from(proj, old_end, delta)
    end

    reaper.SetProjectMarker2(
        proj,
        region.id,
        true,
        old_start,
        new_end,
        region.name
    )

    shift_regions_after(
        proj,
        region_number,
        delta,
        regions
    )

    return true
end

local function get_scene_length(region_number)
    local longest = nil

    for project_index = 1, LAST_SUBPROJECT_INDEX do
        local proj = reaper.EnumProjects(project_index, "")

        if proj then
            local region =
                get_all_regions(proj)[region_number]

            local bars =
                region_length_in_bars(proj, region)

            if bars
            and (not longest or bars > longest) then
                longest = bars
            end
        end
    end

    return longest
end

local function resize_main_region_to_scene_length(region_number)
    local main_proj = reaper.EnumProjects(0, "")

    if not main_proj then
        return false
    end

    local scene_bars =
        get_scene_length(region_number)

    if not scene_bars then
        return false
    end

    return resize_region_to_bars(
        main_proj,
        region_number,
        scene_bars,
        false
    )
end

local function begin_project_undo(proj)
    reaper.Undo_BeginBlock2(proj)
end

local function end_project_undo(proj, description)
    reaper.Undo_EndBlock2(proj, description, -1)
end

function M.resize_all_regions_all_projects(
    bars,
    selected_track,
    selected_region
)
    bars = tonumber(bars)

    if not bars or bars < 1 or bars > 16 then
        return false
    end

    reaper.PreventUIRefresh(1)

    for project_index = 1, LAST_SUBPROJECT_INDEX do
        local proj = reaper.EnumProjects(project_index, "")

        if proj then
            begin_project_undo(proj)

            -- Work backwards so earlier region positions remain stable.
            for region_number = REGION_COUNT, 1, -1 do
                resize_region_to_bars(
                    proj,
                    region_number,
                    bars,
                    true
                )
            end

            end_project_undo(
                proj,
                "Resize all regions to "
                .. tostring(bars)
                .. " bars"
            )
        end
    end

    local main_proj = reaper.EnumProjects(0, "")

    if main_proj then
        begin_project_undo(main_proj)

        for region_number = REGION_COUNT, 1, -1 do
            resize_main_region_to_scene_length(region_number)
        end

        end_project_undo(
            main_proj,
            "Resize main regions to scene lengths"
        )
    end

    reaper.PreventUIRefresh(-1)

    select_region(
        tonumber(selected_track)
            or tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
            or 1,
        tonumber(selected_region)
            or tonumber(reaper.GetExtState("GJS_MULTI", "Region"))
            or 1
    )

    reaper.UpdateArrange()

    return true
end

function M.resize_selected_region_all_projects(
    region_number,
    bars,
    selected_track
)
    region_number = tonumber(region_number)
    bars = tonumber(bars)

    if not region_number
    or region_number < 1
    or region_number > REGION_COUNT
    or not bars
    or bars < 1
    or bars > 16
    then
        return false
    end

    reaper.PreventUIRefresh(1)

    for project_index = 1, LAST_SUBPROJECT_INDEX do
        local proj = reaper.EnumProjects(project_index, "")

        if proj then
            begin_project_undo(proj)

            resize_region_to_bars(
                proj,
                region_number,
                bars,
                true
            )

            end_project_undo(
                proj,
                "Resize region "
                .. tostring(region_number)
                .. " to "
                .. tostring(bars)
                .. " bars"
            )
        end
    end

    local main_proj = reaper.EnumProjects(0, "")

    if main_proj then
        if create_undo_points then begin_project_undo(main_proj) end

        resize_main_region_to_scene_length(region_number)

        if create_undo_points then
            end_project_undo(
                main_proj,
                "Resize main region "
                .. tostring(region_number)
                .. " to scene length"
            )
        end
    end

    reaper.PreventUIRefresh(-1)

    select_region(
        tonumber(selected_track)
            or tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
            or 1,
        region_number
    )

    reaper.UpdateArrange()

    return true
end

local function resize_selected_region_selected_project_impl(
    active_track,
    region_number,
    bars,
    create_undo_points
)
    active_track = tonumber(active_track)
    region_number = tonumber(region_number)
    bars = tonumber(bars)

    if not active_track
    or active_track < 1
    or active_track > 8
    or not region_number
    or region_number < 1
    or region_number > REGION_COUNT
    or not bars
    or bars < 1
    or bars > 16
    then
        return false
    end

    local project_index = active_track - 1

    -- Project 0 is the main project. A selected-project resize is meant
    -- for subprojects only; the main region is derived from their maximum.
    if project_index < 1 or project_index > LAST_SUBPROJECT_INDEX then
        return false
    end

    local proj =
        reaper.EnumProjects(project_index, "")

    if not proj then
        return false
    end

    reaper.PreventUIRefresh(1)

    if create_undo_points then begin_project_undo(proj) end

    resize_region_to_bars(
        proj,
        region_number,
        bars,
        true
    )

    if create_undo_points then
        end_project_undo(
            proj,
            "Resize region "
            .. tostring(region_number)
            .. " to "
            .. tostring(bars)
            .. " bars"
        )
    end

    local main_proj = reaper.EnumProjects(0, "")

    if main_proj then
        if create_undo_points then begin_project_undo(main_proj) end

        resize_main_region_to_scene_length(region_number)

        if create_undo_points then
            end_project_undo(
                main_proj,
                "Resize main region "
                .. tostring(region_number)
                .. " to scene length"
            )
        end
    end

    reaper.PreventUIRefresh(-1)

    -- Resizing can move the time selection/region context. Restore the
    -- operated region explicitly so edit mode stays focused on it.
    select_region(active_track, region_number)

    reaper.UpdateArrange()

    return true
end

function M.resize_selected_region_selected_project(
    active_track,
    region_number,
    bars
)
    return resize_selected_region_selected_project_impl(
        active_track, region_number, bars, true
    )
end

function M.resize_selected_region_selected_project_no_undo(
    active_track,
    region_number,
    bars
)
    return resize_selected_region_selected_project_impl(
        active_track, region_number, bars, false
    )
end

-- Public helper for callers that continue modifying the project after a
-- resize. Those later operations can change the edit/time-selection context,
-- so they can explicitly reselect the operated region once they are done.
function M.select_region(active_track, region_number)
    return select_region(active_track, region_number)
end

return M
