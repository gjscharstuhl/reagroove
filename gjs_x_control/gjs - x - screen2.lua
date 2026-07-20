-- ============================================================
-- gjs - x - screen2.lua
-- Page 1: volumes of the first 8 direct children of folder "tracks"
-- Page 2: global FX send levels for the active track
-- ============================================================

return function(api)
    local FOLDER_NAME = "tracks"

    local FADER_RGB = {
        {127,   0,   0}, -- red
        {127,  35,   0}, -- orange
        {  0, 127,   0}, -- green
        {127, 100,   0}, -- yellow
        {127,   0,  70}, -- magenta
        { 55,   0, 127}, -- purple
        {127,  20,  90}, -- pink
        {  0,  35, 127}  -- blue
    }

    local GLOBAL_FX_TRACKS = {
        "Reverb1",
        "Delay",
        "Chorus",
        "Flanger",
        "Filter",
        "Fuzz",
        "Reverb2",
        "Delay2"
    }

    local function normalized_name(name)
        return (name or "")
            :match("^%s*(.-)%s*$")
            :lower()
    end

    local function find_track_by_name(wanted_name)
        local wanted = normalized_name(wanted_name)

        for index = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local _, name = reaper.GetTrackName(track)

            if normalized_name(name) == wanted then
                return track
            end
        end

        return nil
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

        if folder_index == nil then
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

    local function volume_to_fader(volume)
        local db

        if volume <= 0 then
            db = -60
        else
            db = 20 * math.log(volume, 10)
        end

        local normalized = math.max(0, math.min(1, (db + 60) / 72))
        local position = math.floor(normalized * 31 + 0.5)

        return math.floor(position / 4) + 1,
               (position % 4) + 1
    end

    local function fader_to_volume(row, step)
        local position = ((row - 1) * 4) + (step - 1)
        local db = -60 + (position / 31) * 72
        return 10 ^ (db / 20)
    end

    local function find_send(source_track, destination_track)
        for send_index = 0, reaper.GetTrackNumSends(source_track, 0) - 1 do
            local destination = reaper.GetTrackSendInfo_Value(
                source_track,
                0,
                send_index,
                "P_DESTTRACK"
            )

            if destination == destination_track then
                return send_index
            end
        end

        return nil
    end

    local page = api.get_page and api.get_page() or 1
    local children = find_direct_children(FOLDER_NAME, 8)
    local state = api.get_screen_state(2)

    -- Page 1 follows the actual track volumes whenever the mixer is opened.
    if page == 1 then
        for col = 1, 8 do
            local track = children[col]
            local group = "mixer_page_1_fader_" .. col

            if track then
                local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
                local row, step = volume_to_fader(volume)

                state.fader[group] = {
                    row = row,
                    step = step
                }
            end
        end
    end

    -- Page 2 follows existing sends for the currently active pattern track.
    if page == 2 then
        local active_track = tonumber(
            reaper.GetExtState("GJS_X", "ActiveTrack")
        )
        local source_track = active_track and children[active_track] or nil

        if source_track then
            for col = 1, 8 do
                local destination_track = find_track_by_name(
                    GLOBAL_FX_TRACKS[col]
                )
                local group = "mixer_page_2_fader_" .. col

                if destination_track then
                    local send_index = find_send(
                        source_track,
                        destination_track
                    )

                    local volume = 0
                    if send_index ~= nil then
                        volume = reaper.GetTrackSendInfo_Value(
                            source_track,
                            0,
                            send_index,
                            "D_VOL"
                        )
                    end

                    local row, step = volume_to_fader(volume)
                    state.fader[group] = {
                        row = row,
                        step = step
                    }
                end
            end
        end
    end

    for col = 1, 8 do
        local group = "mixer_page_" .. page .. "_fader_" .. col

        api.draw_vertical_fader(
            col,
            FADER_RGB[col],
            {
                group = group,
                default_row = 1,
                default_step = 1,

                on_press = function()
                    local fader = state.fader[group]
                    if not fader then
                        return
                    end

                    local volume = fader_to_volume(
                        fader.row,
                        fader.step
                    )

                    if page == 1 then
                        local track = children[col]
                        if not track then
                            return
                        end

                        reaper.SetMediaTrackInfo_Value(
                            track,
                            "D_VOL",
                            volume
                        )

                    elseif page == 2 then
                        local active_track = tonumber(
                            reaper.GetExtState("GJS_X", "ActiveTrack")
                        )
                        local source_track =
                            active_track and children[active_track] or nil
                        local destination_track = find_track_by_name(
                            GLOBAL_FX_TRACKS[col]
                        )

                        if not source_track or not destination_track then
                            return
                        end

                        local send_index = find_send(
                            source_track,
                            destination_track
                        )

                        if send_index == nil then
                            send_index = reaper.CreateTrackSend(
                                source_track,
                                destination_track
                            )
                        end

                        if send_index < 0 then
                            return
                        end

                        reaper.SetTrackSendInfo_Value(
                            source_track,
                            0,
                            send_index,
                            "D_VOL",
                            volume
                        )
                    end

                    reaper.TrackList_AdjustWindows(false)
                    reaper.UpdateArrange()
                end
            }
        )
    end
end
