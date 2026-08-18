-- ============================================================
-- gjs - x - clear.lua
-- Version 01 - shared region clear functions
-- ============================================================

local M = {}

local TOLERANCE = 0.000001
local REGION_COUNT = 8


-- Remove WAV source files that belonged to deleted items, but only when the
-- file lives inside this project's directory and no remaining item uses it.
local function project_directory(proj)
    -- Prefer the actual .RPP filename. GetProjectPathEx may point at REAPER's
    -- configured recording/media directory, which is not necessarily the
    -- project root.
    local index = 0
    while true do
        local candidate, project_file = reaper.EnumProjects(index, "")
        if not candidate then break end
        if candidate == proj and type(project_file) == "string" and project_file ~= "" then
            local normalized = project_file:gsub("\\", "/")
            return normalized:match("^(.*)/[^/]+$")
        end
        index = index + 1
    end

    if type(reaper.GetProjectPathEx) == "function" then
        local ok, path = reaper.GetProjectPathEx(proj, "")
        if ok and path and path ~= "" then return path end
    end
    return nil
end

local function item_wav_path(item)
    local take = item and reaper.GetActiveTake(item)
    if not take then return nil end
    local source = reaper.GetMediaItemTake_Source(take)
    if not source then return nil end
    local path = reaper.GetMediaSourceFileName(source, "")
    if type(path) ~= "string" or path == "" then return nil end
    if not path:lower():match("%.wav$") then return nil end
    return path
end

