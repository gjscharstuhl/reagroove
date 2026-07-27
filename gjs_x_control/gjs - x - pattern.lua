-- gjs - x - pattern.lua

local Pattern = {}

-- Eén actieve/queued pattern per track/projecttab.
-- Voorbeeld:
-- selections[3] = { region = 5, visual_state = "queued" }
local selections = {}

-- Beperk de statuscontrole tot 20 keer per seconde.
local UPDATE_INTERVAL = 0.05
local last_update_time = 0

local queued_scene_patterns = nil
local queued_scene_callback = nil
local queued_scene_active_track = nil

local SCENE_QUEUE_LOOKAHEAD = 1.0

local function select_track_in_folder(folder_name, track_number)
    track_number = tonumber(track_number)

    if not folder_name or not track_number then
        return nil
    end

    local folder_track
    local folder_index

    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)

        if name == folder_name then
            folder_track = track
            folder_index = i
            break
        end
    end

    if not folder_track then
        return nil
    end

    local folder_depth = reaper.GetTrackDepth(folder_track)
    local found = 0
    local target_track

    for i = folder_index + 1, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(track)

        if depth <= folder_depth then
            break
        end

        reaper.SetTrackSelected(track, false)

        if depth == folder_depth + 1 then
            found = found + 1

            if found == track_number then
                target_track = track
            end
        end
    end

    if target_track then
        reaper.SetTrackSelected(target_track, true)
    end

    return target_track
end

local command_cache = {}
local current_region_number

local function arm_subproject_track(track_number, page)

    --------------------------------------------------------
    -- Alle subprojecten resetten
    --------------------------------------------------------

    for subproject_index = 1, 8 do
        local subproject =
            reaper.EnumProjects(subproject_index)

        if subproject then
            for track_index = 0,
                reaper.CountTracks(subproject) - 1 do

                local track =
                    reaper.GetTrack(
                        subproject,
                        track_index
                    )

                if track then
                    reaper.SetMediaTrackInfo_Value(
                        track,
                        "I_RECARM",
                        0
                    )

                    reaper.SetMediaTrackInfo_Value(
                        track,
                        "I_AUTOMODE",
                        0
                    )
                end
            end
        end
    end

    --------------------------------------------------------
    -- Actieve subprojecttrack
    --------------------------------------------------------

    local project =
        reaper.EnumProjects(track_number)

    if not project then
        return false
    end

    local track =
        reaper.GetTrack(project, 0)

    if not track then
        return false
    end

    --------------------------------------------------------
    -- Page-filter
    --------------------------------------------------------

    if page >= 1 then
        reaper.SetMediaTrackInfo_Value(
            track,
            "I_RECARM",
            1
        )
    end

    -- Latch wordt uitsluitend door transport.lua geregeld.
    reaper.SetMediaTrackInfo_Value(
        track,
        "I_AUTOMODE",
        0
    )

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    return true
end


function Pattern.activate_track(track_number)
    track_number = tonumber(track_number)

    if not track_number or track_number < 1 or track_number > 8 then
        return false
    end

    track_number = math.floor(track_number)

    reaper.SetExtState(
        "GJS_X",
        "ActiveTrack",
        tostring(track_number),
        false
    )

    local page = tonumber(
        reaper.GetExtState("GJS_X", "Page")
    ) or 1

    select_track_in_folder("tracks", track_number)
    return arm_subproject_track(track_number, page)
end

local function find_region(project, region_number)
    local _, markers, regions =
        reaper.CountProjectMarkers(project)

    for index = 0, markers + regions - 1 do
        local _, is_region, start_pos, end_pos,
              _, number =
            reaper.EnumProjectMarkers2(
                project,
                index
            )

        if is_region and number == region_number then
            return start_pos, end_pos
        end
    end

    return nil, nil
end

local function copy_patternlist(patternlist)
    local copy = {}

    for track = 1, 8 do
        copy[track] = patternlist[track]
    end

    return copy
end

local function get_longest_current_pattern()
    local longest = nil

    for track, selection in pairs(selections) do
        local project = reaper.EnumProjects(track)

        if project
        and selection
        and selection.region then

            local start_pos, end_pos =
                find_region(
                    project,
                    selection.region
                )

            if start_pos and end_pos then
                local length = end_pos - start_pos

                if not longest
                or length > longest.length then
                    longest = {
                        track = track,
                        project = project,
                        region = selection.region,
                        start_pos = start_pos,
                        end_pos = end_pos,
                        length = length
                    }
                end
            end
        end
    end

    return longest
end

local function get_region_command(region_number)
    if command_cache[region_number] then
        return command_cache[region_number]
    end

    local wanted = string.format(
        "Regions: Go to region %02d after current region finishes playing",
        region_number
    )

    for command = 0, 70000 do
        local text =
            reaper.kbd_getTextFromCmd(
                command,
                0
            )

        if text and text:find(wanted, 1, true) then
            command_cache[region_number] = command
            return command
        end
    end

    return nil
end

