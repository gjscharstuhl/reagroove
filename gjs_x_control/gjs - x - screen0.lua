-- ============================================================
-- Screen 0: main screen
-- ============================================================

return function(api)
    local C = api.COLOR

    local function normalized_name(name)
        return (name or "")
            :match("^%s*(.-)%s*$")
            :lower()
    end

    local function find_direct_children(folder_name, maximum)
        local wanted = normalized_name(folder_name)
        local folder_index = nil
        local folder_depth = nil

        for index = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local _, name = reaper.GetTrackName(track)

            if normalized_name(name) == wanted
            and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0 then
                folder_index = index
                folder_depth = reaper.GetTrackDepth(track)
                break
            end
        end

        if not folder_index then
            return {}
        end

        local children = {}

        for index = folder_index + 1, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local depth = reaper.GetTrackDepth(track)

            if depth <= folder_depth then
                break
            end

            if depth == folder_depth + 1 then
                children[#children + 1] = track

                if #children >= maximum then
                    break
                end
            end
        end

        return children
    end

    local function tap_and_sync_tempo()
        -- REAPER: Transport: Tap tempo
        reaper.Main_OnCommand(1134, 0)

        local main_proj = reaper.EnumProjects(0, "")
        if not main_proj then
            return
        end

        local tempo = reaper.Master_GetTempo(main_proj)

        reaper.Undo_BeginBlock()

        for index = 1, 9 do
            local project = reaper.EnumProjects(index, "")

            if project then
                reaper.SetTempoTimeSigMarker(
                    project,
                    -1,
                    0,
                    -1,
                    -1,
                    tempo,
                    0,
                    0,
                    false
                )
            end
        end

        reaper.Undo_EndBlock("Sync tempo tabs 2-9 to tab 1", -1)
        reaper.UpdateTimeline()
    end

    local function get_selected_track_and_region()
        local state = api.get_screen_state(0)

        local track_note =
            state.radio["tracks"] or 11

        local region_note =
            state.radio["regions"] or 61

        local track = track_note - 10
        local region = region_note - 60

        return track, region
    end

    local function select_current_pattern()
        if not api.pattern
        or type(api.pattern.select) ~= "function" then
            return
        end

        local track, region =
            get_selected_track_and_region()

        -- Mirror the chosen combination to screen 1 before queueing it.
        if api.set_screen1_track_and_region then
            api.set_screen1_track_and_region(track, region)
        end

        api.pattern.select(track, region)
    end

    api.drawblock(
        8, 1,
        7, 8,
        C.GREY,
        api.MODE_RADIO,
        {
            group = "sequencer_patterns",
            selected_row = 8,
            selected_col = 1,
            active_color = api.SELECT_COLOR
        }
    )

    -- Regions 1 t/m 8
    -- Pending uses the same LIGHT_BLUE everywhere. The normal row is BLUE so
    -- the pending region remains clearly visible without introducing a second
    -- almost-identical shade of light blue.
    local selected_track, selected_region =
        get_selected_track_and_region()

    local region_visual_state = nil
    if api.pattern
    and type(api.pattern.get_visual_state) == "function" then
        region_visual_state =
            api.pattern.get_visual_state(selected_track, selected_region)
    end

    local region_active_color = api.SELECT_COLOR
    if region_visual_state == "queued" then
        region_active_color = C.LIGHT_BLUE
    end

    api.drawstrip(
        6, 1, 8,
        C.BLUE,
        api.MODE_RADIO,
        {
            group = "regions",
            selected_col = 1,
            active_color = region_active_color,

            on_press = function()
                select_current_pattern()
            end
        }
    )

    -- Play
    api.drawpad(
        4,
        1,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if api.transport then
                    api.transport.play()
                end
            end
        }
    )

    -- Record
    api.drawpad(
        4,
        2,
        C.YELLOW,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if api.transport then
                    api.transport.record()
                end
            end,

            on_release = function()
                if api.transport then
                    api.transport.invalidate_record_led()
                end
            end
        }
    )

    -- Stop
    api.drawpad(
        4,
        3,
        C.GREY,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if api.transport then
                    api.transport.stop()
                end
            end
        }
    )

    -- Page 1 t/m 4. The selected page is also stored as a shared variable
    -- so other screens can become page-aware later without changing this UI.
    local current_page = 1
    if api.get_page then
        current_page = api.get_page()
    end

    api.drawstrip(
        4, 5, 8,
        C.BLUE,
        api.MODE_RADIO,
        {
            group = "page_selector",
            selected_col = current_page + 4,
            active_color = api.SELECT_COLOR,

            on_press = function(pad)
                if api.set_page then
                    api.set_page(pad.col - 4)
                end
            end
        }
    )

    -- Tap tempo, then copy tab 1 tempo to tabs 2 through 9.
    api.drawpad(
        3,
        5,
        C.PURPLE,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,
            on_press = tap_and_sync_tempo
        }
    )

    -- Undo
    api.drawpad(
        3,
        6,
        C.LIGHT_PURPLE,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,
            on_press = function()
                reaper.Main_OnCommand(40029, 0)
            end
        }
    )

    -- Redo
    api.drawpad(
        3,
        7,
        C.LIGHT_PURPLE,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,
            on_press = function()
                reaper.Main_OnCommand(40030, 0)
            end
        }
    )

    -- Reserved for a later function.
    api.drawpad(
        3,
        8,
        C.LIGHT_BLUE,
        api.MODE_HIGHLIGHT
    )

    -- Record-arm buttons for the first eight direct children of folder
    -- "tracks". Load REAPER's current state before drawing each toggle.
    local arm_tracks = find_direct_children("tracks", 8)
    local screen_state = api.get_screen_state(0)

    for col = 1, 8 do
        local track = arm_tracks[col]
        local note = 20 + col
		local muted =
			reaper.GetMediaTrackInfo_Value(track, "B_MUTE") > 0.5
            or false

        screen_state.toggle[note] = muted

        api.drawpad(
            2,
            col,
            track and C.DARK_YELLOW or C.GREY,
            api.MODE_TOGGLE,
            {
                active_color = api.SELECT_COLOR,

                on_press = function(pad)
                    if not track then
                        return
                    end
                    
					reaper.SetMediaTrackInfo_Value(
						track,
						"B_MUTE",
						pad.active and 1 or 0
					)

                    reaper.TrackList_AdjustWindows(false)
                    reaper.UpdateArrange()
                end
            }
        )
    end

    -- Tracks 1 t/m 8
    api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "tracks",
            selected_col = 1,
            active_color = api.SELECT_COLOR,

            on_press = function()
                select_current_pattern()
            end
        }
    )

    -- Current-region overview on the top two rows.
    -- This is a visual overlay only; all existing pad callbacks remain intact.
    api.draw_loop_overview()
end
