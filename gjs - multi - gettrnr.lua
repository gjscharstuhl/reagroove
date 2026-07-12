local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

local nr = lib.target("tracks")

if nr then
  reaper.SetExtState("GJS_MULTI", "ActiveTrack", tostring(nr), false)
end

