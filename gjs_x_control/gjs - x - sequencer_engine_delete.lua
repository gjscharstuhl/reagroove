-- ============================================================
-- gjs - x - sequencer_engine.lua
-- Shared MIDI sequencer logic for ReaGroove sequencer screens.
-- The screen decides the note mapping and user interface.
-- ============================================================

local M = {}

local ITEM_TAG_KEY = "P_EXT:GJS_X_SEQUENCER"
local ITEM_TAG_VALUE = "1"
local ITEM_NAME = "ReaGroove Sequencer"
local POSITION_TOLERANCE = 0.000001

local function get_active_project()
    local active_track = tonumber(
        reaper.GetExtState("GJS_X", "ActiveTrack")
    )

    if not active_track then
        return nil
    end

    active_track = math.floor(active_track)
    if active_track < 1 or active_track > 8 then
        return nil
    end

    return reaper.EnumProjects(active_track - 1, "")
end

local function get_target_region(project)
    local region_number = tonumber(
        reaper.GetExtState("GJS_X", "TargetRegion")
    )

    if not project or not region_number then
        return nil, nil, nil
    end

    region_number = math.floor(region_number)

    local _, marker_count, region_count =
        reaper.CountProjectMarkers(project)

    for index = 0, marker_count + region_count - 1 do
        local ok, is_region, start_pos, end_pos, _, number =
            reaper.EnumProjectMarkers2(project, index)

        if ok and is_region and number == region_number then
            return start_pos, end_pos, region_number
        end
    end

    return nil, nil, region_number
end

local function get_first_armed_track(project)
    if not project then
        return nil
    end

    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)

        if track
        and reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5 then
            return track
        end
    end

    return nil
end

local function is_sequencer_item(item)
    if not item then
        return false
    end

    local _, value = reaper.GetSetMediaItemInfo_String(
        item,
        ITEM_TAG_KEY,
        "",
        false
    )

    return value == ITEM_TAG_VALUE
end

local function find_sequencer_item(track, region_start, region_end)
    if not track or not region_start or not region_end then
        return nil
    end

    for index = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, index)
        local item_start =
            reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start +
            reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

        if is_sequencer_item(item)
        and math.abs(item_start - region_start) <= POSITION_TOLERANCE
        and math.abs(item_end - region_end) <= POSITION_TOLERANCE then
            return item
        end
    end

    return nil
end

function M.get_context()
    local project = get_active_project()
    local region_start, region_end, region_number =
        get_target_region(project)
    local track = get_first_armed_track(project)
    local item = find_sequencer_item(track, region_start, region_end)
    local take = item and reaper.GetActiveTake(item) or nil

    return {
        project = project,
        track = track,
        region_start = region_start,
        region_end = region_end,
        region_number = region_number,
        item = item,
        take = take
    }
end

function M.item_exists()
    return M.get_context().item ~= nil
end

function M.create_item()
    local context = M.get_context()

    if not context.project then
        return false, "No active ReaGroove subproject."
    end

    if not context.track then
        return false, "No record-armed track found in the active subproject."
    end

    if not context.region_start
    or not context.region_end
    or context.region_end <= context.region_start then
        return false, "The selected ReaGroove region was not found."
    end

    if context.item then
        return true, context.item
    end

    reaper.Undo_BeginBlock2(context.project)

    local item = reaper.CreateNewMIDIItemInProj(
        context.track,
        context.region_start,
        context.region_end,
        false
    )

    if not item then
        reaper.Undo_EndBlock2(
            context.project,
            "Create ReaGroove sequencer item",
            -1
        )
        return false, "REAPER could not create the MIDI item."
    end

    reaper.GetSetMediaItemInfo_String(
        item,
        ITEM_TAG_KEY,
        ITEM_TAG_VALUE,
        true
    )

    local take = reaper.GetActiveTake(item)
    if take then
        reaper.GetSetMediaItemTakeInfo_String(
            take,
            "P_NAME",
            ITEM_NAME,
            true
        )
    end

    reaper.SetMediaItemSelected(item, true)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock2(
        context.project,
        "Create ReaGroove sequencer item",
        -1
    )

    return true, item
end

local function get_bar_qn_range(project, region_start, bar_index)
    bar_index = math.max(1, math.floor(tonumber(bar_index) or 1))

    local _, first_measure =
        reaper.TimeMap2_timeToBeats(project, region_start)

    if first_measure == nil then
        return nil, nil
    end

    local measure_index = first_measure + (bar_index - 1)
    local ok, qn_start, qn_end =
        reaper.TimeMap_GetMeasureInfo(project, measure_index)

    if not ok or not qn_start or not qn_end or qn_end <= qn_start then
        return nil, nil
    end

    return qn_start, qn_end
end

local function note_exists_at(take, pitch, start_ppq, tolerance_ppq)
    local _, note_count = reaper.MIDI_CountEvts(take)

    for index = 0, note_count - 1 do
        local ok, _, _, note_start, _, _, note_pitch =
            reaper.MIDI_GetNote(take, index)

        if ok
        and note_pitch == pitch
        and math.abs(note_start - start_ppq) <= tolerance_ppq then
            return true
        end
    end

    return false
