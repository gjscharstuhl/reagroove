-- gjs - Delete items on selected tracks inside selected region
-- Region is determined by current time selection

local TOLERANCE = 0.000001
local proj = 0

local ts_start, ts_end =
  reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

if ts_end <= ts_start then
  reaper.ShowMessageBox(
    "Selecteer eerst een region via time selection / dubbelklik op region.",
    "Geen region geselecteerd",
    0
  )
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local item_count = reaper.CountMediaItems(proj)

for i = item_count - 1, 0, -1 do
  local item = reaper.GetMediaItem(proj, i)
  local track = reaper.GetMediaItem_Track(item)

  if reaper.IsTrackSelected(track) then
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = pos + len

    local overlaps_region =
      item_end > ts_start + TOLERANCE and
      pos < ts_end - TOLERANCE

    if overlaps_region then
      reaper.DeleteTrackMediaItem(track, item)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "gjs - Delete selected track items inside selected region",
  -1
)
