-- Previous visible track in TCP
local proj = 0
local sel = reaper.GetSelectedTrack(proj, 0)
if not sel then return end

local sel_idx = reaper.GetMediaTrackInfo_Value(sel, "IP_TRACKNUMBER") - 1

for i = sel_idx - 1, 0, -1 do
  local tr = reaper.GetTrack(proj, i)
  local visible = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
  if visible > 0 then
    reaper.SetOnlyTrackSelected(tr)
    reaper.Main_OnCommand(40913, 0) -- Track: Vertical scroll selected tracks into view
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    return
  end
end
