-- GJS - Resize all 8 regions in all project tabs to selected bar length
-- bar lengte komt uit geselecteerde track onder folder "bars" in hoofdproject/tab 1

local TOLERANCE = 0.000001
local REGION_COUNT = 8

local main_proj = reaper.EnumProjects(0)

local function get_regions_folder_track_number()
  for i = 0, reaper.CountTracks(main_proj) - 1 do
    local tr = reaper.GetTrack(main_proj, i)
    local _, name = reaper.GetTrackName(tr)

    if name:lower() == "bars" then
      return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
    end
  end
end

local function get_selected_bar_track()
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
end

local bar_track = get_selected_bar_track()
if not bar_track then return end

local tracknr = reaper.GetMediaTrackInfo_Value(bar_track, "IP_TRACKNUMBER")
local foldernr = get_regions_folder_track_number()
if not tracknr or not foldernr then return end

local BARS = tracknr - foldernr
if BARS <= 0 then return end

local function get_all_regions(proj)
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)

  for i = 0, num_markers + num_regions - 1 do
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
  for i = reaper.CountMediaItems(proj) - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    if pos >= time_pos - TOLERANCE then
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos + shift_amount)
    end
  end
end

local function trim_items_from_old_region_to_new_region(proj, old_start, old_end, new_start, new_end)
  for i = reaper.CountMediaItems(proj) - 1, 0, -1 do
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
          for t = 0, reaper.CountTakes(item) - 1 do
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

local function resize_region(proj, region_index)
  local regions = get_all_regions(proj)
  local region = regions[region_index]
  if not region then return false end

  local old_start = region.start_pos
  local old_end = region.end_pos
  local new_end = bars_to_time_from(proj, old_start, BARS)
  local delta = new_end - old_end

  if math.abs(delta) <= TOLERANCE then return false end

  trim_items_from_old_region_to_new_region(proj, old_start, old_end, old_start, new_end)
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

  return true
end

reaper.PreventUIRefresh(1)

local proj_idx = 0

while true do
  local proj = reaper.EnumProjects(proj_idx)
  if not proj then break end

  local changed = false
  reaper.Undo_BeginBlock2(proj)

  for region_nr = REGION_COUNT, 1, -1 do
    if resize_region(proj, region_nr) then
      changed = true
    end
  end

  reaper.Undo_EndBlock2(
    proj,
    changed and ("Resize all 8 regions to " .. BARS .. " bars") or "No regions resized",
    -1
  )

  proj_idx = proj_idx + 1
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
