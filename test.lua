 active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
if not active_track then return end

local proj = reaper.EnumProjects(active_track)
if not proj then return end

track = reaper.GetTrack(proj,0)
reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0) -- latch
