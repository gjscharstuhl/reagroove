-- gjs - Create minimal Launchpad X test setup.lua
--
-- HOOFDPROJECT:
--   tracks
--     16PADS
--     Bass
--     Guitar R
--     Guitar S
--     Synth
--     Synth1
--     Synth2
--     Synth2
--     Other
--
--   paging
--     page1
--     page2
--     page3
--     page4
--
--   recordled
--
--   regions
--     region1 ... region8
--
--   bars
--     bar1 ... bar8
--
--   DIRTT Launchpad Bridge
--     gjs - x - sysex bridge
--
-- SUBPROJECTEN 1..8:
--   Test-track met ReaSynth
--   8 regions van elk 4 maten
--
-- Start dit met precies één leeg project geopend.

local BRIDGE_TRACK_NAME = "DIRTT Launchpad Bridge"
local BRIDGE_FX_NAME    = "gjs - x - sysex bridge"

local SUBPROJECT_COUNT   = 8
local REGION_COUNT       = 8
local MEASURES_PER_REGION = 4

------------------------------------------------------------
-- Algemene helpers
------------------------------------------------------------

local function count_open_projects()
    local count = 0

    while reaper.EnumProjects(count, "") do
        count = count + 1
    end

    return count
end

local function add_track(proj, name)
    local index = reaper.CountTracks(proj)

    reaper.InsertTrackAtIndex(index, false)

    local track = reaper.GetTrack(proj, index)
    if not track then
        return nil
    end

    reaper.GetSetMediaTrackInfo_String(
        track,
        "P_NAME",
        name,
        true
    )

    return track
end

local function set_folder_depth(track, depth)
    reaper.SetMediaTrackInfo_Value(
        track,
        "I_FOLDERDEPTH",
        depth
    )
end

local function hide_track(track)
    -- Verberg in TCP en mixer.
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
end

local function clear_project(proj)
    for i = reaper.CountTracks(proj) - 1, 0, -1 do
        local track = reaper.GetTrack(proj, i)

        if track then
            reaper.DeleteTrack(track)
        end
    end

    local _, marker_count, region_count =
        reaper.CountProjectMarkers(proj)

    local markers = {}

    for i = 0, marker_count + region_count - 1 do
        local ok, is_region, _, _, _, index =
            reaper.EnumProjectMarkers2(proj, i)

        if ok then
            markers[#markers + 1] = {
                index = index,
                is_region = is_region
            }
        end
    end

    for i = #markers, 1, -1 do
        reaper.DeleteProjectMarker(
            proj,
            markers[i].index,
            markers[i].is_region
        )
    end
end

------------------------------------------------------------
-- Folder met child-tracks maken
------------------------------------------------------------

