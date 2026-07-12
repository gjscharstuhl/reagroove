-- GJS Pattern Launcher - MIDI note to track/region

 function cleararm(proj)
   for i=0,reaper.CountTracks()-1 do
     local tr=reaper.GetTrack(proj, i)
       if tr then reaper.SetMediaTrackInfo_Value(tr,"I_RECARM", 0) end
     end
    
 end
 
 
function arm(nr,page)
  

  -- tabs 2 t/m 9 = tracks 1 t/m 8
  for tab = 2, 9 do
    local proj = reaper.EnumProjects(tab - 1)

    if proj then
      mytracknr = tab - 1
      cleararm(proj) 
      if page==1 then
        if mytracknr==nr then
      a=1
          local track=reaper.GetTrack(proj, 0) -- eerste track in dat subproject
          reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        end
      elseif page==2 then
        if mytracknr==6 or  mytracknr==7 then
          local track=reaper.GetTrack(proj, 1) -- eerste track in dat subproject
          reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        end
      
      end
    end
    

  end
end

local _, _, _, _, mode, resolution, val, valhw =
  reaper.get_action_context()

local note = math.floor((val / resolution) * 127 + 0.5)

local active_track = nil
local region_num = nil

local pc_to_region = {
  [0]  = 1,
  [2]  = 2,
  [3]  = 3,
  [4]  = 4,
  [5]  = 5,
  [7]  = 6,
  [9]  = 7,
  [10] = 8
}

-- wraparound voor hoogste rij rechts
if note == 1 then
  active_track = 8
  region_num = 7
elseif note == 2 then
  active_track = 8
  region_num = 8
else
  region_num = pc_to_region[note % 12]
  if not region_num then return end

  local base_note = 36
  active_track = math.floor((note - base_note) / 12) + 1
end

if active_track < 1 or active_track > 8 then return end

reaper.SetExtState("GJS_MULTI", "ActiveTrack", tostring(active_track), false)
reaper.SetExtState("GJS_MULTI", "TargetRegion", tostring(region_num), false)
page = reaper.GetExtState("GJS_MULTI", "Page")

local proj = reaper.EnumProjects(active_track)
if not proj then return end

local wanted = string.format(
  "Regions: Go to region %02d after current region finishes playing",
  region_num
)

local cmd = nil

for i = 0, 70000 do
  local txt = reaper.kbd_getTextFromCmd(i, 0)
  if txt and txt:find(wanted, 1, true) then
    cmd = i
    break
  end
end

if cmd then
  reaper.Main_OnCommandEx(cmd, 0, proj)
end

local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)

for i = 0, num_markers + num_regions - 1 do
  local retval, is_region, pos, rgnend, name, markrgnindexnumber =
    reaper.EnumProjectMarkers2(proj, i)

  if is_region and markrgnindexnumber == region_num then
    reaper.GetSet_LoopTimeRange2(proj, true, false, pos, rgnend, false)
    reaper.UpdateArrange()
    return
  end
end
