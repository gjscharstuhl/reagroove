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
        return nil, "Select a MIDI item or create the sequencer MIDI item first."
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

function M.copy_filled_bars_to_rest(sequencer)
    local context, err = require_take(sequencer)
    if not context then return false, err end

    local bar_count = math.max(1, math.floor(tonumber(sequencer.get_bar_count()) or 1))
    if bar_count <= 1 then
        return true, "nothing_to_copy"
    end

    -- The source phrase is the consecutive run of non-empty bars starting at bar 1.
    -- Example: only bar 1 filled -> 1,1,1,1... ; bars 1+2 filled -> 1,2,1,2...
    local notes_by_bar = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for bar = 1, bar_count do
        notes_by_bar[bar] = {}
    end

    for index = 0, note_count - 1 do
        local ok, selected, muted, start_ppq, end_ppq, channel, pitch, velocity =
            reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)
            local bar, bar_start = bar_for_note_qn(context, start_qn, bar_count)
            if bar and bar_start then
                notes_by_bar[bar][#notes_by_bar[bar] + 1] = {
                    selected = selected,
                    muted = muted,
                    offset_qn = start_qn - bar_start,
                    length_qn = math.max(0.000001, end_qn - start_qn),
                    channel = channel,
                    pitch = pitch,
                    velocity = velocity
                }
            end
        end
    end

    local source_length = 0
    for bar = 1, bar_count do
        if #notes_by_bar[bar] == 0 then break end
        source_length = bar
    end

    if source_length == 0 then
        return false, "Bar 1 is empty; there is no phrase to repeat."
    end
    if source_length >= bar_count then
        return true, "nothing_to_copy"
    end

    local destination_indices = {}
    for index = 0, note_count - 1 do
        local ok, _, _, start_ppq = reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local bar = bar_for_note_qn(context, start_qn, bar_count)
            if bar and bar > source_length then
                destination_indices[#destination_indices + 1] = index
            end
        end
    end

    reaper.Undo_BeginBlock2(context.project)
    reaper.MIDI_DisableSort(context.take)

    for i = #destination_indices, 1, -1 do
        reaper.MIDI_DeleteNote(context.take, destination_indices[i])
    end

    for destination_bar = source_length + 1, bar_count do
        local source_bar = ((destination_bar - 1) % source_length) + 1
        local dst_start, dst_end = get_bar_qn_range(context, destination_bar)
        if dst_start and dst_end then
            for _, note in ipairs(notes_by_bar[source_bar]) do
                local start_qn = dst_start + note.offset_qn
                if start_qn < dst_end then
                    local end_qn = math.min(dst_end, start_qn + note.length_qn)
                    reaper.MIDI_InsertNote(
                        context.take,
                        note.selected,
                        note.muted,
                        reaper.MIDI_GetPPQPosFromProjQN(context.take, start_qn),
                        reaper.MIDI_GetPPQPosFromProjQN(context.take, end_qn),
                        note.channel,
                        note.pitch,
                        note.velocity,
                        true
                    )
                end
            end
        end
    end

    finish(context, "Repeat filled ReaGroove bars through region")
    return true, source_length
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

function M.swing_bars(sequencer, bars, amount, division_qn, division_label)
    local wanted = bars_lookup(bars)
    if next(wanted) == nil then return false, "Select one or more bars." end

    amount = math.max(-1, math.min(1, tonumber(amount) or 0))
    if math.abs(amount) < 0.000001 then
        return false, "Swing amount is centered; choose a value left or right first."
    end

    division_qn = tonumber(division_qn) or 0.25
    if division_qn <= 0 then return false, "Invalid swing division." end
    division_label = tostring(division_label or "1/16")

    local context, err = require_take(sequencer)
    if not context then return false, err end

    -- Build selected measure ranges. Swing is anchored to the item's musical
    -- timeline, not to note order, so live-recorded timing can still be classified.
    local ranges = {}
    for bar in pairs(wanted) do
        local qn_start, qn_end = get_bar_qn_range(context, bar)
        if qn_start and qn_end and qn_end > qn_start then
            ranges[#ranges + 1] = { bar = bar, qn_start = qn_start, qn_end = qn_end }
        end
    end
    table.sort(ranges, function(a, b) return a.bar < b.bar end)
    if #ranges == 0 then return false, "The selected bars could not be resolved." end

    -- Use the first resolved bar as the phase anchor. This lets coarse divisions
    -- such as 1/1 work across consecutive selected measures as well as 1/8 and 1/16.
    local phase_qn = ranges[1].qn_start
    local changes = {}
    local _, note_count = reaper.MIDI_CountEvts(context.take)

    for index = 0, note_count - 1 do
        local ok, selected, muted, start_ppq, end_ppq, channel, pitch, velocity =
            reaper.MIDI_GetNote(context.take, index)
        if ok then
            local start_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, start_ppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(context.take, end_ppq)

            local in_selected_bar = false
            for _, range in ipairs(ranges) do
                if start_qn >= range.qn_start and start_qn < range.qn_end then
                    in_selected_bar = true
                    break
                end
            end

            if in_selected_bar then
                local relative = (start_qn - phase_qn) / division_qn
                local grid_index = math.floor(relative + 0.5)

                -- Every second grid point is the swung offbeat for the chosen
                -- division: 1/16 -> alternate sixteenths, 1/8 -> alternate eighths,
                -- 1/4 -> alternate quarter notes, 1/1 -> alternate whole notes.
                if grid_index % 2 == 1 then
                    local nominal_qn = phase_qn + grid_index * division_qn
                    local delta_qn = division_qn * 0.5 * amount
                    local duration_qn = math.max(0.000001, end_qn - start_qn)

                    -- Preserve the player's timing offset relative to the straight
                    -- grid, then add swing. Clamp between neighbouring even-grid
                    -- anchors so negative swing can never cross the previous anchor.
                    local timing_offset = start_qn - nominal_qn
                    local new_start = nominal_qn + timing_offset + delta_qn
                    local epsilon = 0.000001
                    local left_anchor = phase_qn + (grid_index - 1) * division_qn
                    local right_anchor = phase_qn + (grid_index + 1) * division_qn
                    new_start = math.max(left_anchor + epsilon, math.min(right_anchor - epsilon, new_start))
                    local new_end = new_start + duration_qn

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

    if #changes == 0 then
        return false, "No offbeat " .. division_label .. " notes were found in the selected bars."
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
    finish(context, "Swing ReaGroove MIDI bars (" .. division_label .. ")")
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
