-- ============================================================
-- Screen 3: pan controls
-- Reads and writes pan for the first eight direct children of
-- folder "tracks", while preserving the existing horizontal faders.
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

    -- Convert REAPER pan (-1.0 .. +1.0) to the 19 positions offered by
    -- the existing horizontal fader: full L, 8 fine-left positions,
    -- centre, 8 fine-right positions, full R.
    local function pan_to_balance(pan)
        local value = math.max(-1, math.min(1, pan or 0))
        local index = math.floor(((value + 1) * 9) + 0.5) -- 0 .. 18

        if index == 0 then
            return { position = 1, step = 4, centered = false }
        elseif index <= 4 then
            return { position = 2, step = 5 - index, centered = false }
        elseif index <= 8 then
            return { position = 3, step = 9 - index, centered = false }
        elseif index == 9 then
            return { position = 4, step = 4, centered = true }
        elseif index <= 13 then
            return { position = 6, step = index - 9, centered = false }
        elseif index <= 17 then
            return { position = 7, step = index - 13, centered = false }
        end

        return { position = 8, step = 4, centered = false }
    end

    local function balance_to_pan(balance)
        if not balance or balance.centered then
            return 0
        end

        local index

        if balance.position == 1 then
            index = 0
        elseif balance.position == 2 then
            index = 5 - balance.step
        elseif balance.position == 3 then
            index = 9 - balance.step
        elseif balance.position == 6 then
            index = 9 + balance.step
        elseif balance.position == 7 then
            index = 13 + balance.step
        elseif balance.position == 8 then
            index = 18
        else
            index = 9
        end

        return (index / 9) - 1
    end

    local children = find_direct_children(FOLDER_NAME, 8)
    local state = api.get_screen_state(3)

    -- Load the current REAPER pan values before drawing the faders.
    for row = 1, 8 do
        local track = children[row]

        if track then
            local group = "mixer_pan_" .. row
            local pan = reaper.GetMediaTrackInfo_Value(track, "D_PAN")
            state.balance[group] = pan_to_balance(pan)
        end
    end

    for row = 1, 8 do
        local track = children[row]
        local group = "mixer_pan_" .. row

        api.draw_horizontal_fader(
            row,
            FADER_RGB[row],
            {
                group = group,

                on_press = function()
                    if not track then
                        return
                    end

                    local balance = state.balance[group]
                    local pan = balance_to_pan(balance)

                    reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan)
                    reaper.TrackList_AdjustWindows(false)
                end
            }
        )
    end
end
