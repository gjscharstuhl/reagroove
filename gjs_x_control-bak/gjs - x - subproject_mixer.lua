-- ============================================================
-- gjs - x - subproject_mixer.lua
-- Internal mixer for the active subproject.
-- Only top-level tracks (folder layer 0) are included.
-- Child tracks are ignored and do not consume a mixer channel.
-- ============================================================

local M = {}
local MAX_CHANNELS = 8

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function M.get_active_subproject_number()
    local value = tonumber(reaper.GetExtState("GJS_X", "ActiveTrack")) or 1
    return clamp(math.floor(value), 1, 8)
end

function M.get_project(subproject_number)
    local number = tonumber(subproject_number)
    if not number then
        return nil
    end

    number = clamp(math.floor(number), 1, 8)

    -- Natural visible-tab flow:
    -- ActiveTrack 1 -> REAPER project 0
    -- ...
    -- ActiveTrack 8 -> REAPER project 7
    return reaper.EnumProjects(number - 1, "")
end

function M.get_top_level_tracks(project, maximum)
    local tracks = {}
    if not project then return tracks end

    maximum = math.max(1, math.floor(tonumber(maximum) or MAX_CHANNELS))
    local depth = 0

    for index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, index)

        -- I_FOLDERDEPTH changes the depth after this track. A folder
        -- parent is therefore still a top-level mixer channel.
        if track and depth == 0 then
            tracks[#tracks + 1] = track
            if #tracks >= maximum then break end
        end

        if track then
            depth = depth + math.floor(
                reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            )
            if depth < 0 then depth = 0 end
        end
    end

    return tracks
end

function M.get_active_tracks(maximum)
    local number = M.get_active_subproject_number()
    local project = M.get_project(number)
    return project, M.get_top_level_tracks(project, maximum), number
end

function M.volume_to_fader(volume)
    local db
    if not volume or volume <= 0 then
        db = -60
    else
        db = 20 * math.log(volume, 10)
    end

    local normalized = clamp((db + 60) / 72, 0, 1)
    local position = math.floor(normalized * 31 + 0.5)
    return math.floor(position / 4) + 1, (position % 4) + 1
end

function M.fader_to_volume(row, step)
    local position = ((row - 1) * 4) + (step - 1)
    local db = -60 + (position / 31) * 72
    return 10 ^ (db / 20)
end

function M.pan_to_balance(pan)
    local value = clamp(tonumber(pan) or 0, -1, 1)
    local index = math.floor(((value + 1) * 9) + 0.5)

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

function M.balance_to_pan(balance)
    if not balance or balance.centered then return 0 end

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

function M.same_balance(left, right)
    return left and right
       and left.position == right.position
       and left.step == right.step
       and left.centered == right.centered
end

return M
