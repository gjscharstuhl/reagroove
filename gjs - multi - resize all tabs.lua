-- GJS - Resize stored region in all project tabs to selected bar length
-- bars selectie uit hoofdproject/tab 1
-- target region via GJS_MULTI / Region

local TOLERANCE = 0.000001

local main_proj = reaper.EnumProjects(0)

local REGION_NR = tonumber(reaper.GetExtState("GJS_MULTI", "Region"))
if not REGION_NR then return end

local function get_regions_folder_track_number()
  for i = 0, reaper.CountTracks(main_proj) - 1 do
    local tr = reaper.GetTrack(main_proj, i)
    local _, name = reaper.GetTrackName(tr)

    if name:lower() == "bars" then
      return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
    end
  end

  return nil
end

local function get_selected_region_track()
  local folder_nr = get_regions_folder_track_number()
  if not folder_nr then return nil end

  local tr_idx = folder_nr

  while tr_idx < reaper.CountTracks(main_proj) do
    local tr = reaper.GetTrack(main_proj, tr_idx)
    if not tr then break end

    if reaper.IsTrackSelected(tr) then
      return tr
    end

    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if depth < 0 then break end

    tr_idx = tr_idx + 1
  end

  return nil
end

local region_track = get_selected_region_track()
if not region_track then return end

local tracknr = reaper.GetMediaTrackInfo_Value(region_track, "IP_TRACKNUMBER")
local regionfoldernr = get_regions_folder_track_number()

if not tracknr or not regionfoldernr then return end

local BARS = tracknr - regionfoldernr
if BARS <= 0 then return end

local function get_qn_per_bar_at_time(proj, time)
  local num, denom = reaper.TimeMap_GetTimeSigAtTime(proj, time)

  if not num or num < 1 then num = 4 end
  if not denom or denom < 1 then denom = 4 end

  return num * (4 / denom)
end

local function bars_to_time_from(proj, start_time, bars)
  local start_qn = reaper.TimeMap2_timeToQN(proj, start_time)
  local end_qn = start_qn + bars * get_qn_per_bar_at_time(proj, start_time)

  return reaper.TimeMap2_QNToTime(proj, end_qn)
end

local function get_all_regions(proj)
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, id =
      reaper.EnumProjectMarkers2(proj, i)

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

local function find_region_by_number(regions)
  local r = regions[REGION_NR]
  if not r then return nil, nil end

  return REGION_NR, r
end

local function shift_regions_after(proj, region_index, shift_amount, regions)
  for i = #regions, region_index + 1, -1 do
    local r = regions[i]

    reaper.SetProjectMarker2(
      proj,
      r.id,
      true,
      r.start_pos + shift_amount,
      r.end_pos + shift_amount,
      r.name
    )
  end
end

local function shift_items_from(proj, time_pos, shift_amount)
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    if pos >= time_pos - TOLERANCE then
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos + shift_amount)
    end
  end
end

local function trim_items_from_old_region_to_new_region(proj, old_start, old_end, new_start, new_end)
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)

    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_pos + item_len

    local was_in_old_region =
      item_end > old_start + TOLERANCE and
      item_pos < old_end - TOLERANCE

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
                startoffs + trim_left_amount * playrate
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

reaper.PreventUIRefresh(1)

local proj_idx = 0

while true do
  local proj = reaper.EnumProjects(proj_idx)
  if not proj then break end

  local regions = get_all_regions(proj)
  local region_index, region = find_region_by_number(regions)

  if region then
    reaper.Undo_BeginBlock2(proj)

    local old_start = region.start_pos
    local old_end = region.end_pos
    local new_end = bars_to_time_from(proj, old_start, BARS)
    local delta = new_end - old_end

    trim_items_from_old_region_to_new_region(
      proj,
      old_start,
      old_end,
      old_start,
      new_end
    )

    shift_items_from(proj, old_end, delta)

    reaper.SetProjectMarker2(
      proj,
      region.id,
      true,
      old_start,
      new_end,
      region.name
    )

    shift_regions_after(proj, region_index, delta, regions)

    reaper.GetSet_LoopTimeRange2(proj, true, false, old_start, new_end, false)
    reaper.SetEditCurPos2(proj, old_start, false, false)

    reaper.Undo_EndBlock2(
      proj,
      "Resize region " .. REGION_NR .. " to " .. BARS .. " bars",
      -1
    )
  end

  proj_idx = proj_idx + 1
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
