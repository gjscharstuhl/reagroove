-- ============================================================
-- gjs - x - export.lua
-- Playlist export for ReaGroove.
--   mode 1: editable REAPER project (scene regions + subtracks)
--   mode 2: stereo stems (one long rendered file per used subproject)
-- ============================================================

local M = {}

local scene_api = include("gjs - scene_api.lua")
local playlist_api = include("gjs - playlist_api.lua")

local STEM_RENDER_ACTION = 40788 -- Track: Render tracks to stereo stem tracks (and mute originals)
local EPSILON = 0.0000001

local HOME = os.getenv("HOME") or os.getenv("USERPROFILE")
if not HOME then
    local drive = os.getenv("HOMEDRIVE")
    local path = os.getenv("HOMEPATH")
    if drive and path then HOME = drive .. path end
end
local EXPORTS_DIR = HOME and (HOME .. "/ReaBox/exports") or nil
local EXT_SECTION = "GJS_X"
local EXT_ACTIVE_SLOT = "ActiveSlotSession"

local function get_active_slot()
    local slot = tonumber(reaper.GetExtState(EXT_SECTION, EXT_ACTIVE_SLOT))
    if not slot then return nil end
    slot = math.floor(slot)
    if slot < 1 or slot > 56 then return nil end
    return slot
end

local function export_directory()
    if not EXPORTS_DIR then return nil end
    local slot = get_active_slot()
    if not slot then return nil end
    return string.format("%s/slot_%d", EXPORTS_DIR, slot)
end

local function ensure_export_directory()
    local directory = export_directory()
    if not directory then
        return nil, "Er is geen actief jam-slot; export kan niet worden opgeslagen."
    end
    reaper.RecursiveCreateDirectory(EXPORTS_DIR, 0)
    reaper.RecursiveCreateDirectory(directory, 0)
    return directory
end

local function save_export_project(project, kind)
    local directory, err = ensure_export_directory()
    if not directory then return false, err end
    local path = directory .. "/" .. tostring(kind) .. ".rpp"
    reaper.Main_SaveProjectEx(project, path, 0)
    return true, path
end

local function show_error(message)
    reaper.ShowMessageBox(
        tostring(message or "Onbekende exportfout"),
        "ReaGroove export",
        0
    )
end

local function get_project(number)
    number = math.floor(tonumber(number) or 0)
    if number < 1 or number > 8 then return nil end
    return reaper.EnumProjects(number - 1, "")
end

local function find_region(project, region_number)
    if not project then return nil end

    local _, marker_count, region_count = reaper.CountProjectMarkers(project)

    for index = 0, marker_count + region_count - 1 do
        local ok, is_region, start_pos, end_pos, name, number, color =
            reaper.EnumProjectMarkers3(project, index)

        if ok and is_region and number == region_number then
            return {
                start_pos = start_pos,
                end_pos = end_pos,
                length = end_pos - start_pos,
                name = name,
                number = number,
                color = color
            }
        end
    end

    return nil
end

local function collect_playlist()
    local result = {}

    for slot = 1, playlist_api.GetSlotCount() do
        local scene_number = playlist_api.Get(slot)
        local scene = scene_number and scene_api.GetScene(scene_number) or nil

        if scene then
            result[#result + 1] = {
                slot = slot,
                scene_number = scene_number,
                scene = scene
            }
        end
    end

    return result
end

local function build_timeline(entries)
    local cursor = 0

    for _, entry in ipairs(entries) do
        local longest = 0
        entry.patterns = {}

        for project_number = 1, 8 do
            local region_number = entry.scene.patternlist
                and entry.scene.patternlist[project_number]
                or nil
            local project = get_project(project_number)
            local region = region_number and find_region(project, region_number) or nil

            if region then
                entry.patterns[project_number] = region
                if region.length > longest then longest = region.length end
            end
        end

        entry.start_pos = cursor
        entry.length = longest
        entry.end_pos = cursor + longest
        cursor = entry.end_pos
    end

    return cursor
end

local function item_overlaps_region(item, region)
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = position + length

    return position < region.end_pos - EPSILON
       and item_end > region.start_pos + EPSILON
end

