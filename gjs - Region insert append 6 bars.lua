-- Smart Insert/Append region based on cursor position
local BARS = 6
local INITIAL_OFFSET_BARS = 4
local TOLERANCE = 0.000001
local proj = 0

local function almost_equal(a, b, tol)
  return math.abs(a - b) <= tol
end

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

local function find_region_starting_at(time_pos, regions)
  for i, r in ipairs(regions) do
    if almost_equal(r.start_pos, time_pos, TOLERANCE) then
      return i, r
    end
  end
  return nil, nil
end

local function find_region_containing(time_pos, regions)
  for i, r in ipairs(regions) do
    if time_pos > r.start_pos + TOLERANCE and time_pos < r.end_pos - TOLERANCE then
      return i, r
    end
  end
  return nil, nil
end

local function find_next_region_after(time_pos, regions)
  for i, r in ipairs(regions) do
    if r.start_pos > time_pos + TOLERANCE then
      return i, r
    end
  end
  return nil, nil
end

local function shift_regions_from(time_pos, shift_amount, regions)
  local to_shift = {}

  for _, r in ipairs(regions) do
    if r.start_pos >= time_pos - TOLERANCE then
      table.insert(to_shift, r)
    end
  end

  table.sort(to_shift, function(a, b)
    return a.start_pos > b.start_pos
  end)

  for _, r in ipairs(to_shift) do
    reaper.SetProjectMarker(
      r.id,
      true,
      r.start_pos + shift_amount,
      r.end_pos + shift_amount,
      r.name
    )
  end
end

local function shift_items_from(time_pos, shift_amount)
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    if pos >= time_pos - TOLERANCE then
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos + shift_amount)
    end
  end
end

local function add_region(start_pos, end_pos, name)
  reaper.AddProjectMarker2(proj, true, start_pos, end_pos, name or "", -1, 0)
end

local function focus_new_region(start_pos, end_pos)
  reaper.GetSet_LoopTimeRange(true, false, start_pos, end_pos, false)
  reaper.SetEditCurPos(start_pos, true, false)
  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local cursor_pos = reaper.GetCursorPosition()
local regions = get_all_regions()

local new_start = nil
local new_end = nil

if #regions == 0 then
  local start_pos = bars_to_time_from(0.0, INITIAL_OFFSET_BARS)
  local len = get_region_length_in_time(start_pos, BARS)

  add_region(start_pos, start_pos + len, BARS .. " bars")
  new_start = start_pos
  new_end = start_pos + len
else
  local last_region = get_last_region(regions)
  local start_idx, region_at_start = find_region_starting_at(cursor_pos, regions)
  local contain_idx, region_containing = find_region_containing(cursor_pos, regions)
  local next_idx, next_region = find_next_region_after(cursor_pos, regions)

  local insert_pos = nil
  local do_ripple = false

  -- HARD RULE:
  -- op/in/na laatste region = append
  if cursor_pos >= (last_region.start_pos - TOLERANCE) then
    insert_pos = last_region.end_pos
    do_ripple = false

  elseif region_at_start then
    -- begin van eerdere region = insert + ripple
    insert_pos = region_at_start.start_pos
    do_ripple = true

  elseif region_containing then
    -- in eerdere region = insert op begin van die region + ripple
    insert_pos = region_containing.start_pos
    do_ripple = true

  elseif next_region then
    -- tussen 2 regions = insert op cursor
    insert_pos = cursor_pos
    do_ripple = false

  else
    -- fallback
    insert_pos = last_region.end_pos
    do_ripple = false
  end

  local len = get_region_length_in_time(insert_pos, BARS)
  new_start = insert_pos
  new_end = insert_pos + len

  if do_ripple then
    shift_items_from(new_start, len)
    shift_regions_from(new_start, len, regions)
  end

  add_region(new_start, new_end, BARS .. " bars")
end

focus_new_region(new_start, new_end)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Smart insert/append region (" .. BARS .. " bars)", -1)
