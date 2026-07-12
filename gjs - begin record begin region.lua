-- gjs - record at time selection start + blinking recordled mute
-- tweede druk tijdens recording = punch-out + previous take + alle oude loops stoppen

local SCRIPT_ID = "GJS_RecordAtTS"

local CMD_RECORD = 1013
local CMD_PREV_TAKE = 42612
local TOL = 0.25

local LED_TRACK_NAME = "recordled"
local BLINK_INTERVAL = 0.25

local run_id = tostring(reaper.time_precise())
reaper.SetExtState(SCRIPT_ID, "active_run", run_id, false)

local function find_track(name)
  name = name:lower()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tr_name = reaper.GetTrackName(tr)
    if tr_name:lower() == name then return tr end
  end
end

local led_track = find_track(LED_TRACK_NAME)

local function led(on)
  if not led_track then return end
  reaper.SetMediaTrackInfo_Value(led_track, "B_MUTE", on and 1 or 0)
  reaper.UpdateArrange()
end

local function stop_this_script()
  if reaper.GetExtState(SCRIPT_ID, "active_run") == run_id then
    reaper.DeleteExtState(SCRIPT_ID, "active_run", false)
  end
  led(false)
end

-- tweede druk tijdens recording
if (reaper.GetPlayState() & 4) == 4 then
  reaper.DeleteExtState(SCRIPT_ID, "active_run", false)

  reaper.Main_OnCommand(CMD_RECORD, 0)
  reaper.Main_OnCommand(CMD_PREV_TAKE, 0)

  led(false)
  return
end

local ts_start = select(1, reaper.GetSet_LoopTimeRange(false, false, 0, 0, false))

local blink_state = false
local last_blink = reaper.time_precise()
local record_started = false

local function watch()
  -- als er een nieuwe run is of alles is gestopt: deze oude loop beeindigen
  if reaper.GetExtState(SCRIPT_ID, "active_run") ~= run_id then
    led(false)
    return
  end

  local state = reaper.GetPlayState()
  local pos = reaper.GetPlayPosition()

  -- gestopt voordat recording begon
  if not record_started and (state & 1) == 0 and (state & 4) == 0 then
    reaper.Main_OnCommand(CMD_PREV_TAKE, 0)
    stop_this_script()
    return
  end

  -- recording 1 keer starten bij time selection start
  if not record_started
    and (state & 4) == 0
    and pos >= ts_start
    and pos <= ts_start + TOL
  then
    reaper.Main_OnCommand(CMD_RECORD, 0)
    record_started = true
    led(true)
  end

  state = reaper.GetPlayState()

  if record_started then
    -- na recording-start: vast aan zolang hij recordt, anders klaar
    if (state & 4) == 4 then
      led(true)
    else
      stop_this_script()
      return
    end
  else
    -- pending: knipperen
    local now = reaper.time_precise()
    if now - last_blink >= BLINK_INTERVAL then
      blink_state = not blink_state
      led(blink_state)
      last_blink = now
    end
  end

  reaper.defer(watch)
end

reaper.atexit(function()
  if reaper.GetExtState(SCRIPT_ID, "active_run") == run_id then
    led(false)
  end
end)

watch()
