-- ============================================================
-- gjs - x - midi_edit_engine.lua
-- Measure-based MIDI editing helpers for screen 6.
-- ============================================================

local M = {}

local function get_bar_qn_range(context, bar_index)
    if not context or not context.project or context.region_start == nil then
        return nil, nil
    end

    bar_index = math.max(1, math.floor(tonumber(bar_index) or 1))
    local _, first_measure = reaper.TimeMap2_timeToBeats(
        context.project,
        context.region_start
    )
    if first_measure == nil then return nil, nil end

    local measure_index = math.floor(first_measure) + (bar_index - 1)
    local ok, qn_start, qn_end = reaper.TimeMap_GetMeasureInfo(
        context.project,
        measure_index
    )
    if not ok or not qn_start or not qn_end or qn_end <= qn_start then
        return nil, nil
    end
    return qn_start, qn_end
end

local function require_take(sequencer)
    local context = sequencer.get_context()
    if not context.project then
        return nil, "No active ReaGroove subproject."
    end
    if not context.item or not context.take then
        return nil, "Create the sequencer MIDI item first."
    end
    return context
end

local function finish(context, description)
    reaper.MIDI_Sort(context.take)
    if context.track and context.item then
        reaper.MarkTrackItemsDirty(context.track, context.item)
        reaper.UpdateItemInProject(context.item)
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock2(context.project, description, -1)
end

local function bars_lookup(bars)
    local lookup = {}
    for _, bar in ipairs(bars or {}) do
        bar = math.floor(tonumber(bar) or 0)
        if bar >= 1 and bar <= 16 then lookup[bar] = true end
    end
    return lookup
end

local function bar_for_note_qn(context, qn, max_bars)
    for bar = 1, max_bars do
        local qn_start, qn_end = get_bar_qn_range(context, bar)
        if qn_start and qn >= qn_start and qn < qn_end then
            return bar, qn_start, qn_end
        end
    end
    return nil
end

