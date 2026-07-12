-- gjs - Set active project slot LED
-- Zet 1 slot aan en alle andere slots uit via helper tracks

local ACTIVE_SLOT = 2
local NUM_SLOTS = 16
local TRACK_PREFIX = "GJS_LED_SLOT_"

local function two_digits(n)
  return string.format("%02d", n)
end

local function find_or_create_track(name)
  local track_count = reaper.CountTracks(0)

  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name =
      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if track_name == name then
      return track
    end
  end

  reaper.InsertTrackAtIndex(track_count, true)
  local track = reaper.GetTrack(0, track_count)

  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

  -- helper track verbergen
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)

  return track
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for n = 1, NUM_SLOTS do
  local track = find_or_create_track(TRACK_PREFIX .. two_digits(n))

  if n == ACTIVE_SLOT then
    reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 1) -- LED aan
  else
    reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0) -- LED uit
  end
end

reaper.SetExtState("gjs_slots", "active_slot", tostring(ACTIVE_SLOT), true)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("gjs - Set active project slot LED " .. ACTIVE_SLOT, -1)
