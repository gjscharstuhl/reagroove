-- ============================================================
-- gjs - x - preset_selector.lua
-- REAPER FX preset selector for Screen 0 Edit.
-- Rows 8-7: top-level tracks (purple)
-- Rows 6-5: track FX (light blue)
-- Rows 4-3: REAPER-visible FX presets (green)
-- Row 1: confirm / cancel
--
-- Preview behaviour:
--   - pressing a preset loads it immediately so it can be auditioned
--   - green confirms the current preview state
--   - red restores every FX preset to the state from before opening
-- ============================================================

local M = {}
local MAX_PADS = 16

local selected_track = 1
local selected_fx = 1
local selected_preset = 1
local context_subproject = nil
local preview_snapshot = nil

local function get_project(subproject_number)
    local n = math.floor(tonumber(subproject_number) or 0)
    if n < 1 or n > 8 then return nil end
    return reaper.EnumProjects(n - 1, "")
end

local function top_level_tracks(project)
    local result = {}
    if not project then return result end
    local depth = 0
    for i = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, i)
        if track and depth == 0 then
            local tcp = reaper.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") > 0.5
            local mixer = reaper.GetMediaTrackInfo_Value(track, "B_SHOWINMIXER") > 0.5
            if tcp or mixer then result[#result + 1] = track end
        end
        if track then
            depth = depth + math.floor(reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH"))
            if depth < 0 then depth = 0 end
        end
    end
    return result
end

local function pad_row_col(index, upper_row, lower_row)
    if index <= 8 then return upper_row, index end
    return lower_row, index - 8
end

local function clamp_selection(value, count)
    if count < 1 then return 1 end
    value = math.floor(tonumber(value) or 1)
    return math.max(1, math.min(count, value))
end

local function current_context(subproject_number)
    local project = get_project(subproject_number)
    local tracks = top_level_tracks(project)
    selected_track = clamp_selection(selected_track, math.min(#tracks, MAX_PADS))
    local track = tracks[selected_track]
    local fx_count = track and reaper.TrackFX_GetCount(track) or 0
    selected_fx = clamp_selection(selected_fx, math.min(fx_count, MAX_PADS))
    local fx_index = selected_fx - 1
    local current_index, preset_count = -1, 0
    if track and fx_count > 0 then
        current_index, preset_count = reaper.TrackFX_GetPresetIndex(track, fx_index)
        current_index = tonumber(current_index) or -1
        preset_count = tonumber(preset_count) or 0
    end
    selected_preset = clamp_selection(selected_preset, math.min(preset_count, MAX_PADS))
    return project, tracks, track, fx_count, fx_index, current_index, preset_count
end

local function snapshot_presets(project)
    local snapshot = {
        project = project,
        entries = {},
        active = true
    }

    if not project then return snapshot end

    local tracks = top_level_tracks(project)
    for _, track in ipairs(tracks) do
        local fx_count = reaper.TrackFX_GetCount(track)
        for fx_index = 0, fx_count - 1 do
            local preset_index = reaper.TrackFX_GetPresetIndex(track, fx_index)
            preset_index = tonumber(preset_index) or -1
            snapshot.entries[#snapshot.entries + 1] = {
                track = track,
                fx_index = fx_index,
                preset_index = preset_index
            }
        end
    end

    return snapshot
end

local function restore_snapshot(snapshot)
    if not snapshot or not snapshot.active then return true end

    for _, entry in ipairs(snapshot.entries or {}) do
        if entry.track and entry.preset_index and entry.preset_index >= 0 then
            reaper.TrackFX_SetPresetByIndex(
                entry.track,
                entry.fx_index,
                entry.preset_index
            )
        end
    end

    if snapshot.project then
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
    end

    snapshot.active = false
    return true
end

local function finish_snapshot(snapshot)
    if snapshot then snapshot.active = false end
end

local function sync_selected_preset(subproject_number)
    local _, _, _, _, _, current_index = current_context(subproject_number)
    if current_index and current_index >= 0 then
        selected_preset = current_index + 1
    else
        selected_preset = 1
    end
end

function M.open(subproject_number)
    context_subproject = math.floor(tonumber(subproject_number) or 1)
    selected_track = 1
    selected_fx = 1
    selected_preset = 1

    local project = get_project(context_subproject)
    preview_snapshot = snapshot_presets(project)
    sync_selected_preset(context_subproject)
end

function M.draw(api, C, subproject_number, close_callback)
    subproject_number = context_subproject or subproject_number
    local project, tracks, track, fx_count, fx_index, current_index, preset_count =
        current_context(subproject_number)

    local dark_purple = { 16, 0, 24 }
    local dark_blue = { 0, 16, 28 }
    local dark_green = { 0, 22, 0 }

    -- Tracks: rows 8-7.
    for i = 1, MAX_PADS do
        local row, col = pad_row_col(i, 8, 7)
        local available = tracks[i] ~= nil
        local colour = available and C.PURPLE or dark_purple
        if i == selected_track and available then colour = C.WHITE end
        api.drawpad(row, col, colour, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = available and function()
                selected_track = i
                selected_fx = 1
                sync_selected_preset(subproject_number)
                api.redraw()
            end or nil
        })
    end

    -- FX: rows 6-5.
    for i = 1, MAX_PADS do
        local row, col = pad_row_col(i, 6, 5)
        local available = i <= fx_count
        local colour = available and C.LIGHT_BLUE or dark_blue
        if i == selected_fx and available then colour = C.WHITE end
        api.drawpad(row, col, colour, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = available and function()
                selected_fx = i
                sync_selected_preset(subproject_number)
                api.redraw()
            end or nil
        })
    end

    -- Presets: rows 4-3. A press is a live preview, just like Pattern Load:
    -- the preset is applied immediately so it can be auditioned while playing.
    for i = 1, MAX_PADS do
        local row, col = pad_row_col(i, 4, 3)
        local available = i <= preset_count
        local colour = available and C.GREEN or dark_green
        if i == selected_preset and available then colour = C.WHITE end
        api.drawpad(row, col, colour, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = available and function()
                selected_preset = i
                if track and fx_count > 0 then
                    local ok = reaper.TrackFX_SetPresetByIndex(
                        track,
                        fx_index,
                        selected_preset - 1
                    )
                    if not ok then
                        reaper.ShowConsoleMsg("Preset kon niet worden ingesteld.\n")
                    else
                        reaper.TrackList_AdjustWindows(false)
                        reaper.UpdateArrange()
                    end
                end
                api.redraw()
            end or nil
        })
    end

    -- Confirm: keep the live preview state and return to Edit.
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            finish_snapshot(preview_snapshot)
            if project then
                reaper.Undo_OnStateChange2(project, "GJS-X select FX preset")
            end
            preview_snapshot = nil
            if close_callback then close_callback() end
            api.redraw()
        end
    })

    -- Cancel: restore the complete preset state from before opening.
    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            restore_snapshot(preview_snapshot)
            preview_snapshot = nil
            if close_callback then close_callback() end
            api.redraw()
        end
    })
end

return M