function M.copy_bar(sequencer, source_bar, destination_bar)
    source_bar = math.floor(tonumber(source_bar) or 0)
    destination_bar = math.floor(tonumber(destination_bar) or 0)
    if source_bar < 1 or destination_bar < 1 then
        return false, "Select one source bar and one destination bar."
    end
    if source_bar == destination_bar then
        return true, "same_bar"
    end

    local context, err = require_take(sequencer)
    if not context then return false, err end

    local src_start, src_end = get_bar_qn_range(context, source_bar)
    local dst_start, dst_end = get_bar_qn_range(context, destination_bar)
    if not src_start or not dst_start then
        return false, "The selected bar could not be resolved."
    end

    local source_notes = {}
    local destination_indices = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for index = 0, note_count - 1 do
        local ok, selected, muted, start_ppq, end_ppq, channel, pitch, velocity =
            reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)

            if start_qn >= src_start and start_qn < src_end then
                source_notes[#source_notes + 1] = {
                    selected = selected,
                    muted = muted,
                    offset_qn = start_qn - src_start,
                    length_qn = math.max(0.000001, end_qn - start_qn),
                    channel = channel,
                    pitch = pitch,
                    velocity = velocity
                }
            end

            if start_qn >= dst_start and start_qn < dst_end then
                destination_indices[#destination_indices + 1] = index
            end
        end
    end

    reaper.Undo_BeginBlock2(context.project)

    for i = #destination_indices, 1, -1 do
        reaper.MIDI_DeleteNote(context.take, destination_indices[i])
    end

    for _, note in ipairs(source_notes) do
        local start_qn = dst_start + note.offset_qn
        -- Do not create a new note outside the destination measure.
        if start_qn < dst_end then
            local end_qn = start_qn + note.length_qn
            local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(context.take, start_qn)
            local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(context.take, end_qn)
            reaper.MIDI_InsertNote(
                context.take,
                note.selected,
                note.muted,
                start_ppq,
                end_ppq,
                note.channel,
                note.pitch,
                note.velocity,
                true
            )
        end
    end

    finish(context, "Copy ReaGroove MIDI bar")
    return true, "copied"
end

function M.copy_bar_to_many(sequencer, source_bar, destination_bars)
    source_bar = math.floor(tonumber(source_bar) or 0)
    local destinations = {}
    local seen = {}
    for _, bar in ipairs(destination_bars or {}) do
        bar = math.floor(tonumber(bar) or 0)
        if bar >= 1 and bar <= 16 and bar ~= source_bar and not seen[bar] then
            seen[bar] = true
            destinations[#destinations + 1] = bar
        end
    end
    table.sort(destinations)

    if source_bar < 1 or #destinations == 0 then
        return false, "Select one source bar and one or more different destination bars."
    end

    local context, err = require_take(sequencer)
    if not context then return false, err end

    local src_start, src_end = get_bar_qn_range(context, source_bar)
    if not src_start then
        return false, "The selected source bar could not be resolved."
    end

    local destination_ranges = {}
    for _, bar in ipairs(destinations) do
        local qn_start, qn_end = get_bar_qn_range(context, bar)
        if not qn_start then
            return false, "One of the selected destination bars could not be resolved."
        end
        destination_ranges[#destination_ranges + 1] = {
            bar = bar,
            qn_start = qn_start,
            qn_end = qn_end
        }
    end

    local source_notes = {}
    local destination_indices = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for index = 0, note_count - 1 do
        local ok, selected, muted, start_ppq, end_ppq, channel, pitch, velocity =
            reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)

            if start_qn >= src_start and start_qn < src_end then
                source_notes[#source_notes + 1] = {
                    selected = selected,
                    muted = muted,
                    offset_qn = start_qn - src_start,
                    length_qn = math.max(0.000001, end_qn - start_qn),
                    channel = channel,
                    pitch = pitch,
                    velocity = velocity
                }
            end

            for _, range in ipairs(destination_ranges) do
                if start_qn >= range.qn_start and start_qn < range.qn_end then
                    destination_indices[#destination_indices + 1] = index
                    break
                end
            end
        end
    end

    reaper.Undo_BeginBlock2(context.project)

    for i = #destination_indices, 1, -1 do
        reaper.MIDI_DeleteNote(context.take, destination_indices[i])
    end

    for _, range in ipairs(destination_ranges) do
        for _, note in ipairs(source_notes) do
            local start_qn = range.qn_start + note.offset_qn
            if start_qn < range.qn_end then
                local end_qn = start_qn + note.length_qn
                local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(context.take, start_qn)
                local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(context.take, end_qn)
                reaper.MIDI_InsertNote(
                    context.take,
                    note.selected,
                    note.muted,
                    start_ppq,
                    end_ppq,
                    note.channel,
                    note.pitch,
                    note.velocity,
                    true
                )
            end
        end
    end

    finish(context, "Copy ReaGroove MIDI bar to multiple bars")
    return true, "copied"
end

function M.clear_bars(sequencer, bars)
    local wanted = bars_lookup(bars)
    if next(wanted) == nil then return false, "Select one or more bars." end

    local context, err = require_take(sequencer)
    if not context then return false, err end

    local bar_count = sequencer.get_bar_count()
    local delete_indices = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for index = 0, note_count - 1 do
        local ok, _, _, start_ppq = reaper.MIDI_GetNote(context.take, index)
        if ok then
            local qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local bar = bar_for_note_qn(context, qn, bar_count)
            if bar and wanted[bar] then delete_indices[#delete_indices + 1] = index end
        end
    end

    reaper.Undo_BeginBlock2(context.project)
    for i = #delete_indices, 1, -1 do
        reaper.MIDI_DeleteNote(context.take, delete_indices[i])
    end
    finish(context, "Clear ReaGroove MIDI bars")
    return true, "cleared"
end

function M.swing_bars(sequencer, bars, amount)
    local wanted = bars_lookup(bars)
    if next(wanted) == nil then return false, "Select one or more bars." end

    amount = math.max(-1, math.min(1, tonumber(amount) or 0))
    local context, err = require_take(sequencer)
    if not context then return false, err end

    local bar_count = sequencer.get_bar_count()
    local changes = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for index = 0, note_count - 1 do
        local ok, selected, muted, start_ppq, end_ppq, channel, pitch, velocity =
            reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)
            local bar, qn_start, qn_end = bar_for_note_qn(context, start_qn, bar_count)
            if bar and wanted[bar] then
                local step_qn = (qn_end - qn_start) / 16
                local relative = (start_qn - qn_start) / step_qn
                local nearest = math.max(0, math.min(15, math.floor(relative + 0.5)))
                -- 0-based odd indices are the offbeat sixteenths.
                if nearest % 2 == 1 then
                    local delta_qn = step_qn * 0.5 * amount
                    local new_start = start_qn + delta_qn
                    local new_end = end_qn + delta_qn
                    changes[#changes + 1] = {
                        index = index,
                        selected = selected,
                        muted = muted,
                        start_qn = new_start,
                        end_qn = new_end,
                        channel = channel,
                        pitch = pitch,
                        velocity = velocity
                    }
                end
            end
        end
    end

    reaper.Undo_BeginBlock2(context.project)
    for _, note in ipairs(changes) do
        reaper.MIDI_SetNote(
            context.take,
            note.index,
            note.selected,
            note.muted,
            reaper.MIDI_GetPPQPosFromProjQN(context.take, note.start_qn),
            reaper.MIDI_GetPPQPosFromProjQN(context.take, note.end_qn),
            note.channel,
            note.pitch,
            note.velocity,
            true
        )
    end
    finish(context, "Swing ReaGroove MIDI bars")
    return true, "swung"
end

function M.quantize_bars(sequencer, bars, strength)
    local wanted = bars_lookup(bars)
    if next(wanted) == nil then return false, "Select one or more bars." end

    strength = math.max(0.20, math.min(1.0, tonumber(strength) or 1.0))
    local context, err = require_take(sequencer)
    if not context then return false, err end

    local bar_count = sequencer.get_bar_count()
    local changes = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for index = 0, note_count - 1 do
        local ok, selected, muted, start_ppq, end_ppq, channel, pitch, velocity =
            reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)
            local bar, qn_start, qn_end = bar_for_note_qn(context, start_qn, bar_count)
            if bar and wanted[bar] then
                local step_qn = (qn_end - qn_start) / 16
                local relative = (start_qn - qn_start) / step_qn
                local nearest = math.max(0, math.min(16, math.floor(relative + 0.5)))
                local target_qn = qn_start + nearest * step_qn
                local delta_qn = (target_qn - start_qn) * strength
                changes[#changes + 1] = {
                    index = index,
                    selected = selected,
                    muted = muted,
                    start_qn = start_qn + delta_qn,
                    end_qn = end_qn + delta_qn,
                    channel = channel,
                    pitch = pitch,
                    velocity = velocity
                }
            end
        end
    end

    reaper.Undo_BeginBlock2(context.project)
    for _, note in ipairs(changes) do
        reaper.MIDI_SetNote(
            context.take,
            note.index,
            note.selected,
            note.muted,
            reaper.MIDI_GetPPQPosFromProjQN(context.take, note.start_qn),
            reaper.MIDI_GetPPQPosFromProjQN(context.take, note.end_qn),
            note.channel,
            note.pitch,
            note.velocity,
            true
        )
    end
    finish(context, "Quantize ReaGroove MIDI bars")
    return true, "quantized"
end

function M.undo(sequencer)
    local context = sequencer.get_context()
    if not context.project then return false, "No active ReaGroove subproject." end
    reaper.Undo_DoUndo2(context.project)
    reaper.UpdateArrange()
    return true
end

function M.redo(sequencer)
    local context = sequencer.get_context()
    if not context.project then return false, "No active ReaGroove subproject." end
    reaper.Undo_DoRedo2(context.project)
    reaper.UpdateArrange()
    return true
end

return M
