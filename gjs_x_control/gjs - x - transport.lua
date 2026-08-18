-- ============================================================
-- gjs - x - transport.lua
local subproject_track = include("gjs - x - subproject_track.lua")
--
-- Transport- en recordlogica voor de actieve GJS_X-projecttab
-- ============================================================

local Transport = {}

local CMD_PLAY   = 1007
local CMD_RECORD = 1013
local CMD_STOP   = 1016



local state = {
    watching_record = false,
    record_mode = "normal",
    active_track = nil,
    project = nil,
    reached_time_selection = false,
    pending_record = false,
    pending_cleanup_project = nil,
    pending_cleanup_time = nil,
    last_play_led_color = nil,
    last_record_led_color = nil
}


-- ============================================================
-- Projectselectie
-- ============================================================

local function get_active_project()
    local active_track =
        tonumber(
            reaper.GetExtState(
                "GJS_X",
                "ActiveTrack"
            )
        )

    if not active_track then
        return nil, nil
    end

    -- Natural tab flow:
    -- ActiveTrack 1 -> REAPER project 0
    -- ...
    -- ActiveTrack 8 -> REAPER project 7
    local project_index = active_track - 1
    local project = reaper.EnumProjects(project_index)

    if not project then
        return nil, nil
    end

    return project, active_track
end


local function get_record_mode()
    local mode =
        reaper.GetExtState("GJS_X", "RecordMode")

    if mode == "latch" then
        return "latch"
    end

    return "normal"
end


-- ============================================================
-- Time-selection
-- ============================================================

local function inside_time_selection(project)
    if not project then
        return false
    end

    local position =
        reaper.GetPlayPositionEx(project)

    local start_time, end_time =
        reaper.GetSet_LoopTimeRange2(
            project,
            false,
            false,
            0,
            0,
            false
        )

    if end_time <= start_time then
        return false
    end

    return position >= start_time
       and position < end_time
end


-- ============================================================
-- Opname-items opschonen
-- ============================================================

local function item_overlaps_time_selection(
    item,
    start_time,
    end_time
)
    local epsilon = 0.000001

    local position =
        reaper.GetMediaItemInfo_Value(
            item,
            "D_POSITION"
        )

    local length =
        reaper.GetMediaItemInfo_Value(
            item,
            "D_LENGTH"
        )

    local item_end = position + length

    return item_end > start_time + epsilon
       and position < end_time - epsilon
end


local function item_covers_time_selection(
    item,
    start_time,
    end_time
)
    local epsilon = 0.000001

    local position =
        reaper.GetMediaItemInfo_Value(
            item,
            "D_POSITION"
        )

    local length =
        reaper.GetMediaItemInfo_Value(
            item,
            "D_LENGTH"
        )

    local item_end = position + length

    return position <= start_time + epsilon
       and item_end >= end_time - epsilon
end


