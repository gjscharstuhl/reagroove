local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

local nr = lib.target("regions")

if nr then
  reaper.SetExtState("GJS_MULTI", "Region", tostring(nr), false)
end


--reaper.ShowConsoleMsg(tostring(nr))


