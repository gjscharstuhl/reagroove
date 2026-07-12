-- gjs - Transport LED status monitor
-- Keeps helper tracks muted/unmuted for ReaLearn LED feedback

local PLAY_TRACK_NAME = "GJS_LED_PLAY"
local RECORD_TRACK_NAME = "GJS_LED_RECORD"

local function find_or_create_track(name)
  local count = reaper.CountTracks(0)

  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if track_name == name then
      return track
    end
  end

  reaper.InsertTrackAtIndex(count, true)
  local track = reaper.GetTrack(0, count)

  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

  -- helper track verbergen
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)

  return track
end

local play_track = find_or_create_track(PLAY_TRACK_NAME)
local record_track = find_or_create_track(RECORD_TRACK_NAME)

local function main()
  local play_state = reaper.GetPlayState()

  local is_playing = (play_state & 1) == 1
  local is_recording = (play_state & 4) == 4

  -- Mute = LED aan, unmute = LED uit
  reaper.SetMediaTrackInfo_Value(play_track, "B_MUTE", is_playing and 1 or 0)
  reaper.SetMediaTrackInfo_Value(record_track, "B_MUTE", is_recording and 1 or 0)

  reaper.defer(main)
end

main()