local function get_armed_tracks(project)
    local tracks = {}

    if not project then
        return tracks
    end

    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)

        if track
        and reaper.GetMediaTrackInfo_Value(
            track,
            "I_RECARM"
        ) > 0.5 then
            tracks[#tracks + 1] = track
        end
    end

    return tracks
end



local function project_directory(project)
    if type(reaper.GetProjectPathEx) == "function" then
        local ok, path = reaper.GetProjectPathEx(project, "")
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

local function source_still_used(project, path)
    for i = 0, reaper.CountMediaItems(project) - 1 do
        if item_wav_path(reaper.GetMediaItem(project, i)) == path then return true end
    end
    return false
end

local function remove_unused_project_wavs(project, candidates)
    local directory = project_directory(project)
    if not directory then return end
    for path in pairs(candidates or {}) do
        if path_is_inside(path, directory) and not source_still_used(project, path) then
            os.remove(path)
        end
    end
end

local function clean_track_keep_last_complete(
    track,
    start_time,
    end_time,
    wav_candidates
)
    if not track then
        return false
    end

    local overlapping_items = {}
    local complete_items = {}

    for index = 0,
        reaper.CountTrackMediaItems(track) - 1 do

        local item =
            reaper.GetTrackMediaItem(
                track,
                index
            )

        if item_overlaps_time_selection(
            item,
            start_time,
            end_time
        ) then
            overlapping_items[#overlapping_items + 1] = item

            if item_covers_time_selection(
                item,
                start_time,
                end_time
            ) then
                complete_items[#complete_items + 1] = item
            end
        end
    end

    if #complete_items == 0 then
        return false
    end

    local keep_item = complete_items[#complete_items]
    local changed = false

    for _, item in ipairs(overlapping_items) do
        if item ~= keep_item then
            local wav_path = item_wav_path(item)
            if wav_path and wav_candidates then wav_candidates[wav_path] = true end
            reaper.DeleteTrackMediaItem(track, item)
            changed = true
        end
    end

    return changed
end


local function set_items_full_height_in_time_selection(
    project,
    start_time,
    end_time
)
    if not project then
        return
    end

    for index = 0, reaper.CountMediaItems(project) - 1 do
        local item = reaper.GetMediaItem(project, index)

        if item_overlaps_time_selection(
            item,
            start_time,
            end_time
        ) then
            reaper.SetMediaItemInfo_Value(
                item,
                "F_FREEMODE_Y",
                0.0
            )

            reaper.SetMediaItemInfo_Value(
                item,
                "F_FREEMODE_H",
                1.0
            )
        end
    end
end


local function clean_time_selection_keep_last_complete(project)
    local armed_tracks = get_armed_tracks(project)

    if #armed_tracks == 0 then
        return
    end

    local start_time, end_time =
        reaper.GetSet_LoopTimeRange2(
            project,
            false,
            false,
            0,
            0,
            false
        )

    if start_time == end_time then
        return
    end

    reaper.Undo_BeginBlock2(project)
    reaper.PreventUIRefresh(1)

    local changed = false
    local wav_candidates = {}

    for _, track in ipairs(armed_tracks) do
        if clean_track_keep_last_complete(
            track,
            start_time,
            end_time,
            wav_candidates
        ) then
            changed = true
        end
    end

    -- Physical cleanup: delete WAV files for removed takes when they are
    -- inside this project directory and no remaining item references them.
    remove_unused_project_wavs(project, wav_candidates)

    -- Make items easy to see and select when
    -- Free Item Positioning is enabled.
    set_items_full_height_in_time_selection(
        project,
        start_time,
        end_time
    )

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    reaper.Undo_EndBlock2(
        project,
        changed
            and "Keep last complete takes on armed tracks"
            or "Keep last complete takes - nothing found",
        -1
    )
end


-- ============================================================
-- FX-record automation
-- ============================================================

local function get_active_track_project()
    local active_track =
        tonumber(
            reaper.GetExtState(
                "GJS_MULTI",
                "ActiveTrack"
            )
        ) or 1

    return reaper.EnumProjects(active_track - 1, "")
end

local function reset_fx_automation()
    local proj = get_active_track_project()
    if not proj then
        return
    end

    local track = subproject_track.get_selected_track(proj)
    if not track then
        return
    end

    reaper.SetMediaTrackInfo_Value(
        track,
        "I_AUTOMODE",
        0
    )
end


local function enable_fx_latch()
    if not state.project then
        return
    end

    local track =
        subproject_track.get_selected_track(state.project)

    if track then
        reaper.SetMediaTrackInfo_Value(
            track,
            "I_AUTOMODE",
            4
        )
    end
end


-- ============================================================
-- Transport-LEDs
-- ============================================================

local function get_transport_play_state()
    return reaper.GetPlayState()
end

local function desired_play_led_color(api)
    local play_state = get_transport_play_state()



    if (play_state & 1) == 1
    or (play_state & 4) == 4 then
        return api.COLOR.GREEN
    end

    return api.COLOR.DARK_GREEN
end

local function any_project_is_recording()
    local index = 0

    while true do
        local project = reaper.EnumProjects(index, "")
        if not project then
            break
        end

        local play_state = reaper.GetPlayStateEx(project)
        if (play_state & 4) == 4 then
            return true
        end

        index = index + 1
    end

    return false
end

local function desired_record_led_color(api)
    -- In de multi-tab-opzet kan de opname lopen in een andere
    -- projecttab dan de actieve controller-tab. Controleer daarom
    -- alle geopende projecten in plaats van alleen state.project.
    if any_project_is_recording() then
        return api.COLOR.RED
    end

    if not state.watching_record then
        return api.COLOR.YELLOW
    end

    if not state.reached_time_selection then
        return api.COLOR.ORANGE
    end

    -- FX-recording gebruikt geen normale REAPER-recordstatus.
    return api.COLOR.RED
end

local function update_transport_leds(api)
    if not api or not api.get_current_screen then
        return
    end

    -- Main and Edit share core screen 0. Only Main owns the transport LEDs.
    -- A deferred/continuous Transport.update() must therefore also verify the
    -- active screen-0 layout, otherwise pad 41/42 can leak into Edit/pattern.
    if api.get_current_screen() ~= 0
    or reaper.GetExtState("GJS_X", "Screen0Layout") ~= "main" then
        state.last_play_led_color = nil
        state.last_record_led_color = nil
        return
    end

    local play_color = desired_play_led_color(api)
    local record_color = desired_record_led_color(api)

    if play_color ~= state.last_play_led_color then
        api.send_pad_color(4, 1, play_color)
        state.last_play_led_color = play_color
    end

    if record_color ~= state.last_record_led_color then
        api.send_pad_color(4, 2, record_color)
        state.last_record_led_color = record_color
    end
end

function Transport.invalidate_record_led()
    state.last_record_led_color = nil
end

function Transport.invalidate_transport_leds()
    state.last_play_led_color = nil
    state.last_record_led_color = nil
end


function Transport.cancel_record_watch()
    state.watching_record = false
    state.reached_time_selection = false
    state.pending_record = false
    state.record_mode = get_record_mode()
    state.last_record_led_color = nil

    reaper.SetExtState(
        "GJS_X",
        "FxRec",
        "0",
        true
    )

    reset_fx_automation()
end


local function move_cursor_to_current_region_start(project)
    if not project then
        return
    end

    local position = reaper.GetCursorPositionEx(project)

    local _, marker_count, region_count =
        reaper.CountProjectMarkers(project)

    for index = 0, marker_count + region_count - 1 do
        local ok,
              is_region,
              start_pos,
              end_pos =
            reaper.EnumProjectMarkers2(project, index)

        if ok
        and is_region
        and position >= start_pos
        and position < end_pos then
            reaper.SetEditCurPos2(
                project,
                start_pos,
                false,
                false
            )

            return
        end
    end
end


-- ============================================================
-- Bedieningsfuncties
-- ============================================================

function Transport.play()
    local project = get_active_project()

    if not project then
        return
    end

    reaper.SetExtState(
        "GJS_X",
        "FxRec",
        "0",
        true
    )

    local play_state =
        reaper.GetPlayStateEx(project)

    if (play_state & 4) == 4 then
        reaper.Main_OnCommandEx(
            CMD_RECORD,
            0,
            project
        )

        state.watching_record = false
        state.reached_time_selection = false
        state.pending_record = false
        state.last_play_led_color = nil
        state.last_record_led_color = nil

        state.pending_cleanup_project = project
        state.pending_cleanup_time =
            reaper.time_precise() + 0.05

        return
    end

    if play_state == 0 then
        reaper.Main_OnCommandEx(
            CMD_PLAY,
            0,
            0
        )

        state.last_play_led_color = nil
        state.last_record_led_color = nil
    end
end

function Transport.stop()

    -- Stop every open project and return its cursor to the beginning
    -- of the region in which it stopped.
    local project_index = 0

    while true do
        local project =
            reaper.EnumProjects(project_index, "")

        if not project then
            break
        end

        reaper.Main_OnCommandEx(
            CMD_STOP,
            0,
            project
        )

        move_cursor_to_current_region_start(project)

        project_index = project_index + 1
    end

    state.watching_record = false
    state.reached_time_selection = false
    state.pending_record = false

    state.last_play_led_color = nil
    state.last_record_led_color = nil

    reaper.SetExtState(
        "GJS_X",
        "FxRec",
        "0",
        true
    )

    reset_fx_automation()
end


function Transport.record()
    local project, active_track =
        get_active_project()

    if not project then
        return
    end

    local record_mode = get_record_mode()
    local play_state =
        reaper.GetPlayStateEx(project)

    --------------------------------------------------------
    -- Normal mode: second press stops normal recording
    --------------------------------------------------------

    if record_mode == "normal"
    and (play_state & 4) == 4 then

        reaper.Main_OnCommandEx(
            CMD_RECORD,
            0,
            project
        )

        state.watching_record = false
        state.reached_time_selection = false
        state.pending_record = false
        state.last_record_led_color = nil

        return
    end

    --------------------------------------------------------
    -- Store state for Transport.update()
    --------------------------------------------------------

    state.project = project
    state.active_track = active_track
    state.record_mode = record_mode

    state.reached_time_selection = false
    state.pending_record = false
    state.last_record_led_color = nil
    state.watching_record = true

    --------------------------------------------------------
    -- Latch mode: automation recording on every page
    --------------------------------------------------------

    if record_mode == "latch" then
        reaper.SetExtState(
            "GJS_X",
            "FxRec",
            "1",
            true
        )

        -- Do not start normal REAPER recording.
        -- Transport.update() enables latch when the active region starts.
        return
    end

    --------------------------------------------------------
    -- Normal mode: audio/MIDI recording
    --------------------------------------------------------

    reaper.SetExtState(
        "GJS_X",
        "FxRec",
        "0",
        true
    )

    if (play_state & 1) == 1
    and not inside_time_selection(project) then

        state.pending_record = true
        return
    end

    reaper.Main_OnCommandEx(
        CMD_RECORD,
        0,
        project
    )
end


-- ============================================================
-- Update vanuit de centrale mainloop
-- ============================================================

function Transport.update(api)
    local now = reaper.time_precise()

    if state.pending_cleanup_project
       and state.pending_cleanup_time
       and now >= state.pending_cleanup_time then

        clean_time_selection_keep_last_complete(
            state.pending_cleanup_project
        )

        state.pending_cleanup_project = nil
        state.pending_cleanup_time = nil
    end

    if not state.watching_record then
        update_transport_leds(api)
        return
    end

    if not state.project then
        state.watching_record = false
        state.reached_time_selection = false
        update_transport_leds(api)
        return
    end

    state.reached_time_selection =
        inside_time_selection(state.project)

    if state.record_mode == "latch" then
        local fx_record =
            tonumber(
                reaper.GetExtState(
                    "GJS_X",
                    "FxRec"
                )
            ) or 0

        if fx_record ~= 1 then
            state.watching_record = false
            state.reached_time_selection = false
            reset_fx_automation()
            update_transport_leds(api)
            return
        end

        if state.reached_time_selection then
            enable_fx_latch()
        end
    else
        local play_state =
            reaper.GetPlayStateEx(
                state.project
            )

        if state.pending_record then
            -- Playback moet blijven lopen terwijl we wachten op
            -- de reeds gequeuede region.
            if (play_state & 1) ~= 1 then
                state.watching_record = false
                state.reached_time_selection = false
                state.pending_record = false
                update_transport_leds(api)
                return
            end

            if state.reached_time_selection then
                reaper.Main_OnCommandEx(
                    CMD_RECORD,
                    0,
                    state.project
                )

                state.pending_record = false
            end
        elseif (play_state & 4) ~= 4 then
            state.watching_record = false
            state.reached_time_selection = false
            update_transport_leds(api)
            return
        end
    end

    update_transport_leds(api)
end

function Transport.cleanup(api)
    state.watching_record = false
    state.reached_time_selection = false
    state.pending_record = false
    state.last_play_led_color = nil
    state.last_record_led_color = nil

    reset_fx_automation()

    reaper.SetExtState(
        "GJS_X",
        "FxRec",
        "0",
        true
    )

    if api then
        update_transport_leds(api)
    end
end


return Transport
