-- Append region of X bars at end of last region
local BARS = 4
local INITIAL_OFFSET_BARS = 4
local proj = 0

local function get_qn_per_bar_at_time(time)
  local num, denom = reaper.TimeMap_GetTimeSigAtTime(proj, time)
  if not num or num < 1 then num = 4 end
  if not denom or denom < 1 then denom = 4 end
  return num * (4 / denom)
end

local function bars_to_time_from(start_time, bars)
  local qn_per_bar = get_qn_per_bar_at_time(start_time)
  local start_qn = reaper.TimeMap2_timeToQN(proj, start_time)
  local end_qn = start_qn + (bars * qn_per_bar)
  return reaper.TimeMap2_QNToTime(proj, end_qn)
end

local function get_region_length_in_time(start_time, bars)
  return bars_to_time_from(start_time, bars) - start_time
end

local function get_all_regions()
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local retval, isrgn, pos, rgnend, name, id = reaper.EnumProjectMarkers(i)
    if retval and isrgn then
      table.insert(regions, {
        id = id,
        start_pos = pos,
        end_pos = rgnend,
        name = name or ""
      })
    end
  end

  table.sort(regions, function(a, b)
    return a.start_pos < b.start_pos
  end)

  return regions
end

local function get_last_region(regions)
  if #regions == 0 then return nil end
  return regions[#regions]
end

local function add_region(start_pos, end_pos, name)
  reaper.AddProjectMarker2(proj, true, start_pos, end_pos, name or "", -1, 0)
end

local function focus_new_region(start_pos, end_pos)
  -- time selection op de nieuwe region
  reaper.GetSet_LoopTimeRange(true, false, start_pos, end_pos, false)

  -- cursor aan begin van de nieuwe region
  reaper.SetEditCurPos(start_pos, true, false)

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local regions = get_all_regions()
local start_pos

if #regions == 0 then
  -- eerste region komt INITIAL_OFFSET_BARS maten vanaf begin
  start_pos = bars_to_time_from(0.0, INITIAL_OFFSET_BARS)
else
  -- append direct achter de laatste region
  local last_region = get_last_region(regions)
  start_pos = last_region.end_pos
end

local len = get_region_length_in_time(start_pos, BARS)
local end_pos = start_pos + len

add_region(start_pos, end_pos, BARS .. " bars")
focus_new_region(start_pos, end_pos)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Append region (" .. BARS .. " bars)", -1)
