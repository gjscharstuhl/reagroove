-- GJS Pattern Launcher - MIDI note to track/region + queued blink
local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")




x,y=lib.getxy()

reaper.ShowConsoleMsg(tostring(y).."  "..tostring(x).."\n")
