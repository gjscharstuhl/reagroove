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

local SCENE_QUEUE_LOOKAHEAD = 1.0
local lib = dofile(
    reaper.GetResourcePath() ..
    "/Scripts/gjs/gjs - lib.lua"
)

local command_cache = {}

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

    -- Alleen de selectie van deze track vervangen.
    -- Andere tracks blijven onafhankelijk gevolgd worden.
    selections[track_number] = {
        region = region_number,
        visual_state = nil
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

    lib.SelectTrackInFolder(
        "tracks",
        track_number
    )

    lib.arm(
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
    
    reaper.ShowConsoleMsg(
    string.format(
        "QUEUE track=%d region=%d\n",
        track_number,
        region_number
    )
)

	-- SWS-regioncommando's werken op de actieve projecttab.
	--reaper.SelectProjectInstance(project)

	reaper.Main_OnCommandEx(
		command,
		0,
		project
	)

    reaper.UpdateArrange()

    reaper.ShowConsoleMsg(
        string.format(
            "Pattern geselecteerd: track=%d, region=%d\n",
            track_number,
            region_number
        )
    )

    return true
end

function Pattern.queue_scene(patternlist)
    if type(patternlist) ~= "table" then
        return false
    end

    queued_scene_patterns =
        copy_patternlist(patternlist)

    reaper.ShowConsoleMsg(
        "Scene patterns queued.\n"
    )

    return true
end

function Pattern.queue_scene(patternlist)
    if type(patternlist) ~= "table" then
        return false
    end

    queued_scene_patterns =
        copy_patternlist(patternlist)

    reaper.ShowConsoleMsg(
        "Scene patterns queued.\n"
    )

    return true
end

local function activate_queued_scene(api)
    if not queued_scene_patterns then
        return false
    end

    local patternlist = queued_scene_patterns
    queued_scene_patterns = nil

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

    if api.redraw then
        api.redraw()
    end

    reaper.ShowConsoleMsg(
        "Queued scene activated.\n"
    )

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

local function current_region_number(project)
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
            new_state = "active"
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

    -- Redraw once through the framebuffer whenever queued/active changes.
    -- This keeps LIGHT_BLUE identical to the initial matrix colour and also
    -- lets screen 0 show the pending state without separate palette updates.
    if changed
    and api.redraw
    and api.get_current_screen
    and (api.get_current_screen() == 0 or api.get_current_screen() == 1) then
        api.redraw()
    end
end

return Pattern
