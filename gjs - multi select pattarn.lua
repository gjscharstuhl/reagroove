local tr = reaper.GetLastTouchedTrack()
if not tr then return end

local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)

local pat_num = tonumber(name:match("^pat(%d+)$"))
if not pat_num then return end

local active_track = math.floor((pat_num - 1) / 8) + 1
local region_num = ((pat_num - 1) % 8) + 1

reaper.SetExtState("GJS_MULTI", "ActiveTrack", tostring(active_track), false)
reaper.SetExtState("GJS_MULTI", "TargetRegion", tostring(region_num), false)

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
  local retval, is_region, pos, rgnend, rgn_name, markrgnindexnumber =
    reaper.EnumProjectMarkers2(proj, i)

  if is_region and markrgnindexnumber == region_num then
    reaper.GetSet_LoopTimeRange2(proj, true, false, pos, rgnend, false)
    reaper.UpdateArrange()
    return
  end
end
