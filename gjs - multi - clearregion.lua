-- gjs - Delete all items and FX automation inside selected region
-- target project via GJS_MULTI / ActiveTrack
-- Region is determined by current time selection in target project

local TOLERANCE = 0.000001

local active_track =
  tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))

if not active_track then return end

local proj = reaper.EnumProjects(active_track)
if not proj then return end

local function almost_equal(a, b)
  return math.abs(a - b) <= TOLERANCE
end

local function get_all_regions(proj)
  local regions = {}

  local _, num_markers, num_regions =
    reaper.CountProjectMarkers(proj)

  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, id =
      reaper.EnumProjectMarkers2(proj, i)

    if ok and isrgn then
      table.insert(regions, {
        id = id,
        start_pos = pos,
        end_pos = rgnend,
        name = name or ""
      })
    end
  end

  return regions
end

local function find_region_by_time_selection(
  ts_start,
  ts_end,
  regions
)
  for _, r in ipairs(regions) do
    if almost_equal(r.start_pos, ts_start)
    and almost_equal(r.end_pos, ts_end) then
      return r
    end
  end

  return nil
end

local function delete_media_items_in_region(
  proj,
  region_start,
  region_end
)
  local deleted = false
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)

    local item_pos =
      reaper.GetMediaItemInfo_Value(
        item,
        "D_POSITION"
      )

    local item_len =
      reaper.GetMediaItemInfo_Value(
        item,
        "D_LENGTH"
      )

    local item_end = item_pos + item_len

    local overlaps_region =
      item_end > region_start + TOLERANCE and
      item_pos < region_end - TOLERANCE

    if overlaps_region then
      local track = reaper.GetMediaItem_Track(item)

      reaper.DeleteTrackMediaItem(
        track,
        item
      )

      deleted = true
    end
  end

  return deleted
end

local function delete_automation_from_envelope(
  envelope,
  region_start,
  region_end
)
  local deleted = false

  -- Verwijder losse envelope-punten binnen de region.
  local point_count_before =
    reaper.CountEnvelopePointsEx(
      envelope,
      -1
    )

  reaper.DeleteEnvelopePointRangeEx(
    envelope,
    -1,
    region_start - TOLERANCE,
    region_end + TOLERANCE
  )

  local point_count_after =
    reaper.CountEnvelopePointsEx(
      envelope,
      -1
    )

  if point_count_after < point_count_before then
    deleted = true
  end

  -- Verwijder automation items die de region overlappen.
  local ai_count =
    reaper.CountAutomationItems(envelope)

  for ai = ai_count - 1, 0, -1 do
    local ai_pos =
      reaper.GetSetAutomationItemInfo(
        envelope,
        ai,
        "D_POSITION",
        0,
        false
      )

    local ai_len =
      reaper.GetSetAutomationItemInfo(
        envelope,
        ai,
        "D_LENGTH",
        0,
        false
      )

    local ai_end = ai_pos + ai_len

    local overlaps_region =
      ai_end > region_start + TOLERANCE and
      ai_pos < region_end - TOLERANCE

    if overlaps_region then
      reaper.DeleteAutomationItem(
        envelope,
        ai
      )

      deleted = true
    end
  end

  reaper.Envelope_SortPointsEx(
    envelope,
    -1
  )

  return deleted
end

local function delete_track_automation_in_region(
  track,
  region_start,
  region_end
)
  local deleted = false

  local envelope_count =
    reaper.CountTrackEnvelopes(track)

  for i = 0, envelope_count - 1 do
    local envelope =
      reaper.GetTrackEnvelope(
        track,
        i
      )

    if envelope then
      if delete_automation_from_envelope(
        envelope,
        region_start,
        region_end
      ) then
        deleted = true
      end
    end
  end

  return deleted
end

local function delete_all_automation_in_region(
  proj,
  region_start,
  region_end
)
  local deleted = false

  -- Normale tracks.
  local track_count = reaper.CountTracks(proj)

  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, i)

    if delete_track_automation_in_region(
      track,
      region_start,
      region_end
    ) then
      deleted = true
    end
  end

  -- Mastertrack.
  local master_track =
    reaper.GetMasterTrack(proj)

  if master_track then
    if delete_track_automation_in_region(
      master_track,
      region_start,
      region_end
    ) then
      deleted = true
    end
  end

  return deleted
end

local ts_start, ts_end =
  reaper.GetSet_LoopTimeRange2(
    proj,
    false,
    false,
    0,
    0,
    false
  )

local regions = get_all_regions(proj)

local region =
  find_region_by_time_selection(
    ts_start,
    ts_end,
    regions
  )

if not region then
  reaper.ShowMessageBox(
    "Selecteer eerst een region via time selection / dubbelklik op region.",
    "Geen geselecteerde region",
    0
  )

  return
end

reaper.Undo_BeginBlock2(proj)
reaper.PreventUIRefresh(1)

local items_deleted =
  delete_media_items_in_region(
    proj,
    region.start_pos,
    region.end_pos
  )

local automation_deleted =
  delete_all_automation_in_region(
    proj,
    region.start_pos,
    region.end_pos
  )

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

local undo_text

if items_deleted or automation_deleted then
  undo_text =
    "gjs - Clear items and FX automation inside selected region"
else
  undo_text =
    "gjs - Clear selected region - nothing found"
end

reaper.Undo_EndBlock2(
  proj,
  undo_text,
  -1
)