local function path_is_inside(path, directory)
    if not path or not directory or directory == "" then return false end
    local p = path:gsub("\\", "/")
    local d = directory:gsub("\\", "/"):gsub("/+$", "")
    return p == d or p:sub(1, #d + 1) == d .. "/"
end

local function source_still_used_any_project(path)
    local project_index = 0
    while true do
        local proj = reaper.EnumProjects(project_index, "")
        if not proj then break end
        for i = 0, reaper.CountMediaItems(proj) - 1 do
            if item_wav_path(reaper.GetMediaItem(proj, i)) == path then
                return true
            end
        end
        project_index = project_index + 1
    end
    return false
end

local function remove_peak_for_wav(path)
    if type(path) ~= "string" or path == "" then return end
    -- REAPER normally stores the peak next to the source as <source>.reapeaks.
    os.remove(path .. ".reapeaks")
end

local function remove_unused_project_wavs(proj, candidates)
    local directory = project_directory(proj)
    if not directory then return end
    for path in pairs(candidates or {}) do
        if path_is_inside(path, directory) and not source_still_used_any_project(path) then
            os.remove(path)
            remove_peak_for_wav(path)
        end
    end
end


-- Build one set of WAV files still referenced by any currently open project.
-- This makes the startup sweep safe across project tabs/subprojects.
local function normalize_path(path)
    if type(path) ~= "string" then return nil end
    local value = path:gsub("\\", "/")
    if type(reaper.GetOS) == "function" then
        local os_name = reaper.GetOS() or ""
        if os_name:match("Win") then
            value = value:lower()
        end
    end
    return value
end

local function collect_used_wavs_all_projects()
    local used = {}
    local project_index = 0

    while true do
        local proj = reaper.EnumProjects(project_index, "")
        if not proj then break end

        for item_index = 0, reaper.CountMediaItems(proj) - 1 do
            local item = reaper.GetMediaItem(proj, item_index)
            local take_count = reaper.CountTakes(item)

            for take_index = 0, take_count - 1 do
                local take = reaper.GetTake(item, take_index)
                if take then
                    local source = reaper.GetMediaItemTake_Source(take)
                    if source then
                        local path = reaper.GetMediaSourceFileName(source, "")
                        if type(path) == "string"
                        and path:lower():match("%.wav$") then
                            used[normalize_path(path)] = true
                        end
                    end
                end
            end
        end

        project_index = project_index + 1
    end

    return used
end

local function join_path(a, b)
    if not a or a == "" then return b end
    local tail = a:sub(-1)
    if tail == "/" or tail == "\\" then
        return a .. b
    end
    return a .. "/" .. b
end

local function sweep_unused_wavs_recursive(directory, used)
    if not directory or directory == "" then return end

    local file_index = 0
    while true do
        local name = reaper.EnumerateFiles(directory, file_index)
        if not name then break end

        if name:lower():match("%.wav$") then
            local path = join_path(directory, name)
            if not used[normalize_path(path)] then
                os.remove(path)
            end
        end

        file_index = file_index + 1
    end

    local dir_index = 0
    while true do
        local name = reaper.EnumerateSubdirectories(directory, dir_index)
        if not name then break end
        sweep_unused_wavs_recursive(join_path(directory, name), used)
        dir_index = dir_index + 1
    end
end

local function dirname(path)
    if type(path) ~= "string" then return nil end
    local value = path:gsub("\\", "/")
    return value:match("^(.*)/[^/]+$")
end

local function resolve_source_path(base_dir, path)
    if type(path) ~= "string" or path == "" then return nil end
    local value = path:gsub("\\", "/")

    -- Unix absolute path or Windows drive/UNC path.
    if value:sub(1, 1) == "/"
    or value:match("^%a:/")
    or value:sub(1, 2) == "//" then
        return value
    end

    return join_path(base_dir, value)
end

local function collect_subproject_rpps_all_projects()
    local found = {}
    local queue = {}

    local function add(path)
        if type(path) ~= "string" or not path:lower():match("%.rpp$") then
            return
        end
        local normalized = normalize_path(path)
        if normalized and not found[normalized] then
            found[normalized] = path
            queue[#queue + 1] = path
        end
    end

    -- First discover .RPP sources directly used by all open project tabs.
    local project_index = 0
    while true do
        local proj = reaper.EnumProjects(project_index, "")
        if not proj then break end

        for item_index = 0, reaper.CountMediaItems(proj) - 1 do
            local item = reaper.GetMediaItem(proj, item_index)
            for take_index = 0, reaper.CountTakes(item) - 1 do
                local take = reaper.GetTake(item, take_index)
                if take then
                    local source = reaper.GetMediaItemTake_Source(take)
                    if source then
                        add(reaper.GetMediaSourceFileName(source, ""))
                    end
                end
            end
        end

        project_index = project_index + 1
    end

    -- A subproject may itself contain another subproject. Discover those from
    -- the RPP text without opening any windows or project tabs.
    local index = 1
    while index <= #queue do
        local rpp_path = queue[index]
        local base_dir = dirname(rpp_path)
        local file = io.open(rpp_path, "r")
        if file and base_dir then
            for line in file:lines() do
                local source_path = line:match('FILE%s+"([^"]+)"')
                if source_path and source_path:lower():match("%.rpp$") then
                    add(resolve_source_path(base_dir, source_path))
                end
            end
            file:close()
        elseif file then
            file:close()
        end
        index = index + 1
    end

    return found
end

local function add_rpp_wav_references(rpp_path, used)
    local base_dir = dirname(rpp_path)
    if not base_dir then return end

    local file = io.open(rpp_path, "r")
    if not file then return end

    for line in file:lines() do
        local source_path = line:match('FILE%s+"([^"]+)"')
        if source_path and source_path:lower():match("%.wav$") then
            local resolved = resolve_source_path(base_dir, source_path)
            local key = normalize_path(resolved)
            if key then used[key] = true end
        end
    end

    file:close()
end

local function delete_all_files_from_named_Media_dirs(directory)
    if not directory or directory == "" then return end

    -- Only a directory named exactly "Media" is treated as a REAPER media
    -- directory. On Linux the case matters, and ReaBox standardizes on Media.
    local normalized = directory:gsub("\\", "/"):gsub("/+$", "")
    local basename = normalized:match("([^/]+)$")

    if basename == "Media" then
        -- Collect first; deleting during EnumerateFiles can skip entries.
        local files = {}
        local file_index = 0
        while true do
            local name = reaper.EnumerateFiles(directory, file_index)
            if not name then break end
            local lower = name:lower()
            if lower:match("%.wav$") or lower:match("%.reapeaks$") then
                files[#files + 1] = name
            end
            file_index = file_index + 1
        end
        for _, name in ipairs(files) do
            os.remove(join_path(directory, name))
        end
    end

    local dir_index = 0
    while true do
        local name = reaper.EnumerateSubdirectories(directory, dir_index)
        if not name then break end
        delete_all_files_from_named_Media_dirs(join_path(directory, name))
        dir_index = dir_index + 1
    end
end

local function delete_directory_tree(directory)
    if not directory or directory == "" then return end

    -- Collect first: deleting while Enumerate* is advancing can skip entries.
    local files = {}
    local file_index = 0
    while true do
        local name = reaper.EnumerateFiles(directory, file_index)
        if not name then break end
        files[#files + 1] = name
        file_index = file_index + 1
    end

    for _, name in ipairs(files) do
        os.remove(join_path(directory, name))
    end

    local directories = {}
    local dir_index = 0
    while true do
        local name = reaper.EnumerateSubdirectories(directory, dir_index)
        if not name then break end
        directories[#directories + 1] = name
        dir_index = dir_index + 1
    end

    for _, name in ipairs(directories) do
        delete_directory_tree(join_path(directory, name))
    end

    -- os.remove removes an empty directory on both POSIX and Windows Lua.
    os.remove(directory)
end

local function delete_named_cache_dirs(directory)
    if not directory or directory == "" then return end

    local normalized = directory:gsub("\\", "/"):gsub("/+$", "")
    local basename = normalized:match("([^/]+)$")

    if basename == "peaks" or basename == "Backups" then
        delete_directory_tree(directory)
        return
    end

    -- Collect first because a child named Peaks can disappear during traversal.
    local directories = {}
    local dir_index = 0
    while true do
        local name = reaper.EnumerateSubdirectories(directory, dir_index)
        if not name then break end
        directories[#directories + 1] = name
        dir_index = dir_index + 1
    end

    for _, name in ipairs(directories) do
        delete_named_cache_dirs(join_path(directory, name))
    end
end

local function delete_all_project_media_files()
    local seen = {}

    local function scan_root(directory)
        if not directory or directory == "" then return end
        local key = normalize_path(directory)
        if not key or seen[key] then return end
        seen[key] = true
        delete_all_files_from_named_Media_dirs(directory)
        delete_named_cache_dirs(directory)
    end

    local project_index = 0
    while true do
        -- EnumProjects returns the actual project filename as its second value.
        -- That is the correct root for sibling/nested subprojects.
        local proj, project_file = reaper.EnumProjects(project_index, "")
        if not proj then break end

        if type(project_file) == "string" and project_file ~= "" then
            scan_root(dirname(project_file))
        end

        -- Also cover REAPER's configured project media/recording path.
        -- If it points at <project>/Media, scan its parent project directory
        -- rather than only the Media directory itself.
        local media_path = project_directory(proj)
        if media_path and media_path ~= "" then
            local normalized = media_path:gsub("\\", "/"):gsub("/+$", "")
            if normalized:match("/Media$") then
                scan_root(dirname(normalized))
            else
                scan_root(media_path)
            end
        end

        project_index = project_index + 1
    end
end


local function delete_all_project_cache_dirs()
    local seen = {}

    local function scan_root(directory)
        if not directory or directory == "" then return end
        local key = normalize_path(directory)
        if not key or seen[key] then return end
        seen[key] = true
        delete_named_cache_dirs(directory)
    end

    local project_index = 0
    while true do
        local proj, project_file = reaper.EnumProjects(project_index, "")
        if not proj then break end

        if type(project_file) == "string" and project_file ~= "" then
            scan_root(dirname(project_file))
        end

        local media_path = project_directory(proj)
        if media_path and media_path ~= "" then
            local normalized = media_path:gsub("\\", "/"):gsub("/+$", "")
            if normalized:match("/Media$") then
                scan_root(dirname(normalized))
            else
                scan_root(media_path)
            end
        end

        project_index = project_index + 1
    end
end

-- One physical cleanup entry point used by startup clear and Edit clear.
-- full=true wipes WAV/REAPEAKS from every exact Media directory under the
-- project roots. Otherwise only files belonging to items just deleted are
-- removed, and only when no open project still uses that WAV.
local function cleanup_physical_Media(proj, candidates, full)
    if full then
        delete_all_project_media_files()
    else
        remove_unused_project_wavs(proj, candidates)
        -- peaks and Backups are disposable project cache/backup data. Edit-clean uses the same Peaks
        -- cleanup as startup-clean; REAPER regenerates peaks when required.
        delete_all_project_cache_dirs()
    end
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

local function should_clear_track(track, target_tracks)
    return target_tracks ~= nil
       and target_tracks[track] == true
end

local function delete_items_inside_region(
    proj,
    region,
    target_tracks
)
    local deleted = false
    local wav_candidates = {}

    if not target_tracks then
        return false
    end

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

            if should_clear_track(track, target_tracks) then
                local wav_path = item_wav_path(item)
                if wav_path then wav_candidates[wav_path] = true end
                reaper.DeleteTrackMediaItem(track, item)
                deleted = true
            end
        end
    end

    cleanup_physical_Media(proj, wav_candidates, false)
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

local function delete_all_automation(
    proj,
    region,
    target_tracks
)
    local deleted = false

    if not target_tracks then
        return false
    end

    for track in pairs(target_tracks) do
        if delete_track_automation(track, region) then
            deleted = true
        end
    end

    return deleted
end

local function clear_region(
    proj,
    region,
    undo_text,
    clear_items,
    clear_fx,
    target_tracks
)
    if not proj or not region then
        return false
    end

    -- Backwards-compatible defaults.
    if clear_items == nil then clear_items = true end
    if clear_fx == nil then clear_fx = true end

    reaper.Undo_BeginBlock2(proj)

    local items_deleted = false
    if clear_items then
        items_deleted =
            delete_items_inside_region(
                proj,
                region,
                target_tracks
            )
    end

    -- "FX" here means recorded automation in the region:
    -- volume, pan, sends and plugin parameter envelopes.
    local automation_deleted = false
    if clear_fx then
        automation_deleted =
            delete_all_automation(
                proj,
                region,
                target_tracks
            )
    end

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

local function get_top_level_track_set(project, track_mode)
    if not project then
        return nil
    end

    local targets = {}
    local depth = 0

    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)

        if track and depth == 0 then
            local include = false

            if track_mode == "all" then
                include = true
            elseif track_mode == "armed" then
                include =
                    reaper.GetMediaTrackInfo_Value(
                        track,
                        "I_RECARM"
                    ) > 0.5
            end

            if include then
                targets[track] = true
            end
        end

        if track then
            depth = depth + math.floor(
                reaper.GetMediaTrackInfo_Value(
                    track,
                    "I_FOLDERDEPTH"
                )
            )

            if depth < 0 then
                depth = 0
            end
        end
    end

    if next(targets) == nil then
        return nil
    end

    return targets
end

local function read_options(options)
    if type(options) ~= "table" then
        return true, true, "armed"
    end

    local track_mode =
        options.track_mode == "all"
        and "all"
        or "armed"

    return options.items == true,
           options.fx == true,
           track_mode
end

function M.clear_all_regions_all_projects(options)
    local clear_items, clear_fx, track_mode = read_options(options)

    if not clear_items and not clear_fx then
        return false
    end

    reaper.PreventUIRefresh(1)

    local ok, err = xpcall(function()
        local project_index = 0

        while true do
            local proj = reaper.EnumProjects(project_index, "")
            if not proj then
                break
            end

            local regions = get_all_regions(proj)
            local target_tracks =
                get_top_level_track_set(proj, track_mode)

            for region_number = 1, REGION_COUNT do
                local region = regions[region_number]

                if region then
                    clear_region(
                        proj,
                        region,
                        "gjs - Clear all regions in all projects",
                        clear_items,
                        clear_fx,
                        target_tracks
                    )
                end
            end

            project_index = project_index + 1
        end

        cleanup_physical_Media(nil, nil, true)
    end, debug.traceback)

    -- Always release the REAPER UI, even when cleanup throws an error.
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    if not ok then
        reaper.ShowConsoleMsg("ReaBox cleanup error:\n" .. tostring(err) .. "\n")
        return false, err
    end

    return true
end

function M.clear_selected_region_all_projects(
    region_number,
    options
)
    local clear_items, clear_fx, track_mode = read_options(options)

    if not clear_items and not clear_fx then
        return false
    end

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

        local target_tracks =
            get_top_level_track_set(proj, track_mode)

        if region and target_tracks then
            clear_region(
                proj,
                region,
                "gjs - Clear region "
                    .. tostring(region_number)
                    .. " in all projects",
                clear_items,
                clear_fx,
                target_tracks
            )
        end

        project_index = project_index + 1
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

function M.clear_selected_region_selected_project(
    track_number,
    region_number,
    options
)
    local clear_items, clear_fx, track_mode = read_options(options)

    if not clear_items and not clear_fx then
        return false
    end

    track_number = tonumber(track_number)
    region_number = tonumber(region_number)

    if not track_number or not region_number then
        return
    end

    -- Natural visible-tab flow:
    -- selected track/tab 1 -> REAPER project 0.
    local proj =
        reaper.EnumProjects(track_number - 1, "")

    if not proj then
        return
    end

    local region =
        get_all_regions(proj)[region_number]

    if not region then
        return
    end

    local target_tracks =
        get_top_level_track_set(proj, track_mode)

    if not target_tracks then
        return false
    end

    reaper.PreventUIRefresh(1)

    clear_region(
        proj,
        region,
        "gjs - Clear chosen tracks in region "
            .. tostring(region_number)
            .. " in project tab "
            .. tostring(track_number),
        clear_items,
        clear_fx,
        target_tracks
    )

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

return M
