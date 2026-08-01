-- ============================================================
-- Main screen content for screen 0
-- Version 18 - restore exact palette colors after matrix draw
-- ============================================================


local resize_api = include("gjs - x - resize.lua")
local clear_api = include("gjs - x - clear.lua")

return function(api, navigation)
    local C = api.COLOR

    if api.set_screen0_main_active then
        api.set_screen0_main_active(true)
    end

    if api.set_navigation then
        api.set_navigation(
            nil,
            navigation and navigation.open_edit or nil
        )
    end

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

        -- Only screen 0 may change the active REAPER track.
        if type(api.pattern.activate_track) == "function" then
            api.pattern.activate_track(track)
        end

        api.pattern.select(track, region)
    end

    local current_page = 1
    if api.get_page then
        current_page = api.get_page()
    end

    local function get_resize_bars(pad)
        if pad.row == 8 then
            return pad.col
        end

        return pad.col + 8
    end

    local function run_resize(pad)
        local bars = get_resize_bars(pad)
        local track, region =
            get_selected_track_and_region()

        if current_page == 2 then
            resize_api.resize_all_regions_all_projects(
                bars
            )
        elseif current_page == 3 then
            resize_api.resize_selected_region_all_projects(
                region,
                bars
            )
        elseif current_page == 4 then
            resize_api.resize_selected_region_selected_project(
                track,
                region,
                bars
            )
        end
    end

    local function run_clear()
        local track, region =
            get_selected_track_and_region()

        if current_page == 2 then
            clear_api.clear_all_regions_all_projects()
        elseif current_page == 3 then
            clear_api.clear_selected_region_all_projects(
                region
            )
        elseif current_page == 4 then
            clear_api.clear_selected_region_selected_project(
                track,
                region
            )
        end
    end

    local play_state = reaper.GetPlayState()
    local transport_active =
        (play_state & 1) == 1 or
        (play_state & 4) == 4

    if current_page == 1 or transport_active then
        api.drawblock(
            8, 1,
            7, 8,
            C.GREY,
            api.MODE_NONE
        )
    else
        api.drawblock(
            8, 1,
            7, 8,
            C.PURPLE,
            api.MODE_RADIO,
            {
                group =
                    "resize_bars_page_"
                    .. tostring(current_page),

                selected_row = 8,
                selected_col = 1,
                active_color = api.SELECT_COLOR,

                on_press = function(pad)
                    run_resize(pad)

                    -- Redraw after the resize operation so the selected
                    -- bar length remains visibly active.
                    api.redraw()
                end
            }
        )
    end

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
		C.DARK_GREEN,
		api.MODE_HIGHLIGHT,
		{
			active_color = api.SELECT_COLOR,

			on_press = function()
				if api.transport then
					api.transport.play()
				end
			end,

		on_release = function()
			if api.transport then
				api.transport.invalidate_transport_leds()
				api.transport.update(api)
			end

			return true
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
				api.transport.invalidate_transport_leds()
				api.transport.update(api)
			end
			return true
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
            end,

            on_release = function()
                -- Let REAPER process the stop command first, then redraw
                -- screen 0 so pages 2-4 immediately return to purple.
                reaper.defer(function()
                    api.redraw()
                end)

                return true
            end
        }
    )

    -- Only the physical page buttons are reordered for now.
    -- Button 1 opens internal page 4; button 4 opens internal page 1.
    -- Pages 2 and 3 remain unchanged.
    local page_button_to_internal = {
        [5] = 4,
        [6] = 2,
        [7] = 3,
        [8] = 1
    }

    local internal_to_page_button = {
        [1] = 8,
        [2] = 6,
        [3] = 7,
        [4] = 5
    }

    -- core.set_page() still stores the old page-to-pad mapping.
    -- Override the saved radio note with the new physical button position
    -- before drawing, otherwise drawstrip highlights the old button.
    local page_screen_state = api.get_screen_state(0)
    local selected_page_col =
        internal_to_page_button[current_page] or 5

    page_screen_state.radio["page_selector"] =
        40 + selected_page_col

    api.drawstrip(
        4, 5, 8,
        C.BLUE,
        api.MODE_RADIO,
        {
            group = "page_selector",
            selected_col = selected_page_col,
            active_color = api.SELECT_COLOR,

            on_press = function(pad)
                if api.set_page then
                    local internal_page =
                        page_button_to_internal[pad.col]

                    if internal_page then
                        api.set_page(internal_page)
                    end

                    -- Redraw on the next defer cycle. An immediate redraw here
                    -- can still be overwritten by the current page-button MIDI
                    -- event.
                    reaper.defer(function()
                        api.redraw()
                    end)
                end
            end
        }
    )

	if current_page == 1 then
		-- Bestaande tap tempo: niets wijzigen.
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

	elseif current_page == 2 then
		-- Metronoomstatus uit REAPER ophalen.
		local metronome_on =
			reaper.GetToggleCommandState(40364) == 1

		local screen_state = api.get_screen_state(0)
		screen_state.toggle[35] = metronome_on

		api.drawpad(
			3,
			5,
			C.PURPLE,
			api.MODE_TOGGLE,
			{
				active_color = api.SELECT_COLOR,

				on_press = function()
					reaper.Main_OnCommand(40364, 0)
				end
			}
		)

	else
		-- Keep the tap-tempo/metronome position visible on pages 3 and 4.
		api.drawpad(
			3,
			5,
			C.PURPLE,
			api.MODE_NONE
		)
	end

	local function undo_active_track()
		local proj = api.GetActiveTrackProject()

		if proj then
			reaper.Undo_DoUndo2(proj)
		end
	end
    -- Undo
    api.drawpad(
        3,
        6,
        C.LIGHT_PURPLE,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,
            on_press = function()
                undo_active_track()
            end
        }
    )

	local function redo_active_track()
		local proj = api.GetActiveTrackProject()

		if proj then
			reaper.Undo_DoRedo2(proj)
		end
	end
    -- Redo
    api.drawpad(
        3,
        7,
        C.LIGHT_PURPLE,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,
            on_press = function()
                redo_active_track()
            end
        }
    )

    -- Pad 38 keeps the original LIGHT_BLUE -> SELECT_COLOR highlight.
    -- Only the page-aware clear callback is new.
    api.drawpad(
        3,
        8,
        C.LIGHT_BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if current_page >= 2
                and current_page <= 4 then
                    run_clear()
                end
            end
        }
    )



    -- Record-arm buttons for the first eight direct children of folder
    -- "tracks". Load REAPER's current state before drawing each toggle.
    -- Project 0 is now the central mixer.
    -- The mute row controls its first eight tracks directly.
    local arm_tracks = {}

    for index = 0, 7 do
        arm_tracks[#arm_tracks + 1] = reaper.GetTrack(0, index)
    end
    local screen_state = api.get_screen_state(0)

    for col = 1, 8 do
        local track = arm_tracks[col]
        if track == nil then goto continue end
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
        ::continue::
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

    if current_page == 1 or transport_active then
        api.draw_loop_overview()
    end
end
