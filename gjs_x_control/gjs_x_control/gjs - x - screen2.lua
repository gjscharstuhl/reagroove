-- ============================================================
-- Screen 2: mixer faders
-- Patch 1b: read volumes from direct children of folder "tracks"
-- Read/display only; no volume writing yet.
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

    local function normalized_name(name)
        return (name or "")
            :match("^%s*(.-)%s*$")
            :lower()
    end

    local function find_direct_children(folder_name, maximum)
        local wanted = normalized_name(folder_name)
        local folder = nil
        local folder_index = nil
        local folder_depth = nil

        for index = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local _, name = reaper.GetTrackName(track)

            if normalized_name(name) == wanted
            and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0 then
                folder = track
                folder_index = index
                folder_depth = reaper.GetTrackDepth(track)
                break
            end
        end

        if not folder then
            return {}
        end

        local children = {}

        for index = folder_index + 1, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, index)
            local depth = reaper.GetTrackDepth(track)

            -- We have left the folder.
            if depth <= folder_depth then
                break
            end

            -- Only immediate children, not tracks inside nested folders.
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

        -- 32 LED positions: -60 dB at the bottom, +12 dB at the top.
        local normalized = math.max(0, math.min(1, (db + 60) / 72))
        local position = math.floor(normalized * 31 + 0.5)

        return math.floor(position / 4) + 1,
               (position % 4) + 1
    end

    -- Page 1 is currently the only implemented mixer page, so do not gate
    -- volume loading on screen 0's page state yet. This avoids a stale or
    -- uninitialised page-selector state preventing the faders from loading.
    local children = find_direct_children(FOLDER_NAME, 8)
    local state = api.get_screen_state(2)

    for col = 1, 8 do
        local track = children[col]

        if track then
            local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
            local row, step = volume_to_fader(volume)

            state.fader["mixer_fader_" .. col] = {
                row = row,
                step = step
            }
        end
    end

    for col = 1, 8 do
        api.draw_vertical_fader(
            col,
            FADER_RGB[col],
            {
                group = "mixer_fader_" .. col,
                default_row = 1,
                default_step = 4
            }
        )
    end
end
