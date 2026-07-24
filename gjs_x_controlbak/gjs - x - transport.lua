-- ============================================================
-- gjs - x - transport.lua
--
-- Transport- en recordlogica voor de actieve GJS_X-projecttab
-- ============================================================

local Transport = {}

local CMD_PLAY   = 1007
local CMD_RECORD = 1013
local CMD_STOP   = 1016



local state = {
    watching_record = false,
    phase = 0,
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

    local project = reaper.EnumProjects(active_track)

    if not project then
        return nil, nil
    end

    return project, active_track
end


local function get_phase()
    return tonumber(
        reaper.GetExtState(
            "GJS_X",
            "Page"
        )
    ) or 0
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


local function get_armed_track(project)
    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)

        if reaper.GetMediaTrackInfo_Value(
            track,
            "I_RECARM"
        ) == 1 then

            return track
        end
    end

    return nil
end


local function clean_time_selection_keep_last_complete(project)
    local track = get_armed_track(project)

    if not track then
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
            overlapping_items[
                #overlapping_items + 1
            ] = item

            if item_covers_time_selection(
                item,
                start_time,
                end_time
            ) then
                complete_items[
                    #complete_items + 1
                ] = item
            end
        end
    end

    if #complete_items == 0 then
        return
    end

    local keep_item =
        complete_items[#complete_items]

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    for _, item in ipairs(overlapping_items) do
        if item ~= keep_item then
            reaper.DeleteTrackMediaItem(
                track,
                item
            )
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    reaper.Undo_EndBlock(
        "Keep last complete item and remove incomplete takes",
        -1
    )
end


-- ============================================================
-- FX-record automation
-- ============================================================

local function reset_fx_automation()
    if not state.project then
        return
    end

    local track =
        reaper.GetTrack(state.project, 0)

    if track then
        reaper.SetMediaTrackInfo_Value(
            track,
            "I_AUTOMODE",
            0
        )
    end
end


local function enable_fx_latch()
    if not state.project then
        return
    end

    local track =
        reaper.GetTrack(state.project, 0)

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
    local project = get_active_project()
    if not project then
        return 0
    end
    return reaper.GetPlayStateEx(project)
end

local function desired_play_led_color(api)
    local play_state = get_transport_play_state()

    if (play_state & 1) == 1
    or (play_state & 4) == 4 then
        return api.COLOR.GREEN
    end

    return api.COLOR.DARK_GREEN or 17
end

local function desired_record_led_color(api)
    if not state.watching_record then
        return api.COLOR.YELLOW
    end

    if not state.reached_time_selection then
        return api.COLOR.ORANGE
    end

    return api.COLOR.RED
end

local function update_transport_leds(api)
    if not api or not api.get_current_screen then
        return
    end

    if api.get_current_screen() ~= 0 then
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
   -- local project =
    --    get_active_project()

   -- if not project then
    --    return
   --`	 end

    reaper.Main_OnCommandEx(
        CMD_STOP,
        0,
        0
    )

    state.watching_record = false
    state.reached_time_selection = false
    state.pending_record = false
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

    local phase = get_phase()
    local play_state =
        reaper.GetPlayStateEx(project)

    -- Tweede druk tijdens normale opname:
    -- opname beëindigen.
    reaper.ShowConsoleMsg(
    "Phase = " .. tostring(get_phase()) .. "\n"
	)
    if phase ~= 2 and (play_state & 4) == 4 then
        reaper.Main_OnCommandEx(
            CMD_RECORD,
            0,
            project
        )

        state.watching_record = false
        state.pending_record = false
        state.last_record_led_color = nil
        return
    end

    state.project = project
    state.active_track = active_track
    state.phase = phase

    state.reached_time_selection = false
    state.last_record_led_color = nil
    state.watching_record = true

    if phase == 2 then
        reaper.SetExtState(
            "GJS_X",
            "FxRec",
            "1",
            true
        )

        -- Phase 2 start geen normale opname.
        -- De watcher schakelt latch in bij de region.
    else
        reaper.SetExtState(
            "GJS_X",
            "FxRec",
            "0",
            true
        )

        -- Als er al wordt afgespeeld buiten de gekozen region,
        -- laat de bestaande region-queue intact en start opname
        -- pas zodra de time-selection is bereikt.
        if (play_state & 1) == 1
        and not inside_time_selection(project) then
            state.pending_record = true
        else
            state.pending_record = false

            reaper.Main_OnCommandEx(
                CMD_RECORD,
                0,
                project
            )
        end
    end
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

    if state.phase == 2 then
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
