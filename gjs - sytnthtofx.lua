local function find_track_by_name(name)
  name = name:lower()

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tr_name = reaper.GetTrackName(tr)

    if tr_name:lower() == name then
      return tr
    end
  end

  return nil
end

function redirect(oldname,newname)
local oldtr=find_track_by_name(oldname)

if oldtr==nil then return end

if reaper.IsTrackSelected(oldtr) then
  local newtr=find_track_by_name(newname)
  reaper.SetTrackSelected(oldtr,0)
  reaper.SetTrackSelected(newtr,1)
end
return nil
end

redirect("Synth1","Synth1-fx")

redirect("Synth2","Synth2-fx")

