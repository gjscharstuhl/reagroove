-- ============================================================
-- gjs - x - merge.lua
-- Merge a sequence of source regions into one target region.
-- Version 02 - resize timeline, keep regions aligned and select result
-- ============================================================

local M = {}

local EPSILON = 0.000001
local REGION_COUNT = 8
local SUBPROJECT_COUNT = 8

local function get_project(track_number)
    track_number = tonumber(track_number)

    if not track_number then
        return nil
    end

    track_number = math.floor(track_number)

    if track_number < 1 or track_number > SUBPROJECT_COUNT then
        return nil
    end

    -- Natural visible-tab flow:
    -- Tab/track 1 -> REAPER project 0
    -- ...
    -- Tab/track 8 -> REAPER project 7
    return reaper.EnumProjects(track_number - 1, "")
end

local function get_regions(project)
    local regions = {}
    local _, marker_count, region_count =
        reaper.CountProjectMarkers(project)

    local total = marker_count + region_count

    for index = 0, total - 1 do
        local ok,
              is_region,
              position,
              region_end,
              name,
              id,
              color =
            reaper.EnumProjectMarkers3(project, index)

        if ok and is_region then
            regions[#regions + 1] = {
                id = id,
                position = position,
                region_end = region_end,
                name = name or "",
                color = color or 0
            }
        end
    end

    table.sort(regions, function(left, right)
        return left.position < right.position
    end)

    return regions
end

local function replace_chunk_number(chunk, key, value)
    local replacement =
        string.format("%s %.14f", key, value)

    local pattern = "\n" .. key .. " [^\n]+"

    if chunk:find(pattern) then
        return chunk:gsub(
            pattern,
            "\n" .. replacement,
            1
        )
    end

    return chunk
end

local function capture_region_items(project, region)
    local captured = {}

    for track_index = 0,
        reaper.CountTracks(project) - 1
    do
        local track =
            reaper.GetTrack(project, track_index)

        for item_index = 0,
            reaper.CountTrackMediaItems(track) - 1
        do
            local item =
                reaper.GetTrackMediaItem(
                    track,
                    item_index
                )

            local position =
                reaper.GetMediaItemInfo_Value(
                    item,
                    "D_POSITION"
                )

            local length =
                reaper.GetMediaItemInfo_Value(
                    item,
                    "D_LENGTH"
                )

            local item_end = position + length

            if position < region.region_end - EPSILON
            and item_end > region.position + EPSILON then
                local ok, chunk =
                    reaper.GetItemStateChunk(
                        item,
                        "",
                        false
                    )

                if ok then
                    captured[#captured + 1] = {
                        track_index = track_index,
                        chunk = chunk,
                        relative_position =
                            position - region.position,
                        length = length
                    }
                end
            end
        end
    end

    return captured
end

local function delete_items_in_range(
    project,
    range_start,
    range_end
)
    for track_index = 0,
        reaper.CountTracks(project) - 1
    do
        local track =
            reaper.GetTrack(project, track_index)

        for item_index =
            reaper.CountTrackMediaItems(track) - 1,
            0,
            -1
        do
            local item =
                reaper.GetTrackMediaItem(
                    track,
                    item_index
                )

            local position =
                reaper.GetMediaItemInfo_Value(
                    item,
                    "D_POSITION"
                )

            local length =
                reaper.GetMediaItemInfo_Value(
                    item,
                    "D_LENGTH"
                )

            local item_end = position + length

            if position < range_end - EPSILON
            and item_end > range_start + EPSILON then
                reaper.DeleteTrackMediaItem(track, item)
            end
        end
    end
end

local function shift_items_from(
    project,
    time_position,
    shift_amount
)
    if math.abs(shift_amount) <= EPSILON then
        return
    end

    for index =
        reaper.CountMediaItems(project) - 1,
        0,
        -1
    do
        local item = reaper.GetMediaItem(project, index)

        local position =
            reaper.GetMediaItemInfo_Value(
                item,
                "D_POSITION"
            )

        if position >= time_position - EPSILON then
            reaper.SetMediaItemInfo_Value(
                item,
                "D_POSITION",
                position + shift_amount
            )
        end
    end
