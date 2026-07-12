-- GJS Pattern Launcher - MIDI note to track/region + queued blink
local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")
local SCRIPT_ID = "GJS_PatternLauncherBlink"
local BLINK_INTERVAL = 0.25

local _, _, _, _, mode, resolution, val, valhw =
  reaper.get_action_context()

local note = math.floor((val / resolution) * 127 + 0.5)

 active_track = nil
local region_num = nil

local pc_to_region = {
  [0]  = 1,
  [2]  = 2,
  [3]  = 3,
  [4]  = 4,
  [5]  = 5,
  [7]  = 6,
  [9]  = 7,
  [10] = 8
}

if note == 1 then
  active_track = 8
  region_num = 7
elseif note == 2 then
  active_track = 8
  region_num = 8
else
  region_num = pc_to_region[note % 12]
  if not region_num then return end

  local base_note = 36
  active_track = math.floor((note - base_note) / 12) + 1
end

if active_track < 1 or active_track > 8 then return end

local pat_num = (active_track - 1) * 8 + region_num
local pat_track_name = "pat" .. pat_num

reaper.SetExtState("GJS_MULTI", "ActiveTrack", tostring(active_track), false)
reaper.SetExtState("GJS_MULTI", "TargetRegion", tostring(region_num), false)
page= tonumber(reaper.GetExtState("GJS_MULTI", "Page"))
if not page then page=1 end
lib.SelectTrackInFolder("tracks", active_track)
lib.arm(active_track,page)
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

local led_track = find_track_in_project(main_proj, pat_track_name)

local function led(on)
  if not led_track then return end

  if on then
    reaper.SetTrackSelected(led_track, true)
  else
    reaper.SetTrackSelected(led_track, false)
  end
  reaper.UpdateArrange()
end

local function current_region_number(project)
  local pos = reaper.GetPlayPositionEx(project)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(project)

  for i = 0, num_markers + num_regions - 1 do
    local _, is_region, start_pos, end_pos, _, rgn_num =
      reaper.EnumProjectMarkers2(project, i)

    if is_region and pos >= start_pos and pos < end_pos then
      return rgn_num
    end
  end

  return nil
end

-- native action:
-- Regions: Go to region XX after current region finishes playing
local wanted = string.format(
  "Regions: Go to region %02d after current region finishes playing",
  region_num
)

local cmd = nil

for i = 0, 70000 do
  local txt = reaper.kbd_getTextFromCmd(i, 0)
  if txt and txt:find(wanted, 1, true) then
    cmd = i
    break
  end
end

if cmd then
  reaper.Main_OnCommandEx(cmd, 0, proj)
end

-- time selection op target region zetten
local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)

for i = 0, num_markers + num_regions - 1 do
  local _, is_region, pos, rgnend, name, markrgnindexnumber =
    reaper.EnumProjectMarkers2(proj, i)

  if is_region and markrgnindexnumber == region_num then
    reaper.GetSet_LoopTimeRange2(proj, true, false, pos, rgnend, false)
    break
  end
end

reaper.UpdateArrange()

-- Blink alleen tijdens playback tot target region bereikt is
local run_key = "queued_" .. tostring(active_track)
local run_id = tostring(reaper.time_precise())

reaper.SetExtState(SCRIPT_ID, run_key, run_id, false)

local blink_state = false
local last_blink = reaper.time_precise()

local function watch()
  -- nieuwere queue voor dezelfde track overschrijft deze
  if reaper.GetExtState(SCRIPT_ID, run_key) ~= run_id then
    return
  end

  local state = reaper.GetPlayStateEx(proj)

  -- stopstand: niet knipperen
  if (state & 1) == 0 then
    return
  end

  local current = current_region_number(proj)

  -- aangekomen: solid aan laten
  if current == region_num then
    led(true)
    return
  end

  local now = reaper.time_precise()

  if now - last_blink >= BLINK_INTERVAL then
    blink_state = not blink_state
    led(blink_state)
    last_blink = now
  end

  reaper.defer(watch)
end

watch()
