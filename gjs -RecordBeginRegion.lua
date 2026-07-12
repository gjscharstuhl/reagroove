-- gjs - Live region record: start at region start, punch out to play, clean/glue
--
-- Gebruik:
-- 1e keer drukken: record starten bij begin van de actieve region.
-- Tijdens recording nog eens drukken: recording stopt, playback loopt door.
-- Daarna worden nieuw opgenomen items in de region opgeschoond:
--   crop active take -> glue
--
-- Doel:
-- Geen verborgen halve tweede loop-audio in de bron-WAV,
-- maar wel live kunnen doorspelen zonder Transport Stop.

local proj = 0
local TOLERANCE = 0.05

local SECTION = "gjs_region_record_live"
local KEY_REGION_START = "region_start"
local KEY_REGION_END = "region_end"
local KEY_ARMED_TRACKS = "armed_tracks"
local KEY_KNOWN_ITEMS = "known_items"

local CMD_RECORD = 1013
local CMD_UNSELECT_ALL_ITEMS = 40289
local CMD_CROP_TO_ACTIVE_TAKE = 40131 -- Take: Crop to active take in items
local CMD_GLUE_ITEMS = 40362          -- Item: Glue items, ignoring time selection

local region_start = nil
local region_end = nil

local function item_key(item)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  if ok then return guid end
  return tostring(item)
end

local function split_set(s)
  local set = {}
  if not s or s == "" then return set end
  for part in string.gmatch(s, "([^|]+)") do
    set[part] = true
  end
  return set
end

local function join_list(list)
  return table.concat(list, "|")
end

local function get_active_position()
  local play_state = reaper.GetPlayState()
  local is_playing = (play_state & 1) == 1
  local is_recording = (play_state & 4) == 4

  if is_playing or is_recording then
    return reaper.GetPlayPosition()
  else
    return reaper.GetCursorPosition()
  end
end

local function find_region_at_position(pos)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local ok, is_region, r_start, r_end, name, id = reaper.EnumProjectMarkers(i)
    if ok and is_region and pos >= r_start and pos < r_end then
      return r_start, r_end, name, id
    end
  end

  return nil
end

