-- ============================================================
-- gjs - x - pattern_slots.lua
-- Track-scoped reusable patterns in ~/jams/patterns.
--
-- Filename:
--   <edit-track><slot-2-digits>.wav / .mid
--   e.g. track 2, slot 01 => 201.wav / 201.mid
--
-- Save:
--   - only the first record-armed track inside the selected Edit project
--   - only media overlapping the selected region
--   - audio: temporary duplicates are glued inside the region and copied as .wav
--   - MIDI: notes/CC from all overlapping MIDI items are merged into one .mid
--   - originals stay intact
--
-- Load:
--   - only scans files belonging to the selected Edit track/project
--   - replaces media in the selected region on the first record-armed internal track
--   - resizes the region to the stored media length when needed
-- ============================================================

local M = {}

local source = debug.getinfo(1, "S").source
local script_path = source:match("^@(.+)$") or ""
local script_dir = script_path:match("^(.*[/\\])") or ""
local resize = dofile(script_dir .. "gjs - x - resize.lua")

local HOME = os.getenv("HOME")
local PATTERN_DIR = HOME and (HOME .. "/jams/patterns") or nil
local SLOT_COUNT = 56
local EPSILON = 0.000001
local GLUE_WITHIN_TIME_SELECTION = 41588

local MIDI_PPQ = 960

local function write_u16_be(n)
    n = math.floor(n) % 65536
    return string.char(math.floor(n / 256) % 256, n % 256)
end

local function write_u32_be(n)
    n = math.floor(n) % 4294967296
    return string.char(
        math.floor(n / 16777216) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256,
        n % 256
    )
end

local function write_vlq(value)
    value = math.max(0, math.floor(value + 0.5))
    local bytes = { value % 128 }
    value = math.floor(value / 128)
    while value > 0 do
        table.insert(bytes, 1, 128 + (value % 128))
        value = math.floor(value / 128)
    end
    return string.char(table.unpack(bytes))
end

local function midi_event_bytes(status, data1, data2)
    local high = status - (status % 16)
    if high == 0xC0 or high == 0xD0 then
        return string.char(status, data1 % 128)
    end
    return string.char(status, data1 % 128, data2 % 128)
end

local function add_midi_event(events, tick, priority, bytes)
    events[#events + 1] = {
        tick = math.max(0, math.floor(tick + 0.5)),
        priority = priority or 10,
        bytes = bytes
    }
end

local function qn_to_tick(qn, region_qn_start)
    return (qn - region_qn_start) * MIDI_PPQ
end

