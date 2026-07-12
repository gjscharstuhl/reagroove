-- gjs - Start recording at next start of active region + clean/glue after stop
-- Active region = region under play cursor if playing, otherwise edit cursor
--
-- Wat deze versie extra doet:
-- 1. Zet time selection op de actieve region.
-- 2. Start recording aan het begin van de region / bij de volgende loop.
-- 3. Blijft op de achtergrond wachten tot je stopt met opnemen.
-- 4. Selecteert alleen nieuw opgenomen items op armed tracks in deze region.
-- 5. Cropt naar de actieve take en glue't het item, zodat verborgen halve loop-audio uit de WAV verdwijnt.

local TOLERANCE = 0.05 -- trigger window in seconds
local proj = 0

local CMD_RECORD = 1013
local CMD_CROP_TO_ACTIVE_TAKE = 40131 -- Take: Crop to active take in items
local CMD_GLUE_ITEMS = 40362          -- Item: Glue items, ignoring time selection

local region_start = nil
local region_end = nil
local known_items = {}
local armed_tracks = {}

local function item_key(item)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  if ok then return guid end
  return tostring(item)
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
    if ok and is_region then
      if pos >= r_start and pos < r_end then
        return r_start, r_end, name, id
      end
    end
  end

  return nil
end

local function remember_existing_items_and_armed_tracks()
  known_items = {}
  armed_tracks = {}

  local track_count = reaper.CountTracks(proj)

  for t = 0, track_count - 1 do
    local tr = reaper.GetTrack(proj, t)
    local recarm = reaper.GetMediaTrackInfo_Value(tr, "I_RECARM")

    if recarm == 1 then
      armed_tracks[tr] = true

      local item_count = reaper.CountTrackMediaItems(tr)
      for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(tr, i)
        known_items[item_key(item)] = true
      end
    end
  end
end

local function item_overlaps_region(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = pos + len

  return item_end > region_start and pos < region_end
end

local function cleanup_new_recorded_items()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local old_selected = {}
  local old_count = reaper.CountSelectedMediaItems(proj)
  for i = 0, old_count - 1 do
    old_selected[#old_selected + 1] = reaper.GetSelectedMediaItem(proj, i)
  end

  reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items

  local selected_new = 0

  for tr, _ in pairs(armed_tracks) do
    local item_count = reaper.CountTrackMediaItems(tr)

    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(tr, i)
      local key = item_key(item)

      if not known_items[key] and item_overlaps_region(item) then
        reaper.SetMediaItemSelected(item, true)

        -- Forceer item zelf exact naar region-lengte.
        -- Dit verandert nog niet de bron-WAV; dat doet Glue hieronder.
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", region_start)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", region_end - region_start)

        selected_new = selected_new + 1
      end
    end
  end

  if selected_new > 0 then
    -- Gooi andere takes weg en maak een nieuwe schone WAV van precies de item-lengte.
    -- Let op: dit is destructief op take-niveau voor de nieuw opgenomen items.
    reaper.Main_OnCommand(CMD_CROP_TO_ACTIVE_TAKE, 0)
    reaper.Main_OnCommand(CMD_GLUE_ITEMS, 0)
  end

  -- Laat de nieuw gemaakte/glued items geselecteerd staan.
  -- Dat is handig: je ziet meteen wat de script heeft opgeschoond.

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Record region and clean incomplete loop tail", -1)
end

local function watch_until_recording_stops()
  local state = reaper.GetPlayState()
  local now_recording = (state & 4) == 4

  if now_recording then
    reaper.defer(watch_until_recording_stops)
    return
  end

  cleanup_new_recorded_items()
end

local function start_record_and_watch()
  remember_existing_items_and_armed_tracks()
  reaper.Main_OnCommand(CMD_RECORD, 0) -- Transport: Record
  reaper.defer(watch_until_recording_stops)
end

local current_pos = get_active_position()
local region_name, region_id
region_start, region_end, region_name, region_id = find_region_at_position(current_pos)

if not region_start then
  return
end

-- Time selection op huidige region zetten
reaper.GetSet_LoopTimeRange(true, false, region_start, region_end, false)

local play_state = reaper.GetPlayState()
local is_playing = (play_state & 1) == 1
local is_recording = (play_state & 4) == 4

if is_recording then
  return
end

-- Als transport stil staat: naar begin region en meteen record
if not is_playing then
  reaper.SetEditCurPos(region_start, true, false)
  start_record_and_watch()
  return
end

-- Als hij speelt: wacht tot vlak voor einde region.
-- Met loop points linked to time selection start recording dan bij de volgende loop/begin region.
local function wait_for_region_start()
  local state = reaper.GetPlayState()
  local still_playing = (state & 1) == 1
  local now_recording = (state & 4) == 4

  if now_recording then
    return
  end

  if not still_playing then
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
