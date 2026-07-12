local _, _, sectionID, cmdID = reaper.get_action_context()

local track = reaper.GetSelectedTrack(0, 0)
if not track then return end

local mode = reaper.GetMediaTrackInfo_Value(track, "I_AUTOMODE")

if mode == 4 then
  reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0) -- trim/read
  reaper.SetToggleCommandState(sectionID, cmdID, 0)
else
  reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 4) -- latch
  reaper.SetToggleCommandState(sectionID, cmdID, 1)
end

reaper.RefreshToolbar2(sectionID, cmdID)
