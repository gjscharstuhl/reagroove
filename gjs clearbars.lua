-- gjs - unselect all tracks in Bars folder

local FOLDER_NAME = "Bars"

local function find_folder_track_number(name)
    name = name:lower()

    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, tr_name = reaper.GetTrackName(tr)

        if tr_name:lower() == name then
            return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
        end
    end

    return nil
end

local function unselect_tracks_in_folder(folder_name)
    local folder_nr = find_folder_track_number(folder_name)
    if not folder_nr then return end

    local idx = folder_nr -- eerste child-track

    while idx < reaper.CountTracks(0) do
        local tr = reaper.GetTrack(0, idx)
        if not tr then break end

        reaper.SetTrackSelected(tr, false)

        local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        if depth < 0 then break end

        idx = idx + 1
    end

    reaper.UpdateArrange()
end

unselect_tracks_in_folder(FOLDER_NAME)
