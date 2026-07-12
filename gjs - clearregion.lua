-- gjs - Delete all items inside selected region
-- Region is determined by current time selection

local TOLERANCE = 0.000001
local proj = 0

local function almost_equal(a, b)
  return math.abs(a - b) <= TOLERANCE
end

local function get_all_regions()
  local regions = {}

  local _, num_markers, num_regions =
    reaper.CountProjectMarkers(proj)

  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, id =
      reaper.EnumProjectMarkers(i)

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

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local ts_start, ts_end =
  reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

local regions = get_all_regions()

local region =
  find_region_by_time_selection(ts_start, ts_end, regions)

if not region then
  reaper.ShowMessageBox(
    "Selecteer eerst een region via time selection / dubbelklik op region.",
    "Geen geselecteerde region",
    0
  )

  reaper.PreventUIRefresh(-1)
  return
end

local item_count = reaper.CountMediaItems(proj)

for i = item_count - 1, 0, -1 do

  local item = reaper.GetMediaItem(proj, i)

  local item_pos =
    reaper.GetMediaItemInfo_Value(item, "D_POSITION")

  local item_len =
    reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local item_end = item_pos + item_len

  local overlaps_region =
    item_end > region.start_pos + TOLERANCE and
    item_pos < region.end_pos - TOLERANCE

  if overlaps_region then
    local track = reaper.GetMediaItem_Track(item)
    reaper.DeleteTrackMediaItem(track, item)
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "gjs - Delete items inside selected region",
  -1
)
