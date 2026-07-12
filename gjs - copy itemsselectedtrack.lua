
-- gjs - Copy items from selected region to region X
-- Only selected track
-- Destination region is cleared first, only on selected track

local target_region_number = 1

local TOLERANCE = 0.000001
local proj = 0

local selected_track = reaper.GetSelectedTrack(proj, 0)
if not selected_track then return end

------------------------------------------------------------
-- Helper functions
------------------------------------------------------------

local function almost_equal(a, b)
  return math.abs(a - b) <= TOLERANCE
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

  return regions
end

local function find_region_by_time_selection(ts_start, ts_end, regions)
  for _, r in ipairs(regions) do
    if almost_equal(r.start_pos, ts_start)
      and almost_equal(r.end_pos, ts_end) then
      return r
    end
  end

  return nil
end

local function find_region_by_number(region_number, regions)
  for _, r in ipairs(regions) do
    if r.id == region_number then
      return r
    end
  end

  return nil
end

local function item_overlaps_region(item, region)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = pos + len

  return item_end > region.start_pos + TOLERANCE
    and pos < region.end_pos - TOLERANCE
end

local function delete_items_in_region_on_track(region, track)
  for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)

    if item_overlaps_region(item, region) then
      reaper.DeleteTrackMediaItem(track, item)
    end
  end
end

local function collect_source_items_on_track(source_region, track)
  local items = {}

  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)

    if item_overlaps_region(item, source_region) then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local ok, chunk = reaper.GetItemStateChunk(item, "", false)

      if ok then
        table.insert(items, {
          pos = pos,
          chunk = chunk
        })
      end
    end
  end

  return items
end

local function set_chunk_position(chunk, new_pos)
  return chunk:gsub(
    "POSITION [^\n]+",
    "POSITION " .. string.format("%.15f", new_pos),
    1
  )
end

local function copy_track_envelopes(track, source_region, target_region)
  local offset = target_region.start_pos - source_region.start_pos
  local env_count = reaper.CountTrackEnvelopes(track)

  for e = 0, env_count - 1 do
    local env = reaper.GetTrackEnvelope(track, e)

    reaper.DeleteEnvelopePointRange(
      env,
      target_region.start_pos,
      target_region.end_pos
    )

    local points = {}
    local point_count = reaper.CountEnvelopePoints(env)

    for p = 0, point_count - 1 do
      local ok, time, value, shape, tension, selected =
        reaper.GetEnvelopePoint(env, p)

      if ok
        and time >= source_region.start_pos
        and time <= source_region.end_pos then
        table.insert(points, {
          time = time + offset,
          value = value,
          shape = shape,
          tension = tension,
          selected = false
        })
      end
    end

    for _, pt in ipairs(points) do
      reaper.InsertEnvelopePoint(
        env,
        pt.time,
        pt.value,
        pt.shape,
        pt.tension,
        pt.selected,
        true
      )
    end

    reaper.Envelope_SortPoints(env)
  end
end

------------------------------------------------------------
-- Main
------------------------------------------------------------

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local ts_start, ts_end =
  reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

local regions = get_all_regions()

local source_region =
  find_region_by_time_selection(ts_start, ts_end, regions)

local target_region =
  find_region_by_number(target_region_number, regions)

if not source_region or not target_region then
  reaper.PreventUIRefresh(-1)
  return
end

local source_items =
  collect_source_items_on_track(source_region, selected_track)

local offset = target_region.start_pos - source_region.start_pos

delete_items_in_region_on_track(target_region, selected_track)

for _, data in ipairs(source_items) do
  local new_item = reaper.AddMediaItemToTrack(selected_track)
  local new_chunk = set_chunk_position(data.chunk, data.pos + offset)

  reaper.SetItemStateChunk(new_item, new_chunk, false)
end

copy_track_envelopes(selected_track, source_region, target_region)

reaper.SelectAllMediaItems(proj, false)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "gjs - Copy selected track region items to region " .. target_region_number,
  -1
)
