-- gjs - Play clean: cancel pending record, clear record LED, then play

reaper.SetExtState("gjs_transport", "record_pending", "0", false)

local function set_led_track(name, on)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name =
      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if track_name == name then
      reaper.SetMediaTrackInfo_Value(track, "B_MUTE", on and 1 or 0)
      return
    end
  end
end

-- record LED altijd uit
set_led_track("GJS_LED_RECORD", false)

local state = reaper.GetPlayState()
local is_recording = (state & 4) == 4

-- als REAPER nog in record hangt: eerst stoppen
if is_recording then
  reaper.Main_OnCommand(1016, 0) -- Transport: Stop
end

-- starten met clean play
reaper.Main_OnCommand(1007, 0) -- Transport: Play

reaper.UpdateArrange()
