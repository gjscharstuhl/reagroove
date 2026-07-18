-- gjs - x - pattern.lua

local Pattern = {}

-- Eén actieve/queued pattern per track/projecttab.
-- Voorbeeld:
-- selections[3] = { region = 5, visual_state = "queued" }
local selections = {}

-- Beperk de statuscontrole tot 20 keer per seconde.
local UPDATE_INTERVAL = 0.05
local last_update_time = 0

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
        "GJS_MULTI",
        "ActiveTrack",
        tostring(track_number),
        false
    )

    reaper.SetExtState(
        "GJS_MULTI",
        "TargetRegion",
        tostring(region_number),
        false
    )

    local page =
        tonumber(
            reaper.GetExtState(
                "GJS_MULTI",
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

local function update_selection(api, track_number, selection)
    local project =
        reaper.EnumProjects(track_number)

    if not project then
        return
    end

    local play_state =
        reaper.GetPlayStateEx(project)

    local row = 9 - track_number
    local col = selection.region

    if (play_state & 1) == 0 then
        selection.visual_state = "stopped"
        return
    end

    local current_region =
        current_region_number(project)

    if current_region == selection.region then
        if selection.visual_state ~= "active" then
            selection.visual_state = "active"

            api.send_pad_color(
                row,
                col,
                api.COLOR.WHITE
            )
        end

        return
    end

    if selection.visual_state ~= "queued" then
        selection.visual_state = "queued"

        api.send_pad_color(
            row,
            col,
            api.COLOR.LIGHT_BLUE
        )
    end
end

function Pattern.update(api)
    if next(selections) == nil then
        return
    end

    -- Patternkleuren horen alleen op screen 1.
    if api.get_current_screen
    and api.get_current_screen() ~= 1 then
        return
    end

    local now = reaper.time_precise()

    if now - last_update_time < UPDATE_INTERVAL then
        return
    end

    last_update_time = now

    for track_number, selection in pairs(selections) do
        update_selection(
            api,
            track_number,
            selection
        )
    end
end

return Pattern
