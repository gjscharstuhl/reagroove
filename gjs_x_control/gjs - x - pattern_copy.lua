-- ============================================================
-- gjs - x - pattern_copy.lua
-- Copy one region/pattern to another inside a selected subproject.
-- The target region is resized to the source length first.
-- ============================================================

local M = {}

local source = debug.getinfo(1, "S").source
local script_path = source:match("^@(.+)$") or ""
local script_dir = script_path:match("^(.*[/\\])") or ""
local resize = dofile(script_dir .. "gjs - x - resize.lua")

local EPSILON = 0.000001

local function get_project(subproject_number)
    local n = math.floor(tonumber(subproject_number) or 0)
    if n < 1 or n > 8 then return nil end
    return reaper.EnumProjects(n - 1, "")
end

local function get_regions(project)
    local regions = {}
    local _, markers, region_count = reaper.CountProjectMarkers(project)
    for i = 0, markers + region_count - 1 do
        local ok, is_region, pos, region_end, name, id, color =
            reaper.EnumProjectMarkers3(project, i)
        if ok and is_region then
            regions[#regions + 1] = {
                id = id,
                position = pos,
                region_end = region_end,
                name = name or "",
                color = color or 0
            }
        end
    end
    table.sort(regions, function(a, b) return a.position < b.position end)
    return regions
end

local function source_bars(project, region)
    local num, den = reaper.TimeMap_GetTimeSigAtTime(project, region.position)
    num = tonumber(num) or 4
    den = tonumber(den) or 4
    if num < 1 then num = 4 end
    if den < 1 then den = 4 end
    local qn_per_bar = num * (4 / den)
    local qn0 = reaper.TimeMap2_timeToQN(project, region.position)
    local qn1 = reaper.TimeMap2_timeToQN(project, region.region_end)
    local bars = (qn1 - qn0) / qn_per_bar
    return math.max(1, math.floor(bars + 0.5))
end

local function track_is_target(track, track_mode)
    if track_mode == "all" then
        return true
    end

    -- Same convention as the Edit/Clear screen: the selected
    -- performance tracks are the record-armed tracks.
    return reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5
end

local function capture_items(project, region, track_mode)
    local captured = {}
    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)
        if track and track_is_target(track, track_mode) then
            for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, item_index)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local item_end = pos + len
                if pos < region.region_end - EPSILON and item_end > region.position + EPSILON then
                    local ok, chunk = reaper.GetItemStateChunk(item, "", false)
                    if ok then
                        captured[#captured + 1] = {
                            track_index = track_index,
                            chunk = chunk,
                            relative_position = pos - region.position
                        }
                    end
                end
            end
        end
    end
    return captured
end

local function delete_target_items(project, region, track_mode)
    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)
        if track and track_is_target(track, track_mode) then
            for item_index = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
                local item = reaper.GetTrackMediaItem(track, item_index)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if pos < region.region_end - EPSILON and pos + len > region.position + EPSILON then
                    reaper.DeleteTrackMediaItem(track, item)
                end
            end
        end
    end
end

local function set_chunk_position(chunk, position)
    local replacement = string.format("POSITION %.14f", position)
    if chunk:find("\nPOSITION [^\n]+") then
        return chunk:gsub("\nPOSITION [^\n]+", "\n" .. replacement, 1)
    end
    return chunk
end

local function paste_items(project, captured, target_start)
    for _, entry in ipairs(captured) do
        local track = reaper.GetTrack(project, entry.track_index)
        if track then
            local item = reaper.AddMediaItemToTrack(track)
            if item then
                local chunk = set_chunk_position(
                    entry.chunk,
                    target_start + entry.relative_position
                )
                reaper.SetItemStateChunk(item, chunk, false)
            end
        end
    end
end

function M.copy(subproject_number, from_region, to_region, options)
    from_region = math.floor(tonumber(from_region) or 0)
    to_region = math.floor(tonumber(to_region) or 0)
    if from_region < 1 or from_region > 8 or to_region < 1 or to_region > 8 then
        return false, "Ongeldige patternselectie."
    end
    if from_region == to_region then
        return false, "Bron en doel zijn hetzelfde pattern."
    end

    local project = get_project(subproject_number)
    if not project then return false, "Subproject niet gevonden." end

    options = type(options) == "table" and options or {}
    local track_mode = options.track_mode == "all" and "all" or "armed"

    local regions = get_regions(project)
    local source_region = regions[from_region]
    local target_region = regions[to_region]
    if not source_region or not target_region then
        return false, "Bron- of doelregion niet gevonden."
    end

    local bars = source_bars(project, source_region)
    reaper.Undo_BeginBlock2(project)

    local resized = resize.resize_selected_region_selected_project(
        subproject_number,
        to_region,
        bars
    )
    if resized == false then
        reaper.Undo_EndBlock2(project, "GJS-X copy pattern", -1)
        return false, "Doelpattern kon niet worden resized."
    end

    -- Resize can move the source if the target sits before it, so resolve again.
    regions = get_regions(project)
    source_region = regions[from_region]
    target_region = regions[to_region]
    if not source_region or not target_region then
        reaper.Undo_EndBlock2(project, "GJS-X copy pattern", -1)
        return false, "Regions niet meer gevonden na resize."
    end

    local captured = capture_items(project, source_region, track_mode)
    delete_target_items(project, target_region, track_mode)
    paste_items(project, captured, target_region.position)

    reaper.UpdateArrange()
    reaper.Undo_EndBlock2(project, "GJS-X copy pattern", -1)
    return true
end

return M