local function save_record_state(r_start, r_end)
  local armed_track_guids = {}
  local known_item_guids = {}

  local track_count = reaper.CountTracks(proj)
  for t = 0, track_count - 1 do
    local tr = reaper.GetTrack(proj, t)
    local recarm = reaper.GetMediaTrackInfo_Value(tr, "I_RECARM")

    if recarm == 1 then
      armed_track_guids[#armed_track_guids + 1] = reaper.GetTrackGUID(tr)

      local item_count = reaper.CountTrackMediaItems(tr)
      for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(tr, i)
        known_item_guids[#known_item_guids + 1] = item_key(item)
      end
    end
  end

  reaper.SetExtState(SECTION, KEY_REGION_START, tostring(r_start), false)
  reaper.SetExtState(SECTION, KEY_REGION_END, tostring(r_end), false)
  reaper.SetExtState(SECTION, KEY_ARMED_TRACKS, join_list(armed_track_guids), false)
  reaper.SetExtState(SECTION, KEY_KNOWN_ITEMS, join_list(known_item_guids), false)
end

local function clear_record_state()
  reaper.DeleteExtState(SECTION, KEY_REGION_START, false)
  reaper.DeleteExtState(SECTION, KEY_REGION_END, false)
  reaper.DeleteExtState(SECTION, KEY_ARMED_TRACKS, false)
  reaper.DeleteExtState(SECTION, KEY_KNOWN_ITEMS, false)
end

local function item_overlaps_region(item, r_start, r_end)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  return (pos + len) > r_start and pos < r_end
end

local function cleanup_recorded_items()
  local r_start = tonumber(reaper.GetExtState(SECTION, KEY_REGION_START) or "")
  local r_end = tonumber(reaper.GetExtState(SECTION, KEY_REGION_END) or "")

  if not r_start or not r_end then
    local pos = get_active_position()
    r_start, r_end = find_region_at_position(pos)
    if not r_start then return end
  end

  local armed_guid_set = split_set(reaper.GetExtState(SECTION, KEY_ARMED_TRACKS))
  local known_item_set = split_set(reaper.GetExtState(SECTION, KEY_KNOWN_ITEMS))

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  reaper.Main_OnCommand(CMD_UNSELECT_ALL_ITEMS, 0)

  local selected_new = 0
  local track_count = reaper.CountTracks(proj)

  for t = 0, track_count - 1 do
    local tr = reaper.GetTrack(proj, t)
    local tr_guid = reaper.GetTrackGUID(tr)

    -- Normaal: alleen tracks die armed waren toen recording startte.
    -- Fallback: als er geen saved state is, gebruik tracks die nu armed zijn.
    local use_track = armed_guid_set[tr_guid] or (next(armed_guid_set) == nil and reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1)

    if use_track then
      local item_count = reaper.CountTrackMediaItems(tr)

      for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(tr, i)
        local key = item_key(item)

        if not known_item_set[key] and item_overlaps_region(item, r_start, r_end) then
          reaper.SetMediaItemSelected(item, true)
          reaper.SetMediaItemInfo_Value(item, "D_POSITION", r_start)
          reaper.SetMediaItemInfo_Value(item, "D_LENGTH", r_end - r_start)
          selected_new = selected_new + 1
        end
      end
    end
  end

  if selected_new > 0 then
    reaper.Main_OnCommand(CMD_CROP_TO_ACTIVE_TAKE, 0)
    reaper.Main_OnCommand(CMD_GLUE_ITEMS, 0)
  end

  clear_record_state()

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Live punch out region recording and clean", -1)
end

local function cleanup_after_punchout_deferred(count)
  count = count or 0
  local state = reaper.GetPlayState()
  local now_recording = (state & 4) == 4

  -- Wacht heel kort tot REAPER de opname-items heeft aangemaakt/gefinalized.
  if now_recording and count < 30 then
    reaper.defer(function() cleanup_after_punchout_deferred(count + 1) end)
    return
  end

  if count < 3 then
    reaper.defer(function() cleanup_after_punchout_deferred(count + 1) end)
    return
  end

  cleanup_recorded_items()
end

local function start_record_and_watch()
  save_record_state(region_start, region_end)
  reaper.Main_OnCommand(CMD_RECORD, 0) -- Transport: Record
end

-- Als we al opnemen: punch out naar playback, niet stoppen.
local play_state = reaper.GetPlayState()
local is_recording = (play_state & 4) == 4

if is_recording then
  -- Transport: Record werkt als record-toggle: opname stopt, transport blijft spelen.
  reaper.Main_OnCommand(CMD_RECORD, 0)
  cleanup_after_punchout_deferred(0)
  return
end

local current_pos = get_active_position()
local region_name, region_id
region_start, region_end, region_name, region_id = find_region_at_position(current_pos)

if not region_start then
  return
end

-- Time selection op huidige region zetten
reaper.GetSet_LoopTimeRange(true, false, region_start, region_end, false)

local state = reaper.GetPlayState()
local is_playing = (state & 1) == 1

-- Als transport stil staat: naar begin region en meteen record
if not is_playing then
  reaper.SetEditCurPos(region_start, true, false)
  start_record_and_watch()
  return
end

-- Als hij speelt: wacht tot vlak voor einde region.
-- Met loop points linked to time selection start recording dan bij de volgende loop/begin region.
local function wait_for_region_start()
  local st = reaper.GetPlayState()
  local still_playing = (st & 1) == 1
  local now_recording = (st & 4) == 4

  if now_recording or not still_playing then
    return
  end

  local pos = reaper.GetPlayPosition()
  local trigger_pos = region_end - TOLERANCE

  if pos >= trigger_pos then
    start_record_and_watch()
    return
  end

  reaper.defer(wait_for_region_start)
end

wait_for_region_start()

