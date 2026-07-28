-- ============================================================
-- gjs - x - merge.lua
-- Merge a sequence of source regions into one target region.
-- ============================================================

local M = {}
local EPSILON = 0.000001

local function get_project(track_number)
    return reaper.EnumProjects(track_number, "")
end

local function get_regions(project)
    local regions = {}
    local _, marker_count, region_count = reaper.CountProjectMarkers(project)
    local total = marker_count + region_count

    for index = 0, total - 1 do
        local ok, is_region, position, region_end, name, id, color =
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
    local replacement = string.format("%s %.14f", key, value)
    local pattern = "\n" .. key .. " [^\n]+"

    if chunk:find(pattern) then
        return chunk:gsub(pattern, "\n" .. replacement, 1)
    end

    return chunk
end

local function capture_region_items(project, region)
    local captured = {}

    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)

        for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, item_index)
            local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = position + length

            if position < region.region_end - EPSILON
            and item_end > region.position + EPSILON then
                local ok, chunk = reaper.GetItemStateChunk(item, "", false)

                if ok then
                    captured[#captured + 1] = {
                        track_index = track_index,
                        chunk = chunk,
                        relative_position = position - region.position,
                        length = length
                    }
                end
            end
        end
    end

    return captured
end

local function delete_items_in_range(project, range_start, range_end)
    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)

        for item_index = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
            local item = reaper.GetTrackMediaItem(track, item_index)
            local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = position + length

            if position < range_end - EPSILON
            and item_end > range_start + EPSILON then
                reaper.DeleteTrackMediaItem(track, item)
            end
        end
    end
end

local function paste_captured_items(project, captured, destination_start)
    for _, source_item in ipairs(captured) do
        local track = reaper.GetTrack(project, source_item.track_index)

        if track then
            local item = reaper.AddMediaItemToTrack(track)
            local position = destination_start + source_item.relative_position
            local chunk = replace_chunk_number(
                source_item.chunk,
                "POSITION",
                position
            )

            reaper.SetItemStateChunk(item, chunk, false)
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", source_item.length)
        end
    end
end

local function merge_project(project, source_sequence, target_region_index)
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

    -- Capture everything before changing or clearing the target region.
    for sequence_index, source_region_index in ipairs(source_sequence) do
        local source_region = regions[source_region_index]

        if not source_region then
            return false, "Source region " .. tostring(source_region_index) .. " not found"
        end

        local source_length = source_region.region_end - source_region.position

        snapshots[sequence_index] = {
            length = source_length,
            items = capture_region_items(project, source_region)
        }

        total_length = total_length + source_length
    end

    if total_length <= EPSILON then
        return false, "Merged region has no length"
    end

    reaper.Undo_BeginBlock2(project)
    reaper.PreventUIRefresh(1)

    delete_items_in_range(project, target.position, target.region_end)

    local write_position = target.position

    for _, snapshot in ipairs(snapshots) do
        paste_captured_items(project, snapshot.items, write_position)
        write_position = write_position + snapshot.length
    end

    reaper.SetProjectMarker3(
        project,
        target.id,
        true,
        target.position,
        target.position + total_length,
        target.name,
        target.color
    )

    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(project, "Merge pattern regions", -1)

    return true
end

function M.merge_selected_project(track_number, source_sequence, target_region)
    return merge_project(
        get_project(track_number),
        source_sequence,
        target_region
    )
end

function M.merge_all_projects(source_sequence, target_region)
    local all_ok = true
    local first_error = nil

    for track_number = 1, 8 do
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

    return all_ok, first_error
end

return M
