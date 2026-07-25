-- ============================================================
-- gjs - x - clear.lua
-- Version 01 - shared region clear functions
-- ============================================================

local M = {}

local TOLERANCE = 0.000001
local REGION_COUNT = 8

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

local function delete_items_inside_region(proj, region)
    local deleted = false

    for index = reaper.CountMediaItems(proj) - 1, 0, -1 do
        local item = reaper.GetMediaItem(proj, index)

        local item_start =
            reaper.GetMediaItemInfo_Value(item, "D_POSITION")

        local item_length =
            reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

        local item_end = item_start + item_length

        local overlaps =
            item_end > region.start_pos + TOLERANCE
            and item_start < region.end_pos - TOLERANCE

        if overlaps then
            local track = reaper.GetMediaItem_Track(item)
            reaper.DeleteTrackMediaItem(track, item)
            deleted = true
        end
    end

    return deleted
end

local function delete_automation_from_envelope(
    envelope,
    region_start,
    region_end
)
    local deleted = false

    local points_before =
        reaper.CountEnvelopePointsEx(envelope, -1)

    reaper.DeleteEnvelopePointRangeEx(
        envelope,
        -1,
        region_start - TOLERANCE,
        region_end + TOLERANCE
    )

    local points_after =
        reaper.CountEnvelopePointsEx(envelope, -1)

    if points_after < points_before then
        deleted = true
    end

    for index = reaper.CountAutomationItems(envelope) - 1, 0, -1 do
        local item_start =
            reaper.GetSetAutomationItemInfo(
                envelope,
                index,
                "D_POSITION",
                0,
                false
            )

        local item_length =
            reaper.GetSetAutomationItemInfo(
                envelope,
                index,
                "D_LENGTH",
                0,
                false
            )

        local item_end = item_start + item_length

        local overlaps =
            item_end > region_start + TOLERANCE
            and item_start < region_end - TOLERANCE

        if overlaps then
            reaper.DeleteAutomationItem(envelope, index)
            deleted = true
        end
    end

    reaper.Envelope_SortPointsEx(envelope, -1)

    return deleted
end

local function delete_track_automation(track, region)
    local deleted = false

    for index = 0, reaper.CountTrackEnvelopes(track) - 1 do
        local envelope =
            reaper.GetTrackEnvelope(track, index)

        if envelope
        and delete_automation_from_envelope(
            envelope,
            region.start_pos,
            region.end_pos
        ) then
            deleted = true
        end
    end

    return deleted
end

local function delete_all_automation(proj, region)
    local deleted = false

    for index = 0, reaper.CountTracks(proj) - 1 do
        local track = reaper.GetTrack(proj, index)

        if delete_track_automation(track, region) then
            deleted = true
        end
    end

    local master = reaper.GetMasterTrack(proj)

    if master and delete_track_automation(master, region) then
        deleted = true
    end

    return deleted
end

local function clear_region(proj, region, undo_text)
    if not proj or not region then
        return false
    end

    reaper.Undo_BeginBlock2(proj)

    local items_deleted =
        delete_items_inside_region(proj, region)

    local automation_deleted =
        delete_all_automation(proj, region)

    local changed =
        items_deleted or automation_deleted

    reaper.Undo_EndBlock2(
        proj,
        changed
            and undo_text
            or undo_text .. " - nothing found",
        -1
    )

    return changed
end

function M.clear_all_regions_all_projects()
    reaper.PreventUIRefresh(1)

    local project_index = 0

    while true do
        local proj = reaper.EnumProjects(project_index, "")
        if not proj then
            break
        end

        local regions = get_all_regions(proj)

        for region_number = 1, REGION_COUNT do
            local region = regions[region_number]

            if region then
                clear_region(
                    proj,
                    region,
                    "gjs - Clear all regions in all projects"
                )
            end
        end

        project_index = project_index + 1
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

function M.clear_selected_region_all_projects(region_number)
    region_number = tonumber(region_number)
    if not region_number then
        return
    end

    reaper.PreventUIRefresh(1)

    local project_index = 0

    while true do
        local proj = reaper.EnumProjects(project_index, "")
        if not proj then
            break
        end

        local region =
            get_all_regions(proj)[region_number]

        if region then
            clear_region(
                proj,
                region,
                "gjs - Clear region "
                    .. tostring(region_number)
                    .. " in all projects"
            )
        end

        project_index = project_index + 1
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

function M.clear_selected_region_selected_project(
    track_number,
    region_number
)
    track_number = tonumber(track_number)
    region_number = tonumber(region_number)

    if not track_number or not region_number then
        return
    end

    local proj =
        reaper.EnumProjects(track_number, "")

    if not proj then
        return
    end

    local region =
        get_all_regions(proj)[region_number]

    if not region then
        return
    end

    reaper.PreventUIRefresh(1)

    clear_region(
        proj,
        region,
        "gjs - Clear region "
            .. tostring(region_number)
            .. " in subproject "
            .. tostring(track_number)
    )

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

return M
