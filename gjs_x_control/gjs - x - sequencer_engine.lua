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

local function get_target_track(project)
    if not project then
        return nil
    end

    -- ReaGroove track rule: the first record-armed track in the ActiveTrack
    -- subproject is the sequencer/edit target. Keep this deterministic and
    -- independent of REAPER track/item selection.
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

-- Find a normal MIDI item on the armed track when no tagged sequencer item
-- exists. Live-recorded MIDI does not carry the ReaGroove sequencer tag, but
-- it should still be editable/displayable by screen 6. Prefer an exact
-- region-sized item; otherwise use the MIDI item with the largest overlap
-- with the target region.
local function find_midi_item_in_region(track, region_start, region_end)
    if not track or not region_start or not region_end then
        return nil, nil
    end

    local best_item, best_take, best_overlap = nil, nil, 0

    for index = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, index)
        local take = item and reaper.GetActiveTake(item) or nil

        if take and reaper.TakeIsMIDI(take) then
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start +
                reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

            if math.abs(item_start - region_start) <= POSITION_TOLERANCE
            and math.abs(item_end - region_end) <= POSITION_TOLERANCE then
                return item, take
            end

            local overlap = math.max(0,
                math.min(item_end, region_end) - math.max(item_start, region_start)
            )

            if overlap > best_overlap then
                best_overlap = overlap
                best_item = item
                best_take = take
            end
        end
    end

    return best_item, best_take
end

local function get_selected_midi_item(project)
    if not project then return nil, nil, nil end

    local selected_count = reaper.CountSelectedMediaItems(project)
    for index = 0, selected_count - 1 do
        local item = reaper.GetSelectedMediaItem(project, index)
        local take = item and reaper.GetActiveTake(item) or nil
        if take and reaper.TakeIsMIDI(take) then
            return item, take, reaper.GetMediaItemTrack(item)
        end
    end

    return nil, nil, nil
end

local function get_selected_midi_item_context(preferred_project)
    -- First use the project that is actually active in REAPER. Live-recorded
    -- items are normally selected there, even when ReaGroove's ActiveTrack
    -- still points at a subproject tab.
    local current_project = reaper.EnumProjects(-1, "")
    if current_project then
        local item, take, track = get_selected_midi_item(current_project)
        if item then
            return current_project, item, take, track
        end
    end

    -- Then try the ReaGroove project selected by ActiveTrack.
    if preferred_project and preferred_project ~= current_project then
        local item, take, track = get_selected_midi_item(preferred_project)
        if item then
            return preferred_project, item, take, track
        end
    end

    return nil, nil, nil, nil
end

function M.get_context()
    local project = get_active_project()
    local region_start, region_end, region_number = get_target_region(project)
    local track = get_target_track(project)

    -- A MIDI item is valid regardless of origin. Prefer an exact/overlapping
    -- MIDI item on the first armed track in the target region. Tagged legacy
    -- sequencer items remain valid, but no special ownership is required.
    local item, take = find_midi_item_in_region(track, region_start, region_end)

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

local function get_owned_sequencer_context()
    return M.get_context()
end

-- Any usable MIDI item is a sequencer item. Its origin does not matter:
-- live-recorded, created by screen 6, or created manually in REAPER.
function M.item_exists()
    return M.get_context().item ~= nil
end

local function count_bars_by_measure_boundaries(
    project,
    region_start,
    region_end
)
    if not project
    or region_start == nil
    or region_end == nil
    or region_end <= region_start then
        return 0
    end

    local _, start_measure =
        reaper.TimeMap2_timeToBeats(project, region_start)

    if start_measure == nil then
        return 0
    end

    local measure_index = math.floor(start_measure)
    local bar_count = 0
    local tolerance = 0.000001

    -- The Launchpad overview supports at most sixteen visible bars.
    while bar_count < 16 do
        local ok, _, qn_end =
            reaper.TimeMap_GetMeasureInfo(
                project,
                measure_index
            )

        if not ok or qn_end == nil then
            break
        end

        local measure_end_time =
            reaper.TimeMap2_QNToTime(project, qn_end)

        bar_count = bar_count + 1

        if measure_end_time >= region_end - tolerance then
            break
        end

        measure_index = measure_index + 1
    end

    return math.max(1, bar_count)