end

local function shift_regions_after(
    project,
    target_region_index,
    shift_amount,
    regions
)
    if math.abs(shift_amount) <= EPSILON then
        return
    end

    -- Work backwards, exactly like the resize engine.
    for index = #regions,
        target_region_index + 1,
        -1
    do
        local region = regions[index]

        reaper.SetProjectMarker3(
            project,
            region.id,
            true,
            region.position + shift_amount,
            region.region_end + shift_amount,
            region.name,
            region.color
        )
    end
end

local function paste_captured_items(
    project,
    captured,
    destination_start
)
    for _, source_item in ipairs(captured) do
        local track =
            reaper.GetTrack(
                project,
                source_item.track_index
            )

        if track then
            local item =
                reaper.AddMediaItemToTrack(track)

            local position =
                destination_start
                + source_item.relative_position

            local chunk = replace_chunk_number(
                source_item.chunk,
                "POSITION",
                position
            )

            reaper.SetItemStateChunk(
                item,
                chunk,
                false
            )

            reaper.SetMediaItemInfo_Value(
                item,
                "D_POSITION",
                position
            )

            reaper.SetMediaItemInfo_Value(
                item,
                "D_LENGTH",
                source_item.length
            )
        end
    end
end

local function get_qn_per_bar_at_time(project, time)
    local numerator, denominator =
        reaper.TimeMap_GetTimeSigAtTime(
            project,
            time
        )

    if not numerator or numerator < 1 then
        numerator = 4
    end

    if not denominator or denominator < 1 then
        denominator = 4
    end

    return numerator * (4 / denominator)
end

local function region_length_in_bars(project, region)
    if not region then
        return nil
    end

    local start_qn =
        reaper.TimeMap2_timeToQN(
            project,
            region.position
        )

    local end_qn =
        reaper.TimeMap2_timeToQN(
            project,
            region.region_end
        )

    local qn_per_bar =
        get_qn_per_bar_at_time(
            project,
            region.position
        )

    if qn_per_bar <= 0 then
        return nil
    end

    return (end_qn - start_qn) / qn_per_bar
end

local function bars_to_time_from(
    project,
    start_time,
    bars
)
    local start_qn =
        reaper.TimeMap2_timeToQN(
            project,
            start_time
        )

    local end_qn =
        start_qn
        + bars
        * get_qn_per_bar_at_time(
            project,
            start_time
        )

    return reaper.TimeMap2_QNToTime(
        project,
        end_qn
    )
end

local function get_scene_length_in_bars(region_number)
    local longest = nil

    -- Scan visible tabs 1..8, which are REAPER projects 0..7.
    for project_index = 0, SUBPROJECT_COUNT - 1 do
        local project =
            reaper.EnumProjects(project_index, "")

        if project then
            local region =
                get_regions(project)[region_number]

            local bars =
                region_length_in_bars(
                    project,
                    region
                )

            if bars
            and (not longest or bars > longest) then
                longest = bars
            end
        end
    end

    return longest
end

local function resize_main_region_to_scene_length(
    region_number
)
    local main_project =
        reaper.EnumProjects(0, "")

    if not main_project then
        return false
    end

    local regions = get_regions(main_project)
    local target = regions[region_number]

    if not target then
        return false
    end

    local scene_bars =
        get_scene_length_in_bars(region_number)

    if not scene_bars then
        return false
    end

    local new_end = bars_to_time_from(
        main_project,
        target.position,
        scene_bars
    )

    local delta = new_end - target.region_end

    if math.abs(delta) <= EPSILON then
        return true
    end

    shift_regions_after(
        main_project,
        region_number,
        delta,
        regions
    )

    reaper.SetProjectMarker3(
        main_project,
        target.id,
        true,
        target.position,
        new_end,
        target.name,
        target.color
    )

    return true
