-- ============================================================
-- gjs - x - subproject_track.lua
-- Selects and record-arms top-level tracks inside a subproject.
-- Only tracks on folder layer 0 are shown and selectable.
-- Child tracks are ignored and do not consume one of the 16 pads.
-- Multiple tracks may be armed; REAPER selection remains the control/FX target.
-- ============================================================

local M = {}
local MAX_VISIBLE_TRACKS = 16

local function get_project(subproject_number)
    subproject_number = tonumber(subproject_number)
    if not subproject_number then
        return nil
    end

    subproject_number = math.floor(subproject_number)

    if subproject_number < 1 or subproject_number > 8 then
        return nil
    end

    -- Natural visible-tab flow:
    -- ActiveTrack 1 -> REAPER project 0
    -- ...
    -- ActiveTrack 8 -> REAPER project 7
    return reaper.EnumProjects(subproject_number - 1, "")
end

-- Return tracks whose folder depth before the track is zero.
-- I_FOLDERDEPTH changes the depth after the current track, so a folder
-- parent itself still belongs to layer 0 while its children do not.
local function get_top_level_tracks(project)
    local tracks = {}
    if not project then return tracks end

    local depth = 0
    local count = reaper.CountTracks(project)

    for index = 0, count - 1 do
        local track = reaper.GetTrack(project, index)

        if track and depth == 0 then
            tracks[#tracks + 1] = track
        end

        if track then
            depth = depth + math.floor(
                reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            )

            -- Protect against malformed folder structures.
            if depth < 0 then depth = 0 end
        end
    end

    return tracks
end

function M.get_selected_track(project)
    if not project then return nil end

    local top_level_tracks = get_top_level_tracks(project)

    for number, track in ipairs(top_level_tracks) do
        if reaper.IsTrackSelected(track) then
            return track, number
        end
    end

    if #top_level_tracks > 0 then
        return top_level_tracks[1], 1
    end

    return nil
end

function M.get_for_subproject(subproject_number)
    local project = get_project(subproject_number)
    if not project then return nil, nil end
    return project, M.get_selected_track(project)
end

function M.select(subproject_number, track_number, armed)
    local project = get_project(subproject_number)
    track_number = math.floor(tonumber(track_number) or 0)

    if not project or track_number < 1 then
        return false
    end

    local top_level_tracks = get_top_level_tracks(project)
    local track = top_level_tracks[track_number]

    if not track then
        return false
    end

    -- Keep one selected track as the control/FX target, but do not
    -- disarm any of the other top-level tracks.
    for index = 0, reaper.CountTracks(project) - 1 do
        local candidate = reaper.GetTrack(project, index)

        if candidate then
            reaper.SetTrackSelected(candidate, false)
        end
    end

    reaper.SetTrackSelected(track, true)

    if armed == nil then
        armed =
            reaper.GetMediaTrackInfo_Value(track, "I_RECARM") < 0.5
    end

    reaper.SetMediaTrackInfo_Value(
        track,
        "I_RECARM",
        armed and 1 or 0
    )

    -- Selecting/arming tracks must not leave an old automation mode active.
    reaper.SetMediaTrackInfo_Value(
        track,
        "I_AUTOMODE",
        0
    )

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    return true
end


function M.draw(api, C, subproject_number, close_callback)
    local project = get_project(subproject_number)
    local top_level_tracks = get_top_level_tracks(project)
    local track_count = #top_level_tracks

    local available_colour = C.LIGHT_BLUE
    local unavailable_colour = { 0, 18, 32 }
    local state = api.get_screen_state(0)

    for number = 1, MAX_VISIBLE_TRACKS do
        local row = number <= 8 and 8 or 7
        local col = number <= 8 and number or number - 8
        local note = row * 10 + col
        local track = top_level_tracks[number]
        local available = track ~= nil

        if available then
            local armed =
                reaper.GetMediaTrackInfo_Value(
                    track,
                    "I_RECARM"
                ) > 0.5

            state.toggle[note] = armed

            api.drawpad(
                row,
                col,
                available_colour,
                api.MODE_TOGGLE,
                {
                    active_color = C.WHITE,

                    on_press = function(pad)
                        M.select(
                            subproject_number,
                            number,
                            pad.active
                        )

                        api.redraw()
                    end
                }
            )
        else
            state.toggle[note] = false

            api.drawpad(
                row,
                col,
                unavailable_colour,
                api.MODE_NONE
            )
        end
    end

    -- Action pad 5 closes this mode.
    api.drawpad(
        1,
        5,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,

            on_press = function()
                if close_callback then
                    close_callback()
                end

                api.redraw()
            end
        }
    )
end

return M