local function save_midi_pattern(project, items, region, destination)
    local region_qn_start = reaper.TimeMap2_timeToQN(project, region.start_pos)
    local region_qn_end = reaper.TimeMap2_timeToQN(project, region.end_pos)
    local region_ticks = math.max(1, math.floor((region_qn_end - region_qn_start) * MIDI_PPQ + 0.5))
    local events = {}
    local found_midi = false

    -- Put the current project tempo in the file. REAPER can then derive a sane
    -- source length when the .mid is loaded as media.
    local _, _, tempo = reaper.TimeMap_GetTimeSigAtTime(project, region.start_pos)
    tempo = tonumber(tempo) or 120
    if tempo <= 0 then tempo = 120 end
    local mpqn = math.max(1, math.floor(60000000 / tempo + 0.5))
    add_midi_event(events, 0, 0, string.char(0xFF, 0x51, 0x03,
        math.floor(mpqn / 65536) % 256,
        math.floor(mpqn / 256) % 256,
        mpqn % 256))

    for _, item in ipairs(items) do
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            found_midi = true
            local _, note_count, cc_count = reaper.MIDI_CountEvts(take)

            for note_index = 0, note_count - 1 do
                local ok, _, muted, start_ppq, end_ppq, chan, pitch, vel =
                    reaper.MIDI_GetNote(take, note_index)
                if ok and not muted then
                    local note_start = reaper.MIDI_GetProjTimeFromPPQPos(take, start_ppq)
                    local note_end = reaper.MIDI_GetProjTimeFromPPQPos(take, end_ppq)
                    if note_start < region.end_pos - EPSILON and note_end > region.start_pos + EPSILON then
                        note_start = math.max(note_start, region.start_pos)
                        note_end = math.min(note_end, region.end_pos)
                        local start_qn = reaper.TimeMap2_timeToQN(project, note_start)
                        local end_qn = reaper.TimeMap2_timeToQN(project, note_end)
                        local status_on = 0x90 + (chan % 16)
                        local status_off = 0x80 + (chan % 16)
                        add_midi_event(events, qn_to_tick(start_qn, region_qn_start), 20,
                            midi_event_bytes(status_on, pitch, vel))
                        add_midi_event(events, qn_to_tick(end_qn, region_qn_start), 10,
                            midi_event_bytes(status_off, pitch, 0))
                    end
                end
            end

            for cc_index = 0, cc_count - 1 do
                local ok, _, muted, ppq, chanmsg, chan, msg2, msg3 =
                    reaper.MIDI_GetCC(take, cc_index)
                if ok and not muted then
                    local event_time = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
                    if event_time >= region.start_pos - EPSILON and event_time < region.end_pos - EPSILON then
                        local event_qn = reaper.TimeMap2_timeToQN(project, event_time)
                        local status = (chanmsg - (chanmsg % 16)) + (chan % 16)
                        add_midi_event(events, qn_to_tick(event_qn, region_qn_start), 15,
                            midi_event_bytes(status, msg2, msg3))
                    end
                end
            end
        end
    end

    if not found_midi then
        return false, "Geen MIDI-items in de geselecteerde region op de armed track."
    end

    table.sort(events, function(a, b)
        if a.tick == b.tick then return a.priority < b.priority end
        return a.tick < b.tick
    end)

    local chunks = {}
    local previous_tick = 0
    for _, event in ipairs(events) do
        local tick = math.min(event.tick, region_ticks)
        local delta = math.max(0, tick - previous_tick)
        chunks[#chunks + 1] = write_vlq(delta)
        chunks[#chunks + 1] = event.bytes
        previous_tick = tick
    end
    chunks[#chunks + 1] = write_vlq(math.max(0, region_ticks - previous_tick))
    chunks[#chunks + 1] = string.char(0xFF, 0x2F, 0x00)

    local track_data = table.concat(chunks)
    local smf = "MThd" .. write_u32_be(6) .. write_u16_be(0) .. write_u16_be(1) .. write_u16_be(MIDI_PPQ)
        .. "MTrk" .. write_u32_be(#track_data) .. track_data

    local output = io.open(destination, "wb")
    if not output then
        return false, "MIDI-patternbestand kon niet worden aangemaakt."
    end
    output:write(smf)
    output:close()
    return true
end

local function region_content_type(items)
    local has_midi = false
    local has_audio = false
    for _, item in ipairs(items) do
        local take = reaper.GetActiveTake(item)
        if take then
            if reaper.TakeIsMIDI(take) then has_midi = true else has_audio = true end
        end
    end
    if has_midi and has_audio then return "mixed" end
    if has_midi then return "midi" end
    if has_audio then return "audio" end
    return nil
end

local function valid_slot(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    slot = math.floor(slot)
    if slot < 1 or slot > SLOT_COUNT then return nil end
    return slot
end

local function valid_track_number(track_number)
    track_number = tonumber(track_number)
    if not track_number then return nil end
    track_number = math.floor(track_number)
    if track_number < 1 or track_number > 8 then return nil end
    return track_number
end

local function pattern_stem(track_number, slot)
    return string.format("%d%02d", track_number, slot)
end

local function slot_paths(track_number, slot)
    local stem = PATTERN_DIR .. "/" .. pattern_stem(track_number, slot)
    return stem .. ".wav", stem .. ".mid"
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function copy_file(source_path, destination_path)
    local input = io.open(source_path, "rb")
    if not input then return false end
    local data = input:read("*a")
    input:close()

    local output = io.open(destination_path, "wb")
    if not output then return false end
    output:write(data)
    output:close()
    return true
end

local function get_project(track_number)
    track_number = valid_track_number(track_number)
    if not track_number then return nil end
    return reaper.EnumProjects(track_number - 1, "")
end

local function get_regions(project)
    local regions = {}
    local _, marker_count, region_count = reaper.CountProjectMarkers(project)

    for index = 0, marker_count + region_count - 1 do
        local ok, is_region, start_pos, end_pos, name, id =
            reaper.EnumProjectMarkers2(project, index)
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

local function get_region(project, region_number)
    region_number = math.floor(tonumber(region_number) or 0)
    if region_number < 1 or region_number > 8 then return nil end
    return get_regions(project)[region_number]
end

local function get_first_armed_internal_track(project)
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        if track and reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5 then
            return track
        end
    end
    return nil
end

local function get_qn_per_bar(project, time_pos)
    local numerator, denominator = reaper.TimeMap_GetTimeSigAtTime(project, time_pos)
    numerator = tonumber(numerator) or 4
    denominator = tonumber(denominator) or 4
    if numerator < 1 then numerator = 4 end
    if denominator < 1 then denominator = 4 end
    return numerator * (4 / denominator)
end

local function region_bars(project, region)
    local qn_per_bar = get_qn_per_bar(project, region.start_pos)
    if qn_per_bar <= 0 then return nil end
    local qn0 = reaper.TimeMap2_timeToQN(project, region.start_pos)
    local qn1 = reaper.TimeMap2_timeToQN(project, region.end_pos)
    return math.max(1, math.min(16, math.floor(((qn1 - qn0) / qn_per_bar) + 0.5)))
end

local function collect_region_items(track, region)
    local items = {}
    for index = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, index)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if pos < region.end_pos - EPSILON and pos + len > region.start_pos + EPSILON then
            items[#items + 1] = item
        end
    end
    return items
end

local function clear_item_selection(project)
    for index = 0, reaper.CountMediaItems(project) - 1 do
        reaper.SetMediaItemSelected(reaper.GetMediaItem(project, index), false)
    end
end

local function duplicate_items_for_glue(project, track, items)
    local duplicates = {}
    clear_item_selection(project)

    for _, item in ipairs(items) do
        local ok, chunk = reaper.GetItemStateChunk(item, "", false)
        if ok then
            local duplicate = reaper.AddMediaItemToTrack(track)
            if duplicate and reaper.SetItemStateChunk(duplicate, chunk, false) then
                reaper.SetMediaItemSelected(duplicate, true)
                duplicates[#duplicates + 1] = duplicate
            elseif duplicate then
                reaper.DeleteTrackMediaItem(track, duplicate)
            end
        end
    end

    return duplicates
end

local function remove_items(track, items)
    for _, item in ipairs(items) do
        if reaper.ValidatePtr2(0, item, "MediaItem*") then
            reaper.DeleteTrackMediaItem(track, item)
        end
    end
end

local function get_glued_source_info(item)
    if not item then return nil end
    local take = reaper.GetActiveTake(item)
    if not take then return nil end
    local media_source = reaper.GetMediaItemTake_Source(take)
    if not media_source then return nil end
    local source_path = reaper.GetMediaSourceFileName(media_source, "")
    if not source_path or source_path == "" then return nil end
    return {
        take = take,
        source = media_source,
        source_path = source_path,
        is_midi = reaper.TakeIsMIDI(take)
    }
end

local function save_glued_pattern(project, track, region, track_number, slot)
    local originals = collect_region_items(track, region)
    if #originals == 0 then
        return false, "Geen items in de geselecteerde region op de geselecteerde track."
    end

    local content_type = region_content_type(originals)
    local wav_path, mid_path = slot_paths(track_number, slot)
    os.remove(wav_path)
    os.remove(mid_path)

    if content_type == "midi" then
        return save_midi_pattern(project, originals, region, mid_path)
    elseif content_type == "mixed" then
        return false, "De armed track bevat in deze region zowel audio als MIDI; sla die apart op."
    elseif content_type ~= "audio" then
        return false, "Geen bruikbare audio- of MIDI-takes in de geselecteerde region."
    end

    local previous_project = reaper.EnumProjects(-1, "")
    local old_start, old_end = reaper.GetSet_LoopTimeRange2(project, false, false, 0, 0, false)

    reaper.SelectProjectInstance(project)
    local duplicates = duplicate_items_for_glue(project, track, originals)
    if #duplicates == 0 then
        if previous_project then reaper.SelectProjectInstance(previous_project) end
        return false, "Items konden niet tijdelijk worden gekopieerd voor glue."
    end

    reaper.GetSet_LoopTimeRange2(project, true, false, region.start_pos, region.end_pos, false)
    reaper.Main_OnCommand(GLUE_WITHIN_TIME_SELECTION, 0)

    local glued = reaper.GetSelectedMediaItem(project, 0)
    local info = get_glued_source_info(glued)

    local success = false
    local error_message = nil

    if info then
        local destination = info.is_midi and mid_path or wav_path
        success = copy_file(info.source_path, destination)
        if not success then
            error_message = "Glue-bestand kon niet naar de patternmap worden gekopieerd."
        end
    else
        error_message = "REAPER glue leverde geen extern media-bestand op."
    end

    -- Glue replaces the selected duplicates with the glued result. Remove that
    -- result (or any remaining duplicates on failure) so the original project
    -- content is untouched.
    if glued and reaper.ValidatePtr2(project, glued, "MediaItem*") then
        reaper.DeleteTrackMediaItem(track, glued)
    end
    remove_items(track, duplicates)

    reaper.GetSet_LoopTimeRange2(project, true, false, old_start, old_end, false)
    if previous_project then reaper.SelectProjectInstance(previous_project) end
    reaper.UpdateArrange()

    return success, error_message
end

local function find_pattern_file(track_number, slot)
    if not PATTERN_DIR then return nil end
    local wav_path, mid_path = slot_paths(track_number, slot)
    if file_exists(mid_path) then return mid_path, true end
    if file_exists(wav_path) then return wav_path, false end
    return nil
end

local function get_pattern_bars(project, region, media_source)
    local length, length_is_qn = reaper.GetMediaSourceLength(media_source)
    if not length or length <= 0 then return nil end

    local qn_length
    if length_is_qn then
        qn_length = length
    else
        local start_qn = reaper.TimeMap2_timeToQN(project, region.start_pos)
        local end_qn = reaper.TimeMap2_timeToQN(project, region.start_pos + length)
        qn_length = end_qn - start_qn
    end

    local qn_per_bar = get_qn_per_bar(project, region.start_pos)
    if qn_per_bar <= 0 then return nil end
    return math.max(1, math.min(16, math.floor((qn_length / qn_per_bar) + 0.5)))
end

local function delete_region_items_on_track(track, region)
    for index = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, index)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if pos < region.end_pos - EPSILON and pos + len > region.start_pos + EPSILON then
            reaper.DeleteTrackMediaItem(track, item)
        end
    end
end

local function insert_pattern_file(project, track, region, path, stretch_audio)
    local media_source = reaper.PCM_Source_CreateFromFile(path)
    if not media_source then return false, "Patternbestand kon niet door REAPER worden geopend." end

    local item = reaper.AddMediaItemToTrack(track)
    if not item then return false, "Nieuw pattern-item kon niet worden aangemaakt." end

    local take = reaper.AddTakeToMediaItem(item)
    if not take then
        reaper.DeleteTrackMediaItem(track, item)
        return false, "Nieuwe pattern-take kon niet worden aangemaakt."
    end

    reaper.SetMediaItemTake_Source(take, media_source)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", region.start_pos)

    local target_length = region.end_pos - region.start_pos
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", target_length)

    -- Audio stretch mode: keep the region fixed and fit the complete source
    -- inside it. The take playrate makes the sample follow the musical
    -- length/BPM of the current region. Preserve pitch while changing rate.
    if stretch_audio and not reaper.TakeIsMIDI(take) and target_length > EPSILON then
        local source_length, length_is_qn = reaper.GetMediaSourceLength(media_source)
        if source_length and source_length > EPSILON and not length_is_qn then
            reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", source_length / target_length)
            reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
        end
    end

    reaper.SetMediaItemSelected(item, true)
    return true
end


local function snapshot_regions(project)
    local snapshot = {}
    if not project then return snapshot end
    local regions = get_regions(project)
    for _, region in ipairs(regions) do
        snapshot[#snapshot + 1] = {
            id = region.id,
            start_pos = region.start_pos,
            end_pos = region.end_pos,
            name = region.name
        }
    end
    return snapshot
end

local function restore_regions(project, snapshot)
    if not project or not snapshot then return end
    for _, region in ipairs(snapshot) do
        reaper.SetProjectMarker2(
            project,
            region.id,
            true,
            region.start_pos,
            region.end_pos,
            region.name or ""
        )
    end
end

local function snapshot_all_items(project)
    local snapshot = {}
    if not project then return snapshot end

    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)
        if track then
            for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, item_index)
                local ok, chunk = reaper.GetItemStateChunk(item, "", false)
                if ok and chunk then
                    snapshot[#snapshot + 1] = {
                        track_index = track_index,
                        chunk = chunk
                    }
                end
            end
        end
    end

    return snapshot
end

local function restore_all_items(project, snapshot)
    if not project or not snapshot then return false end

    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)
        if track then
            for item_index = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
                local item = reaper.GetTrackMediaItem(track, item_index)
                reaper.DeleteTrackMediaItem(track, item)
            end
        end
    end

    for _, saved in ipairs(snapshot) do
        local track = reaper.GetTrack(project, saved.track_index)
        if track then
            local item = reaper.AddMediaItemToTrack(track)
            if item then
                reaper.SetItemStateChunk(item, saved.chunk, false)
            end
        end
    end

    return true
end

local function restore_preview_snapshot(session)
    if not session or not session.project then
        return false, "Geen geldige pattern-preview actief."
    end

    reaper.PreventUIRefresh(1)
    restore_regions(session.project, session.project_regions)
    restore_all_items(session.project, session.project_items)
    restore_regions(session.main_project, session.main_regions)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    return true
end

function M.scan_existing(track_number)
    local existing = {}
    track_number = valid_track_number(track_number)
    if not PATTERN_DIR or not track_number then return existing end

    for slot = 1, SLOT_COUNT do
        existing[slot] = find_pattern_file(track_number, slot) ~= nil
    end
    return existing
end

function M.can_load(slot, track_number)
    slot = valid_slot(slot)
    track_number = valid_track_number(track_number)
    return slot ~= nil and track_number ~= nil and find_pattern_file(track_number, slot) ~= nil
end

function M.save(slot, track_number, region_number)
    slot = valid_slot(slot)
    track_number = valid_track_number(track_number)
    if not slot or not track_number or not PATTERN_DIR then
        return false, "Ongeldig patternslot, tracknummer of HOME ontbreekt."
    end

    local project = get_project(track_number)
    if not project then return false, "Geselecteerde track/project niet gevonden." end
    local region = get_region(project, region_number)
    if not region then return false, "Geselecteerde region niet gevonden." end
    local track = get_first_armed_internal_track(project)
    if not track then return false, "Geen record-armed track in het subproject gevonden." end

    reaper.RecursiveCreateDirectory(PATTERN_DIR, 0)
    reaper.Undo_BeginBlock2(project)
    local ok, err = save_glued_pattern(project, track, region, track_number, slot)
    reaper.Undo_EndBlock2(project, "GJS-X save pattern " .. pattern_stem(track_number, slot), -1)
    return ok, err
end

local function load_impl(slot, track_number, region_number, create_undo, stretch_audio)
    slot = valid_slot(slot)
    track_number = valid_track_number(track_number)
    if not slot or not track_number or not PATTERN_DIR then
        return false, "Ongeldig patternslot, tracknummer of HOME ontbreekt."
    end

    local path, is_midi = find_pattern_file(track_number, slot)
    if not path then return false, "Dit patternslot bestaat niet voor de geselecteerde track." end

    local project = get_project(track_number)
    if not project then return false, "Geselecteerde track/project niet gevonden." end
    local region = get_region(project, region_number)
    if not region then return false, "Geselecteerde region niet gevonden." end
    local track = get_first_armed_internal_track(project)
    if not track then return false, "Geen record-armed track in het subproject gevonden." end

    local source_for_length = reaper.PCM_Source_CreateFromFile(path)
    if not source_for_length then return false, "Patternbestand kon niet worden geopend." end
    local target_bars = get_pattern_bars(project, region, source_for_length)
    if not target_bars then return false, "Patternlengte kon niet worden bepaald." end

    local current_bars = region_bars(project, region)
    if not current_bars then return false, "Doelregionlengte kon niet worden bepaald." end

    if create_undo then reaper.Undo_BeginBlock2(project) end

    -- MIDI always keeps the existing behaviour: the region follows the
    -- pattern length. For audio this only happens when stretch mode is off.
    local resize_region_to_pattern = is_midi or not stretch_audio
    if resize_region_to_pattern and current_bars ~= target_bars then
        local resize_fn = create_undo
            and resize.resize_selected_region_selected_project
            or resize.resize_selected_region_selected_project_no_undo
        local resized = resize_fn(track_number, region_number, target_bars)
        if resized == false then
            if create_undo then reaper.Undo_EndBlock2(project, "GJS-X load pattern", -1) end
            return false, "Doelregion kon niet worden resized."
        end
    end

    region = get_region(project, region_number)
    if not region then
        if create_undo then reaper.Undo_EndBlock2(project, "GJS-X load pattern", -1) end
        return false, "Doelregion niet meer gevonden na resize."
    end

    track = get_first_armed_internal_track(project) or track
    delete_region_items_on_track(track, region)
    clear_item_selection(project)

    local ok, err = insert_pattern_file(project, track, region, path, stretch_audio and not is_midi)
    reaper.UpdateArrange()
    if create_undo then
        reaper.Undo_EndBlock2(project, "GJS-X load pattern " .. pattern_stem(track_number, slot), -1)
    end
    return ok, err
end

function M.load(slot, track_number, region_number, stretch_audio)
    if stretch_audio == nil then stretch_audio = true end
    return load_impl(slot, track_number, region_number, true, stretch_audio)
end

function M.begin_preview(track_number, region_number)
    track_number = valid_track_number(track_number)
    region_number = math.floor(tonumber(region_number) or 0)
    if not track_number or region_number < 1 or region_number > 8 then
        return nil, "Ongeldige track of region voor pattern-preview."
    end

    local project = get_project(track_number)
    if not project then return nil, "Geselecteerde track/project niet gevonden." end
    local region = get_region(project, region_number)
    if not region then return nil, "Geselecteerde region niet gevonden." end
    if not get_first_armed_internal_track(project) then
        return nil, "Geen record-armed track in het subproject gevonden."
    end

    local main_project = reaper.EnumProjects(0, "")
    return {
        track_number = track_number,
        region_number = region_number,
        project = project,
        main_project = main_project,
        project_regions = snapshot_regions(project),
        project_items = snapshot_all_items(project),
        main_regions = snapshot_regions(main_project),
        active = true
    }
end

function M.preview_load(session, slot, stretch_audio)
    if not session or not session.active then
        return false, "Geen actieve pattern-preview."
    end

    local restored, restore_err = restore_preview_snapshot(session)
    if not restored then return false, restore_err end

    if stretch_audio == nil then stretch_audio = true end
    return load_impl(
        slot,
        session.track_number,
        session.region_number,
        false,
        stretch_audio
    )
end

function M.cancel_preview(session)
    if not session or not session.active then return true end
    local ok, err = restore_preview_snapshot(session)
    session.active = false
    return ok, err
end

function M.confirm_preview(session)
    if session then session.active = false end
    return true
end

return M