function Pattern.select(track_number, region_number)
    if track_number < 1 or track_number > 8 then
        return false
    end

    if region_number < 1 or region_number > 8 then
        return false
    end

    local project =
        reaper.EnumProjects(track_number)

    if not project then
        reaper.ShowConsoleMsg(
            "Pattern: projecttab " ..
            track_number ..
            " niet gevonden.\n"
        )
        return false
    end

    local start_pos, end_pos =
        find_region(
            project,
            region_number
        )

    if not start_pos then
        reaper.ShowConsoleMsg(
            "Pattern: region " ..
            region_number ..
            " niet gevonden in projecttab " ..
            track_number ..
            ".\n"
        )
        return false
    end

    local command =
        get_region_command(region_number)

    if not command then
        reaper.ShowConsoleMsg(
            "Pattern: queue-commando voor region " ..
            region_number ..
            " niet gevonden.\n"
        )
        return false
    end

    local play_state =
        reaper.GetPlayStateEx(project)

    local play_pos =
        reaper.GetPlayPositionEx(project)

    local current_region =
        current_region_number
        and current_region_number(project)
        or nil

    -- Wanneer dezelfde region opnieuw wordt gequeued, is die region
    -- op dit moment nog actief. Zonder extra status zou de playlist
    -- deze stap onmiddellijk als aangekomen beschouwen.
    --
    -- Daarom wachten we bij een herhaling tot de playpositie werkelijk
    -- over de regiongrens is gewrapt.
    local wait_for_wrap =
        (play_state & 1) ~= 0
        and current_region == region_number

    selections[track_number] = {
        region = region_number,
        visual_state = wait_for_wrap
            and "queued"
            or nil,
        wait_for_wrap = wait_for_wrap,
        queue_play_pos = play_pos
    }

    last_update_time = 0

    reaper.SetExtState(
        "GJS_X",
        "ActiveTrack",
        tostring(track_number),
        false
    )

    reaper.SetExtState(
        "GJS_X",
        "TargetRegion",
        tostring(region_number),
        false
    )

    local page =
        tonumber(
            reaper.GetExtState(
                "GJS_X",
                "Page"
            )
        ) or 1

    select_track_in_folder(
        "tracks",
        track_number
    )

    arm_subproject_track(
        track_number,
        page
    )

    reaper.GetSet_LoopTimeRange2(
        project,
        true,
        false,
        start_pos,
        end_pos,
        false
    )

    reaper.Main_OnCommandEx(
        command,
        0,
        project
    )

    reaper.UpdateArrange()

    return true
end

function Pattern.queue_scene(patternlist, active_track, activated_callback)
    if type(patternlist) ~= "table" then
        return false
    end

    queued_scene_patterns =
        copy_patternlist(patternlist)

    queued_scene_active_track = tonumber(active_track)
    queued_scene_callback = activated_callback

    return true
end

local function activate_queued_scene(api)
    if not queued_scene_patterns then
        return false
    end

    local patternlist = queued_scene_patterns
    local active_track = queued_scene_active_track
    local callback = queued_scene_callback

    queued_scene_patterns = nil
    queued_scene_active_track = nil
    queued_scene_callback = nil

    for track = 1, 8 do
        local region = patternlist[track]

        if region then
            api.set_track_and_region(
                track,
                region
            )

            Pattern.select(
                track,
                region
            )
        end
    end

    if active_track then
        Pattern.activate_track(active_track)
    end

    if callback then
        callback()
    end

    if api.redraw then
        api.redraw()
    end

    return true
end

local function update_queued_scene(api)
    if not queued_scene_patterns then
        return
    end

    local longest =
        get_longest_current_pattern()

    if not longest then
        activate_queued_scene(api)
        return
    end

    local play_state =
        reaper.GetPlayStateEx(
            longest.project
        )

    if (play_state & 1) == 0 then
        activate_queued_scene(api)
        return
    end

    local play_pos =
        reaper.GetPlayPositionEx(
            longest.project
        )

    local remaining =
        longest.end_pos - play_pos

    if remaining >= 0
    and remaining <= SCENE_QUEUE_LOOKAHEAD then
        activate_queued_scene(api)
    end
end

current_region_number = function(project)
    local pos = reaper.GetPlayPositionEx(project)

    local _, num_markers, num_regions =
        reaper.CountProjectMarkers(project)

    for i = 0, num_markers + num_regions - 1 do
        local _, is_region, start_pos, end_pos,
              _, region_number =
            reaper.EnumProjectMarkers2(project, i)

        if is_region
        and pos >= start_pos
        and pos < end_pos then
            return region_number
        end
    end

    return nil
end

local function update_selection(track_number, selection)
    local project =
        reaper.EnumProjects(track_number)

    if not project then
        return false
    end

    local play_state =
        reaper.GetPlayStateEx(project)

    local new_state

    if (play_state & 1) == 0 then
        new_state = "stopped"
    else
        local current_region =
            current_region_number(project)

        if current_region == selection.region then
            if selection.wait_for_wrap then
                local play_pos =
                    reaper.GetPlayPositionEx(project)

                -- Dezelfde region is opnieuw gequeued. Hij wordt pas actief
                -- nadat de transportpositie van het einde terug naar het
                -- begin van de region is gesprongen.
                if play_pos < selection.queue_play_pos then
                    selection.wait_for_wrap = false
                    new_state = "active"
                else
                    new_state = "queued"
                end
            else
                new_state = "active"
            end
        else
            new_state = "queued"
        end
    end

    if selection.visual_state == new_state then
        return false
    end

    selection.visual_state = new_state
    return true
end

function Pattern.get_visual_state(track_number, region_number)
    local selection = selections[track_number]

    if not selection or selection.region ~= region_number then
        return nil
    end

    return selection.visual_state
end

function Pattern.update(api)
    update_queued_scene(api)

    if next(selections) == nil then
        return
    end

    local now = reaper.time_precise()

    if now - last_update_time < UPDATE_INTERVAL then
        return
    end

    last_update_time = now

    local changed = false

    for track_number, selection in pairs(selections) do
        if update_selection(track_number, selection) then
            changed = true
        end
    end

    if changed
    and api.redraw
    and api.get_current_screen
    and (
        api.get_current_screen() == 0
        or api.get_current_screen() == 1
        or api.get_current_screen() == 4
    ) then
        api.redraw()
    end
end

return Pattern