end

local function select_merged_region(
    track_number,
    region_number
)
    local project = get_project(track_number)

    if not project then
        return false
    end

    local region = get_regions(project)[region_number]

    if not region then
        return false
    end

    reaper.GetSet_LoopTimeRange2(
        project,
        true,
        false,
        region.position,
        region.region_end,
        false
    )

    reaper.SetEditCurPos2(
        project,
        region.position,
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

local function merge_project(
    project,
    source_sequence,
    target_region_index
)
    if not project then
        return false, "Project not found"
    end

    local regions = get_regions(project)
    local target = regions[target_region_index]

    if not target then
        return false, "Target region not found"
    end

    local snapshots = {}
    local total_length = 0

    -- Capture all sources before the target or timeline is changed.
    for sequence_index, source_region_index
        in ipairs(source_sequence)
    do
        local source_region =
            regions[source_region_index]

        if not source_region then
            return false,
                "Source region "
                .. tostring(source_region_index)
                .. " not found"
        end

        local source_length =
            source_region.region_end
            - source_region.position

        snapshots[sequence_index] = {
            length = source_length,
            items = capture_region_items(
                project,
                source_region
            )
        }

        total_length =
            total_length + source_length
    end

    if total_length <= EPSILON then
        return false, "Merged region has no length"
    end

    local old_end = target.region_end
    local new_end = target.position + total_length
    local delta = new_end - old_end

    reaper.Undo_BeginBlock2(project)
    reaper.PreventUIRefresh(1)

    -- Replace the old target contents.
    delete_items_in_range(
        project,
        target.position,
        old_end
    )

    -- Create or remove timeline space exactly like resize.lua.
    shift_items_from(project, old_end, delta)

    shift_regions_after(
        project,
        target_region_index,
        delta,
        regions
    )

    reaper.SetProjectMarker3(
        project,
        target.id,
        true,
        target.position,
        new_end,
        target.name,
        target.color
    )

    local write_position = target.position

    for _, snapshot in ipairs(snapshots) do
        paste_captured_items(
            project,
            snapshot.items,
            write_position
        )

        write_position =
            write_position + snapshot.length
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(
        project,
        "Merge pattern regions",
        -1
    )

    return true
end

function M.merge_selected_project(
    track_number,
    source_sequence,
    target_region
)
    local project = get_project(track_number)

    local ok, error_message = merge_project(
        project,
        source_sequence,
        target_region
    )

    if not ok then
        return false, error_message
    end

    local main_project =
        reaper.EnumProjects(0, "")

    if main_project then
        reaper.Undo_BeginBlock2(main_project)
        resize_main_region_to_scene_length(target_region)
        reaper.Undo_EndBlock2(
            main_project,
            "Resize main region to merged scene length",
            -1
        )
    end

    select_merged_region(
        track_number,
        target_region
    )

    reaper.UpdateArrange()
    return true
end

function M.merge_all_projects(
    source_sequence,
    target_region,
    selected_track
)
    local all_ok = true
    local first_error = nil

    for track_number = 1, SUBPROJECT_COUNT do
        local ok, error_message = merge_project(
            get_project(track_number),
            source_sequence,
            target_region
        )

        if not ok then
            all_ok = false
            first_error = first_error or error_message
        end
    end

    if all_ok then
        local main_project =
            reaper.EnumProjects(0, "")

        if main_project then
            reaper.Undo_BeginBlock2(main_project)
            resize_main_region_to_scene_length(target_region)
            reaper.Undo_EndBlock2(
                main_project,
                "Resize main region to merged scene length",
                -1
            )
        end

        select_merged_region(
            tonumber(selected_track) or 1,
            target_region
        )
    end

    reaper.UpdateArrange()
    return all_ok, first_error
end

return M
