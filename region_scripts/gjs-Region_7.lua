-- gjs - Set time selection to region number 3
-- Recording friendly: does not move cursor or transport

local target_region_number = 7

local _, num_markers, num_regions = reaper.CountProjectMarkers(0)

for i = 0, num_markers + num_regions - 1 do
  local retval, is_region, pos, rgnend, name, markrgnindexnumber =
    reaper.EnumProjectMarkers(i)

  if is_region and markrgnindexnumber == target_region_number then
    reaper.GetSet_LoopTimeRange(true, false, pos, rgnend, false)
    reaper.UpdateArrange()
    return
  end
end
