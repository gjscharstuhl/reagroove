local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

local active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
if not active_track then return end

-- tab 1 = hoofdproject
-- tab 2 = track 1
-- tab 3 = track 2
-- etc.
local proj = reaper.EnumProjects(active_track)

if not proj then return end

local target_region_number = lib.target("regions")
if not target_region_number then return end

local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)

for i = 0, num_markers + num_regions - 1 do
  local retval, is_region, pos, rgnend, name, markrgnindexnumber =
    reaper.EnumProjectMarkers2(proj, i)

  if is_region and markrgnindexnumber == target_region_number then
    reaper.GetSet_LoopTimeRange2(proj, true, false, pos, rgnend, false)
    reaper.UpdateArrange()
    return
  end
end