local function create_folder(proj, folder_name, child_names, hidden)
    local folder = add_track(proj, folder_name)

    if not folder then
        return nil, {}
    end

    set_folder_depth(folder, 1)

    if hidden then
        hide_track(folder)
    end

    local children = {}

    for i, child_name in ipairs(child_names) do
        local child = add_track(proj, child_name)

        if not child then
            break
        end

        if i == #child_names then
            set_folder_depth(child, -1)
        else
            set_folder_depth(child, 0)
        end

        if hidden then
            hide_track(child)
        end

        children[#children + 1] = child
    end

    return folder, children
end

------------------------------------------------------------
-- Hoofdproject
------------------------------------------------------------

local function create_main_project(proj)
    --------------------------------------------------------
    -- Muzikale hoofdtracks
    --------------------------------------------------------

    local musical_names = {
        "16PADS",
        "Bass",
        "Guitar R",
        "Guitar S",
        "Synth",
        "Synth1",
        "Synth2",
        "Synth2",
        "Other"
    }

    local _, musical_tracks =
        create_folder(
            proj,
            "tracks",
            musical_names,
            false
        )

    -- Net zoals in het echte project staan deze tracks armed.
    for _, track in ipairs(musical_tracks) do
        reaper.SetMediaTrackInfo_Value(
            track,
            "I_RECARM",
            1
        )
    end

    --------------------------------------------------------
    -- Paging
    --------------------------------------------------------

    create_folder(
        proj,
        "paging",
        {
            "page1",
            "page2",
            "page3",
            "page4"
        },
        true
    )

    --------------------------------------------------------
    -- Record-led
    --------------------------------------------------------

    local record_led = add_track(proj, "recordled")

    if record_led then
        hide_track(record_led)
    end

    --------------------------------------------------------
    -- Region-selectortracks
    --------------------------------------------------------

    create_folder(
        proj,
        "regions",
        {
            "region1",
            "region2",
            "region3",
            "region4",
            "region5",
            "region6",
            "region7",
            "region8"
        },
        true
    )

    --------------------------------------------------------
    -- Bar-selectortracks
    --------------------------------------------------------

    create_folder(
        proj,
        "bars",
        {
            "bar1",
            "bar2",
            "bar3",
            "bar4",
            "bar5",
            "bar6",
            "bar7",
            "bar8"
        },
        true
    )

    --------------------------------------------------------
    -- Bridge
    --------------------------------------------------------

    local bridge = add_track(
        proj,
        BRIDGE_TRACK_NAME
    )

    if not bridge then
        return false, "Kon de bridge-track niet maken."
    end

    local fx_index = reaper.TrackFX_AddByName(
        bridge,
        BRIDGE_FX_NAME,
        false,
        -1
    )

    if fx_index < 0 then
        return false,
            "De bridge-track is gemaakt, maar de JSFX werd niet gevonden:\n\n"
            .. BRIDGE_FX_NAME
    end

    return true
end

------------------------------------------------------------
-- Subproject
------------------------------------------------------------

local function create_regions(proj)
    -- De posities worden via QN berekend, zodat vier maten
    -- ook bij een ander tempo vier muzikale maten blijven.
    local qn_per_measure = 4
    local qn_per_region =
        MEASURES_PER_REGION * qn_per_measure

    for region = 1, REGION_COUNT do
        local start_qn =
            (region - 1) * qn_per_region

        local end_qn =
            region * qn_per_region

        local start_time =
            reaper.TimeMap2_QNToTime(
                proj,
                start_qn
            )

        local end_time =
            reaper.TimeMap2_QNToTime(
                proj,
                end_qn
            )

        reaper.AddProjectMarker2(
            proj,
            true,
            start_time,
            end_time,
            "Region " .. region,
            region,
            0
        )
    end
end

local function create_test_track(proj, number)
    local track = add_track(
        proj,
        "Test " .. number
    )

    if not track then
        return false, "Kon Test-track niet maken."
    end

    local fx_index = reaper.TrackFX_AddByName(
        track,
        "ReaSynth",
        false,
        -1
    )

    if fx_index < 0 then
        return false, "ReaSynth werd niet gevonden."
    end

    -- Record-arm.
    reaper.SetMediaTrackInfo_Value(
        track,
        "I_RECARM",
        1
    )

    -- MIDI-input: alle MIDI-devices, alle kanalen.
    reaper.SetMediaTrackInfo_Value(
        track,
        "I_RECINPUT",
        4096 + 63
    )

    -- Normale MIDI-recordmodus.
    reaper.SetMediaTrackInfo_Value(
        track,
        "I_RECMODE",
        0
    )

    return true
end

local function create_new_project_tab()
    -- File: New project tab
    reaper.Main_OnCommand(40859, 0)

    return reaper.EnumProjects(-1, "")
end

------------------------------------------------------------
-- Controle
------------------------------------------------------------

local open_projects = count_open_projects()

if open_projects ~= 1 then
    reaper.MB(
        "Open eerst precies één leeg project.\n\n"
        .. "Er zijn nu "
        .. open_projects
        .. " projecttabs geopend.",
        "Minimale Launchpad X-testsetup",
        0
    )

    return
end

local answer = reaper.MB(
    "Dit wist alle tracks, markers en regions "
    .. "uit het huidige project.\n\n"
    .. "Daarna maakt het script acht nieuwe projecttabs.\n\n"
    .. "Doorgaan?",
    "Minimale Launchpad X-testsetup",
    4
)

if answer ~= 6 then
    return
end

------------------------------------------------------------
-- Uitvoeren
------------------------------------------------------------

local main_project = reaper.EnumProjects(-1, "")

local errors = {}

reaper.PreventUIRefresh(1)

------------------------------------------------------------
-- Hoofdproject opbouwen
------------------------------------------------------------

reaper.Undo_BeginBlock2(main_project)

clear_project(main_project)

local main_ok, main_error =
    create_main_project(main_project)

if not main_ok then
    errors[#errors + 1] =
        "Hoofdproject: " .. main_error
end

reaper.Undo_EndBlock2(
    main_project,
    "Create minimal Launchpad X main project",
    -1
)

------------------------------------------------------------
-- Acht subprojecttabs opbouwen
------------------------------------------------------------

for number = 1, SUBPROJECT_COUNT do
    local proj = create_new_project_tab()

    if not proj then
        errors[#errors + 1] =
            "Kon subproject " .. number .. " niet maken."
    else
        reaper.Undo_BeginBlock2(proj)

        clear_project(proj)

        local track_ok, track_error =
            create_test_track(proj, number)

        if not track_ok then
            errors[#errors + 1] =
                "Subproject "
                .. number
                .. ": "
                .. track_error
        end

        create_regions(proj)

        reaper.Undo_EndBlock2(
            proj,
            "Create ReaSynth test subproject",
            -1
        )
    end
end

------------------------------------------------------------
-- Terug naar hoofdproject
------------------------------------------------------------

reaper.SelectProjectInstance(main_project)

reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)

------------------------------------------------------------
-- Resultaat
------------------------------------------------------------

local message = {
    "Testsetup aangemaakt:",
    "",
    "- hoofdproject met de vereiste folders en tracks",
    "- DIRTT Launchpad Bridge met de bridge-JSFX",
    "- acht subprojecttabs",
    "- iedere subprojecttab heeft ReaSynth",
    "- iedere subprojecttab heeft acht regions van vier maten",
    "",
    "Stel op de bridge-track nog handmatig de juiste",
    "MIDI hardware-output naar de Launchpad X in."
}

if #errors > 0 then
    message[#message + 1] = ""
    message[#message + 1] = "Fouten:"

    for _, error_message in ipairs(errors) do
        message[#message + 1] = "- " .. error_message
    end
end

reaper.MB(
    table.concat(message, "\n"),
    "Testsetup gereed",
    0
)
