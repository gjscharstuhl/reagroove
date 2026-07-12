-- gjs - Play / stop recording safely

local state = reaper.GetPlayState()
local is_recording = (state & 4) == 4
local is_playing = (state & 1) == 1

if is_recording then

  -- echte recording stoppen
  reaper.Main_OnCommand(40667, 0)

  return
end

if not is_playing then
  reaper.Main_OnCommand(1007, 0)
end
