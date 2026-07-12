local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

local page = lib.target("paging")
local active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))

reaper.SetExtState("GJS_MULTI", "Page", tostring(page), false)

--[[
local proj = reaper.EnumProjects(active_track )

if active_track == 6 or active_track == 7 then
    local track = reaper.GetTrack(proj,0) -- eerste track

    if track then
        if page == 2 then
            reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 7) -- MIDI Overdub
        else
            reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 0) -- Record Input
        end
    end
end
]]
