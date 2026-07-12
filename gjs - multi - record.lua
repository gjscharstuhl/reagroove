-- gjs - multi - record.lua

local SCRIPT_ID = "GJS_RecordAtTS"

local CMD_RECORD = 1013

local LED_TRACK_NAME = "recordled"
local BLINK_INTERVAL = 0.25

local active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
if not active_track then return end

fase  = tonumber(reaper.GetExtState("GJS_MULTI", "Page"))
if fase==2 then reaper.SetExtState("GJS_MULTI","FxRec","1",true) end

local proj = reaper.EnumProjects(active_track)
if not proj then return end

local main_proj = reaper.EnumProjects(0)

local function find_track_in_project(project, name)
  if not project then return nil end

  name = name:lower()

  for i = 0, reaper.CountTracks(project) - 1 do
    local tr = reaper.GetTrack(project, i)
    local _, tr_name = reaper.GetTrackName(tr)

    if tr_name:lower() == name then
      return tr
    end
  end

  return nil
end

local led_track = find_track_in_project(main_proj, LED_TRACK_NAME)

local function led(on)
  if not led_track then return end

  reaper.SetMediaTrackInfo_Value(led_track, "I_RECARM", on and 1 or 0)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local function run_cmd(cmd)
  reaper.Main_OnCommandEx(cmd, 0, proj)
end

local run_key = "active_run_" .. tostring(active_track)
local run_id = tostring(reaper.time_precise())

reaper.SetExtState(SCRIPT_ID, run_key, run_id, false)

local function stop_this_script()
  if reaper.GetExtState(SCRIPT_ID, run_key) == run_id then
    reaper.DeleteExtState(SCRIPT_ID, run_key, false)
  end

  led(false)
end

local function inside_time_selection()
  local pos = reaper.GetPlayPositionEx(proj)

  local ts_start, ts_end =
    reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

  if ts_end <= ts_start then
    return false
  end

  return pos >= ts_start and pos < ts_end
end

-- tweede druk tijdens recording = stoppen
if (reaper.GetPlayStateEx(proj) & 4) == 4 then
  reaper.DeleteExtState(SCRIPT_ID, run_key, false)
  run_cmd(CMD_RECORD)
  led(false)
  return
end

local blink_state = false
local last_blink = reaper.time_precise()
local reached_time_selection = false

local function watch()
  if reaper.GetExtState(SCRIPT_ID, run_key) ~= run_id then
    led(false)
    return
  end

  local state = reaper.GetPlayStateEx(proj)
  local is_recording = (state & 4) == 4

  -- record mode uit = script klaar + led uit
  if not is_recording then
    stop_this_script()
    return
  end

  if inside_time_selection() then
    reached_time_selection = true
  end

  if reached_time_selection then
    led(true)
    reaper.defer(watch)
    return
  end

  -- nog niet in time selection geweest = knipperen
  local now = reaper.time_precise()

  if now - last_blink >= BLINK_INTERVAL then
    blink_state = not blink_state
    led(blink_state)
    last_blink = now
  end

  reaper.defer(watch)
end

local function watch2()
  fxrec=tonumber(reaper.GetExtState("GJS_MULTI", "FxRec"))
  --reaper.ShowConsoleMsg(fxrec)
  if reaper.GetExtState(SCRIPT_ID, run_key) ~= run_id then
    led(false)
    return
  end


  if inside_time_selection() then
    reached_time_selection = true
  end

  if reached_time_selection then
    led(true)
    track = reaper.GetTrack(proj,0)
    reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 4) -- latch
    if fxrec==1 then reaper.defer(watch2) end
    return
  end

  -- nog niet in time selection geweest = knipperen
  local now = reaper.time_precise()

  if now - last_blink >= BLINK_INTERVAL then
    blink_state = not blink_state
    led(blink_state)
    last_blink = now
  end
  
  if fxrec==1 then reaper.defer(watch2) end
end


reaper.atexit(function()
  led(false)
  local fxtrack = reaper.GetTrack(proj,0)
  reaper.SetMediaTrackInfo_Value(fxtrack, "I_AUTOMODE", 0)
end)

led(false)

if fase~=2 then 
  run_cmd(CMD_RECORD)
  watch() 
else 
  watch2() 
  --reaper.ShowConsoleMsg("einde")
  local fxtrack = reaper.GetTrack(proj,0)
  reaper.SetMediaTrackInfo_Value(fxtrack, "I_AUTOMODE", 0)
end

