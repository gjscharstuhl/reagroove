local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

local active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
if not active_track then return end
cmd=3122+active_track
reaper.Main_OnCommand(cmd, 0)
