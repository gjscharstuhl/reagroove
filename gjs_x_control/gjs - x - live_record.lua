-- ============================================================
-- gjs - x - live_record.lua
-- Toggle recording for the open project named liverec.rpp.
-- ============================================================

local M = {}

local CMD_RECORD = 1013
local TARGET_NAME = "liverec.rpp"

local function basename(path)
    if not path or path == "" then return "" end
    return path:match("([^/\\]+)$") or path
end

function M.find_project()
    local index = 0

    while true do
        local project, path = reaper.EnumProjects(index, "")
        if not project then break end

        if basename(path):lower() == TARGET_NAME then
            return project
        end

        index = index + 1
    end

    return nil
end

function M.is_recording()
    local project = M.find_project()
    if not project then return false end

    local play_state = reaper.GetPlayStateEx(project) or 0
    return (play_state & 4) == 4
end

function M.toggle()
    local project = M.find_project()

    if not project then
        reaper.ShowConsoleMsg("ReaGroove live record: liverec.rpp is niet geopend.\n")
        return false
    end

    local play_state = reaper.GetPlayStateEx(project) or 0
    local recording = (play_state & 4) == 4

    if recording then
        -- Stop recording normally. REAPER commits the take/item and leaves
        -- the project cursor at the point where recording stopped.
        reaper.Main_OnCommandEx(CMD_RECORD, 0, project)
        return true
    end

    -- Starting again must continue from the end of the existing live
    -- recording, not from an older edit/play cursor position.
    local end_position = 0
    for track_index = 0, reaper.CountTracks(project) - 1 do
        local track = reaper.GetTrack(project, track_index)
        for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, item_index)
            local item_end =
                reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if item_end > end_position then
                end_position = item_end
            end
        end
    end

    reaper.SetEditCurPos2(project, end_position, false, false)
    reaper.Main_OnCommandEx(CMD_RECORD, 0, project)
    return true
end

return M
