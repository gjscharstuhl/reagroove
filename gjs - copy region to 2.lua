-- gjs - Copy items from selected region to region X
-- Destination region is cleared first

local target_region_number = 2

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

local function find_region_by_number(region_number, regions)
  for _, r in ipairs(regions) do
    local _, _, _, _, _, id =
      reaper.EnumProjectMarkers3(proj, r.id)

    if r.id == region_number then
      return r
    end
  end

  return nil
end

local function delete_items_in_region(region)
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)

    local pos =
      reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    local len =
      reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

    local item_end = pos + len

    local overlaps =
      item_end > region.start_pos + TOLERANCE and
      pos < region.end_pos - TOLERANCE

    if overlaps then
      local track = reaper.GetMediaItem_Track(item)
      reaper.DeleteTrackMediaItem(track, item)
    end
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local ts_start, ts_end =
  reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

local regions = get_all_regions()

local source_region =
  find_region_by_time_selection(ts_start, ts_end, regions)

if not source_region then
  reaper.ShowMessageBox(
    "Selecteer eerst een source region via time selection.",
    "Geen source region",
    0
  )

  reaper.PreventUIRefresh(-1)
  return
end

local target_region = nil

for _, r in ipairs(regions) do
  if r.id == target_region_number then
    target_region = r
    break
  end
end

if not target_region then
  reaper.ShowMessageBox(
    "Target region niet gevonden.",
    "Fout",
    0
  )

  reaper.PreventUIRefresh(-1)
  return
end

-- target eerst leegmaken
delete_items_in_region(target_region)

local source_start = source_region.start_pos
local target_start = target_region.start_pos

local offset = target_start - source_start

local item_count = reaper.CountMediaItems(proj)

-- items kopiëren
for i = 0, item_count - 1 do

  local item = reaper.GetMediaItem(proj, i)

  local pos =
    reaper.GetMediaItemInfo_Value(item, "D_POSITION")

  local len =
    reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local item_end = pos + len

  local inside_source =
    item_end > source_region.start_pos + TOLERANCE and
    pos < source_region.end_pos - TOLERANCE

  if inside_source then

    reaper.SelectAllMediaItems(proj, false)
    reaper.SetMediaItemSelected(item, true)

    reaper.Main_OnCommand(40698, 0) -- copy items

    local track = reaper.GetMediaItem_Track(item)
    reaper.SetOnlyTrackSelected(track)

    reaper.SetEditCurPos(pos + offset, false, false)

    reaper.Main_OnCommand(42398, 0) -- paste items/tracks

  end
end

reaper.SelectAllMediaItems(proj, false)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "gjs - Copy region items to region " .. target_region_number,
  -1
)