end

function M.get_bar_count()
    local context = M.get_context()

    return count_bars_by_measure_boundaries(
        context.project,
        context.region_start,
        context.region_end
    )
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
            "Create MIDI item",
            -1
        )
        return false, "REAPER could not create the MIDI item."
    end

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
        "Create MIDI item",
        -1
    )

    return true, item
end


function M.delete_item()
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

    if not context.item then
        return true, "not_found"
    end

    reaper.Undo_BeginBlock2(context.project)

    local deleted = reaper.DeleteTrackMediaItem(
        context.track,
        context.item
    )

    if not deleted then
        reaper.Undo_EndBlock2(
            context.project,
            "Delete MIDI item",
            -1
        )
        return false, "REAPER could not delete the MIDI item."
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock2(
        context.project,
        "Delete MIDI item",
        -1
    )

    return true, "deleted"
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
        math.min(16.0, tonumber(options.gate) or 0.5)
    )
    local offset = math.max(
        -0.45,
        math.min(0.45, tonumber(options.offset) or 0)
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
    local nominal_start_qn = qn_start + ((step - 1) * step_qn)
    local note_start_qn = nominal_start_qn + (step_qn * offset)
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

function M.microtune_note(options)
    options = options or {}

    local pitch = math.floor(tonumber(options.pitch) or -1)
    local step = math.floor(tonumber(options.step) or 0)
    local bar = math.floor(tonumber(options.bar) or 1)
    local offset = math.max(
        -0.45,
        math.min(0.45, tonumber(options.offset) or 0)
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

    local step_qn = (qn_end - qn_start) / 16
    local nominal_qn = qn_start + ((step - 1) * step_qn)
    local wanted_qn = nominal_qn + (step_qn * offset)

    local nominal_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        nominal_qn
    )

    local wanted_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        wanted_qn
    )

    local next_ppq = reaper.MIDI_GetPPQPosFromProjQN(
        context.take,
        nominal_qn + step_qn
    )

    -- Slightly more than half a step lets us find an already microtuned
    -- note again and set a new absolute offset.
    local tolerance_ppq = math.max(
        1,
        math.abs(next_ppq - nominal_ppq) * 0.55
    )

    local _, note_count = reaper.MIDI_CountEvts(context.take)
    local best_index = nil
    local best_distance = nil
    local best_note = nil

    for index = 0, note_count - 1 do
        local ok,
              selected,
              muted,
              note_start,
              note_end,
              channel,
              note_pitch,
              velocity =
            reaper.MIDI_GetNote(context.take, index)

        if ok and note_pitch == pitch then
            local distance = math.abs(note_start - nominal_ppq)

            if distance <= tolerance_ppq
            and (best_distance == nil or distance < best_distance) then
                best_index = index
                best_distance = distance
                best_note = {
                    selected = selected,
                    muted = muted,
                    length = math.max(1, note_end - note_start),
                    channel = channel,
                    pitch = note_pitch,
                    velocity = velocity
                }
            end
        end
    end

    if not best_note then
        return true, "not_found"
    end

    reaper.Undo_BeginBlock2(context.project)

    -- Delete/reinsert is more reliable here than MIDI_SetNote for moving
    -- notes in newly created MIDI sources.
    local deleted = reaper.MIDI_DeleteNote(
        context.take,
        best_index
    )

    if not deleted then
        reaper.Undo_EndBlock2(
            context.project,
            "Microtune ReaGroove drum note",
            -1
        )
        return false, "REAPER could not remove the MIDI note before moving it."
    end

    local inserted = reaper.MIDI_InsertNote(
        context.take,
        best_note.selected,
        best_note.muted,
        wanted_ppq,
        wanted_ppq + best_note.length,
        best_note.channel,
        best_note.pitch,
        best_note.velocity,
        true
    )

    if not inserted then
        reaper.Undo_EndBlock2(
            context.project,
            "Microtune ReaGroove drum note",
            -1
        )
        return false, "REAPER could not reinsert the moved MIDI note."
    end

    reaper.MIDI_Sort(context.take)
    reaper.MarkTrackItemsDirty(context.track, context.item)
    reaper.UpdateItemInProject(context.item)
    reaper.UpdateArrange()

    reaper.Undo_EndBlock2(
        context.project,
        "Microtune ReaGroove drum note",
        -1
    )

    return true, "moved"
