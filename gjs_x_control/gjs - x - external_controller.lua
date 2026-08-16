-- ============================================================
-- gjs - x - external_controller.lua
-- External MIDI controller bridge for ReaGroove.
--  1..8  = Screen 2 style faders
--  9..16 = Screen 3 style balance/knob controls
-- Values arrive via GJS_X_BRIDGE gmem from the MIDI-learn JSFX.
-- ============================================================

local M = {}

local GMEM_NAME = "GJS_X_BRIDGE"
local EVENT_SEQ_SLOT = 1900
local EVENT_CONTROL_SLOT = 1901
local EVENT_VALUE_SLOT = 1902

local fx_mapping = include("gjs - x - fx_mapping.lua")
local fx_engine = include("gjs - x - fx_engine.lua")

local GLOBAL_FX_TRACKS = {
    "master",
    "Reverb1",
    "Delay",
    "Chorus",
    "Flanger",
    "Filter",
    "Fuzz",
    "Reverb2",
}

local last_sequence = -1
local latch_page = nil
local latch_active_track = nil
local latched = {}
local previous_hw_value = {}

local function reset_latches(page, active_track)
    latch_page = page
    latch_active_track = active_track
    latched = {}
    previous_hw_value = {}
end

local function clamp(value, lo, hi)
    value = tonumber(value) or 0
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function normalized_name(name)
    return (name or ""):match("^%s*(.-)%s*$"):lower()
end

local function active_track_number()
    local n = tonumber(reaper.GetExtState("GJS_X", "ActiveTrack")) or 1
    return math.max(1, math.min(8, math.floor(n)))
end

local function current_page()
    local n = tonumber(reaper.GetExtState("GJS_X", "Page")) or 1
    return math.max(1, math.min(4, math.floor(n)))
end

local function volume_from_cc(value)
    -- Same range as the Launchpad vertical faders: -60 dB .. +12 dB.
    local normalized = clamp(value, 0, 127) / 127
    local db = -60 + normalized * 72
    return 10 ^ (db / 20)
end

local function pan_from_cc(value)
    return (clamp(value, 0, 127) / 127) * 2 - 1
end

local function norm_from_cc(value)
    return clamp(value, 0, 127) / 127
end

local function find_track_by_name(project, wanted_name)
    local wanted = normalized_name(wanted_name)
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        local _, name = reaper.GetTrackName(track)
        if normalized_name(name) == wanted then
            return track
        end
    end
    return nil
end

local function find_send(source_track, destination_track)
    if not source_track or not destination_track then return nil end
    for send_index = 0, reaper.GetTrackNumSends(source_track, 0) - 1 do
        local destination = reaper.GetTrackSendInfo_Value(
            source_track, 0, send_index, "P_DESTTRACK"
        )
        if destination == destination_track then
            return send_index
        end
    end
    return nil
end

local function main_tracks()
    local project = reaper.EnumProjects(0, "")
    local tracks = {}
    if not project then return project, tracks end
    for index = 0, 7 do
        local track = reaper.GetTrack(project, index)
        if track then tracks[index + 1] = track end
    end
    return project, tracks
end