end

function M.insert_note(options)
    options = options or {}

    local pitch = math.floor(tonumber(options.pitch) or -1)
    local step = math.floor(tonumber(options.step) or 0)
    local bar = math.floor(tonumber(options.bar) or 1)
    local velocity = math.max(
        1,
        math.min(127, math.floor(tonumber(options.velocity) or 100))
    )
    local channel = math.max(
        0,
        math.min(15, math.floor(tonumber(options.channel) or 0))
    )
    local gate = math.max(
        0.01,
        math.min(1.0, tonumber(options.gate) or 0.5)
    )

    if pitch < 0 or pitch > 127 then
        return false, "Invalid MIDI note."
    end

    if step < 1 or step > 16 then
        return false, "Invalid sequencer step."
    end

    local context = M.get_context()

    if not context.item or not context.take then
        return false, "Create the sequencer MIDI item first."
    end

    local qn_start, qn_end = get_bar_qn_range(
        context.project,
        context.region_start,
        bar
    )

    if not qn_start or not qn_end then
        return false, "The sequencer bar could not be resolved."
    end

    local bar_start_time = reaper.TimeMap2_QNToTime(context.project, qn_start)
    local bar_end_time = reaper.TimeMap2_QNToTime(context.project, qn_end)

    if bar_start_time >= context.region_end
    or bar_end_time <= context.region_start then
        return false, "This bar lies outside the selected region."
    end

    local step_qn = (qn_end - qn_start) / 16
    local note_start_qn = qn_start + ((step - 1) * step_qn)
    local note_end_qn = note_start_qn + (step_qn * gate)

    local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        note_start_qn
    )
    local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        note_end_qn
    )
    local next_step_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        note_start_qn + step_qn
    )
    local tolerance_ppq = math.max(1, math.abs(next_step_ppq - start_ppq) * 0.01)

    if note_exists_at(context.take, pitch, start_ppq, tolerance_ppq) then
        return true, "exists"
    end

    reaper.Undo_BeginBlock2(context.project)

    local inserted = reaper.MIDI_InsertNote(
        context.take,
        false,
        false,
        start_ppq,
        end_ppq,
        channel,
        pitch,
        velocity,
        true
    )

    if not inserted then
        reaper.Undo_EndBlock2(
            context.project,
            "Insert ReaGroove drum note",
            -1
        )
        return false, "REAPER could not insert the MIDI note."
    end

    reaper.MIDI_Sort(context.take)
    reaper.MarkTrackItemsDirty(context.track, context.item)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock2(
        context.project,
        "Insert ReaGroove drum note",
        -1
    )

    return true, "inserted"
end

function M.delete_note(options)
    options = options or {}

    local pitch = math.floor(tonumber(options.pitch) or -1)
    local step = math.floor(tonumber(options.step) or 0)
    local bar = math.floor(tonumber(options.bar) or 1)

    if pitch < 0 or pitch > 127 then
        return false, "Invalid MIDI note."
    end

    if step < 1 or step > 16 then
        return false, "Invalid sequencer step."
    end

    local context = M.get_context()

    if not context.item or not context.take then
        return false, "Create the sequencer MIDI item first."
    end

    local qn_start, qn_end = get_bar_qn_range(
        context.project,
        context.region_start,
        bar
    )

    if not qn_start or not qn_end then
        return false, "The sequencer bar could not be resolved."
    end

    local step_qn = (qn_end - qn_start) / 16
    local wanted_qn = qn_start + ((step - 1) * step_qn)
    local wanted_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        wanted_qn
    )
    local next_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        wanted_qn + step_qn
    )

    -- Search within half a step. This also keeps deletion working after
    -- the note has later been shifted slightly by microtune.
    local tolerance_ppq = math.max(1, math.abs(next_ppq - wanted_ppq) * 0.49)
    local _, note_count = reaper.MIDI_CountEvts(context.take)
    local best_index = nil
    local best_distance = nil

    for index = 0, note_count - 1 do
        local ok, _, _, note_start, _, _, note_pitch =
            reaper.MIDI_GetNote(context.take, index)

        if ok and note_pitch == pitch then
            local distance = math.abs(note_start - wanted_ppq)

            if distance <= tolerance_ppq
            and (best_distance == nil or distance < best_distance) then
                best_index = index
                best_distance = distance
            end
        end
    end

    if best_index == nil then
        return true, "not_found"
    end

    reaper.Undo_BeginBlock2(context.project)

    local deleted = reaper.MIDI_DeleteNote(
        context.take,
        best_index
    )

    if not deleted then
        reaper.Undo_EndBlock2(
            context.project,
            "Delete ReaGroove drum note",
            -1
        )
        return false, "REAPER could not delete the MIDI note."
    end

    reaper.MIDI_Sort(context.take)
    reaper.MarkTrackItemsDirty(context.track, context.item)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock2(
        context.project,
        "Delete ReaGroove drum note",
        -1
    )

    return true, "deleted"
end

return M