end



------------------------------------------------------------
-- JSFX display bridge
------------------------------------------------------------

local DISPLAY_GMEM = "GJS_X_BRIDGE"
local DISPLAY_BASE = 300
local DISPLAY_ACTIVE_PROJECT_SLOT = DISPLAY_BASE + 32 -- gmem[332]
local display_pattern_version = 0
local display_force_version = 0


local function publish_active_clock_project()
    local active_track = tonumber(
        reaper.GetExtState("GJS_X", "ActiveTrack")
    ) or 0

    active_track = math.max(
        0,
        math.min(8, math.floor(active_track))
    )

    reaper.gmem_write(
        DISPLAY_ACTIVE_PROJECT_SLOT,
        active_track
    )
end

local function clear_display_steps()
    for index = 0, 15 do
        reaper.gmem_write(DISPLAY_BASE + 16 + index, 0)
    end
end

function M.disable_display(expected_mode)
    reaper.gmem_attach(DISPLAY_GMEM)

    local current_mode = math.floor(
        tonumber(reaper.gmem_read(DISPLAY_BASE + 0)) or 0
    )

    if expected_mode ~= nil
    and current_mode ~= math.floor(expected_mode) then
        return false
    end

    reaper.gmem_write(DISPLAY_BASE + 0, 0)
    display_force_version = display_force_version + 1
    reaper.gmem_write(DISPLAY_BASE + 5, display_force_version)
    return true
end

local function get_region_at_position(project, position)
    if not project or position == nil then
        return nil, nil, nil
    end

    local _, marker_count, region_count =
        reaper.CountProjectMarkers(project)

    for index = 0, marker_count + region_count - 1 do
        local ok, is_region, start_pos, end_pos, _, number =
            reaper.EnumProjectMarkers2(project, index)

        if ok and is_region
        and position >= start_pos
        and position < end_pos then
            return start_pos, end_pos, number
        end
    end

    return nil, nil, nil
end

local function count_region_bars(project, region_start, region_end)
    return count_bars_by_measure_boundaries(
        project,
        region_start,
        region_end
    )
end

function M.get_main_display_context()
    local project = get_active_project()
    if not project then
        return { project = nil }
    end

    local play_state = reaper.GetPlayStateEx(project)
    local transport_active =
        (play_state & 1) == 1 or
        (play_state & 4) == 4

    local position
    if transport_active then
        position = reaper.GetPlayPositionEx(project)
    else
        position = reaper.GetCursorPositionEx(project)
    end

    local region_start, region_end, region_number =
        get_region_at_position(project, position)

    -- At stop, or briefly outside all markers, keep the selected region as
    -- a useful fallback. During playback the region under the playhead wins,
    -- so a queued/pending TargetRegion cannot hide the current region.
    if not region_start then
        region_start, region_end, region_number =
            get_target_region(project)
    end

    return {
        project = project,
        region_start = region_start,
        region_end = region_end,
        region_number = region_number,
        bar_count = count_region_bars(
            project,
            region_start,
            region_end
        )
    }
end

function M.update_main_display()
    local context = M.get_main_display_context()

    reaper.gmem_attach(DISPLAY_GMEM)
    publish_active_clock_project()
    reaper.gmem_write(DISPLAY_BASE + 0, 2)

    if not context.project
    or not context.region_start
    or not context.region_end
    or context.region_end <= context.region_start then
        reaper.gmem_write(DISPLAY_BASE + 1, 1)
        reaper.gmem_write(DISPLAY_BASE + 2, 0)
        reaper.gmem_write(DISPLAY_BASE + 3, 0)
        clear_display_steps()
        display_pattern_version = display_pattern_version + 1
        reaper.gmem_write(DISPLAY_BASE + 4, display_pattern_version)
        return false
    end

    local region_start_qn = reaper.TimeMap2_timeToQN(
        context.project,
        context.region_start
    )

    reaper.gmem_write(DISPLAY_BASE + 1, 1)
    reaper.gmem_write(DISPLAY_BASE + 2, region_start_qn or 0)
    reaper.gmem_write(DISPLAY_BASE + 3, context.bar_count or 0)

    -- Keep the current mainscreen overview visible while switching regions.
    -- The JSFX receives the new region context atomically via the version bump
    -- below, without an intermediate empty frame.
    display_pattern_version = display_pattern_version + 1
    reaper.gmem_write(DISPLAY_BASE + 4, display_pattern_version)
    return true
