-- gjs - Set time selection to region number 3
-- Recording friendly: does not move cursor or transport

local function get_selected_region_number()
  local tr = reaper.GetSelectedTrack(0, 0)
  if not tr then return nil end

  local _, name = reaper.GetTrackName(tr)

  local num = name:lower():match("^region(%d+)$")
  if not num then return nil end

  num = tonumber(num)

  if num < 1 or num > 8 then return nil end

  return num
end

local TARGET_REGION = get_selected_region_number()

if not TARGET_REGION then
  return
end

local target_region_number = TARGET_REGION

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
