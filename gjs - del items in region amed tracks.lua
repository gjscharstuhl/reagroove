-- gjs - Delete items on armed tracks inside active region
-- Active region = region under play cursor if playing, otherwise edit cursor

local TOLERANCE = 0.000001
local proj = 0

local play_state = reaper.GetPlayState()
local is_playing_or_recording = (play_state & 1) == 1 or (play_state & 4) == 4

local cursor_pos

if is_playing_or_recording then
  cursor_pos = reaper.GetPlayPosition()
else
  cursor_pos = reaper.GetCursorPosition()
end

local region_start = nil
local region_end = nil
local region_name = nil

local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
local total = num_markers + num_regions

for i = 0, total - 1 do
  local ok, is_region, pos, rgnend, name, id =
    reaper.EnumProjectMarkers(i)

  if ok and is_region then
    if cursor_pos >= pos - TOLERANCE and cursor_pos < rgnend - TOLERANCE then
      region_start = pos
      region_end = rgnend
      region_name = name
      break
    end
  end
end

if not region_start then
  reaper.ShowMessageBox(
    "Geen actieve region gevonden onder de cursor/play cursor.",
    "Geen actieve region",
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

  local armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")

  if armed == 1 then
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = pos + len

    local overlaps_region =
      item_end > region_start + TOLERANCE and
      pos < region_end - TOLERANCE

    if overlaps_region then
      reaper.DeleteTrackMediaItem(track, item)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "gjs - Delete armed track items inside active region",
  -1
)
