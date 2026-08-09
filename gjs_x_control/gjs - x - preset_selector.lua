-- ============================================================
-- gjs - x - preset_selector.lua
-- REAPER FX preset selector for Screen 0 Edit.
-- Rows 8-7: top-level tracks (purple)
-- Rows 6-5: track FX (light blue)
-- Rows 4-3: REAPER-visible FX presets (green)
-- Row 1: confirm / cancel
-- ============================================================

local M = {}
local MAX_PADS = 16

local selected_track = 1
local selected_fx = 1
local selected_preset = 1
local original_preset_index = nil
local context_subproject = nil

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

function M.open(subproject_number)
    context_subproject = math.floor(tonumber(subproject_number) or 1)
    selected_track = 1
    selected_fx = 1
    selected_preset = 1
    local _, _, _, _, _, current_index = current_context(context_subproject)
    if current_index and current_index >= 0 then
        selected_preset = current_index + 1
        original_preset_index = current_index
    else
        original_preset_index = nil
    end
end

function M.draw(api, C, subproject_number, close_callback)
    subproject_number = context_subproject or subproject_number
    local _, tracks, track, fx_count, fx_index, current_index, preset_count =
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
                selected_preset = 1
                original_preset_index = nil
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
                local _, _, _, _, new_fx_index, new_current = current_context(subproject_number)
                if new_current and new_current >= 0 then
                    selected_preset = new_current + 1
                    original_preset_index = new_current
                else
                    selected_preset = 1
                    original_preset_index = nil
                end
                api.redraw()
            end or nil
        })
    end

    -- Presets: rows 4-3. REAPER's preset list includes user presets and
    -- plug-in/factory presets that REAPER exposes through its preset dropdown.
    for i = 1, MAX_PADS do
        local row, col = pad_row_col(i, 4, 3)
        local available = i <= preset_count
        local colour = available and C.GREEN or dark_green
        if i == selected_preset and available then colour = C.WHITE end
        api.drawpad(row, col, colour, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = available and function()
                selected_preset = i
                api.redraw()
            end or nil
        })
    end

    -- Confirm: pad 11. Cancel: pad 12.
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            if track and fx_count > 0 and preset_count > 0 then
                reaper.Undo_BeginBlock2(get_project(subproject_number))
                local ok = reaper.TrackFX_SetPresetByIndex(track, fx_index, selected_preset - 1)
                reaper.Undo_EndBlock2(get_project(subproject_number), "GJS-X select FX preset", -1)
                if not ok then
                    reaper.ShowConsoleMsg("Preset kon niet worden ingesteld.\n")
                end
            end
            if close_callback then close_callback() end
            api.redraw()
        end
    })

    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            if close_callback then close_callback() end
            api.redraw()
        end
    })
end

return M