local function collect_project_track_info(project, used_regions)
    local info = {}
    local depth = 0
    local parent_stack = {}

    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        local folder_delta = math.floor(
            reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        )

        while #parent_stack > depth do
            parent_stack[#parent_stack] = nil
        end

        local entry = {
            index = index,
            track = track,
            depth = depth,
            parent = depth > 0 and parent_stack[depth] or nil,
            has_content = false,
            include = false
        }
        info[#info + 1] = entry

        for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, item_index)
            for _, region in ipairs(used_regions) do
                if item_overlaps_region(item, region) then
                    entry.has_content = true
                    entry.include = true
                    break
                end
            end
            if entry.has_content then break end
        end

        if folder_delta > 0 then
            for level = 1, folder_delta do
                parent_stack[depth + level] = entry
            end
        end

        depth = depth + folder_delta
        if depth < 0 then depth = 0 end
    end

    -- Empty folder/bus tracks are still required when an included child
    -- depends on them. Walk ancestors of every content track.
    for _, entry in ipairs(info) do
        if entry.include then
            local parent = entry.parent
            while parent do
                parent.include = true
                parent = parent.parent
            end
        end
    end

    return info
end

local function get_track_name(track, fallback)
    local ok, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if ok and name and name ~= "" then return name end
    return fallback or "Track"
end

local function copy_track_fx_chain_state(source_track, destination_track)
    local ok_source, source_chunk =
        reaper.GetTrackStateChunk(source_track, "", false)
    local ok_destination, destination_chunk =
        reaper.GetTrackStateChunk(destination_track, "", false)

    if not ok_source or not ok_destination
       or not source_chunk or not destination_chunk then
        return
    end

    -- REAPER stores the track FX-chain power state on the top-level
    -- "FX 0/1" line in the track chunk.  Copy that exact line rather than
    -- relying on API properties that do not cover every REAPER version/state.
    local source_fx_line =
        source_chunk:match("[\r\n](%s*FX%s+[%-%d]+)[\r\n]")

    if not source_fx_line then return end

    local replaced = false
    destination_chunk = destination_chunk:gsub(
        "([\r\n])%s*FX%s+[%-%d]+([\r\n])",
        function(prefix, suffix)
            if replaced then
                return prefix .. "FX 1" .. suffix
            end
            replaced = true
            return prefix .. source_fx_line .. suffix
        end,
        1
    )

    if replaced then
        reaper.SetTrackStateChunk(
            destination_track,
            destination_chunk,
            false
        )
    end
end

local function copy_track_settings(source_track, destination_track, fallback_name)
    local name = get_track_name(source_track, fallback_name)
    reaper.GetSetMediaTrackInfo_String(destination_track, "P_NAME", name, true)

    local numeric_keys = {
        "D_VOL", "D_PAN", "D_WIDTH", "B_PHASE", "B_MUTE",
        "I_SOLO", "I_NCHAN", "I_PANMODE", "B_MAINSEND", "I_MIDIHWOUT",
        "D_PANLAW", "I_AUTOMODE", "B_SHOWINMIXER", "B_SHOWINTCP", "I_FXEN"
    }

    for _, key in ipairs(numeric_keys) do
        local value = reaper.GetMediaTrackInfo_Value(source_track, key)
        reaper.SetMediaTrackInfo_Value(destination_track, key, value)
    end

    -- Copy the normal FX chain. Folder routing is rebuilt separately below.
    local fx_count = reaper.TrackFX_GetCount(source_track)
    for fx = 0, fx_count - 1 do
        local destination_fx = reaper.TrackFX_GetCount(destination_track)

        reaper.TrackFX_CopyToTrack(
            source_track,
            fx,
            destination_track,
            destination_fx,
            false
        )

        -- Preserve the exact FX enabled/bypass state from the source.
        -- TrackFX_CopyToTrack copies the processor, but the live enabled
        -- state is restored explicitly here.
        if type(reaper.TrackFX_GetEnabled) == "function"
           and type(reaper.TrackFX_SetEnabled) == "function" then
            local enabled = reaper.TrackFX_GetEnabled(source_track, fx)
            reaper.TrackFX_SetEnabled(
                destination_track,
                destination_fx,
                enabled
            )
        end

        if type(reaper.TrackFX_GetOffline) == "function"
           and type(reaper.TrackFX_SetOffline) == "function" then
            local offline = reaper.TrackFX_GetOffline(source_track, fx)
            reaper.TrackFX_SetOffline(
                destination_track,
                destination_fx,
                offline
            )
        end
    end

    copy_track_fx_chain_state(source_track, destination_track)
end

local function copy_master_settings(source_project, destination_project)
    if not source_project or not destination_project then return end
    local source_master = reaper.GetMasterTrack(source_project)
    local destination_master = reaper.GetMasterTrack(destination_project)
    if not source_master or not destination_master then return end

    local numeric_keys = {
        "D_VOL", "D_PAN", "D_WIDTH", "B_PHASE", "B_MUTE",
        "I_SOLO", "I_NCHAN", "I_PANMODE", "I_FXEN"
    }
    for _, key in ipairs(numeric_keys) do
        reaper.SetMediaTrackInfo_Value(
            destination_master, key,
            reaper.GetMediaTrackInfo_Value(source_master, key)
        )
    end

    local fx_count = reaper.TrackFX_GetCount(source_master)
    for fx = 0, fx_count - 1 do
        local destination_fx = reaper.TrackFX_GetCount(destination_master)

        reaper.TrackFX_CopyToTrack(
            source_master,
            fx,
            destination_master,
            destination_fx,
            false
        )

        if type(reaper.TrackFX_GetEnabled) == "function"
           and type(reaper.TrackFX_SetEnabled) == "function" then
            local enabled = reaper.TrackFX_GetEnabled(source_master, fx)
            reaper.TrackFX_SetEnabled(
                destination_master,
                destination_fx,
                enabled
            )
        end

        if type(reaper.TrackFX_GetOffline) == "function"
           and type(reaper.TrackFX_SetOffline) == "function" then
            local offline = reaper.TrackFX_GetOffline(source_master, fx)
            reaper.TrackFX_SetOffline(
                destination_master,
                destination_fx,
                offline
            )
        end
    end

    copy_track_fx_chain_state(source_master, destination_master)
end

local function copy_project_timing(source_project, destination_project)
    if not source_project or not destination_project then return end

    -- REAPER Lua returns exactly: bpm, beats-per-measure.
    -- Previous versions treated the first value as a boolean, which turned
    -- an 84 BPM project into 4 BPM in the export.
    local bpm, bpi = reaper.GetProjectTimeSignature2(source_project)
    bpm = tonumber(bpm) or 120
    bpi = math.floor(tonumber(bpi) or 4)

    reaper.SelectProjectInstance(destination_project)

    if bpm > 0 then
        reaper.SetCurrentBPM(destination_project, bpm, false)
    end

    -- Copy the source project's tempo/time-signature markers as well, so the
    -- exported project follows the same musical grid when a jam uses them.
    if type(reaper.CountTempoTimeSigMarkers) == "function"
       and type(reaper.GetTempoTimeSigMarker) == "function"
       and type(reaper.SetTempoTimeSigMarker) == "function" then

        local destination_count =
            reaper.CountTempoTimeSigMarkers(destination_project)
        for marker = destination_count - 1, 0, -1 do
            if type(reaper.DeleteTempoTimeSigMarker) == "function" then
                reaper.DeleteTempoTimeSigMarker(destination_project, marker)
            end
        end

        local count = reaper.CountTempoTimeSigMarkers(source_project)
        for marker = 0, count - 1 do
            local ok, timepos, measurepos, beatpos,
                marker_bpm, num, denom, linear =
                reaper.GetTempoTimeSigMarker(source_project, marker)

            if ok then
                reaper.SetTempoTimeSigMarker(
                    destination_project,
                    -1,
                    timepos,
                    measurepos,
                    beatpos,
                    marker_bpm,
                    num,
                    denom,
                    linear
                )
            end
        end
    end
end

local function regenerate_item_guids(chunk)
    if type(reaper.genGuid) ~= "function" then return chunk end

    chunk = chunk:gsub("([\r\n])GUID%s+{[^}]+}", function(prefix)
        return prefix .. "GUID " .. reaper.genGuid()
    end)
    chunk = chunk:gsub("([\r\n])IGUID%s+{[^}]+}", function(prefix)
        return prefix .. "IGUID " .. reaper.genGuid()
    end)

    return chunk
end

local function item_has_midi(item)
    for take_index = 0, reaper.CountTakes(item) - 1 do
        local take = reaper.GetTake(item, take_index)
        if take and reaper.TakeIsMIDI(take) then return true end
    end
    return false
end

local function copy_midi_item(
    source_item,
    destination_track,
    destination_position
)
    local source_take = reaper.GetActiveTake(source_item)
    if not source_take or not reaper.TakeIsMIDI(source_take) then return nil end

    local item_len = reaper.GetMediaItemInfo_Value(source_item, "D_LENGTH")
    local destination_item = reaper.CreateNewMIDIItemInProj(
        destination_track,
        destination_position,
        destination_position + item_len,
        false
    )
    if not destination_item then return nil end

    local destination_take = reaper.GetActiveTake(destination_item)
    if not destination_take then return destination_item end

    local ok, midi = reaper.MIDI_GetAllEvts(source_take, "")
    if ok and midi then
        reaper.MIDI_SetAllEvts(destination_take, midi)
        reaper.MIDI_Sort(destination_take)
    end

    local source_name_ok, source_name =
        reaper.GetSetMediaItemTakeInfo_String(source_take, "P_NAME", "", false)
    if source_name_ok and source_name then
        reaper.GetSetMediaItemTakeInfo_String(
            destination_take, "P_NAME", source_name, true
        )
    end

    local take_numeric = {
        "D_PLAYRATE", "D_PITCH", "B_PPITCH", "I_CHANMODE",
        "D_VOL", "D_PAN", "I_CUSTOMCOLOR"
    }
    for _, key in ipairs(take_numeric) do
        reaper.SetMediaItemTakeInfo_Value(
            destination_take, key,
            reaper.GetMediaItemTakeInfo_Value(source_take, key)
        )
    end

    local item_numeric = {
        "B_MUTE", "D_VOL", "D_FADEINLEN", "D_FADEOUTLEN",
        "C_FADEINSHAPE", "C_FADEOUTSHAPE"
    }
    for _, key in ipairs(item_numeric) do
        reaper.SetMediaItemInfo_Value(
            destination_item, key,
            reaper.GetMediaItemInfo_Value(source_item, key)
        )
    end

    return destination_item
end

local function copy_item_slice(
    source_project,
    destination_project,
    source_item,
    destination_track,
    source_region,
    destination_scene_start
)
    local item_pos = reaper.GetMediaItemInfo_Value(source_item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(source_item, "D_LENGTH")
    local item_end = item_pos + item_len
    local clip_start = math.max(item_pos, source_region.start_pos)
    local clip_end = math.min(item_end, source_region.end_pos)

    if clip_end <= clip_start + EPSILON then return nil end

    local ok, chunk = reaper.GetItemStateChunk(source_item, "", false)
    if not ok or not chunk then return nil end

    local destination_item = reaper.AddMediaItemToTrack(destination_track)
    if not destination_item then return nil end

    chunk = regenerate_item_guids(chunk)
    reaper.SetItemStateChunk(destination_item, chunk, false)

    if item_has_midi(source_item) then
        -- Copy MIDI event data into a fresh MIDI item.  SetItemStateChunk on an
        -- empty item can leave pooled/embedded MIDI sources empty in REAPER.
        -- Preserve the complete original item and translate only its position.
        reaper.DeleteTrackMediaItem(destination_track, destination_item)
        local scene_offset =
            destination_scene_start - source_region.start_pos
        return copy_midi_item(
            source_item,
            destination_track,
            item_pos + scene_offset
        )
    else
        local destination_position =
            destination_scene_start + (clip_start - source_region.start_pos)
        local destination_length = clip_end - clip_start
        local left_trim = clip_start - item_pos

        reaper.SetMediaItemInfo_Value(
            destination_item, "D_POSITION", destination_position
        )
        reaper.SetMediaItemInfo_Value(
            destination_item, "D_LENGTH", destination_length
        )

        if left_trim > EPSILON then
            for take_index = 0, reaper.CountTakes(destination_item) - 1 do
                local take = reaper.GetTake(destination_item, take_index)
                if take then
                    local playrate =
                        reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    local startoffs =
                        reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                    reaper.SetMediaItemTakeInfo_Value(
                        take,
                        "D_STARTOFFS",
                        startoffs + left_trim * playrate
                    )
                end
            end
        end
    end

    return destination_item
end

local function add_destination_track(destination_project)
    local index = reaper.CountTracks(destination_project)

    if type(reaper.InsertTrackInProject) == "function" then
        reaper.InsertTrackInProject(destination_project, index, 0)
    else
        reaper.SelectProjectInstance(destination_project)
        reaper.InsertTrackAtIndex(index, true)
    end

    return reaper.GetTrack(destination_project, index)
end

local function create_project_tab()
    reaper.Main_OnCommand(40859, 0) -- New project tab
    return reaper.EnumProjects(-1, "")
end

local function collect_used_regions(entries, project_number)
    local seen = {}
    local regions = {}

    for _, entry in ipairs(entries) do
        local region = entry.patterns[project_number]
        if region and not seen[region.number] then
            seen[region.number] = true
            regions[#regions + 1] = region
        end
    end

    return regions
end

local function copy_send_settings(source_track, send_index, destination_track, destination_index)
    local numeric_keys = {
        "D_VOL", "D_PAN", "D_PANLAW",
        "I_SENDMODE", "I_SRCCHAN", "I_DSTCHAN", "I_MIDIFLAGS"
    }
    for _, key in ipairs(numeric_keys) do
        local value =
            reaper.GetTrackSendInfo_Value(source_track, 0, send_index, key)
        reaper.SetTrackSendInfo_Value(
            destination_track, 0, destination_index, key, value
        )
    end
end

local function rebuild_internal_sends(destination_by_source)
    for source_track, destination_track in pairs(destination_by_source) do
        local send_count = reaper.GetTrackNumSends(source_track, 0)
        for send_index = 0, send_count - 1 do
            local source_destination =
                reaper.GetTrackSendInfo_Value(
                    source_track, 0, send_index, "P_DESTTRACK"
                )
            local mapped_destination =
                destination_by_source[source_destination]

            if mapped_destination then
                local destination_index =
                    reaper.CreateTrackSend(
                        destination_track,
                        mapped_destination
                    )
                if destination_index >= 0 then
                    copy_send_settings(
                        source_track,
                        send_index,
                        destination_track,
                        destination_index
                    )
                end
            end
        end
    end
end

local function copy_project_group(destination_project, entries, project_number, output_bus)
    local source_project = get_project(project_number)
    if not source_project then return nil end

    local used_regions = collect_used_regions(entries, project_number)
    if #used_regions == 0 then return nil end

    local source_info = collect_project_track_info(source_project, used_regions)
    local included = {}

    -- For an actually used subproject, keep its complete track/mixer structure.
    -- This preserves bus tracks, receive-only tracks and FX/routing helpers that
    -- may contain no media items themselves but are essential to the sound.
    for _, info in ipairs(source_info) do
        included[#included + 1] = info
    end

    if #included == 0 then return nil end

    local parent = output_bus
    local owns_parent = false

    if not parent then
        parent = add_destination_track(destination_project)
        owns_parent = true
        local source_master = reaper.GetMasterTrack(source_project)
        if source_master then
            copy_track_settings(
                source_master,
                parent,
                string.format("ReaGroove %d", project_number)
            )
        else
            reaper.GetSetMediaTrackInfo_String(
                parent,
                "P_NAME",
                string.format("ReaGroove %d", project_number),
                true
            )
        end

        local master_name = source_master
            and get_track_name(source_master, "")
            or ""
        local export_bus_name = master_name ~= ""
            and string.format("ReaGroove %d - %s", project_number, master_name)
            or string.format("ReaGroove %d", project_number)

        reaper.GetSetMediaTrackInfo_String(
            parent,
            "P_NAME",
            export_bus_name,
            true
        )
        reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 0)
    end

    local destination_by_source = {}
    local original_destination_tracks = {}
    if owns_parent then
        original_destination_tracks[#original_destination_tracks + 1] = parent
    end

    for number, info in ipairs(included) do
        local destination_track = add_destination_track(destination_project)
        original_destination_tracks[#original_destination_tracks + 1] = destination_track
        destination_by_source[info.track] = destination_track

        copy_track_settings(
            info.track,
            destination_track,
            string.format("Subproject %d - track %d", project_number, number)
        )
    end

    -- Restore explicit sends/receives between copied tracks.
    rebuild_internal_sends(destination_by_source)

    -- Route every original top-level mainsend into the exported subproject
    -- bus.  CreateTrackSend is performed while the destination project is the
    -- selected project.  Only disable the track's direct master send AFTER the
    -- explicit send was created successfully.
    reaper.SelectProjectInstance(destination_project)
    for _, info in ipairs(included) do
        if info.depth == 0 then
            local destination_track = destination_by_source[info.track]
            if destination_track then
                local source_mainsend =
                    reaper.GetMediaTrackInfo_Value(info.track, "B_MAINSEND")

                if source_mainsend > 0.5 then
                    local send_index =
                        reaper.CreateTrackSend(destination_track, parent)

                    if send_index and send_index >= 0 then
                        reaper.SetTrackSendInfo_Value(
                            destination_track, 0, send_index, "D_VOL", 1
                        )
                        reaper.SetTrackSendInfo_Value(
                            destination_track, 0, send_index, "D_PAN", 0
                        )
                        reaper.SetTrackSendInfo_Value(
                            destination_track, 0, send_index, "I_SENDMODE", 0
                        )
                        reaper.SetMediaTrackInfo_Value(
                            destination_track, "B_MAINSEND", 0
                        )
                    else
                        -- Never silence the track if REAPER refuses the send.
                        reaper.SetMediaTrackInfo_Value(
                            destination_track, "B_MAINSEND", source_mainsend
                        )
                    end
                end
            end
        end
    end

    -- Rebuild the included part of the source folder tree below our new
    -- subproject parent. The last copied track also closes that parent.
    for number, info in ipairs(included) do
        local destination_track = destination_by_source[info.track]
        local current_depth = info.depth
        local next_depth

        if number < #included then
            next_depth = included[number + 1].depth
        else
            next_depth = 0
        end

        reaper.SetMediaTrackInfo_Value(
            destination_track,
            "I_FOLDERDEPTH",
            next_depth - current_depth
        )
    end

    -- Populate every playlist scene on the copied tracks.
    for _, entry in ipairs(entries) do
        local source_region = entry.patterns[project_number]

        if source_region and entry.length > EPSILON then
            for _, info in ipairs(included) do
                local destination_track = destination_by_source[info.track]

                for item_index = 0, reaper.CountTrackMediaItems(info.track) - 1 do
                    local source_item = reaper.GetTrackMediaItem(info.track, item_index)
                    if item_overlaps_region(source_item, source_region) then
                        copy_item_slice(
                            source_project,
                            destination_project,
                            source_item,
                            destination_track,
                            source_region,
                            entry.start_pos
                        )
                    end
                end
            end
        end
    end

    return {
        project_number = project_number,
        parent = parent,
        owns_parent = owns_parent,
        tracks = original_destination_tracks,
        destination_by_source = destination_by_source
    }
end

local function add_scene_regions(destination_project, entries)
    for _, entry in ipairs(entries) do
        if entry.length > EPSILON then
            reaper.AddProjectMarker2(
                destination_project,
                true,
                entry.start_pos,
                entry.end_pos,
                string.format("Scene %d", entry.scene_number),
                -1,
                0
            )
        end
    end
end

local function build_arrangement_project(entries, route_to_main_buses)
    local destination_project = create_project_tab()
    if not destination_project then return nil, nil end

    local groups = {}
    local timing_source = get_project(1)
    if timing_source then
        copy_project_timing(timing_source, destination_project)
        copy_master_settings(timing_source, destination_project)
    end

    reaper.PreventUIRefresh(1)

    local main_group = nil
    if route_to_main_buses then
        -- Project 1 is the main ReaGroove mixer. Copy it first so its bus
        -- tracks and MASTER FX routing exist before subprojects are connected.
        main_group = copy_project_group(
            destination_project,
            entries,
            1,
            nil
        )
        if main_group then groups[#groups + 1] = main_group end

        local main_source_project = get_project(1)

        for project_number = 2, 8 do
            local output_bus = nil

            -- Main project bus layout:
            -- project 2 -> main track 3 (16PADS / drums)
            -- project 3 -> main track 4 (Bass)
            -- ...
            -- project 8 -> main track 9 (Synth2)
            if main_group
               and main_group.destination_by_source
               and main_source_project then
                local source_bus =
                    reaper.GetTrack(main_source_project, project_number - 1)
                output_bus =
                    source_bus
                    and main_group.destination_by_source[source_bus]
                    or nil
            end

            local group = copy_project_group(
                destination_project,
                entries,
                project_number,
                output_bus
            )
            if group then groups[#groups + 1] = group end
        end
    else
        -- Stems keep the existing independent per-subproject bus structure.
        for project_number = 1, 8 do
            local group = copy_project_group(
                destination_project,
                entries,
                project_number,
                nil
            )
            if group then groups[#groups + 1] = group end
        end
    end

    add_scene_regions(destination_project, entries)
    reaper.PreventUIRefresh(-1)

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    return destination_project, groups, main_group
end


local select_only_tracks

local function collect_main_stem_buses(main_group, main_source_project)
    local buses = {}
    if not main_group
       or not main_group.destination_by_source
       or not main_source_project then
        return buses
    end

    -- Main mixer stem buses are tracks 2..9 in REAPER's visible numbering:
    -- master, 16PADS, Bass, Guitar R, Guitar S, Synth, Synth1, Synth2.
    for source_index = 1, 8 do
        local source_track = reaper.GetTrack(main_source_project, source_index)
        local destination_track =
            source_track and main_group.destination_by_source[source_track] or nil
        if destination_track then
            buses[#buses + 1] = destination_track
        end
    end
    return buses
end

local function track_contains_midi(track)
    for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, item_index)
        for take_index = 0, reaper.CountTakes(item) - 1 do
            local take = reaper.GetTake(item, take_index)
            if take and reaper.TakeIsMIDI(take) then
                return true
            end
        end
    end
    return false
end

local function disable_noninstrument_fx(project)
    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)
        local has_midi = track_contains_midi(track)

        local instrument_index = -1
        if has_midi and type(reaper.TrackFX_GetInstrument) == "function" then
            instrument_index = reaper.TrackFX_GetInstrument(track)
        end

        local fx_count = reaper.TrackFX_GetCount(track)
        for fx = 0, fx_count - 1 do
            -- Dry audio tracks: every FX off.
            -- Dry MIDI tracks: keep only the actual instrument FX alive;
            -- all insert FX before/after it are disabled.
            local keep_enabled = has_midi and (fx == instrument_index)

            if type(reaper.TrackFX_SetEnabled) == "function" then
                reaper.TrackFX_SetEnabled(track, fx, keep_enabled)
            end
        end
    end
end

local function remove_global_fx_sends(
    project,
    main_group,
    main_source_project
)
    if not project or not main_group
       or not main_group.destination_by_source
       or not main_source_project then
        return
    end

    local destination_by_source = main_group.destination_by_source
    local global_fx_tracks = {}

    -- In the main project the MASTER FX folder starts at visible track 10
    -- (zero-based source index 9).  Everything from there onward belongs to
    -- the global effects/returns section rather than the eight instrument buses.
    for source_index = 9, reaper.CountTracks(main_source_project) - 1 do
        local source_track = reaper.GetTrack(
            main_source_project,
            source_index
        )
        local destination_track =
            source_track and destination_by_source[source_track] or nil
        if destination_track then
            global_fx_tracks[destination_track] = true
        end
    end

    -- Keep normal source -> main-bus routing intact.  Remove only sends whose
    -- destination is one of the copied global FX/return tracks.
    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)

        for send_index = reaper.GetTrackNumSends(track, 0) - 1, 0, -1 do
            local destination =
                reaper.GetTrackSendInfo_Value(
                    track,
                    0,
                    send_index,
                    "P_DESTTRACK"
                )

            if destination and global_fx_tracks[destination] then
                reaper.RemoveTrackSend(track, 0, send_index)
            end
        end
    end

    -- The global FX/return tracks themselves should not contribute anything
    -- to a Dry stem.
    for track, _ in pairs(global_fx_tracks) do
        if reaper.ValidatePtr2(project, track, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
        end
    end
end

local function render_bus_tracks_to_stems(project, buses, wet)
    if #buses == 0 then
        return false, "Geen stem-bussen gevonden in het hoofdproject."
    end

    local directory, directory_err = ensure_export_directory()
    if not directory then
        return false, directory_err
    end

    local audio_dir =
        directory .. (wet and "/audio_wet" or "/audio_dry")
    reaper.RecursiveCreateDirectory(audio_dir, 0)

    local names = {}
    for i, bus in ipairs(buses) do
        names[i] = get_track_name(bus, string.format("Stem %d", i))
    end

    -- Render each bus separately. REAPER's project render setting was treating
    -- the eight selected buses as one combined source, hence v15 produced one
    -- stem. Soloing one bus at a time and rendering the master mix preserves
    -- all downstream sends/returns/master FX for Wet.
    local rendered_files = {}
    local total_tracks = reaper.CountTracks(project)

    -- Save the original mute/solo state.  Do not solo the stem bus:
    -- with explicit sends that can exclude its upstream source tracks and
    -- produce a perfectly valid but silent render.
    local original_mute = {}
    local original_solo = {}
    for track_index = 0, total_tracks - 1 do
        local track = reaper.GetTrack(project, track_index)
        original_mute[track] =
            reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        original_solo[track] =
            reaper.GetMediaTrackInfo_Value(track, "I_SOLO")
        reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
    end

    for bus_index, bus in ipairs(buses) do
        -- Isolate at the source/input side instead of muting the mixer buses.
        -- The target main bus, MASTER FX returns and real master remain fully
        -- active, so Wet includes the global effects generated by this stem.
        for track_index = 0, total_tracks - 1 do
            local track = reaper.GetTrack(project, track_index)
            reaper.SetMediaTrackInfo_Value(
                track, "B_MUTE", original_mute[track] or 0
            )
        end

        for other_index, other_bus in ipairs(buses) do
            reaper.SetMediaTrackInfo_Value(other_bus, "B_MUTE", 0)

            if other_index ~= bus_index then
                -- Find tracks whose explicit send feeds this non-target main
                -- bus and mute only those source tracks. Do not mute return/FX
                -- tracks downstream of the selected bus.
                for track_index = 0, total_tracks - 1 do
                    local source_track = reaper.GetTrack(project, track_index)
                    local send_count = reaper.GetTrackNumSends(source_track, 0)

                    for send_index = 0, send_count - 1 do
                        local destination =
                            reaper.GetTrackSendInfo_Value(
                                source_track, 0, send_index, "P_DESTTRACK"
                            )
                        if destination == other_bus then
                            reaper.SetMediaTrackInfo_Value(
                                source_track, "B_MUTE", 1
                            )
                            break
                        end
                    end
                end
            end
        end

        local safe_name = names[bus_index]:gsub("[^%w%-%._ ]", "_")
        local file_base = string.format("%02d-%s", bus_index, safe_name)
        local full_path = audio_dir .. "/" .. file_base .. ".wav"

        reaper.GetSetProjectInfo(project, "RENDER_SETTINGS", 0, true)
        reaper.GetSetProjectInfo(project, "RENDER_BOUNDSFLAG", 1, true)
        reaper.GetSetProjectInfo(project, "RENDER_CHANNELS", 2, true)
        reaper.GetSetProjectInfo(project, "RENDER_ADDTOPROJ", 0, true)

        if type(reaper.GetSetProjectInfo_String) == "function" then
            reaper.GetSetProjectInfo_String(
                project, "RENDER_FILE", audio_dir, true
            )
            reaper.GetSetProjectInfo_String(
                project, "RENDER_PATTERN", file_base, true
            )
        end

        reaper.Main_OnCommandEx(41824, 0, project)
        rendered_files[#rendered_files + 1] = full_path
    end

    -- Restore temporary mixer states before dismantling the render project.
    for track_index = 0, total_tracks - 1 do
        local track = reaper.GetTrack(project, track_index)
        if track then
            reaper.SetMediaTrackInfo_Value(
                track, "B_MUTE", original_mute[track] or 0
            )
            reaper.SetMediaTrackInfo_Value(
                track, "I_SOLO", original_solo[track] or 0
            )
        end
    end

    -- Remove the temporary complete mixer. The final project is deliberately
    -- only eight plain audio tracks.
    for index = reaper.CountTracks(project) - 1, 0, -1 do
        local track = reaper.GetTrack(project, index)
        reaper.DeleteTrack(track)
    end

    for index, file_path in ipairs(rendered_files) do
        local track = add_destination_track(project)
        reaper.GetSetMediaTrackInfo_String(
            track, "P_NAME", names[index], true
        )
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
        reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)

        local item = reaper.AddMediaItemToTrack(track)
        local take = item and reaper.AddTakeToMediaItem(item) or nil
        local source = reaper.PCM_Source_CreateFromFile(file_path)

        if item and take and source then
            reaper.SetMediaItemTake_Source(take, source)
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)

            local length, is_qn =
                reaper.GetMediaSourceLength(source)
            if length and length > 0 then
                reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
            end

            -- Force REAPER to refresh/build the waveform for the newly
            -- attached rendered source, just like the import/record flows.
            if type(reaper.PCM_Source_BuildPeaks) == "function" then
                reaper.PCM_Source_BuildPeaks(source, 0)
            end
            if type(reaper.UpdateItemInProject) == "function" then
                reaper.UpdateItemInProject(item)
            end
        else
            return false,
                "Kon gerenderde stem niet terugplaatsen: " .. file_path
        end
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    -- Rebuild missing peak displays after all eight files have been attached.
    -- Action 40441: Peaks: Rebuild peaks for selected items.
    if type(reaper.Main_OnCommandEx) == "function" then
        for index = 0, reaper.CountMediaItems(project) - 1 do
            local item = reaper.GetMediaItem(project, index)
            reaper.SetMediaItemSelected(item, true)
        end
        reaper.Main_OnCommandEx(40441, 0, project)
        for index = 0, reaper.CountMediaItems(project) - 1 do
            local item = reaper.GetMediaItem(project, index)
            reaper.SetMediaItemSelected(item, false)
        end
        reaper.UpdateArrange()
    end

    return true
end

select_only_tracks = function(project, tracks)
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        reaper.SetTrackSelected(track, false)
    end

    for _, track in ipairs(tracks) do
        if reaper.ValidatePtr2(project, track, "MediaTrack*") then
            reaper.SetTrackSelected(track, true)
        end
    end
end

local function render_groups_to_stems(project, groups)
    local parents = {}
    local originals = {}

    for _, group in ipairs(groups) do
        parents[#parents + 1] = group.parent
        for _, track in ipairs(group.tracks) do
            originals[track] = true
        end
    end

    if #parents == 0 then return false, "De playlist bevat geen media om te renderen." end

    select_only_tracks(project, parents)
    reaper.Main_OnCommandEx(STEM_RENDER_ACTION, 0, project)

    local rendered = {}
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        if not originals[track] then rendered[#rendered + 1] = track end
    end

    if #rendered < #parents then
        return false,
            "REAPER heeft niet voor ieder subproject een stemtrack aangemaakt."
    end

    -- Delete the copied source arrangement; the newly rendered stem tracks
    -- remain. Delete via pointers because stem tracks may have been inserted
    -- between the originals.
    for track, _ in pairs(originals) do
        if reaper.ValidatePtr2(project, track, "MediaTrack*") then
            reaper.DeleteTrack(track)
        end
    end

    -- Keep only one clean track per rendered subproject and give it a stable
    -- ReaGroove name. REAPER's stem action creates one long item per parent.
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        local project_number = groups[index + 1]
            and groups[index + 1].project_number
            or (index + 1)
        reaper.GetSetMediaTrackInfo_String(
            track,
            "P_NAME",
            string.format("ReaGroove Stem %d", project_number),
            true
        )
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
        reaper.SetTrackSelected(track, false)
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    return true
end

function M.export_reaper_project()
    local entries = collect_playlist()
    if #entries == 0 then
        show_error("De playlist is leeg.")
        return false
    end

    local total_length = build_timeline(entries)
    if total_length <= EPSILON then
        show_error("De playlist bevat geen geldige regions.")
        return false
    end

    local project, groups = build_arrangement_project(entries, true)
    if not project or #groups == 0 then
        show_error("Er is geen media gevonden om te exporteren.")
        return false
    end

    local ok, err = save_export_project(project, "project")
    if not ok then
        show_error(err)
        return false
    end
    return true
end

function M.export_stems(wet)
    if wet == nil then wet = true end

    local entries = collect_playlist()
    if #entries == 0 then
        show_error("De playlist is leeg.")
        return false
    end

    local total_length = build_timeline(entries)
    if total_length <= EPSILON then
        show_error("De playlist bevat geen geldige regions.")
        return false
    end

    -- Stems use the same main-mixer routing as the now-correct REAPER export.
    local project, groups, main_group =
        build_arrangement_project(entries, true)

    if not project or not main_group then
        show_error("De hoofd-mixer kon niet voor stems worden opgebouwd.")
        return false
    end

    local main_source_project = get_project(1)
    local buses = collect_main_stem_buses(
        main_group,
        main_source_project
    )

    if #buses == 0 then
        show_error("Er zijn geen hoofdbussen gevonden om te renderen.")
        return false
    end

    if not wet then
        -- Dry = preserve source -> main-bus routing, but remove the global
        -- master-FX sends/returns and disable all local audio FX. MIDI tracks
        -- keep only their instrument plug-in so they still generate sound.
        remove_global_fx_sends(
            project,
            main_group,
            main_source_project
        )
        disable_noninstrument_fx(project)
    end

    local ok, err = render_bus_tracks_to_stems(project, buses, wet)
    if not ok then
        show_error(err)
        return false
    end

    local kind = wet and "stems_wet" or "stems_dry"
    local saved, save_err = save_export_project(project, kind)
    if not saved then
        show_error(save_err)
        return false
    end

    return true
end

function M.run(mode, stems_wet)
    mode = math.floor(tonumber(mode) or 0)

    if mode == 1 then
        return M.export_reaper_project()
    elseif mode == 2 then
        return M.export_stems(stems_wet)
    end

    return false
end


-- ------------------------------------------------------------
-- Dedicated Export edit sub-screen
-- ------------------------------------------------------------
local selected_mode = 1
local stems_wet = true

function M.open()
    selected_mode = 1
    stems_wet = true
end

function M.draw(api, C, close_screen)
    -- A real sub-screen: blank the complete 8x8 matrix first, then draw only
    -- the controls that belong to Export.
    api.drawblock(8, 1, 1, 8, C.OFF, api.MODE_NONE)

    -- 81 = editable REAPER project
    api.drawpad(8, 1, C.ORANGE, api.MODE_RADIO, {
        group = "edit_export_type",
        selected_row = 8,
        selected_col = selected_mode,
        active_color = C.WHITE,
        on_press = function()
            selected_mode = 1
            api.redraw()
        end
    })

    -- 82 = rendered stems
    api.drawpad(8, 2, C.LIGHT_BLUE, api.MODE_RADIO, {
        group = "edit_export_type",
        selected_row = 8,
        selected_col = selected_mode,
        active_color = C.WHITE,
        on_press = function()
            selected_mode = 2
            api.redraw()
        end
    })

    -- 83 = Wet/Dry toggle, only visible when Stems (82) is selected.
    if selected_mode == 2 then
        api.drawpad(
            8, 3,
            stems_wet and C.BLUE or C.ORANGE,
            api.MODE_HIGHLIGHT,
            {
                active_color = C.WHITE,
                on_press = function()
                    stems_wet = not stems_wet
                    api.redraw()
                end,
                on_release = function()
                    return true
                end
            }
        )
    end

    -- 11 confirm
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            local ok = M.run(selected_mode, stems_wet)
            if ok ~= false and close_screen then
                close_screen()
            end
        end
    })

    -- 12 cancel
    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            if close_screen then close_screen() end
        end
    })
end

return M
