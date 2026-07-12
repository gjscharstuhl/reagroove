-- GJS - Resize selected region to 4 bars, trim items to region, and ripple following regions/items

local BARS = 6

local TOLERANCE = 0.000001
local proj = 0

local function almost_equal(a, b)
  return math.abs(a - b) <= TOLERANCE
end

local function get_qn_per_bar_at_time(time)
  local num, denom = reaper.TimeMap_GetTimeSigAtTime(proj, time)
  if not num or num < 1 then num = 4 end
  if not denom or denom < 1 then denom = 4 end
  return num * (4 / denom)
end

local function bars_to_time_from(start_time, bars)
  local start_qn = reaper.TimeMap2_timeToQN(proj, start_time)
  local end_qn = start_qn + bars * get_qn_per_bar_at_time(start_time)
  return reaper.TimeMap2_QNToTime(proj, end_qn)
end

local function get_all_regions()
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, id = reaper.EnumProjectMarkers(i)
    if ok and isrgn then
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

local function find_region_by_time_selection(ts_start, ts_end, regions)
  for i, r in ipairs(regions) do
    if almost_equal(r.start_pos, ts_start) and almost_equal(r.end_pos, ts_end) then
      return i, r
    end
  end
  return nil, nil
end

local function shift_regions_after(region_index, shift_amount, regions)
  for i = #regions, region_index + 1, -1 do
    local r = regions[i]
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

local function trim_items_from_old_region_to_new_region(old_start, old_end, new_start, new_end)
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)

    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_pos + item_len

    local was_in_old_region = item_end > old_start + TOLERANCE and item_pos < old_end - TOLERANCE

    if was_in_old_region then
      local new_item_pos = math.max(item_pos, new_start)
      local new_item_end = math.min(item_end, new_end)
      local new_item_len = new_item_end - new_item_pos

      if new_item_len <= TOLERANCE then
        reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
      else
        local trim_left_amount = new_item_pos - item_pos

        if trim_left_amount > TOLERANCE then
          local take_count = reaper.CountTakes(item)

          for t = 0, take_count - 1 do
            local take = reaper.GetTake(item, t)

            if take then
              local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
              local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

              reaper.SetMediaItemTakeInfo_Value(
                take,
                "D_STARTOFFS",
                startoffs + (trim_left_amount * playrate)
              )
            end
          end
        end

        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_item_pos)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_item_len)
      end
    end
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
local regions = get_all_regions()

local region_index, region = find_region_by_time_selection(ts_start, ts_end, regions)

if region then
  local old_start = region.start_pos
  local old_end = region.end_pos
  local new_end = bars_to_time_from(old_start, BARS)
  local delta = new_end - old_end

  -- items binnen oude region trimmen naar nieuwe region
  trim_items_from_old_region_to_new_region(old_start, old_end, old_start, new_end)

  -- items rechts van oude einde verschuiven
  shift_items_from(old_end, delta)

  -- geselecteerde region resize
  reaper.SetProjectMarker(
    region.id,
    true,
    old_start,
    new_end,
    region.name
  )

  -- alle regions rechts ervan mee schuiven
  shift_regions_after(region_index, delta, regions)

  -- time selection op aangepaste region
  reaper.GetSet_LoopTimeRange(true, false, old_start, new_end, false)

  -- cursor naar begin
  reaper.SetEditCurPos(old_start, true, false)
else
  reaper.PreventUIRefresh(-1)
  return
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Resize selected region to " .. BARS .. " bars and trim items", -1)
