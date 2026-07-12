-- gjs - bar display + region length marker
-- selecteert barX voor huidige maat
-- selecteert ook barY voor lengte/einde van region

local SCRIPT_ID = "GJS_BAR_DISPLAY"
local PAUSE="GJS_BAR_PAUSE"
local BAR_PREFIX = "bar"
local UPDATE_INTERVAL = 0.05

local last_update = 0
local last_bar = nil
local last_size = nil

--if reaper.GetExtState(SCRIPT_ID, "enabled") == "1" then return end
reaper.SetExtState(SCRIPT_ID, "enabled", "1", false)
reaper.SetExtState(PAUSE, "enabled", "0", false)
local function find_track_by_name(name)
  name = name:lower()

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tr_name = reaper.GetTrackName(tr)

    if tr_name:lower() == name then
      return tr
    end
  end

  return nil
end

local function set_led_track(track_name, on)
  local tr = find_track_by_name(track_name)
  if not tr then return end

  reaper.SetTrackSelected(tr, on)
end

local function get_current_region()
  local pos = reaper.GetPlayPosition()
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)

  for i = 0, num_markers + num_regions - 1 do
    local _, is_region, rgn_start, rgn_end, name, region_nr =
      reaper.EnumProjectMarkers(i)

    if is_region and pos >= rgn_start and pos < rgn_end then
      return region_nr, rgn_start, rgn_end
    end
  end

  return nil
end

local function unselect()
  if last_bar then
    set_led_track(BAR_PREFIX .. tostring(last_bar), false)
  end

  if last_size and last_size ~= last_bar then
    set_led_track(BAR_PREFIX .. tostring(last_size), false)
  end

end

local function get_measure_number(time)
  local _, measure = reaper.TimeMap2_timeToBeats(0, time)
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

 function loop()

  local now = reaper.time_precise()
  
  if now - last_update >= UPDATE_INTERVAL then
    local region_nr, rgn_start, rgn_end = get_current_region()
 
    if region_nr then
      local pos = reaper.GetPlayPosition()

      local current_measure = get_measure_number(pos)
      local start_measure = get_measure_number(rgn_start)
      local end_measure = get_measure_number(rgn_end)

      local current_bar = current_measure - start_measure + 1
      local region_size = end_measure - start_measure

      refresh_leds(current_bar, region_size)
      reaper.UpdateArrange()
    end

    last_update = now
  end

  -- reaper.defer(loop) 
end

reaper.atexit(function()
  unselect()
end)

function bars()

    if reaper.GetExtState(PAUSE, "enabled") == "0" then
        loop()
    else
        unselect()
    end

    if reaper.GetExtState(SCRIPT_ID, "enabled") == "1" then
        reaper.defer(bars)
    end

end

bars()
