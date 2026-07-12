-- gjs - bar display + region length marker
-- target project bepaald door GJS_MULTI / ActiveTrack
-- bar-led tracks zitten in hoofdproject/tab 1

local SCRIPT_ID = "GJS_BAR_DISPLAY"
local PAUSE = "GJS_BAR_PAUSE"

local BAR_PREFIX = "bar"
local UPDATE_INTERVAL = 0.05

local main_proj = reaper.EnumProjects(0)

local last_update = 0
local last_bar = nil
local last_size = nil

local DEBUG = false

local function log(msg)
  if DEBUG then
    reaper.ShowConsoleMsg(tostring(msg) .. "\n")
  end
end

reaper.ClearConsole()
-- if reaper.GetExtState(SCRIPT_ID, "enabled") == "1" then return end

reaper.SetExtState(SCRIPT_ID, "enabled", "1", false)
reaper.SetExtState(PAUSE, "enabled", "0", false)

local function get_target_project()
  local active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
  if not active_track then return nil end

  -- ActiveTrack 1 = tab 2
  -- ActiveTrack 2 = tab 3
  return reaper.EnumProjects(active_track)
end

local function find_track_by_name(proj, name)
  if not proj then return nil end

  name = name:lower()

  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    local _, tr_name = reaper.GetTrackName(tr)

    if tr_name:lower() == name then
      return tr
    end
  end

  return nil
end

local function set_led_track(track_name, on)
  local tr = find_track_by_name(main_proj, track_name)
  if not tr then return end

  reaper.SetTrackSelected(tr, on)
end

local function unselect()
  if last_bar then
    set_led_track(BAR_PREFIX .. tostring(last_bar), false)
  end

  if last_size and last_size ~= last_bar then
    set_led_track(BAR_PREFIX .. tostring(last_size), false)
  end

  last_bar = nil
  last_size = nil
end

local function get_current_region(proj)
  local pos = reaper.GetPlayPositionEx(proj)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)

  for i = 0, num_markers + num_regions - 1 do
    local _, is_region, rgn_start, rgn_end, name, region_nr =
      reaper.EnumProjectMarkers2(proj, i)

    if is_region and pos >= rgn_start and pos < rgn_end then
      return region_nr, rgn_start, rgn_end
    end
  end

  return nil
end

local function get_measure_number(proj, time)
  local _, measure = reaper.TimeMap2_timeToBeats(proj, time)
  return measure
end

local function refresh_leds(current_bar, region_size)
  if last_bar and last_bar ~= region_size then
    set_led_track(BAR_PREFIX .. tostring(last_bar), false)
  end

  if last_size and last_size ~= current_bar then
    set_led_track(BAR_PREFIX .. tostring(last_size), false)
  end

  if region_size then
    set_led_track(BAR_PREFIX .. tostring(region_size), true)
  end

  if current_bar then
    set_led_track(BAR_PREFIX .. tostring(current_bar), true)
  end

  last_bar = current_bar
  last_size = region_size
end

local function loop()
  local proj = get_target_project()
  log(proj)
  if not proj then
    unselect()
    return
  end

  local now = reaper.time_precise()

  if now - last_update >= UPDATE_INTERVAL then
    local region_nr, rgn_start, rgn_end = get_current_region(proj)
  
    if region_nr then
      local pos = reaper.GetPlayPositionEx(proj)
      
      
      local current_measure = get_measure_number(proj, pos)
      local start_measure = get_measure_number(proj, rgn_start)
      local end_measure = get_measure_number(proj, rgn_end)

      local current_bar = current_measure - start_measure + 1
      local region_size = end_measure - start_measure

      refresh_leds(current_bar, region_size)
      reaper.UpdateArrange()
    else
      unselect()
    end

    last_update = now
  end
end

reaper.atexit(function()
  unselect()
  reaper.DeleteExtState(SCRIPT_ID, "enabled", false)
end)

local function bars()
  if reaper.GetExtState(PAUSE, "enabled") == "0" then
    loop()
  else
    unselect()
  end

  if reaper.GetExtState(SCRIPT_ID, "enabled") == "1" then
    reaper.defer(bars)
  else
    unselect()
  end
end

bars()
