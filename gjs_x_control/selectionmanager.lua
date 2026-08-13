-- ============================================================
-- selectionmanager.lua
-- Shared selected region per track.
-- Pending/active visual state stays owned by pattern.lua.
-- ============================================================

local M = {}

local regions = {1,1,1,1,1,1,1,1}

local function valid_track(track)
    track = tonumber(track)
    if not track then return nil end
    track = math.floor(track)
    if track < 1 or track > 8 then return nil end
    return track
end

local function valid_region(region)
    region = tonumber(region)
    if not region then return nil end
    region = math.floor(region)
    if region < 1 or region > 8 then return nil end
    return region
end

function M.set_region(track, region)
    track = valid_track(track)
    region = valid_region(region)
    if not track or not region then return false end

    regions[track] = region
    return true
end

function M.get_region(track)
    track = valid_track(track)
    if not track then return 1 end
    return regions[track] or 1
end

function M.show()
    for track = 1, 8 do
        reaper.ShowConsoleMsg(
            "track " .. track .. " -> region " .. M.get_region(track) .. "\n"
        )
    end
end

return M