local function top_level_tracks(project)
    local tracks = {}
    if not project then return tracks end

    local depth = 0
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)
        if track and depth == 0 then
            tracks[#tracks + 1] = track
            if #tracks >= 8 then break end
        end
        if track then
            depth = depth + math.floor(
                reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            )
            if depth < 0 then depth = 0 end
        end
    end
    return tracks
end

local function load_page3_mappings()
    local path = fx_mapping.default_path()
    if not path then return {} end

    local mappings, err = fx_mapping.load(path, active_track_number())
    if not mappings then
        reaper.ShowConsoleMsg(
            "External controller: fx_mapping.ini kon niet worden geladen: "
            .. tostring(err) .. "\n"
        )
        return {}
    end
    return mappings
end

local function cc_from_volume(volume)
    local db
    if not volume or volume <= 0 then
        db = -60
    else
        db = 20 * math.log(volume, 10)
    end
    local normalized = clamp((db + 60) / 72, 0, 1)
    return math.floor(normalized * 127 + 0.5)
end

local function cc_from_pan(pan)
    local normalized = clamp(((tonumber(pan) or 0) + 1) / 2, 0, 1)
    return math.floor(normalized * 127 + 0.5)
end

local function cc_from_normalized(value)
    return math.floor(clamp(value, 0, 1) * 127 + 0.5)
end

local function get_fader_target_cc(index, page)
    if page == 3 then
        local mapping = load_page3_mappings()["F" .. index]
        if mapping then
            local value = fx_engine.get_value(mapping)
            if value ~= nil then return cc_from_normalized(value) end
        end
        return nil
    end

    if page == 4 then
        local project = reaper.EnumProjects(active_track_number() - 1, "")
        local tracks = top_level_tracks(project)
        local track = tracks[index]
        if track then
            return cc_from_volume(
                reaper.GetMediaTrackInfo_Value(track, "D_VOL")
            )
        end
        return nil
    end

    local project, tracks = main_tracks()
    if not project then return nil end

    if page == 1 then
        local track = tracks[index]
        if track then
            return cc_from_volume(
                reaper.GetMediaTrackInfo_Value(track, "D_VOL")
            )
        end
        return nil
    end

    if page == 2 then
        local source_track = tracks[active_track_number()]
        local destination_track =
            find_track_by_name(project, GLOBAL_FX_TRACKS[index])
        if not source_track or not destination_track then return nil end
        local send_index = find_send(source_track, destination_track)
        if send_index == nil then
            return cc_from_volume(0)
        end
        return cc_from_volume(
            reaper.GetTrackSendInfo_Value(
                source_track, 0, send_index, "D_VOL"
            )
        )
    end

    return nil
end

local function get_balance_target_cc(index, page)
    if page == 3 then
        local mapping = load_page3_mappings()["B" .. index]
        if mapping then
            local value = fx_engine.get_value(mapping)
            if value ~= nil then return cc_from_normalized(value) end
        end
        return nil
    end

    if page == 4 then
        local project = reaper.EnumProjects(active_track_number() - 1, "")
        local tracks = top_level_tracks(project)
        local track = tracks[index]
        if track then
            return cc_from_pan(
                reaper.GetMediaTrackInfo_Value(track, "D_PAN")
            )
        end
        return nil
    end

    local _, tracks = main_tracks()
    local track = tracks[index]
    if track then
        return cc_from_pan(
            reaper.GetMediaTrackInfo_Value(track, "D_PAN")
        )
    end
    return nil
end

local function soft_takeover(control, value, target)
    if target == nil then
        previous_hw_value[control] = value
        return false
    end

    if latched[control] then
        previous_hw_value[control] = value
        return true
    end

    local previous = previous_hw_value[control]
    previous_hw_value[control] = value

    -- Allow a small pickup window for 7-bit CC controls.
    if math.abs(value - target) <= 2 then
        latched[control] = true
        return true
    end

    if previous ~= nil then
        local crossed =
            (previous < target and value >= target)
            or (previous > target and value <= target)
        if crossed then
            latched[control] = true
            return true
        end
    end

    return false
end

local function apply_fader(index, value, page)
    if page == 3 then
        local mapping = load_page3_mappings()["F" .. index]
        if mapping then
            fx_engine.set_value(mapping, norm_from_cc(value))
        end
        return
    end

    if page == 4 then
        local project = reaper.EnumProjects(active_track_number() - 1, "")
        local tracks = top_level_tracks(project)
        local track = tracks[index]
        if track then
            reaper.CSurf_OnVolumeChange(
                track, volume_from_cc(value), false
            )
        end
        return
    end

    local project, tracks = main_tracks()
    if not project then return end

    if page == 1 then
        local track = tracks[index]
        if track then
            reaper.CSurf_OnVolumeChange(
                track, volume_from_cc(value), false
            )
        end
        return
    end

    if page == 2 then
        local source_track = tracks[active_track_number()]
        local destination_track =
            find_track_by_name(project, GLOBAL_FX_TRACKS[index])

        if not source_track or not destination_track then return end

        local send_index = find_send(source_track, destination_track)
        if send_index == nil then
            send_index = reaper.CreateTrackSend(
                source_track, destination_track
            )
        end

        if send_index and send_index >= 0 then
            reaper.SetTrackSendInfo_Value(
                source_track,
                0,
                send_index,
                "D_VOL",
                volume_from_cc(value)
            )
        end
    end
end

local function apply_balance(index, value, page)
    if page == 3 then
        local mapping = load_page3_mappings()["B" .. index]
        if mapping then
            fx_engine.set_value(mapping, norm_from_cc(value))
        end
        return
    end

    if page == 4 then
        local project = reaper.EnumProjects(active_track_number() - 1, "")
        local tracks = top_level_tracks(project)
        local track = tracks[index]
        if track then
            reaper.CSurf_OnPanChange(track, pan_from_cc(value), false)
        end
        return
    end

    -- Screen 3 pages 1 and 2 both control the main mixer pans.
    local _, tracks = main_tracks()
    local track = tracks[index]
    if track then
        reaper.CSurf_OnPanChange(track, pan_from_cc(value), false)
    end
end

function M.update()
    reaper.gmem_attach(GMEM_NAME)

    -- GUI feedback for the external-controller JSFX.
    reaper.gmem_write(1903, current_page())
    reaper.gmem_write(1904, active_track_number())

    local sequence = math.floor(tonumber(
        reaper.gmem_read(EVENT_SEQ_SLOT)
    ) or 0)

    if sequence == last_sequence then return end
    last_sequence = sequence

    local control = math.floor(tonumber(
        reaper.gmem_read(EVENT_CONTROL_SLOT)
    ) or 0)
    local value = math.floor(tonumber(
        reaper.gmem_read(EVENT_VALUE_SLOT)
    ) or 0)

    if control < 1 or control > 16 then return end

    local page = current_page()
    local active_track = active_track_number()

    if latch_page ~= page or latch_active_track ~= active_track then
        reset_latches(page, active_track)
    end

    if control <= 8 then
        local target = get_fader_target_cc(control, page)
        if soft_takeover(control, value, target) then
            apply_fader(control, value, page)
        end
    else
        local index = control - 8
        local target = get_balance_target_cc(index, page)
        if soft_takeover(control, value, target) then
            apply_balance(index, value, page)
        end
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

return M
