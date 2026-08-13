-- ============================================================
-- Main screen content for screen 0
-- Version 18 - restore exact palette colors after matrix draw
-- ============================================================


local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""
local sequencer = dofile(script_dir .. "gjs - x - sequencer_engine.lua")
local main_display_generation = 0
local trmanager = include("trackmanager.lua")

return function(api, navigation)
    local C = api.COLOR

    if api.set_screen0_main_active then
        api.set_screen0_main_active(true)
    end

    if api.set_jsfx_loop_overview_active then
        api.set_jsfx_loop_overview_active(true)
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
        -- REAPER's Tap Tempo action works on the currently active
        -- project tab. Use that tab only as the tempo source.
        reaper.Main_OnCommand(1134, 0)

        local source_project = reaper.EnumProjects(-1, "")
        if not source_project then
            return
        end

        local tempo = reaper.Master_GetTempo(source_project)
        if not tempo or tempo <= 0 then
            return
        end

        -- Apply the newly tapped tempo explicitly to every open project,
        -- including visible Tab 1 / project index 0.
        reaper.PreventUIRefresh(1)

        local project_index = 0

        while true do
            local project = reaper.EnumProjects(project_index, "")
            if not project then
                break
            end

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

            project_index = project_index + 1
        end

        reaper.PreventUIRefresh(-1)
        reaper.UpdateTimeline()
        reaper.UpdateArrange()
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


	local function getactivetrack()
		local track =     reaper.GetExtState(
        "GJS_X",
        "ActiveTrack"
        )
       return tonumber(track)
    
	end
		
	local function select_current_pattern()
		local track, region = get_selected_track_and_region()

		if api.set_screen1_track_and_region then
			api.set_screen1_track_and_region(track, region)
		end

		api.pattern.select(track, region)
	end

    local current_page = 1
    if api.get_page then
        current_page = api.get_page()
    end


    local play_state = reaper.GetPlayState()
    local transport_active =
        (play_state & 1) == 1 or
        (play_state & 4) == 4

    -- The sequencer area is always visible.
    -- Resize and Clear now live exclusively on the Edit screen.
    api.drawblock(
        8, 1,
        7, 8,
        C.GREY,
        api.MODE_NONE
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

    -- Four natural page buttons.
    --   col 5 = page 1: master mixer
    --   col 6 = page 2: master sends
    --   col 7 = page 3: FX
    --   col 8 = page 4: selected subproject mixer
    local page_screen_state = api.get_screen_state(0)
    page_screen_state.radio["page_selector"] =
        40 + current_page + 4

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

                    reaper.defer(function()
                        api.redraw()
                    end)
                end
            end
        }
    )

    -- Record-mode toggle moved one row down to pad 38.
    local record_mode =
        reaper.GetExtState("GJS_X", "RecordMode")

    if record_mode ~= "latch" then
        record_mode = "normal"
    end

    api.drawpad(
        3,
        8,
        record_mode == "latch" and C.PURPLE or C.YELLOW,
        api.MODE_HIGHLIGHT,
        {
            active_color =
                record_mode == "latch" and C.PURPLE or C.YELLOW,

            on_press = function()
                local new_mode =
                    record_mode == "latch"
                    and "normal"
                    or "latch"

                reaper.SetExtState(
                    "GJS_X",
                    "RecordMode",
                    new_mode,
                    true
                )

                if api.transport
                and api.transport.cancel_record_watch then
                    api.transport.cancel_record_watch()
                end

                reaper.defer(function()
                    api.redraw()
                end)
            end,

            on_release = function()
                return true
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

            on_press = function(pad)
                --select_current_pattern()
                
                local currenttrack=getactivetrack()
                reaper.ShowConsoleMsg("van pad:"..currenttrack.."\n")
				if currenttrack>1 then trmanager.DisArmAllTracks(currenttrack) end
			
				reaper.SetExtState("GJS_X", "ActiveTrack", tostring(pad.col), true)
				reaper.ShowConsoleMsg("naar pad:"..pad.col.."\n")

                -- When Main switches instrument, show the region that was
                -- last selected for that instrument in Pattern/Screen 1.
                if api.pattern
                and type(api.pattern.get_selected_region) == "function"
                and api.set_main_region then
                    local remembered_region =
                        api.pattern.get_selected_region(pad.col) or 1
                    api.set_main_region(remembered_region)
                end

				if pad.col>1 then trmanager.Armtracks(pad.col) end
				trmanager.show()

                -- The region row was already drawn before this track press.
                -- Redraw Main so the remembered region for the newly selected
                -- instrument becomes visible immediately.
                if api.redraw then
                    api.redraw()
                end
            end
        }
    )

    -- Lua draws only the neutral base. The JSFX owns these sixteen pads
    -- after the complete matrix has been sent.
    api.drawblock(8, 1, 7, 8, C.GREY, api.MODE_NONE)

    main_display_generation = main_display_generation + 1
    local generation = main_display_generation
    local last_signature = nil
    local last_check = 0

    local function refresh_main_display()
        sequencer.update_main_display()
    end

    local function keep_main_display_synced()
        if generation ~= main_display_generation then return end

        if api.get_current_screen
        and api.get_current_screen() ~= 0 then
            sequencer.disable_display(2)
            return
        end

        local now = reaper.time_precise()
        if now - last_check >= 0.05 then
            last_check = now
            local context = sequencer.get_main_display_context
                and sequencer.get_main_display_context()
                or sequencer.get_context()

            local signature = table.concat({
                tostring(context.project),
                tostring(context.region_start or 0),
                tostring(context.region_end or 0),
                tostring(context.region_number or 0),
                tostring(reaper.GetExtState("GJS_X", "ActiveTrack"))
            }, ":")

            if signature ~= last_signature then
                last_signature = signature
                refresh_main_display()
            end
        end
		
        reaper.defer(keep_main_display_synced)

    end

    -- Defer once so the JSFX repaint happens after core sends the full matrix.
    reaper.defer(refresh_main_display)
    reaper.defer(keep_main_display_synced)
end