end

-- Return all unique MIDI pitches that start on one sequencer step.
-- This is used by screen 6 to recall an existing chord from the MIDI item.
function M.get_step_pitches(options)
    options = options or {}

    local bar = math.max(1, math.floor(tonumber(options.bar) or 1))
    local step = math.max(1, math.min(16, math.floor(tonumber(options.step) or 1)))
    local context = M.get_context()
    local result = {}
    local seen = {}

    if not context.project or not context.take or not context.region_start then
        return result
    end

    local qn_start, qn_end = get_bar_qn_range(
        context.project,
        context.region_start,
        bar
    )
    if not qn_start or not qn_end or qn_end <= qn_start then
        return result
    end

    local step_qn = (qn_end - qn_start) / 16
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for note_index = 0, note_count - 1 do
        local ok, _, _, start_ppq, _, _, pitch =
            reaper.MIDI_GetNote(context.take, note_index)

        if ok then
            local note_qn = reaper.MIDI_GetProjQNFromPPQPos(
                context.take,
                start_ppq
            )
            local relative = (note_qn - qn_start) / step_qn
            local note_step = math.floor(relative + 0.5) + 1

            if note_step == step
            and note_qn >= qn_start - (step_qn * 0.5)
            and note_qn < qn_end + (step_qn * 0.5)
            and not seen[pitch] then
                seen[pitch] = true
                result[#result + 1] = pitch
            end
        end
    end

    table.sort(result)
    return result
end

-- Return the pitches plus editable properties for one sequencer step.
-- The lowest-pitch note is used as the reference for velocity and length;
-- notes inserted as a chord by screen 6 normally share those properties.
function M.get_step_note_data(options)
    options = options or {}

    local bar = math.max(1, math.floor(tonumber(options.bar) or 1))
    local step = math.max(1, math.min(16, math.floor(tonumber(options.step) or 1)))
    local context = M.get_context()
    local result = { pitches = {}, velocity = nil, gate = nil }
    local notes = {}

    if not context.project or not context.take or not context.region_start then
        return result
    end

    local qn_start, qn_end = get_bar_qn_range(
        context.project,
        context.region_start,
        bar
    )
    if not qn_start or not qn_end or qn_end <= qn_start then
        return result
    end

    local step_qn = (qn_end - qn_start) / 16
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for note_index = 0, note_count - 1 do
        local ok, _, _, start_ppq, end_ppq, _, pitch, velocity =
            reaper.MIDI_GetNote(context.take, note_index)

        if ok then
            local note_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local relative = (note_qn - qn_start) / step_qn
            local note_step = math.floor(relative + 0.5) + 1

            if note_step == step
            and note_qn >= qn_start - (step_qn * 0.5)
            and note_qn < qn_end + (step_qn * 0.5) then
                local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)
                notes[#notes + 1] = {
                    pitch = pitch,
                    velocity = velocity or 0,
                    gate = math.max(0.01, (end_qn - note_qn) / step_qn)
                }
            end
        end
    end

    table.sort(notes, function(a, b) return a.pitch < b.pitch end)
    local seen = {}
    for _, note in ipairs(notes) do
        if not seen[note.pitch] then
            seen[note.pitch] = true
            result.pitches[#result.pitches + 1] = note.pitch
        end
    end

    if notes[1] then
        result.velocity = notes[1].velocity
        result.gate = notes[1].gate
    end

    return result
end

function M.update_display(options)
    options = options or {}

    local bar = math.max(1, math.floor(tonumber(options.bar) or 1))
    local pitch = math.floor(tonumber(options.pitch) or -1)
    local requested_pitches = {}
    local requested_lookup = {}

    if type(options.pitches) == "table" then
        for _, value in ipairs(options.pitches) do
            local requested_pitch = math.floor(tonumber(value) or -1)
            if requested_pitch >= 0 and requested_pitch <= 127
            and not requested_lookup[requested_pitch] then
                requested_lookup[requested_pitch] = true
                requested_pitches[#requested_pitches + 1] = requested_pitch
            end
        end
        table.sort(requested_pitches)
    elseif pitch >= 0 and pitch <= 127 then
        requested_lookup[pitch] = true
        requested_pitches[1] = pitch
    end

    local exact_pitches = options.exact_pitches == true
    local context = M.get_context()

    reaper.gmem_attach(DISPLAY_GMEM)
    publish_active_clock_project()
    reaper.gmem_write(DISPLAY_BASE + 0, 1)
    reaper.gmem_write(DISPLAY_BASE + 1, bar)

    if not context.project
    or not context.region_start
    or not context.region_end then
        reaper.gmem_write(DISPLAY_BASE + 2, 0)
        reaper.gmem_write(DISPLAY_BASE + 3, 0)
        clear_display_steps()
        display_pattern_version = display_pattern_version + 1
        reaper.gmem_write(DISPLAY_BASE + 4, display_pattern_version)
        return false
    end

    local region_start_qn = reaper.TimeMap2_timeToQN(
        context.project,
        context.region_start
    )

    reaper.gmem_write(DISPLAY_BASE + 2, region_start_qn or 0)
    reaper.gmem_write(DISPLAY_BASE + 3, M.get_bar_count())
    clear_display_steps()

    if context.take and #requested_pitches > 0 then
        local qn_start, qn_end = get_bar_qn_range(
            context.project,
            context.region_start,
            bar
        )

        if qn_start and qn_end and qn_end > qn_start then
            local step_qn = (qn_end - qn_start) / 16
            local step_notes = {}
            local _, note_count = reaper.MIDI_CountEvts(context.take)

            for note_index = 0, note_count - 1 do
                local ok, _, _, start_ppq, _, _, note_pitch, velocity =
                    reaper.MIDI_GetNote(context.take, note_index)

                if ok then
                    local note_qn = reaper.MIDI_GetProjQNFromPPQPos(
                        context.take,
                        start_ppq
                    )
                    local relative = (note_qn - qn_start) / step_qn
                    local step = math.floor(relative + 0.5) + 1

                    if step >= 1 and step <= 16
                    and note_qn >= qn_start - (step_qn * 0.5)
                    and note_qn < qn_end + (step_qn * 0.5) then
                        local entry = step_notes[step]
                        if not entry then
                            entry = { pitches = {}, count = 0, velocity = 0 }
                            step_notes[step] = entry
                        end
                        if not entry.pitches[note_pitch] then
                            entry.pitches[note_pitch] = true
                            entry.count = entry.count + 1
                        end
                        if requested_lookup[note_pitch] then
                            entry.velocity = math.max(entry.velocity, velocity or 0)
                        end
                    end
                end
            end

            for step = 1, 16 do
                local entry = step_notes[step]
                local matches = entry ~= nil

                if matches then
                    for _, requested_pitch in ipairs(requested_pitches) do
                        if not entry.pitches[requested_pitch] then
                            matches = false
                            break
                        end
                    end
                end

                -- In chord mode, a step is shown only when the MIDI item has
                -- exactly the selected chord: every selected pitch and no
                -- additional pitch starting on that step.
                if matches and exact_pitches
                and entry.count ~= #requested_pitches then
                    matches = false
                end

                reaper.gmem_write(
                    DISPLAY_BASE + 15 + step,
                    matches and math.max(1, entry.velocity) or 0
                )
            end
        end
    end

    display_pattern_version = display_pattern_version + 1
    reaper.gmem_write(DISPLAY_BASE + 4, display_pattern_version)
    return true
end

return M
